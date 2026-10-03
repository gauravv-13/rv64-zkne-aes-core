`timescale 1ns/1ps

module fulladder (
    input  a,
    input  b,
    input  cin,
    output sum,
    output cout
);

assign sum  = a ^ b ^ cin;
assign cout = (a & b) | (a & cin) | (b & cin);

endmodule
