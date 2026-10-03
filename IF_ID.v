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

always @(posedge clk or posedge reset)
begin
    if (reset) begin
        pc_out <= 64'd0;
        instr_out <= 32'd0;
    end

    else if (flush) begin
        pc_out <= 64'd0;
        instr_out <= 32'd0;
    end

    else if (write_enable) begin
        pc_out <= pc_in;
        instr_out <= instr_in;
    end

end

endmodule