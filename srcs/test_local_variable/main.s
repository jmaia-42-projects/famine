%define SYS_EXIT 60

global _start

section .text

_start:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local fd:qword
	%local dirent:qword
	%local pouet:qword

	push rbp
	mov rbp, rsp
	sub rsp, %$localsize + 8

	xor rax, rax
	mov [fd], rax		; Save fd to stack

	mov rax, [fd]
	mov rax, [dirent]
	mov rax, [pouet]
	mov rax, [rbp - %$localsize - 8]

	%pop

	mov rax, SYS_EXIT
	mov rdi, 0
	syscall

section .data
	folder_name: db "/tmp/pouet", 0
	err_msg: db "Error occured !", 10
	len_err_msg: equ $ - err_msg
