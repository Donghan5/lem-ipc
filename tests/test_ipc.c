#include <unistd.h>
#include <sys/wait.h>
#include "harness.h"

static int	fail_semaphore;
static int	fail_queue;
static int	fail_memory;
static int	fail_attach;
/* Emulates SEMMSL: the most semaphores the kernel allows in one set. */
static int	semaphores_per_set;

int	__real_semget(key_t key, int count, int flags);
int	__real_msgget(key_t key, int flags);
int	__real_shmget(key_t key, size_t size, int flags);
void	*__real_shmat(int id, const void *address, int flags);

int	__wrap_semget(key_t key, int count, int flags)
{
	if (semaphores_per_set > 0 && count > semaphores_per_set)
		return (errno = EINVAL, -1);
	if (!fail_semaphore)
		return (__real_semget(key, count, flags));
	errno = ENOSPC;
	return (-1);
}

/*
** The session must fit the tightest kernel: a single semaphore. Anything more
** makes the game unplayable where SEMMSL or SEMMNS headroom is small.
*/
static void	test_single_semaphore_kernel(t_suite *s)
{
	t_session	session;
	int			result;

	semaphores_per_set = 1;
	result = create_session(&session, IPC_PRIVATE, 2);
	semaphores_per_set = 0;
	check(s, "session_fits_one_semaphore_kernel", result, 0);
	if (result != 0)
		return ;
	check(s, "single_semaphore_set_size",
		semctl(session.sem_id, 1, GETVAL) == -1 && errno == EINVAL, true);
	check(s, "single_semaphore_session_removed", remove_session(&session), 0);
	check(s, "single_semaphore_view_detached", shmdt(session.board), 0);
}

int	__wrap_msgget(key_t key, int flags)
{
	if (!fail_queue)
		return (__real_msgget(key, flags));
	errno = ENOSPC;
	return (-1);
}

int	__wrap_shmget(key_t key, size_t size, int flags)
{
	if (!fail_memory)
		return (__real_shmget(key, size, flags));
	errno = ENOSPC;
	return (-1);
}

void	*__wrap_shmat(int id, const void *address, int flags)
{
	if (!fail_attach)
		return (__real_shmat(id, address, flags));
	errno = ENOMEM;
	return ((void *)-1);
}

static bool	removed(int result)
{
	return (result == -1 && (errno == EINVAL || errno == EIDRM));
}

static void	test_creation_failure(t_suite *s, int *fault, int expected_errno)
{
	t_session		session;
	struct msqid_ds	queue;
	struct shmid_ds	memory;
	int				result;
	int				error;

	*fault = 1;
	result = create_session(&session, IPC_PRIVATE, 2);
	error = errno;
	*fault = 0;
	check(s, "creation_fails", result, -1);
	check(s, "creation_preserves_errno", error, expected_errno);
	check(s, "semaphore_was_created", session.sem_id >= 0, fault != &fail_semaphore);
	if (session.sem_id >= 0)
		check(s, "semaphore_rolled_back",
			removed(semctl(session.sem_id, 0, GETVAL)), true);
	if (fault == &fail_memory || fault == &fail_attach)
	{
		check(s, "queue_was_created", session.queue_id >= 0, true);
		check(s, "queue_rolled_back",
			removed(msgctl(session.queue_id, IPC_STAT, &queue)), true);
	}
	if (fault == &fail_attach)
	{
		check(s, "shared_memory_was_created", session.shm_id >= 0, true);
		check(s, "shared_memory_rolled_back",
			removed(shmctl(session.shm_id, IPC_STAT, &memory)), true);
	}
	if (result == 0)
		shmdt(session.board);
	if (session.sem_id >= 0 && semctl(session.sem_id, 0, GETVAL) >= 0)
		semctl(session.sem_id, 0, IPC_RMID);
	if (session.queue_id >= 0 && msgctl(session.queue_id, IPC_STAT, &queue) == 0)
		msgctl(session.queue_id, IPC_RMID, NULL);
	if (session.shm_id >= 0 && shmctl(session.shm_id, IPC_STAT, &memory) == 0)
		shmctl(session.shm_id, IPC_RMID, NULL);
}

static bool	bounded_exchange(t_session *session, t_target *target)
{
	int		channel[2];
	int		status;
	pid_t	child;
	ssize_t	bytes;

	if (pipe(channel) == -1)
		return (false);
	child = fork();
	if (child == 0)
	{
		close(channel[0]);
		alarm(3);
		exchange_target(session, target);
		_exit(write(channel[1], target, sizeof(*target)) != sizeof(*target));
	}
	close(channel[1]);
	bytes = read(channel[0], target, sizeof(*target));
	close(channel[0]);
	return (child > 0 && waitpid(child, &status, 0) == child
		&& WIFEXITED(status) && WEXITSTATUS(status) == 0
		&& bytes == sizeof(*target));
}

static void	test_team_exchange(t_suite *s, t_session *session, size_t size)
{
	t_target	own = {1, 21, 4, 5};
	t_target	other = {2, 42, 6, 7};
	t_target	got = {0};

	check(s, "exchange_with_empty_queue_returns", bounded_exchange(session, &own), true);
	check(s, "empty_queue_preserves_target", own.player_id, 21);
	check(s, "empty_queue_publishes_target",
		msgrcv(session->queue_id, &got, size, 1, IPC_NOWAIT), size);
	check(s, "published_target_payload", got.player_id, 21);
	check(s, "other_team_published",
		msgsnd(session->queue_id, &other, size, IPC_NOWAIT), 0);
	check(s, "exchange_with_other_team_returns", bounded_exchange(session, &own), true);
	check(s, "missing_team_message_preserves_target", own.player_id, 21);
	check(s, "other_team_message_still_queued",
		msgrcv(session->queue_id, &got, size, 2, IPC_NOWAIT), size);
	check(s, "other_team_payload_preserved", got.player_id, 42);
	own.player_id = 99;
	check(s, "exchange_with_own_team_returns", bounded_exchange(session, &own), true);
	check(s, "same_team_message_received", own.player_id, 21);
	check(s, "same_team_row_received", own.row, 4);
	check(s, "same_team_column_received", own.column, 5);
	check(s, "received_message_republished",
		msgrcv(session->queue_id, &got, size, 1, IPC_NOWAIT), size);
	check(s, "republished_payload", got.player_id, 21);
}

static void	test_full_queue(t_suite *s, t_session *session, size_t size)
{
	struct msqid_ds	queue;
	t_target		other = {2, 42, 6, 7};
	t_target		own = {1, 21, 4, 5};
	t_target		got = {0};
	ssize_t			result;

	if (msgctl(session->queue_id, IPC_STAT, &queue) == -1)
	{
		check(s, "queue_limits_read", 0, 1);
		return ;
	}
	queue.msg_qbytes = size;
	if (msgctl(session->queue_id, IPC_SET, &queue) == -1)
	{
		check(s, "queue_capacity_set", 0, 1);
		return ;
	}
	check(s, "queue_filled_by_other_team",
		msgsnd(session->queue_id, &other, size, IPC_NOWAIT), 0);
	check(s, "full_queue_returns_with_own_target",
		bounded_exchange(session, &own) && own.team == 1
		&& own.player_id == 21 && own.row == 4 && own.column == 5, true);
	check(s, "full_queue_preserves_other_message",
		msgrcv(session->queue_id, &got, size, 2, IPC_NOWAIT), size);
	check(s, "full_queue_other_payload", got.player_id, 42);
	result = msgrcv(session->queue_id, &got, size, 1, IPC_NOWAIT);
	check(s, "full_queue_dropped_new_message", result == -1 && errno == ENOMSG, true);
}

static void	test_invalid_messages(t_suite *s, t_session *session, size_t size)
{
	t_target	own = {1, 21, 4, 5};
	t_target	short_message = {1, 99, 8, 9};
	t_target	sentinel = {1, 0, -1, 0};
	t_target	got = {0};

	check(s, "short_message_enqueued",
		msgsnd(session->queue_id, &short_message, sizeof(int), IPC_NOWAIT), 0);
	check(s, "short_message_ignored",
		bounded_exchange(session, &own) && own.player_id == 21
		&& own.row == 4 && own.column == 5, true);
	check(s, "valid_replacement_after_short_message",
		msgrcv(session->queue_id, &got, size, 1, IPC_NOWAIT) == (ssize_t)size
		&& got.player_id == 21 && got.row == 4 && got.column == 5, true);
	check(s, "sentinel_enqueued", msgsnd(session->queue_id, &sentinel, size, IPC_NOWAIT), 0);
	check(s, "sentinel_does_not_replace_live_target",
		bounded_exchange(session, &own) && own.player_id == 21, true);
	check(s, "live_target_republished_after_sentinel",
		msgrcv(session->queue_id, &got, size, 1, IPC_NOWAIT) == (ssize_t)size
		&& got.player_id == 21, true);
}

static void	test_exchange(t_suite *s)
{
	t_session	session = {0};
	size_t		size;
	t_target	target = {1, 21, 4, 5};
	struct msqid_ds info;

	session.queue_id = msgget(IPC_PRIVATE, 0600);
	check(s, "queue_created", session.queue_id >= 0, true);
	if (session.queue_id < 0)
		return ;
	size = sizeof(t_target) - sizeof(long);
	test_team_exchange(s, &session, size);
	test_invalid_messages(s, &session, size);
	test_full_queue(s, &session, size);
	check(s, "queue_removed", msgctl(session.queue_id, IPC_RMID, NULL), 0);
	check(s, "queue_id_is_invalid_after_removal",
		removed(msgctl(session.queue_id, IPC_STAT, &info)), true);
	check(s, "exchange_on_removed_queue_preserves_target",
		bounded_exchange(&session, &target) && target.player_id == 21, true);
}

int	main(void)
{
	t_suite	s;

	suite_start(&s, "IPC: creation rollback and target exchange");
	test_creation_failure(&s, &fail_semaphore, ENOSPC);
	test_creation_failure(&s, &fail_queue, ENOSPC);
	test_creation_failure(&s, &fail_memory, ENOSPC);
	test_creation_failure(&s, &fail_attach, ENOMEM);
	test_single_semaphore_kernel(&s);
	test_exchange(&s);
	return (suite_end(&s));
}
