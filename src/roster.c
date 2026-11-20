#include "lemipc.h"

static int	find_remaining_team(const t_board *board)
{
	int	team;
	int	remaining;

	team = 1;
	remaining = 0;
	while (team <= TEAM_COUNT)
	{
		if (board->team_count[team] > 0)
		{
			if (remaining != 0)
				return (0);
			remaining = team;
		}
		team++;
	}
	return (remaining);
}

static void	record_winner(t_board *board)
{
	if (board->phase == RUNNING)
	{
		board->winner = find_remaining_team(board);
		if (board->winner != 0)
			board->phase = FINISHED;
	}
}

int	join_player(t_board *board, int team)
{
	int			player_id;
	int			cell;
	t_player	*player;

	if (board->phase != WAITING || board->count >= board->expected)
		return (0);
	player_id = 1;
	while (board->players[player_id].team != 0)
		player_id++;
	cell = rand() % BOARD_CELLS;
	while (board->cells[cell] != 0)
		cell = (cell + 1) % BOARD_CELLS;
	player = &board->players[player_id];
	*player = (t_player){team, cell, -1};
	board->cells[cell] = player_id;
	board->team_count[team]++;
	board->count++;
	if (board->count == board->expected)
	{
		board->phase = RUNNING;
		record_winner(board);
	}
	return (player_id);
}

void	leave_player(t_session *session, int player_id)
{
	t_board		*board;
	t_player	*player;

	board = session->board;
	player = &board->players[player_id];
	board->cells[player->cell] = 0;
	board->team_count[player->team]--;
	player->team = 0;
	board->count--;
	record_winner(board);
	if (board->count == 0)
	{
		board->phase = FINISHED;
		remove_session(session);
	}
	else if (unlock_board(session) == -1)
		perror("semop");
}
