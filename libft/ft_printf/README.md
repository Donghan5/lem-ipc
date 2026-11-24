# ft_printf

## Description
This is a custom implementation of the C standard library's `printf` function. The goal is to recreate the functionality of the original `printf` while understanding its internal workings and handling of variadic arguments.

## Features
The implementation supports the following format specifiers:
- `%c` - Character
- `%s` - String
- `%d` or `%i` - Decimal integer
- `%p` - Pointer address
- `%x` - Hexadecimal (lowercase)
- `%X` - Hexadecimal (uppercase)
- `%u` - Unsigned decimal integer
- `%%` - Percent sign

## Implementation Details
The project is structured as follows:
- `ft_printf.c` - Main function handling format parsing and dispatch
- `ft_printf_strings.c` - Functions for character and string output
- `ft_printf_nbr.c` - Functions for numerical output (decimal, hex, unsigned)
- `ft_printf_address.c` - Function for pointer address output
- Uses the `libft` library for supporting functions

## Memory Management
The implementation takes special care to free any dynamically allocated memory. This is particularly important in the numerical conversion functions to prevent memory leaks.

## Usage
```c
#include "ft_printf.h"

int main(void)
{
    int count;
    int num = 42;
    
    count = ft_printf("This is a string: %s\n", "Hello, world!");
    ft_printf("The previous call printed %d characters\n", count);
    ft_printf("Number in decimal: %d\n", num);
    ft_printf("Number in hexadecimal: %x\n", num);
    ft_printf("Address of num: %p\n", &num);
    
    return (0);
}
```

## Compilation
The project can be compiled using the provided Makefile:
```
make        # Compile the library
make clean  # Remove object files
make fclean # Remove object files and the library
make re     # Recompile everything
```

## Return Value
Like the original `printf`, the function returns the total number of characters printed.

## Notes
- This implementation is part of a programming exercise and may not include all features of the standard `printf`.
- The code follows a specific style guide including 42 header format.
- Built with careful consideration for handling edge cases such as NULL pointers.
