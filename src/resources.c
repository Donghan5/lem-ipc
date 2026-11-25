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

/*
** All three objects share one key, so whatever a crash leaves behind, at any
** step of creation, is found again through that key. Called under the
** directory lock with no live board, so nobody else can be using them.
*/
int	remove_keyed(t_session *session, key_t key)
{
	session->sem_id = -1;
	session->queue_id = -1;
	if (key != IPC_PRIVATE)
	{
		session->sem_id = semget(key, 0, 0600);
		session->queue_id = msgget(key, 0600);
	}
	return (remove_session(session));
}

int	create_session(t_session *session, key_t key, int expected)
{
	t_semun	initial;

	session->shm_id = -1;
	if (remove_keyed(session, key) == -1)
		return (-1);
	session->sem_id = semget(key, 1, IPC_CREAT | IPC_EXCL | 0600);
	initial.val = 1;
	if (session->sem_id == -1 || semctl(session->sem_id, 0, SETVAL, initial)
		== -1)
		return (fail_creation(session));
	session->queue_id = msgget(key, IPC_CREAT | IPC_EXCL | 0600);
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
