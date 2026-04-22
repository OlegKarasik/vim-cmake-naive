# Selection Popups (Shared Behavior)

**Scope:** Shared behavior for selection popups used by:

1. `:CMakeSwitchPreset`
2. `:CMakeSwitchBuild`
3. `:CMakeSwitchTarget`
4. `:CMakeMenu`
5. `:CMakeMenuFull`

**Trigger keywords:** popup keys, popup search mode, popup filtering, no matches.
**Depends on:** none.
**Conflicts:** none.

## Visual style

1. fixed width: `30`
2. dynamic height: `1..10` lines (with scrollbar)
3. highlight: `Pmenu`
4. border highlight: `Pmenu`
5. single-line rounded border style

## Navigation keys

1. `j` or `Down` - move down
2. `k` or `Up` - move up
3. `Enter`, or `CR` - confirm selection
4. `x` or `Esc` - close/cancel

## Search mode

1. `Ctrl+F` toggles search mode on/off
2. while search mode is on, title ends with `--SEARCH--`
3. with query text, title becomes `<Prompt> [<query>] --SEARCH--`
4. search is case-insensitive substring matching
5. query updates after each typed character
6. `Backspace`, `Ctrl+H`, `Del`, and `kDel` remove one character
7. `Ctrl+U` clears query
8. leaving search mode keeps current query/filter active and title in
   `<Prompt> [<query>] --SEARCH--` format

## Key precedence

1. `Esc` and `Enter` remain command keys even when search mode is active
2. any other printable characters are inserted into search query while search
   mode is active

## Empty results

Empty filter result is rendered as one row: `1.   no matches`.
