// Load-use hazards into Zkne instructions: ld immediately followed by a
// Zkne instruction that reads the loaded register as rs1, as rs2, as both,
// into aes64ks1i and aes64ks2, and with rd == rs1 == rs2.
#include "test.h"
        .section .text.init
        .globl _start
_start:
        la    x1, data
        ld    x2, 0(x1)             // A
        ld    x3, 8(x1)             // B
        addi  x0, x0, 0
        addi  x0, x0, 0
        ld    x5, 16(x1)
        aes64esm x6, x5, x3         // load-use on rs1
        ld    x7, 24(x1)
        aes64esm x8, x2, x7         // load-use on rs2
        ld    x9, 0(x1)
        ld    x10, 8(x1)
        aes64esm x11, x9, x10       // rs1 loaded 2 before, rs2 load-use
        aes64esm x12, x10, x9       // swapped pair right after the stall
        ld    x13, 16(x1)
        aes64ks1i x14, x13, 0xA     // load-use into ks1i
        ld    x15, 24(x1)
        aes64ks2 x16, x14, x15      // load-use on rs2 of ks2
        ld    x17, 0(x1)
        aes64esm x17, x17, x17      // load-use, rd = rs1 = rs2
        ld    x18, 8(x1)
        aes64es  x19, x18, x18      // load-use on both operands
        TEST_END

        .data
data:   .dword 0x0123456789abcdef, 0xfedcba9876543210, 0x0f1e2d3c4b5a6978, 0x8796a5b4c3d2e1f0

// Expected values computed with scripts/zkne_golden.py
// EXPECT: x6  = 0xfe118f9d4af2cc8b
// EXPECT: x8  = 0xa9b462358ff9d0b5
// EXPECT: x11 = 0x6443f5555927d88c
// EXPECT: x12 = 0x21ff754e2b7ee396
// EXPECT: x14 = 0x7672d8eb7672d8eb
// EXPECT: x16 = 0x32369cafb5a0391b
// EXPECT: x17 = 0x5a86294c8ef1d909
// EXPECT: x19 = 0x38862346bb20f4ca
