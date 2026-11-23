NAME = lemipc

CC = cc
CFLAGS = -Wall -Wextra -Werror
CPPFLAGS = -Iinc -Ilibft -Ilibft/ft_printf

LIBFT_DIR = libft
LIBFT = $(LIBFT_DIR)/libft.a
PRINTF = $(LIBFT_DIR)/ft_printf/ft_printf.a

CORE_SRCS = src/config.c src/session.c src/resources.c src/roster.c \
            src/player.c src/movement.c src/capture.c src/target.c \
            src/display.c
SRCS = src/main.c $(CORE_SRCS)
CORE_OBJS = $(CORE_SRCS:.c=.o)
OBJS = $(SRCS:.c=.o)

TEST_DIR = tests
TEST_HARNESS = $(TEST_DIR)/harness.c
TEST_BINS = $(TEST_DIR)/test_rules $(TEST_DIR)/test_roster \
            $(TEST_DIR)/test_movement $(TEST_DIR)/test_config $(TEST_DIR)/test_ipc \
            $(TEST_DIR)/test_ipc_lifecycle
INTEGRATION = $(TEST_DIR)/run_integration.sh
IPC_PROBE = $(TEST_DIR)/ipc_probe

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

# Unit suites link every object but src/main.o, so they call the real
# game functions directly on a plain t_board -- no shared memory needed.
$(TEST_DIR)/test_%: $(TEST_DIR)/test_%.c $(TEST_HARNESS) $(TEST_DIR)/harness.h \
		$(CORE_OBJS) $(PRINTF) $(LIBFT)
	$(CC) $(CPPFLAGS) -I$(TEST_DIR) $(CFLAGS) $< $(TEST_HARNESS) \
		$(CORE_OBJS) $(TEST_LDFLAGS) $(PRINTF) $(LIBFT) -o $@

$(TEST_DIR)/test_ipc: TEST_LDFLAGS = -Wl,--wrap=semget,--wrap=msgget,--wrap=shmget,--wrap=shmat

$(IPC_PROBE): $(TEST_DIR)/ipc_probe.c inc/lemipc.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $< -o $@

unit: $(TEST_BINS)
	@status=0; for suite in $(TEST_BINS); do \
		./$$suite || status=1; \
	done; exit $$status

integration: $(NAME) $(IPC_PROBE)
	@$(INTEGRATION)

test: unit integration

clean:
	$(MAKE) -C $(LIBFT_DIR) clean
	rm -f $(OBJS)
	rm -f $(TEST_BINS) $(IPC_PROBE)

fclean: clean
	$(MAKE) -C $(LIBFT_DIR) fclean
	rm -f $(NAME)

re: fclean
	$(MAKE) all

FORCE:

.PHONY: all clean fclean re test unit integration FORCE
