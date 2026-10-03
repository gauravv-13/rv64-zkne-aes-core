#!/usr/bin/env python3
"""Run every test and print a pass/fail summary.

    python3 scripts/run_tests.py            # all tests
    python3 scripts/run_tests.py -k legacy  # only tests whose name contains "legacy"

The process exits non-zero if any test fails.
"""
import argparse
import json
import os
import pathlib
import random
import re
import subprocess
import sys
import traceback

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import zkne_golden as golden  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
RTL_FILELIST = ROOT / "rtl" / "files.f"
TB = ROOT / "tb" / "pipe_tb.v"
SW = ROOT / "sw"
CROSS = "riscv64-unknown-elf-"
MARCH = "rv64i_zkne"
SPIKE_ISA = "rv64i_zkne"


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


def assemble(src, defines=None, tag=""):
    """Assemble + link a test program; returns the ELF path.

    defines: {name: value} passed as -D to the C preprocessor (for .S
    files); tag: suffix for the output name when building variants."""
    src = pathlib.Path(src)
    out = BUILD / "prog" / (src.stem + tag + ".elf")
    out.parent.mkdir(parents=True, exist_ok=True)
    sh([CROSS + "gcc", f"-march={MARCH}", "-mabi=lp64", "-nostdlib", "-nostartfiles",
        "-Wl,--no-warn-rwx-segments", f"-I{SW}", "-T", str(SW / "link.ld")]
       + [f"-D{k}={v}" for k, v in (defines or {}).items()]
       + [str(src), "-o", str(out)])
    return out


MEM_BASE = 0x80000000   # address of byte 0 of both memories (sw/link.ld)
MEM_BYTES = 65536


def make_image(elf):
    """ELF -> $readmemh image: objcopy -O verilog, one byte per entry, with
    @offsets relative to MEM_BASE. Bytes stay in ELF (little-endian) order;
    the same image is loaded into instruction_mem and data_mem."""
    hexf = elf.with_suffix(".hex")
    sh([CROSS + "objcopy", "-O", "verilog", f"--change-addresses=-{MEM_BASE:#x}",
        str(elf), str(hexf)])
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


def parse_expect_mem(src):
    """'// EXPECT_MEM: 0x80008000 = ef cd ab ...' lines -> {address: [bytes]}."""
    exp = {}
    for m in re.finditer(r"EXPECT_MEM:\s*(0x[0-9a-fA-F_]+)\s*=\s*((?:[0-9a-fA-F]{2}\s*)+)",
                         pathlib.Path(src).read_text()):
        exp[int(m.group(1).replace("_", ""), 16)] = [int(b, 16) for b in m.group(2).split()]
    return exp


def symbols(elf, prefix):
    """{name: address} for ELF symbols starting with prefix."""
    syms = {}
    for line in sh([CROSS + "nm", str(elf)]).splitlines():
        addr, _, name = line.split()
        if name.startswith(prefix):
            syms[name] = int(addr, 16)
    return syms


def illegal_reports(stdout):
    """PCs from the testbench's 'ILLEGAL INSTRUCTION 0x... at pc 0x...' lines."""
    return [int(pc, 16) for pc in
            re.findall(r"ILLEGAL INSTRUCTION 0x[0-9a-f]+ at pc 0x([0-9a-f]+)", stdout)]


def run_program(src, max_cycles=2000, defines=(), dump_dmem=False, extra=(), expect_done=True,
                asm_defines=None, tag=""):
    """Assemble, simulate and return (registers[32], cycles, stdout, dmem bytes or None).

    extra: additional plusargs. expect_done=False returns even if the run did
    not end with RESULT: DONE (for tests that check a failing run).
    asm_defines/tag: see assemble()."""
    elf = assemble(src, asm_defines, tag)
    img = make_image(elf)
    regs_file = elf.with_suffix(".regs")
    regs_file.unlink(missing_ok=True)
    tohost = symbols(elf, "tohost")["tohost"]
    plusargs = [f"IMEM={img}", f"DMEM={img}", f"OUT={regs_file}",
                f"MAX_CYCLES={max_cycles}", f"TOHOST={tohost:x}"]
    dmem_file = elf.with_suffix(".dmem")
    if dump_dmem:
        plusargs.append(f"DUMP_DMEM={dmem_file}")
    plusargs += list(extra)
    if expect_done:
        out = run_sim(build_sim(defines), plusargs)
    else:
        out = sh(["vvp", "-n", str(build_sim(defines))] + [f"+{p}" for p in plusargs])
    vals = regs_file.read_text().split()
    dmem = None
    if dump_dmem:
        # $writememh output: one byte per line plus "// 0x<addr>" comment lines.
        dmem = [int(line, 16) for line in dmem_file.read_text().splitlines()
                if line.strip() and not line.lstrip().startswith("//")]
        if len(dmem) != MEM_BYTES:
            raise TestFailure(f"data memory dump has {len(dmem)} bytes, expected {MEM_BYTES}")
    return [int(v, 16) for v in vals[:32]], int(vals[32]), out, dmem


def check_expect(src, **kw):
    exp_mem = parse_expect_mem(src)
    regs, cycles, _, dmem = run_program(src, dump_dmem=bool(exp_mem), **kw)
    bad = [f"  x{r}: got 0x{regs[r]:016x} expected 0x{v:016x}"
           for r, v in sorted(parse_expect(src).items()) if regs[r] != v]
    for addr, want in sorted(exp_mem.items()):
        off = addr - MEM_BASE
        got = dmem[off:off + len(want)]
        if got != want:
            bad.append(f"  mem[{addr:#x}..]: got {' '.join(f'{b:02x}' for b in got)}"
                       f" expected {' '.join(f'{b:02x}' for b in want)}")
    if bad:
        raise TestFailure(f"{src}: mismatch\n" + "\n".join(bad))
    n_mem = sum(len(v) for v in exp_mem.values())
    return (f"{len(parse_expect(src))} regs" + (f" + {n_mem} mem bytes" if n_mem else "")
            + f" ok, cycles={cycles}")


# ---------------------------------------------------------------------------
# Lockstep with Spike
# ---------------------------------------------------------------------------
SPIKE_LINE = re.compile(r"core\s+\d+:\s+\d+\s+0x([0-9a-f]+)\s+\(0x[0-9a-f]+\)(.*)")


def spike_commits(elf, isa=SPIKE_ISA, timeout=60):
    """Run Spike with --log-commits; return (reg_writes, stores) of the program
    (pc >= MEM_BASE, i.e. after the boot ROM). reg_writes: [(rd, value)],
    rd != 0; stores: [(addr, data)]. Spike's exit status is returned too."""
    cmd = ["spike", f"--isa={isa}", f"-m{MEM_BASE:#x}:{MEM_BYTES:#x}",
           "-l", "--log-commits", str(elf)]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise TestFailure(f"Spike did not exit within {timeout}s (a trap with no handler?): "
                          + " ".join(cmd))
    regs, stores = [], []
    for line in (p.stdout + p.stderr).splitlines():
        m = SPIKE_LINE.match(line)
        if not m or int(m.group(1), 16) < MEM_BASE:
            continue
        tok = m.group(2).split()
        i = 0
        while i < len(tok):
            t = tok[i]
            if re.fullmatch(r"x\d+", t) and i + 1 < len(tok):
                rd, val = int(t[1:]), int(tok[i + 1], 16)
                if rd != 0:
                    regs.append((rd, val))
                i += 2
            elif t == "mem" and i + 1 < len(tok):
                addr = int(tok[i + 1], 16)
                if i + 2 < len(tok) and tok[i + 2].startswith("0x"):   # store: addr data
                    stores.append((addr, int(tok[i + 2], 16)))
                    i += 3
                else:                                                  # load: addr only
                    i += 2
            else:
                i += 1
    return regs, stores, p.returncode


def core_commits(path):
    regs, stores = [], []
    for line in pathlib.Path(path).read_text().splitlines():
        f = line.split()
        if f[0] == "mem":
            stores.append((int(f[1], 16), int(f[2], 16)))
        else:
            regs.append((int(f[0][1:]), int(f[1], 16)))
    return regs, stores


def first_diff(a, b, fmt):
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return f"  #{i}: core {fmt(x)}   spike {fmt(y)}"
    return f"  lengths differ: core {len(a)}, spike {len(b)}"


def lockstep(src, max_cycles=20000, expect_done=True, asm_defines=None, tag="", isa=SPIKE_ISA):
    """Same ELF on the core and on Spike; compare every register write (order
    and value) and every store. Returns (core reg writes, cycles, detail)."""
    src = pathlib.Path(src)
    log = BUILD / "prog" / (src.stem + tag + ".commits")
    _, cycles, out, _ = run_program(src, max_cycles=max_cycles, expect_done=expect_done,
                                    extra=[f"COMMITLOG={log}"], asm_defines=asm_defines, tag=tag)
    c_regs, c_st = core_commits(log)
    s_regs, s_st, _ = spike_commits(BUILD / "prog" / (src.stem + tag + ".elf"), isa=isa)
    errs = []
    if c_regs != s_regs:
        errs.append("register writes differ:\n" +
                    first_diff(c_regs, s_regs, lambda w: f"x{w[0]} = {w[1]:#018x}"))
    if c_st != s_st:
        errs.append("stores differ:\n" +
                    first_diff(c_st, s_st, lambda w: f"[{w[0]:#x}] = {w[1]:#018x}"))
    if errs:
        raise TestFailure(f"{src.name}: lockstep mismatch vs Spike\n" + "\n".join(errs))
    if not c_regs:
        raise TestFailure(f"{src.name}: no register writes logged")
    return c_regs, cycles, (f"{len(c_regs)} reg writes + {len(c_st)} stores identical "
                            f"to Spike, cycles={cycles}")


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


@test("isa C: little-endian ld/sd, byte order in memory, data image load")
def test_endian():
    return check_expect(ROOT / "tests/isa/endian.S")


@test("isa D: beq/bne decode, taken/not-taken, squash, forwarding")
def test_branch():
    return check_expect(ROOT / "tests/isa/branch.S")


def check_illegal(src):
    """Run with +ALLOW_ILLEGAL: exactly the ill_* labelled PCs must be reported
    (once each), and the EXPECT registers must hold."""
    src = pathlib.Path(src)
    detail = check_expect(src, extra=["ALLOW_ILLEGAL"])
    _, _, out, _ = run_program(src, extra=["ALLOW_ILLEGAL"])
    want = symbols(BUILD / "prog" / (src.stem + ".elf"), "ill_")
    got = illegal_reports(out)
    by_pc = {a: n for n, a in want.items()}
    missing = sorted(n for n, a in want.items() if got.count(a) == 0)
    dup = sorted(by_pc.get(a, hex(a)) for a in set(got) if got.count(a) > 1)
    extra = sorted(hex(a) for a in set(got) if a not in by_pc)
    if missing or dup or extra:
        raise TestFailure(f"not reported: {missing}\nreported more than once: {dup}\n"
                          f"reported but legal: {extra}")
    return f"{len(want)} illegal encodings reported; {detail}"


@test("isa D: every undecoded encoding raises illegal_instr (exactly once)")
def test_illegal_encodings():
    return check_illegal(ROOT / "tests/isa/illegal_encodings.S")


@test("isa E: illegal instruction is a NOP (no reg/mem write, no branch)")
def test_illegal_nop():
    return check_expect(ROOT / "tests/isa/illegal_nop.S", extra=["ALLOW_ILLEGAL"])


@test("isa E: by default the first illegal instruction fails the run")
def test_illegal_fails_run():
    src = ROOT / "tests/isa/illegal_nop.S"
    regs, _, out, _ = run_program(src, expect_done=False)
    first_ill = symbols(BUILD / "prog" / "illegal_nop.elf", "first_illegal")["first_illegal"]
    if "RESULT: ILLEGAL" not in out or "RESULT: DONE" in out:
        raise TestFailure("run did not end with RESULT: ILLEGAL:\n" + out)
    if illegal_reports(out) != [first_ill]:
        raise TestFailure(f"expected one report at {first_ill:#x}:\n" + out)
    if "ERROR: illegal instruction" not in out:
        raise TestFailure("no clear error message:\n" + out)
    return f"stopped at pc {first_ill:#x} with RESULT: ILLEGAL"


@test("isa F: tohost exit; fail code; nothing after TEST_END commits")
def test_tohost():
    src = ROOT / "tests/isa/tohost_fail.S"
    regs, _, out, _ = run_program(src, expect_done=False)
    if "RESULT: FAIL" not in out or "(code 5)" not in out:
        raise TestFailure("expected RESULT: FAIL with code 5:\n" + out)
    bad = [f"  x{r}: got 0x{regs[r]:016x} expected 0x{v:016x}"
           for r, v in sorted(parse_expect(src).items()) if regs[r] != v]
    if bad:
        raise TestFailure("register mismatch\n" + "\n".join(bad))
    return "TEST_FAIL(5) -> RESULT: FAIL (code 5); " + check_expect(ROOT / "tests/isa/tohost_pass.S")


@test("zkne: directed FIPS-197 C.1 values (es, esm, ks1i incl. rnum=0xA, ks2)")
def test_zkne_directed():
    return check_expect(ROOT / "tests/zkne/zkne_directed.S")


@test("zkne: aes64ks1i rnum 0xB..0xF raises illegal_instr, writes nothing")
def test_ks1i_reserved():
    return check_illegal(ROOT / "tests/zkne/ks1i_reserved.S")


@test("golden model self-test (FIPS-197 S-box, C.1 two ways, A.1 key schedule)")
def test_golden_selftest():
    return golden.selftest()


# zkne_unit op encoding (its port definition)
UNIT_OPS = {"aes64es": 0, "aes64esm": 1, "aes64ks1i": 2, "aes64ks2": 3}
N_RANDOM = int(os.environ.get("ZKNE_N", "10000"))
SEED = int(os.environ.get("ZKNE_SEED", "20261003"))


def edge_values():
    v = [0, golden.MASK64, 0x5555555555555555, 0xAAAAAAAAAAAAAAAA,
         0x0123456789ABCDEF, 0xFEDCBA9876543210, 0x8000000000000000, 1]
    v += [1 << i for i in range(64)]                       # walking one
    v += [golden.MASK64 ^ (1 << i) for i in range(64)]     # walking zero
    v += [0xFF << (8 * i) for i in range(8)]               # one byte set
    return v


@test(f"zkne_unit: edge cases + {N_RANDOM} random operands per instruction vs golden model")
def test_zkne_unit_random():
    rng = random.Random(SEED)
    vecs = []                                   # (valid, name, rs1, rs2, rnum)
    edges = edge_values()
    for name in UNIT_OPS:
        for a in edges:
            for b in (edges[0], edges[1], edges[4], a):
                for rnum in (range(11) if name == "aes64ks1i" else [0]):
                    vecs.append((1, name, a, b, rnum))
        for _ in range(N_RANDOM):
            vecs.append((1, name, rng.getrandbits(64), rng.getrandbits(64),
                         rng.randrange(11) if name == "aes64ks1i" else rng.randrange(16)))
    for _ in range(200):                        # operand isolation: valid=0 -> 0
        vecs.append((0, rng.choice(list(UNIT_OPS)), rng.getrandbits(64),
                     rng.getrandbits(64), rng.randrange(11)))

    d = BUILD / "zkne_unit"
    d.mkdir(parents=True, exist_ok=True)
    vec_file, out_file, vvp = d / "vectors.txt", d / "results.txt", d / "tb.vvp"
    vec_file.write_text("".join(f"{v:x} {UNIT_OPS[n]:x} {a:016x} {b:016x} {r:x}\n"
                                for v, n, a, b, r in vecs))
    sh(["iverilog", "-g2005", "-s", "zkne_unit_tb", "-o", str(vvp),
        str(ROOT / "rtl/zkne_unit.v"), str(ROOT / "rtl/aes_sbox.v"),
        str(ROOT / "tb/zkne_unit_tb.v")])
    out = sh(["vvp", "-n", str(vvp), f"+VEC={vec_file}", f"+OUT={out_file}"])
    got = [int(x, 16) for x in out_file.read_text().split()]
    if len(got) != len(vecs):
        raise TestFailure(f"{len(got)} results for {len(vecs)} vectors\n{out}")
    fails, per_op = [], {}
    for (v, n, a, b, r), g in zip(vecs, got):
        exp = golden.OPS[n](a, b, r) if v else 0
        if v:
            per_op[n] = per_op.get(n, 0) + 1
        if g != exp:
            fails.append(f"  valid={v} {n} rs1={a:016x} rs2={b:016x} rnum={r:x}: "
                         f"rtl={g:016x} golden={exp:016x}")
    if fails:
        raise TestFailure(f"{len(fails)} mismatches (seed {SEED}), first 10:\n"
                          + "\n".join(fails[:10]))
    return (", ".join(f"{n} {c}" for n, c in per_op.items())
            + f", valid=0 200; seed {SEED}")


@test("zkne: FIPS-197 C.1 AES-128 in assembly (ks1i/ks2 key expansion) + lockstep")
def test_fips197_c1():
    src = ROOT / "tests/zkne/fips197_c1.S"
    return check_expect(src) + "; " + lockstep(src)[2]


@test("zkne: Zkt - FIPS program cycle count independent of key/plaintext (4 data sets)")
def test_zkt_constant_time():
    src = ROOT / "tests/zkne/fips197_c1.S"
    rng = random.Random(SEED)
    cycles = set()
    for i in range(4):
        key = bytes(rng.getrandbits(8) for _ in range(16)) if i else bytes(range(16))
        pt = (bytes(rng.getrandbits(8) for _ in range(16)) if i
              else bytes.fromhex("00112233445566778899aabbccddeeff"))
        fmt = lambda b: ",".join(f"0x{x:02x}" for x in b)
        regs, cyc, _, _ = run_program(src, asm_defines={"KEY_BYTES": fmt(key), "PT_BYTES": fmt(pt)},
                                      tag=f"_zkt{i}")
        ct = bytes(golden.aes128_encrypt(key, pt))
        got = golden.u64_to_bytes(regs[2]) + golden.u64_to_bytes(regs[3])
        if bytes(got) != ct:
            raise TestFailure(f"data set {i}: ciphertext {bytes(got).hex()} != golden {ct.hex()}")
        cycles.add(cyc)
    if len(cycles) != 1:
        raise TestFailure(f"cycle counts differ between data sets: {sorted(cycles)}")
    return f"4 key/plaintext sets, all {cycles.pop()} cycles, ciphertexts match golden AES-128"


@test("pipeline: forwarding into both Zkne operands (golden EXPECT + lockstep)")
def test_pipe_fwd():
    src = ROOT / "tests/pipeline/fwd_operands.S"
    return check_expect(src) + "; " + lockstep(src)[2]


@test("pipeline: load-use into aes64esm/es/ks1i/ks2 (golden EXPECT + lockstep)")
def test_pipe_load_use():
    src = ROOT / "tests/pipeline/load_use.S"
    return check_expect(src) + "; " + lockstep(src)[2]


@test("pipeline: mispredicted branches squash Zkne instructions (golden EXPECT + lockstep)")
def test_pipe_squash():
    src = ROOT / "tests/pipeline/squash.S"
    return check_expect(src) + "; " + lockstep(src)[2]


N_RANDOM_PROG = int(os.environ.get("ZKNE_PROG_N", "3000"))


@test(f"random program: {N_RANDOM_PROG} random Zkne/xor/ld instructions, core vs golden vs Spike")
def test_random_program():
    d = BUILD / "random"
    d.mkdir(parents=True, exist_ok=True)
    src = d / "random_prog.S"
    sh([sys.executable, str(ROOT / "scripts/gen_random_prog.py"), str(src), str(SEED),
        str(N_RANDOM_PROG)])
    exp = json.loads(src.with_suffix(".expect.json").read_text())
    c_regs, cycles, detail = lockstep(src, max_cycles=20 * N_RANDOM_PROG)
    # core log = la x1 (2 writes) + body + TEST_END (la x30: 2, addi x29: 1)
    body = [list(w) for w in c_regs[2:-3]]
    if body != exp["writes"]:
        raise TestFailure("core register writes differ from the golden model:\n"
                          + first_diff(body, exp["writes"], lambda w: f"x{w[0]} = {w[1]:#018x}"))
    counts = ", ".join(f"{k} {v}" for k, v in sorted(exp["counts"].items()))
    return f"{counts}; {len(body)} writes match golden; {detail}"


@test("demo: sw/aes128_ctr.S, AES-128 CTR x4 vs NIST SP 800-38A F.5.1 + lockstep; cycles/block")
def test_ctr_demo():
    src = ROOT / "sw/aes128_ctr.S"
    detail = check_expect(src)
    _, cycles, out, _ = run_program(src, extra=["TRACE_STORES"])
    ct = symbols(BUILD / "prog" / "aes128_ctr.elf", "ciphertext")["ciphertext"]
    # cycle at which the second (last) store of each ciphertext block commits
    done = [int(c) for c, a in re.findall(r"STORE cycle=(\d+) addr=([0-9a-f]+)", out)
            if int(a, 16) in [ct + 16 * i + 8 for i in range(4)]]
    if len(done) != 4:
        raise TestFailure(f"expected 4 ciphertext block stores, saw {len(done)}:\n{out}")
    per_block = [b - a for a, b in zip(done, done[1:])]
    if len(set(per_block)) != 1:
        raise TestFailure(f"blocks took different numbers of cycles: {per_block}")
    return (f"{per_block[0]} cycles/block (steady state), first block done at cycle "
            f"{done[0]} (incl. key expansion), total {cycles} cycles for 4 blocks; "
            f"{detail}; " + lockstep(src)[2])


def parse_vcd(path):
    """Minimal VCD reader: returns (scopes, signal names, list of (time, {name: value}))
    with the full value set at every timestamp. Names are '<scope path>.<signal>'."""
    ids, scopes, stack = {}, set(), []
    cur, frames, t = {}, [], None
    in_defs = True
    for line in pathlib.Path(path).read_text().splitlines():
        tok = line.split()
        if not tok:
            continue
        if in_defs:
            if tok[0] == "$scope":
                stack.append(tok[2])
                scopes.add(".".join(stack))
            elif tok[0] == "$upscope":
                stack.pop()
            elif tok[0] == "$var":
                ids.setdefault(tok[3], []).append(".".join(stack + [tok[4]]))
            elif tok[0] == "$enddefinitions":
                in_defs = False
            continue
        if tok[0].startswith("#"):
            if t is not None:
                frames.append((t, dict(cur)))
            t = int(tok[0][1:])
        elif tok[0][0] in "bB":
            for n in ids.get(tok[1], []):
                cur[n] = tok[0][1:]
        elif tok[0][0] in "01xzXZ" and len(tok) == 1:
            for n in ids.get(tok[0][1:], []):
                cur[n] = tok[0][0]
    if t is not None:
        frames.append((t, dict(cur)))
    return scopes, {n for v in ids.values() for n in v}, frames


@test("vcd: make vcd dumps only the Zkne unit; valid=0 -> S-box inputs, sr, result all 0")
def test_vcd_zkne():
    vcd = BUILD / "vcd" / "aes128_ctr_zkne.vcd"
    vcd.unlink(missing_ok=True)
    sh(["make", "-s", "vcd", "PROG=sw/aes128_ctr.S"])
    scopes, names, frames = parse_vcd(vcd)
    unit = "pipe_tb.uut.ZKNE_UNIT"
    outside = sorted(n for n in names if not n.startswith(unit + "."))
    if outside:
        raise TestFailure(f"signals outside {unit} in the VCD: {outside[:5]}")
    for net in ("valid", "sb_in", "sb_out", "sr", "mc", "result", "sbox[0].u_sbox.in"):
        if f"{unit}.{net}" not in names:
            raise TestFailure(f"{unit}.{net} missing from the VCD")
    zero = lambda v: v is not None and set(v) <= {"0"}
    idle = [f for f in frames if f[1].get(unit + ".valid") == "0"]
    busy = [f for f in frames if f[1].get(unit + ".valid") == "1"]
    for tm, vals in idle:
        for net in ("sb_in", "sr", "result", "a", "b"):
            if not zero(vals.get(f"{unit}.{net}")):
                raise TestFailure(f"t={tm}: valid=0 but {net} = {vals.get(unit + '.' + net)}")
    if not idle or not busy:
        raise TestFailure("expected both valid=0 and valid=1 periods")
    return (f"{len(names)} signals, all inside {unit}; {len(idle)} valid=0 timestamps with "
            f"isolated (all-zero) operands, {len(busy)} valid=1")


# Every test program that Spike can run (no illegal instructions, no
# custom-0). endian.S does misaligned ld/sd on purpose: Spike needs Zicclsm
# for that (the core supports misaligned accesses within memory).
LOCKSTEP_PROGRAMS = [
    ("tests/isa/xor.S", {}),
    ("tests/isa/lui_auipc.S", {}),
    ("tests/isa/endian.S", {"isa": SPIKE_ISA + "_zicclsm"}),
    ("tests/isa/branch.S", {}),
    ("tests/isa/tohost_pass.S", {}),
    ("tests/isa/tohost_fail.S", {"expect_done": False}),
    ("tests/zkne/zkne_directed.S", {}),
]


def _make_lockstep_test(path, kw):
    @test(f"lockstep vs Spike: {path}")
    def _t():
        return lockstep(ROOT / path, **kw)[2]


for _path, _kw in LOCKSTEP_PROGRAMS:
    _make_lockstep_test(_path, _kw)


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
