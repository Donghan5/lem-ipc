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

/*
** A lock owner frozen by Ctrl+Z (simulated by the parent never unlocking)
** must not trap the others: a stop request has to end their wait, whether it
** lands while they are blocked or just before they start waiting.
*/
static void	test_stop_while_waiting(t_suite *s, t_session *session)
{
	pid_t	blocked;
	pid_t	early;

	check(s, "frozen_owner_holds_lock", lock_board(session), 0);
	blocked = fork();
	if (blocked == 0)
	{
		alarm(3);
		if (install_signals() == -1)
			_exit(1);
		_exit(!(lock_board(session) == -1 && errno == EINTR));
	}
	check(s, "stop_target_blocks", wait_for_waiter(session->sem_id), true);
	check(s, "stop_sent_to_waiter", kill(blocked, SIGINT), 0);
	check(s, "stop_ends_blocked_wait", wait_status(blocked, 0), true);
	early = fork();
	if (early == 0)
	{
		alarm(3);
		if (install_signals() == -1 || raise(SIGINT) != 0)
			_exit(1);
		_exit(!(lock_board(session) == -1 && errno == EINTR));
	}
	check(s, "stop_before_wait_never_blocks", wait_status(early, 0), true);
	check(s, "frozen_owner_unlocks", unlock_board(session), 0);
	check(s, "lock_free_after_stopped_waiters",
		semctl(session->sem_id, 0, GETVAL), 1);
}

static pid_t	start_lock_waiter(t_session *session)
{
	pid_t	child;

	child = fork();
	if (child == 0)
	{
		alarm(6);
		if (lock_board(session) == -1 || unlock_board(session) == -1)
			_exit(1);
		_exit(0);
	}
	return (child);
}

static void	test_crashed_lock_owner(t_suite *s, t_session *session)
{
	int		ready[2];
	char	marker;
	pid_t	child;
	pid_t	waiter;

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
	waiter = start_lock_waiter(session);
	check(s, "waiter_blocks_behind_owner_before_sigkill",
		waiter > 0 && wait_for_waiter(session->sem_id), true);
	if (child > 0)
		check(s, "kill_lock_owner", kill(child, SIGKILL), 0);
	check(s, "owner_died_by_sigkill", wait_status(child, SIGKILL), true);
	check(s, "waiter_acquires_and_releases_lock_after_sigkill",
		wait_status(waiter, 0), true);
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
		bool with_waiter, int expected)
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
	check(s, "attached_view_survives_removal", session->board->expected, expected);
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

static bool	key_unused(key_t key)
{
	return (shmget(key, 0, 0600) == -1 && errno == ENOENT
		&& semget(key, 0, 0600) == -1 && errno == ENOENT
		&& msgget(key, 0600) == -1 && errno == ENOENT);
}

/*
** What a session that crashed while being created leaves behind must be found
** through the key and reclaimed: a semaphore and a queue whose board never
** existed, or also a board whose creator died before recording their IDs.
*/
static void	test_orphans_reclaimed(t_suite *s, key_t key, bool with_board)
{
	t_session		session = {0};
	struct msqid_ds	queue;
	struct shmid_ds	memory;
	int				sem_id;
	int				queue_id;
	int				shm_id;

	sem_id = semget(key, 1, IPC_CREAT | IPC_EXCL | 0600);
	queue_id = msgget(key, IPC_CREAT | IPC_EXCL | 0600);
	shm_id = -1;
	if (with_board)
		shm_id = shmget(key, sizeof(t_board), IPC_CREAT | IPC_EXCL | 0600);
	check(s, with_board ? "orphan_board_planted" : "orphans_planted",
		sem_id >= 0 && queue_id >= 0 && (!with_board || shm_id >= 0), true);
	check(s, "session_opens_over_orphans", open_session(&session, 3), 0);
	check(s, "orphan_semaphore_reclaimed",
		id_gone(semctl(sem_id, 0, GETVAL)), true);
	check(s, "orphan_queue_reclaimed",
		id_gone(msgctl(queue_id, IPC_STAT, &queue)), true);
	if (with_board)
		check(s, "orphan_board_reclaimed",
			id_gone(shmctl(shm_id, IPC_STAT, &memory)), true);
	check(s, "new_semaphore_and_queue_are_keyed",
		semget(key, 0, 0600) == session.sem_id
		&& msgget(key, 0600) == session.queue_id, true);
	if (session.board != NULL)
		check(s, "orphan_test_session_closed", close_session(&session), 0);
	check(s, "key_fully_released", key_unused(key), true);
	/* Clean up by ID even when the code under test leaked an object. */
	if (semctl(sem_id, 0, GETVAL) >= 0)
		semctl(sem_id, 0, IPC_RMID);
	if (msgctl(queue_id, IPC_STAT, &queue) == 0)
		msgctl(queue_id, IPC_RMID, NULL);
	if (shm_id >= 0 && shmctl(shm_id, IPC_STAT, &memory) == 0)
		shmctl(shm_id, IPC_RMID, NULL);
	sem_id = semget(key, 0, 0600);
	if (sem_id >= 0)
		semctl(sem_id, 0, IPC_RMID);
	queue_id = msgget(key, 0600);
	if (queue_id >= 0)
		msgctl(queue_id, IPC_RMID, NULL);
}

enum { RACE_PLAYERS = 4, RACE_TURNS = 100 };

static bool	board_is_consistent(const t_board *board)
{
	int	count = 0;

	for (int id = 1; id <= BOARD_CELLS; id++)
	{
		const t_player *player = &board->players[id];

		if (player->team == 0)
			continue ;
		if (player->team < 1 || player->pid <= 0
			|| player->cell < 0 || player->cell >= BOARD_CELLS
			|| board->cells[player->cell] != id)
			return (false);
		count++;
	}
	for (int cell = 0; cell < BOARD_CELLS; cell++)
	{
		int id = board->cells[cell];

		if (id != 0 && (id < 1 || id > BOARD_CELLS
				|| board->players[id].team == 0 || board->players[id].cell != cell))
			return (false);
	}
	return (count == board->count && count <= board->expected);
}

static void	race_worker(int team, int ready, int start, int turns)
{
	t_session	session = {0};
	char		marker;
	int			id;
	bool		valid;

	alarm(10);
	if (write(ready, "R", 1) != 1 || read(start, &marker, 1) != 0
		|| open_session(&session, RACE_PLAYERS) == -1
		|| lock_board(&session) == -1)
		_exit(1);
	/* Give every worker the same first spawn candidate. */
	srand(1);
	id = join_player(session.board, team);
	valid = id > 0 && board_is_consistent(session.board);
	if (unlock_board(&session) == -1 || !valid)
		_exit(1);
	if (write(ready, "J", 1) != 1)
		_exit(1);
	close(ready);
	/* Start taking turns only after all joins have been reported. */
	if (read(turns, &marker, 1) != 0)
		_exit(1);
	for (int turn = 0; turn < RACE_TURNS; turn++)
	{
		if (lock_board(&session) == -1)
			_exit(1);
		move_player(session.board, id, BOARD_CELLS / 2);
		valid = session.board->phase == RUNNING && board_is_consistent(session.board);
		if (unlock_board(&session) == -1 || !valid)
			_exit(1);
	}
	_exit(shmdt(session.board) == -1);
}

static bool	receive_workers(int fd, int count, char expected)
{
	char	marker;

	for (int index = 0; index < count; index++)
		if (read(fd, &marker, 1) != 1 || marker != expected)
			return (false);
	return (true);
}

static bool	joined_workers(const t_board *board, const pid_t *children)
{
	if (!board_is_consistent(board) || board->expected != RACE_PLAYERS
		|| board->count != RACE_PLAYERS || board->phase != RUNNING)
		return (false);
	for (int index = 0; index < RACE_PLAYERS; index++)
	{
		int matches = 0;

		for (int id = 1; id <= BOARD_CELLS; id++)
			if (board->players[id].pid == children[index]
				&& board->players[id].team == 1 + index % 2)
				matches++;
		if (matches != 1)
			return (false);
	}
	return (true);
}

static void	test_concurrent_board(t_suite *s, key_t key)
{
	int			pipes[3][2];
	int			created = 0;
	pid_t		children[RACE_PLAYERS];
	int			workers = 0;
	t_session	session = {0};
	bool		attached;

	for (; created < 3; created++)
		if (pipe(pipes[created]) == -1)
			break ;
	check(s, "concurrent_board_pipes_created", created, 3);
	if (created != 3)
	{
		for (int index = 0; index < created; index++)
		{
			close(pipes[index][0]);
			close(pipes[index][1]);
		}
		return ;
	}
	for (; workers < RACE_PLAYERS; workers++)
	{
		children[workers] = fork();
		if (children[workers] == -1)
			break ;
		if (children[workers] == 0)
		{
			close(pipes[0][0]);
			close(pipes[1][1]);
			close(pipes[2][1]);
			race_worker(1 + workers % 2, pipes[0][1], pipes[1][0], pipes[2][0]);
		}
	}
	close(pipes[0][1]);
	close(pipes[1][0]);
	close(pipes[2][0]);
	check(s, "all_workers_ready_before_session_open",
		receive_workers(pipes[0][0], workers, 'R') && workers == RACE_PLAYERS, true);
	close(pipes[1][1]);
	check(s, "all_workers_join_before_first_turn",
		receive_workers(pipes[0][0], workers, 'J') && workers == RACE_PLAYERS, true);
	close(pipes[0][0]);
	attached = open_session(&session, 0) == 0;
	check(s, "concurrent_session_available_to_observer", attached, true);
	close(pipes[2][1]);
	for (int index = 0; index < workers; index++)
		check(s, "worker_board_consistent_after_each_join_and_turn", wait_status(children[index], 0), true);
	if (attached)
	{
		check(s, "all_workers_joined_same_board_once",
			workers == RACE_PLAYERS && joined_workers(session.board, children), true);
		test_removal(s, &session, key, false, RACE_PLAYERS);
	}
}

static void	test_lifecycle(t_suite *s)
{
	t_session	session = {0};
	key_t		key;
	int			result;
	int			cycle;
	bool		unused_key;

	key = ftok(".", 'L');
	check(s, "session_key_created", key != (key_t)-1, true);
	if (key == (key_t)-1)
		return ;
	result = shmget(key, 1, 0600);
	unused_key = result == -1 && errno == ENOENT;
	check(s, "session_key_is_unused", unused_key, true);
	if (!unused_key)
		return ;
	test_concurrent_board(s, key);
	test_orphans_reclaimed(s, key, false);
	test_orphans_reclaimed(s, key, true);
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
			test_stop_while_waiting(s, &session);
			test_crashed_lock_owner(s, &session);
			test_reattach(s, &session);
		}
		test_removal(s, &session, key, cycle == 2, 3);
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
