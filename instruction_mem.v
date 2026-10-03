`define IMEM_SIZE 4096

module instruction_mem (
    input [63:0] addr,
    output [31:0] instr
);

    reg [7:0] mem [0:`IMEM_SIZE-1]; 
    integer i, file, status;
    reg [7:0] line_data;

    initial begin
    
        for (i = 0; i < `IMEM_SIZE; i = i + 1)
            mem[i] = 8'b0;

        file = $fopen("instructions.txt", "r");
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