%define SYS_WRITE 1
%define SYS_OPEN 2
%define SYS_CLOSE 3
%define SYS_EXIT 60
%define SYS_GETDENTS64 217

%define O_RDONLY 0o

%define BUFFER_SIZE 1024

global _start

struc linux_dirent64
	.d_ino		resq	1
	.d_off		resq	1
	.d_reclen	resw	1
	.d_type		resb	1
	.d_name		resq	1
endstruc

section .text

_start:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local fd:qword
	%local cur_offset:qword		; Need to be optimized in a register I think
	%local read_bytes:qword

	push rbp
	mov rbp, rsp
	sub rsp, %$localsize + BUFFER_SIZE

	; Open folder_name
	mov rax, SYS_OPEN
	mov rdi, folder_name
	mov rsi, O_RDONLY
	xor rdx, rdx
	syscall
	cmp rax, 0
	jl err
	mov [fd], rax		; Save fd to stack

	mov rax, SYS_GETDENTS64
	mov rdi, [fd]
	lea rsi, [rbp - %$localsize - BUFFER_SIZE]
	mov rdx, BUFFER_SIZE
	syscall

	mov [read_bytes], rax

	xor rax, rax
	mov [cur_offset], rax
; TEMP TO REMOVE

begin_print_loop:
	; ft_strlen
	lea rdi, [rbp - %$localsize - BUFFER_SIZE + linux_dirent64.d_name]
	add rdi, [cur_offset]
	xor rdx, rdx
	.begin:
		mov sil, [rdi]	; Copy current character to sil (rsi)
		cmp sil, 0		; If end of string is reached
		je .end			; Go to the end
		inc rdx			; Else, increment return value
		inc rdi			; and go to next character
		jmp .begin		; Treat next character
	.end:

	mov rax, 1
	mov rdi, 1
	lea rsi, [rbp - %$localsize - BUFFER_SIZE + linux_dirent64.d_name]
	add rsi, [cur_offset] ; Need to opti ce doublon
	syscall

	lea rax, [rbp - %$localsize - BUFFER_SIZE + linux_dirent64.d_reclen]
	add rax, [cur_offset]
	xor rdi, rdi
	mov di, [rax]
	add [cur_offset], rdi

	mov rax, [cur_offset]
	cmp rax, [read_bytes]
	je end_print_loop

	jmp begin_print_loop

end_print_loop:
	
; TODO Continue here
; TODO Check return error

	; Close folder
	mov rax, SYS_CLOSE
	mov rdi, [fd]
	syscall
	cmp rax, -1
	je err

	jmp end

err:
	mov rax, SYS_WRITE
	mov rdi, 1
	mov rsi, err_msg
	mov rdx, len_err_msg
	syscall
	jmp end

end:
	%pop
	mov rax, SYS_EXIT
	mov rdi, 0
	syscall

section .data
	folder_name: db "/tmp/pouet", 0
	err_msg: db "Error occured !", 10
	len_err_msg: equ $ - err_msg
