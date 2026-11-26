#include "lemipc.h"

static int	get_team_at(const t_board *board, int row, int column)
{
	int	player_id;

	if (row < 0 || row >= BOARD_SIZE || column < 0 || column >= BOARD_SIZE)
		return (0);
	player_id = board->cells[row * BOARD_SIZE + column];
	return (board->players[player_id].team);
}

/* Count one more neighbour of team; at most 8 distinct teams fit around. */
static int	tally(int teams[8], int counts[8], int *seen, int team)
{
	int	index;

	index = 0;
	while (index < *seen && teams[index] != team)
		index++;
	if (index == *seen)
	{
		teams[index] = team;
		counts[index] = 0;
		(*seen)++;
	}
	return (++counts[index]);
}

bool	is_surrounded(const t_board *board, int player_id)
{
	int	teams[8];
	int	counts[8];
	int	seen;
	int	cell;
	int	offset;
	int	team;

	seen = 0;
	cell = board->players[player_id].cell;
	offset = 0;
	while (offset < 9)
	{
		team = get_team_at(board, cell / BOARD_SIZE + offset / 3 - 1,
				cell % BOARD_SIZE + offset % 3 - 1);
		if (team != 0 && team != board->players[player_id].team
			&& tally(teams, counts, &seen, team) >= 2)
			return (true);
		offset++;
	}
	return (false);
}
