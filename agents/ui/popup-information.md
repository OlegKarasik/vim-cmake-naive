# Information Popup (`:CMakeInfo`)

**Scope:** Popup created by `:CMakeInfo` via `popup_create`.
**Trigger keywords:** CMakeInfo popup, info popup size, popup_create.
**Depends on:** none.
**Conflicts:** none.

## Visual style

1. width is dynamic and clamped to `10..100`
2. width is computed from max(title length, content width)
3. height is dynamic and clamped to `1..10`
4. highlight: `Pmenu`
5. border highlight: `Pmenu`
6. single-line rounded border style
7. padding: top/right/bottom/left = `0,1,0,1`

## Content

1. config table lines (`key | value`) when config exists
2. one guidance line when config is missing

## Behavior

Uses `popup_filter_menu` filter behavior.

