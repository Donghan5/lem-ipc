#ifndef HARNESS_H
# define HARNESS_H

# include "lemipc.h"

typedef struct s_suite
{
	const char	*name;
	int			passed;
	int			failed;
}	t_suite;

/* A semctl(SETVAL) argument; resources.c keeps its own private copy. */
union u_semarg
{
	int					val;
	struct semid_ds		*buf;
	unsigned short int	*array;
};

void	suite_start(t_suite *suite, const char *name);
void	check(t_suite *suite, const char *label, int got, int want);
int		suite_end(t_suite *suite);

void	board_reset(t_board *board, int expected);
void	board_put(t_board *board, int id, int team, int cell);
int		cell_of(int row, int column);
int		team_size(const t_board *board, int team);

int		make_test_semaphore(void);

#endif
