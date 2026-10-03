# RV64 Zkne AES Core

**A small 5-stage pipelined RISC-V (RV64) core in Verilog, with the ratified
Zkne AES encryption instructions. It matches Spike bit for bit and is built
as a clean, easy-to-probe target for power side-channel research.**

![ISA](https://img.shields.io/badge/ISA-RV64%20%2B%20Zkne-blue)
![Spec](https://img.shields.io/badge/Scalar%20Crypto-v1.0.1-blue)
![Tests](https://img.shields.io/badge/make%20test-31%2F31%20passing-brightgreen)
![Spike](https://img.shields.io/badge/Spike%20lockstep-3442%20writes%20identical-brightgreen)
![Lint](https://img.shields.io/badge/verilator%20lint-clean-brightgreen)
![Endian](https://img.shields.io/badge/endianness-little--only-lightgrey)

```text
  FIPS-197 C.1   key 000102...0f   pt 00112233...ff
  ciphertext  -> 69c4e0d86a7b0430d8cdb78070b4c55a   ✔  (90 cycles, incl. key expansion)
  AES-128 CTR -> NIST SP 800-38A F.5.1, 4 blocks     ✔  (54 cycles / block)
```

---

## Contents

- [Why this exists](#why-this-exists)
- [Highlights](#highlights)
- [Quick start](#quick-start)
- [The Zkne instructions](#the-zkne-instructions)
- [Architecture](#architecture)
- [Verification](#verification)
- [Side-channel hooks](#side-channel-hooks)
- [Writing your own programs](#writing-your-own-programs)
- [Project layout](#project-layout)
- [Known limits](#known-limits)
- [Project history](#project-history)

---

## Why this exists

The RISC-V Scalar Crypto extension adds instructions that compute AES rounds
directly in the CPU. To study how much power side-channel information those
instructions leak, you need a core that is:

1. **Correct.** It implements the *standard* instructions exactly as the
   spec and Spike define them.
2. **Readable.** The AES datapath is small, in its own module, and has a
   named wire for each step.
3. **Easy to probe.** You can dump just the AES unit's signals for
   toggle-count leakage analysis, and swap in a masked S-box later.

This repository is that core. It is deliberately **not** a full RV64I
processor. It implements only what the AES work needs, and checks it
heavily.

## Highlights

- **Standard Zkne for RV64:** `aes64es`, `aes64esm`, `aes64ks1i`,
  `aes64ks2`, following the Sail code of Scalar Crypto v1.0.1 and Spike's
  `riscv/insns/aes64*.h`.
- **Single cycle, fixed latency, no data-dependent timing (Zkt).** A test
  checks that the AES-128 program takes the same number of cycles for
  every key and plaintext.
- **Clean AES datapath:** `rtl/zkne_unit.v` plus a `case`-statement S-box in
  `rtl/aes_sbox.v`. There are no memories or `initial` blocks in the AES
  logic, so it synthesizes to plain logic and every net can be probed.
- **Operand isolation, switchable:** by default the AES nets stay at zero
  unless an AES instruction is in EX, so ordinary ALU instructions don't add
  toggle noise. `ISOLATE=0` builds an ungated unit, like a crypto unit with
  no isolation, so leakage can be measured both ways.
- **Full forwarding:** both operands, including the back-to-back
  `aes64esm t2,t0,t1 ; aes64esm t3,t1,t0` pattern.
- **Checked against Spike:** every register write and store of 13 programs
  is compared, in order and value, with Spike's commit log.
- **No silent fallbacks:** every encoding the core doesn't fully decode
  raises `illegal_instr`, and the test fails.
- **Little-endian only,** like RISC-V, Spike and GCC. There is no byte
  swapping anywhere.

## Quick start

### 1. Install the tools (macOS, Homebrew)

```bash
brew install icarus-verilog verilator
brew tap riscv-software-src/riscv
brew install riscv-tools        # riscv64-unknown-elf-gcc, binutils, Spike
```

Versions used during development:

| Tool | Version |
|---|---|
| Icarus Verilog | 13.0 |
| Verilator | 5.052 |
| GCC | 16.1.0 |
| binutils | 2.46 |
| Spike | 1.1.1-dev |
| Python | 3.11 |

The Python scripts use only the standard library. File names match their
`include`/filelist spelling exactly, so the build also works on
case-sensitive filesystems (tested on a case-sensitive APFS volume).

### 2. Run everything

```bash
make test
```

```text
[PASS] legacy: original program gives the original 32 registers + 21 cycles
[PASS] isa A: xor (forwarding on both operands, x0)
...
[PASS] zkne: FIPS-197 C.1 AES-128 in assembly (ks1i/ks2 key expansion) + lockstep
[PASS] zkne: Zkt - FIPS program cycle count independent of key/plaintext (4 data sets)
[PASS] random program: 3000 random Zkne/xor/ld instructions, core vs golden vs Spike
[PASS] demo: sw/aes128_ctr.S, AES-128 CTR x4 vs NIST SP 800-38A F.5.1 + lockstep; cycles/block
...
============================================================
SUMMARY: 31/31 passed, 0 failed
============================================================
```

The whole suite takes about 15 seconds.

### 3. Other targets

| Command | What it does |
|---|---|
| `make test` | Every test, with a pass/fail summary. `K=<substring>` runs a subset. |
| `make sim PROG=sw/aes128_ctr.S` | Run one program (`.S` or ELF), print the registers, write a full VCD. |
| `make vcd PROG=sw/aes128_ctr.S` | VCD of **only the Zkne unit**, saved as `build/vcd/<name>_zkne.vcd`. |
| `make vcd PROG=... ISOLATE=0` | Same, with operand isolation off: `build/vcd/<name>_zkne_noiso.vcd`. `ISOLATE=0` also works with `make sim` and `make lint`. |
| `make sim` | Run the original legacy program. |
| `make lint` | `verilator --lint-only -Wall` (clean). |
| `make clean` | Remove `build/`. |

## The Zkne instructions

| Instruction | Encoding | What it computes |
|---|---|---|
| `aes64es rd, rs1, rs2` | `0011001 rs2 rs1 000 rd 0110011` | Final round: SubBytes(ShiftRows(state)), low 64 bits |
| `aes64esm rd, rs1, rs2` | `0011011 rs2 rs1 000 rd 0110011` | Middle round: MixColumns(SubBytes(ShiftRows(state))), low 64 bits |
| `aes64ks1i rd, rs1, rnum` | `00110001 rnum rs1 001 rd 0010011` | Key schedule: `{w,w}`, where `w = SubWord(RotWord(rs1[63:32])) ^ rcon` (no rotation, no rcon when rnum = 0xA) |
| `aes64ks2 rd, rs1, rs2` | `0111111 rs2 rs1 000 rd 0110011` | Key schedule: `{w0^rs2[63:32], w0}`, where `w0 = rs1[63:32] ^ rs2[31:0]` |

- The 128-bit AES state lives in **two registers**. rs1 holds bytes 0..7
  and rs2 holds bytes 8..15, with byte 0 in bits [7:0].
- `aes64es` and `aes64esm` return one 64-bit half. You get the other half
  by swapping the operands.
- AddRoundKey is a plain `xor`.
- rnum 0xB..0xF is reserved and raises `illegal_instr`.
- Decryption (Zknd) is not implemented.

One AES-128 middle round looks like this (from `sw/aes128_zkne.h`):

```asm
aes64esm t0, s0, s1      # new state bytes 0..7
aes64esm t1, s1, s0      # new state bytes 8..15  (operands swapped)
xor      s0, t0, k0      # AddRoundKey
xor      s1, t1, k1
```

And one key-expansion step:

```asm
aes64ks1i t,  hi, rnum   # SubWord(RotWord(w3)) ^ rcon
aes64ks2  lo, t,  lo     # w4, w5
aes64ks2  hi, lo, hi     # w6, w7
```

A 16-byte block stored in memory in FIPS order (byte 0 at the lowest
address) and loaded with two little-endian `ld` instructions is already in
the spec's register layout. No byte reordering is needed anywhere.

## Architecture

```text
            IF              ID                    EX                     MEM           WB
       ┌─────────┐    ┌───────────────┐    ┌────────────────────┐    ┌─────────┐   ┌────────┐
 PC ──►│ instr   │──► │ control.v     │──► │ forwarding muxes   │──► │ data    │──►│ reg    │
       │ memory  │    │  decode +     │    │   │rs1      │rs2   │    │ memory  │   │ write  │
       │ 64 KB   │    │  illegal_instr│    │   ▼         ▼      │    │ 64 KB   │   │        │
       └─────────┘    │ register file │    │ ┌─────┐ ┌────────┐│    └─────────┘   └────────┘
                      │ imm_gen       │    │ │ ALU │ │zkne_   ││
                      └───────────────┘    │ └──┬──┘ │unit    ││
                                           │    │    └───┬────┘│
                                           │    └─ mux ──┘     │
                                           └────────────────────┘
   hazards: EX/MEM + MEM/WB forwarding, 1-cycle load-use stall,
            branches predicted not-taken, resolved in EX (2-cycle penalty)
```

The Zkne unit's datapath is all combinational, one cycle in EX:

```text
 rs1, rs2, rnum ──► operand isolation (zero unless valid) ──► a, b, rn
                                   │
          ┌────────────────────────┼────────────────────────┐
          ▼                        ▼                        ▼
   ShiftRows (sr)          ks1i: RotWord? (ks_rot)    ks2: xor words
          └──────────► 8 × aes_sbox (sb_in → sb_out) ◄──────┘
                              │
                 ┌────────────┼──────────────┐
                 ▼            ▼              ▼
            es: sb_out   esm: MixColumns   ks1i: ^ rcon
                              (mc)
                 └──────────► result ◄───────┘
```

| RTL file | Role |
|---|---|
| `rtl/processor.v` | Top level. Pipeline, forwarding muxes, unit instance `ZKNE_UNIT`. |
| `rtl/zkne_unit.v` | The four Zkne instructions. Ports: `valid, op, rs1, rs2, rnum → result`. |
| `rtl/aes_sbox.v` | AES S-box as a `case` statement, generated from the FIPS-197 math. |
| `rtl/control.v` | Main decoder: Zkne decode and `illegal_instr`. |
| `rtl/ForwardingUnit.v`, `rtl/hazard_detection_unit.v` | Data hazards. |
| `rtl/IF_ID.v` … `rtl/MEM_WB.v` | Pipeline registers. |
| `rtl/alu.v` + `add64/sub64/and64/or64/xor64.v` | Gate-level ALU. |
| `rtl/aes_round64.v` | The original non-standard instruction. Only built with `-DLEGACY_AES`. |

The core decodes exactly these instructions:
- `add sub and or xor addi ld sd beq bne lui auipc`
- the four Zkne instructions

Everything else is reported as illegal.

## Verification

```text
                       ┌──────────────────────┐
   tests/*.S, sw/*.S ─►│ riscv64-elf-gcc      │──► ELF ──┬──► Spike --log-commits ──┐
                       └──────────────────────┘          │                          ├─► compare every
                                                         └──► Icarus RTL sim ───────┘   register write
   scripts/zkne_golden.py (from FIPS-197 + Sail) ──► expected values ─────────────────►  and store
```

| Layer | What is checked |
|---|---|
| **Golden model** | `scripts/zkne_golden.py` is written from FIPS-197 and the Sail code, not from the RTL. Its self-test runs FIPS-197 C.1 both through a textbook AES-128 and through AES-128 built from the four instructions. |
| **Unit, random** | Edge cases plus **10,000 random operand sets per instruction** (about 48,000 vectors), RTL vs golden. Also checks that the result is 0 when `valid=0`. |
| **FIPS-197** | Directed C.1 intermediate values, and a full AES-128 in assembly with key expansion done by `aes64ks1i`/`aes64ks2`. |
| **Zkt** | The same program with 4 different key/plaintext sets takes the same number of cycles. |
| **Pipeline** | Forwarding on both operands, load-use into every Zkne instruction, and taken branches squashing Zkne instructions (even a squashed reserved-rnum one). |
| **Random program** | 3,000 random Zkne/xor/ld instructions, biased toward hazards. Checked core vs golden and core vs Spike. |
| **Spike lockstep** | The same ELF runs on the core and on `spike --isa=rv64i_zkne`. The order and value of every register write and store are compared. |
| **Base ISA** | xor, lui/auipc, little-endian byte order, beq/bne, 48 illegal encodings, illegal-instruction-as-NOP, tohost exit. |
| **Legacy** | The original program still gives the original 32 registers and 21 cycles. |

The random tests use a fixed seed. You can override it and the test sizes
with `ZKNE_SEED`, `ZKNE_N` and `ZKNE_PROG_N`.

**Spike lockstep results:** all identical.

| Program | Register writes | Stores | Cycles |
|---|---:|---:|---:|
| `tests/zkne/fips197_c1.S` | 83 | 3 | 90 |
| `sw/aes128_ctr.S` | 236 | 9 | 259 |
| Random program (3000 instructions) | 2979 | 1 | 3182 |
| 10 smaller ISA / Zkne / pipeline tests | 144 | 15 | – |
| **Total (13 programs)** | **3442** | **28** | |

The per-program breakdown is in [`docs/ZKNE.md`](docs/ZKNE.md#comparison-with-spike).

## Side-channel hooks

```bash
make vcd PROG=sw/aes128_ctr.S
# -> build/vcd/aes128_ctr_zkne.vcd : only pipe_tb.uut.ZKNE_UNIT and below
```

Every step of the AES datapath has its own wire, so it shows up in the VCD:

| Net | Meaning |
|---|---|
| `a`, `b`, `rn` | Operands (isolated when `ISOLATE=1`) |
| `sr` | ShiftRows output |
| `sb_in`, `sb_out` | S-box layer input and output |
| `sbox[i].u_sbox.in/out` | Each of the 8 S-boxes |
| `mixcol[c].x*/t*/y*` | MixColumns: inputs, xtime terms, outputs |
| `mc` | MixColumns result |
| `ks_rot`, `rcon`, `ks1_word` | `aes64ks1i` steps |
| `ks2_w0`, `ks2_w1` | `aes64ks2` words |
| `result` | Unit output |

- **Masked S-box:** all S-box use goes through one module, `rtl/aes_sbox.v`
  (generated by `scripts/gen_aes_sbox.py`). To try a masked
  implementation, replace that module.
- **Operand isolation:** a test parses the VCD and checks that the operand,
  S-box and result nets are zero whenever no AES instruction is in EX.
- **Isolation on/off:** `zkne_unit` has a parameter `ISOLATE` (default 1),
  set from the top as `ZKNE_ISOLATE` and by `make ... ISOLATE=0`. With 0, the
  operands feed the datapath every cycle and the internal muxes select on
  the instruction bits alone, so the AES nets follow ordinary ALU traffic.
  Results are the same in both modes, and the test suite checks that
  (unit vectors, FIPS-197, CTR, forwarding and the random program vs Spike).
  An unprotected crypto unit in a larger core probably doesn't isolate
  its operands, so measure both ways. On the CTR demo, the bit toggles on
  `a/b/sr/sb_in/sb_out/mc/result` are:

  | | Toggles while idle | Total toggles |
  |---|---|---|
  | `ISOLATE=1` | 0 | 31,918 |
  | `ISOLATE=0` | 10,224 | 41,970 |

  "Idle" means no AES instruction in EX in either of two consecutive VCD
  frames. With isolation, the only toggles outside AES instructions are
  the return to zero just after one.- **Not hardened:** the unit is unprotected AES. Operand isolation reduces
  noise but is not a countermeasure.

## Writing your own programs

```asm
#include "test.h"
        .section .text.init
        .globl _start
_start:
        la        x1, data
        ld        x5, 0(x1)
        ld        x6, 8(x1)
        aes64esm  x7, x5, x6
        aes64esm  x8, x6, x5
        TEST_END                    // store 1 to tohost (Spike's convention)

        .data
data:   .byte 0x00,0x10,0x20,0x30,0x40,0x50,0x60,0x70
        .byte 0x80,0x90,0xa0,0xb0,0xc0,0xd0,0xe0,0xf0

// EXPECT: x7 = 0x92bcf5571564725f      (checked by the test runner)
```

```bash
make sim PROG=myprog.S      # run it and print the registers
make vcd PROG=myprog.S      # Zkne-unit VCD
```

- **Memory map** (`sw/link.ld`): code at `0x80000000`, data at
  `0x80008000`, `tohost` at `0x8000f000`.
- **Ending the program:** `TEST_END` passes; `TEST_FAIL(code)` fails with
  that code. Both use x29/x30.
- **Constants:** load them with `la` + `ld`. There is no `slli`, so `li`
  with a large constant won't assemble into supported instructions.
- **Adding a test to the suite:** add a function decorated with `@test(...)`
  in `scripts/run_tests.py`.

## Project layout

```text
rtl/            synthesizable core (rtl/files.f lists the files)
tb/             pipe_tb.v (core testbench), zkne_unit_tb.v (unit vectors)
sw/             test.h, link.ld, aes128_zkne.h macros, aes128_ctr.S demo
tests/
  legacy/       original program (converted to little-endian) + golden regs
  isa/          base-ISA regression tests (xor, lui/auipc, endian, branches, illegal, tohost)
  zkne/         directed Zkne, FIPS-197 C.1, reserved rnum
  pipeline/     forwarding, load-use, squash
scripts/        run_tests.py (make test), zkne_golden.py, gen_random_prog.py,
                gen_aes_sbox.py, sim_prog.py, lint_waivers.vlt, legacy_hex_to_le.py
docs/ZKNE.md    full implementation notes, encodings, Spike results, limits
LICENSE         MIT
```

## Known limits

- **No traps.** An illegal instruction becomes a NOP (no register write, no
  memory access, no branch), and the testbench fails the run with a clear
  message.
- **Reserved rnum differs from Spike.** `aes64ks1i` with rnum > 0xA is a NOP
  plus a test failure here, while Spike traps. That test therefore runs
  outside the lockstep set.
- **Subset of RV64I.** No `jal`/`jalr`, shifts, byte/word loads or stores,
  or CSRs.
- **Memories.** Separate 64 KB instruction and data memories, decoded from
  the low address bits. Both are loaded from the same ELF. Stores don't
  reach instruction memory, so there's no self-modifying code.
- **Misaligned `ld`/`sd`** run byte by byte. Spike needs `_zicclsm` to match.

The full list is in [`docs/ZKNE.md`](docs/ZKNE.md#known-limits).

## Project history

This started as a small 5-stage RV64 pipeline with a custom AES
instruction (`aes_round64`, custom-0). That instruction treated a 64-bit
value as the whole AES state, which isn't real AES, so it was replaced by
the standard Zkne instructions. The work was done in small steps, one
commit each, so `git log` reads as a guide:

| Commit / tag | Step |
|---|---|
| `v0-original` | The original project, exactly as it was |
| Step 2 | Cleanup, layout, Icarus 13 build, Makefile, test runner (no behaviour change) |
| Step 2.5 A–F | Base-ISA fixes: `xor`, `lui`/`auipc` + reset vector, little-endian, no silent fallbacks, illegal = NOP, tohost exit |
| Step 3 | Zkne implementation |
| Step 4 | Golden model, FIPS-197, random tests, Spike lockstep |
| Step 5 | AES-128 CTR demo and the Zkne-unit VCD hook |
| `v1.0` | Operand isolation switch (`ISOLATE`), MIT license. The fixed version for the paper |

The original instruction is kept, unchanged, behind `-DLEGACY_AES`, and its
regression test still passes.

## License

MIT. See [`LICENSE`](LICENSE).

---

<sub>References: RISC-V Cryptography Extensions Volume I (Scalar & Entropy
Source), v1.0.1 · FIPS-197 (AES) · NIST SP 800-38A (block cipher modes) ·
Spike, riscv-software-src/riscv-isa-sim.</sub>
