#include "lemipc.h"

static bool	is_on_board(int row, int column)
{
	return (row >= 0 && row < BOARD_SIZE && column >= 0
		&& column < BOARD_SIZE);
}

static int	score_move(int cell, int target, int previous)
{
	int	score;

	score = 0;
	if (target >= 0)
		score = abs(cell / BOARD_SIZE - target / BOARD_SIZE)
			+ abs(cell % BOARD_SIZE - target % BOARD_SIZE);
	return (score * 2 + (cell == previous));
}

static int	pick_step(const t_board *board, const t_player *player, int target)
{
	static const int	offsets[4][2] = {{-1, 0}, {0, -1}, {1, 0}, {0, 1}};
	int					direction;
	int					best;
	int					step;
	int					index;

	best = -1;
	index = rand() % 4;
	direction = 0;
	while (direction < 4)
	{
		step = player->cell + offsets[index][0] * BOARD_SIZE
			+ offsets[index][1];
		if (is_on_board(player->cell / BOARD_SIZE + offsets[index][0],
			player->cell % BOARD_SIZE + offsets[index][1])
			&& board->cells[step] == 0 && (best < 0
				|| score_move(step, target, player->previous)
				< score_move(best, target, player->previous)))
			best = step;
		index = (index + 1) % 4;
		direction++;
	}
	return (best);
}

bool	move_player(t_board *board, int player_id, int target_cell)
{
	t_player	*player;
	int			step;

	player = &board->players[player_id];
	if (rand() % 8 == 0)
		target_cell = -1;
	step = pick_step(board, player, target_cell);
	if (step < 0)
		return (false);
	board->cells[player->cell] = 0;
	board->cells[step] = player_id;
	player->previous = player->cell;
	player->cell = step;
	return (true);
}
