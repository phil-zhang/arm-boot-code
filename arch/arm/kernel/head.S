/*
 *  linux/arch/arm/kernel/head.S
 *
 *  Copyright (C) 1994-2002 Russell King
 *  Copyright (c) 2003 ARM Limited
 *  All Rights Reserved
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 *  Kernel startup code for all 32-bit CPUs
 */
#include <linux/linkage.h>
#include <linux/init.h>

#include <asm/assembler.h>
#include <asm/cp15.h>
#include <asm/domain.h>
#include <asm/ptrace.h>
#include <asm/asm-offsets.h>
#include <asm/memory.h>
#include <asm/thread_info.h>
#include <asm/pgtable.h>

/*
 * swapper_pg_dir is the virtual address of the initial page table.
 * We place the page tables 16K below KERNEL_RAM_VADDR.  Therefore, we must
 * make sure that KERNEL_RAM_VADDR is correctly set.  Currently, we expect
 * the least significant 16 bits to be 0x8000, but we could probably
 * relax this restriction to KERNEL_RAM_VADDR >= PAGE_OFFSET + 0x4000.
 */
/* KERNEL_RAM_VADDR = 0x80000000 + 0x8000*/
#define KERNEL_RAM_VADDR        (PAGE_OFFSET + TEXT_OFFSET)
#if (KERNEL_RAM_VADDR & 0xffff) != 0x8000
#error KERNEL_RAM_VADDR must start at 0xXXXX8000
#endif

#define PG_DIR_SIZE     0x4000
#define PMD_ORDER       2

        /* swapper_pg_dir = 0x80004000 */
        .globl  swapper_pg_dir
        .equ    swapper_pg_dir, KERNEL_RAM_VADDR - PG_DIR_SIZE @swapper_pg_dir = 0x80004000

        .macro  pgtbl, rd, phys
        add     \rd, \phys, #TEXT_OFFSET @rd = phys + 0x8000
        sub     \rd, \rd, #PG_DIR_SIZE @ rd = rd - 0x4000
        .endm

/*
 * Kernel startup entry point.
 * ---------------------------
 *
 * This is normally called from the decompressor code.  The requirements
 * are: MMU = off, D-cache = off, I-cache = dont care, r0 = 0,
 * r1 = machine nr, r2 = atags or dtb pointer.
 *
 * This code is mostly position independent, so if you link the kernel at
 * 0xc0008000, you call this at __pa(0xc0008000).
 *
 * See linux/arch/arm/tools/mach-types for the complete list of machine
 * numbers for r1.
 *
 * We're trying to keep crap to a minimum; DO NOT add any machine specific
 * crap here - that's what the boot loader (or in extreme, well justified
 * circumstances, zImage) is for.
 */
        .arm

        __HEAD     /* what's the purpose of __HEAD ???? */
ENTRY(stext)
#ifdef CONFIG_ARM_VIRT_EXT
        /*
         * ENTRY(__hyp_stub_install)
         * store_primary_cpu_mode  r4, r5, r6
         * ENDPROC(__hyp_stub_install)
         */
        /*
         * Save the primary CPU boot mode. Requires 3 scratch registers. 
         */
        /* .macro  store_primary_cpu_mode  reg1, reg2, reg3 
         * mrs     \reg1, cpsr                     @ reg1 = cpsr 
         * and     \reg1, \reg1, #MODE_MASK        @ reg1 = cpsr & 0x1f
         * adr     \reg2, .L__boot_cpu_mode_offset @ get boot_cpu_mode phys address to reg2
         * ldr     \reg3, [\reg2]                  @ reg3 = [reg2], reg3 now is boot_cpu_mode physical address
         * str     \reg1, [\reg2, \reg3]           @ [reg2 + reg3] = reg1
         * .endm
         */
        bl      __hyp_stub_install
#endif
        @ ensure svc mode and all interrupts masked
        safe_svcmode_maskall r9

        mrc     p15, 0, r9, c0, c0              @ get processor id
        bl      __lookup_processor_type         @ r5=procinfo r9=cpuid
        movs    r10, r5                         @ invalid processor (r5=0)?
 THUMB( it      eq )            @ force fixup-able long branch encoding
        beq     __error_p                       @ yes, error 'p'
