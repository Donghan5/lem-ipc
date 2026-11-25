#include "lemipc.h"

typedef union u_semun
{
	int	val;
}	t_semun;

static bool	removal_failed(int result)
{
	return (result == -1 && errno != EINVAL && errno != EIDRM);
}

/* Keep the board discoverable until its queue and semaphore are gone. */
int	remove_session(t_session *session)
{
	int	error;

	error = 0;
	if (session->queue_id >= 0
		&& removal_failed(msgctl(session->queue_id, IPC_RMID, NULL)))
		error = errno;
	if (session->sem_id >= 0
		&& removal_failed(semctl(session->sem_id, 0, IPC_RMID)) && !error)
		error = errno;
	if (error)
		return (errno = error, -1);
	if (session->shm_id >= 0
		&& removal_failed(shmctl(session->shm_id, IPC_RMID, NULL)))
		return (-1);
	return (0);
}

static int	fail_creation(t_session *session)
{
	int	saved_errno;

	saved_errno = errno;
	if (remove_session(session) == -1)
		perror("remove_session");
	errno = saved_errno;
	return (-1);
}

int	create_session(t_session *session, key_t key, int expected)
{
	t_semun	initial;

	session->shm_id = -1;
	session->queue_id = -1;
	session->sem_id = semget(IPC_PRIVATE, 1, 0600);
	initial.val = 1;
	if (session->sem_id == -1 || semctl(session->sem_id, 0, SETVAL, initial)
		== -1)
		return (fail_creation(session));
	session->queue_id = msgget(IPC_PRIVATE, 0600);
	if (session->queue_id == -1)
		return (fail_creation(session));
	session->shm_id = shmget(key, sizeof(t_board), IPC_CREAT | IPC_EXCL
			| 0600);
	if (session->shm_id == -1)
		return (fail_creation(session));
	session->board = shmat(session->shm_id, NULL, 0);
	if (session->board == (void *)-1)
		return (fail_creation(session));
	session->board->sem_id = session->sem_id;
	session->board->queue_id = session->queue_id;
	session->board->expected = expected;
	return (0);
}
