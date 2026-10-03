module register_file(
    input clk,
    input reset,
    input [4:0] read_reg1,
    input [4:0] read_reg2,
    input [4:0] write_reg,
    input [63:0] write_data,
    input reg_write_en,
    output [63:0] read_data1,
    output [63:0] read_data2
);

reg [63:0] registers [0:31];
integer i;

assign read_data1 = (read_reg1 == 5'b0) ? 64'b0 :
                    (reg_write_en && (write_reg == read_reg1) && (write_reg != 5'b0)) ? write_data :
                    registers[read_reg1];
assign read_data2 = (read_reg2 == 5'b0) ? 64'b0 :
                    (reg_write_en && (write_reg == read_reg2) && (write_reg != 5'b0)) ? write_data :
                    registers[read_reg2];

always @(posedge clk or posedge reset) begin
    if(reset) begin
        for(i = 0; i < 32; i = i + 1)
            registers[i] <= 64'b0;
    end
    else begin
        if(reg_write_en && write_reg != 5'b0)
            registers[write_reg] <= write_data;

        registers[0] <= 64'b0;
    end
end

task dump_registers;
    integer f;
    integer j;
    begin
        f = $fopen("register_file.txt","w");
        for(j = 0; j < 32; j = j + 1)
            $fwrite(f,"%016h\n",registers[j]);
        $fclose(f);
    end
endtask

endmodule