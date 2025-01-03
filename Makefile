NAME		=	Famine

SRCS		= 	\
				main.s

_OBJS		=	${SRCS:.s=.o}
OBJS		=	$(addprefix build/, $(_OBJS))

NASM		=	nasm
NFLAGS		=	-felf64

LD			=	ld

all		:	$(NAME)

build/%.o	:	srcs/%.s
	@if [ ! -d $(dir $@) ]; then\
		mkdir -p $(dir $@);\
	fi
	$(NASM) ${NFLAGS} $< -o $@

$(NAME)	:	$(OBJS)
	$(LD) $(OBJS) -o $(NAME)

clean	:	
	rm -Rf build/

fclean	:	clean
	rm -f ${NAME}

re		:	fclean
			make ${NAME}

test	:	${NAME}
	rm -rf /tmp/test
	rm -rf /tmp/test2
	mkdir -p /tmp/test
	cp /bin/echo /tmp/test
	./${NAME}

.PHONY	:	all clean fclean re test
