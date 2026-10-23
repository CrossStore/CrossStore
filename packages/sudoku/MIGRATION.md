# Sudoku 0.3.0

This package requires CrossMux Lua API 4 and keeps its 64 KiB VM allowance.

- Three selectable difficulty levels, 43 / 35 / 29 givens, matching the native
  generator's clue counts. The nine original seeds in `assets/puzzles.txt` are
  generated offline, and every seed has exactly one solution.
- Grades are reproducible: easy is solvable with naked singles; medium needs
  hidden singles; hard cannot be completed with either kind of single alone.
  This is a stated solver criterion, not a universal human difficulty rating.
- New games select one of three seeds per grade and permute digits, rows within
  bands, columns within stacks, bands, stacks and transpose the board. Those
  symmetries preserve uniqueness. No expensive solver runs on the device.
- Candidate notes, twenty in-memory undo steps, three hints, mistake count,
  elapsed active time, completion counts and best times. Menus pause the timer.
  Completion is counted once across exit/resume; restarting counts a new attempt.
- New-puzzle and restart actions are explicit. The board adapts to portrait and
  landscape, with shared drawing/hit geometry and at least 6 px between controls.

## Saving

Edits stay in RAM. Save after two seconds without an edit, or at a ten-second
checkpoint while editing. Active timer-only changes checkpoint every ten seconds.
Normal Back, system exit and sleep flush via `on_stop`. Failed writes retain the
pending state, show a title warning and retry; Back stays in the app on failure.
Power loss can still discard changes after the last successful checkpoint.

`game` is one atomic host record: a 17-number metadata header, three 81-digit
strings (givens / board / solution), and 81 comma-separated candidate masks,
separated by `|`. The app reads the old 324-number CSV record from 0.2.0 as well.
New saves should not be read by older app versions. Native C++ binary save files
are not imported by this migration.

## Development

`python3 tools/generate_puzzles.py` reproducibly regenerates the nine seeds.
The catalog tests verify clue counts, uniqueness, solutions and grades. The
firmware's `test/crossstore/test_game_migration.py` runs the actual sandbox,
including save failure/retry, old saves, hints, statistics, full candidate notes,
64 KiB allocation limits, Chinese/English and four viewport sizes.

Compared with the native generator, the seed bank is finite (plus its symmetry
variants). The Lua opponent/solver does not run a new search when opening a puzzle.
