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
	%xdefine dest rbp - %$localsize - text_len
	%assign %$localsize %$localsize + text_len

	push rbp
	mov rbp, rsp
	sub rsp, %$localsizse

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

	mov [i_src], 0				; i_src = 0;
	mov [i_dest], 0				; i_dest = 0;

.begin_compression:	
	; Il me faut mes 2 index
	; On va d'abord recup le max entre - 255 et la limite
	; Revenir en arrière de 0 n'est pas possible parce qu'il nous faudra au moins 3 pour que ce soit rentable
	; On va pouvoir se servir de ça pour encoder le token
	xor rdi, rdi				; _i_haystack_limit = 0;
	mov rax, i_src - 255			; if (i_src > 255) {
	cmp i_src, 255				; 	...
	cmova rdi, rax				; 	_i_haystack_limit = i_src - 255; }
	mov [i_haystack_limit], rdi		; i_haystack_limit = _i_haystack_limit;
	mov [best_len_subbyte], 0		; best_len_subbyte = 0;

.begin_lookup_haystack:				; while (i_haystack_limit < i_src) {
	mov rax, [i_haystack_limit]		; ...
	cmp rax, [i_src]			; ...
	jge .end_lookup_haystack		; ...

	mov [i_haystack], rax			; i_haystack = i_haystack_limit;
	mov [i_len_subbyte], 0			; i_len_subbyte = 0;
	
.begin_lookup_needle:				; while (i_haystack < i_src
	mov rax, [i_haystack]			; ...
	cmp rax, [i_src]			; ...
	jge .end_lookup_needle			; ...

	mov rax, [src_end_ptr]			; 	&& src_end_ptr[-i_haystack] != dest_end_ptr[-i_needle]) {
	sub rax, [i_haystack]			; ...
	mov r8b, [rax]				; ...
	mov rax, [dest_end_ptr]			; ...
	sub rax, [i_needle]			; ...
	mov r9b, [rax]				; ...
	cmp r8b, r9b				; ...
	jne .end_lookup_needle			; ...

	inc [len_subbyte]			; i_len_subbyte++;
	inc [i_haystack]			; i_haystack++;
	inc [i_needle]				; i_needle++;
	jmp .begin_lookup_needle		; }

.end_lookup_needle:

	mov rax, [len_subbyte]			; if (len_subbyte > best_len_subbyte) {
	mov rdi, [i_src]			; ...
	sub rdi, [i_subbyte]			; ...
	cmp rax, [best_len_subbyte]		; ...
	cmova [best_len_subbyte], rax		; 	best_len_subbyte = len_subbyte;
	cmova [best_offset_subbyte], rdi	; 	best_offset_subbyte = i_src - i_subbyte;
						; }
	inc [i_haystack_limit]			; i_haystack_limit++;

.end_lookup_haystack:				; }

	cmp [best_len_subbyte], 3		; if (best_len_subbyte > 3) //length of a token
	jg .write_token				; ...
	jmp .write_byte				; ...

.write_token:					; {
	; TODO Fix size of variables, play with byte/qword, it is ugly
	mov rax, [dest_end_ptr]			; 
	sub rax, [i_dest]			;
	mov byte [rax], TOKEN
	dec rax
	mov rdi, [best_offset_subbyte]
	mov byte [rax], rdi
	dec rax
	mov rdi, [best_len_subbyte]
	mov byte [rax], rdi
	dec rax
	
	
.write_byte:					; else {

	; TODO TU T'ETAIS ARRÊTÉ LÀ
	; TODO Inc i_src and i_dest (but not by one, maybe by more)
.end_compression:

	mov rax, 60
	mov rdi, 0
	syscall

	; Never reached
	%add rsp, %$localsize
	pop rbp
	%pop
	ret

section .data
	text: db "I AM SAM. I AM SAM. SAM I AM."
db "THAT SAM-I-AM! THAT SAM-I-AM! I DO NOT LIKE THAT SAM-I-AM!"
db "DO WOULD YOU LIKE GREEN EGGS AND HAM?"
db "I DO NOT LIKE THEM,SAM-I-AM."
db "I DO NOT LIKE GREEN EGGS AND HAM."
	text_len: equ $ - text
