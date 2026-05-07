# Shared Popup Rules (Copied)

**Scope:** Baseline rules shared across repositories for interactive selection popups.
**Trigger keywords:** popup keys, popup search mode, popup filtering, no matches.
**Depends on:** none.
**Conflicts:** none.
**Precedence:** these shared rules override any conflicting repository-local popup rules.

## Visual style

1. dynamic height: `1..10` lines (with scrollbar)
2. highlight: `Pmenu`
3. border highlight: `Pmenu`
4. single-line rounded border style
5. width is repository/command specific (see repository-specific popup docs)

## Navigation keys

1. `j` or `Down` - move down
2. `k` or `Up` - move up
3. `Enter`, or `CR` - confirm selection
4. `x` or `Esc` - close/cancel

## Search mode

1. `Ctrl+F` toggles search mode on/off
2. while search mode is on, title ends with `(SEARCH)`
3. with query text and search mode on, title becomes `<Prompt> [<query>] (SEARCH)`
4. search is case-insensitive substring matching
5. query updates after each typed character
6. `Backspace`, `Ctrl+H`, `Del`, and `kDel` remove one character
7. `Ctrl+U` clears query
8. leaving search mode keeps current query/filter active and title in
   `<Prompt> [<query>]` format

## Key precedence

1. `Esc` and `Enter` remain command keys even when search mode is active
2. any other printable characters are inserted into search query while search
   mode is active

## Empty results

Empty filter result is rendered as one row: `1.   no matches`.
