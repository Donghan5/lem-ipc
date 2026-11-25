#include "lemipc.h"

static int	stat_path(char *path, pid_t pid)
{
	char	digits[11];
	int		count;
	int		length;

	count = 0;
	digits[count++] = '0' + pid % 10;
	while (pid >= 10)
	{
		pid /= 10;
		digits[count++] = '0' + pid % 10;
	}
	ft_strlcpy(path, "/proc/", 7);
	length = 6;
	while (count > 0)
		path[length++] = digits[--count];
	ft_strlcpy(path + length, "/stat", 6);
	return (open(path, O_RDONLY));
}

/* Field 22 of /proc/<pid>/stat, counted from the state field (3). */
static long long	parse_start(const char *field)
{
	long long	start;
	int			index;

	if (*field == 'Z' || *field == 'X')
		return (-1);
	index = 3;
	while (index < 22 && *field != '\0')
		if (*field++ == ' ')
			index++;
	if (index != 22 || !ft_isdigit(*field))
		return (-1);
	start = 0;
	while (ft_isdigit(*field))
		start = start * 10 + (*field++ - '0');
	return (start);
}

/*
** The start time of a running process, or -1 once it has exited, including
** while it is an unwaited zombie, which kill(pid, 0) still reports as alive.
** A pid and its start time together name one process, even after pid reuse.
*/
long long	process_start(pid_t pid)
{
	char	path[24];
	char	stat[512];
	char	*state;
	ssize_t	size;
	int		fd;

	if (pid <= 0)
		return (-1);
	fd = stat_path(path, pid);
	if (fd == -1)
		return (-1);
	size = read(fd, stat, sizeof(stat) - 1);
	close(fd);
	if (size <= 0)
		return (-1);
	stat[size] = '\0';
	state = ft_strrchr(stat, ')');
	if (state == NULL || state[1] != ' ')
		return (-1);
	return (parse_start(state + 2));
}

/* Without /proc at join time, fall back to plain pid existence. */
bool	player_is_live(const t_player *player)
{
	if (player->started < 0)
		return (!(kill(player->pid, 0) == -1 && errno == ESRCH));
	return (process_start(player->pid) == player->started);
}
