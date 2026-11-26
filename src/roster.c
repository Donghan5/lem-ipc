#include "lemipc.h"

/* Team ids are unbounded, so read the teams off the roster itself. */
static int	find_remaining_team(const t_board *board)
{
	int	player_id;
	int	team;
	int	remaining;

	player_id = 1;
	remaining = 0;
	while (player_id <= BOARD_CELLS)
	{
		team = board->players[player_id++].team;
		if (team != 0 && remaining != 0 && team != remaining)
			return (0);
		if (team != 0)
			remaining = team;
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
	*player = (t_player){team, cell, -1, getpid(), process_start(getpid())};
	board->cells[cell] = player_id;
	board->count++;
	if (board->count == board->expected)
	{
		board->phase = RUNNING;
		record_winner(board);
	}
	return (player_id);
}

static void	clear_player(t_board *board, int player_id)
{
	t_player	*player;

	player = &board->players[player_id];
	board->cells[player->cell] = 0;
	ft_bzero(player, sizeof(*player));
	board->count--;
}

bool	has_live_players(const t_board *board)
{
	int	player_id;

	player_id = 1;
	while (player_id <= BOARD_CELLS)
	{
		if (board->players[player_id].team != 0
			&& player_is_live(&board->players[player_id]))
			return (true);
		player_id++;
	}
	return (false);
}

void	reap_players(t_board *board)
{
	int	player_id;

	player_id = 1;
	while (player_id <= BOARD_CELLS)
	{
		if (board->players[player_id].team != 0
			&& !player_is_live(&board->players[player_id]))
			clear_player(board, player_id);
		player_id++;
	}
	record_winner(board);
}

void	leave_player(t_session *session, int player_id)
{
	t_board	*board;

	board = session->board;
	clear_player(board, player_id);
	record_winner(board);
	if (board->count == 0)
		board->phase = FINISHED;
	if (unlock_board(session) == -1)
		perror("semop");
}
