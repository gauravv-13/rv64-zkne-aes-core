// An illegal instruction must behave as a NOP: no register write, no
// memory write, no branch. Each one below would have a visible effect
// under the old silent fallbacks (shown in the comment). Run with
// +ALLOW_ILLEGAL; the default (stop and fail) is tested separately.
#include "test.h"
        .section .text.init
        .globl _start
_start:
        la    x1, buf
        addi  x2, x0, 0x55
        sd    x2, 0(x1)             // buf = 0x55 (legal)
first_illegal:
        lw    x5, 0(x1)             // ld fallback: x5 = 0x55
        slli  x6, x2, 1             // addi fallback: x6 = 0x56
        sll   x7, x2, x2            // and fallback: x7 = 0x55
        sw    x0, 0(x1)             // sd fallback: buf = 0
        blt   x0, x0, skip          // beq fallback: taken
        addi  x8, x0, 8             // must execute
        andi  x9, x2, 0             // addi fallback: x9 = 0x55 (rd != 0)
        add   x10, x5, x6           // reads x5/x6: forwarding must not
                                    // pick up an illegal "result"
        ld    x11, 0(x1)            // buf unchanged: 0x55
        TEST_END
skip:   addi  x31, x0, 1
        TEST_END

        .data
buf:    .dword 0

// EXPECT: x5  = 0x0000000000000000
// EXPECT: x6  = 0x0000000000000000
// EXPECT: x7  = 0x0000000000000000
// EXPECT: x8  = 0x0000000000000008
// EXPECT: x9  = 0x0000000000000000
// EXPECT: x10 = 0x0000000000000000
// EXPECT: x11 = 0x0000000000000055
// EXPECT: x31 = 0x0000000000000000
// EXPECT_MEM: 0x80008000 = 55 00 00 00 00 00 00 00
