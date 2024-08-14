global _start

section .text

_start:
	; Il va falloir utiliser getdents. Cf. le man
	; IL faut ausi open, evidemment
	; Faut sûrement alouer toute las tructure et donner le count. À tester voir si on peut faire une boucle ou bien si faut galérer à get avec le bon count
