// Directed Zkne tests with expected values from FIPS-197 Appendix C.1
// (AES-128, key 000102...0f).
//
// Byte order: test data is stored as .byte lists in FIPS order, so AES
// state byte 0 is at the lowest address. A little-endian ld then puts
// state byte i in bits [8i+7:8i], which is exactly the register layout
// of the spec (bytes 0..7 in rs1, 8..15 in rs2). No reordering is needed;
// the EXPECT values below are the FIPS bytes packed the same way
// (byte 0 = least significant).
#include "test.h"
        .section .text.init
        .globl _start
_start:
        la    x1, data

        // Key expansion, round 1 and 2 (C.1 round[1].k_sch, round[2].k_sch)
        ld    x5, 0(x1)             // key bytes 0..7
        ld    x6, 8(x1)             // key bytes 8..15
        aes64ks1i x7, x6, 0         // load-use on rs1
        aes64ks2  x8, x7, x5        // rk1 bytes 0..7  (rs1 from EX/MEM)
        aes64ks2  x9, x8, x6        // rk1 bytes 8..15 (rs1 from EX/MEM)
        aes64ks1i x19, x9, 1
        aes64ks2  x20, x19, x8      // rk2 bytes 0..7
        aes64ks2  x21, x20, x9      // rk2 bytes 8..15
        aes64ks1i x18, x6, 0xA      // rnum = 0xA: SubWord without rotation, rcon = 0

        // Middle round: C.1 round[1].start -> round[1].m_col
        ld    x10, 16(x1)
        ld    x11, 24(x1)
        aes64esm x12, x10, x11      // bytes 0..7  (load-use on rs2)
        aes64esm x13, x11, x10      // bytes 8..15 (operands swapped, back to back)

        // Final round: C.1 round[10].start -> round[10].s_row
        ld    x14, 32(x1)
        ld    x15, 40(x1)
        aes64es  x16, x14, x15
        aes64es  x17, x15, x14
        TEST_END

        .data
data:   .byte 0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07   // key
        .byte 0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f
        .byte 0x00,0x10,0x20,0x30,0x40,0x50,0x60,0x70   // round[1].start
        .byte 0x80,0x90,0xa0,0xb0,0xc0,0xd0,0xe0,0xf0
        .byte 0xbd,0x6e,0x7c,0x3d,0xf2,0xb5,0x77,0x9e   // round[10].start
        .byte 0x0b,0x61,0x21,0x6e,0x8b,0x10,0xb6,0x89

// SubWord(RotWord(w3)) ^ rcon(1): w3 = 0c0d0e0f -> RotWord 0d0e0f0c ->
// SubWord d7ab76fe -> ^01 -> d6ab76fe (bytes), i.e. word 0xfe76abd6
// EXPECT: x7  = 0xfe76abd6fe76abd6
// round[1].k_sch = d6aa74fd d2af72fa daa678f1 d6ab76fe
// EXPECT: x8  = 0xfa72afd2fd74aad6
// EXPECT: x9  = 0xfe76abd6f178a6da
// SubWord(RotWord(w7 = d6ab76fe)) ^ rcon(2) = 6238bbf6 ^ 02 -> 6038bbf6
// EXPECT: x19 = 0xf6bb3860f6bb3860
// round[2].k_sch = b692cf0b 643dbdf1 be9bc500 6830b3fe
// EXPECT: x20 = 0xf1bd3d640bcf92b6
// EXPECT: x21 = 0xfeb3306800c59bbe
// rnum 0xA: SubWord(w3 = 0c0d0e0f) = fed7ab76 (bytes), no rcon
// EXPECT: x18 = 0x76abd7fe76abd7fe
// round[1].m_col = 5f726415 57f5bc92 f7be3b29 1db9f91a
// EXPECT: x12 = 0x92bcf5571564725f
// EXPECT: x13 = 0x1af9b91d293bbef7
// round[10].s_row = 7ad5fda7 89ef4e27 2bca100b 3d9ff59f
// EXPECT: x16 = 0x274eef89a7fdd57a
// EXPECT: x17 = 0x9ff59f3d0b10ca2b
