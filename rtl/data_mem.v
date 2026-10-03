`timescale 1ns/1ps

// Data memory: BYTES bytes, little-endian (ld/sd: the byte at the lowest
// address is bits [7:0]). Decoded from the low address bits only; byte
// indices wrap modulo BYTES, so nothing is read or written past the end.
//
// Initial contents: zero, then +DMEM=<file> if given ($readmemh format,
// same image as instruction_mem). Reset does not clear the memory (like
// an SRAM; there is no reset port), so the image loaded at time 0
// survives reset.
module data_mem #(
    parameter BYTES = 65536
) (
    input clk,
    input [63:0] address,
    input [63:0] write_data,
    input MemRead,
    input MemWrite,
    output [63:0] read_data
);

    localparam AW = $clog2(BYTES);

    reg [7:0] mem [0:BYTES-1];

    localparam [AW-1:0] OFF1 = 1, OFF2 = 2, OFF3 = 3, OFF4 = 4,
                        OFF5 = 5, OFF6 = 6, OFF7 = 7;

    // Byte addresses of the 8 bytes of a doubleword access.
    wire [AW-1:0] a0 = address[AW-1:0];
    wire [AW-1:0] a1 = a0 + OFF1;
    wire [AW-1:0] a2 = a0 + OFF2;
    wire [AW-1:0] a3 = a0 + OFF3;
    wire [AW-1:0] a4 = a0 + OFF4;
    wire [AW-1:0] a5 = a0 + OFF5;
    wire [AW-1:0] a6 = a0 + OFF6;
    wire [AW-1:0] a7 = a0 + OFF7;

    integer i;
    reg [8*256-1:0] dmem_file;   // initial data image path (simulation only)

    initial begin
        for (i = 0; i < BYTES; i = i + 1)
            mem[i] = 8'b0;
        if ($value$plusargs("DMEM=%s", dmem_file))
            $readmemh(dmem_file, mem);
    end

    // STORE (MEM stage): little-endian 64-bit store
    always @(posedge clk) begin
        if (MemWrite) begin   // EX_MEM holds MemWrite low during reset
            mem[a0] <= write_data[7:0];
            mem[a1] <= write_data[15:8];
            mem[a2] <= write_data[23:16];
            mem[a3] <= write_data[31:24];
            mem[a4] <= write_data[39:32];
            mem[a5] <= write_data[47:40];
            mem[a6] <= write_data[55:48];
            mem[a7] <= write_data[63:56];
        end
    end

    // LOAD (combinational so MEM/WB can capture next cycle): little-endian
    assign read_data = MemRead ? {mem[a7], mem[a6], mem[a5], mem[a4],
                                  mem[a3], mem[a2], mem[a1], mem[a0]}
                               : 64'b0;

endmodule
