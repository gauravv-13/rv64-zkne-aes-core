#!/usr/bin/env python3
"""Golden model of the RV64 Zkne instructions (aes64es, aes64esm,
aes64ks1i, aes64ks2).

Written from the specifications, not from the RTL:
  - FIPS-197 (AES): S-box, ShiftRows, MixColumns, KeyExpansion, Cipher.
  - RISC-V Scalar Crypto v1.0.1, Sail code of the four instructions:

      AES64ES:   sr = aes_rv64_shiftrows_fwd(X(rs2), X(rs1)); wd = sr[63..0]
                 X(rd) = aes_apply_fwd_sbox_to_each_byte(wd)
      AES64ESM:  ... sb = aes_apply_fwd_sbox_to_each_byte(wd)
                 X(rd) = aes_mixcolumn_fwd(sb[63..32]) @ aes_mixcolumn_fwd(sb[31..0])
      AES64KS1I: if rnum > 10 then illegal
                 tmp1 = X(rs1)[63..32]; rc = aes_decode_rcon(rnum)
                 tmp2 = if rnum == 0xA then tmp1 else ror32(tmp1, 8)
                 tmp3 = aes_subword_fwd(tmp2); X(rd) = (tmp3 ^ rc) @ (tmp3 ^ rc)
      AES64KS2:  w0 = X(rs1)[63..32] ^ X(rs2)[31..0]
                 w1 = X(rs1)[63..32] ^ X(rs2)[31..0] ^ X(rs2)[63..32]
                 X(rd) = w1 @ w0

The spec's register layout for the 128-bit state: AES state bytes 0..7
are rs1 (byte i in bits [8i+7:8i]) and bytes 8..15 are rs2; the state is
column-major (byte 4c+r = row r, column c). The ShiftRows of the Sail
helper is therefore derived here from the FIPS-197 ShiftRows on the full
16-byte state, rather than from a hard-coded byte map.

    python3 scripts/zkne_golden.py selftest
"""
import sys

MASK64 = (1 << 64) - 1
MASK32 = (1 << 32) - 1


class IllegalInstruction(Exception):
    pass


# ---------------------------------------------------------------------------
# GF(2^8) with the AES polynomial m(x) = x^8 + x^4 + x^3 + x + 1 (FIPS-197 4.2)
# ---------------------------------------------------------------------------
def xtime(b):
    b <<= 1
    return (b ^ 0x11B) if b & 0x100 else b


def gmul(a, b):
    r = 0
    while b:
        if b & 1:
            r ^= a
        a = xtime(a)
        b >>= 1
    return r


# Log / antilog tables with generator 0x03; inverse = g^(255 - log a).
EXP = [0] * 255
LOG = [0] * 256
_x = 1
for _i in range(255):
    EXP[_i] = _x
    LOG[_x] = _i
    _x = gmul(_x, 3)


def ginv(a):
    return 0 if a == 0 else EXP[(255 - LOG[a]) % 255]


def _affine(b):
    """FIPS-197 eq. 5.1: b'_i = b_i ^ b_(i+4) ^ b_(i+5) ^ b_(i+6) ^ b_(i+7) ^ c_i, c = 0x63."""
    out = 0
    for i in range(8):
        bit = 0
        for k in (0, 4, 5, 6, 7):
            bit ^= (b >> ((i + k) % 8)) & 1
        bit ^= (0x63 >> i) & 1
        out |= bit << i
    return out


SBOX = [_affine(ginv(x)) for x in range(256)]


# ---------------------------------------------------------------------------
# FIPS-197 transformations on a 16-byte column-major state
# ---------------------------------------------------------------------------
def sub_bytes(s):
    return [SBOX[b] for b in s]


def shift_rows(s):
    # s'[r, c] = s[r, (c + r) mod 4]
    return [s[r + 4 * ((c + r) % 4)] for c in range(4) for r in range(4)]


def mix_column(col):
    a0, a1, a2, a3 = col
    return [gmul(a0, 2) ^ gmul(a1, 3) ^ a2 ^ a3,
            a0 ^ gmul(a1, 2) ^ gmul(a2, 3) ^ a3,
            a0 ^ a1 ^ gmul(a2, 2) ^ gmul(a3, 3),
            gmul(a0, 3) ^ a1 ^ a2 ^ gmul(a3, 2)]


def mix_columns(s):
    out = []
    for c in range(4):
        out += mix_column(s[4 * c:4 * c + 4])
    return out


def add_round_key(s, k):
    return [a ^ b for a, b in zip(s, k)]


def rot_word(w):        # w as 4 bytes [a0, a1, a2, a3]
    return w[1:] + w[:1]


def sub_word(w):
    return [SBOX[b] for b in w]


def rcon(i):
    """Round constant byte for round i (1-based): x^(i-1) in GF(2^8)."""
    r = 1
    for _ in range(i - 1):
        r = xtime(r)
    return r


# ---------------------------------------------------------------------------
# Register <-> state packing (spec register layout, little-endian bytes)
# ---------------------------------------------------------------------------
def u64_to_bytes(x):
    return [(x >> (8 * i)) & 0xFF for i in range(8)]


def bytes_to_u64(b):
    return sum(v << (8 * i) for i, v in enumerate(b))


def regs_to_state(rs1, rs2):
    return u64_to_bytes(rs1) + u64_to_bytes(rs2)


# ---------------------------------------------------------------------------
# The four instructions
# ---------------------------------------------------------------------------
def aes64es(rs1, rs2):
    s = shift_rows(regs_to_state(rs1, rs2))
    return bytes_to_u64(sub_bytes(s)[0:8])


def aes64esm(rs1, rs2):
    s = sub_bytes(shift_rows(regs_to_state(rs1, rs2)))
    return bytes_to_u64(mix_columns(s)[0:8])     # columns 0, 1 = bytes 0..7


def aes_decode_rcon(rnum):
    # rnum 0..9 -> rcon of round rnum+1; 0xA -> 0 (Sail aes_decode_rcon)
    return 0 if rnum == 0xA else rcon(rnum + 1)


def aes64ks1i(rs1, rnum):
    if rnum > 0xA:
        raise IllegalInstruction(f"aes64ks1i rnum={rnum:#x} is reserved")
    tmp1 = (rs1 >> 32) & MASK32
    tmp2 = tmp1 if rnum == 0xA else ((tmp1 >> 8) | (tmp1 << 24)) & MASK32   # ror32
    w = u64_to_bytes(tmp2)[0:4]
    tmp3 = bytes_to_u64(sub_word(w))
    word = tmp3 ^ aes_decode_rcon(rnum)
    return (word << 32) | word


def aes64ks2(rs1, rs2):
    w0 = ((rs1 >> 32) ^ rs2) & MASK32
    w1 = ((rs1 >> 32) ^ rs2 ^ (rs2 >> 32)) & MASK32
    return (w1 << 32) | w0


OPS = {
    "aes64es": lambda rs1, rs2, rnum: aes64es(rs1, rs2),
    "aes64esm": lambda rs1, rs2, rnum: aes64esm(rs1, rs2),
    "aes64ks1i": lambda rs1, rs2, rnum: aes64ks1i(rs1, rnum),
    "aes64ks2": lambda rs1, rs2, rnum: aes64ks2(rs1, rs2),
}


# ---------------------------------------------------------------------------
# Reference AES-128 (FIPS-197 sections 5.1-5.2), textbook style
# ---------------------------------------------------------------------------
def key_expansion_128(key):
    w = [list(key[4 * i:4 * i + 4]) for i in range(4)]
    for i in range(4, 44):
        t = w[i - 1]
        if i % 4 == 0:
            t = sub_word(rot_word(t))
            t = [t[0] ^ rcon(i // 4)] + t[1:]
        w.append([a ^ b for a, b in zip(w[i - 4], t)])
    # round key r = words 4r..4r+3, as 16 bytes
    return [[b for j in range(4) for b in w[4 * r + j]] for r in range(11)]


def aes128_encrypt(key, pt):
    rk = key_expansion_128(key)
    s = add_round_key(list(pt), rk[0])
    for r in range(1, 10):
        s = add_round_key(mix_columns(shift_rows(sub_bytes(s))), rk[r])
    return add_round_key(shift_rows(sub_bytes(s)), rk[10])


# ---------------------------------------------------------------------------
# AES-128 through the instructions, the way software uses them
# ---------------------------------------------------------------------------
def aes128_key_schedule_zkne(key):
    lo, hi = bytes_to_u64(key[0:8]), bytes_to_u64(key[8:16])
    rks = [(lo, hi)]
    for rnum in range(10):
        t = aes64ks1i(hi, rnum)
        lo = aes64ks2(t, lo)
        hi = aes64ks2(lo, hi)
        rks.append((lo, hi))
    return rks


def aes128_encrypt_zkne(key, pt):
    rks = aes128_key_schedule_zkne(key)
    s0 = bytes_to_u64(pt[0:8]) ^ rks[0][0]
    s1 = bytes_to_u64(pt[8:16]) ^ rks[0][1]
    for r in range(1, 10):
        s0, s1 = aes64esm(s0, s1) ^ rks[r][0], aes64esm(s1, s0) ^ rks[r][1]
    s0, s1 = aes64es(s0, s1) ^ rks[10][0], aes64es(s1, s0) ^ rks[10][1]
    return u64_to_bytes(s0) + u64_to_bytes(s1)


# ---------------------------------------------------------------------------
def selftest():
    # FIPS-197 Figure 7 spot checks
    assert SBOX[0x00] == 0x63 and SBOX[0x01] == 0x7C and SBOX[0x53] == 0xED
    assert SBOX[0xFF] == 0x16 and sorted(SBOX) == list(range(256))
    # FIPS-197 Appendix C.1
    key = bytes(range(16))
    pt = bytes.fromhex("00112233445566778899aabbccddeeff")
    ct = bytes.fromhex("69c4e0d86a7b0430d8cdb78070b4c55a")
    assert bytes(aes128_encrypt(key, pt)) == ct, "textbook AES-128"
    assert bytes(aes128_encrypt_zkne(key, pt)) == ct, "AES-128 via Zkne model"
    # FIPS-197 Appendix A.1 round key 10 (key 2b7e1516...)
    k = bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")
    lo, hi = aes128_key_schedule_zkne(k)[10]
    assert bytes(u64_to_bytes(lo) + u64_to_bytes(hi)) == bytes.fromhex(
        "d014f9a8c9ee2589e13f0cc8b6630ca6")
    try:
        aes64ks1i(0, 0xB)
        raise AssertionError("rnum 0xB accepted")
    except IllegalInstruction:
        pass
    return "golden model self-test passed (S-box, FIPS-197 C.1 both ways, A.1 key schedule)"


if __name__ == "__main__":
    if sys.argv[1:] == ["selftest"]:
        print(selftest())
    else:
        sys.exit(__doc__)
