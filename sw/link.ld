/* Linker script for test programs. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS
{
    . = 0x0;
    .text : { *(.text.init) *(.text) }
    .data : { *(.data) *(.rodata*) }
}
