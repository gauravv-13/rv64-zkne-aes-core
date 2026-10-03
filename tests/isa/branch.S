// beq / bne decode. Before this fix every branch funct3 behaved as beq.
// Taken and not-taken cases for both, operands forwarded from EX/MEM and
// MEM/WB, and the two instructions behind a taken branch are squashed.
#include "test.h"
        .section .text.init
        .globl _start
_start:
        addi x1, x0, 5
        addi x2, x0, 5
        addi x3, x0, 7
        bne  x1, x2, fail           // equal: not taken
        addi x10, x0, 1
        beq  x1, x3, fail           // not equal: not taken
        addi x11, x0, 2
        bne  x1, x3, 1f             // not equal: taken
        addi x20, x0, 99            // squashed
        addi x21, x0, 99            // squashed
1:      beq  x1, x2, 2f             // equal: taken
        addi x22, x0, 99            // squashed
        addi x23, x0, 99            // squashed
2:      addi x12, x0, 3
        addi x4, x0, 5
        bne  x4, x1, fail           // rs1 forwarded from EX/MEM: not taken
        addi x5, x0, 6
        addi x13, x0, 4
        bne  x5, x4, 3f             // rs1 from MEM/WB, rs2 from earlier: taken
        addi x24, x0, 99            // squashed
3:      addi x14, x0, 5
        TEST_END
fail:   addi x31, x0, 1
        TEST_END

// EXPECT: x10 = 0x0000000000000001
// EXPECT: x11 = 0x0000000000000002
// EXPECT: x12 = 0x0000000000000003
// EXPECT: x13 = 0x0000000000000004
// EXPECT: x14 = 0x0000000000000005
// EXPECT: x20 = 0x0000000000000000
// EXPECT: x21 = 0x0000000000000000
// EXPECT: x22 = 0x0000000000000000
// EXPECT: x23 = 0x0000000000000000
// EXPECT: x24 = 0x0000000000000000
// EXPECT: x31 = 0x0000000000000000
