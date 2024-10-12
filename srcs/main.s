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

	%local fd:qword					; long fd;
	%local cur_offset:qword				; long cur_offset;
	%local read_bytes:qword				; long read_bytes;
	%local cur_dirent:qword				; void *cur_dirent;
	%xdefine buf rbp - %$localsize - BUFFER_SIZE	; uint8_t buf[BUFFER_SIZE];
	%assign %$localsize %$localsize + BUFFER_SIZE	; ...

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	; Open folder_name
	mov rax, SYS_OPEN				; _ret = open(
	mov rdi, folder_name				; folder_name,
	mov rsi, O_RDONLY				; O_RDONLY,
	xor rdx, rdx					; 0
	syscall						; );
	cmp rax, 0					; if (_ret < 0)
	jl .err						;	 goto .err
	mov [fd], rax					; fd = _ret;

.begin_getdents_loop:					; while (true) {
	mov rax, SYS_GETDENTS64				; _ret = SYS_GETDENTS64(
	mov rdi, [fd]					; 	fd,
	lea rsi, [buf]					; 	buf,
	mov rdx, BUFFER_SIZE				; 	BUFFER_SIZE
	syscall						; );

	cmp rax, 0					; if (_ret <= 0)
	jle .end_getdents_loop				;	 break;
	mov [read_bytes], rax				; read_bytes = _ret;

	xor rax, rax					; cur_offset = 0;
	mov [cur_offset], rax				; ...

; TEMP TO REMOVE AND REPLACE WITH THE REAL CODE
.begin_treate_loop:					; do {
	lea rax, [buf]					; cur_dirent = buf + cur_offset;
	add rax, [cur_offset]				; ...
	mov [cur_dirent], rax				; ...
	; ft_strlen
	mov rdi, [cur_dirent]				; char *_str = cur_dirent->d_name;
	add rdi, linux_dirent64.d_name			; ...
	xor rdx, rdx					; _len = 0;
	.begin_strlen_loop:				; while (true) {
		mov sil, [rdi]				; _c = *_str;
		cmp sil, 0				; if (_c == 0)
		je .end_strlen_loop			; 	break;
		inc rdx					; _len++
		inc rdi					; _str++;
		jmp .begin_strlen_loop			; }
	.end_strlen_loop:				; ...

	mov rax, 1					; write(
	mov rdi, 1					; 	1,
	mov rsi, [cur_dirent]				;	cur_dirent->d_name,
	add rsi, linux_dirent64.d_name			;	...
	syscall						;	_len);

	mov rax, 1					; write(
	mov rdi, 1					; 	1, 
	push 0x0A					;	'\n',
	mov rsi, rsp					;	...
	mov rdx, 1					;	1
	syscall						;);

	mov rax, [cur_dirent]				; _reclen_ptr = cur_dirent->d_reclen;
	add rax, linux_dirent64.d_reclen		; ...
	xor rdi, rdi					; _reclen = *_reclen_ptr;
	mov di, [rax]					; ...
	add [cur_offset], rdi				; cur_offset += _reclen;

	mov rax, [cur_offset]				; } while (cur_offset == read_bytes);
	cmp rax, [read_bytes]				; ...
	je .end_treate_loop				; ...
	jmp .begin_treate_loop				; ...
.end_treate_loop:					; ...

	jmp .begin_getdents_loop
.end_getdents_loop:					; }
	
	; Close folder
	mov rax, SYS_CLOSE				; _ret = close(
	mov rdi, [fd]					;	fd
	syscall						; );
	cmp rax, -1					; if (_ret == -1)
	je .err						; 	goto .err
	jmp .end					; else goto end

.err:
	mov rax, SYS_WRITE				; write(
	mov rdi, 1					; 	1,
	mov rsi, err_msg				; 	err_msg,
	mov rdx, len_err_msg				; 	len_err_msg,
	syscall						; );
	jmp .end					; goto .end

.end:
	%pop
	mov rax, SYS_EXIT				; exit(
	mov rdi, 0					; 0
	syscall						; );

section .data
	folder_name: db "/usr/bin/", 0
	err_msg: db "Error occured !", 10
	len_err_msg: equ $ - err_msg
