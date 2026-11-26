NAME = lemipc

CC = cc
CFLAGS = -Wall -Wextra -Werror
CPPFLAGS = -Iinc -Ilibft -Ilibft/ft_printf

LIBFT_DIR = libft
LIBFT = $(LIBFT_DIR)/libft.a
PRINTF = $(LIBFT_DIR)/ft_printf/ft_printf.a

CORE_SRCS = src/config.c src/session.c src/resources.c src/roster.c \
            src/player.c src/movement.c src/capture.c src/target.c \
            src/display.c src/liveness.c src/announce.c
SRCS = src/main.c $(CORE_SRCS)
OBJ_DIR = obj/src
CORE_OBJS = $(CORE_SRCS:src/%.c=$(OBJ_DIR)/%.o)
OBJS = $(SRCS:src/%.c=$(OBJ_DIR)/%.o)

TEST_DIR = tests
TEST_HARNESS = $(TEST_DIR)/harness.c
TEST_BINS = $(TEST_DIR)/test_rules $(TEST_DIR)/test_roster \
            $(TEST_DIR)/test_movement $(TEST_DIR)/test_config $(TEST_DIR)/test_ipc \
            $(TEST_DIR)/test_ipc_lifecycle
INTEGRATION = $(TEST_DIR)/run_integration.sh
IPC_PROBE = $(TEST_DIR)/ipc_probe
export SCENARIO VERBOSE

# make play TEAMS="1 1 1 2 2 2": one player per entry, all in this directory.
TEAMS ?= 1 1 2 2
# make demo NTEAMS=5 KILL=1: number of teams (2-7, two players each), and
# KILL=1 to SIGKILL one team 2 player during the match.
NTEAMS ?= 2
KILL ?= 0

.DEFAULT_GOAL := all
MAKEFLAGS += --no-print-directory

##@ Build

all: $(NAME) ## Build lemipc (libft included)

clean: ## Remove object files and test binaries
	$(MAKE) -C $(LIBFT_DIR) clean
	rm -f $(OBJS) $(SRCS:.c=.o)
	@rmdir $(OBJ_DIR) obj 2>/dev/null || :
	rm -f $(TEST_BINS) $(IPC_PROBE)

fclean: clean ## clean + remove lemipc and libft archives
	$(MAKE) -C $(LIBFT_DIR) fclean
	rm -f $(NAME)

re: fclean ## Rebuild from scratch
	$(MAKE) all

$(NAME): $(OBJS) $(PRINTF) $(LIBFT)
	$(CC) $(CFLAGS) $(OBJS) $(PRINTF) $(LIBFT) -o $@

$(OBJ_DIR):
	mkdir -p $@

$(OBJ_DIR)/%.o: src/%.c | $(OBJ_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(OBJS): inc/lemipc.h libft/libft.h libft/ft_printf/ft_printf.h

# libft decides for itself whether to rebuild; -s keeps its no-op runs quiet,
# so a second make only says there is nothing to do.
$(PRINTF): FORCE | $(LIBFT)
	@$(MAKE) -s -C $(LIBFT_DIR)/ft_printf

$(LIBFT): FORCE
	@$(MAKE) -s -C $(LIBFT_DIR) libft.a

# Unit suites link the core objects, so they call the real
# game functions directly on a plain t_board -- no shared memory needed.
$(TEST_DIR)/test_%: $(TEST_DIR)/test_%.c $(TEST_HARNESS) $(TEST_DIR)/harness.h \
		$(CORE_OBJS) $(PRINTF) $(LIBFT)
	$(CC) $(CPPFLAGS) -I$(TEST_DIR) $(CFLAGS) $< $(TEST_HARNESS) \
		$(CORE_OBJS) $(TEST_LDFLAGS) $(PRINTF) $(LIBFT) -o $@

$(TEST_DIR)/test_ipc: TEST_LDFLAGS = -Wl,--wrap=semget,--wrap=msgget,--wrap=shmget,--wrap=shmat

$(IPC_PROBE): $(TEST_DIR)/ipc_probe.c inc/lemipc.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $< -o $@

##@ Test

test: unit integration ## Run unit + integration (about 2 minutes)

unit: $(TEST_BINS) ## Run the unit test suites
	@status=0; for suite in $(TEST_BINS); do \
		./$$suite || status=1; \
	done; exit $$status

ipc-test: $(TEST_DIR)/test_ipc ## Run the IPC and team message tests
	@./$(TEST_DIR)/test_ipc

integration: $(NAME) $(IPC_PROBE) ## Run real-process tests and check session IPC
	@$(INTEGRATION)

stress: $(NAME) $(IPC_PROBE) $(TEST_DIR)/test_ipc_lifecycle ## Run the 400-player stress test and IPC lock recovery checks
	@$(INTEGRATION) --stress

##@ Evaluation

eval-list: ## List the evaluation scenarios
	@$(INTEGRATION) --eval-list

eval: $(NAME) $(IPC_PROBE) ## Run evaluation scenarios (SCENARIO=<name>, VERBOSE=1)
	@$(INTEGRATION) --eval "$$SCENARIO"

##@ Demo

demo: $(NAME) $(IPC_PROBE) ## Two-terminal demo (NTEAMS=2-7, KILL=1 adds a SIGKILL)
	@./scripts/demo.sh $(NTEAMS) $(if $(filter 1,$(KILL)),--kill-player)

play: $(NAME) ## One player per TEAMS entry, board on screen; Ctrl+C leaves
	@./scripts/play.sh $(TEAMS)

ipcs: ## List the IPC objects this user owns (read only, removes nothing)
	@./scripts/ipcs.sh

help: ## Show these commands
	@echo "Usage: make [target] [VARIABLE=value]"
	@awk -F ':.*## ' ' \
		/^##@ / { printf "\n%s\n", substr($$0, 5) } \
		/^[a-z0-9-]+:.*## / { printf "  %-12s %s\n", $$1, $$2 }' \
		$(firstword $(MAKEFILE_LIST))
	@echo
	@echo "Examples:"
	@echo "  make demo NTEAMS=5 KILL=1"
	@echo "  make play TEAMS=\"8 8 42 42\""
	@echo "  make eval SCENARIO=large-teams"
	@echo "  LEMIPC_PLAYERS=4 ./lemipc <team>    board: ./lemipc 0"

FORCE:

.PHONY: all clean fclean re test unit ipc-test integration stress eval eval-list demo play ipcs help FORCE
