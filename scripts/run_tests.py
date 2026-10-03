#!/usr/bin/env python3
"""Run every test and print a pass/fail summary.

    python3 scripts/run_tests.py            # all tests
    python3 scripts/run_tests.py -k legacy  # only tests whose name contains "legacy"

The process exits non-zero if any test fails.
"""
import argparse
import pathlib
import subprocess
import sys
import traceback

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
RTL_FILELIST = ROOT / "rtl" / "files.f"
TB = ROOT / "tb" / "pipe_tb.v"


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


def build_sim(defines=()):
    """Compile the core + testbench with Icarus; one binary per define set."""
    key = tuple(sorted(defines))
    if key not in _sim_cache:
        name = "sim" + "".join("_" + d.lower() for d in key) + ".vvp"
        out = BUILD / name
        BUILD.mkdir(exist_ok=True)
        sh(["iverilog", "-g2005", "-s", "pipe_tb", "-o", str(out)]
           + [f"-D{d}" for d in key]
           + ["-c", str(RTL_FILELIST), str(TB)])
        _sim_cache[key] = out
    return _sim_cache[key]


def run_sim(vvp, plusargs):
    """Run a compiled simulation; return stdout. Fails unless it ends with RESULT: DONE."""
    out = sh(["vvp", "-n", str(vvp)] + [f"+{p}" for p in plusargs])
    if "RESULT: DONE" not in out:
        raise TestFailure("simulation did not finish normally:\n" + out)
    return out


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
    vvp = build_sim(defines=["LEGACY_AES"])
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
