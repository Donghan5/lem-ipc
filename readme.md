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

Start the first command and wait for its join message before starting the others when using a custom roster size. With the default roster size, launch four players. Arguments `1` through `7` select a team. Argument `0` opens a terminal view of an existing session. Use Ctrl-C to close the display or withdraw a player running in the foreground.

Players check for elimination before each turn. They move one tile up, down, left, or right when a legal move is available, with one second between turns. A player is eliminated when two or more adjacent players belong to the same opposing team. Diagonal neighbors count for elimination. Teammates exchange target coordinates, and the last team remaining wins.

## Tests

```sh
make test          # unit and integration suites
make unit          # game rules and focused System V IPC tests
make integration   # real processes and real System V IPC
```

`make unit` links every object but `src/main.o`, so the suites call
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

Two integration tests are marked `XFAIL` because they record known defects:

| Test | Defect |
| --- | --- |
| `ipc_cleanup_after_sigkill` | A player killed with SIGKILL never decrements `board->count`, so no survivor runs the cleanup and the shm, msgq and semaphore outlive the match |
| `player_lines_never_garbled` | `ft_printf` issues one `write(2)` per byte, so players sharing a terminal interleave mid-word |

The second test only reproduces when the players share one file descriptor and
start together. `TICK_MS` is one second, so players launched in lockstep print
in the same instant on every tick and collide, while starting them half a
second apart keeps their bursts from overlapping and hides the defect:

| Launch | Malformed lines |
| --- | --- |
| staggered by 0.5s | 0 of 45 |
| started together | 87 of 123 |

Starting every player at once is the documented way to run a match, so the
test launches them that way.

When either defect is fixed the suite prints `XPASS`; drop that test's
known-fail flag in `tests/run_integration.sh` at that point.

Files under `tests/` are deliberately outside 42 Norm scope, since they are not
part of the turn-in. Check the submitted sources with:

```sh
norminette src inc libft
```

## Source layout

| Module | Responsibility |
| --- | --- |
| `main.c`, `config.c` | Command-line dispatch, roster configuration, and signal handling |
| `session.c`, `resources.c` | Session discovery, synchronized initialization, board locking, and IPC removal |
| `player.c`, `roster.c` | Joining, waiting for the roster, taking turns, and leaving |
| `movement.c`, `capture.c`, `target.c` | Legal steps, elimination, and team targeting |
| `display.c` | Copy the board under lock and render the snapshot after unlocking |
| `tests/` | Unit suites on a plain board, plus an integration suite over real IPC |

The last departing player removes the IPC resources. If the remaining players are forcibly killed, for example with SIGKILL, the session can leave IPC resources behind.
