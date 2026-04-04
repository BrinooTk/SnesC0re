	.file	"snes_runtime.c"
	.text
	.globl	snes_runtime_init               # -- Begin function snes_runtime_init
	.type	snes_runtime_init,@function
snes_runtime_init:                      # @snes_runtime_init
# %bb.0:
	pushq	%rbp
	movq	%rsp, %rbp
	andq	$-8, %rsp
	movq	%rdi, g_heap_base(%rip)
	movq	%rdi, g_heap_ptr(%rip)
	movl	%esi, %eax
	addq	%rdi, %rax
	movq	%rax, g_heap_end(%rip)
	movq	%rdx, g_gadget(%rip)
	movq	%rcx, g_sendto_fn(%rip)
	movl	%r8d, g_log_fd(%rip)
	xorl	%eax, %eax
	leaq	g_log_sa(%rip), %rcx
.LBB0_1:                                # =>This Inner Loop Header: Depth=1
	testq	%r9, %r9
	je	.LBB0_2
# %bb.3:                                #   in Loop: Header=BB0_1 Depth=1
	movb	(%r9,%rax), %dl
	jmp	.LBB0_4
.LBB0_2:                                #   in Loop: Header=BB0_1 Depth=1
	xorl	%edx, %edx
.LBB0_4:                                #   in Loop: Header=BB0_1 Depth=1
	movb	%dl, (%rax,%rcx)
	incq	%rax
	cmpq	$16, %rax
	jne	.LBB0_1
# %bb.5:
	movq	%rbp, %rsp
	popq	%rbp
	retq
.Lfunc_end0:
	.size	snes_runtime_init, .Lfunc_end0-snes_runtime_init
                                        # -- End function
	.globl	snes_runtime_reset_heap         # -- Begin function snes_runtime_reset_heap
	.type	snes_runtime_reset_heap,@function
snes_runtime_reset_heap:                # @snes_runtime_reset_heap
# %bb.0:
	pushq	%rbp
	movq	%rsp, %rbp
	andq	$-8, %rsp
	movq	g_heap_base(%rip), %rax
	movq	%rax, g_heap_ptr(%rip)
	movq	%rbp, %rsp
	popq	%rbp
	retq
.Lfunc_end1:
	.size	snes_runtime_reset_heap, .Lfunc_end1-snes_runtime_reset_heap
                                        # -- End function
	.globl	malloc                          # -- Begin function malloc
	.type	malloc,@function
malloc:                                 # @malloc
# %bb.0:
	movq	g_heap_ptr(%rip), %rax
	testq	%rax, %rax
	sete	%cl
	testq	%rdi, %rdi
	sete	%dl
	orb	%cl, %dl
	jne	.LBB2_1
# %bb.3:
	leal	23(%rdi), %ecx
	andl	$-16, %ecx
	addq	%rax, %rcx
	cmpq	g_heap_end(%rip), %rcx
	jbe	.LBB2_4
.LBB2_1:
	xorl	%eax, %eax
	retq
.LBB2_4:
	pushq	%rbp
	movq	%rsp, %rbp
	andq	$-8, %rsp
	movl	%edi, (%rax)
	movl	$0, 4(%rax)
	movq	%rcx, g_heap_ptr(%rip)
	addq	$8, %rax
	movq	%rbp, %rsp
	popq	%rbp
	retq
.Lfunc_end2:
	.size	malloc, .Lfunc_end2-malloc
                                        # -- End function
	.globl	free                            # -- Begin function free
	.type	free,@function
free:                                   # @free
# %bb.0:
	pushq	%rbp
	movq	%rsp, %rbp
	andq	$-8, %rsp
	movq	%rbp, %rsp
	popq	%rbp
	retq
.Lfunc_end3:
	.size	free, .Lfunc_end3-free
                                        # -- End function
	.globl	realloc                         # -- Begin function realloc
	.type	realloc,@function
realloc:                                # @realloc
# %bb.0:
	testq	%rdi, %rdi
	je	.LBB4_1
# %bb.5:
	testq	%rsi, %rsi
	je	.LBB4_2
# %bb.6:
	movq	g_heap_ptr(%rip), %rax
	testq	%rax, %rax
	je	.LBB4_2
# %bb.7:
	leal	23(%rsi), %ecx
	andl	$-16, %ecx
	addq	%rax, %rcx
	cmpq	g_heap_end(%rip), %rcx
	ja	.LBB4_2
# %bb.8:
	movl	%esi, (%rax)
	movl	$0, 4(%rax)
	movq	%rcx, g_heap_ptr(%rip)
	addq	$8, %rax
	movl	-8(%rdi), %ecx
	cmpl	%esi, %ecx
	cmovll	%ecx, %esi
	testl	%esi, %esi
	je	.LBB4_12
# %bb.9:
	pushq	%rbp
	movq	%rsp, %rbp
	andq	$-8, %rsp
	movslq	%esi, %rcx
	xorl	%edx, %edx
.LBB4_10:                               # =>This Inner Loop Header: Depth=1
	movb	(%rdi,%rdx), %sil
	movb	%sil, (%rax,%rdx)
	incq	%rdx
	cmpq	%rdx, %rcx
	jne	.LBB4_10
# %bb.11:
	movq	%rbp, %rsp
	popq	%rbp
.LBB4_12:
	retq
.LBB4_1:
	movq	g_heap_ptr(%rip), %rax
	testq	%rax, %rax
	sete	%cl
	testq	%rsi, %rsi
	sete	%dl
	orb	%cl, %dl
	jne	.LBB4_2
# %bb.3:
	leal	23(%rsi), %ecx
	andl	$-16, %ecx
	addq	%rax, %rcx
	cmpq	g_heap_end(%rip), %rcx
	jbe	.LBB4_4
.LBB4_2:
	xorl	%eax, %eax
	retq
.LBB4_4:
	movl	%esi, (%rax)
	movl	$0, 4(%rax)
	movq	%rcx, g_heap_ptr(%rip)
	addq	$8, %rax
	retq
.Lfunc_end4:
	.size	realloc, .Lfunc_end4-realloc
                                        # -- End function
	.globl	memcpy                          # -- Begin function memcpy
	.type	memcpy,@function
memcpy:                                 # @memcpy
# %bb.0:
	pushq	%rbp
	movq	%rsp, %rbp
	andq	$-8, %rsp
	movq	%rdi, %rax
	testq	%rdx, %rdx
	je	.LBB5_3
# %bb.1:
	xorl	%ecx, %ecx
.LBB5_2:                                # =>This Inner Loop Header: Depth=1
	movb	(%rsi,%rcx), %dil
	movb	%dil, (%rax,%rcx)
	incq	%rcx
	cmpq	%rcx, %rdx
	jne	.LBB5_2
.LBB5_3:
	movq	%rbp, %rsp
	popq	%rbp
	retq
.Lfunc_end5:
	.size	memcpy, .Lfunc_end5-memcpy
                                        # -- End function
	.globl	memmove                         # -- Begin function memmove
	.type	memmove,@function
memmove:                                # @memmove
# %bb.0:
	pushq	%rbp
	movq	%rsp, %rbp
	andq	$-8, %rsp
	movq	%rdi, %rax
	cmpq	%rsi, %rdi
	sete	%cl
	testq	%rdx, %rdx
	sete	%dil
	orb	%cl, %dil
	jne	.LBB6_6
# %bb.1:
	cmpq	%rsi, %rax
	jae	.LBB6_2
# %bb.4:
	xorl	%ecx, %ecx
.LBB6_5:                                # =>This Inner Loop Header: Depth=1
	movb	(%rsi,%rcx), %dil
	movb	%dil, (%rax,%rcx)
	incq	%rcx
	cmpq	%rcx, %rdx
	jne	.LBB6_5
	jmp	.LBB6_6
.LBB6_2:
	movq	%rdx, %rcx
.LBB6_3:                                # =>This Inner Loop Header: Depth=1
	movb	-1(%rsi,%rdx), %dil
	movb	%dil, -1(%rax,%rdx)
	decq	%rcx
	movq	%rcx, %rdx
	jne	.LBB6_3
.LBB6_6:
	movq	%rbp, %rsp
	popq	%rbp
	retq
.Lfunc_end6:
	.size	memmove, .Lfunc_end6-memmove
                                        # -- End function
	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	4, 0x0                          # -- Begin function memset
.LCPI7_0:
	.quad	14                              # 0xe
	.quad	15                              # 0xf
.LCPI7_1:
	.quad	12                              # 0xc
	.quad	13                              # 0xd
.LCPI7_2:
	.quad	10                              # 0xa
	.quad	11                              # 0xb
.LCPI7_3:
	.quad	8                               # 0x8
	.quad	9                               # 0x9
.LCPI7_4:
	.quad	6                               # 0x6
	.quad	7                               # 0x7
.LCPI7_5:
	.quad	4                               # 0x4
	.quad	5                               # 0x5
.LCPI7_6:
	.quad	2                               # 0x2
	.quad	3                               # 0x3
.LCPI7_7:
	.byte	0                               # 0x0
	.byte	0                               # 0x0
	.byte	0                               # 0x0
	.byte	0                               # 0x0
	.byte	0                               # 0x0
	.byte	0                               # 0x0
	.byte	0                               # 0x0
	.byte	0                               # 0x0
	.byte	1                               # 0x1
	.byte	0                               # 0x0
	.byte	0                               # 0x0
	.byte	0                               # 0x0
	.byte	0                               # 0x0
	.byte	0                               # 0x0
	.byte	0                               # 0x0
	.byte	0                               # 0x0
.LCPI7_8:
	.quad	-9223372034707292160            # 0x8000000080000000
	.quad	-9223372034707292160            # 0x8000000080000000
.LCPI7_9:
	.quad	16                              # 0x10
	.quad	16                              # 0x10
	.text
	.globl	memset
	.type	memset,@function
memset:                                 # @memset
# %bb.0:
	movq	%rdi, %rax
	testq	%rdx, %rdx
	je	.LBB7_36
# %bb.1:
	pushq	%rbp
	movq	%rsp, %rbp
	andq	$-16, %rsp
	subq	$16, %rsp
	leaq	15(%rdx), %rcx
	andq	$-16, %rcx
	decq	%rdx
	movq	%rdx, %xmm0
	pshufd	$68, %xmm0, %xmm0               # xmm0 = xmm0[0,1,0,1]
	movdqa	%xmm0, (%rsp)                   # 16-byte Spill
	movdqa	.LCPI7_0(%rip), %xmm1           # xmm1 = [14,15]
	movdqa	.LCPI7_1(%rip), %xmm2           # xmm2 = [12,13]
	movdqa	.LCPI7_2(%rip), %xmm3           # xmm3 = [10,11]
	movdqa	.LCPI7_3(%rip), %xmm4           # xmm4 = [8,9]
	movdqa	.LCPI7_4(%rip), %xmm5           # xmm5 = [6,7]
	movdqa	.LCPI7_5(%rip), %xmm6           # xmm6 = [4,5]
	movdqa	.LCPI7_6(%rip), %xmm7           # xmm7 = [2,3]
	movdqa	.LCPI7_7(%rip), %xmm8           # xmm8 = [0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0]
	xorl	%edx, %edx
	movdqa	.LCPI7_8(%rip), %xmm9           # xmm9 = [9223372039002259456,9223372039002259456]
	pcmpeqd	%xmm10, %xmm10
.LBB7_2:                                # =>This Inner Loop Header: Depth=1
	movdqa	(%rsp), %xmm12                  # 16-byte Reload
	pxor	%xmm9, %xmm12
	movdqa	%xmm8, %xmm13
	pxor	%xmm9, %xmm13
	movdqa	%xmm13, %xmm15
	pcmpgtd	%xmm12, %xmm15
	pshufd	$160, %xmm15, %xmm14            # xmm14 = xmm15[0,0,2,2]
	pshuflw	$232, %xmm14, %xmm0             # xmm0 = xmm14[0,2,2,3,4,5,6,7]
	pcmpeqd	%xmm12, %xmm13
	pshufd	$245, %xmm13, %xmm13            # xmm13 = xmm13[1,1,3,3]
	pshuflw	$232, %xmm13, %xmm11            # xmm11 = xmm13[0,2,2,3,4,5,6,7]
	pand	%xmm0, %xmm11
	pshufd	$245, %xmm15, %xmm15            # xmm15 = xmm15[1,1,3,3]
	pshuflw	$232, %xmm15, %xmm0             # xmm0 = xmm15[0,2,2,3,4,5,6,7]
	por	%xmm11, %xmm0
	pxor	%xmm10, %xmm0
	packssdw	%xmm0, %xmm0
	movd	%xmm0, %edi
	testb	$1, %dil
	je	.LBB7_4
# %bb.3:                                #   in Loop: Header=BB7_2 Depth=1
	movb	%sil, (%rax,%rdx)
.LBB7_4:                                #   in Loop: Header=BB7_2 Depth=1
	pand	%xmm14, %xmm13
	por	%xmm15, %xmm13
	packssdw	%xmm13, %xmm13
	pxor	%xmm10, %xmm13
	packssdw	%xmm13, %xmm13
	packsswb	%xmm13, %xmm13
	movd	%xmm13, %edi
	shrl	$8, %edi
	testb	$1, %dil
	je	.LBB7_6
# %bb.5:                                #   in Loop: Header=BB7_2 Depth=1
	movb	%sil, 1(%rax,%rdx)
.LBB7_6:                                #   in Loop: Header=BB7_2 Depth=1
	movdqa	%xmm7, %xmm0
	pxor	%xmm9, %xmm0
	movdqa	%xmm0, %xmm11
	pcmpgtd	%xmm12, %xmm11
	pshufd	$160, %xmm11, %xmm13            # xmm13 = xmm11[0,0,2,2]
	pcmpeqd	%xmm12, %xmm0
	pshufd	$245, %xmm0, %xmm14             # xmm14 = xmm0[1,1,3,3]
	movdqa	%xmm14, %xmm0
	pand	%xmm13, %xmm0
	pshufd	$245, %xmm11, %xmm15            # xmm15 = xmm11[1,1,3,3]
	por	%xmm15, %xmm0
	packssdw	%xmm0, %xmm0
	pxor	%xmm10, %xmm0
	packssdw	%xmm0, %xmm0
	packsswb	%xmm0, %xmm0
	movd	%xmm0, %edi
	shrl	$16, %edi
	testb	$1, %dil
	je	.LBB7_8
# %bb.7:                                #   in Loop: Header=BB7_2 Depth=1
	movb	%sil, 2(%rax,%rdx)
.LBB7_8:                                #   in Loop: Header=BB7_2 Depth=1
	pshufhw	$132, %xmm13, %xmm0             # xmm0 = xmm13[0,1,2,3,4,5,4,6]
	pshufhw	$132, %xmm14, %xmm11            # xmm11 = xmm14[0,1,2,3,4,5,4,6]
	pand	%xmm0, %xmm11
	pshufhw	$132, %xmm15, %xmm0             # xmm0 = xmm15[0,1,2,3,4,5,4,6]
	por	%xmm11, %xmm0
	pxor	%xmm10, %xmm0
	packssdw	%xmm0, %xmm0
	packsswb	%xmm0, %xmm0
	movd	%xmm0, %edi
	shrl	$24, %edi
	testb	$1, %dil
	je	.LBB7_10
# %bb.9:                                #   in Loop: Header=BB7_2 Depth=1
	movb	%sil, 3(%rax,%rdx)
.LBB7_10:                               #   in Loop: Header=BB7_2 Depth=1
	movdqa	%xmm6, %xmm0
	pxor	%xmm9, %xmm0
	movdqa	%xmm0, %xmm11
	pcmpgtd	%xmm12, %xmm11
	pshufd	$160, %xmm11, %xmm14            # xmm14 = xmm11[0,0,2,2]
	pshuflw	$232, %xmm14, %xmm15            # xmm15 = xmm14[0,2,2,3,4,5,6,7]
	pcmpeqd	%xmm12, %xmm0
	pshufd	$245, %xmm0, %xmm13             # xmm13 = xmm0[1,1,3,3]
	pshuflw	$232, %xmm13, %xmm0             # xmm0 = xmm13[0,2,2,3,4,5,6,7]
	pand	%xmm15, %xmm0
	pshufd	$245, %xmm11, %xmm15            # xmm15 = xmm11[1,1,3,3]
	pshuflw	$232, %xmm15, %xmm11            # xmm11 = xmm15[0,2,2,3,4,5,6,7]
	por	%xmm0, %xmm11
	pxor	%xmm10, %xmm11
	packssdw	%xmm11, %xmm0
	packsswb	%xmm0, %xmm0
	pextrw	$2, %xmm0, %edi
	testb	$1, %dil
	je	.LBB7_12
# %bb.11:                               #   in Loop: Header=BB7_2 Depth=1
	movb	%sil, 4(%rax,%rdx)
.LBB7_12:                               #   in Loop: Header=BB7_2 Depth=1
	pand	%xmm14, %xmm13
	por	%xmm15, %xmm13
	packssdw	%xmm13, %xmm13
	pxor	%xmm10, %xmm13
	packssdw	%xmm13, %xmm0
	packsswb	%xmm0, %xmm0
	pextrw	$2, %xmm0, %edi
	shrl	$8, %edi
	testb	$1, %dil
	je	.LBB7_14
# %bb.13:                               #   in Loop: Header=BB7_2 Depth=1
	movb	%sil, 5(%rax,%rdx)
.LBB7_14:                               #   in Loop: Header=BB7_2 Depth=1
	movdqa	%xmm5, %xmm0
	pxor	%xmm9, %xmm0
	movdqa	%xmm0, %xmm11
	pcmpgtd	%xmm12, %xmm11
	pshufd	$160, %xmm11, %xmm13            # xmm13 = xmm11[0,0,2,2]
	pcmpeqd	%xmm12, %xmm0
	pshufd	$245, %xmm0, %xmm14             # xmm14 = xmm0[1,1,3,3]
	movdqa	%xmm14, %xmm0
	pand	%xmm13, %xmm0
	pshufd	$245, %xmm11, %xmm15            # xmm15 = xmm11[1,1,3,3]
	por	%xmm15, %xmm0
	packssdw	%xmm0, %xmm0
	pxor	%xmm10, %xmm0
	packssdw	%xmm0, %xmm0
	packsswb	%xmm0, %xmm0
	pextrw	$3, %xmm0, %edi
	testb	$1, %dil
	je	.LBB7_16
# %bb.15:                               #   in Loop: Header=BB7_2 Depth=1
	movb	%sil, 6(%rax,%rdx)
.LBB7_16:                               #   in Loop: Header=BB7_2 Depth=1
	pshufhw	$132, %xmm13, %xmm0             # xmm0 = xmm13[0,1,2,3,4,5,4,6]
	pshufhw	$132, %xmm14, %xmm11            # xmm11 = xmm14[0,1,2,3,4,5,4,6]
	pand	%xmm0, %xmm11
	pshufhw	$132, %xmm15, %xmm0             # xmm0 = xmm15[0,1,2,3,4,5,4,6]
	por	%xmm11, %xmm0
	pxor	%xmm10, %xmm0
	packssdw	%xmm0, %xmm0
	packsswb	%xmm0, %xmm0
	pextrw	$3, %xmm0, %edi
	shrl	$8, %edi
	testb	$1, %dil
	je	.LBB7_18
# %bb.17:                               #   in Loop: Header=BB7_2 Depth=1
	movb	%sil, 7(%rax,%rdx)
.LBB7_18:                               #   in Loop: Header=BB7_2 Depth=1
	movdqa	%xmm4, %xmm0
	pxor	%xmm9, %xmm0
	movdqa	%xmm0, %xmm11
	pcmpgtd	%xmm12, %xmm11
	pshufd	$160, %xmm11, %xmm14            # xmm14 = xmm11[0,0,2,2]
	pshuflw	$232, %xmm14, %xmm15            # xmm15 = xmm14[0,2,2,3,4,5,6,7]
	pcmpeqd	%xmm12, %xmm0
	pshufd	$245, %xmm0, %xmm13             # xmm13 = xmm0[1,1,3,3]
	pshuflw	$232, %xmm13, %xmm0             # xmm0 = xmm13[0,2,2,3,4,5,6,7]
	pand	%xmm15, %xmm0
	pshufd	$245, %xmm11, %xmm15            # xmm15 = xmm11[1,1,3,3]
	pshuflw	$232, %xmm15, %xmm11            # xmm11 = xmm15[0,2,2,3,4,5,6,7]
	por	%xmm0, %xmm11
	pxor	%xmm10, %xmm11
	packssdw	%xmm11, %xmm11
	packsswb	%xmm11, %xmm0
	pextrw	$4, %xmm0, %edi
	testb	$1, %dil
	je	.LBB7_20
# %bb.19:                               #   in Loop: Header=BB7_2 Depth=1
	movb	%sil, 8(%rax,%rdx)
.LBB7_20:                               #   in Loop: Header=BB7_2 Depth=1
	pand	%xmm14, %xmm13
	por	%xmm15, %xmm13
	packssdw	%xmm13, %xmm13
	pxor	%xmm10, %xmm13
	packssdw	%xmm13, %xmm13
	packsswb	%xmm13, %xmm0
	pextrw	$4, %xmm0, %edi
	shrl	$8, %edi
	testb	$1, %dil
	je	.LBB7_22
# %bb.21:                               #   in Loop: Header=BB7_2 Depth=1
	movb	%sil, 9(%rax,%rdx)
.LBB7_22:                               #   in Loop: Header=BB7_2 Depth=1
	movdqa	%xmm3, %xmm0
	pxor	%xmm9, %xmm0
	movdqa	%xmm0, %xmm11
	pcmpgtd	%xmm12, %xmm11
	pshufd	$160, %xmm11, %xmm13            # xmm13 = xmm11[0,0,2,2]
	pcmpeqd	%xmm12, %xmm0
	pshufd	$245, %xmm0, %xmm14             # xmm14 = xmm0[1,1,3,3]
	movdqa	%xmm14, %xmm0
	pand	%xmm13, %xmm0
	pshufd	$245, %xmm11, %xmm15            # xmm15 = xmm11[1,1,3,3]
	por	%xmm15, %xmm0
	packssdw	%xmm0, %xmm0
	pxor	%xmm10, %xmm0
	packssdw	%xmm0, %xmm0
	packsswb	%xmm0, %xmm0
	pextrw	$5, %xmm0, %edi
	testb	$1, %dil
	je	.LBB7_24
# %bb.23:                               #   in Loop: Header=BB7_2 Depth=1
	movb	%sil, 10(%rax,%rdx)
.LBB7_24:                               #   in Loop: Header=BB7_2 Depth=1
	pshufhw	$132, %xmm13, %xmm0             # xmm0 = xmm13[0,1,2,3,4,5,4,6]
	pshufhw	$132, %xmm14, %xmm11            # xmm11 = xmm14[0,1,2,3,4,5,4,6]
	pand	%xmm0, %xmm11
	pshufhw	$132, %xmm15, %xmm0             # xmm0 = xmm15[0,1,2,3,4,5,4,6]
	por	%xmm11, %xmm0
	pxor	%xmm10, %xmm0
	packssdw	%xmm0, %xmm0
	packsswb	%xmm0, %xmm0
	pextrw	$5, %xmm0, %edi
	shrl	$8, %edi
	testb	$1, %dil
	je	.LBB7_26
# %bb.25:                               #   in Loop: Header=BB7_2 Depth=1
	movb	%sil, 11(%rax,%rdx)
.LBB7_26:                               #   in Loop: Header=BB7_2 Depth=1
	movdqa	%xmm2, %xmm0
	pxor	%xmm9, %xmm0
	movdqa	%xmm0, %xmm11
	pcmpgtd	%xmm12, %xmm11
	pshufd	$160, %xmm11, %xmm14            # xmm14 = xmm11[0,0,2,2]
	pshuflw	$232, %xmm14, %xmm15            # xmm15 = xmm14[0,2,2,3,4,5,6,7]
	pcmpeqd	%xmm12, %xmm0
	pshufd	$245, %xmm0, %xmm13             # xmm13 = xmm0[1,1,3,3]
	pshuflw	$232, %xmm13, %xmm0             # xmm0 = xmm13[0,2,2,3,4,5,6,7]
	pand	%xmm15, %xmm0
	pshufd	$245, %xmm11, %xmm15            # xmm15 = xmm11[1,1,3,3]
	pshuflw	$232, %xmm15, %xmm11            # xmm11 = xmm15[0,2,2,3,4,5,6,7]
	por	%xmm0, %xmm11
	pxor	%xmm10, %xmm11
	packssdw	%xmm11, %xmm0
	packsswb	%xmm0, %xmm0
	pextrw	$6, %xmm0, %edi
	testb	$1, %dil
	je	.LBB7_28
# %bb.27:                               #   in Loop: Header=BB7_2 Depth=1
	movb	%sil, 12(%rax,%rdx)
.LBB7_28:                               #   in Loop: Header=BB7_2 Depth=1
	pand	%xmm14, %xmm13
	por	%xmm15, %xmm13
	packssdw	%xmm13, %xmm13
	pxor	%xmm10, %xmm13
	packssdw	%xmm13, %xmm0
	packsswb	%xmm0, %xmm0
	pextrw	$6, %xmm0, %edi
	shrl	$8, %edi
	testb	$1, %dil
	je	.LBB7_30
# %bb.29:                               #   in Loop: Header=BB7_2 Depth=1
	movb	%sil, 13(%rax,%rdx)
.LBB7_30:                               #   in Loop: Header=BB7_2 Depth=1
	movdqa	%xmm1, %xmm0
	pxor	%xmm9, %xmm0
	movdqa	%xmm0, %xmm11
	pcmpgtd	%xmm12, %xmm11
	pshufd	$160, %xmm11, %xmm13            # xmm13 = xmm11[0,0,2,2]
	pcmpeqd	%xmm12, %xmm0
	pshufd	$245, %xmm0, %xmm12             # xmm12 = xmm0[1,1,3,3]
	movdqa	%xmm12, %xmm0
	pand	%xmm13, %xmm0
	pshufd	$245, %xmm11, %xmm14            # xmm14 = xmm11[1,1,3,3]
	por	%xmm14, %xmm0
	packssdw	%xmm0, %xmm0
	pxor	%xmm10, %xmm0
	packssdw	%xmm0, %xmm0
	packsswb	%xmm0, %xmm0
	pextrw	$7, %xmm0, %edi
	testb	$1, %dil
	je	.LBB7_32
# %bb.31:                               #   in Loop: Header=BB7_2 Depth=1
	movb	%sil, 14(%rax,%rdx)
.LBB7_32:                               #   in Loop: Header=BB7_2 Depth=1
	pshufhw	$132, %xmm13, %xmm0             # xmm0 = xmm13[0,1,2,3,4,5,4,6]
	pshufhw	$132, %xmm12, %xmm11            # xmm11 = xmm12[0,1,2,3,4,5,4,6]
	pand	%xmm0, %xmm11
	pshufhw	$132, %xmm14, %xmm0             # xmm0 = xmm14[0,1,2,3,4,5,4,6]
	por	%xmm11, %xmm0
	pxor	%xmm10, %xmm0
	packssdw	%xmm0, %xmm0
	packsswb	%xmm0, %xmm0
	pextrw	$7, %xmm0, %edi
	shrl	$8, %edi
	testb	$1, %dil
	je	.LBB7_34
# %bb.33:                               #   in Loop: Header=BB7_2 Depth=1
	movb	%sil, 15(%rax,%rdx)
.LBB7_34:                               #   in Loop: Header=BB7_2 Depth=1
	addq	$16, %rdx
	movdqa	.LCPI7_9(%rip), %xmm0           # xmm0 = [16,16]
	paddq	%xmm0, %xmm8
	paddq	%xmm0, %xmm7
	paddq	%xmm0, %xmm6
	paddq	%xmm0, %xmm5
	paddq	%xmm0, %xmm4
	paddq	%xmm0, %xmm3
	paddq	%xmm0, %xmm2
	paddq	%xmm0, %xmm1
	cmpq	%rdx, %rcx
	jne	.LBB7_2
# %bb.35:
	movq	%rbp, %rsp
	popq	%rbp
.LBB7_36:
	retq
.Lfunc_end7:
	.size	memset, .Lfunc_end7-memset
                                        # -- End function
	.globl	memcmp                          # -- Begin function memcmp
	.type	memcmp,@function
memcmp:                                 # @memcmp
# %bb.0:
	pushq	%rbp
	movq	%rsp, %rbp
	andq	$-8, %rsp
	testq	%rdx, %rdx
	je	.LBB8_1
# %bb.3:
	xorl	%ecx, %ecx
.LBB8_4:                                # =>This Inner Loop Header: Depth=1
	movzbl	(%rdi,%rcx), %eax
	movzbl	(%rsi,%rcx), %r8d
	cmpb	%r8b, %al
	jne	.LBB8_5
# %bb.2:                                #   in Loop: Header=BB8_4 Depth=1
	incq	%rcx
	cmpq	%rcx, %rdx
	jne	.LBB8_4
.LBB8_1:
	xorl	%eax, %eax
	jmp	.LBB8_6
.LBB8_5:
	subl	%r8d, %eax
.LBB8_6:
	movq	%rbp, %rsp
	popq	%rbp
	retq
.Lfunc_end8:
	.size	memcmp, .Lfunc_end8-memcmp
                                        # -- End function
	.globl	snes_runtime_log                # -- Begin function snes_runtime_log
	.type	snes_runtime_log,@function
snes_runtime_log:                       # @snes_runtime_log
# %bb.0:
	movq	%rdi, %rcx
	testq	%rdi, %rdi
	setne	%dl
	movl	g_log_fd(%rip), %eax
	testl	%eax, %eax
	setns	%dil
	movq	g_sendto_fn(%rip), %rsi
	testq	%rsi, %rsi
	setne	%r8b
	andb	%dl, %r8b
	andb	%dil, %r8b
	cmpb	$1, %r8b
	jne	.LBB9_4
# %bb.1:
	movl	%eax, %edx
	movq	$-1, %r8
.LBB9_2:                                # =>This Inner Loop Header: Depth=1
	cmpb	$0, 1(%rcx,%r8)
	leaq	1(%r8), %r8
	jne	.LBB9_2
# %bb.3:
	pushq	%rbp
	movq	%rsp, %rbp
	andq	$-16, %rsp
	movq	g_gadget(%rip), %rdi
	leaq	g_log_sa(%rip), %rax
	xorl	%r9d, %r9d
	pushq	$16
	pushq	%rax
	callq	native_call
	addq	$16, %rsp
	movq	%rbp, %rsp
	popq	%rbp
.LBB9_4:
	retq
.Lfunc_end9:
	.size	snes_runtime_log, .Lfunc_end9-snes_runtime_log
                                        # -- End function
	.type	native_call,@function           # -- Begin function native_call
native_call:                            # @native_call
# %bb.0:
	#APP
	pushq	%rbx
	movq	%rsi, %rbx
	movq	%rdi, %rax
	movq	%rdx, %rdi
	movq	%rcx, %rsi
	movq	%r8, %rdx
	movq	%r9, %rcx
	movq	16(%rsp), %r8
	movq	24(%rsp), %r9
	callq	*%rax
	popq	%rbx
	retq
	#NO_APP
.Lfunc_end10:
	.size	native_call, .Lfunc_end10-native_call
                                        # -- End function
	.globl	snes_runtime_vlogf              # -- Begin function snes_runtime_vlogf
	.type	snes_runtime_vlogf,@function
snes_runtime_vlogf:                     # @snes_runtime_vlogf
# %bb.0:
	pushq	%rbp
	movq	%rsp, %rbp
	pushq	%r15
	pushq	%r14
	pushq	%r12
	pushq	%rbx
	andq	$-16, %rsp
	subq	$512, %rsp                      # imm = 0x200
	movq	%rsi, %rbx
	movq	%rdi, %r14
	xorl	%eax, %eax
	movq	%rsp, %r15
	leaq	.L.str(%rip), %r12
.LBB11_1:                               # =>This Loop Header: Depth=1
                                        #     Child Loop BB11_38 Depth 2
	movzbl	(%r14), %ecx
	cmpl	$37, %ecx
	je	.LBB11_6
# %bb.2:                                #   in Loop: Header=BB11_1 Depth=1
	testl	%ecx, %ecx
	je	.LBB11_60
# %bb.3:                                #   in Loop: Header=BB11_1 Depth=1
	cmpl	$510, %eax                      # imm = 0x1FE
	jg	.LBB11_5
# %bb.4:                                #   in Loop: Header=BB11_1 Depth=1
	movslq	%eax, %rdx
	movb	%cl, (%rsp,%rdx)
.LBB11_5:                               #   in Loop: Header=BB11_1 Depth=1
	incl	%eax
	jmp	.LBB11_59
.LBB11_6:                               #   in Loop: Header=BB11_1 Depth=1
	movzbl	1(%r14), %ecx
	incq	%r14
	cmpl	$104, %ecx
	jg	.LBB11_19
# %bb.7:                                #   in Loop: Header=BB11_1 Depth=1
	cmpl	$98, %ecx
	jg	.LBB11_15
# %bb.8:                                #   in Loop: Header=BB11_1 Depth=1
	cmpl	$37, %ecx
	je	.LBB11_28
# %bb.9:                                #   in Loop: Header=BB11_1 Depth=1
	cmpl	$88, %ecx
	jne	.LBB11_10
# %bb.54:                               #   in Loop: Header=BB11_1 Depth=1
	movl	(%rbx), %edx
	cmpq	$40, %rdx
	ja	.LBB11_56
# %bb.55:                               #   in Loop: Header=BB11_1 Depth=1
	movq	%rdx, %rcx
	addq	16(%rbx), %rcx
	addl	$8, %edx
	movl	%edx, (%rbx)
	jmp	.LBB11_57
.LBB11_19:                              #   in Loop: Header=BB11_1 Depth=1
	cmpl	$116, %ecx
	jg	.LBB11_24
# %bb.20:                               #   in Loop: Header=BB11_1 Depth=1
	cmpl	$105, %ecx
	je	.LBB11_17
# %bb.21:                               #   in Loop: Header=BB11_1 Depth=1
	cmpl	$115, %ecx
	jne	.LBB11_11
# %bb.22:                               #   in Loop: Header=BB11_1 Depth=1
	movl	(%rbx), %edx
	cmpq	$40, %rdx
	ja	.LBB11_35
# %bb.23:                               #   in Loop: Header=BB11_1 Depth=1
	movq	%rdx, %rcx
	addq	16(%rbx), %rcx
	addl	$8, %edx
	movl	%edx, (%rbx)
	jmp	.LBB11_36
.LBB11_15:                              #   in Loop: Header=BB11_1 Depth=1
	cmpl	$99, %ecx
	je	.LBB11_30
# %bb.16:                               #   in Loop: Header=BB11_1 Depth=1
	cmpl	$100, %ecx
	jne	.LBB11_11
.LBB11_17:                              #   in Loop: Header=BB11_1 Depth=1
	movl	(%rbx), %edx
	cmpq	$40, %rdx
	ja	.LBB11_41
# %bb.18:                               #   in Loop: Header=BB11_1 Depth=1
	movq	%rdx, %rcx
	addq	16(%rbx), %rcx
	addl	$8, %edx
	movl	%edx, (%rbx)
	jmp	.LBB11_42
.LBB11_24:                              #   in Loop: Header=BB11_1 Depth=1
	cmpl	$117, %ecx
	je	.LBB11_48
# %bb.25:                               #   in Loop: Header=BB11_1 Depth=1
	cmpl	$120, %ecx
	jne	.LBB11_11
# %bb.26:                               #   in Loop: Header=BB11_1 Depth=1
	movl	(%rbx), %edx
	cmpq	$40, %rdx
	ja	.LBB11_52
# %bb.27:                               #   in Loop: Header=BB11_1 Depth=1
	movq	%rdx, %rcx
	addq	16(%rbx), %rcx
	addl	$8, %edx
	movl	%edx, (%rbx)
	jmp	.LBB11_53
.LBB11_30:                              #   in Loop: Header=BB11_1 Depth=1
	movl	(%rbx), %edx
	cmpq	$40, %rdx
	ja	.LBB11_32
# %bb.31:                               #   in Loop: Header=BB11_1 Depth=1
	movq	%rdx, %rcx
	addq	16(%rbx), %rcx
	addl	$8, %edx
	movl	%edx, (%rbx)
	jmp	.LBB11_33
.LBB11_48:                              #   in Loop: Header=BB11_1 Depth=1
	movl	(%rbx), %edx
	cmpq	$40, %rdx
	ja	.LBB11_50
# %bb.49:                               #   in Loop: Header=BB11_1 Depth=1
	movq	%rdx, %rcx
	addq	16(%rbx), %rcx
	addl	$8, %edx
	movl	%edx, (%rbx)
	jmp	.LBB11_51
.LBB11_41:                              #   in Loop: Header=BB11_1 Depth=1
	movq	8(%rbx), %rcx
	leaq	8(%rcx), %rdx
	movq	%rdx, 8(%rbx)
.LBB11_42:                              #   in Loop: Header=BB11_1 Depth=1
	movl	(%rcx), %edx
	testl	%edx, %edx
	jns	.LBB11_46
# %bb.43:                               #   in Loop: Header=BB11_1 Depth=1
	cmpl	$510, %eax                      # imm = 0x1FE
	jg	.LBB11_45
# %bb.44:                               #   in Loop: Header=BB11_1 Depth=1
	movslq	%eax, %rcx
	movb	$45, (%rsp,%rcx)
.LBB11_45:                              #   in Loop: Header=BB11_1 Depth=1
	incl	%eax
	negl	%edx
	jmp	.LBB11_46
.LBB11_28:                              #   in Loop: Header=BB11_1 Depth=1
	cmpl	$510, %eax                      # imm = 0x1FE
	jg	.LBB11_5
# %bb.29:                               #   in Loop: Header=BB11_1 Depth=1
	movslq	%eax, %rcx
	movb	$37, (%rsp,%rcx)
	jmp	.LBB11_5
.LBB11_32:                              #   in Loop: Header=BB11_1 Depth=1
	movq	8(%rbx), %rcx
	leaq	8(%rcx), %rdx
	movq	%rdx, 8(%rbx)
.LBB11_33:                              #   in Loop: Header=BB11_1 Depth=1
	cmpl	$510, %eax                      # imm = 0x1FE
	jg	.LBB11_5
# %bb.34:                               #   in Loop: Header=BB11_1 Depth=1
	movb	(%rcx), %cl
	movslq	%eax, %rdx
	movb	%cl, (%rsp,%rdx)
	jmp	.LBB11_5
.LBB11_56:                              #   in Loop: Header=BB11_1 Depth=1
	movq	8(%rbx), %rcx
	leaq	8(%rcx), %rdx
	movq	%rdx, 8(%rbx)
.LBB11_57:                              #   in Loop: Header=BB11_1 Depth=1
	movl	(%rcx), %edx
	movq	%r15, %rdi
	movl	%eax, %esi
	movl	$16, %ecx
	movl	$1, %r8d
	jmp	.LBB11_58
.LBB11_50:                              #   in Loop: Header=BB11_1 Depth=1
	movq	8(%rbx), %rcx
	leaq	8(%rcx), %rdx
	movq	%rdx, 8(%rbx)
.LBB11_51:                              #   in Loop: Header=BB11_1 Depth=1
	movl	(%rcx), %edx
.LBB11_46:                              #   in Loop: Header=BB11_1 Depth=1
	movq	%r15, %rdi
	movl	%eax, %esi
	movl	$10, %ecx
	jmp	.LBB11_47
.LBB11_35:                              #   in Loop: Header=BB11_1 Depth=1
	movq	8(%rbx), %rcx
	leaq	8(%rcx), %rdx
	movq	%rdx, 8(%rbx)
.LBB11_36:                              #   in Loop: Header=BB11_1 Depth=1
	movq	(%rcx), %rcx
	testq	%rcx, %rcx
	cmoveq	%r12, %rcx
	movb	(%rcx), %sil
	testb	%sil, %sil
	je	.LBB11_59
# %bb.37:                               #   in Loop: Header=BB11_1 Depth=1
	movslq	%eax, %rdx
	incq	%rcx
.LBB11_38:                              #   Parent Loop BB11_1 Depth=1
                                        # =>  This Inner Loop Header: Depth=2
	cmpq	$510, %rdx                      # imm = 0x1FE
	jg	.LBB11_40
# %bb.39:                               #   in Loop: Header=BB11_38 Depth=2
	movb	%sil, (%rsp,%rdx)
.LBB11_40:                              #   in Loop: Header=BB11_38 Depth=2
	incq	%rdx
	movb	(%rcx), %sil
	incl	%eax
	incq	%rcx
	testb	%sil, %sil
	jne	.LBB11_38
	jmp	.LBB11_59
.LBB11_52:                              #   in Loop: Header=BB11_1 Depth=1
	movq	8(%rbx), %rcx
	leaq	8(%rcx), %rdx
	movq	%rdx, 8(%rbx)
.LBB11_53:                              #   in Loop: Header=BB11_1 Depth=1
	movl	(%rcx), %edx
	movq	%r15, %rdi
	movl	%eax, %esi
	movl	$16, %ecx
.LBB11_47:                              #   in Loop: Header=BB11_1 Depth=1
	xorl	%r8d, %r8d
.LBB11_58:                              #   in Loop: Header=BB11_1 Depth=1
	callq	append_u32_base
.LBB11_59:                              #   in Loop: Header=BB11_1 Depth=1
	incq	%r14
	jmp	.LBB11_1
.LBB11_10:                              #   in Loop: Header=BB11_1 Depth=1
	testl	%ecx, %ecx
	je	.LBB11_60
.LBB11_11:                              #   in Loop: Header=BB11_1 Depth=1
	cmpl	$510, %eax                      # imm = 0x1FE
	jg	.LBB11_14
# %bb.12:                               #   in Loop: Header=BB11_1 Depth=1
	movslq	%eax, %rcx
	movb	$37, (%rsp,%rcx)
	je	.LBB11_14
# %bb.13:                               #   in Loop: Header=BB11_1 Depth=1
	movb	(%r14), %dl
	movb	%dl, 1(%rsp,%rcx)
.LBB11_14:                              #   in Loop: Header=BB11_1 Depth=1
	addl	$2, %eax
	jmp	.LBB11_59
.LBB11_60:
	movl	$511, %ecx                      # imm = 0x1FF
	cmpl	%ecx, %eax
	cmovll	%eax, %ecx
	movslq	%ecx, %rax
	movb	$0, (%rsp,%rax)
	movq	%rsp, %rdi
	callq	snes_runtime_log@PLT
	leaq	-32(%rbp), %rsp
	popq	%rbx
	popq	%r12
	popq	%r14
	popq	%r15
	popq	%rbp
	retq
.Lfunc_end11:
	.size	snes_runtime_vlogf, .Lfunc_end11-snes_runtime_vlogf
                                        # -- End function
	.type	append_u32_base,@function       # -- Begin function append_u32_base
append_u32_base:                        # @append_u32_base
# %bb.0:
                                        # kill: def $esi killed $esi def $rsi
	testl	%edx, %edx
	je	.LBB12_9
# %bb.1:
	pushq	%rbp
	movq	%rsp, %rbp
	pushq	%rbx
	andq	$-16, %rsp
	subq	$32, %rsp
	movl	%edx, %r9d
	xorl	%r10d, %r10d
	testl	%r8d, %r8d
	sete	%r10b
	shll	$5, %r10d
	addl	$55, %r10d
	xorl	%r8d, %r8d
.LBB12_2:                               # =>This Inner Loop Header: Depth=1
	movl	%r9d, %eax
	xorl	%edx, %edx
	divl	%ecx
                                        # kill: def $edx killed $edx def $rdx
	leal	(%r10,%rdx), %r11d
	movl	%edx, %ebx
	orb	$48, %bl
	cmpl	$10, %edx
	movzbl	%bl, %ebx
	cmovael	%r11d, %ebx
	leaq	1(%r8), %rdx
	movb	%bl, (%rsp,%r8)
	cmpl	%r9d, %ecx
	ja	.LBB12_4
# %bb.3:                                #   in Loop: Header=BB12_2 Depth=1
	movl	%eax, %r9d
	cmpq	$15, %r8
	movq	%rdx, %r8
	jb	.LBB12_2
.LBB12_4:
	movslq	%esi, %rsi
	incq	%rdx
.LBB12_5:                               # =>This Inner Loop Header: Depth=1
	cmpq	$510, %rsi                      # imm = 0x1FE
	jg	.LBB12_7
# %bb.6:                                #   in Loop: Header=BB12_5 Depth=1
	movb	-2(%rsp,%rdx), %al
	movb	%al, (%rdi,%rsi)
.LBB12_7:                               #   in Loop: Header=BB12_5 Depth=1
	incq	%rsi
	decq	%rdx
	cmpq	$1, %rdx
	jg	.LBB12_5
# %bb.8:
	leaq	-8(%rbp), %rsp
	popq	%rbx
	popq	%rbp
	jmp	.LBB12_12
.LBB12_9:
	cmpl	$510, %esi                      # imm = 0x1FE
	jg	.LBB12_11
# %bb.10:
	movslq	%esi, %rax
	movb	$48, (%rdi,%rax)
.LBB12_11:
	incl	%esi
.LBB12_12:
	movl	%esi, %eax
	retq
.Lfunc_end12:
	.size	append_u32_base, .Lfunc_end12-append_u32_base
                                        # -- End function
	.globl	snes_runtime_logf               # -- Begin function snes_runtime_logf
	.type	snes_runtime_logf,@function
snes_runtime_logf:                      # @snes_runtime_logf
# %bb.0:
	pushq	%rbp
	movq	%rsp, %rbp
	andq	$-16, %rsp
	subq	$208, %rsp
	leaq	32(%rsp), %r10
	movq	%rsi, 8(%r10)
	movq	%rdx, 16(%r10)
	movq	%rcx, 24(%r10)
	movq	%r8, 32(%r10)
	movq	%r9, 40(%r10)
	testb	%al, %al
	je	.LBB13_2
# %bb.1:
	movaps	%xmm0, 80(%rsp)
	movaps	%xmm1, 96(%rsp)
	movaps	%xmm2, 112(%rsp)
	movaps	%xmm3, 128(%rsp)
	movaps	%xmm4, 144(%rsp)
	movaps	%xmm5, 160(%rsp)
	movaps	%xmm6, 176(%rsp)
	movaps	%xmm7, 192(%rsp)
.LBB13_2:
	movq	%rsp, %rsi
	movq	%r10, 16(%rsi)
	leaq	16(%rbp), %rax
	movq	%rax, 8(%rsi)
	movabsq	$206158430216, %rax             # imm = 0x3000000008
	movq	%rax, (%rsi)
	callq	snes_runtime_vlogf@PLT
	movq	%rbp, %rsp
	popq	%rbp
	retq
.Lfunc_end13:
	.size	snes_runtime_logf, .Lfunc_end13-snes_runtime_logf
                                        # -- End function
	.globl	vprintf                         # -- Begin function vprintf
	.type	vprintf,@function
vprintf:                                # @vprintf
# %bb.0:
	pushq	%rbp
	movq	%rsp, %rbp
	andq	$-16, %rsp
	subq	$32, %rsp
	movq	16(%rsi), %rcx
	movq	%rsp, %rax
	movq	%rcx, 16(%rax)
	movups	(%rsi), %xmm0
	movaps	%xmm0, (%rax)
	movq	%rax, %rsi
	callq	snes_runtime_vlogf@PLT
	xorl	%eax, %eax
	movq	%rbp, %rsp
	popq	%rbp
	retq
.Lfunc_end14:
	.size	vprintf, .Lfunc_end14-vprintf
                                        # -- End function
	.globl	printf                          # -- Begin function printf
	.type	printf,@function
printf:                                 # @printf
# %bb.0:
	pushq	%rbp
	movq	%rsp, %rbp
	andq	$-16, %rsp
	subq	$208, %rsp
	leaq	32(%rsp), %r10
	movq	%rsi, 8(%r10)
	movq	%rdx, 16(%r10)
	movq	%rcx, 24(%r10)
	movq	%r8, 32(%r10)
	movq	%r9, 40(%r10)
	testb	%al, %al
	je	.LBB15_2
# %bb.1:
	movaps	%xmm0, 80(%rsp)
	movaps	%xmm1, 96(%rsp)
	movaps	%xmm2, 112(%rsp)
	movaps	%xmm3, 128(%rsp)
	movaps	%xmm4, 144(%rsp)
	movaps	%xmm5, 160(%rsp)
	movaps	%xmm6, 176(%rsp)
	movaps	%xmm7, 192(%rsp)
.LBB15_2:
	movq	%rsp, %rsi
	movq	%r10, 16(%rsi)
	leaq	16(%rbp), %rax
	movq	%rax, 8(%rsi)
	movabsq	$206158430216, %rax             # imm = 0x3000000008
	movq	%rax, (%rsi)
	callq	snes_runtime_vlogf@PLT
	xorl	%eax, %eax
	movq	%rbp, %rsp
	popq	%rbp
	retq
.Lfunc_end15:
	.size	printf, .Lfunc_end15-printf
                                        # -- End function
	.type	g_heap_base,@object             # @g_heap_base
	.local	g_heap_base
	.comm	g_heap_base,8,8
	.type	g_heap_ptr,@object              # @g_heap_ptr
	.local	g_heap_ptr
	.comm	g_heap_ptr,8,8
	.type	g_heap_end,@object              # @g_heap_end
	.local	g_heap_end
	.comm	g_heap_end,8,8
	.type	g_gadget,@object                # @g_gadget
	.local	g_gadget
	.comm	g_gadget,8,8
	.type	g_sendto_fn,@object             # @g_sendto_fn
	.local	g_sendto_fn
	.comm	g_sendto_fn,8,8
	.type	g_log_fd,@object                # @g_log_fd
	.data
	.p2align	2, 0x0
g_log_fd:
	.long	4294967295                      # 0xffffffff
	.size	g_log_fd, 4

	.type	g_log_sa,@object                # @g_log_sa
	.local	g_log_sa
	.comm	g_log_sa,16,16
	.type	.L.str,@object                  # @.str
	.section	.rodata.str1.1,"aMS",@progbits,1
.L.str:
	.asciz	"(null)"
	.size	.L.str, 7

	.ident	"clang version 20.1.2 (https://github.com/ziglang/zig-bootstrap 7ef74e656cf8ddbd6bf891a8475892aa1afa6891)"
	.section	".note.GNU-stack","",@progbits
	.addrsig
	.addrsig_sym native_call
	.addrsig_sym g_log_sa
