#include <sys/wait.h>
#include <unistd.h>
#include "harness.h"

static bool	wait_status(pid_t child, int expected_signal)
{
	int	status;

	if (child <= 0 || waitpid(child, &status, 0) != child)
		return (false);
	if (expected_signal != 0)
		return (WIFSIGNALED(status) && WTERMSIG(status) == expected_signal);
	return (WIFEXITED(status) && WEXITSTATUS(status) == 0);
}

static bool	wait_for_waiter(int id)
{
	int	attempt;

	for (attempt = 0; attempt < 200; attempt++)
	{
		if (semctl(id, 0, GETNCNT) == 1)
			return (true);
		usleep(10000);
	}
	return (false);
}

static volatile sig_atomic_t	signal_seen;

static void	note_signal(int signal_number)
{
	(void)signal_number;
	signal_seen = 1;
}

static void	test_contended_lock(t_suite *s, t_session *session)
{
	struct sigaction	action = {.sa_handler = note_signal};
	pid_t				child;

	check(s, "parent_acquires_lock", lock_board(session), 0);
	check(s, "held_lock_value_is_zero", semctl(session->sem_id, 0, GETVAL), 0);
	child = fork();
	if (child == 0)
	{
		alarm(6);
		sigemptyset(&action.sa_mask);
		if (sigaction(SIGUSR1, &action, NULL) == -1 || lock_board(session) == -1)
			_exit(1);
		if (!signal_seen || session->board->count != 17
			|| unlock_board(session) == -1)
			_exit(1);
		_exit(0);
	}
	if (child > 0)
	{
		check(s, "second_process_blocks", wait_for_waiter(session->sem_id), true);
		check(s, "interrupt_sent_to_waiter", kill(child, SIGUSR1), 0);
		/* Keep the lock held while the waiter handles the signal. */
		usleep(50000);
		check(s, "interrupted_waiter_retries",
			semctl(session->sem_id, 0, GETNCNT), 1);
	}
	session->board->count = 17;
	check(s, "parent_releases_lock", unlock_board(session), 0);
	check(s, "waiter_reads_published_state_and_unlocks", wait_status(child, 0), true);
	check(s, "unlocked_value_is_one", semctl(session->sem_id, 0, GETVAL), 1);
}

static void	test_crashed_lock_owner(t_suite *s, t_session *session)
{
	int		ready[2];
	char	marker;
	pid_t	child;

	if (pipe(ready) == -1)
	{
		check(s, "owner_handshake_pipe", 0, 1);
		return ;
	}
	child = fork();
	if (child == 0)
	{
		close(ready[0]);
		alarm(6);
		if (lock_board(session) == -1 || write(ready[1], "L", 1) != 1)
			_exit(1);
		for (;;)
			pause();
	}
	close(ready[1]);
	check(s, "child_holds_lock_before_death", read(ready[0], &marker, 1) == 1, true);
	close(ready[0]);
	check(s, "crashed_owner_held_lock", semctl(session->sem_id, 0, GETVAL), 0);
	if (child > 0)
		check(s, "kill_lock_owner", kill(child, SIGKILL), 0);
	check(s, "owner_died_by_sigkill", wait_status(child, SIGKILL), true);
	check(s, "sem_undo_releases_dead_owners_lock",
		semctl(session->sem_id, 0, GETVAL), 1);
}

static void	test_reattach(t_suite *s, t_session *session)
{
	pid_t	child;

	child = fork();
	if (child == 0)
	{
		t_session	attached = {0};

		alarm(6);
		if (shmdt(session->board) == -1 || open_session(&attached, 0) == -1)
			_exit(1);
		if (attached.shm_id != session->shm_id || attached.sem_id != session->sem_id
			|| attached.queue_id != session->queue_id
			|| attached.board->expected != 3 || attached.board->count != 17)
			_exit(1);
		attached.board->count = 23;
		_exit(shmdt(attached.board) == -1);
	}
	check(s, "independent_process_reattaches_to_same_session",
		wait_status(child, 0), true);
	check(s, "parent_sees_reattached_process_write", session->board->count, 23);
}

static bool	id_gone(int result)
{
	return (result == -1 && (errno == EINVAL || errno == EIDRM));
}

static void	test_removal(t_suite *s, t_session *session, key_t key,
		bool with_waiter)
{
	struct shmid_ds	memory;
	struct msqid_ds	queue;
	int				result;
	pid_t			child;

	child = -1;
	if (with_waiter && semctl(session->sem_id, 0, GETVAL) == 1)
	{
		check(s, "lock_held_before_removal", lock_board(session), 0);
		child = fork();
		if (child == 0)
		{
			alarm(6);
			result = lock_board(session);
			_exit(result != -1 || errno != EIDRM);
		}
		check(s, "waiter_blocked_before_removal",
			child > 0 && wait_for_waiter(session->sem_id), true);
	}
	remove_session(session);
	if (with_waiter)
		check(s, "removal_wakes_blocked_waiter_with_eidrm", wait_status(child, 0), true);
	check(s, "only_parent_still_attached",
		shmctl(session->shm_id, IPC_STAT, &memory) == 0 && memory.shm_nattch == 1, true);
	result = shmget(key, sizeof(t_board), 0600);
	check(s, "removed_key_immediately_unavailable", result == -1 && errno == ENOENT, true);
	check(s, "attached_view_survives_removal", session->board->expected, 3);
	check(s, "last_view_detaches", shmdt(session->board), 0);
	check(s, "shared_memory_id_gone_after_last_detach",
		id_gone(shmctl(session->shm_id, IPC_STAT, &memory)), true);
	check(s, "message_queue_id_gone", id_gone(msgctl(session->queue_id, IPC_STAT, &queue)), true);
	result = id_gone(semctl(session->sem_id, 0, GETVAL));
	check(s, "semaphore_id_gone", result, true);
	check(s, "lock_fails_after_removal", result && id_gone(lock_board(session)), true);
	/* Clean up by ID even when the code under test leaked an object. */
	if (shmctl(session->shm_id, IPC_STAT, &memory) == 0)
		shmctl(session->shm_id, IPC_RMID, NULL);
	if (msgctl(session->queue_id, IPC_STAT, &queue) == 0)
		msgctl(session->queue_id, IPC_RMID, NULL);
	if (semctl(session->sem_id, 0, GETVAL) >= 0)
		semctl(session->sem_id, 0, IPC_RMID);
}

static void	test_lifecycle(t_suite *s)
{
	t_session	session = {0};
	key_t		key;
	int			result;
	int			cycle;

	key = ftok(".", 'L');
	check(s, "session_key_created", key != (key_t)-1, true);
	if (key == (key_t)-1)
		return ;
	result = shmget(key, 1, 0600);
	check(s, "session_key_is_unused", result == -1 && errno == ENOENT, true);
	if (result != -1 || errno != ENOENT)
		return ;
	for (cycle = 0; cycle < 3; cycle++)
	{
		result = open_session(&session, 3);
		check(s, "create_session_on_same_key", result, 0);
		if (result == -1)
			return ;
		check(s, "fresh_board_count_is_zero", session.board->count, 0);
		check(s, "fresh_board_is_waiting", session.board->phase, WAITING);
		check(s, "fresh_semaphore_value_is_one", semctl(session.sem_id, 0, GETVAL), 1);
		if (cycle == 0 && semctl(session.sem_id, 0, GETVAL) == 1)
		{
			test_contended_lock(s, &session);
			test_crashed_lock_owner(s, &session);
			test_reattach(s, &session);
		}
		test_removal(s, &session, key, cycle == 2);
	}
}

int	main(void)
{
	char	dir[] = "/tmp/lemipc-lifecycle-XXXXXX";
	t_suite	s;

	suite_start(&s, "IPC: semaphore contention and shared session lifecycle");
	if (mkdtemp(dir) == NULL)
		check(&s, "temporary_directory_created", 0, 1);
	else
	{
		if (chdir(dir) == 0)
			test_lifecycle(&s);
		else
			check(&s, "temporary_directory_entered", 0, 1);
		check(&s, "temporary_directory_removed", rmdir(dir), 0);
	}
	return (suite_end(&s));
}
