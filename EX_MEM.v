module EX_MEM (
    input clk,
    input reset,

    input [63:0] alu_result_in,
    input [63:0] rs2_data_in,
    input [4:0] rd_in,

    input RegWrite_in,
    input MemRead_in,
    input MemWrite_in,
    input MemtoReg_in,
    input Branch_in,

    output reg [63:0] alu_result_out,
    output reg [63:0] rs2_data_out,
    output reg [4:0] rd_out,

    output reg RegWrite_out,
    output reg MemRead_out,
    output reg MemWrite_out,
    output reg MemtoReg_out,
    output reg Branch_out
);

always @(posedge clk or posedge reset)
begin
    if (reset) begin
        alu_result_out <= 64'd0;
        rs2_data_out <= 64'd0;
        rd_out <= 5'd0;

        RegWrite_out <= 0;
        MemRead_out <= 0;
        MemWrite_out <= 0;
        MemtoReg_out <= 0;
        Branch_out <= 0;
    end
    else begin
        alu_result_out <= alu_result_in;
        rs2_data_out <= rs2_data_in;
        rd_out <= rd_in;

        RegWrite_out <= RegWrite_in;
        MemRead_out <= MemRead_in;
        MemWrite_out <= MemWrite_in;
        MemtoReg_out <= MemtoReg_in;
        Branch_out <= Branch_in;
    end
end

endmodule