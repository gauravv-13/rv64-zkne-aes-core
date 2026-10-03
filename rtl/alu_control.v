`timescale 1ns/1ps

module alu_control(
    input [1:0] ALUOp,
    input funct7,               // instr[30]: add / sub
    input [2:0] funct3,
    output reg [3:0] ALUControl
);

always @(*) begin
    case(ALUOp)
        2'b00: ALUControl = 4'b0010;
        2'b01: ALUControl = 4'b0110;
        2'b10: begin
            case(funct3)
                3'b000: begin
                    if (funct7 == 1'b0)
                        ALUControl = 4'b0010;
                    else
                        ALUControl = 4'b0110;
                end
                3'b111: ALUControl = 4'b0000;
                3'b110: ALUControl = 4'b0001;
                3'b100: ALUControl = 4'b0011;   // xor
                default: ALUControl = 4'b0000;
            endcase
        end
`ifdef LEGACY_AES
        2'b11: ALUControl = 4'b1000;   // AES round
`endif
        default: ALUControl = 4'b0000;
    endcase
end

endmodule
