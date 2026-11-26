#include "lemipc.h"

static int	print_usage(const char *program)
{
	ft_putstr_fd("Usage: ", STDERR_FILENO);
	ft_putstr_fd((char *)program, STDERR_FILENO);
	ft_putendl_fd(" [0-7] (0 displays the board)", STDERR_FILENO);
	return (EXIT_FAILURE);
}

static int	open_client_session(t_session *session, int expected)
{
	if (install_signals() == -1)
		perror("lemipc");
	else if (open_session(session, expected) == 0)
		return (EXIT_SUCCESS);
	else if (expected == 0 && errno == ENOENT)
		ft_putendl_fd("lemipc: No active game session in this directory. "
			"Start a player first.", STDERR_FILENO);
	else
		perror("lemipc");
	return (EXIT_FAILURE);
}

int	main(int argc, char **argv)
{
	t_session	session;
	int			team;
	int			expected;
	int			result;

	if (argc != 2 || ft_strlen(argv[1]) != 1
		|| argv[1][0] < '0' || argv[1][0] > '0' + TEAM_COUNT)
		return (print_usage(argv[0]));
	team = argv[1][0] - '0';
	expected = 0;
	if (team != 0)
		expected = read_player_count();
	if (expected < 0)
		return (EXIT_FAILURE);
	if (open_client_session(&session, expected) != EXIT_SUCCESS)
		return (EXIT_FAILURE);
	srand((unsigned int)getpid());
	if (team == 0)
		result = show_board(&session);
	else
		result = run_player(&session, team);
	if (close_session(&session) == -1)
		return (perror("close_session"), EXIT_FAILURE);
	return (result);
}
