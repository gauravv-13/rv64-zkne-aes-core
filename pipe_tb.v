`timescale 1ns/1ps

// ----- ALU building blocks -----
`include "fulladder.v"
`include "add64.v"
`include "sub64.v"
`include "and64.v"
`include "or64.v"

// ----- ALU + control -----
`include "aes_round64.v"
`include "alu.v"
`include "alu_control.v"

// ----- misc datapath helpers -----
`include "imm_gen.v"
`include "pc.v"
// `include "pc_mux.v"
// `include "alu_src_mux.v"

// ----- memory + regfile -----
`include "instruction_mem.v"
`include "data_mem.v"
`include "register_file.v"

// ----- control unit -----
`include "cu.v"

// ----- hazard + forwarding -----
`include "hazard_detection_unit.v"
`include "ForwardingUnit.v"

// ----- pipeline registers -----
`include "IF_ID.v"
`include "ID_EX.v"
`include "EX_MEM.v"
`include "MEM_WB.v"

// ----- processor (depends on everything above) -----
`include "processor.v"


module pipe_tb;

reg clk;
reg reset;
integer cycle_count;

processor uut(
    .clk(clk),
    .reset(reset)
);

//////////////////////
// CLOCK
//////////////////////
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

//////////////////////
// RESET
//////////////////////
initial begin
    reset = 1;
    cycle_count = 0;
    #10;
    reset = 0;
end

//////////////////////
// VCD
//////////////////////
initial begin
    $dumpfile("pipeline.vcd");
    $dumpvars(0, pipe_tb);
end

//////////////////////
// CYCLE COUNTER
//////////////////////
always @(posedge clk) begin
    if (reset)
        cycle_count = 0;
    else
        cycle_count = cycle_count + 1;
end

//////////////////////
// PROGRAM FINISH
//////////////////////
always @(posedge clk) begin
    if (!reset && uut.instruction == 32'b0) begin
        #40;  // allow pipeline to drain

        uut.RF.dump_registers();
        append_cycles();
        $finish;
    end
end

always @(posedge clk) begin
    if (!reset && cycle_count > 200) begin
        $display("TIMEOUT at cycle %0d", cycle_count);
        uut.RF.dump_registers();
        append_cycles();
        $finish;
    end
end

task append_cycles;
    integer f;
    begin
        f = $fopen("register_file.txt","a");
        $fdisplay(f, "%0d", cycle_count);
        $fclose(f);
    end
endtask

endmodule