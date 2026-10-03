`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// pipe_tb - top-level testbench for the pipelined core.
//
// Plusargs:
//   +IMEM=<file>      program image (read by instruction_mem)
//   +OUT=<file>       register dump written at the end of the run
//                     (32 lines of %016h, then the cycle count)
//   +MAX_CYCLES=<n>   cycle limit, default 200; hitting it fails the run
//   +ZERO_WORD_STOP   legacy end-of-program rule: stop when the fetched
//                     instruction word is 0x00000000 (legacy test only)
//   +VCD=<file>       dump all signals to a VCD file
//   +ALLOW_ILLEGAL    report illegal instructions but keep running
//                     (default: the first one ends the run with ILLEGAL)
//   +DUMP_DMEM=<file> at the end, write data memory with $writememh
//                     (one byte per line, byte 0 = lowest address)
//
// Parameters (set with iverilog -P pipe_tb.<name>=<value>):
//   RESET_PC          reset vector, default 0x80000000 (legacy test: 0)
//
// The run ends with one of these lines (scripts/run_tests.py looks for them):
//   "RESULT: DONE"     program finished normally
//   "RESULT: TIMEOUT"  cycle limit reached
//   "RESULT: ILLEGAL"  an illegal instruction reached EX (test fails)
// ---------------------------------------------------------------------------
module pipe_tb #(
    parameter [63:0] RESET_PC = 64'h0000_0000_8000_0000
);

reg clk;
reg reset;
integer cycle_count;
integer max_cycles;
reg zero_word_stop;
reg draining;
reg [8*256-1:0] out_file;
reg [8*256-1:0] vcd_file;
reg [8*256-1:0] dmem_dump_file;

wire illegal_instr_ex;
integer illegal_count;

processor #(.RESET_PC(RESET_PC)) uut(
    .clk(clk),
    .reset(reset),
    .illegal_instr_ex(illegal_instr_ex)
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
    draining = 0;
    illegal_count = 0;
    #10;
    reset = 0;
end

//////////////////////
// PLUSARGS + VCD
//////////////////////
initial begin
    if (!$value$plusargs("MAX_CYCLES=%d", max_cycles))
        max_cycles = 200;
    if (!$value$plusargs("OUT=%s", out_file))
        out_file = "register_file.txt";
    zero_word_stop = $test$plusargs("ZERO_WORD_STOP");
    if ($value$plusargs("VCD=%s", vcd_file)) begin
        $dumpfile(vcd_file);
        $dumpvars(0, pipe_tb);
    end
end

//////////////////////
// CYCLE COUNTER
//////////////////////
always @(posedge clk) begin
    if (reset)
        cycle_count <= 0;
    else
        cycle_count <= cycle_count + 1;
end

//////////////////////
// PROGRAM FINISH (legacy rule): zero word fetched -> drain 4 cycles -> stop
//////////////////////
always @(posedge clk) begin
    if (!reset && zero_word_stop && !draining && uut.instruction == 32'b0)
        draining <= 1'b1;
end

initial begin
    @(posedge draining);
    repeat (4) @(posedge clk);   // allow pipeline to drain
    finish_run("DONE");
end

//////////////////////
// ILLEGAL INSTRUCTIONS: reported from EX, so squashed instructions never
// count. The core turns them into NOPs (it has no traps); the testbench
// fails the run on the first one unless +ALLOW_ILLEGAL. In legacy mode
// (+ZERO_WORD_STOP) the zero word is the end marker and is not reported.
//////////////////////
function [31:0] imem_word;
    input [63:0] pc;
    begin
        imem_word = {uut.IM.mem[(pc + 3) % uut.IMEM_BYTES],
                     uut.IM.mem[(pc + 2) % uut.IMEM_BYTES],
                     uut.IM.mem[(pc + 1) % uut.IMEM_BYTES],
                     uut.IM.mem[pc % uut.IMEM_BYTES]};
    end
endfunction

always @(posedge clk) begin
    if (!reset && illegal_instr_ex &&
        !(zero_word_stop && imem_word(uut.ID_EX_pc) == 32'b0)) begin
        $display("ILLEGAL INSTRUCTION 0x%08h at pc 0x%016h (cycle %0d)",
                 imem_word(uut.ID_EX_pc), uut.ID_EX_pc, cycle_count);
        illegal_count = illegal_count + 1;
        if (!$test$plusargs("ALLOW_ILLEGAL")) begin
            $display("ERROR: illegal instruction (executed as a NOP; the core has no traps). Failing the test.");
            finish_run("ILLEGAL");
        end
    end
end

//////////////////////
// TIMEOUT
//////////////////////
always @(posedge clk) begin
    if (!reset && cycle_count > max_cycles) begin
        $display("TIMEOUT at cycle %0d", cycle_count);
        finish_run("TIMEOUT");
    end
end

task finish_run;
    input [8*16-1:0] status;
    integer f;
    integer j;
    begin
        f = $fopen(out_file, "w");
        for (j = 0; j < 32; j = j + 1)
            $fdisplay(f, "%016h", uut.RF.registers[j]);
        $fdisplay(f, "%0d", cycle_count);
        $fclose(f);
        if ($value$plusargs("DUMP_DMEM=%s", dmem_dump_file))
            $writememh(dmem_dump_file, uut.DM.mem);
        $display("RESULT: %0s (cycles=%0d)", status, cycle_count);
        $finish;
    end
endtask

endmodule
