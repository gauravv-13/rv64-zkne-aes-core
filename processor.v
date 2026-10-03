`timescale 1ns/1ps

module processor(
    input clk,
    input reset
);

reg [63:0] PC;

wire [63:0] PC_next;
wire [63:0] PC_plus4;

assign PC_plus4 = PC + 4;

wire PCWrite;

always @(posedge clk or posedge reset)
begin
    if(reset)
        PC <= 0;
    else if(PCWrite)
        PC <= PC_next;
end

wire [31:0] instruction;

instruction_mem IM(
    .addr(PC),
    .instr(instruction)
);

wire branch_taken;

wire [63:0] IF_ID_pc;
wire [31:0] IF_ID_instr;

IF_ID ifid(
    .clk(clk),
    .reset(reset),
    .write_enable(IF_ID_Write),
    .flush(branch_taken),
    .pc_in(PC),
    .instr_in(instruction),
    .pc_out(IF_ID_pc),
    .instr_out(IF_ID_instr)
);

wire [6:0] opcode;
wire [4:0] rd;
wire [2:0] funct3;
wire [4:0] rs1;
wire [4:0] rs2;
wire funct7;

assign opcode = IF_ID_instr[6:0];
assign rd     = IF_ID_instr[11:7];
assign funct3 = IF_ID_instr[14:12];
assign rs1    = IF_ID_instr[19:15];
assign rs2    = IF_ID_instr[24:20];
assign funct7 = IF_ID_instr[30];

wire RegWrite;
wire MemRead;
wire MemWrite;
wire MemtoReg;
wire ALUSrc;
wire Branch;
wire [1:0] ALUOp;

control CU(
    .opcode(opcode),
    .RegWrite(RegWrite),
    .MemRead(MemRead),
    .MemWrite(MemWrite),
    .MemtoReg(MemtoReg),
    .ALUSrc(ALUSrc),
    .Branch(Branch),
    .ALUOp(ALUOp)
);

wire IF_ID_Write;
wire stall;

hazard_detection_unit HDU(
    .ID_EX_MemRead(ID_EX_MemRead),
    .ID_EX_Rd(ID_EX_rd),
    .IF_ID_Rs1(rs1),
    .IF_ID_Rs2(rs2),
    .PCWrite(PCWrite),
    .IF_ID_Write(IF_ID_Write),
    .stall(stall)
);

wire [63:0] rd1;
wire [63:0] rd2;
wire [63:0] write_data;

wire [4:0] MEM_WB_rd;
wire MEM_WB_RegWrite;

register_file RF(
    .clk(clk),
    .reset(reset),
    .read_reg1(rs1),
    .read_reg2(rs2),
    .write_reg(MEM_WB_rd),
    .write_data(write_data),
    .reg_write_en(MEM_WB_RegWrite),
    .read_data1(rd1),
    .read_data2(rd2)
);

wire [63:0] imm;

imm_gen IG(
    .instruction(IF_ID_instr),
    .imm_out(imm)
);

wire [63:0] ID_EX_pc;
wire [63:0] ID_EX_rs1_data;
wire [63:0] ID_EX_rs2_data;
wire [63:0] ID_EX_imm;

wire [4:0] ID_EX_rs1;
wire [4:0] ID_EX_rs2;
wire [4:0] ID_EX_rd;

wire [2:0] ID_EX_funct3;
wire ID_EX_funct7;

wire ID_EX_RegWrite;
wire ID_EX_MemRead;
wire ID_EX_MemWrite;
wire ID_EX_MemtoReg;
wire ID_EX_ALUSrc;
wire ID_EX_Branch;
wire [1:0] ID_EX_ALUOp;

ID_EX idex(
    .clk(clk),
    .reset(reset),
    .stall(stall),
    .flush(branch_taken),

    .pc_in(IF_ID_pc),
    .rs1_data_in(rd1),
    .rs2_data_in(rd2),
    .imm_in(imm),

    .rs1_in(rs1),
    .rs2_in(rs2),
    .rd_in(rd),

    .funct3_in(funct3),
    .funct7_in(funct7),

    .RegWrite_in((stall | branch_taken) ? 1'b0 : RegWrite),
    .MemRead_in((stall | branch_taken) ? 1'b0 : MemRead),
    .MemWrite_in((stall | branch_taken) ? 1'b0 : MemWrite),
    .MemtoReg_in((stall | branch_taken) ? 1'b0 : MemtoReg),
    .ALUSrc_in((stall | branch_taken) ? 1'b0 : ALUSrc),
    .ALUOp_in((stall | branch_taken) ? 2'b00 : ALUOp),
    .Branch_in((stall | branch_taken) ? 1'b0 : Branch),

    .pc_out(ID_EX_pc),
    .rs1_data_out(ID_EX_rs1_data),
    .rs2_data_out(ID_EX_rs2_data),
    .imm_out(ID_EX_imm),

    .rs1_out(ID_EX_rs1),
    .rs2_out(ID_EX_rs2),
    .rd_out(ID_EX_rd),

    .funct3_out(ID_EX_funct3),
    .funct7_out(ID_EX_funct7),

    .RegWrite_out(ID_EX_RegWrite),
    .MemRead_out(ID_EX_MemRead),
    .MemWrite_out(ID_EX_MemWrite),
    .MemtoReg_out(ID_EX_MemtoReg),
    .ALUSrc_out(ID_EX_ALUSrc),
    .ALUOp_out(ID_EX_ALUOp),
    .Branch_out(ID_EX_Branch)
);

wire [1:0] ForwardA;
wire [1:0] ForwardB;

ForwardingUnit FU(
    .EX_MEM_RegWrite(EX_MEM_RegWrite),
    .MEM_WB_RegWrite(MEM_WB_RegWrite),
    .EX_MEM_Rd(EX_MEM_rd),
    .MEM_WB_Rd(MEM_WB_rd),
    .ID_EX_Rs1(ID_EX_rs1),
    .ID_EX_Rs2(ID_EX_rs2),
    .ForwardA(ForwardA),
    .ForwardB(ForwardB)
);

wire [63:0] alu_input1;
wire [63:0] alu_input2_forward;
wire [63:0] alu_input2;

assign alu_input1 =
    (ForwardA == 2'b10) ? EX_MEM_alu :
    (ForwardA == 2'b01) ? write_data :
                          ID_EX_rs1_data;

assign alu_input2_forward =
    (ForwardB == 2'b10) ? EX_MEM_alu :
    (ForwardB == 2'b01) ? write_data :
                          ID_EX_rs2_data;

assign alu_input2 =
        ID_EX_ALUSrc ? ID_EX_imm : alu_input2_forward;

wire [3:0] ALUControl;

alu_control ALUCTRL(
    .ALUOp(ID_EX_ALUOp),
    .funct7(ID_EX_funct7),
    .funct3(ID_EX_funct3),
    .ALUControl(ALUControl)
);

wire [63:0] alu_result;
wire zero;

alu ALU(
    .input1(alu_input1),
    .input2(alu_input2),
    .control_signal(ALUControl),
    .result(alu_result),
    .zero_flag(zero)
);

assign branch_taken = ID_EX_Branch & zero;
wire [63:0] branch_target = ID_EX_pc + ID_EX_imm;
assign PC_next = branch_taken ? branch_target : PC_plus4;

wire [63:0] EX_MEM_alu;
wire [63:0] EX_MEM_write_data;
wire [4:0] EX_MEM_rd;
wire EX_MEM_RegWrite;
wire EX_MEM_MemRead;
wire EX_MEM_MemWrite;
wire EX_MEM_MemtoReg;

EX_MEM exmem(
    .clk(clk),
    .reset(reset),

    .alu_result_in(alu_result),
    .rs2_data_in(alu_input2_forward),
    .rd_in(ID_EX_rd),

    .RegWrite_in(ID_EX_RegWrite),
    .MemRead_in(ID_EX_MemRead),
    .MemWrite_in(ID_EX_MemWrite),
    .MemtoReg_in(ID_EX_MemtoReg),
    .Branch_in(ID_EX_Branch),

    .alu_result_out(EX_MEM_alu),
    .rs2_data_out(EX_MEM_write_data),
    .rd_out(EX_MEM_rd),

    .RegWrite_out(EX_MEM_RegWrite),
    .MemRead_out(EX_MEM_MemRead),
    .MemWrite_out(EX_MEM_MemWrite),
    .MemtoReg_out(EX_MEM_MemtoReg),
    .Branch_out()
);

wire [63:0] mem_read_data;

data_mem DM(
    .clk(clk),
    .reset(reset),
    .address(EX_MEM_alu),
    .write_data(EX_MEM_write_data),
    .MemRead(EX_MEM_MemRead),
    .MemWrite(EX_MEM_MemWrite),
    .read_data(mem_read_data)
);

wire [63:0] MEM_WB_mem_data;
wire [63:0] MEM_WB_alu;
wire MEM_WB_MemtoReg;

MEM_WB memwb(
    .clk(clk),
    .reset(reset),

    .mem_data_in(mem_read_data),
    .alu_result_in(EX_MEM_alu),
    .rd_in(EX_MEM_rd),

    .RegWrite_in(EX_MEM_RegWrite),
    .MemtoReg_in(EX_MEM_MemtoReg),

    .mem_data_out(MEM_WB_mem_data),
    .alu_result_out(MEM_WB_alu),
    .rd_out(MEM_WB_rd),

    .RegWrite_out(MEM_WB_RegWrite),
    .MemtoReg_out(MEM_WB_MemtoReg)
);

assign write_data =
        MEM_WB_MemtoReg ? MEM_WB_mem_data : MEM_WB_alu;

endmodule