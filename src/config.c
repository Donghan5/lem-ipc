#include "lemipc.h"

static volatile sig_atomic_t	g_stop;

static void	request_stop(int signal_number)
{
	(void)signal_number;
	g_stop = 1;
}

int	install_signals(void)
{
	struct sigaction	action;

	ft_bzero(&action, sizeof(action));
	action.sa_handler = request_stop;
	sigemptyset(&action.sa_mask);
	if (sigaction(SIGINT, &action, NULL) == -1
		|| sigaction(SIGHUP, &action, NULL) == -1
		|| sigaction(SIGQUIT, &action, NULL) == -1
		|| sigaction(SIGPIPE, &action, NULL) == -1)
		return (-1);
	return (sigaction(SIGTERM, &action, NULL));
}

bool	stop_requested(void)
{
	return (g_stop != 0);
}

void	wait_ms(long milliseconds)
{
	struct timespec	delay;

	delay.tv_sec = milliseconds / 1000;
	delay.tv_nsec = (milliseconds % 1000) * 1000000L;
	if (!stop_requested())
		nanosleep(&delay, NULL);
}

int	read_player_count(void)
{
	const char	*value;
	int			count;

	value = getenv("LEMIPC_PLAYERS");
	if (value == NULL)
		return (DEFAULT_PLAYERS);
	count = 0;
	while (ft_isdigit(*value) && count <= BOARD_CELLS)
		count = count * 10 + (*value++ - '0');
	if (*value == '\0' && count >= 2 && count <= BOARD_CELLS)
		return (count);
	ft_putstr_fd("LEMIPC_PLAYERS must be between 2 and ", STDERR_FILENO);
	ft_putnbr_fd(BOARD_CELLS, STDERR_FILENO);
	ft_putchar_fd('\n', STDERR_FILENO);
	return (-1);
}
