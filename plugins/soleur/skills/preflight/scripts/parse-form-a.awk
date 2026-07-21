# Form A parser for preflight Check 10 Step 10.4 — the production runtime of record.
# Mirrored (non-authoritatively) by plugins/soleur/test/lib/discoverability-test-parser.ts.
# If the two drift, THIS FILE WINS and the mirror is the bug.
#
# Scalar shapes for `command:`:
#   inline   `command: curl …`
#   block    `command: |`  `|-`  `|+`   → continuations joined with NEWLINE
#   folded   `command: >`  `>-`  `>+`   → continuations joined with SPACE
#
# Scalar extent follows YAML: a continuation is any non-empty line indented MORE than the
# `command:` key; the first line indented <= the key ends the scalar. No key-name matching
# is used INSIDE a scalar — a key regex both truncates legitimate content (a jq object
# filter's `host_present:`) and leaves a differential where a LESS-indented non-key line is
# still consumed, which a PR reviewer reads as outside the command but the shell executes.
#
# The `!mode` guard on the three `command:` rules below is what makes that claim true. The
# header and inline rules match on a KEY NAME, so without the guard they re-fire on a
# continuation line that happens to begin `command:` — the inline rule then truncates the
# scalar at that line AND concatenates its value onto the accumulated fold (no separator,
# because `printf` had not yet emitted a newline). Verified: a fold whose continuation is
# `    command: bar` yielded `…/apibar` instead of `…/api command: bar`, and production
# would have silently executed the corrupted string.
#
# Chomping indicators (-/+) are accepted but not modelled: the value goes to `bash -c` and
# $(…) strips trailing newlines regardless.
#
# CAVEAT (folded + trailing backslash): folding joins with a space, so a continuation
# ending in `\` yields `\ ` — an escaped space, not a line continuation. YAML folding
# consumes the backslash as ordinary text too, so this is spec-correct, but the executed
# command differs from the one a reviewer reads. Prefer block (`|`) for commands using
# trailing-backslash continuations.

function indent(s,   t) { t = s; sub(/[^[:space:]].*$/, "", t); return length(t) }

# Folded/block headers. MUST precede the inline rule: `/^[[:space:]]*command:/` also
# matches `command: >-` and would print the literal indicator, which then self-rejects
# against Step 10.5's shell-active `>` branch (#6772). The `(#.*)?$` tail is load-bearing —
# anchoring to a bare `$` makes `command: >- # note` fall through to inline and reproduce
# #6772 exactly.
!mode && /^[[:space:]]*command:[[:space:]]*>[-+]?[[:space:]]*(#.*)?$/  { mode = "fold";  key = indent($0); next }
!mode && /^[[:space:]]*command:[[:space:]]*\|[-+]?[[:space:]]*(#.*)?$/ { mode = "block"; key = indent($0); next }

# Inline. `!mode` keeps this OUTSIDE a scalar only — see the header note.
!mode && /^[[:space:]]*command:/ { sub(/^[[:space:]]*command:[[:space:]]*/, ""); print; exit }

# Blank lines are legal inside a scalar and carry no indentation — skip before the
# terminator, or indent()==0 would end every scalar at the first blank line.
mode && /^[[:space:]]*$/ { next }

# Scalar ends at the first line indented <= the opening key. Covers sibling keys, parent
# keys, the closing ``` of the YAML fence, and column-0 prose in one rule.
mode && indent($0) <= key { exit }

# Continuations (reached only when indent > key).
mode == "fold"  { sub(/^[[:space:]]+/, ""); printf "%s%s", (n++ ? " " : ""), $0; next }
mode == "block" { sub(/^[[:space:]]+/, ""); print; next }

END { if (mode == "fold" && n) printf "\n" }
