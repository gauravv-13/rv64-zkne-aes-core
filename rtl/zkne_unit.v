`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// zkne_unit - RISC-V Zkne (AES encryption) instructions for RV64.
//
// Follows the Sail code of the ratified Scalar Crypto spec v1.0.1 and
// Spike's riscv/insns/aes64{es,esm,ks1i,ks2}.h bit for bit:
//
//   aes64es   rd = SubBytes(ShiftRows(rs2:rs1)[63:0])            (final round)
//   aes64esm  rd = MixColumns(SubBytes(ShiftRows(rs2:rs1)[63:0])) (middle round)
//   aes64ks1i rd = {w, w}, w = SubWord(rnum == 0xA ? rs1[63:32]
//                                    : ror32(rs1[63:32], 8)) ^ rcon(rnum)
//   aes64ks2  rd = {w1, w0}, w0 = rs1[63:32] ^ rs2[31:0], w1 = w0 ^ rs2[63:32]
//
// No AddRoundKey: software xors the round key.
//
// Register layout (spec): the 16-byte AES state s[0..15] is column-major
// (s[4c+r] = row r, column c). s[0..7] (columns 0, 1) is in rs1 and
// s[8..15] (columns 2, 3) in rs2, with byte i of a register in bits
// [8i+7:8i]. aes64es/aes64esm return output bytes 0..7 (columns 0, 1);
// software gets bytes 8..15 by swapping rs1 and rs2.
//
// Purely combinational: single cycle, fixed latency, and no data-dependent
// timing (Zkt).
//
// Operand isolation: unless a Zkne instruction is in EX (valid), every
// operand input is forced to zero, so the AES nets do not toggle with
// ordinary ALU traffic. rs2 and rnum are also zeroed for the instructions
// that do not use them.
//
// One S-box layer of 8 aes_sbox instances is shared: aes64es/aes64esm
// use all 8, aes64ks1i uses bytes 0..3 (the inputs of bytes 4..7 are 0).
// ---------------------------------------------------------------------------
module zkne_unit (
    input         valid,     // a (legal) Zkne instruction is in EX
    input  [1:0]  op,        // ZKNE_ES / ZKNE_ESM / ZKNE_KS1I / ZKNE_KS2
    input  [63:0] rs1,
    input  [63:0] rs2,
    input  [3:0]  rnum,      // aes64ks1i round number, 0x0..0xA
    output [63:0] result
);

    localparam [1:0] ZKNE_ES   = 2'b00;
    localparam [1:0] ZKNE_ESM  = 2'b01;
    localparam [1:0] ZKNE_KS1I = 2'b10;
    localparam [1:0] ZKNE_KS2  = 2'b11;

    wire is_es   = valid && (op == ZKNE_ES);
    wire is_esm  = valid && (op == ZKNE_ESM);
    wire is_ks1i = valid && (op == ZKNE_KS1I);
    wire is_ks2  = valid && (op == ZKNE_KS2);
    wire is_round = is_es | is_esm;

    // -----------------------------------------------------------------
    // Operand isolation
    // -----------------------------------------------------------------
    wire [63:0] a    = valid               ? rs1  : 64'b0;
    wire [63:0] b    = (is_round | is_ks2) ? rs2  : 64'b0;
    wire [3:0]  rn   = is_ks1i             ? rnum : 4'b0;

    // -----------------------------------------------------------------
    // ShiftRows: output bytes 0..7 of ShiftRows of the state {b, a}.
    // Output byte s'[4c+r] = s[4((c+r) mod 4) + r], for c = 0, 1:
    //   s'0=s0  s'1=s5  s'2=s10 s'3=s15 | s'4=s4  s'5=s9  s'6=s14 s'7=s3
    // (s0..s7 = a bytes 0..7, s8..s15 = b bytes 0..7)
    // -----------------------------------------------------------------
    wire [63:0] sr = {a[31:24],     // s'7 = s3
                      b[55:48],     // s'6 = s14
                      b[15:8],      // s'5 = s9
                      a[39:32],     // s'4 = s4
                      b[63:56],     // s'3 = s15
                      b[23:16],     // s'2 = s10
                      a[47:40],     // s'1 = s5
                      a[7:0]};      // s'0 = s0

    // -----------------------------------------------------------------
    // aes64ks1i word: rs1[63:32], rotated right by 8 unless rnum == 0xA
    // -----------------------------------------------------------------
    wire [31:0] ks_w   = a[63:32];
    wire [31:0] ks_rot = (rn == 4'hA) ? ks_w : {ks_w[7:0], ks_w[31:8]};

    // -----------------------------------------------------------------
    // S-box layer (SubBytes / SubWord)
    // -----------------------------------------------------------------
    wire [63:0] sb_in = is_round ? sr :
                        is_ks1i  ? {32'b0, ks_rot} :
                                   64'b0;
    wire [63:0] sb_out;

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : sbox
            aes_sbox u_sbox (.in(sb_in[8*i +: 8]), .out(sb_out[8*i +: 8]));
        end
    endgenerate

    // -----------------------------------------------------------------
    // MixColumns on each 32-bit column of sb_out (bytes x0..x3 = rows 0..3)
    //   y0 = 2x0 ^ 3x1 ^  x2 ^  x3
    //   y1 =  x0 ^ 2x1 ^ 3x2 ^  x3
    //   y2 =  x0 ^  x1 ^ 2x2 ^ 3x3
    //   y3 = 3x0 ^  x1 ^  x2 ^ 2x3
    // 2x = xtime(x) (multiply by 2 in GF(2^8) mod x^8+x^4+x^3+x+1); 3x = 2x ^ x
    // -----------------------------------------------------------------
    wire [63:0] mc;

    genvar c;
    generate
        for (c = 0; c < 2; c = c + 1) begin : mixcol
            wire [7:0] x0 = sb_out[32*c +  0 +: 8];
            wire [7:0] x1 = sb_out[32*c +  8 +: 8];
            wire [7:0] x2 = sb_out[32*c + 16 +: 8];
            wire [7:0] x3 = sb_out[32*c + 24 +: 8];

            wire [7:0] t0 = {x0[6:0], 1'b0} ^ (x0[7] ? 8'h1b : 8'h00);   // 2*x0
            wire [7:0] t1 = {x1[6:0], 1'b0} ^ (x1[7] ? 8'h1b : 8'h00);   // 2*x1
            wire [7:0] t2 = {x2[6:0], 1'b0} ^ (x2[7] ? 8'h1b : 8'h00);   // 2*x2
            wire [7:0] t3 = {x3[6:0], 1'b0} ^ (x3[7] ? 8'h1b : 8'h00);   // 2*x3

            wire [7:0] y0 = t0 ^ (t1 ^ x1) ^ x2 ^ x3;
            wire [7:0] y1 = x0 ^ t1 ^ (t2 ^ x2) ^ x3;
            wire [7:0] y2 = x0 ^ x1 ^ t2 ^ (t3 ^ x3);
            wire [7:0] y3 = (t0 ^ x0) ^ x1 ^ x2 ^ t3;

            assign mc[32*c +: 32] = {y3, y2, y1, y0};
        end
    endgenerate

    // -----------------------------------------------------------------
    // aes64ks1i: round constant (0xA -> 0; 0xB..0xF are reserved and
    // decoded as illegal before they get here)
    // -----------------------------------------------------------------
    reg [7:0] rcon;
    always @(*) begin
        case (rn)
            4'h0: rcon = 8'h01;
            4'h1: rcon = 8'h02;
            4'h2: rcon = 8'h04;
            4'h3: rcon = 8'h08;
            4'h4: rcon = 8'h10;
            4'h5: rcon = 8'h20;
            4'h6: rcon = 8'h40;
            4'h7: rcon = 8'h80;
            4'h8: rcon = 8'h1b;
            4'h9: rcon = 8'h36;
            default: rcon = 8'h00;
        endcase
    end

    wire [31:0] ks1_word = sb_out[31:0] ^ {24'b0, rcon};

    // -----------------------------------------------------------------
    // aes64ks2
    // -----------------------------------------------------------------
    wire [31:0] ks2_w0 = a[63:32] ^ b[31:0];
    wire [31:0] ks2_w1 = ks2_w0 ^ b[63:32];

    // -----------------------------------------------------------------
    // Result
    // -----------------------------------------------------------------
    assign result = is_es   ? sb_out :
                    is_esm  ? mc :
                    is_ks1i ? {ks1_word, ks1_word} :
                    is_ks2  ? {ks2_w1, ks2_w0} :
                              64'b0;

endmodule
