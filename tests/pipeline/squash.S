// Mispredicted (taken) branches squashing Zkne instructions. Branches are
// predicted not-taken and resolved in EX, so the two instructions after a
// taken branch are fetched and must be squashed: no register write, no
// forwarding of their results, and no illegal-instruction report (a
// reserved-rnum aes64ks1i sits in one shadow; the default testbench mode
// fails the run on any illegal instruction that reaches EX).
#include "test.h"
        .section .text.init
        .globl _start
_start:
        la    x1, data
        ld    x2, 0(x1)
        ld    x3, 8(x1)
        addi  x20, x0, 0x111
        addi  x21, x0, 0x222
        beq   x0, x0, 1f            // taken
        aes64esm  x20, x2, x3       // squashed (in ID)
        aes64ks1i x21, x2, 4        // squashed (in IF)
1:      xor   x22, x20, x21         // must read the old x20/x21: 0x333
        bne   x2, x3, 2f            // taken
        aes64es   x23, x2, x3       // squashed
        .insn i 0x13, 1, x24, x2, 0x31f   // aes64ks1i rnum=0xF (reserved), squashed
2:      aes64esm  x25, x2, x3       // branch target executes
        beq   x2, x3, fail          // not taken: the next one executes
        aes64es   x26, x2, x3
        aes64ks2  x27, x2, x3
        bne   x27, x0, 3f           // taken, operand forwarded from a Zkne result
        aes64esm  x28, x2, x3       // squashed
        aes64esm  x31, x2, x3       // squashed
3:      TEST_END
fail:   TEST_FAIL(1)

        .data
data:   .dword 0x0123456789abcdef, 0xfedcba9876543210

// Expected values computed with scripts/zkne_golden.py
// EXPECT: x20 = 0x0000000000000111
// EXPECT: x21 = 0x0000000000000222
// EXPECT: x22 = 0x0000000000000333
// EXPECT: x23 = 0x0000000000000000
// EXPECT: x24 = 0x0000000000000000
// EXPECT: x25 = 0x6443f5555927d88c
// EXPECT: x26 = 0xa7862385bb206edf
// EXPECT: x27 = 0x89abcdef77777777
// EXPECT: x28 = 0x0000000000000000
// EXPECT: x31 = 0x0000000000000000
