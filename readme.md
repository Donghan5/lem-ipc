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

## Source layout

| Module | Responsibility |
| --- | --- |
| `main.c`, `config.c` | Command-line dispatch, roster configuration, and signal handling |
| `session.c`, `resources.c` | Session discovery, synchronized initialization, board locking, and IPC removal |
| `player.c`, `roster.c` | Joining, waiting for the roster, taking turns, and leaving |
| `movement.c`, `capture.c`, `target.c` | Legal steps, elimination, and team targeting |
| `display.c` | Copy the board under lock and render the snapshot after unlocking |

The last departing player removes the IPC resources. If the remaining players are forcibly killed, for example with SIGKILL, the session can leave IPC resources behind.
