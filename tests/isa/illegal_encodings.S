// Every encoding the core does not fully decode must raise illegal_instr.
// Each one is labelled ill_<name>; the runner checks that exactly these
// PCs are reported, once each. All use rd=x0 / base x0 so that nothing
// depends on them. Conditional branches target the next instruction.
#include "test.h"
#define ILL(name, ...) ill_##name: __VA_ARGS__

        .section .text.init
        .globl _start
_start:
        addi x1, x0, 1              // legal
        // OP-IMM, funct3 != 000
        ILL(slli,  slli  x0, x1, 1)
        ILL(slti,  slti  x0, x1, 1)
        ILL(sltiu, sltiu x0, x1, 1)
        ILL(xori,  xori  x0, x1, 1)
        ILL(srli,  srli  x0, x1, 1)
        ILL(srai,  srai  x0, x1, 1)
        ILL(ori,   ori   x0, x1, 1)
        ILL(andi,  andi  x0, x1, 1)
        // OP, funct3/funct7 other than add/sub/and/or/xor
        ILL(sll,   sll   x0, x1, x1)
        ILL(slt,   slt   x0, x1, x1)
        ILL(sltu,  sltu  x0, x1, x1)
        ILL(srl,   srl   x0, x1, x1)
        ILL(sra,   sra   x0, x1, x1)
        ILL(sub_f3_111, .insn r 0x33, 7, 0x20, x0, x1, x1)
        ILL(mul,   .insn r 0x33, 0, 0x01, x0, x1, x1)
        ILL(add_f7_bit31, .insn r 0x33, 0, 0x40, x0, x1, x1)
        ILL(aes64ds,  .insn r 0x33, 0, 0x1d, x0, x1, x1)   // Zknd: not implemented
        ILL(aes64dsm, .insn r 0x33, 0, 0x1f, x0, x1, x1)   // Zknd: not implemented
        ILL(aes64im,  .insn i 0x13, 1, x0, x1, 0x300)      // Zknd: not implemented
        // LOAD other than ld
        ILL(lb,    lb    x0, 0(x0))
        ILL(lh,    lh    x0, 0(x0))
        ILL(lw,    lw    x0, 0(x0))
        ILL(lbu,   lbu   x0, 0(x0))
        ILL(lhu,   lhu   x0, 0(x0))
        ILL(lwu,   lwu   x0, 0(x0))
        ILL(load_f3_111, .insn i 0x03, 7, x0, 0(x0))
        // STORE other than sd
        ILL(sb,    sb    x0, 0(x0))
        ILL(sh,    sh    x0, 0(x0))
        ILL(sw,    sw    x0, 0(x0))
        ILL(store_f3_100, .insn s 0x23, 4, x0, 0(x0))
        // BRANCH other than beq/bne
        ILL(blt,   blt   x0, x1, 1f)
1:      ILL(bge,   bge   x0, x1, 1f)
1:      ILL(bltu,  bltu  x0, x1, 1f)
1:      ILL(bgeu,  bgeu  x0, x1, 1f)
1:      ILL(br_f3_010, .insn b 0x63, 2, x0, x1, 1f)
1:      ILL(br_f3_011, .insn b 0x63, 3, x0, x1, 1f)
1:
        // Unknown opcodes
        ILL(jal,   jal   x0, 1f)
1:      ILL(jalr,  .insn i 0x67, 0, x0, x0, 0)
        ILL(addw,  addw  x0, x1, x1)
        ILL(addiw, addiw x0, x1, 1)
        ILL(fence, fence)
        ILL(ecall, ecall)
        ILL(ebreak, ebreak)
        ILL(custom1, .insn r 0x2b, 0, 0, x0, x1, x1)
        ILL(custom0_f3_001, .insn r 0x0b, 1, 0, x0, x1, x1)
        ILL(all_ones, .word 0xffffffff)
        addi x2, x0, 2              // legal
        addi x3, x0, 3              // legal
        TEST_END

// EXPECT: x1 = 0x0000000000000001
// EXPECT: x2 = 0x0000000000000002
// EXPECT: x3 = 0x0000000000000003
