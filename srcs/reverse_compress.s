; En vrai, pour les programmes infectés, il faut juste être capable de copier le payload compressé + le décompresseur + la taille + adapter le jump
; Dans le programme de base, on va mettre une partie compression qui sera pas copiée, on va set une variable qui défini l'endroit où est la zone compressée et ensuite on viendra faire le reste

; -- Structure du programme de base --
; Allocation d'espace sur la stack + compression du payload sur cet espace
; Execution du payload + va falloir donner l'adresse vers le payload compressé à copier

; -- Structure d'un programme infecté --
; Allocation d'espace sur la stack + copie du payload compressé
; <Décompresseur>
; Execution du payload + va falloir donner l'adresse vers le payload compressé à copier


global _start

%define TOKEN 127

section .text
_start:
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
	%xdefine dest rbp - %$localsize - 1000 ;TODO, in real code it will never be in define like this
	%assign %$localsize %$localsize + 1000

	; DECOMPRESSION
	%xdefine decoded rbp - %$localsize - 1000
	%assign %$localsize %$localsize + 1000

	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	lea rax, [text + text_len - 1]
	mov [src_end_ptr], rax
	lea rax, [dest + text_len - 1]
	mov [dest_end_ptr], rax

	; Print before
	mov rax, 1
	mov rdi, 1
	mov rsi, text
	mov rdx, text_len
	syscall

	; Faut garder en tête qu'on part de la fin
	; On commence donc depuis text+text_len-1
	; On commence donc depuis rsp+text_len-1

	; Faut d'abord faire une boucle sur la sourc
	; D'abord : le premier caractère est forcément copié, ça y'a pas de doute
	; Ensuite, il faut voir si ça peut être intéressant d'utiliser un token ou pas
	; On va donc avoir plein de boucles :
	; On revient le plus loin possible mais au maximum à 255 caractères
	; On compare les caractères
	; Tant que c'est pareil on fait + 1 sur les 2 (et on fait gaffe à ne pas dépasser l'endroit où on est)
	; Quand c'est pas pareil, on stocke l'index et la taille si jamais c'est les meilleurs qu'on a trouvé
	; Pour la galère avec la jump value, on peut la stocker quelque part et on viendra la récup de plus loin

	mov qword [i_src], 0			; i_src = 0;
	mov qword [i_dest], 0			; i_dest = 0;

.begin_compression:				; while (i_src < text_len) {
	cmp qword [i_src], text_len		; ...
	jge .end_compression			; ...
	; Il me faut mes 2 index
	; On va d'abord recup le max entre - 255 et la limite
	; Revenir en arrière de 0 n'est pas possible parce qu'il nous faudra au moins 3 pour que ce soit rentable
	; On va pouvoir se servir de ça pour encoder le token
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
	mov byte [rax], TOKEN			; 	*_cur_dest_ptr = TOKEN;
	dec rax					; 	_cur_dest_ptr--;
	mov rdi, [best_offset_subbyte]		; 	*_cur_dest_ptr = best_offset_subbyte;
	mov byte [rax], dil			; 	...
	dec rax					; 	_cur_dest_ptr--;
	mov rdi, [best_len_subbyte]		; 	*_cur_dest_ptr = best_len_subbyte;
	mov byte [rax], dil			; 	...
	add qword [i_dest], 3			;	i_dest += 3;
	add [i_src], rdi			;	i_src += best_len_subbyte;
	jmp .end_write_byte_or_token		; }
	
.write_byte:					; else if (*src_end_ptr != TOKEN) {
	mov rsi, [src_end_ptr]			; 	...
	sub rsi, [i_src]			; 	...
	cmp byte [rsi], TOKEN			; 	...
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
	mov byte [rax], TOKEN			;	*_cur_dest_ptr = TOKEN;
	dec rax					; 	_cur_dest_ptr--;
	mov byte [rax], 0			; 	*_cur_dest_ptr = 0;
.end_write_byte_or_token:			; }
	jmp .begin_compression			; }

.end_compression:

	mov rax, 1
	mov rdi, 1
	mov rsi, [dest_end_ptr]
	sub rsi, [i_dest]
	inc rsi
	mov rdx, [i_dest]
	syscall

	; On boucle sur chaque caractère
	; Si c'est un caractère classique, on ecrit et ++
	; Si c'est un 0x7F, on regarde les 2 caractères suivants, on écrit, et +
	lea rax, [dest + text_len - 1]
	mov [src_end_ptr], rax
	lea rax, [decoded + text_len - 1]
	mov [dest_end_ptr], rax

decompression_routine:
	lea rax, [dest]
	cmp [src_end_ptr], rax
	je end_decompression_routine

	mov rsi, [src_end_ptr]
	mov r8b, [rsi]
	cmp r8b, TOKEN
	je .decompress_token	; TODO
	mov rdi, [dest_end_ptr]
	mov [rdi], r8b
	dec qword [src_end_ptr]
	dec qword [dest_end_ptr]
	jmp decompression_routine
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

	jmp decompression_routine

.decompress_byte_token:
	mov byte [dest_end_ptr], TOKEN
	dec qword [dest_end_ptr]
	sub qword [src_end_ptr], 2
	jmp decompression_routine

end_decompression_routine:

	mov rax, 1
	mov rdi, 1
	lea rsi, [decoded]
	mov rdx, text_len
	syscall

	mov rax, 60
	mov rdi, 0
	syscall

	; Never reached
	add rsp, %$localsize
	pop rbp
	%pop
	ret

section .data
;	text: db "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
	text: db "I AM SAM. I AM SAM. SAM I AM."
db "THAT SAM-I-AM! THAT SAM-I-AM! I DO NOT LIKE THAT SAM-I-AM!"
db "DO WOULD YOU LIKE GREEN EGGS AND HAM?"
db "I DO NOT LIKE THEM,SAM-I-AM."
db "I DO NOT LIKE GREEN EGGS AND HAM.", 0x0A
	text_len: equ $ - text
