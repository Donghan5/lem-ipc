#include "lemipc.h"

/* Widest team id on the board; INT_MAX has 10 digits. */
static int	tile_width(const t_board *board)
{
	int	cell;
	int	team;
	int	digits;
	int	width;

	cell = 0;
	width = 1;
	while (cell < BOARD_CELLS)
	{
		team = board->players[board->cells[cell++]].team;
		digits = 1;
		while (team >= 10)
		{
			team /= 10;
			digits++;
		}
		if (digits > width)
			width = digits;
	}
	return (width);
}

/* Right-align one tile; wide tiles are space-separated so ids stay legible. */
static int	put_tile(char *frame, int team, int width, bool first)
{
	int	length;
	int	index;

	length = 0;
	if (width > 1 && !first)
		frame[length++] = ' ';
	index = length + width;
	ft_memset(frame + length, ' ', width);
	frame[index - 1] = '.';
	while (team != 0)
	{
		frame[--index] = '0' + team % 10;
		team /= 10;
	}
	return (length + width);
}

static void	render_board(const t_board *board)
{
	char	frame[BOARD_CELLS * 11 + BOARD_SIZE + 1];
	int		cell;
	int		index;
	int		width;

	cell = 0;
	index = 0;
	width = tile_width(board);
	while (cell < BOARD_CELLS)
	{
		index += put_tile(frame + index,
				board->players[board->cells[cell]].team, width,
				cell % BOARD_SIZE == 0);
		if (++cell % BOARD_SIZE == 0)
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
		{
			if (errno == EINTR)
				break ;
			return (perror("semop"), EXIT_FAILURE);
		}
		if (snapshot.phase != FINISHED && snapshot.count > 0
			&& !has_live_players(&snapshot))
		{
			ft_bzero(snapshot.cells, sizeof(snapshot.cells));
			snapshot.phase = FINISHED;
		}
		render_board(&snapshot);
		if (snapshot.phase == FINISHED)
			break ;
		wait_ms(POLL_MS);
	}
	return (EXIT_SUCCESS);
}
