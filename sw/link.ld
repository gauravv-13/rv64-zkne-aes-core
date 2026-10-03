/* Linker script for test programs.
 * Code at 0x80000000 (Spike's default reset vector). Data at a fixed
 * address so tests can check addresses exactly. The core decodes only the
 * low address bits, so 64 KB memories cover 0x80000000-0x8000ffff. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS
{
    . = 0x80000000;
    .text : { *(.text.init) *(.text) }
    . = 0x80008000;
    .data : { *(.data) *(.rodata*) }
}
