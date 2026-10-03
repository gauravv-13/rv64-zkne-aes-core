`timescale 1ns/1ps

`define IMEM_SIZE 4096

module instruction_mem (
    input [63:0] addr,
    output [31:0] instr
);

    reg [7:0] mem [0:`IMEM_SIZE-1]; 
    integer i, file, status;
    reg [7:0] line_data;
    reg [8*256-1:0] imem_file;   // program image path (simulation only)

    initial begin
    
        for (i = 0; i < `IMEM_SIZE; i = i + 1)
            mem[i] = 8'b0;

        if (!$value$plusargs("IMEM=%s", imem_file))
            imem_file = "instructions.txt";
        file = $fopen(imem_file, "r");
        if (file) begin
            i = 0;
            while (!$feof(file) && i < `IMEM_SIZE) begin
                status = $fscanf(file, "%h\n", line_data);
                if (status == 1) begin
                    mem[i] = line_data;
                    i = i + 1;
                end
            end
            $fclose(file);
        end
    end
    
    assign instr = {mem[addr], mem[addr+1], mem[addr+2], mem[addr+3]};

endmodule
