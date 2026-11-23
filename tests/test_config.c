#include <unistd.h>
#include <stdlib.h>
#include "harness.h"

/* read_player_count() reports rejections on stderr; keep the log readable. */
static void	mute_stderr(void)
{
	int	fd;

	fd = open("/dev/null", O_WRONLY);
	if (fd == -1)
		return ;
	dup2(fd, STDERR_FILENO);
	close(fd);
}

static int	count_for(const char *value)
{
	if (value == NULL)
		unsetenv("LEMIPC_PLAYERS");
	else
		setenv("LEMIPC_PLAYERS", value, 1);
	return (read_player_count());
}

static void	test_valid_values(t_suite *s)
{
	check(s, "unset_gives_default", count_for(NULL), DEFAULT_PLAYERS);
	check(s, "lower_bound_2", count_for("2"), 2);
	check(s, "upper_bound_400", count_for("400"), BOARD_CELLS);
	check(s, "plain_value_7", count_for("7"), 7);
	check(s, "leading_zeros_accepted", count_for("004"), 4);
}

static void	test_rejected_values(t_suite *s)
{
	check(s, "reject_zero", count_for("0"), -1);
	check(s, "reject_one", count_for("1"), -1);
	check(s, "reject_401", count_for("401"), -1);
	check(s, "reject_huge", count_for("99999"), -1);
	check(s, "reject_overflow", count_for("99999999999999999999"), -1);
	check(s, "reject_empty", count_for(""), -1);
	check(s, "reject_letters", count_for("abc"), -1);
	check(s, "reject_trailing_garbage", count_for("2x"), -1);
	check(s, "reject_negative", count_for("-5"), -1);
	check(s, "reject_space", count_for(" 4"), -1);
	check(s, "reject_plus", count_for("+4"), -1);
}

int	main(void)
{
	t_suite	s;

	mute_stderr();
	suite_start(&s, "config: LEMIPC_PLAYERS parsing");
	test_valid_values(&s);
	test_rejected_values(&s);
	return (suite_end(&s));
}
