`timescale 1ns/1ps

// -----------------------------------------------------------------------
// aes_round64
//
// Single-cycle, purely combinational 64-bit AES round.
//   input1 = state      (rs1)
//   input2 = round key  (rs2)
//   result = scrambled cipher output (rd)
//
// Mirrors the Spike golden model exactly:
//   Step A: SubBytes   - AES S-box applied to each of the 8 state bytes
//   Step B: ShiftRows  - swap byte1<->byte5 and byte3<->byte7, then
//                         regroup into two 4-byte columns
//   Step C: MixColumns - standard AES column-mix matrix, applied to
//                         each of the two 32-bit columns independently
//   Step D: AddRoundKey - XOR with the 64-bit round key
// -----------------------------------------------------------------------
module aes_round64(
    input  [63:0] input1,
    input  [63:0] input2,
    output [63:0] result
);

    // ---------------------------------------------------------------
    // AES S-Box (256 x 8-bit lookup table)
    // ---------------------------------------------------------------
    reg [7:0] SBOX [0:255];

    initial begin
        SBOX[8'h00]=8'h63; SBOX[8'h01]=8'h7c; SBOX[8'h02]=8'h77; SBOX[8'h03]=8'h7b;
        SBOX[8'h04]=8'hf2; SBOX[8'h05]=8'h6b; SBOX[8'h06]=8'h6f; SBOX[8'h07]=8'hc5;
        SBOX[8'h08]=8'h30; SBOX[8'h09]=8'h01; SBOX[8'h0a]=8'h67; SBOX[8'h0b]=8'h2b;
        SBOX[8'h0c]=8'hfe; SBOX[8'h0d]=8'hd7; SBOX[8'h0e]=8'hab; SBOX[8'h0f]=8'h76;
        SBOX[8'h10]=8'hca; SBOX[8'h11]=8'h82; SBOX[8'h12]=8'hc9; SBOX[8'h13]=8'h7d;
        SBOX[8'h14]=8'hfa; SBOX[8'h15]=8'h59; SBOX[8'h16]=8'h47; SBOX[8'h17]=8'hf0;
        SBOX[8'h18]=8'had; SBOX[8'h19]=8'hd4; SBOX[8'h1a]=8'ha2; SBOX[8'h1b]=8'haf;
        SBOX[8'h1c]=8'h9c; SBOX[8'h1d]=8'ha4; SBOX[8'h1e]=8'h72; SBOX[8'h1f]=8'hc0;
        SBOX[8'h20]=8'hb7; SBOX[8'h21]=8'hfd; SBOX[8'h22]=8'h93; SBOX[8'h23]=8'h26;
        SBOX[8'h24]=8'h36; SBOX[8'h25]=8'h3f; SBOX[8'h26]=8'hf7; SBOX[8'h27]=8'hcc;
        SBOX[8'h28]=8'h34; SBOX[8'h29]=8'ha5; SBOX[8'h2a]=8'he5; SBOX[8'h2b]=8'hf1;
        SBOX[8'h2c]=8'h71; SBOX[8'h2d]=8'hd8; SBOX[8'h2e]=8'h31; SBOX[8'h2f]=8'h15;
        SBOX[8'h30]=8'h04; SBOX[8'h31]=8'hc7; SBOX[8'h32]=8'h23; SBOX[8'h33]=8'hc3;
        SBOX[8'h34]=8'h18; SBOX[8'h35]=8'h96; SBOX[8'h36]=8'h05; SBOX[8'h37]=8'h9a;
        SBOX[8'h38]=8'h07; SBOX[8'h39]=8'h12; SBOX[8'h3a]=8'h80; SBOX[8'h3b]=8'he2;
        SBOX[8'h3c]=8'heb; SBOX[8'h3d]=8'h27; SBOX[8'h3e]=8'hb2; SBOX[8'h3f]=8'h75;
        SBOX[8'h40]=8'h09; SBOX[8'h41]=8'h83; SBOX[8'h42]=8'h2c; SBOX[8'h43]=8'h1a;
        SBOX[8'h44]=8'h1b; SBOX[8'h45]=8'h6e; SBOX[8'h46]=8'h5a; SBOX[8'h47]=8'ha0;
        SBOX[8'h48]=8'h52; SBOX[8'h49]=8'h3b; SBOX[8'h4a]=8'hd6; SBOX[8'h4b]=8'hb3;
        SBOX[8'h4c]=8'h29; SBOX[8'h4d]=8'he3; SBOX[8'h4e]=8'h2f; SBOX[8'h4f]=8'h84;
        SBOX[8'h50]=8'h53; SBOX[8'h51]=8'hd1; SBOX[8'h52]=8'h00; SBOX[8'h53]=8'hed;
        SBOX[8'h54]=8'h20; SBOX[8'h55]=8'hfc; SBOX[8'h56]=8'hb1; SBOX[8'h57]=8'h5b;
        SBOX[8'h58]=8'h6a; SBOX[8'h59]=8'hcb; SBOX[8'h5a]=8'hbe; SBOX[8'h5b]=8'h39;
        SBOX[8'h5c]=8'h4a; SBOX[8'h5d]=8'h4c; SBOX[8'h5e]=8'h58; SBOX[8'h5f]=8'hcf;
        SBOX[8'h60]=8'hd0; SBOX[8'h61]=8'hef; SBOX[8'h62]=8'haa; SBOX[8'h63]=8'hfb;
        SBOX[8'h64]=8'h43; SBOX[8'h65]=8'h4d; SBOX[8'h66]=8'h33; SBOX[8'h67]=8'h85;
        SBOX[8'h68]=8'h45; SBOX[8'h69]=8'hf9; SBOX[8'h6a]=8'h02; SBOX[8'h6b]=8'h7f;
        SBOX[8'h6c]=8'h50; SBOX[8'h6d]=8'h3c; SBOX[8'h6e]=8'h9f; SBOX[8'h6f]=8'ha8;
        SBOX[8'h70]=8'h51; SBOX[8'h71]=8'ha3; SBOX[8'h72]=8'h40; SBOX[8'h73]=8'h8f;
        SBOX[8'h74]=8'h92; SBOX[8'h75]=8'h9d; SBOX[8'h76]=8'h38; SBOX[8'h77]=8'hf5;
        SBOX[8'h78]=8'hbc; SBOX[8'h79]=8'hb6; SBOX[8'h7a]=8'hda; SBOX[8'h7b]=8'h21;
        SBOX[8'h7c]=8'h10; SBOX[8'h7d]=8'hff; SBOX[8'h7e]=8'hf3; SBOX[8'h7f]=8'hd2;
        SBOX[8'h80]=8'hcd; SBOX[8'h81]=8'h0c; SBOX[8'h82]=8'h13; SBOX[8'h83]=8'hec;
        SBOX[8'h84]=8'h5f; SBOX[8'h85]=8'h97; SBOX[8'h86]=8'h44; SBOX[8'h87]=8'h17;
        SBOX[8'h88]=8'hc4; SBOX[8'h89]=8'ha7; SBOX[8'h8a]=8'h7e; SBOX[8'h8b]=8'h3d;
        SBOX[8'h8c]=8'h64; SBOX[8'h8d]=8'h5d; SBOX[8'h8e]=8'h19; SBOX[8'h8f]=8'h73;
        SBOX[8'h90]=8'h60; SBOX[8'h91]=8'h81; SBOX[8'h92]=8'h4f; SBOX[8'h93]=8'hdc;
        SBOX[8'h94]=8'h22; SBOX[8'h95]=8'h2a; SBOX[8'h96]=8'h90; SBOX[8'h97]=8'h88;
        SBOX[8'h98]=8'h46; SBOX[8'h99]=8'hee; SBOX[8'h9a]=8'hb8; SBOX[8'h9b]=8'h14;
        SBOX[8'h9c]=8'hde; SBOX[8'h9d]=8'h5e; SBOX[8'h9e]=8'h0b; SBOX[8'h9f]=8'hdb;
        SBOX[8'ha0]=8'he0; SBOX[8'ha1]=8'h32; SBOX[8'ha2]=8'h3a; SBOX[8'ha3]=8'h0a;
        SBOX[8'ha4]=8'h49; SBOX[8'ha5]=8'h06; SBOX[8'ha6]=8'h24; SBOX[8'ha7]=8'h5c;
        SBOX[8'ha8]=8'hc2; SBOX[8'ha9]=8'hd3; SBOX[8'haa]=8'hac; SBOX[8'hab]=8'h62;
        SBOX[8'hac]=8'h91; SBOX[8'had]=8'h95; SBOX[8'hae]=8'he4; SBOX[8'haf]=8'h79;
        SBOX[8'hb0]=8'he7; SBOX[8'hb1]=8'hc8; SBOX[8'hb2]=8'h37; SBOX[8'hb3]=8'h6d;
        SBOX[8'hb4]=8'h8d; SBOX[8'hb5]=8'hd5; SBOX[8'hb6]=8'h4e; SBOX[8'hb7]=8'ha9;
        SBOX[8'hb8]=8'h6c; SBOX[8'hb9]=8'h56; SBOX[8'hba]=8'hf4; SBOX[8'hbb]=8'hea;
        SBOX[8'hbc]=8'h65; SBOX[8'hbd]=8'h7a; SBOX[8'hbe]=8'hae; SBOX[8'hbf]=8'h08;
        SBOX[8'hc0]=8'hba; SBOX[8'hc1]=8'h78; SBOX[8'hc2]=8'h25; SBOX[8'hc3]=8'h2e;
        SBOX[8'hc4]=8'h1c; SBOX[8'hc5]=8'ha6; SBOX[8'hc6]=8'hb4; SBOX[8'hc7]=8'hc6;
        SBOX[8'hc8]=8'he8; SBOX[8'hc9]=8'hdd; SBOX[8'hca]=8'h74; SBOX[8'hcb]=8'h1f;
        SBOX[8'hcc]=8'h4b; SBOX[8'hcd]=8'hbd; SBOX[8'hce]=8'h8b; SBOX[8'hcf]=8'h8a;
        SBOX[8'hd0]=8'h70; SBOX[8'hd1]=8'h3e; SBOX[8'hd2]=8'hb5; SBOX[8'hd3]=8'h66;
        SBOX[8'hd4]=8'h48; SBOX[8'hd5]=8'h03; SBOX[8'hd6]=8'hf6; SBOX[8'hd7]=8'h0e;
        SBOX[8'hd8]=8'h61; SBOX[8'hd9]=8'h35; SBOX[8'hda]=8'h57; SBOX[8'hdb]=8'hb9;
        SBOX[8'hdc]=8'h86; SBOX[8'hdd]=8'hc1; SBOX[8'hde]=8'h1d; SBOX[8'hdf]=8'h9e;
        SBOX[8'he0]=8'he1; SBOX[8'he1]=8'hf8; SBOX[8'he2]=8'h98; SBOX[8'he3]=8'h11;
        SBOX[8'he4]=8'h69; SBOX[8'he5]=8'hd9; SBOX[8'he6]=8'h8e; SBOX[8'he7]=8'h94;
        SBOX[8'he8]=8'h9b; SBOX[8'he9]=8'h1e; SBOX[8'hea]=8'h87; SBOX[8'heb]=8'he9;
        SBOX[8'hec]=8'hce; SBOX[8'hed]=8'h55; SBOX[8'hee]=8'h28; SBOX[8'hef]=8'hdf;
        SBOX[8'hf0]=8'h8c; SBOX[8'hf1]=8'ha1; SBOX[8'hf2]=8'h89; SBOX[8'hf3]=8'h0d;
        SBOX[8'hf4]=8'hbf; SBOX[8'hf5]=8'he6; SBOX[8'hf6]=8'h42; SBOX[8'hf7]=8'h68;
        SBOX[8'hf8]=8'h41; SBOX[8'hf9]=8'h99; SBOX[8'hfa]=8'h2d; SBOX[8'hfb]=8'h0f;
        SBOX[8'hfc]=8'hb0; SBOX[8'hfd]=8'h54; SBOX[8'hfe]=8'hbb; SBOX[8'hff]=8'h16;
    end

    // ---------------------------------------------------------------
    // GF(2^8) multiply-by-2 (xtime) and multiply-by-3, mod x^8+x^4+x^3+x+1
    // ---------------------------------------------------------------
    function [7:0] gf_mul2;
        input [7:0] x;
        begin
            gf_mul2 = {x[6:0], 1'b0} ^ (x[7] ? 8'h1B : 8'h00);
        end
    endfunction

    function [7:0] gf_mul3;
        input [7:0] x;
        begin
            gf_mul3 = gf_mul2(x) ^ x;
        end
    endfunction

    // ---------------------------------------------------------------
    // Step A: SubBytes -- apply S-box to each of the 8 bytes of state
    // byte i = input1[8*i +: 8]  (byte0 = LSB ... byte7 = MSB)
    // ---------------------------------------------------------------
    wire [7:0] sb0 = SBOX[input1[7:0]];
    wire [7:0] sb1 = SBOX[input1[15:8]];
    wire [7:0] sb2 = SBOX[input1[23:16]];
    wire [7:0] sb3 = SBOX[input1[31:24]];
    wire [7:0] sb4 = SBOX[input1[39:32]];
    wire [7:0] sb5 = SBOX[input1[47:40]];
    wire [7:0] sb6 = SBOX[input1[55:48]];
    wire [7:0] sb7 = SBOX[input1[63:56]];

    // ---------------------------------------------------------------
    // Step B: ShiftRows -- swap byte1<->byte5 and byte3<->byte7 on the
    // sub_state, then regroup into two 4-byte columns:
    //   col0 = { m3, m2, m1, m0 } = { sb7, sb2, sb5, sb0 }
    //   col1 = { m7, m6, m5, m4 } = { sb3, sb6, sb1, sb4 }
    // (a0 = LSB byte of the column, a3 = MSB byte)
    // ---------------------------------------------------------------
    wire [7:0] c0a0 = sb0;
    wire [7:0] c0a1 = sb5;
    wire [7:0] c0a2 = sb2;
    wire [7:0] c0a3 = sb7;

    wire [7:0] c1a0 = sb4;
    wire [7:0] c1a1 = sb1;
    wire [7:0] c1a2 = sb6;
    wire [7:0] c1a3 = sb3;

    // ---------------------------------------------------------------
    // Step C: MixColumns -- standard AES column-mix matrix,
    // applied independently to col0 and col1
    // ---------------------------------------------------------------
    wire [7:0] c0r0 = gf_mul2(c0a0) ^ gf_mul3(c0a1) ^ c0a2          ^ c0a3;
    wire [7:0] c0r1 = c0a0          ^ gf_mul2(c0a1) ^ gf_mul3(c0a2) ^ c0a3;
    wire [7:0] c0r2 = c0a0          ^ c0a1          ^ gf_mul2(c0a2) ^ gf_mul3(c0a3);
    wire [7:0] c0r3 = gf_mul3(c0a0) ^ c0a1          ^ c0a2          ^ gf_mul2(c0a3);

    wire [7:0] c1r0 = gf_mul2(c1a0) ^ gf_mul3(c1a1) ^ c1a2          ^ c1a3;
    wire [7:0] c1r1 = c1a0          ^ gf_mul2(c1a1) ^ gf_mul3(c1a2) ^ c1a3;
    wire [7:0] c1r2 = c1a0          ^ c1a1          ^ gf_mul2(c1a2) ^ gf_mul3(c1a3);
    wire [7:0] c1r3 = gf_mul3(c1a0) ^ c1a1          ^ c1a2          ^ gf_mul2(c1a3);

    wire [31:0] col0 = {c0r3, c0r2, c0r1, c0r0};
    wire [31:0] col1 = {c1r3, c1r2, c1r1, c1r0};

    wire [63:0] mixed_state = {col1, col0};

    // ---------------------------------------------------------------
    // Step D: AddRoundKey
    // ---------------------------------------------------------------
    assign result = mixed_state ^ input2;

endmodule
