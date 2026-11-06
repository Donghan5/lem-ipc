# lem-ipc

42 infrastructure project (out-circle) in prep.

## Main Rules of command line
- the executable will be named `lemipc`
- 0 is for graphic mode
- the other 1 to 7 which are team numbers.

## Game Rules
- Each player is represented by its team number on the grid.
- Each second a player mooves
- A player can move only in 4 directions (up, down, left and right)
- A player can move several times in a row
- You cannot differentiate players from the same team on the grid
- All the players of a same team target all together the same ennemy player.
- When two players from the same team surround an ennemy player, this one dies (diagonal works).
- It's mandatory for a player to move when it's its turn, even if th's just next to its target.
- The game stop when only one team is remaining.

## What we use
- Shared memory segment --> contain map and game data
- Semaphore sets --> secure the access of the shared memory segment
- message queue --> allow the players of a same team to exchange ennemy player ID to focus.

## Architecture of project
- Launch the game with `./lemipc [team_number]`
- If `0` launch the game in graphic mode, else launch a player of the team number given.
- init IPC and spawn a player in the map and wait for the other players to join.
- When all the players are spawned, the game starts and each player move in its own process
- Team communication with message queue.
- When a player move, it update the shared memory segment with its new position and the new position of the ennemy player if it was killed (Sync game board).
- Log showing (Following a subject asking)
- Clean all the resources before exit.
- 
