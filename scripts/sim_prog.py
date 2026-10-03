#!/usr/bin/env python3
"""Build and simulate one program on the core (used by make sim / make vcd).

    python3 scripts/sim_prog.py [--vcd-zkne FILE] [--vcd FILE] [--max-cycles N] PROG

PROG is a .S file (assembled with sw/test.h, sw/link.ld) or an ELF linked
at 0x80000000 that ends with a store to `tohost`. Prints the result line
and the non-zero registers.
"""
import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import run_tests as rt  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prog")
    ap.add_argument("--vcd-zkne", help="dump only the Zkne unit's signals to this VCD")
    ap.add_argument("--vcd", help="dump all signals to this VCD")
    ap.add_argument("--max-cycles", type=int, default=100000)
    args = ap.parse_args()

    prog = pathlib.Path(args.prog).resolve()
    elf = rt.assemble(prog) if prog.suffix in (".S", ".s") else prog
    img = rt.make_image(elf)
    regs_file = elf.with_suffix(".regs")
    plusargs = [f"IMEM={img}", f"DMEM={img}", f"OUT={regs_file}",
                f"MAX_CYCLES={args.max_cycles}",
                f"TOHOST={rt.symbols(elf, 'tohost')['tohost']:x}"]
    for opt, name in ((args.vcd_zkne, "VCD_ZKNE"), (args.vcd, "VCD")):
        if opt:
            pathlib.Path(opt).parent.mkdir(parents=True, exist_ok=True)
            plusargs.append(f"{name}={pathlib.Path(opt).resolve()}")
    try:
        out = rt.sh(["vvp", "-n", str(rt.build_sim())] + [f"+{p}" for p in plusargs])
    except rt.TestFailure as e:
        sys.exit(str(e))
    print("".join(l + "\n" for l in out.splitlines() if not l.startswith("VCD info")), end="")
    vals = regs_file.read_text().split()
    for i, v in enumerate(vals[:32]):
        if int(v, 16):
            print(f"  x{i:<2} = 0x{v}")
    if args.vcd_zkne:
        print(f"Zkne-unit VCD: {args.vcd_zkne}")
    if "RESULT: DONE" not in out:
        sys.exit(1)


if __name__ == "__main__":
    main()
