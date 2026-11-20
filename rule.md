# lem-ipc Coding Rules for AI Agents

Apply these rules when writing or editing C code and Makefiles for lem-ipc.

1. **42 Norm.** Prefer to follow the 42 Norm and check changed C files with `norminette` when available. Norminette compliance is recommended by this guide and is required wherever the assignment or evaluation requires it.
2. **Function names.** Use a verb that describes the action and name what it acts on where helpful. Examples include `attach_shared_memory`, `lock_board`, and `is_cell_empty`.
3. **Function parameters.** Use at most five parameters per function. Aim for three or fewer. The 42 Norm limits functions to four named parameters, so use four or fewer whenever following the Norm.
4. **Local variables.** Use at most five local variables per function. Aim for three or fewer. Count local variables separately from parameters.
5. **Makefile sources.** List each source file explicitly. Do not use `$(wildcard ...)` or glob patterns such as `src/*.c` to discover sources.
6. **Code comments.** Add comments only when they help explain what a function does. Skip comments when the function name and code already make its behavior clear.
7. **Allowed functions.** Use `libc` functions only when `libft` has no equivalent. If `libft` provides an equivalent, call the project’s `libft` implementation. The subject expects `libft` to include your own `printf` implementation.

## Additional conventions

- Use descriptive `snake_case` names for functions and variables. Use names such as `team_id` and `empty_cell_count` where they make the code easier to read.
- Keep each function focused on one responsibility. If several parameters already belong to an existing project struct, consider passing that struct. Keep unrelated values explicit.
