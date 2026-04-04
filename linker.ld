OUTPUT_FORMAT("elf64-x86-64", "elf64-x86-64", "elf64-x86-64")
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

PHDRS
{
    text PT_LOAD FLAGS(7);
}

SECTIONS
{
    . = 0;

    .text : {
        *(.text._start)
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
        *(.data)
        *(.data.*)
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } :text

    /DISCARD/ : {
        *(.comment)
        *(.note.*)
        *(.eh_frame*)
        *(.got)
        *(.got.plt)
        *(.interp)
        *(.dynsym)
        *(.dynstr)
        *(.dynamic)
        *(.gnu.hash)
        *(.gnu.version*)
        *(.rela.*)
        *(.rel.*)
        *(.plt)
        *(.plt.*)
    }
}
