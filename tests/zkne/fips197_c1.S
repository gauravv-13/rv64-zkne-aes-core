// FIPS-197 Appendix C.1: AES-128, key 000102...0f, plaintext
// 00112233...ff, ciphertext 69c4e0d86a7b0430d8cdb78070b4c55a.
// Key expansion with aes64ks1i/aes64ks2; all 11 round keys stay in
// registers (rk r = x(6+2r) lo, x(7+2r) hi, i.e. x6..x27).
//
// KEY_BYTES / PT_BYTES can be overridden with -D (the Zkt test rebuilds
// this program with other data and checks that the cycle count is the
// same); the EXPECT lines below hold for the default FIPS data only.
#include "test.h"
#include "aes128_zkne.h"

#ifndef KEY_BYTES
#define KEY_BYTES 0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f
#endif
#ifndef PT_BYTES
#define PT_BYTES  0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff
#endif

        .section .text.init
        .globl _start
_start:
        la    x1, key
        ld    x6, 0(x1)             // round key 0 = cipher key
        ld    x7, 8(x1)
        AES128_KS(0, x6,  x7,  x8,  x9,  x5)
        AES128_KS(1, x8,  x9,  x10, x11, x5)
        AES128_KS(2, x10, x11, x12, x13, x5)
        AES128_KS(3, x12, x13, x14, x15, x5)
        AES128_KS(4, x14, x15, x16, x17, x5)
        AES128_KS(5, x16, x17, x18, x19, x5)
        AES128_KS(6, x18, x19, x20, x21, x5)
        AES128_KS(7, x20, x21, x22, x23, x5)
        AES128_KS(8, x22, x23, x24, x25, x5)
        AES128_KS(9, x24, x25, x26, x27, x5)

        ld    x2, 16(x1)            // plaintext
        ld    x3, 24(x1)
        xor   x2, x2, x6            // AddRoundKey(rk0)
        xor   x3, x3, x7
        AES128_ROUND(x2, x3, x8,  x9,  x4, x5)
        AES128_ROUND(x2, x3, x10, x11, x4, x5)
        AES128_ROUND(x2, x3, x12, x13, x4, x5)
        AES128_ROUND(x2, x3, x14, x15, x4, x5)
        AES128_ROUND(x2, x3, x16, x17, x4, x5)
        AES128_ROUND(x2, x3, x18, x19, x4, x5)
        AES128_ROUND(x2, x3, x20, x21, x4, x5)
        AES128_ROUND(x2, x3, x22, x23, x4, x5)
        AES128_ROUND(x2, x3, x24, x25, x4, x5)
        AES128_FINAL(x2, x3, x26, x27, x4, x5)

        la    x31, ct
        sd    x2, 0(x31)
        sd    x3, 8(x31)
        TEST_END

        .data
key:    .byte KEY_BYTES
pt:     .byte PT_BYTES
ct:     .dword 0, 0

// Ciphertext 69c4e0d8 6a7b0430 d8cdb780 70b4c55a (FIPS-197 C.1 output)
// EXPECT: x2  = 0x30047b6ad8e0c469
// EXPECT: x3  = 0x5ac5b47080b7cdd8
// EXPECT_MEM: 0x80008020 = 69 c4 e0 d8 6a 7b 04 30 d8 cd b7 80 70 b4 c5 5a
// round[1].k_sch d6aa74fdd2af72fadaa678f1d6ab76fe
// EXPECT: x8  = 0xfa72afd2fd74aad6
// EXPECT: x9  = 0xfe76abd6f178a6da
// round[10].k_sch 13111d7fe3944a17f307a78b4d2b30c5
// EXPECT: x26 = 0x174a94e37f1d1113
// EXPECT: x27 = 0xc5302b4d8ba707f3
