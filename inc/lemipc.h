#ifndef LEMIPC_H
# define LEMIPC_H

# include <errno.h>
# include <fcntl.h>
# include <signal.h>
# include <stdbool.h>
# include <stdio.h>
# include <sys/file.h>
# include <sys/ipc.h>
# include <sys/msg.h>
# include <sys/sem.h>
# include <sys/shm.h>
# include <time.h>
# include "libft.h"
# include "ft_printf.h"

# define BOARD_SIZE 20
# define BOARD_CELLS 400
# define TEAM_COUNT 7
# define DEFAULT_PLAYERS 4
# define TICK_MS 1000
# define POLL_MS 100

typedef enum e_phase
{
	WAITING,
	RUNNING,
	FINISHED
}	t_phase;

typedef struct s_player
{
	int	team;
	int	cell;
	int	previous;
}	t_player;

typedef struct s_board
{
	int			sem_id;
	int			queue_id;
	int			expected;
	int			count;
	int			team_count[TEAM_COUNT + 1];
	int			winner;
	t_phase		phase;
	int			cells[BOARD_CELLS];
	t_player	players[BOARD_CELLS + 1];
}	t_board;

typedef struct s_session
{
	int		shm_id;
	int		sem_id;
	int		queue_id;
	t_board	*board;
}	t_session;

typedef struct s_target
{
	long	team;
	int		player_id;
	int		row;
	int		column;
}	t_target;

int		open_session(t_session *session, int expected);
int		create_session(t_session *session, key_t key, int expected);
void	remove_session(t_session *session);
int		lock_board(const t_session *session);
int		unlock_board(const t_session *session);

int		run_player(t_session *session, int team);
int		join_player(t_board *board, int team);
void	leave_player(t_session *session, int player_id);
bool	is_surrounded(const t_board *board, int player_id);
bool	move_player(t_board *board, int player_id, int target_cell);
void	choose_target(const t_board *board, int team, t_target *target);
void	exchange_target(const t_session *session, t_target *target);
int		show_board(const t_session *session);

int		read_player_count(void);
int		install_signals(void);
bool	stop_requested(void);
void	wait_ms(long milliseconds);

#endif
