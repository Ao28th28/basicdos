;
; BASIC-DOS Miscellaneous DOS Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	dosapi.inc

CODE    SEGMENT

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE

	org	5
	DEFLBL	DOS,near

	org	100h

DEFPROC	main
;
; The following REALLOC is not necessary in BASIC-DOS, because it detects
; our COMHEAP signature and resizes us automatically, but if we want to run
; with the same footprint in PC DOS, then we must still resize ourselves.
;
	mov	bx,offset HEAP + MINHEAP
	and	bl,0F0h
	or	bl,0Eh		; BX adjusted to top word of top paragraph
	mov	word ptr [bx],0	; store a zero there so we can simply return
	mov	sp,bx		; lower the stack
	mov	cl,4
	add	bx,15
	shr	bx,cl
	mov	ah,DOS_MEM_REALLOC
	int	21h
;
; In PC DOS 2.x, the DOS_MSC_GETVARS function (52h) sets ES:BX-2 to the
; address of the first MCB segment, and ES:BX+4 points to the SFT.
;
	mov	ah,DOS_MSC_GETVARS
	int	21h		; ES:[BX-2] -> mcb_head
;
; Test the CALL 5 interface.
;
	mov	dx,offset call5test
	call	print
;
; Make a series of increasingly large memory allocations.
;
	mov	dx,offset alloctest
	call	print

	mov	cx,3		; perform the series CX times
m1:	sub	bx,bx		; start with a zero paragraph request
m2:	mov	ah,DOS_MEM_ALLOC
	int	21h
	jc	m3
	mov	es,ax		; ES = new segment
	mov	ah,DOS_MEM_FREE
	int	21h
	ASSERT	NC
	inc	bx		; ask for more one paragraph
	jmp	m2
m3:	mov	dx,offset progress
	call	print
	loop	m1

	mov	dx,offset passed
	call	print

	push	ds
	pop	es
	mov	dx,offset execfile
	mov	ax,DOS_HDL_OPENRO
	int	21h		; open file (and neglect to close it)

	mov	bx,offset execparms
	mov	[bx].EPB_CMDTAIL.SEG,cs
	mov	[bx].EPB_FCB1.SEG,cs
	mov	[bx].EPB_FCB2.SEG,cs
	mov	ax,DOS_PSP_EXEC1
	mov	dx,offset execfile
	int	21h		; exec (but don't launch)

	mov	ah,DOS_PSP_GET	; check the current PSP
	int	21h

	mov	bx,cs
	mov	ah,DOS_PSP_SET	; ensure the current PSP is ours
	int	21h

	ret
ENDPROC	main

DEFPROC	print
	push	cx
	mov	cl,DOS_TTY_PRINT
	call	DOS
	pop	cx
	ret
ENDPROC	print

call5test	db		"CALL 5 test "
passed		db		"passed",13,10,'$'
progress	db		".$"
alloctest	db		"memory test$"

execfile	db		"tests.com",0
execparms	EPB		<0,PSP_CMDTAIL,PSP_FCB1,PSP_FCB2>
;
; COMHEAP 0 means we don't need a heap, but BASIC-DOS will still allocate a
; minimum amount of heap space, because that's where our initial stack lives.
;
	COMHEAP	0		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
