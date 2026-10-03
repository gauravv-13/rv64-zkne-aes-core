`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// zkne_unit_tb - drives rtl/zkne_unit.v with vectors from a file and writes
// the results; scripts/run_tests.py compares them with the golden model
// (scripts/zkne_golden.py).
//
//   +VEC=<file>   one vector per line, hex: valid op rs1 rs2 rnum
//   +OUT=<file>   one result per line (%016h), same order
// ---------------------------------------------------------------------------
module zkne_unit_tb;

reg         valid;
reg  [1:0]  op;
reg  [63:0] rs1, rs2;
reg  [3:0]  rnum;
wire [63:0] result;

zkne_unit dut (
    .valid(valid), .op(op), .rs1(rs1), .rs2(rs2), .rnum(rnum), .result(result)
);

integer fin, fout, n, count;
reg [8*256-1:0] vec_file, out_file;

initial begin
    if (!$value$plusargs("VEC=%s", vec_file) || !$value$plusargs("OUT=%s", out_file)) begin
        $display("usage: +VEC=<file> +OUT=<file>");
        $finish;
    end
    fin  = $fopen(vec_file, "r");
    fout = $fopen(out_file, "w");
    count = 0;
    while (!$feof(fin)) begin
        n = $fscanf(fin, "%h %h %h %h %h\n", valid, op, rs1, rs2, rnum);
        if (n == 5) begin
            #1;                              // combinational settle
            $fdisplay(fout, "%016h", result);
            count = count + 1;
        end
    end
    $fclose(fin);
    $fclose(fout);
    $display("RESULT: DONE (%0d vectors)", count);
    $finish;
end

endmodule
