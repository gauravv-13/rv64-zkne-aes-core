`timescale 1ns/1ps

// Main decoder. Only the encodings listed here are implemented; every
// other encoding sets illegal_instr (no silent fallbacks):
//   OP      (0110011): add, sub, and, or, xor
//   OP-IMM  (0010011): addi
//   LOAD    (0000011): ld          STORE (0100011): sd
//   BRANCH  (1100011): beq, bne
//   LUI     (0110111), AUIPC (0010111)
//   custom-0 (0001011): legacy aes_round64 (funct3=000, funct7=0000000)
module control(
    input [6:0] opcode,
    input [2:0] funct3,
    input [6:0] funct7,

    output reg RegWrite,
    output reg MemRead,
    output reg MemWrite,
    output reg MemtoReg,
    output reg ALUSrc,
    output reg [1:0] ALUSrcA,   // ALU operand 1: 00 rs1, 01 PC, 10 zero
    output reg Branch,
    output reg [1:0] ALUOp,
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
                default: illegal_instr = 1;
            endcase
        end

        7'b0010011: begin
            RegWrite = 1;
            ALUSrc = 1;
            MemtoReg = 0;
            ALUOp = 2'b00;
            if (funct3 != 3'b000)           // addi only
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

        7'b0001011: begin              // custom-0, your AES round instruction
            RegWrite = 1;
            ALUSrc   = 0;               // operand2 = rs2 (round key), not immediate
            MemtoReg = 0;
            ALUOp    = 2'b11;           // new ALUOp code, unused until now
            if (funct3 != 3'b000 || funct7 != 7'b0000000)
                illegal_instr = 1;
        end

        default: begin
            illegal_instr = 1;
        end

    endcase
end

endmodule
