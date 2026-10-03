module hazard_detection_unit(
    input ID_EX_MemRead,
    input [4:0] ID_EX_Rd,
    input [4:0] IF_ID_Rs1,
    input [4:0] IF_ID_Rs2,

    output reg PCWrite,
    output reg IF_ID_Write,
    output reg stall
);

always @(*) begin
    if (ID_EX_MemRead && (ID_EX_Rd != 5'b0) &&
       ((ID_EX_Rd == IF_ID_Rs1) || (ID_EX_Rd == IF_ID_Rs2))) begin

        PCWrite = 0;
        IF_ID_Write = 0;
        stall = 1;
    end
    else begin
        PCWrite = 1;
        IF_ID_Write = 1;
        stall = 0;
    end
end
endmodule