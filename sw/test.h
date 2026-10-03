// Common macros for test programs (assembled with riscv64-unknown-elf-gcc).
#ifndef TEST_H
#define TEST_H

// End of program. For now the testbench stops when it fetches a
// zero word.
#define TEST_END \
        .word 0

#endif
