#include "lemipc.h"

static int	attach_session(t_session *session)
{
	session->board = shmat(session->shm_id, NULL, 0);
	if (session->board == (void *)-1)
		return (-1);
	session->sem_id = session->board->sem_id;
	session->queue_id = session->board->queue_id;
	return (0);
}

static int	find_session(t_session *session, int expected)
{
	key_t	key;

	key = ftok(".", 'L');
	if (key == (key_t)-1)
		return (-1);
	session->shm_id = shmget(key, sizeof(t_board), 0600);
	if (session->shm_id >= 0)
		return (attach_session(session));
	if (errno != ENOENT || expected == 0)
		return (-1);
	return (create_session(session, key, expected));
}

int	open_session(t_session *session, int expected)
{
	int	fd;
	int	result;
	int	saved_errno;

	fd = open(".", O_RDONLY | O_DIRECTORY);
	if (fd == -1)
		return (-1);
	result = flock(fd, LOCK_EX);
	if (result == 0)
		result = find_session(session, expected);
	saved_errno = errno;
	close(fd);
	errno = saved_errno;
	return (result);
}

static int	change_lock(const t_session *session, short change)
{
	struct sembuf	operation;
	int				result;

	operation.sem_num = 0;
	operation.sem_op = change;
	operation.sem_flg = SEM_UNDO;
	result = semop(session->sem_id, &operation, 1);
	while (result == -1 && errno == EINTR)
		result = semop(session->sem_id, &operation, 1);
	return (result);
}

int	lock_board(const t_session *session)
{
	return (change_lock(session, -1));
}

int	unlock_board(const t_session *session)
{
	return (change_lock(session, 1));
}
