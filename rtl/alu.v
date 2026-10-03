`timescale 1ns/1ps

module alu(input1, input2, control_signal, result, zero_flag);

    input  [63:0] input1;
    input  [63:0] input2;
    input  [3:0]  control_signal;

    output [63:0] result;
    output        zero_flag;

    wire [63:0] y_add;
    wire [63:0] y_sub;
    wire [63:0] y_and;
    wire [63:0] y_or;
    wire [63:0] y_xor;
    wire [63:0] y_aes;

    wire c_add;
    wire c_sub;
    wire o_add;
    wire o_sub;

    wire z_add;
    wire z_sub;
    wire z_and;
    wire z_or;
    wire z_xor;
    wire z_aes;

    add64 u0(input1, input2, y_add, c_add, o_add, z_add);
    sub64 u1(input1, input2, y_sub, c_sub, o_sub, z_sub);
    and64 u2(input1, input2, y_and, z_and);
    or64  u3(input1, input2, y_or, z_or);
    xor64 u5(input1, input2, y_xor, z_xor);
    aes_round64 u4(.input1(input1), .input2(input2), .result(y_aes));

    assign z_aes = (y_aes == 64'b0);

    assign result =
        (control_signal == 4'b0000) ? y_and :
        (control_signal == 4'b0001) ? y_or  :
        (control_signal == 4'b0011) ? y_xor :
        (control_signal == 4'b0010) ? y_add :
        (control_signal == 4'b0110) ? y_sub :
        (control_signal == 4'b1000) ? y_aes :
        64'b0;

    assign zero_flag =
        (control_signal == 4'b0000) ? z_and :
        (control_signal == 4'b0001) ? z_or  :
        (control_signal == 4'b0011) ? z_xor :
        (control_signal == 4'b0010) ? z_add :
        (control_signal == 4'b0110) ? z_sub :
        (control_signal == 4'b1000) ? z_aes :
        1'b0;

endmodule
