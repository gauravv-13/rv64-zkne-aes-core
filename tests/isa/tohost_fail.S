// TEST_FAIL(5): tohost = (5 << 1) | 1 = 11. The testbench must report
// RESULT: FAIL with code 5 (the runner expects exactly that).
#include "test.h"
        .section .text.init
        .globl _start
_start:
        addi x5, x0, 7
        TEST_FAIL(5)
        addi x6, x0, 1              // never executed

// EXPECT: x5 = 0x0000000000000007
// EXPECT: x6 = 0x0000000000000000
