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

#> make [all]
#>
#>   Build ./lemipc with libft and ft_printf. A second run rebuilds nothing.
#>   lemipc is the only executable: players and the display are both
#>   ./lemipc, chosen by the argument.
#>
#>   See also: re, help T=play
all: $(NAME) ## Build lemipc (libft included)

#> make clean
#>
#>   Remove object files, unit test binaries and tests/ipc_probe, and run
#>   libft's clean. It never touches IPC objects: check those with make ipcs.
clean: ## Remove object files and test binaries
	$(MAKE) -C $(LIBFT_DIR) clean
	rm -f $(OBJS) $(SRCS:.c=.o)
	@rmdir $(OBJ_DIR) obj 2>/dev/null || :
	rm -f $(TEST_BINS) $(IPC_PROBE)

#> make fclean
#>
#>   clean, plus ./lemipc and the libft archives. IPC objects are left alone.
fclean: clean ## clean + remove lemipc and libft archives
	$(MAKE) -C $(LIBFT_DIR) fclean
	rm -f $(NAME)

#> make re
#>
#>   fclean, then build again from scratch.
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

#> make test
#>
#>   unit + integration, about 2-3 minutes. It does not run stress or eval.
#>   Before handing in, run both make test and make eval.
#>
#>   See also: help T=unit, help T=integration, help T=eval
test: unit integration ## Run unit + integration (about 2-3 minutes)

#> make unit
#>
#>   Six unit suites linked against the game objects (no main.o):
#>     rules          capture rule, edges, targeting, team ids up to INT_MAX
#>     roster         join, leave, winner, reaping dead and zombie players
#>     movement       legal steps and 400000 random moves on a plain board
#>     config         LEMIPC_PLAYERS and team argument parsing
#>     ipc            private IPC objects, injected creation failures, msgq
#>     ipc_lifecycle  semaphore contention and shared session lifecycle
#>   Exit status is non-zero if any suite fails.
unit: $(TEST_BINS) ## Run the unit test suites
	@status=0; for suite in $(TEST_BINS); do \
		./$$suite || status=1; \
	done; exit $$status

#> make ipc-test
#>
#>   Only the ipc unit suite: creation rollback when semget, msgget, shmget or
#>   shmat fails (GNU ld --wrap), and team-specific target messages on the
#>   message queue, including empty and full queues. Also part of make unit.
ipc-test: $(TEST_DIR)/test_ipc ## Run the IPC and team message tests
	@./$(TEST_DIR)/test_ipc

#> make integration
#>
#>   Real ./lemipc processes over real System V IPC, about 2 minutes. Each
#>   test runs in its own fresh directory (the key is ftok(".")), waits for
#>   its own children, checks their exit codes, and checks that the match's
#>   SHM, SEM and MSGQ are gone afterwards. Covers invalid arguments, signals,
#>   SIGKILL recovery, the display, team ids 8 and 42, a one-on-one stalemate
#>   and interleaved output. Valgrind runs on a few players when installed.
integration: $(NAME) $(IPC_PROBE) ## Run real-process tests and check session IPC
	@$(INTEGRATION)

#> make stress [VERBOSE=1]
#>
#>   400 players in 7 teams (58 in team 1, 57 in the others), in a separate
#>   session. Checks the roster and a move or elimination (30s each), then
#>   SIGINT: every child reaped within 15s and SHM, SEM and MSGQ gone.
#>   Valgrind checks the first player of each team. Also checks that a
#>   blocked waiter gets the semaphore after the lock owner is SIGKILLed.
#>
#>   On a slow machine the join stage can report 399/400: a timing limit of
#>   the test. Shutdown, Valgrind and IPC cleanup still pass in that run.
#>
#>   VERBOSE=1  Valgrind logs and lifecycle test details
stress: $(NAME) $(IPC_PROBE) $(TEST_DIR)/test_ipc_lifecycle ## Run the 400-player stress test and IPC lock recovery checks
	@$(INTEGRATION) --stress

##@ Evaluation

#> make eval-list
#>
#>   Number, name and expected result of every evaluation scenario.
eval-list: ## List the evaluation scenarios
	@$(INTEGRATION) --eval-list

#> make eval [SCENARIO=<name>] [VERBOSE=1]
#>
#>   Evaluation scenarios with Valgrind, reported as Game / Memory / IPC.
#>   Each one reruns a test from make integration. About 1 minute for all.
#>
#>   SCENARIO   one of:
#>                normal-win            team 1 wins, players remove all IPC
#>                sigint-withdrawal     Ctrl-C: both players leave cleanly
#>                sigkill-survivor      one player SIGKILLed, survivor wins
#>                all-killed-recovery   everyone SIGKILLed, rerun reclaims IPC
#>                display-last          the display exits last and cleans up
#>                large-teams           teams 8 and 42 (no team limit)
#>                one-on-one-stalemate  1v1 never ends; Ctrl-C cleans up
#>   VERBOSE=1  full logs for each scenario
#>
#>   Examples:
#>     make eval
#>     make eval SCENARIO=sigkill-survivor VERBOSE=1
eval: $(NAME) $(IPC_PROBE) ## Run evaluation scenarios (SCENARIO=<name>, VERBOSE=1)
	@$(INTEGRATION) --eval "$$SCENARIO"

##@ Demo

#> make demo [NTEAMS=2-7] [KILL=1]
#>
#>   Two-terminal demo. Run it in the right terminal, and ./lemipc 0 in the
#>   left one from the same directory (the demo prints the exact command).
#>   Press Enter to launch the players; the right side reports joins,
#>   eliminations, message queue traffic and the winner, then checks that
#>   SHM, SEM and MSGQ are gone. Close any session in this directory first.
#>
#>   NTEAMS   number of teams, two players each (default 2)
#>   KILL=1   send SIGKILL to one team 2 player during the match and show
#>            that the others finish and still remove the IPC objects
#>
#>   Examples:
#>     make demo
#>     make demo NTEAMS=5 KILL=1
#>
#>   See also: play, ipcs
demo: $(NAME) $(IPC_PROBE) ## Two-terminal demo (NTEAMS=2-7, KILL=1 adds a SIGKILL)
	@./scripts/demo.sh $(NTEAMS) $(if $(filter 1,$(KILL)),--kill-player)

#> make play [TEAMS="1 1 2 2"]
#>
#>   One terminal: starts one background ./lemipc per TEAMS entry, sets
#>   LEMIPC_PLAYERS to their number, then shows the board. Ctrl+C asks every
#>   player to leave; the last one removes the IPC objects. Player output
#>   goes to logs/player-1.log, logs/player-2.log, ...
#>
#>   TEAMS    team ids, one per player (default "1 1 2 2"). ./lemipc checks
#>            each id; 0 is refused because it opens the display.
#>
#>   If ./lemipc rejects a team, or not every player joins within 5s plus
#>   0.1s per player, the started players are asked to leave and make play
#>   exits with status 1.
#>
#>   Examples:
#>     make play TEAMS="1 1 1 2 2 2"
#>     make play TEAMS="8 8 42 42"      wider tiles for team 42
#>     make play TEAMS="1 2"            one-on-one: never ends, use Ctrl+C
#>
#>   See also: demo, ipcs
play: $(NAME) ## One player per TEAMS entry, board on screen; Ctrl+C leaves
	@./scripts/play.sh $(TEAMS)

#> make ipcs
#>
#>   List the SHM, SEM and MSGQ objects this user owns, with what each one is
#>   for in lemipc. Read only: it removes nothing, so a leak stays visible.
ipcs: ## List the IPC objects this user owns (read only, removes nothing)
	@./scripts/ipcs.sh

#> make help [T=<target>]
#>
#>   Without T: every target, grouped, with a one-line summary.
#>   With T:    details for that target, like a command's --help.
#>
#>   Example:
#>     make help T=demo
help: ## Show these commands; T=<target> for details
	@./scripts/help.sh "$(firstword $(MAKEFILE_LIST))" "$(T)"

FORCE:

.PHONY: all clean fclean re test unit ipc-test integration stress eval eval-list demo play ipcs help FORCE
