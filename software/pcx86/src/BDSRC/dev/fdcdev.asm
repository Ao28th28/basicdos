;
; BASIC-DOS Floppy Disk Controller Device Driver
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dev.inc

DEV	group	CODE,DATA

CODE	segment para public 'CODE'

	public	FDC
FDC 	DDH	<offset DEV:ddend+16,,DDATTR_BLOCK,offset ddinit,-1,2020202024434446h>

	DEFLBL	CMDTBL,word
	dw	ddcmd_none, ddcmd_none, ddcmd_buildbpb, ddcmd_none	; 0-3
	dw	ddcmd_read, ddcmd_none, ddcmd_none, ddcmd_none		; 4-7
	dw	ddcmd_write, ddcmd_none, ddcmd_none, ddcmd_none		; 8-11
	dw	ddcmd_none, ddcmd_none, ddcmd_none, ddcmd_none		; 12-15
	dw	ddcmd_none, ddcmd_none, ddcmd_none, ddcmd_none		; 16-19
	DEFABS	CMDTBL_SIZE,<($ - CMDTBL) SHR 1>

	DEFBYTE	ddbuf_drv,-1
	DEFWORD	ddbuf_lba,-1
	DEFPTR	ddbuf_ptr,<offset ddinit>

        ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver request
;
; Inputs:
;	ES:BX -> DDP
;
; Outputs:
;
DEFPROC	ddreq,far
	push	ax
	push	bx
	push	cx
	push	si
	push	di
	push	ds
	push	cs
	pop	ds
	ASSUME	DS:CODE
	mov	di,bx			; ES:DI -> DDP
	mov	bl,es:[di].DDP_CMD
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_UNKCMD
	cmp	bl,CMDTBL_SIZE
	jae	ddr9
	mov	bh,0
	add	bx,bx
	call	CMDTBL[bx]
ddr9:	pop	ds
	pop	di
	pop	si
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	ddreq

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcmd_buildbpb
;
; We're not in the business of allocating or managing BPBs (we leave that to
; DOS), so for now, the only purpose of this call is to signal that we need to
; flush our internal buffer cache.
;
; Inputs:
;	ES:DI -> DDP
;
; Outputs:
;	DDP updated appropriately
;
; Modifies:
;	AX, BX, CX, DX, SI, DS
;
DEFPROC	ddcmd_buildbpb
	ASSUME	DS:CODE
	mov	[ddbuf_drv],-1
	mov	[ddbuf_lba],-1
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	ret
ENDPROC	ddcmd_buildbpb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcmd_read
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;	DDPRW updated appropriately
;
; Modifies:
;	AX, BX, CX, DX, SI, DS
;
DEFPROC	ddcmd_read
	ASSUME	DS:CODE
	push	bp
	push	es
	mov	cx,es:[di].DDPRW_LENGTH
	test	cx,cx		; is length zero (ie, nothing to do)?
	jnz	dcr1		; no
	jmp	dcr8		; yes, all done
;
; If the offset is zero, then there's no need to read a partial first sector.
;
dcr1:	lds	si,es:[di].DDPRW_BPB
	ASSUME	DS:NOTHING
	mov	ax,es:[di].DDPRW_OFFSET
	test	ax,ax
	jz	dcr4
;
; As a preliminary matter, reduce offset and advance LBA until offset is
; within the first sector to read; moreover, if this reduces offset to zero,
; then once again, there's no need for a partial first sector read.
;
; We presume that DOS will not get carried here and generate ridiculously
; large offsets, hence the simple loop; the most common scenario would be
; requesting an offset beyond the first sector of a multi-sector cluster (but
; still within the cluster).
;
	int 3
dcr1a:	cmp	ax,[si].BPB_SECBYTES
	jb	dcr1b
	inc	es:[di].DDPRW_LBA
	sub	ax,[si].BPB_SECBYTES
	jz	dcr4
	jmp	dcr1a
dcr1b:	mov	es:[di].DDPRW_OFFSET,ax
	mov	al,[si].BPB_DRIVE
	cmp	al,[ddbuf_drv]
	jne	dcr1c
	mov	dx,es:[di].DDPRW_LBA
	cmp	dx,[ddbuf_lba]
	je	dcr2
dcr1c:	push	es
	les	bp,[ddbuf_ptr]	; ES:BP -> our own buffer
	mov	bx,(FDC_READ SHL 8) OR 1
	call	readwrite_sectors
	pop	es
	jc	dcr4a
	mov	al,[si].BPB_DRIVE
	mov	[ddbuf_drv],al
	mov	[ddbuf_lba],dx
;
; Reload the offset: copy bytes from ddbuf+offset to the target address.
;
dcr2:	mov	ax,es:[di].DDPRW_OFFSET
	add	cx,ax
	cmp	cx,[si].BPB_SECBYTES
	jb	dcr3		; make sure we don't read beyond the buffer
	mov	cx,[si].BPB_SECBYTES
dcr3:	push	si
	push	di
	push	ds
	push	es
	lds	si,[ddbuf_ptr]	; DS:SI -> our own buffer
	add	si,ax		; add offset
	mov	ax,cx
	les	di,es:[di].DDPRW_ADDR
	rep	movsb		; transfer bytes from our own buffer
	pop	es
	pop	ds
	pop	di
	pop	si
	inc	es:[di].DDPRW_LBA
	add	es:[di].DDPRW_ADDR.off,ax
	sub	es:[di].DDPRW_LENGTH,ax
	mov	cx,es:[di].DDPRW_LENGTH
;
; At this point, we know that the transfer offset is now zero, so we're free to
; transfer as many whole sectors as remain in the request.
;
dcr4:	int 3
	xchg	ax,cx		; convert length in AX to # sectors
	cwd
	div	[si].BPB_SECBYTES
	mov	cx,dx		; CX = final partial sector bytes, if any
	test	al,al		; any whole sectors?
	jz	dcr5		; no
	mov	ah,FDC_READ
	xchg	bx,ax		; BH = FDC cmd, BL = # sectors
	mov	dx,es:[di].DDPRW_LBA
	les	bp,es:[di].DDPRW_ADDR
	call	readwrite_sectors
dcr4a:	jc	dcr8
	mov	al,bl
	cbw
	add	es:[di].DDPRW_LBA,ax
	mul	[si].BPB_SECBYTES
	add	es:[di].DDPRW_ADDR.off,ax
	sub	es:[di].DDPRW_LENGTH,ax
;
; And finally, the tail end of the request, if there are CX bytes remaining.
;
dcr5:	test	cx,cx
	jz	dcr8		; nothing remaining

dcr6:	int 3
	mov	dx,es:[di].DDPRW_LBA
	mov	al,[si].BPB_DRIVE
	cmp	al,[ddbuf_drv]
	jne	dcr6a
	cmp	dx,[ddbuf_lba]
	je	dcr7
dcr6a:	push	es
	les	bp,[ddbuf_ptr]	; ES:BP -> our own buffer
	mov	bx,(FDC_READ SHL 8) OR 1
	call	readwrite_sectors
	pop	es
	jc	dcr8
	mov	al,[si].BPB_DRIVE
	mov	[ddbuf_drv],al
	mov	[ddbuf_lba],dx

dcr7:	push	di
	push	es
	lds	si,[ddbuf_ptr]	; DS:SI -> our own buffer
	les	di,es:[di].DDPRW_ADDR
	mov	ax,cx
	rep	movsb		; transfer bytes from our own buffer
	pop	es
	pop	di
	add	es:[di].DDPRW_ADDR.off,ax
	sub	es:[di].DDPRW_LENGTH,ax
	ASSERTZ	<cmp es:[di].DDPRW_LENGTH,cx>

dcr8:	pop	es
	pop	bp
	mov	es:[di].DDP_STATUS,DDSTAT_DONE
	jnc	dcr9
;
; TODO: Map the error and set the sector count to the correct values
;
	mov	es:[di].DDPRW_LENGTH,0
	mov	es:[di].DDP_STATUS,DDSTAT_ERROR + DDERR_SEEK
dcr9:	ret
ENDPROC	ddcmd_read

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcmd_write
;
; Inputs:
;	ES:DI -> DDPRW
;
; Outputs:
;	DDPRW updated appropriately
;
; Modifies:
;	AX, BX, CX, DX, SI, DS
;
DEFPROC	ddcmd_write
	ASSUME	DS:CODE
	ret
ENDPROC	ddcmd_write

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; ddcmd_none (handler for unimplemented functions)
;
; Inputs:
;	DS:DI -> DDP
;
; Outputs:
;
DEFPROC	ddcmd_none
	ASSUME	DS:CODE
	ret
ENDPROC	ddcmd_none

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Call BIOS to read/write sectors
;
; Inputs:
;	BH = FDC cmd
;	BL = # sectors
;	DX = LBA
;	DS:SI -> BPB
;	ES:BP -> buffer
;
; Outputs:
;	DDPRW updated appropriately
;
; Modifies:
;	AX
;
DEFPROC	readwrite_sectors
	ASSUME	DS:NOTHING
	push	bx
	push	cx
	push	dx
	call	get_chs		; convert LBA in DX to CHS in CX,DX
	xchg	ax,bx		; AH = FDC cmd, AL = # sectors
	mov	bx,bp
	int	INT_FDC		; AX and carry are whatever the ROM returns
	pop	dx
	pop	cx
	pop	bx
	ret
ENDPROC	readwrite_sectors

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Get CHS from LBA in AX, using BPB at SI
;
; Inputs:
;	DX = LBA
;	DS:SI -> BPB
;
; Outputs:
;	CH = cylinder #
;	CL = sector ID
;	DH = head #
;	DL = drive #
;
; Modifies:
;	AX, CX, DX
;
; TODO: Keep this in sync with BOOT.ASM (better yet, factor it out somewhere)
;
DEFPROC	get_chs
	ASSUME	DS:NOTHING
	xchg	ax,dx
	sub	dx,dx		; DX:AX is LBA
	div	[si].BPB_CYLSECS; AX = cylinder, DX = remaining sectors
	xchg	al,ah		; AH = cylinder, AL = cylinder bits 8-9
	ror	al,1		; future-proofing: saving cylinder bits 8-9
	ror	al,1
	xchg	cx,ax		; CH = cylinder #
	xchg	ax,dx		; AX = remaining sectors from last divide
	div	byte ptr [si].BPB_TRACKSECS
	mov	dh,al		; DH = head # (quotient of last divide)
	or	cl,ah		; CL = sector # (remainder of last divide)
	inc	cx		; LBA are zero-based, sector IDs are 1-based
	mov	dl,[si].BPB_DRIVE
	ret
ENDPROC	get_chs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Driver initialization
;
; Inputs:
;	ES:BX -> DDPI
;
; Outputs:
;	DDPI's DDPI_UNITS and DDPI_END updated
;
DEFPROC	ddinit,far
	push	ax
	push	cx
	push	ds
	sub	ax,ax
	mov	ds,ax
	ASSUME	DS:BIOS
	mov	ax,[EQUIP_FLAG]
	mov	es:[bx].DDPI_END.off,offset ddinit + 512
	mov	cs:[0].DDH_REQUEST,offset DEV:ddreq
	mov	[ddbuf_ptr].seg,cs
;
; Determine how many floppy disk drives are in the system.
;
	sub	cx,cx
	test	al,EQ_IPL_DRIVE
	jz	ddin9
	and	ax,EQ_NUM_DRIVES
	mov	cl,6
	shr	ax,cl
	inc	ax
	xchg	cx,ax
ddin9:	mov	es:[bx].DDPI_UNITS,cl
	pop	ds
	ASSUME	DS:NOTHING
	pop	cx
	pop	ax
	ret
ENDPROC	ddinit

CODE	ends

DATA	segment para public 'DATA'

ddend	db	16 dup(0)

DATA	ends

	end
