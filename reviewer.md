Act as an independent reviewer deciding whether the current lem-ipc submission candidate is ready for 42 peer evaluation. Perform the checks yourself and report the evidence.

Scope
- Review only criteria 1–3 below. Exclude criterion 4, which is my ability to explain the code in person.
- Start by recording the exact commit SHA. Use HEAD unless I provide a different commit. Report any uncommitted changes separately so I know what was excluded from the review.
- Read the assignment PDF, FAQ, README, and Makefile. Use the assignment and FAQ to identify mandatory requirements.
- This is a verification-only task. Treat src/ and inc/ as strictly read-only. Do not edit any repository file, add tests or scenarios, commit, or push. Build and test the exact candidate commit in a clean temporary checkout.

1. Clean build and 2 vs 2 run
- Run `make` in the clean checkout and confirm that it builds `lemipc`.
- Start two Team 1 players, two Team 2 players, and the display in the same working directory. Use `make demo` if present, or use the documented commands.
- Verify that four distinct player processes join, the display renders the board, and the match reaches a valid winner. Either team may win. Use a bounded timeout and report the actual result, including any hang or timeout.

2. Mandatory behavior
- Verify that players move one square up, down, left, or right and that no two players share a square.
- Verify that elimination requires at least two adjacent players from the same opposing team, that diagonals count for elimination, and that two opponents from different teams do not satisfy the rule. Verify that the last remaining team wins.
- Verify that the board uses System V shared memory, that a semaphore protects concurrent board access, and that teammates exchange target coordinates through the message queue. Use existing targeted tests where available. Verify team-specific delivery directly instead of inferring it from player movement.
- For each finding, distinguish what you observed at runtime from what you verified by reading the source. Cite relevant test names or file and line numbers.

3. Exit, memory, and IPC cleanup
- Run `make eval` and any existing focused tests needed to cover gaps. Check what the harness actually asserts before accepting a PASS label as evidence.
- Verify cleanup after normal completion and SIGINT. Check SIGKILL during play with a survivor, and recovery on the next run in the same directory after all players are killed. If the display can be the last attached process, verify that path too.
- Verify the exact SHM, semaphore, and message-queue IDs for each tested session. If the harness removes an object left behind by the program, count that as a cleanup failure. Touch only processes and resources created by your own test runs.
- Report actual Valgrind findings and which processes were checked. If Valgrind is unavailable, mark memory verification as SKIP. Mark exit-time leak checks for SIGKILL victims as N/A.

Return the report in Korean:
- Start with `GO`, `NO-GO`, or `UNVERIFIED`, followed by the tested commit SHA.
- Include a compact table with one row per criterion and columns for Result, Evidence, and Remaining gap.
- List the exact commands run and summarize any failures, skips, or timeouts.
- Use GO when all three criteria are verified, NO-GO when you reproduce a failure against those criteria, and UNVERIFIED when a required check could not be completed.
- If you find a blocker, give the shortest reproduction and the expected and actual outcomes. Leave fixes for a separate task. Optional polish should not affect the verdict.
