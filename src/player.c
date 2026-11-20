#include "lemipc.h"

static int	finish_player(t_session *session, int player_id, bool eliminated)
{
	int	winner;

	winner = session->board->winner;
	leave_player(session, player_id);
	if (eliminated)
		ft_printf("Player %d was eliminated\n", player_id);
	else if (winner != 0)
		ft_printf("Team %d wins\n", winner);
	return (EXIT_SUCCESS);
}

static bool	play_turn(t_session *session, int player_id, int team,
		t_target *target)
{
	choose_target(session->board, team, target);
	return (move_player(session->board, player_id,
			target->row * BOARD_SIZE + target->column));
}

static int	play_match(t_session *session, int player_id, int team)
{
	t_target	target;
	bool		eliminated;
	bool		moved;

	ft_bzero(&target, sizeof(target));
	while (lock_board(session) == 0)
	{
		eliminated = session->board->phase == RUNNING
			&& is_surrounded(session->board, player_id);
		if (stop_requested() || eliminated || session->board->phase == FINISHED)
			return (finish_player(session, player_id, eliminated));
		moved = false;
		if (session->board->phase == RUNNING)
			moved = play_turn(session, player_id, team, &target);
		if (unlock_board(session) == -1)
			break ;
		if (target.team != 0)
			exchange_target(session, &target);
		if (moved)
			ft_printf("Player %d (team %d) moved\n", player_id, team);
		if (target.team == 0)
			wait_ms(POLL_MS);
		else
			wait_ms(TICK_MS);
	}
	return (perror("semop"), EXIT_FAILURE);
}

int	run_player(t_session *session, int team)
{
	int	player_id;

	if (lock_board(session) == -1)
		return (perror("semop"), EXIT_FAILURE);
	player_id = join_player(session->board, team);
	if (unlock_board(session) == -1)
		return (perror("semop"), EXIT_FAILURE);
	if (player_id == 0)
	{
		ft_putendl_fd("The match is closed to new players.", STDERR_FILENO);
		return (EXIT_FAILURE);
	}
	ft_printf("Player %d joined team %d\n", player_id, team);
	return (play_match(session, player_id, team));
}
