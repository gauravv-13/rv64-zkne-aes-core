// AES-128 with the RV64 Zkne instructions: assembler macros shared by the
// FIPS-197 test and the CTR demo.
//
// Register layout (spec): a 128-bit block / round key is a register pair
// (lo, hi): lo holds AES bytes 0..7 (byte 0 in bits [7:0]), hi bytes
// 8..15. Loading 16 bytes stored in FIPS order with two little-endian ld
// gives exactly this, so no reordering is needed anywhere.
#ifndef AES128_ZKNE_H
#define AES128_ZKNE_H

// One key-expansion step: (plo, phi) = round key r, (nlo, nhi) = round
// key r+1, rnum = r. tmp is clobbered.
#define AES128_KS(rnum, plo, phi, nlo, nhi, tmp) \
        aes64ks1i tmp, phi, rnum;                \
        aes64ks2  nlo, tmp, plo;                 \
        aes64ks2  nhi, nlo, phi

// Middle round on state (s0, s1) with round key (klo, khi); t0/t1 clobbered.
// The two aes64esm read the same rs1/rs2 pair swapped: the 128-bit state is
// in two registers and each instruction returns one 64-bit half.
#define AES128_ROUND(s0, s1, klo, khi, t0, t1) \
        aes64esm t0, s0, s1;                   \
        aes64esm t1, s1, s0;                   \
        xor      s0, t0, klo;                  \
        xor      s1, t1, khi

// Final round (no MixColumns).
#define AES128_FINAL(s0, s1, klo, khi, t0, t1) \
        aes64es  t0, s0, s1;                   \
        aes64es  t1, s1, s0;                   \
        xor      s0, t0, klo;                  \
        xor      s1, t1, khi

#endif
