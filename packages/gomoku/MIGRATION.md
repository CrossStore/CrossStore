# Gomoku 0.3.0

This package requires CrossMux Lua API 4 and keeps its 64 KiB VM allowance.

- 9×9 and 15×15 boards, local two-player games, or a computer opponent.
- Play black or white. New-game options are drafts until the user confirms;
  changing a setting and returning no longer erases the ongoing match.
- Three computer levels: easy adds bounded ranking variation; medium ranks
  attack/defense patterns; hard additionally evaluates opponent replies for the
  best six candidates. All levels take immediate wins and block immediate losses.
- AI work is sliced between callbacks (18 candidate evaluations / 24 reply
  evaluations per callback). Simulated stones are removed before returning to
  the host, so saving midway through a search records only the real game.
- Active time, per-board starts / black wins / white wins / draws / fastest
  completed game. Completed matches are counted once across restart/resume.
  Undo is available during an unfinished match; computer games undo a turn pair.

The Lua AI is a bounded two-ply tactical evaluator. It does not claim the same
playing strength as the native C++ engine's iterative search up to depth six.

## Memory and persistence

The board packs two bits per point into at most fifteen integer rows. Move
history is at most 225 indices. Loading streams CSV moves into those final
arrays; saving joins the move history directly instead of copying it. UI phrases
are an 854-byte asset to reduce compiler-time allocation pressure; translations
still go through `app.tr`.

Edits save after two seconds idle, at ten-second checkpoints, and before normal
exit/sleep. Timer-only changes checkpoint every ten seconds. Save errors retain
pending state, display a warning and retry; Back remains in the app on failure.
Sudden power loss can lose changes after the last successful checkpoint.

`game` is one host record: `3,n,computer,level,human,elapsed,recorded`, ten
statistics values (five for each board size), then chronological move indices.
The original `n,computer,moves...` saves from 0.2.0 remain readable. New records
are not intended for older app versions. Native binary game saves are not
imported.

The firmware's independent `test/crossstore/test_game_migration.py` covers all
three levels' forced win/block, sliced hard search, draft settings, old saves,
225-move draw reload/save, allocation limits, Chinese/English and four viewport
sizes. Hardware play strength and visual spacing still merit real-device review.
