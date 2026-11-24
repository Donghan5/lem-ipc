# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    Makefile                                           :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: donghank <donghank@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2024/05/31 17:45:15 by donghank          #+#    #+#              #
#    Updated: 2024/06/14 12:37:28 by donghank         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

NAME = ft_printf.a
SRCS = ft_printf.c ft_printf_address.c ft_printf_nbr.c ft_printf_strings.c
OBJS = $(SRCS:.c=.o)
LIBFT_DIR = libft
LIBFT_AR = $(LIBFT_DIR)/libft.a
CC = cc
AR = ar
ARFLAGS = rcs
CFLAGS = -Wall -Wextra -Werror
CPPFLAGS = -I.

all: $(NAME)

%.o: %.c ft_printf.h $(LIBFT_DIR)/libft.h
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(LIBFT_AR): FORCE
	$(MAKE) -C $(LIBFT_DIR)

$(NAME): $(OBJS) $(LIBFT_AR)
	cp $(LIBFT_AR) $@
	$(AR) $(ARFLAGS) $@ $(OBJS)

clean:
	$(MAKE) -C $(LIBFT_DIR) clean
	rm -f $(OBJS) error.txt

fclean: clean
	$(MAKE) -C $(LIBFT_DIR) fclean
	rm -f $(NAME)

re: fclean
	$(MAKE) all

FORCE:

.PHONY: all clean fclean re FORCE
