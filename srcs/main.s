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
	; Il va falloir utiliser getdents. Cf. le man
	; IL faut ausi open, evidemment
	; Faut sûrement alouer toute las tructure et donner le count. À tester voir si on peut faire une boucle ou bien si faut galérer à get avec le bon count
	; Pour tester on va d'abord essayer de lister /tmp/pouet
	%push context
	%stacksize flat64
	%assign %$localsize 0

;	sub rsp, 8+linux_dirent64_size			; 2 variable (fd, dirent)
	%local fd:qword

	push rbp
	mov rbp, rsp
	sub rsp, %$localsize + BUFFER_SIZE

	; Open folder_name
	mov rax, SYS_OPEN
	mov rdi, folder_name
	mov rsi, O_RDONLY
	xor rdx, rdx
	syscall
	cmp rax, -1
	je err
	mov [fd], rax		; Save fd to stack

	; Getdents Did I destroy my stack here ????
;	mov rax, SYS_GETDENTS64
;	lea rdi, [rbp - %$localsize - 8]
;	mov rdx, BUFFER_SIZE
;	syscall

; TEMP TO REMOVE
	mov rax, 1
	mov rdi, 1
;	lea rsi, [rbp - %$localsize - 8 - linux_dirent64.d_name]
	lea rsi, [rbp]
;	mov rdx, [rbp - %$localsize - 8 - linux_dirent64.d_reclen]
	mov rdx, 1
;	sub rdx, linux_dirent64_size
	syscall
; TODO Continue here
; TODO Check return error
;TEMP REMOVE FOLLOWING, JUST TESTING ADDRESS BECAUSE OF EFAULT ABOVE
	mov rax, 'a'
	mov [rbp - %$localsize - 8 - linux_dirent64.d_name], rax
; TEMP END REMOVE

	; Close folder
	mov rax, SYS_CLOSE
	mov rdi, [rbp - 8]
	syscall
	cmp rax, -1
	je err

	jmp end

err:
	mov rax, SYS_WRITE
	mov rdi, err_msg
	mov rsi, len_err_msg
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
