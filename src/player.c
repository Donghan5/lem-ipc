#include "lemipc.h"

/*
** A stop request that ended a lock wait is a normal exit. The player stays on
** the board until it exits; the other players then reap it.
*/
static int	lock_failed(void)
{
	if (errno == EINTR)
		return (EXIT_SUCCESS);
	perror("semop");
	return (EXIT_FAILURE);
}

static int	finish_player(t_session *session, int player_id, bool eliminated)
{
	int	winner;

	winner = session->board->winner;
	leave_player(session, player_id);
	if (eliminated)
		announce("Player %d was eliminated", player_id, 0);
	else if (winner != 0)
		announce("Team %d wins", winner, 0);
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
		/*
		** Reaping reads /proc for every slot while holding the lock. Done on
		** each 100ms poll by every waiting player, it starved late joiners
		** (make stress). Joiners reap in run_player, so waiting skips it.
		*/
		if (session->board->phase != WAITING)
			reap_players(session->board);
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
			announce("Player %d (team %d) moved", player_id, team);
		if (target.team == 0)
			wait_ms(POLL_MS);
		else
			wait_ms(TICK_MS);
	}
	return (lock_failed());
}

int	run_player(t_session *session, int team)
{
	int	player_id;

	if (lock_board(session) == -1)
		return (lock_failed());
	reap_players(session->board);
	player_id = join_player(session->board, team);
	if (unlock_board(session) == -1)
		return (perror("semop"), EXIT_FAILURE);
	if (player_id == 0)
	{
		ft_putendl_fd("The match is closed to new players.", STDERR_FILENO);
		return (EXIT_FAILURE);
	}
	announce("Player %d joined team %d", player_id, team);
	return (play_match(session, player_id, team));
}
