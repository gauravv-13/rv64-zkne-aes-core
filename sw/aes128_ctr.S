// AES-128 CTR encryption of 4 blocks with the RV64 Zkne instructions.
// Test vector: NIST SP 800-38A, F.5.1 CTR-AES128.Encrypt.
//
// - Key expansion with aes64ks1i/aes64ks2; the 11 round keys stay in
//   registers for the whole run: rk r = x(6+2r) (bytes 0..7) and
//   x(7+2r) (bytes 8..15), i.e. x6..x27.
// - The counter blocks are precomputed in data memory (in FIPS byte order:
//   the counter is big-endian, and incrementing it in registers would need
//   a byte reversal that RV64I + Zkne does not have).
// - One pointer (x1) walks counter, plaintext and ciphertext blocks, which
//   are laid out 64 bytes apart.
//
// Byte order: 16-byte blocks are stored in FIPS order and loaded with two
// little-endian ld, giving the spec's register layout (AES byte 0 in bits
// [7:0] of the low register). No reordering anywhere.
#include "test.h"
#include "aes128_zkne.h"

        .section .text.init
        .globl _start
_start:
        la    x31, key
        ld    x6, 0(x31)
        ld    x7, 8(x31)
key_expansion:
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

        la    x1, ctr_blocks        // x1: current counter block
        addi  x28, x1, 64           // end of the 4 counter blocks
block_loop:
        ld    x2, 0(x1)             // counter block
        ld    x3, 8(x1)
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
        AES128_FINAL(x2, x3, x26, x27, x4, x5)   // keystream block
        ld    x4, 64(x1)            // plaintext block
        ld    x5, 72(x1)
        xor   x2, x2, x4
        xor   x3, x3, x5
        sd    x2, 128(x1)           // ciphertext block
        sd    x3, 136(x1)
        addi  x1, x1, 16
        bne   x1, x28, block_loop
        TEST_END

        .data
ctr_blocks:                         // 0x80008000
        .byte 0xf0,0xf1,0xf2,0xf3,0xf4,0xf5,0xf6,0xf7,0xf8,0xf9,0xfa,0xfb,0xfc,0xfd,0xfe,0xff
        .byte 0xf0,0xf1,0xf2,0xf3,0xf4,0xf5,0xf6,0xf7,0xf8,0xf9,0xfa,0xfb,0xfc,0xfd,0xff,0x00
        .byte 0xf0,0xf1,0xf2,0xf3,0xf4,0xf5,0xf6,0xf7,0xf8,0xf9,0xfa,0xfb,0xfc,0xfd,0xff,0x01
        .byte 0xf0,0xf1,0xf2,0xf3,0xf4,0xf5,0xf6,0xf7,0xf8,0xf9,0xfa,0xfb,0xfc,0xfd,0xff,0x02
plaintext:                          // 0x80008040
        .byte 0x6b,0xc1,0xbe,0xe2,0x2e,0x40,0x9f,0x96,0xe9,0x3d,0x7e,0x11,0x73,0x93,0x17,0x2a
        .byte 0xae,0x2d,0x8a,0x57,0x1e,0x03,0xac,0x9c,0x9e,0xb7,0x6f,0xac,0x45,0xaf,0x8e,0x51
        .byte 0x30,0xc8,0x1c,0x46,0xa3,0x5c,0xe4,0x11,0xe5,0xfb,0xc1,0x19,0x1a,0x0a,0x52,0xef
        .byte 0xf6,0x9f,0x24,0x45,0xdf,0x4f,0x9b,0x17,0xad,0x2b,0x41,0x7b,0xe6,0x6c,0x37,0x10
ciphertext:                         // 0x80008080
        .dword 0, 0, 0, 0, 0, 0, 0, 0
key:                                // 0x800080c0
        .byte 0x2b,0x7e,0x15,0x16,0x28,0xae,0xd2,0xa6,0xab,0xf7,0x15,0x88,0x09,0xcf,0x4f,0x3c

// SP 800-38A F.5.1 ciphertext blocks 1-4
// EXPECT_MEM: 0x80008080 = 87 4d 61 91 b6 20 e3 26 1b ef 68 64 99 0d b6 ce
// EXPECT_MEM: 0x80008090 = 98 06 f6 6b 79 70 fd ff 86 17 18 7b b9 ff fd ff
// EXPECT_MEM: 0x800080a0 = 5a e4 df 3e db d5 d3 5e 5b 4f 09 02 0d b0 3e ab
// EXPECT_MEM: 0x800080b0 = 1e 03 1d da 2f be 03 d1 79 21 70 a0 f3 00 9c ee
// Last ciphertext block in registers
// EXPECT: x2 = 0xd103be2fda1d031e
// EXPECT: x3 = 0xee9c00f3a0702179
