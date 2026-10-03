// aes64ks1i with rnum 0xB..0xF (reserved in the spec; Sail calls
// handle_illegal(), Spike traps). This core has no traps: each must raise
// illegal_instr and act as a NOP. Outside the Spike lockstep set because
// Spike traps here. Encoded with .insn: imm[11:0] = instr[31:20] =
// 0011_0001_rnum. rnum 0xA (legal) next to them must not be reported.
#include "test.h"
#define ILL(name, ...) ill_##name: __VA_ARGS__
        .section .text.init
        .globl _start
_start:
        addi x1, x0, 0x123
        ILL(rnum_b, .insn i 0x13, 1, x5, x1, 0x31b)
        ILL(rnum_c, .insn i 0x13, 1, x6, x1, 0x31c)
        ILL(rnum_d, .insn i 0x13, 1, x7, x1, 0x31d)
        ILL(rnum_e, .insn i 0x13, 1, x8, x1, 0x31e)
        ILL(rnum_f, .insn i 0x13, 1, x9, x1, 0x31f)
        .insn i 0x13, 1, x10, x0, 0x31a     // aes64ks1i x10, x0, 0xA: legal
        TEST_END

// EXPECT: x5  = 0x0000000000000000
// EXPECT: x6  = 0x0000000000000000
// EXPECT: x7  = 0x0000000000000000
// EXPECT: x8  = 0x0000000000000000
// EXPECT: x9  = 0x0000000000000000
// SubWord(0) = 63636363, rcon 0
// EXPECT: x10 = 0x6363636363636363
