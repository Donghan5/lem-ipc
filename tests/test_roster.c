#include "harness.h"

static void	test_join(t_suite *s)
{
	t_board	b;

	board_reset(&b, 3);
	check(s, "join_first_id", join_player(&b, 1), 1);
	check(s, "join_second_id", join_player(&b, 1), 2);
	check(s, "join_third_id", join_player(&b, 2), 3);
	check(s, "join_over_roster_refused", join_player(&b, 2), 0);
	check(s, "phase_running_when_full", b.phase == RUNNING, true);
	check(s, "count_matches_roster", b.count, 3);
	check(s, "team_one_counted", b.team_count[1], 2);
	check(s, "team_two_counted", b.team_count[2], 1);
	check(s, "cells_are_distinct", b.players[1].cell != b.players[2].cell
		&& b.players[2].cell != b.players[3].cell
		&& b.players[1].cell != b.players[3].cell, true);
	check(s, "no_winner_with_two_teams", b.winner, 0);
}

/* A late joiner must be refused once the match is no longer WAITING. */
static void	test_join_refused_after_start(t_suite *s)
{
	t_board	b;

	board_reset(&b, 2);
	join_player(&b, 1);
	join_player(&b, 2);
	check(s, "join_refused_when_running", join_player(&b, 1), 0);
	b.phase = FINISHED;
	check(s, "join_refused_when_finished", join_player(&b, 1), 0);
}

/* A single surviving team must be recorded as the winner on the last leave. */
static void	test_leave_and_winner(t_suite *s)
{
	t_session	session;
	t_board		b;

	ft_bzero(&session, sizeof(session));
	session.shm_id = -1;
	session.queue_id = -1;
	session.sem_id = make_test_semaphore();
	if (session.sem_id == -1)
	{
		check(s, "make_test_semaphore", 0, 1);
		return ;
	}
	board_reset(&b, 3);
	session.board = &b;
	join_player(&b, 1);
	join_player(&b, 1);
	join_player(&b, 2);
	lock_board(&session);
	leave_player(&session, 3);
	check(s, "count_after_leave", b.count, 2);
	check(s, "tile_freed_on_leave", b.cells[b.players[3].cell], 0);
	check(s, "slot_freed_on_leave", b.players[3].team, 0);
	check(s, "team_count_decremented", b.team_count[2], 0);
	check(s, "winner_is_last_team", b.winner, 1);
	check(s, "phase_finished_on_win", b.phase == FINISHED, true);
	semctl(session.sem_id, 0, IPC_RMID);
}

static void	test_waiting_slot_reused(t_suite *s)
{
	t_session	session = {.shm_id = -1, .queue_id = -1};
	t_board		b;
	int			cell;

	session.sem_id = make_test_semaphore();
	check(s, "waiting_semaphore_created", session.sem_id >= 0, true);
	if (session.sem_id < 0)
		return ;
	session.board = &b;
	board_reset(&b, 3);
	join_player(&b, 1);
	join_player(&b, 2);
	cell = b.players[1].cell;
	if (lock_board(&session) == 0)
	{
		leave_player(&session, 1);
		check(s, "withdrawal_keeps_waiting", b.phase, WAITING);
		check(s, "withdrawal_frees_old_tile", b.cells[cell], 0);
		check(s, "new_player_reuses_slot", join_player(&b, 3), 1);
		check(s, "reused_slot_has_new_team", b.players[1].team, 3);
		check(s, "reused_slot_owns_its_cell", b.cells[b.players[1].cell], 1);
		check(s, "rejoin_restores_count", b.count, 2);
	}
	else
		check(s, "waiting_board_locked", 0, 1);
	semctl(session.sem_id, 0, IPC_RMID);
}

static void	test_one_team_wins_at_capacity(t_suite *s)
{
	t_board	b;

	board_reset(&b, 2);
	join_player(&b, TEAM_COUNT);
	check(s, "one_team_waits_before_capacity", b.phase, WAITING);
	check(s, "no_winner_before_capacity", b.winner, 0);
	check(s, "last_teammate_joins", join_player(&b, TEAM_COUNT), 2);
	check(s, "one_team_finishes_at_capacity", b.phase, FINISHED);
	check(s, "highest_team_id_wins", b.winner, TEAM_COUNT);
}

/* 400 players on a 400-cell board: every tile taken, nobody can move. */
static void	test_full_board(t_suite *s)
{
	t_board	b;
	int		index;
	int		holes;
	int		moved;

	board_reset(&b, BOARD_CELLS);
	index = 0;
	holes = 0;
	while (index < BOARD_CELLS)
	{
		if (join_player(&b, (index % 2) + 1) == 0)
			holes++;
		index++;
	}
	check(s, "all_400_players_joined", holes, 0);
	check(s, "count_is_400", b.count, BOARD_CELLS);
	check(s, "join_401st_refused", join_player(&b, 1), 0);
	index = 0;
	while (index < BOARD_CELLS)
	{
		if (b.cells[index] == 0)
			holes++;
		index++;
	}
	check(s, "board_has_no_empty_tile", holes, 0);
	index = 1;
	moved = 0;
	while (index <= BOARD_CELLS)
	{
		if (move_player(&b, index, 0))
			moved++;
		index++;
	}
	check(s, "no_move_possible_when_full", moved, 0);
}

int	main(void)
{
	t_suite	s;

	suite_start(&s, "roster: join + leave + winner");
	test_join(&s);
	test_join_refused_after_start(&s);
	test_leave_and_winner(&s);
	test_waiting_slot_reused(&s);
	test_one_team_wins_at_capacity(&s);
	test_full_board(&s);
	return (suite_end(&s));
}
