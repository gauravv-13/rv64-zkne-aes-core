// TEST_END: la x30, tohost; addi x29, x0, 1; sd x29, 0(x30).
// The addi x29 just before the store must have committed when the run
// ends; nothing after the exit may commit.
#include "test.h"
        .section .text.init
        .globl _start
_start:
        addi x5, x0, 5
        addi x6, x0, 6
        TEST_END
        addi x7, x0, 7              // never executed (after the spin loop)
        addi x8, x0, 8

// EXPECT: x5 = 0x0000000000000005
// EXPECT: x6 = 0x0000000000000006
// EXPECT: x7 = 0x0000000000000000
// EXPECT: x8 = 0x0000000000000000
// EXPECT: x29 = 0x0000000000000001
// EXPECT: x30 = 0x000000008000f000
