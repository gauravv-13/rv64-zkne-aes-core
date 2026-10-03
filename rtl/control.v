`timescale 1ns/1ps

// Main decoder. Only the encodings listed here are implemented; every
// other encoding sets illegal_instr (no silent fallbacks):
//   OP      (0110011): add, sub, and, or, xor,
//                      aes64es, aes64esm, aes64ks2 (Zkne)
//   OP-IMM  (0010011): addi, aes64ks1i (Zkne; rnum 0xB..0xF are illegal)
//   LOAD    (0000011): ld          STORE (0100011): sd
//   BRANCH  (1100011): beq, bne
//   LUI     (0110111), AUIPC (0010111)
//   custom-0 (0001011): legacy aes_round64 (funct3=000, funct7=0000000),
//                       only when built with -DLEGACY_AES
// The core has no traps: an illegal instruction becomes a NOP (all control
// signals cleared: no register write, no memory access, no branch).
module control(
    input [6:0] opcode,
    input [2:0] funct3,
    input [6:0] funct7,
    input [4:0] rs2_field,      // instr[24:20]; for aes64ks1i {1'b1, rnum}

    output reg RegWrite,
    output reg MemRead,
    output reg MemWrite,
    output reg MemtoReg,
    output reg ALUSrc,
    output reg [1:0] ALUSrcA,   // ALU operand 1: 00 rs1, 01 PC, 10 zero
    output reg Branch,
    output reg [1:0] ALUOp,
    output reg Zkne,            // Zkne instruction: result from zkne_unit
    output reg illegal_instr
);

always @(*) begin

    RegWrite = 0;
    MemRead = 0;
    MemWrite = 0;
    MemtoReg = 0;
    ALUSrc = 0;
    ALUSrcA = 2'b00;
    Branch = 0;
    ALUOp = 2'b00;
    Zkne = 0;
    illegal_instr = 0;

    case(opcode)

        7'b0110011: begin
            RegWrite = 1;
            ALUSrc = 0;
            MemtoReg = 0;
            ALUOp = 2'b10;
            case ({funct7, funct3})
                {7'b0000000, 3'b000},       // add
                {7'b0100000, 3'b000},       // sub
                {7'b0000000, 3'b111},       // and
                {7'b0000000, 3'b110},       // or
                {7'b0000000, 3'b100}: ;     // xor
                {7'b0011001, 3'b000},       // aes64es
                {7'b0011011, 3'b000},       // aes64esm
                {7'b0111111, 3'b000}:       // aes64ks2
                    Zkne = 1;
                default: illegal_instr = 1;
            endcase
        end

        7'b0010011: begin
            RegWrite = 1;
            ALUSrc = 1;
            MemtoReg = 0;
            ALUOp = 2'b00;
            if (funct3 == 3'b000)
                ;                           // addi
            else if (funct3 == 3'b001 && funct7 == 7'b0011000 && rs2_field[4]) begin
                Zkne = 1;                   // aes64ks1i: instr[31:24] = 00110001
                if (rs2_field[3:0] > 4'hA)  // rnum 0xB..0xF reserved
                    illegal_instr = 1;
            end
            else
                illegal_instr = 1;
        end

        7'b0000011: begin
            RegWrite = 1;
            MemRead = 1;
            MemtoReg = 1;
            ALUSrc = 1;
            ALUOp = 2'b00;
            if (funct3 != 3'b011)           // ld only
                illegal_instr = 1;
        end

        7'b0100011: begin
            MemWrite = 1;
            ALUSrc = 1;
            ALUOp = 2'b00;
            if (funct3 != 3'b011)           // sd only
                illegal_instr = 1;
        end

        7'b1100011: begin
            Branch = 1;
            ALUOp = 2'b01;
            if (funct3 != 3'b000 && funct3 != 3'b001)   // beq, bne only
                illegal_instr = 1;
        end
        7'b0110111: begin              // lui: rd = imm
            RegWrite = 1;
            ALUSrc   = 1;
            ALUSrcA  = 2'b10;
            ALUOp    = 2'b00;
        end

        7'b0010111: begin              // auipc: rd = pc + imm
            RegWrite = 1;
            ALUSrc   = 1;
            ALUSrcA  = 2'b01;
            ALUOp    = 2'b00;
        end

`ifdef LEGACY_AES
        7'b0001011: begin              // custom-0, your AES round instruction
            RegWrite = 1;
            ALUSrc   = 0;               // operand2 = rs2 (round key), not immediate
            MemtoReg = 0;
            ALUOp    = 2'b11;           // new ALUOp code, unused until now
            if (funct3 != 3'b000 || funct7 != 7'b0000000)
                illegal_instr = 1;
        end
`endif

        default: begin
            illegal_instr = 1;
        end

    endcase

    if (illegal_instr) begin
        RegWrite = 0;
        MemRead  = 0;
        MemWrite = 0;
        MemtoReg = 0;
        ALUSrc   = 0;
        ALUSrcA  = 2'b00;
        Branch   = 0;
        ALUOp    = 2'b00;
        Zkne     = 0;
    end
end

endmodule
