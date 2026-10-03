`timescale 1ns/1ps

// IF/ID pipeline register. On reset and flush it holds a canonical NOP
// (addi x0,x0,0), not 0x00000000, which is an illegal instruction.
module IF_ID (
    input clk,
    input reset,
    input write_enable,
    input flush,

    input [63:0] pc_in,
    input [31:0] instr_in,

    output reg [63:0] pc_out,
    output reg [31:0] instr_out
);

localparam [31:0] NOP = 32'h0000_0013;

always @(posedge clk or posedge reset)
begin
    if (reset) begin
        pc_out <= 64'd0;
        instr_out <= NOP;
    end

    else if (flush) begin
        pc_out <= 64'd0;
        instr_out <= NOP;
    end

    else if (write_enable) begin
        pc_out <= pc_in;
        instr_out <= instr_in;
    end

end

endmodule
