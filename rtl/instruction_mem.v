`timescale 1ns/1ps

// Instruction memory: BYTES bytes, little-endian (the byte at the lowest
// address is instruction bits [7:0]). Decoded from the low address bits
// only, so the same image works at any BYTES-aligned base (0 or
// 0x80000000). Byte indices wrap modulo BYTES; nothing is read past the end.
//
// Image: +IMEM=<file> (default instructions.txt), read with $readmemh:
// one byte per entry, optional @<byte offset> lines (objcopy -O verilog).
module instruction_mem #(
    parameter BYTES = 65536
) (
    input [63:0] addr,
    output [31:0] instr
);

    localparam AW = $clog2(BYTES);

    reg [7:0] mem [0:BYTES-1];
    integer i;
    reg [8*256-1:0] imem_file;   // program image path (simulation only)

    initial begin
        for (i = 0; i < BYTES; i = i + 1)
            mem[i] = 8'b0;

        if (!$value$plusargs("IMEM=%s", imem_file))
            imem_file = "instructions.txt";
        $readmemh(imem_file, mem);
    end

    localparam [AW-1:0] OFF1 = 1, OFF2 = 2, OFF3 = 3;

    wire [AW-1:0] a0 = addr[AW-1:0];
    wire [AW-1:0] a1 = a0 + OFF1;
    wire [AW-1:0] a2 = a0 + OFF2;
    wire [AW-1:0] a3 = a0 + OFF3;

    assign instr = {mem[a3], mem[a2], mem[a1], mem[a0]};

endmodule
