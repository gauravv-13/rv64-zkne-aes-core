// xor: R-type funct7=0000000 funct3=100.
// Covers forwarding of an xor result from EX/MEM and MEM/WB into both
// operands, xor with x0, and x ^ x = 0.
#include "test.h"
        .section .text.init
        .globl _start
_start:
        addi x1, x0, 0x5a3          // 0x00000000000005a3
        addi x2, x0, -1365          // 0xfffffffffffffaab
        xor  x3, x1, x2             // EX/MEM forwarding on rs2
        xor  x4, x3, x1             // EX/MEM on rs1, MEM/WB on rs2
        xor  x5, x2, x3             // MEM/WB forwarding on rs2
        xor  x6, x3, x3             // same register on both operands
        xor  x7, x1, x0             // xor with zero
        xor  x0, x1, x2             // write to x0 is discarded
        TEST_END

// EXPECT: x1 = 0x00000000000005a3
// EXPECT: x2 = 0xfffffffffffffaab
// EXPECT: x3 = 0xffffffffffffff08
// EXPECT: x4 = 0xfffffffffffffaab
// EXPECT: x5 = 0x00000000000005a3
// EXPECT: x6 = 0x0000000000000000
// EXPECT: x7 = 0x00000000000005a3
// EXPECT: x0 = 0x0000000000000000
