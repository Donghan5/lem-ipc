#include "harness.h"

#define FUZZ_PLAYERS 60
#define FUZZ_ROUNDS 400000

/* A legal step is exactly one orthogonal tile, and it must not wrap a row. */
static int	bad_step(const t_board *board, int id, int before)
{
	int	step;
	int	drow;
	int	dcolumn;

	step = board->players[id].cell;
	if (step < 0 || step >= BOARD_CELLS)
		return (1);
	drow = step / BOARD_SIZE - before / BOARD_SIZE;
	dcolumn = step % BOARD_SIZE - before % BOARD_SIZE;
	if (abs(drow) + abs(dcolumn) != 1)
		return (1);
	if (board->cells[before] != 0 || board->cells[step] != id)
		return (1);
	return (0);
}

/*
** cells[] and players[] must stay in sync, one player per tile: every
** occupied tile points at a live player standing on it, every live player's
** tile points back at that player, and the number of occupied tiles matches
** the roster count.
*/
static int	bad_invariants(const t_board *board)
{
	int	cell;
	int	id;
	int	occupied;
	int	bad;

	occupied = 0;
	bad = 0;
	id = 1;
	while (id <= BOARD_CELLS)
	{
		if (board->players[id].team != 0
			&& (board->players[id].cell < 0
				|| board->players[id].cell >= BOARD_CELLS
				|| board->cells[board->players[id].cell] != id))
			bad++;
		id++;
	}
	cell = 0;
	while (cell < BOARD_CELLS)
	{
		id = board->cells[cell];
		if (id != 0)
		{
			occupied++;
			if (board->players[id].cell != cell
				|| board->players[id].team == 0)
				bad++;
		}
		cell++;
	}
	if (occupied != board->count)
		bad++;
	return (bad);
}

/*
** Returns the number of illegal steps; *broken counts the rounds after which
** the board no longer had exactly one player per occupied tile.
*/
static int	run_fuzz(t_board *board, int rounds, int *broken)
{
	int	round;
	int	id;
	int	before;
	int	bad;

	bad = 0;
	*broken = 0;
	round = 0;
	while (round < rounds)
	{
		id = 1 + rand() % FUZZ_PLAYERS;
		before = board->players[id].cell;
		if (board->players[id].team != 0
			&& move_player(board, id, rand() % BOARD_CELLS))
			bad += bad_step(board, id, before);
		*broken += (bad_invariants(board) != 0);
		round++;
	}
	return (bad);
}

static void	test_fuzz_invariants(t_suite *s)
{
	static t_board	b;
	int				index;
	int				broken;

	srand(12345);
	board_reset(&b, FUZZ_PLAYERS);
	index = 0;
	while (index < FUZZ_PLAYERS)
		join_player(&b, (index++ % 3) + 1);
	check(s, "fuzz_roster_joined", b.count, FUZZ_PLAYERS);
	check(s, "fuzz_all_steps_legal", run_fuzz(&b, FUZZ_ROUNDS, &broken), 0);
	check(s, "fuzz_one_player_per_tile_every_round", broken, 0);
	check(s, "fuzz_board_consistent", bad_invariants(&b), 0);
}

/* The invariant check must itself catch two players claiming one tile. */
static void	test_invariants_detect_overlap(t_suite *s)
{
	t_board	b;

	board_reset(&b, 2);
	board_put(&b, 1, 1, cell_of(3, 3));
	board_put(&b, 2, 2, cell_of(3, 4));
	check(s, "invariants_accept_valid_board", bad_invariants(&b), 0);
	b.cells[cell_of(3, 4)] = 0;
	b.players[2].cell = cell_of(3, 3);
	b.cells[cell_of(3, 3)] = 2;
	check(s, "invariants_detect_shared_tile", bad_invariants(&b) > 0, true);
	board_reset(&b, 2);
	board_put(&b, 1, 1, cell_of(3, 3));
	board_put(&b, 2, 2, cell_of(3, 4));
	b.cells[cell_of(3, 4)] = 1;
	check(s, "invariants_detect_ghost_tile", bad_invariants(&b) > 0, true);
}

/* A player walled in on all four sides must report that it cannot move. */
static void	test_blocked_player(t_suite *s)
{
	t_board	b;

	board_reset(&b, 5);
	board_put(&b, 1, 1, cell_of(5, 5));
	board_put(&b, 2, 1, cell_of(4, 5));
	board_put(&b, 3, 1, cell_of(6, 5));
	board_put(&b, 4, 1, cell_of(5, 4));
	board_put(&b, 5, 1, cell_of(5, 6));
	check(s, "boxed_in_cannot_move", move_player(&b, 1, 0), false);
	check(s, "boxed_in_stays_put", b.players[1].cell, cell_of(5, 5));
	board_reset(&b, 3);
	board_put(&b, 1, 1, cell_of(0, 0));
	board_put(&b, 2, 1, cell_of(0, 1));
	board_put(&b, 3, 1, cell_of(1, 0));
	check(s, "boxed_corner_cannot_move", move_player(&b, 1, 0), false);
}

/* From a corner only two steps exist, so no move may leave the board. */
static void	test_corner_steps_stay_on_board(t_suite *s)
{
	t_board	b;
	int		round;
	int		bad;

	srand(99);
	bad = 0;
	round = 0;
	while (round < 2000)
	{
		board_reset(&b, 1);
		board_put(&b, 1, 1, cell_of(0, 0));
		if (!move_player(&b, 1, rand() % BOARD_CELLS)
			|| bad_step(&b, 1, cell_of(0, 0)))
			bad++;
		round++;
	}
	check(s, "corner_steps_never_leave_board", bad, 0);
}

static void	test_only_open_neighbor(t_suite *s)
{
	t_board	b;
	int		origin;
	int		destination;

	origin = cell_of(0, BOARD_SIZE - 1);
	destination = cell_of(1, BOARD_SIZE - 1);
	board_reset(&b, 2);
	board_put(&b, 1, 1, origin);
	board_put(&b, 2, 2, origin - 1);
	check(s, "one_open_neighbor_must_move", move_player(&b, 1, origin + 1), true);
	check(s, "only_legal_destination", b.players[1].cell, destination);
	check(s, "previous_cell_recorded", b.players[1].previous, origin);
	check(s, "origin_cleared", b.cells[origin], 0);
	check(s, "destination_claimed", b.cells[destination], 1);
	check(s, "blocker_unchanged", b.cells[origin - 1], 2);
}

int	main(void)
{
	t_suite	s;

	suite_start(&s, "movement: steps + board invariants");
	test_blocked_player(&s);
	test_corner_steps_stay_on_board(&s);
	test_only_open_neighbor(&s);
	test_invariants_detect_overlap(&s);
	test_fuzz_invariants(&s);
	return (suite_end(&s));
}
