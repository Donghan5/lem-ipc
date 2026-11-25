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

static int	detach_session(t_session *session, int result)
{
	int	error;

	error = errno;
	if (shmdt(session->board) == -1 && result == 0)
		return (-1);
	errno = error;
	return (result);
}

static int	discard_stale(t_session *session)
{
	if (session->board->expected == 0)
	{
		session->sem_id = -1;
		session->queue_id = -1;
	}
	return (detach_session(session, remove_session(session)));
}

static int	open_existing(t_session *session, key_t key, int expected)
{
	struct shmid_ds	info;

	if (shmctl(session->shm_id, IPC_STAT, &info) == -1)
		return (-1);
	if (info.shm_segsz != sizeof(t_board))
		return (errno = EINVAL, -1);
	if (attach_session(session) == -1)
		return (-1);
	if (info.shm_nattch != 0)
		return (0);
	if (discard_stale(session) == -1)
		return (-1);
	if (expected == 0)
		return (errno = ENOENT, -1);
	return (create_session(session, key, expected));
}

static int	find_session(t_session *session, int expected)
{
	key_t	key;

	key = ftok(".", 'L');
	if (key == (key_t)-1)
		return (-1);
	session->shm_id = shmget(key, 0, 0600);
	if (session->shm_id >= 0)
		return (open_existing(session, key, expected));
	if (errno != ENOENT || expected == 0)
		return (-1);
	return (create_session(session, key, expected));
}

static int	lock_directory(void)
{
	int	fd;
	int	result;

	fd = open(".", O_RDONLY | O_DIRECTORY);
	if (fd == -1)
		return (-1);
	result = flock(fd, LOCK_EX);
	while (result == -1 && errno == EINTR)
		result = flock(fd, LOCK_EX);
	if (result == 0)
		return (fd);
	result = errno;
	close(fd);
	errno = result;
	return (-1);
}

static int	unlock_directory(int fd, int result)
{
	int	error;

	error = errno;
	close(fd);
	errno = error;
	return (result);
}

int	open_session(t_session *session, int expected)
{
	int	fd;

	fd = lock_directory();
	if (fd == -1)
		return (-1);
	return (unlock_directory(fd, find_session(session, expected)));
}

int	close_session(t_session *session)
{
	struct shmid_ds	info;
	int				fd;
	int				result;

	fd = lock_directory();
	if (fd == -1)
		return (detach_session(session, -1));
	result = shmctl(session->shm_id, IPC_STAT, &info);
	if (result == 0 && info.shm_nattch == 1)
		result = remove_session(session);
	result = detach_session(session, result);
	return (unlock_directory(fd, result));
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
