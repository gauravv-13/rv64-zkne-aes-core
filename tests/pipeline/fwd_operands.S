// Forwarding into Zkne instructions on both operands:
// EX/MEM and MEM/WB on rs1 and rs2 in both combinations, the same
// register on both operands, the back-to-back swapped-operand pair
// (aes64esm t2,t0,t1 ; aes64esm t3,t1,t0) chained on the previous pair,
// the register-file write-through bypass, and Zkne results forwarded into
// xor, sd store data, ks1i and a branch.
#include "test.h"
        .section .text.init
        .globl _start
_start:
        la    x1, data
        ld    x2, 0(x1)             // A
        ld    x3, 8(x1)             // B
        ld    x4, 16(x1)            // C
        addi  x0, x0, 0
        addi  x0, x0, 0
        // rs1 from EX/MEM, rs2 from MEM/WB
        xor   x5, x2, x4
        xor   x6, x3, x4
        aes64esm x7, x6, x5
        // rs1 from MEM/WB, rs2 from EX/MEM
        xor   x8, x2, x3
        xor   x9, x4, x3
        aes64esm x10, x8, x9
        // same register on both operands, from EX/MEM
        xor   x11, x2, x4
        aes64es  x12, x11, x11
        // back-to-back swapped pairs, each fed by the previous pair
        aes64esm x13, x7, x10       // rs1 from WB bypass/regs, rs2 MEM/WB
        aes64esm x14, x10, x7
        aes64esm x15, x13, x14      // rs1 MEM/WB, rs2 EX/MEM
        aes64esm x16, x14, x13      // rs1 MEM/WB, rs2 WB bypass
        // Zkne results into ks2, sd (store data), ks1i, xor and bne
        aes64ks2  x17, x15, x16
        sd    x17, 24(x1)           // store data from EX/MEM
        aes64ks1i x18, x17, 3       // rs1 from MEM/WB
        xor   x19, x18, x17         // EX/MEM and WB bypass
        bne   x19, x18, 1f          // operand from EX/MEM; taken unless x17 = 0
        TEST_FAIL(1)
1:      ld    x20, 24(x1)           // read back the stored Zkne result
        // register-file write-through: x21 is written in WB while the
        // second aes64es reads it in ID
        aes64es  x21, x2, x3
        addi  x0, x0, 0
        addi  x0, x0, 0
        aes64es  x22, x21, x21
        TEST_END

        .data
data:   .dword 0x0123456789abcdef, 0xfedcba9876543210, 0x0f1e2d3c4b5a6978, 0

// Expected values computed with scripts/zkne_golden.py
// EXPECT: x5  = 0x0e3d685bc2f1a497
// EXPECT: x6  = 0xf1c297a43d0e5b68
// EXPECT: x7  = 0xfb279549ab721d03
// EXPECT: x8  = 0xffffffffffffffff
// EXPECT: x9  = 0xf1c297a43d0e5b68
// EXPECT: x10 = 0x0a5f1d54deb57d1c
// EXPECT: x11 = 0x0e3d685bc2f1a497
// EXPECT: x12 = 0x25274939aba14588
// EXPECT: x13 = 0xb9e7f6c1bc492c3a
// EXPECT: x14 = 0x3220216645a9009b
// EXPECT: x15 = 0x96c119874c1a492d
// EXPECT: x16 = 0x6cc3180f5665ee59
// EXPECT: x17 = 0xac67efd1c0a4f7de
// EXPECT: x18 = 0x3e9185d73e9185d7
// EXPECT: x19 = 0x92f66a06fe357209
// EXPECT: x20 = 0xac67efd1c0a4f7de
// EXPECT: x21 = 0xa7862385bb206edf
// EXPECT: x22 = 0xea449f975cb7269e
