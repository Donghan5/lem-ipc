#include "harness.h"

/* Subject: a player dies when touched by >= 2 players of one same team. */
static void	test_kill_rule(t_suite *s)
{
	t_board	b;

	board_reset(&b, 3);
	board_put(&b, 1, 1, cell_of(5, 5));
	board_put(&b, 2, 2, cell_of(4, 5));
	board_put(&b, 3, 2, cell_of(6, 5));
	check(s, "two_same_team_enemies_kill", is_surrounded(&b, 1), true);
	board_reset(&b, 3);
	board_put(&b, 1, 1, cell_of(5, 5));
	board_put(&b, 2, 2, cell_of(4, 4));
	board_put(&b, 3, 2, cell_of(6, 6));
	check(s, "diagonal_enemies_kill", is_surrounded(&b, 1), true);
	board_reset(&b, 4);
	board_put(&b, 1, 1, cell_of(5, 5));
	board_put(&b, 2, 2, cell_of(4, 5));
	board_put(&b, 3, 2, cell_of(6, 5));
	board_put(&b, 4, 2, cell_of(5, 4));
	check(s, "three_enemies_still_kill", is_surrounded(&b, 1), true);
}

static void	test_safe_cases(t_suite *s)
{
	t_board	b;

	board_reset(&b, 3);
	board_put(&b, 1, 1, cell_of(5, 5));
	board_put(&b, 2, 2, cell_of(4, 5));
	board_put(&b, 3, 3, cell_of(6, 5));
	check(s, "two_different_enemy_teams_safe", is_surrounded(&b, 1), false);
	board_reset(&b, 2);
	board_put(&b, 1, 1, cell_of(5, 5));
	board_put(&b, 2, 2, cell_of(4, 5));
	check(s, "single_enemy_safe", is_surrounded(&b, 1), false);
	board_reset(&b, 3);
	board_put(&b, 1, 1, cell_of(5, 5));
	board_put(&b, 2, 1, cell_of(4, 5));
	board_put(&b, 3, 1, cell_of(6, 5));
	check(s, "teammates_never_kill", is_surrounded(&b, 1), false);
	board_reset(&b, 1);
	board_put(&b, 1, 1, cell_of(5, 5));
	check(s, "alone_is_safe", is_surrounded(&b, 1), false);
}

/* Team ids are not capped: the same-team rule must hold for any id. */
static void	test_large_team_ids(t_suite *s)
{
	t_board	b;

	board_reset(&b, 3);
	board_put(&b, 1, 1, cell_of(5, 5));
	board_put(&b, 2, 1000, cell_of(4, 5));
	board_put(&b, 3, 1000, cell_of(6, 6));
	check(s, "team_1000_pair_kills", is_surrounded(&b, 1), true);
	board_reset(&b, 3);
	board_put(&b, 1, 8, cell_of(5, 5));
	board_put(&b, 2, 9, cell_of(4, 5));
	board_put(&b, 3, 42, cell_of(6, 5));
	check(s, "teams_9_and_42_mixed_safe", is_surrounded(&b, 1), false);
	board_reset(&b, 9);
	board_put(&b, 1, 2147483647, cell_of(5, 5));
	board_put(&b, 2, 10, cell_of(4, 4));
	board_put(&b, 3, 11, cell_of(4, 5));
	board_put(&b, 4, 12, cell_of(4, 6));
	board_put(&b, 5, 13, cell_of(5, 4));
	board_put(&b, 6, 14, cell_of(5, 6));
	board_put(&b, 7, 15, cell_of(6, 4));
	board_put(&b, 8, 16, cell_of(6, 5));
	check(s, "seven_distinct_teams_safe", is_surrounded(&b, 1), false);
	board_put(&b, 9, 16, cell_of(6, 6));
	check(s, "eighth_neighbour_pairs_team_16", is_surrounded(&b, 1), true);
	board_reset(&b, 3);
	board_put(&b, 1, 2147483647, cell_of(5, 5));
	board_put(&b, 2, 2147483647, cell_of(4, 5));
	board_put(&b, 3, 2147483647, cell_of(6, 5));
	check(s, "int_max_teammates_never_kill", is_surrounded(&b, 1), false);
}

/* The neighbour scan must clamp at the edges instead of wrapping rows. */
static void	test_edges_and_wrap(t_suite *s)
{
	t_board	b;

	board_reset(&b, 3);
	board_put(&b, 1, 1, cell_of(0, 0));
	board_put(&b, 2, 2, cell_of(0, 1));
	board_put(&b, 3, 2, cell_of(1, 0));
	check(s, "corner_victim_kill", is_surrounded(&b, 1), true);
	board_reset(&b, 3);
	board_put(&b, 1, 1, cell_of(19, 19));
	board_put(&b, 2, 2, cell_of(19, 18));
	board_put(&b, 3, 2, cell_of(18, 19));
	check(s, "far_corner_victim_kill", is_surrounded(&b, 1), true);
	board_reset(&b, 3);
	board_put(&b, 1, 1, cell_of(5, 0));
	board_put(&b, 2, 2, cell_of(4, 19));
	board_put(&b, 3, 2, cell_of(5, 19));
	check(s, "no_horizontal_wrap", is_surrounded(&b, 1), false);
	board_reset(&b, 3);
	board_put(&b, 1, 1, cell_of(0, 5));
	board_put(&b, 2, 2, cell_of(19, 4));
	board_put(&b, 3, 2, cell_of(19, 5));
	check(s, "no_vertical_wrap", is_surrounded(&b, 1), false);
}

static void	test_targeting(t_suite *s)
{
	t_board		b;
	t_target	tg;

	board_reset(&b, 2);
	board_put(&b, 1, 1, cell_of(2, 3));
	board_put(&b, 2, 2, cell_of(7, 9));
	ft_bzero(&tg, sizeof(tg));
	choose_target(&b, 1, &tg);
	check(s, "target_row", tg.row, 7);
	check(s, "target_column", tg.column, 9);
	check(s, "target_player_id", tg.player_id, 2);
	check(s, "target_mtype_is_team", (int)tg.team, 1);
	board_reset(&b, 1);
	board_put(&b, 1, 1, cell_of(2, 3));
	ft_bzero(&tg, sizeof(tg));
	choose_target(&b, 1, &tg);
	check(s, "no_enemy_row_sentinel", tg.row, -1);
	check(s, "no_enemy_player_id", tg.player_id, 0);
}

/* A remembered target that has left the board must be replaced, not reused. */
static void	test_stale_target_dropped(t_suite *s)
{
	t_board		b;
	t_target	tg;

	board_reset(&b, 3);
	board_put(&b, 1, 1, cell_of(2, 3));
	board_put(&b, 2, 2, cell_of(7, 9));
	board_put(&b, 3, 2, cell_of(1, 1));
	ft_bzero(&tg, sizeof(tg));
	choose_target(&b, 1, &tg);
	check(s, "stale_initial_pick", tg.player_id, 2);
	b.players[2].team = 0;
	b.cells[cell_of(7, 9)] = 0;
	choose_target(&b, 1, &tg);
	check(s, "stale_target_replaced", tg.player_id, 3);
	ft_bzero(&tg, sizeof(tg));
	tg.player_id = 1;
	choose_target(&b, 1, &tg);
	check(s, "teammate_never_targeted", tg.player_id, 3);
}

int	main(void)
{
	t_suite	s;

	suite_start(&s, "rules: capture + targeting");
	test_kill_rule(&s);
	test_safe_cases(&s);
	test_large_team_ids(&s);
	test_edges_and_wrap(&s);
	test_targeting(&s);
	test_stale_target_dropped(&s);
	return (suite_end(&s));
}
