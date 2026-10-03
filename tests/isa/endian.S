// Little-endian memory: sd stores bits [7:0] at the lowest address.
// - sd of a known value, then the single bytes are checked in data memory
//   (EXPECT_MEM) and read back with ld.
// - A .dword placed by the assembler (data image loaded from the ELF)
//   reads back with ld unchanged: no byte swapping anywhere.
// - Overlapping sd at buf+4 changes only bytes 4..11.
#include "test.h"
        .section .text.init
        .globl _start
_start:
        la    x1, buf               // 0x80008000
        la    x2, val
        ld    x3, 0(x2)             // 0x0123456789abcdef from the ELF
        sd    x3, 0(x1)
        ld    x4, 0(x1)             // round trip
        addi  x5, x0, -1            // 0xffffffffffffffff
        sd    x5, 16(x1)
        addi  x6, x0, 0x7f
        sd    x6, 4(x1)             // overlapping store at buf+4 (misaligned)
        ld    x7, 0(x1)             // low 4 bytes of x3, then 7f 00 00 00
        ld    x8, 8(x1)             // 00 00 00 00 (buf+8..11), then zeros
        TEST_END

        .data
buf:    .dword 0, 0, 0
val:    .dword 0x0123456789abcdef

// EXPECT: x3 = 0x0123456789abcdef
// EXPECT: x4 = 0x0123456789abcdef
// EXPECT: x7 = 0x0000007f89abcdef
// EXPECT: x8 = 0x0000000000000000
// EXPECT_MEM: 0x80008000 = ef cd ab 89 7f 00 00 00 00 00 00 00
// EXPECT_MEM: 0x80008010 = ff ff ff ff ff ff ff ff
// EXPECT_MEM: 0x80008018 = ef cd ab 89 67 45 23 01
