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
/* KERNEL_RAM_VADDR = 0xC0000000 + 0x8000*/
#define KERNEL_RAM_VADDR        (PAGE_OFFSET + TEXT_OFFSET)
#if (KERNEL_RAM_VADDR & 0xffff) != 0x8000
#error KERNEL_RAM_VADDR must start at 0xXXXX8000
#endif

#define PG_DIR_SIZE     0x4000
#define PMD_ORDER       2

        /* swapper_pg_dir = 0x80004000 */
        .globl  swapper_pg_dir
        .equ    swapper_pg_dir, KERNEL_RAM_VADDR - PG_DIR_SIZE @swapper_pg_dir = 0xC0004000

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
         * adr     \reg2, .L_boot_cpu_mode_offset @ get L_boot_cpu_mode_offset phys address store to reg2
         * ldr     \reg3, [\reg2]                  @ reg3 = [reg2] = __boot_cpu_mode - .（the offset between __boot_cpu_mode & L_boot_cpu_mode_offset）
         * str     \reg1, [\reg2, \reg3]           @ [reg2 + reg3] = reg1, this means __boot_cpu_mode = reg1 = cpsr & 0x1f
         * .endm
         */
        bl      __hyp_stub_install  @ from the comments, we konw now __boot_cpu_mode saves the cpu current mode.
#endif
        @ ensure svc mode and all interrupts masked
        @ .macro safe_svcmode_maskall reg:req
        @ #if __LINUX_ARM_ARCH__ >= 6 && !defined(CONFIG_CPU_V7M)
        @       mrs     \reg , cpsr              @ reg = cpsr
        @       eor     \reg, \reg, #HYP_MODE    @ reg = reg ^ HYP_MODE(0x1a)
        @       tst     \reg, #MODE_MASK         @ reg ^ MODE_MASK(0x1f), notes will upate flags
        @       bic     \reg , \reg , #MODE_MASK @ clr bit0-4
        @       orr     \reg , \reg , #PSR_I_BIT | PSR_F_BIT | SVC_MODE @ set disable IRQ/FIQ, force mode to SVC
        @       THUMB(  orr     \reg , \reg , #PSR_T_BIT        ) @ do nothing in arm mode
        @       bne     1f 
        @       orr     \reg, \reg, #PSR_A_BIT
        @       badr    lr, 2f
        @       msr     spsr_cxsf, \reg @ the operand to msr here is SPSR_<fields>, where <fields> "Is a sequence of one or more of" c, x, s, f, which represent bits 7:0, 15:8, 23:16 and 31:24 respectively.
        @       __MSR_ELR_HYP(14)
        @       __ERET
        @ 1:      msr     cpsr_c, \reg @ cpsr_c = reg
        @ 2:
        @ #else
        @       /*
        @        * workaround for possibly broken pre-v6 hardware
        @        * (akita, Sharp Zaurus C-1000, PXA270-based)
        @        */
        @       setmode PSR_F_BIT | PSR_I_BIT | SVC_MODE, \reg
        @ #endif
        @ .endm
        safe_svcmode_maskall r9

        mrc     p15, 0, r9, c0, c0              @ get processor id
        bl      __lookup_processor_type         @ r5=procinfo r9=cpuid
        movs    r10, r5                         @ invalid processor (r5=0)?
 THUMB( it      eq )            @ force fixup-able long branch encoding
        beq     __error_p                       @ yes, error 'p'

        @ LPAE/.......
        .......
#ifndef CONFIG_XIP_KERNEL
        adr     r3, 2f
        ldmia   r3, {r4, r8}
        sub     r4, r3, r4                      @ (PHYS_OFFSET - PAGE_OFFSET)
        add     r8, r8, r4                      @ PHYS_OFFSET =0x80000000
#else
        ldr     r8, =PLAT_PHYS_OFFSET           @ always constant in this case
#endif
        
        /*
         * r1 = machine no, r2 = atags or dtb,
         * r8 = phys_offset, r9 = cpuid, r10 = procinfo
         */
        bl      __vet_atags  @@ check r2 valid, if not valid, r2 will be set as 0
#ifdef CONFIG_SMP_ON_UP
        bl      __fixup_smp  @@actually do nothing for armv7
#endif
#ifdef CONFIG_ARM_PATCH_PHYS_VIRT
        bl      __fixup_pv_table @@
#endif
        bl      __create_page_tables
