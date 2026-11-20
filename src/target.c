#include "lemipc.h"

static bool	is_enemy(const t_board *board, int player_id, int team)
{
	return (player_id > 0 && player_id <= BOARD_CELLS
		&& board->players[player_id].team != 0
		&& board->players[player_id].team != team);
}

void	choose_target(const t_board *board, int team, t_target *target)
{
	int	player_id;
	int	cell;

	player_id = target->player_id;
	if (!is_enemy(board, player_id, team))
	{
		player_id = 1;
		while (player_id <= BOARD_CELLS && !is_enemy(board, player_id, team))
			player_id++;
	}
	target->team = team;
	target->player_id = 0;
	target->row = -1;
	target->column = 0;
	if (player_id <= BOARD_CELLS)
	{
		cell = board->players[player_id].cell;
		target->player_id = player_id;
		target->row = cell / BOARD_SIZE;
		target->column = cell % BOARD_SIZE;
	}
}

void	exchange_target(const t_session *session, t_target *target)
{
	t_target	incoming;
	size_t		size;

	size = sizeof(t_target) - sizeof(long);
	if (msgrcv(session->queue_id, &incoming, size, target->team, IPC_NOWAIT)
		== (ssize_t)size && incoming.player_id > 0)
		*target = incoming;
	msgsnd(session->queue_id, target, size, IPC_NOWAIT);
}
