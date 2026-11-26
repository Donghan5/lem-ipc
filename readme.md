# lem-ipc

A 42 project in which each player runs in its own process. Players share a board through System V shared memory and coordinate through a semaphore and a message queue.

## Run a match

Build with `make`. Run all processes for a match from the same working directory. The first player creates the session and reads `LEMIPC_PLAYERS`, which defaults to four and accepts 2–400. The match starts when the expected roster has joined.

```sh
LEMIPC_PLAYERS=3 ./lemipc 1 &
./lemipc 1 &
./lemipc 2 &
./lemipc 0
wait
```

Start the first command and wait for its join message before starting the others when using a custom roster size. With the default roster size, launch four players. Any positive number selects a team (there is no fixed limit on teams); teams 1-9 draw one character per tile and larger ids widen every tile. Argument `0` opens a terminal view of an existing session. Use Ctrl-C to close the display or withdraw a player running in the foreground.

Players check for elimination before each turn. They move one tile up, down, left, or right when a legal move is available, with one second between turns. A player is eliminated when two or more adjacent players belong to the same opposing team. Diagonal neighbors count for elimination. Teammates exchange target coordinates, and the last team remaining wins.

## Two-terminal demo

1. In the right terminal, run `make demo` from the repository for two teams.
   Use `make demo3`, `make demo4`, `make demo5`, `make demo6`, or `make demo7`
   for three to seven teams. Each team has two players.
2. In the left terminal, run `./lemipc 0` from the same repository directory,
   or paste the full command printed by the demo.
3. When the board shows one player waiting, press Enter in the right terminal
   to launch the remaining players. Watch the board on the left and the
   joins, eliminations, and winner on the right. Press Ctrl-C in the left
   terminal to close the board when you finish.

The right terminal also prints the session's message queue ID and reports
when the kernel records a successful send and receive by demo players.
For a separate check of team-specific target messages, run
`make ipc-test`.

The demo uses the repository directory for its game session. Close any existing
session in that directory before starting the demo.

A player is eliminated when at least two adjacent players belong to the same opposing team, and diagonals count.

To demonstrate recovery after a player is killed, run `make demo-kill` in the
right terminal and open the same board on the left. Press Enter to start the
match, then press Enter again at the SIGKILL prompt to kill the indicated
Team 2 player. Watch the remaining players on the left. The right terminal
reports the winner and checks that the session's three IPC IDs are gone.

## Tests

```sh
make test          # unit and integration suites
make unit          # game rules and focused System V IPC tests
make integration   # real processes and real System V IPC
make stress        # 400 real players across seven teams and lock recovery
make eval-list      # scenario names and expected behavior
make eval SCENARIO=sigkill-survivor
make eval           # run all evaluation scenarios
make eval SCENARIO=normal-win VERBOSE=1  # include full logs
```

`make unit` links the core objects from `obj/src/` without `main.o`, so the suites call
`is_surrounded`, `join_player`, `leave_player`, `move_player` and
`choose_target` directly on a plain `t_board`. The movement suite checks
forced moves and runs 400000 random move attempts before checking board
consistency. The IPC suite uses private IPC objects and GNU linker wrapping
to inject failures during session creation. It also checks empty and full
message queues and team-specific target exchange.

`make integration` starts real matches. Every test runs in its own fresh
directory, because the session key comes from `ftok(".")` and a new directory
therefore means a new session. The harness waits for its own child processes
and checks their exit codes. It records the IPC IDs from each match's board
and removes any of those objects that survive the match.

The integration suite checks IPC cleanup after `SIGINT`, after a player is
killed during a match, after the display exits last, and when a new run
replaces a session whose last process was killed. When Valgrind is installed,
it checks all players in a normal match and the survivor in the in-progress
`SIGKILL` test. Evaluation reports process exits, Valgrind checks, and the
outcome for each kernel IPC object. The recovery scenario kills players
after the session is initialized and play has started.

`make stress` starts 400 player processes in a separate session, with 58 in
team 1 and 57 in each other team. It checks the roster and looks for a move
or elimination, with up to 30 seconds for each stage. It then sends SIGINT
and checks that all children are reaped within 15 seconds and the session's
SHM, SEM, and MSGQ are gone. The IPC lifecycle suite separately checks
semaphore recovery by checking that a blocked waiter acquires the lock after
the owner is killed. Valgrind checks the first player from each team (7 of
400) for memory errors and definite, indirect, and possible leaks. The
memory check reports `SKIP` if Valgrind is unavailable. Use `VERBOSE=1`
for Valgrind logs and lifecycle test details.

One integration test is marked `XFAIL` because it records a known defect:

| Test | Defect |
| --- | --- |
| `player_lines_never_garbled` | `ft_printf` issues one `write(2)` per byte, so players sharing a terminal interleave mid-word |

The defect only reproduces when the players share one file descriptor and
start together. `TICK_MS` is one second, so players launched in lockstep print
in the same instant on every tick and collide, while starting them half a
second apart keeps their bursts from overlapping and hides the defect:

| Launch | Malformed lines |
| --- | --- |
| staggered by 0.5s | 0 of 45 |
| started together | 87 of 123 |

Starting every player at once is the documented way to run a match, so the
test launches them that way.

When the defect is fixed the suite prints `XPASS`; drop that test's
known-fail flag in `tests/run_integration.sh` at that point.

## Source layout

| Module | Responsibility |
| --- | --- |
| `main.c`, `config.c` | Command-line dispatch, roster configuration, and signal handling |
| `session.c`, `resources.c` | Session discovery, synchronized initialization, board locking, and IPC removal |
| `player.c`, `roster.c` | Joining, waiting for the roster, taking turns, and leaving |
| `movement.c`, `capture.c`, `target.c` | Legal steps, elimination, and team targeting |
| `display.c` | Copy the board under lock and render the snapshot after unlocking |
| `tests/` | Unit suites on a plain board, plus an integration suite over real IPC |

The last process attached to the board, including the display, removes the
IPC resources when it exits through the normal cleanup path. If every
attached process is killed after initialization, the next invocation in the
same directory removes the abandoned session. A segment with an incompatible
board size is rejected with `EINVAL`.

During play, surviving players remove slots whose recorded PIDs no longer
exist. A killed process can still appear to exist while it is a zombie, until
its parent reaps it. The display checks its local snapshot and closes once all
players recorded in that snapshot are gone.

A `SIGKILL` during initialization can leave private IPC objects behind if it
arrives before the shared segment is created or before its header is fully
initialized. The next run cannot reliably identify those objects for cleanup.
