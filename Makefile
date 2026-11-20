NAME = lemipc

CC = cc
CFLAGS = -Wall -Wextra -Werror
CPPFLAGS = -Iinc -Ilibft -Ilibft/ft_printf

LIBFT_DIR = libft
LIBFT = $(LIBFT_DIR)/libft.a
PRINTF = $(LIBFT_DIR)/ft_printf/ft_printf.a

SRCS = src/main.c src/config.c src/session.c src/resources.c src/roster.c \
       src/player.c src/movement.c src/capture.c src/target.c src/display.c
OBJS = $(SRCS:.c=.o)

.DEFAULT_GOAL := all
.SUFFIXES: .c .o

all: $(NAME)

$(NAME): $(OBJS) $(PRINTF) $(LIBFT)
	$(CC) $(CFLAGS) $(OBJS) $(PRINTF) $(LIBFT) -o $@

.c.o:
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(OBJS): inc/lemipc.h libft/libft.h libft/ft_printf/ft_printf.h

$(PRINTF): FORCE
	$(MAKE) -C $(LIBFT_DIR)/ft_printf

$(LIBFT): FORCE
	$(MAKE) -C $(LIBFT_DIR) libft.a

clean:
	$(MAKE) -C $(LIBFT_DIR) clean
	rm -f $(OBJS)

fclean: clean
	$(MAKE) -C $(LIBFT_DIR) fclean
	rm -f $(NAME)

re: fclean
	$(MAKE) all

FORCE:

.PHONY: all clean fclean re FORCE
