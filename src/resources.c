#include "lemipc.h"

typedef union u_semun
{
	int	val;
}	t_semun;

void	remove_session(t_session *session)
{
	if (session->shm_id >= 0 && shmctl(session->shm_id, IPC_RMID, NULL) == -1)
		perror("shmctl");
	if (session->queue_id >= 0 && msgctl(session->queue_id, IPC_RMID,
			NULL) == -1)
		perror("msgctl");
	if (session->sem_id >= 0 && semctl(session->sem_id, 0, IPC_RMID) == -1)
		perror("semctl");
}

static int	fail_creation(t_session *session)
{
	int	saved_errno;

	saved_errno = errno;
	remove_session(session);
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
