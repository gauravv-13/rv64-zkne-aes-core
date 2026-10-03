// Common macros for test programs (assembled with riscv64-unknown-elf-gcc).
//
// Programs end by storing to `tohost`, the HTIF convention Spike uses:
// 1 = pass, (code << 1) | 1 = fail with code. The testbench watches the
// same address (+TOHOST=, taken from the ELF symbol). After the store
// the program spins on a beq, which writes no register.
//
// TEST_END / TEST_FAIL clobber x29 (t4) and x30 (t5).
#ifndef TEST_H
#define TEST_H

#define TEST_EXIT(value)            \
        la   x30, tohost;           \
        addi x29, x0, (value);      \
        sd   x29, 0(x30);           \
1:      beq  x0, x0, 1b

#define TEST_END        TEST_EXIT(1)
#define TEST_FAIL(code) TEST_EXIT(((code) << 1) | 1)

// tohost / fromhost, placed by sw/link.ld (Spike's HTIF needs both).
        .pushsection .tohost, "aw", @progbits
        .align 6
        .globl tohost
tohost:   .dword 0
        .align 6
        .globl fromhost
fromhost: .dword 0
        .popsection

#endif
