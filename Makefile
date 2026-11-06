NAME = lemipc

CC = cc
CFLAGS = -Wall -Wextra -Werror
CPPFLAGS = -Iinc -Ilibft

LIBFT_DIR = libft
LIBFT = $(LIBFT_DIR)/libft.a

# List project source files explicitly here as they are added.
SRCS =
OBJS = $(SRCS:.c=.o)

.DEFAULT_GOAL := all
.SUFFIXES: .c .o

all: $(NAME)

$(NAME): $(OBJS) $(LIBFT)
	$(CC) $(CFLAGS) $(OBJS) $(LIBFT) -o $@

.c.o:
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(OBJS): inc/lemipc.h libft/libft.h

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
