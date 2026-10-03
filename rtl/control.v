`timescale 1ns/1ps

module control(
    input [6:0] opcode,

    output reg RegWrite,
    output reg MemRead,
    output reg MemWrite,
    output reg MemtoReg,
    output reg ALUSrc,
    output reg [1:0] ALUSrcA,   // ALU operand 1: 00 rs1, 01 PC, 10 zero
    output reg Branch,
    output reg [1:0] ALUOp
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

    case(opcode)

        7'b0110011: begin
            RegWrite = 1;
            ALUSrc = 0;
            MemtoReg = 0;
            ALUOp = 2'b10;
        end

        7'b0010011: begin
            RegWrite = 1;
            ALUSrc = 1;
            MemtoReg = 0;
            ALUOp = 2'b00;
        end

        7'b0000011: begin
            RegWrite = 1;
            MemRead = 1;
            MemtoReg = 1;
            ALUSrc = 1;
            ALUOp = 2'b00;
        end

        7'b0100011: begin
            MemWrite = 1;
            ALUSrc = 1;
            ALUOp = 2'b00;
        end

        7'b1100011: begin
            Branch = 1;
            ALUOp = 2'b01;
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
        end

        default: begin
        end

    endcase
end

endmodule
