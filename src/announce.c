#include "lemipc.h"

static int	put_number(char *line, int length, int value)
{
	char	digits[11];
	int		count;

	count = 0;
	if (value < 0)
		value = 0;
	digits[count++] = '0' + value % 10;
	while (value >= 10)
	{
		value /= 10;
		digits[count++] = '0' + value % 10;
	}
	while (count > 0)
		line[length++] = digits[--count];
	return (length);
}

/*
** Prints one line through a single write(). ft_printf issues one write per
** byte, so lines from players sharing a terminal or file would interleave.
** The format only understands %d, at most twice, with non-negative values.
*/
void	announce(const char *format, int first, int second)
{
	char	line[ANNOUNCE_MAX];
	int		length;

	length = 0;
	while (*format != '\0' && length < ANNOUNCE_MAX - 24)
	{
		if (format[0] == '%' && format[1] == 'd')
		{
			length = put_number(line, length, first);
			first = second;
			format += 2;
		}
		else
			line[length++] = *format++;
	}
	line[length++] = '\n';
	if (write(STDOUT_FILENO, line, length) == -1)
		return ;
}
