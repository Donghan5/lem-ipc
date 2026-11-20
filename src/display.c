#include "lemipc.h"

static void	render_board(const t_board *board)
{
	char	frame[BOARD_CELLS + BOARD_SIZE + 1];
	int		cell;
	int		index;
	int		player_id;

	cell = 0;
	index = 0;
	while (cell < BOARD_CELLS)
	{
		player_id = board->cells[cell++];
		frame[index++] = '.';
		if (player_id != 0)
			frame[index - 1] = '0' + board->players[player_id].team;
		if (cell % BOARD_SIZE == 0)
			frame[index++] = '\n';
	}
	frame[index] = '\0';
	if (isatty(STDOUT_FILENO))
		ft_putstr_fd("\033[H\033[J", STDOUT_FILENO);
	ft_putstr_fd(frame, STDOUT_FILENO);
	if (board->winner != 0)
		ft_printf("Team %d wins\n", board->winner);
	else if (board->phase == WAITING)
		ft_printf("Waiting for players (%d/%d)\n", board->count,
			board->expected);
	else if (board->phase == FINISHED)
		ft_putendl_fd("Session closed.", STDOUT_FILENO);
}

static int	copy_board(const t_session *session, t_board *snapshot)
{
	if (lock_board(session) == -1)
	{
		if (errno != EIDRM && errno != EINVAL)
			return (-1);
		ft_memcpy(snapshot, session->board, sizeof(*snapshot));
		return (0);
	}
	ft_memcpy(snapshot, session->board, sizeof(*snapshot));
	return (unlock_board(session));
}

int	show_board(const t_session *session)
{
	t_board	snapshot;

	while (!stop_requested())
	{
		if (copy_board(session, &snapshot) == -1)
			return (perror("semop"), EXIT_FAILURE);
		render_board(&snapshot);
		if (snapshot.phase == FINISHED)
			break ;
		wait_ms(POLL_MS);
	}
	return (EXIT_SUCCESS);
}
