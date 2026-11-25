#include "lemipc.h"

/*
** Semaphores 1..BOARD_CELLS count the live processes holding each player
** slot. A claim is made with SEM_UNDO, so the kernel gives it back the
** moment its owner exits, even while that owner is an unwaited zombie, and
** independently of pid reuse. kill(pid, 0) can detect neither case.
*/
int	claim_slot(const t_session *session, int player_id)
{
	struct sembuf	operation;

	operation.sem_num = player_id;
	operation.sem_op = 1;
	operation.sem_flg = SEM_UNDO;
	return (semop(session->sem_id, &operation, 1));
}

/* Cancels the claim and its pending undo; never blocks. */
int	release_slot(const t_session *session, int player_id)
{
	struct sembuf	operation;

	operation.sem_num = player_id;
	operation.sem_op = -1;
	operation.sem_flg = SEM_UNDO | IPC_NOWAIT;
	return (semop(session->sem_id, &operation, 1));
}

/* A slot nobody holds, or a removed set, means its player is gone. */
bool	slot_is_live(const t_session *session, int player_id)
{
	return (semctl(session->sem_id, player_id, GETVAL) > 0);
}
