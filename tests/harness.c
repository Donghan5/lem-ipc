#include "harness.h"

void	suite_start(t_suite *suite, const char *name)
{
	suite->name = name;
	suite->passed = 0;
	suite->failed = 0;
	ft_printf("== %s ==\n", name);
}

void	check(t_suite *suite, const char *label, int got, int want)
{
	if (got == want)
	{
		suite->passed++;
		ft_printf("  ok   %s\n", label);
		return ;
	}
	suite->failed++;
	ft_printf("  FAIL %s (got %d, want %d)\n", label, got, want);
}

int	suite_end(t_suite *suite)
{
	ft_printf("-- %s: %d passed, %d failed\n\n", suite->name, suite->passed,
		suite->failed);
	return (suite->failed != 0);
}

void	board_reset(t_board *board, int expected)
{
	ft_bzero(board, sizeof(*board));
	board->expected = expected;
	board->phase = WAITING;
}

/* Place a player directly, bypassing join_player, to build a fixed scenario. */
void	board_put(t_board *board, int id, int team, int cell)
{
	board->players[id].team = team;
	board->players[id].cell = cell;
	board->players[id].previous = -1;
	board->cells[cell] = id;
	board->team_count[team]++;
	board->count++;
}

int	cell_of(int row, int column)
{
	return (row * BOARD_SIZE + column);
}

int	make_test_semaphore(void)
{
	union u_semarg	initial;
	int				sem_id;

	sem_id = semget(IPC_PRIVATE, 1, 0600);
	if (sem_id == -1)
		return (-1);
	initial.val = 1;
	if (semctl(sem_id, 0, SETVAL, initial) == -1)
		return (-1);
	return (sem_id);
}
