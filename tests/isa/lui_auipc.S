// lui / auipc, and `la` (auipc + addi). Runs at 0x80000000.
// lui sign-extends bit 31 into the upper half (RV64). auipc results are
// forwarded into the next instruction. buf is at 0x80008000 (sw/link.ld).
#include "test.h"
        .section .text.init
        .globl _start
_start:
        lui   x1, 0x12345           // 0x80000000
        lui   x2, 0x80000           // 0x80000004  sign-extended
        lui   x3, 0xfffff           // 0x80000008
        auipc x4, 0                 // 0x8000000c
        auipc x5, 0x1               // 0x80000010  pc + 0x1000
        auipc x6, 0xfffff           // 0x80000014  pc - 0x1000
        add   x7, x4, x1            // auipc result forwarded (EX/MEM, MEM/WB)
        la    x8, buf               // auipc + addi
        sd    x7, 0(x8)             // high address -> low bits decode
        ld    x9, 0(x8)
        lui   x10, 0x12345          // lui result forwarded into addi
        addi  x10, x10, 0x678
        TEST_END

        .data
buf:    .dword 0

// EXPECT: x1  = 0x0000000012345000
// EXPECT: x2  = 0xffffffff80000000
// EXPECT: x3  = 0xfffffffffffff000
// EXPECT: x4  = 0x000000008000000c
// EXPECT: x5  = 0x0000000080001010
// EXPECT: x6  = 0x000000007ffff014
// EXPECT: x7  = 0x000000009234500c
// EXPECT: x8  = 0x0000000080008000
// EXPECT: x9  = 0x000000009234500c
// EXPECT: x10 = 0x0000000012345678
