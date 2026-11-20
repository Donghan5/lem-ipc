#include "lemipc.h"

static int	get_team_at(const t_board *board, int row, int column)
{
	int	player_id;

	if (row < 0 || row >= BOARD_SIZE || column < 0 || column >= BOARD_SIZE)
		return (0);
	player_id = board->cells[row * BOARD_SIZE + column];
	return (board->players[player_id].team);
}

bool	is_surrounded(const t_board *board, int player_id)
{
	int	counts[TEAM_COUNT + 1];
	int	cell;
	int	offset;
	int	team;

	ft_bzero(counts, sizeof(counts));
	cell = board->players[player_id].cell;
	offset = 0;
	while (offset < 9)
	{
		team = get_team_at(board, cell / BOARD_SIZE + offset / 3 - 1,
				cell % BOARD_SIZE + offset % 3 - 1);
		if (team != 0 && team != board->players[player_id].team
			&& ++counts[team] >= 2)
			return (true);
		offset++;
	}
	return (false);
}
