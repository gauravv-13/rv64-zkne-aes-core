#!/usr/bin/env python3
"""Run every test and print a pass/fail summary.

    python3 scripts/run_tests.py            # all tests
    python3 scripts/run_tests.py -k legacy  # only tests whose name contains "legacy"

The process exits non-zero if any test fails.
"""
import argparse
import pathlib
import re
import subprocess
import sys
import traceback

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
RTL_FILELIST = ROOT / "rtl" / "files.f"
TB = ROOT / "tb" / "pipe_tb.v"
SW = ROOT / "sw"
CROSS = "riscv64-unknown-elf-"
MARCH = "rv64i_zkne"


class TestFailure(Exception):
    pass


def sh(cmd, cwd=ROOT):
    """Run a command; raise TestFailure (with its output) if it fails."""
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if p.returncode != 0:
        raise TestFailure(f"command failed ({p.returncode}): {' '.join(map(str, cmd))}\n"
                          f"{p.stdout}{p.stderr}")
    return p.stdout


_sim_cache = {}


def build_sim(defines=(), params=None):
    """Compile the core + testbench with Icarus; one binary per define/param set.

    params: top-level testbench parameters, e.g. {"RESET_PC": "0"}.
    """
    params = params or {}
    key = (tuple(sorted(defines)), tuple(sorted(params.items())))
    if key not in _sim_cache:
        name = ("sim" + "".join("_" + d.lower() for d in key[0])
                + "".join(f"_{k.lower()}{v}" for k, v in key[1]) + ".vvp")
        out = BUILD / name
        BUILD.mkdir(exist_ok=True)
        sh(["iverilog", "-g2005", "-s", "pipe_tb", "-o", str(out)]
           + [f"-D{d}" for d in key[0]]
           + [f"-Ppipe_tb.{k}={v}" for k, v in key[1]]
           + ["-c", str(RTL_FILELIST), str(TB)])
        _sim_cache[key] = out
    return _sim_cache[key]


def run_sim(vvp, plusargs):
    """Run a compiled simulation; return stdout. Fails unless it ends with RESULT: DONE."""
    out = sh(["vvp", "-n", str(vvp)] + [f"+{p}" for p in plusargs])
    if "RESULT: DONE" not in out:
        raise TestFailure("simulation did not finish normally:\n" + out)
    return out


def assemble(src):
    """Assemble + link a test program; returns the ELF path."""
    src = pathlib.Path(src)
    out = BUILD / "prog" / (src.stem + ".elf")
    out.parent.mkdir(parents=True, exist_ok=True)
    sh([CROSS + "gcc", f"-march={MARCH}", "-mabi=lp64", "-nostdlib", "-nostartfiles",
        "-Wl,--no-warn-rwx-segments", f"-I{SW}", "-T", str(SW / "link.ld"),
        str(src), "-o", str(out)])
    return out


def make_image(elf):
    """ELF -> instruction_mem image (one hex byte per line).

    TEMPORARY: instruction_mem is still big-endian (byte at the lowest
    address = instruction bits [31:24]), so each 32-bit word is written
    most-significant byte first. Removed when the core goes little-endian.
    """
    binf = elf.with_suffix(".bin")
    sh([CROSS + "objcopy", "-O", "binary", str(elf), str(binf)])
    data = binf.read_bytes()
    data += b"\0" * (-len(data) % 4)
    lines = []
    for i in range(0, len(data), 4):
        lines += [f"{b:02x}" for b in reversed(data[i:i + 4])]
    hexf = elf.with_suffix(".hex")
    hexf.write_text("\n".join(lines) + "\n")
    return hexf


def parse_expect(src):
    """'// EXPECT: x5 = 0x...' lines -> {5: value}."""
    exp = {}
    for m in re.finditer(r"EXPECT:\s*x(\d+)\s*=\s*(0x[0-9a-fA-F_]+)",
                         pathlib.Path(src).read_text()):
        exp[int(m.group(1))] = int(m.group(2).replace("_", ""), 16)
    if not exp:
        raise TestFailure(f"{src}: no EXPECT lines")
    return exp


def run_program(src, max_cycles=2000, defines=()):
    """Assemble, simulate and return (registers[32], cycles, stdout)."""
    elf = assemble(src)
    img = make_image(elf)
    regs_file = elf.with_suffix(".regs")
    regs_file.unlink(missing_ok=True)
    out = run_sim(build_sim(defines), [f"IMEM={img}", f"OUT={regs_file}",
                                       f"MAX_CYCLES={max_cycles}", "ZERO_WORD_STOP"])
    vals = regs_file.read_text().split()
    return [int(v, 16) for v in vals[:32]], int(vals[32]), out


def check_expect(src, **kw):
    regs, cycles, _ = run_program(src, **kw)
    bad = [f"  x{r}: got 0x{regs[r]:016x} expected 0x{v:016x}"
           for r, v in sorted(parse_expect(src).items()) if regs[r] != v]
    if bad:
        raise TestFailure(f"{src}: register mismatch\n" + "\n".join(bad))
    return f"{len(parse_expect(src))} regs ok, cycles={cycles}"


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
TESTS = []


def test(name):
    def wrap(fn):
        TESTS.append((name, fn))
        return fn
    return wrap


@test("legacy: original program gives the original 32 registers + 21 cycles")
def test_legacy():
    # The legacy program was written for a reset vector of 0.
    vvp = build_sim(defines=["LEGACY_AES"], params={"RESET_PC": "0"})
    outdir = BUILD / "legacy"
    outdir.mkdir(parents=True, exist_ok=True)
    regs = outdir / "regs.txt"
    regs.unlink(missing_ok=True)
    run_sim(vvp, [f"IMEM={ROOT / 'tests/legacy/program.hex'}",
                  f"OUT={regs}", "MAX_CYCLES=200", "ZERO_WORD_STOP"])
    got = regs.read_text().split()
    exp = (ROOT / "tests/legacy/expected_regs.txt").read_text().split()
    if got != exp:
        diffs = [f"  line {i + 1}: got {g} expected {e}"
                 for i, (g, e) in enumerate(zip(got, exp)) if g != e]
        raise TestFailure("register dump differs from tests/legacy/expected_regs.txt:\n"
                          + "\n".join(diffs or ["  (different length)"]))
    return "32 regs + cycles=%s match" % got[-1]


@test("isa A: xor (forwarding on both operands, x0)")
def test_xor():
    return check_expect(ROOT / "tests/isa/xor.S")


@test("isa B: lui/auipc/la at RESET_PC=0x80000000, low-bit memory decode")
def test_lui_auipc():
    return check_expect(ROOT / "tests/isa/lui_auipc.S")


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-k", default="", help="only run tests whose name contains this")
    args = ap.parse_args()

    selected = [(n, f) for n, f in TESTS if args.k in n]
    results = []
    for name, fn in selected:
        try:
            detail = fn() or ""
            results.append((name, True, detail))
        except TestFailure as e:
            results.append((name, False, str(e)))
        except Exception:
            results.append((name, False, traceback.format_exc()))
        ok, detail = results[-1][1], results[-1][2]
        print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f"  ({detail})" if ok and detail else ""))
        if not ok:
            print("       " + detail.replace("\n", "\n       "))

    passed = sum(ok for _, ok, _ in results)
    print()
    print("=" * 60)
    print(f"SUMMARY: {passed}/{len(results)} passed, {len(results) - passed} failed")
    print("=" * 60)
    sys.exit(0 if results and passed == len(results) else 1)


if __name__ == "__main__":
    main()
