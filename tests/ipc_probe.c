#include <limits.h>
#include <string.h>
#include "lemipc.h"

static int	print_session(void)
{
	key_t			key;
	int				id;
	t_board			*board;
	struct shmid_ds	info;

	key = ftok(".", 'L');
	if (key == (key_t)-1)
		return (1);
	id = shmget(key, sizeof(t_board), 0600);
	if (id == -1)
		return (errno == ENOENT ? 1 : 2);
	if (shmctl(id, IPC_STAT, &info) == -1)
		return (1);
	board = shmat(id, NULL, SHM_RDONLY);
	if (board == (void *)-1)
		return (1);
	printf("%d %d %d %ld\n", id, board->queue_id, board->sem_id,
		(long)info.shm_cpid);
	return (shmdt(board) == -1);
}

/* 0: present, 1: gone, 2: the probe could not establish either. */
static int	probe_id(const char *kind, const char *value)
{
	struct shmid_ds	memory;
	struct msqid_ds	queue;
	char			*end;
	long			id;
	int				result;

	errno = 0;
	id = strtol(value, &end, 10);
	if (errno != 0 || end == value || *end != '\0' || id < 0 || id > INT_MAX)
		return (2);
	if (strcmp(kind, "shm") == 0)
		result = shmctl((int)id, IPC_STAT, &memory);
	else if (strcmp(kind, "queue") == 0)
		result = msgctl((int)id, IPC_STAT, &queue);
	else if (strcmp(kind, "sem") == 0)
		result = semctl((int)id, 0, GETVAL);
	else
		return (2);
	if (result >= 0)
		return (0);
	if (errno == EINVAL || errno == EIDRM)
		return (1);
	perror(kind);
	return (2);
}

int	main(int argc, char **argv)
{
	int			fd;
	int			result;

	if (argc == 3)
		return (probe_id(argv[1], argv[2]));
	if (argc != 1)
		return (2);
	fd = open(".", O_RDONLY | O_DIRECTORY);
	if (fd == -1 || flock(fd, LOCK_SH | LOCK_NB) == -1)
		return (2);
	result = print_session();
	close(fd);
	return (result);
}
