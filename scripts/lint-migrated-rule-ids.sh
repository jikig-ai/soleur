#!/usr/bin/env bash
# Guard: every rule migrated out of AGENTS.rules.md lives where its registry row says, and its
# body is the body that was reviewed (#8030, PR #8175).
#
# A migrated rule is in neither of the corpus's two older states — it has no body in
# AGENTS.rules.md and it is not retired — so the checks that key on AGENTS.rules.md cannot see
# it. This file checks the two properties nothing else does:
#
#   1. PLACEMENT. Each row of scripts/migrated-rule-ids.txt names `<path> :: <heading>`. The
#      heading must occur exactly once (whole-line equality, no regex), and the section it opens —
#      up to the next heading of equal or higher level, fences respected — must contain the
#      migration banner followed, inside the same blockquote, by the `[id: <id>] [` body line.
#      Tranche 1 (PR #8034) shipped a callout outside its section with every gate green.
#   2. BODY INTEGRITY. Each row carries a 5th field: the sha256 of the body (blockquote markers
#      stripped, ASCII whitespace runs collapsed to one space, ends trimmed — the same result as
#      `_normalize` in scripts/lint-rule-bodies.py; keep the two in step). This file proves the
#      row matches the home NOW. It cannot prove the row did not move WITH a weakening — a commit
#      can edit the body and re-hash the row together. That half is `rule-body-lint --check`,
#      which diffs the row against the merge-base and requires a NEW ack for any change, a
#      verbatim move for any new row, and an ack for any removed row.
#   3. UNIQUENESS AND IDENTITY. One row per id; one banner per id in the whole scanned tree; the
#      `[id: <id>]` tag once in its home (a second copy of a body is outside the hash); body text
#      free of non-ASCII whitespace (the two normalisers disagree on it); and the registry's id
#      set equals the `NOT a retirement of the RULE` rows of scripts/retired-rule-ids.txt, so a
#      row cannot be dropped, or swapped for an id that never migrated, while the count holds.
#
# And in reverse: every migration banner in the tree names an id with a row (else its
# SOLEUR_RULE_APPLIED telemetry is dropped by the hook with no sentinel), sits under
# plugins/soleur/, and any line that LOOKS like a banner but is not canonical is a finding.
#
# Not checked here, deliberately: "absent from AGENTS.rules.md" — scripts/lint-rule-ids.py fails
# it at the same pre-commit hook.
#
# NOT COVERED, by construction: any text that is not the body line(s). That is (a) text adjacent
# to a callout but outside its blockquote (an "Exception:" paragraph after a blank line), and (b)
# the callout's own preamble — the banner and the domain-scope sentence between the banner and
# the `[id:` line, which sit INSIDE the blockquote but are not the rule and are not hashed, so a
# qualifying sentence inserted there is also invisible. Hashing them would break the verbatim-move
# check (the row hash equals the corpus body's hash); a reviewer of the home file is the control,
# as it is for the prose around a rule in AGENTS.rules.md.
#
# Root and floor follow the sibling lints: LINT_MIGRATED_RULE_IDS_ROOT (fixture root, floor 1),
# otherwise the script's own location (never `git rev-parse`: GIT_DIR is exported under lefthook
# in a linked worktree, #7833). There is no flag that weakens the corpus run. Positional args
# (lefthook passes staged filenames) are ignored, except `--print-hash <id>`, which prints the
# body hash for a registered id so a row can be written without re-deriving the normalisation.
#
# The reverse scan reads every *.md under the root except .git, node_modules, .worktrees and
# knowledge-base/project/ (plans and specs quote banners as examples and are never loaded as
# instructions). A banner found outside plugins/soleur/ is a finding, which is what makes the
# row-path rule and the scan agree.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIN_ROWS=7 # measured 2026-09-14, #8175. A FLOOR: raise it when a tranche adds rows.
if [[ -n "${LINT_MIGRATED_RULE_IDS_ROOT:-}" ]]; then
  ROOT="$LINT_MIGRATED_RULE_IDS_ROOT"
  FLOOR=1
else
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  FLOOR="$MIN_ROWS"
fi

REG="$ROOT/scripts/migrated-rule-ids.txt"
REG_REL="scripts/migrated-rule-ids.txt"
CANON=' — migrated out of `AGENTS.rules.md` on'
LOOSE_RE='migrated out of .?AGENTS\.rules\.md'
RETIRED="$ROOT/scripts/retired-rule-ids.txt"
MIGRATION_MARK='NOT a retirement of the RULE'

FINDINGS=()
finding() { FINDINGS+=("$1"); }

# Strict row grammar: id | date | #PR | path :: heading | sha256
ROW_RE='^([a-z0-9][a-z0-9-]{2,79})[[:space:]]*\|[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]*\|[[:space:]]*(#[0-9]+)[[:space:]]*\|[[:space:]]*(.+ :: #{1,6} .+)\|[[:space:]]*([0-9a-f]{64})[[:space:]]*$'

hash_text() {
  printf '%s' "$1" | LC_ALL=C tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' | sha256sum | cut -c1-64
}

# locate_body <id> <path> <heading>  -> sets LOC_ERR (empty on success), BODY
# Pure placement logic shared by the lint and --print-hash.
locate_body() {
  local id="$1" rel="$2" heading="$3"
  LOC_ERR=""
  BODY=""

  if [[ "$rel" == /* || "/$rel/" == */../* ]]; then
    LOC_ERR="path escapes root: $rel"; return
  fi
  if [[ "$rel" != plugins/soleur/* ]]; then
    LOC_ERR="home outside plugins/soleur/: $rel"; return
  fi
  local abs="$ROOT/$rel"
  if [[ -L "$abs" ]]; then
    LOC_ERR="symlink home refused: $rel"; return
  fi
  local root_real abs_real
  root_real="$(realpath -m -- "$ROOT")"
  abs_real="$(realpath -m -- "$abs")"
  if [[ "$abs_real" != "$root_real"/* ]]; then
    LOC_ERR="path escapes root: $rel"; return
  fi
  if [[ ! -f "$abs" ]]; then
    LOC_ERR="home file not found: $rel"; return
  fi

  local count
  count="$(grep -cFx -- "$heading" "$abs" || true)"
  if [[ "$count" == "0" ]]; then
    LOC_ERR="heading not found: '$heading' in $rel"; return
  fi
  if [[ "$count" != "1" ]]; then
    LOC_ERR="ambiguous heading: '$heading' occurs $count times in $rel"; return
  fi
  local hl level
  hl="$(grep -nFx -- "$heading" "$abs" | cut -d: -f1)"
  level="${heading%%[!#]*}"
  level="${#level}"

  # End of section: first heading of level <= $level after $hl, fences respected
  # (CommonMark: a fence opens on ``` or ~~~ at <=3 spaces of indent and closes only on the same
  # character at >= the opening length; 4+-space-indented lines are content).
  local end
  end="$(awk -v start="$hl" -v lvl="$level" '
    function lead(s,   n) { n = 0; while (n < 4 && substr(s, n + 1, 1) == " ") n++; return n }
    NR <= start { next }
    {
      ind = lead($0)
      if (ind > 3) { next }
      s = substr($0, ind + 1)
      c = substr(s, 1, 1)
      if (infence) {
        if (c == fch) {
          n = 0; while (substr(s, n + 1, 1) == c) n++
          rest = substr(s, n + 1); gsub(/[ \t]/, "", rest)
          if (n >= flen && rest == "") infence = 0
        }
        next
      }
      if (c == "`" || c == "~") {
        n = 0; while (substr(s, n + 1, 1) == c) n++
        if (n >= 3 && !(c == "`" && index(substr(s, n + 1), "`"))) { infence = 1; fch = c; flen = n; next }
      }
      if (c == "#") {
        n = 0; while (substr(s, n + 1, 1) == "#") n++
        nxt = substr(s, n + 1, 1)
        if (n <= 6 && (nxt == " " || nxt == "\t" || nxt == "") && n <= lvl) { print NR; found = 1; exit }
      }
    }
    END { if (!found) print NR + 1 }
  ' "$abs")"

  local needle="> **Rule \`${id}\`${CANON}"
  local hits b in_section="" nhits
  hits="$(grep -nF -- "$needle" "$abs" | cut -d: -f1 || true)"
  if [[ -z "$hits" ]]; then
    LOC_ERR="migration banner not found for $id in $rel"; return
  fi
  nhits="$(printf '%s\n' "$hits" | wc -l)"
  if (( nhits > 1 )); then
    LOC_ERR="migration banner for $id occurs $nhits times in $rel (lines $(printf '%s' "$hits" | tr '\n' ' ')) — only the first body is hashed"; return
  fi
  for b in $hits; do
    if (( b > hl && b < end )); then
      [[ -z "$in_section" ]] && in_section="$b"
    else
      LOC_ERR="banner for $id is not inside section '$heading' ($rel:$b)"
    fi
  done
  if [[ -n "$LOC_ERR" ]]; then return; fi

  # Body: the first line within the next 8 lines of the SAME blockquote run carrying
  # `[id: <id>] [`, through the end of that blockquote run.
  BODY="$(awk -v b="$in_section" -v tok="[id: ${id}] [" '
    NR <= b { next }
    {
      isq = ($0 ~ /^ ? ? ?>/)
      if (!started) {
        if (!isq || NR > b + 8) { exit }
        if (index($0, tok)) { started = 1 } else { next }
      } else if (!isq) { exit }
      line = $0; sub(/^ ? ? ?> ?/, "", line)
      out = out line "\n"
    }
    END { printf "%s", out }
  ' "$abs")"
  if [[ -z "$BODY" ]]; then
    LOC_ERR="body line missing after banner: no [id: $id] [ line in the blockquote following $rel:$in_section"; return
  fi
  local tags
  tags="$(grep -cF -- "[id: ${id}]" "$abs" || true)"
  if [[ "$tags" != "1" ]]; then
    LOC_ERR="[id: $id] occurs $tags times in $rel — a second copy of the body sits outside the hash"; return
  fi
  # Non-ASCII whitespace (NBSP, U+2000-200A, U+2028/9, U+202F, U+205F, U+3000, U+0085, U+1680)
  # and the ASCII separators U+001C-001F: Python's str.split() collapses them, `tr` in the C
  # locale does not, so a body carrying one hashes differently in the two gates.
  if printf '%s' "$BODY" | LC_ALL=C grep -qE $'\xc2[\x85\xa0]|\xe1\x9a\x80|\xe2\x80[\x80-\x8a\xa8\xa9\xaf]|\xe2\x81\x9f|\xe3\x80\x80|[\x1c-\x1f]'; then
    LOC_ERR="non-ASCII whitespace in the body of $id at $rel — replace it with a plain space"
  fi
}

# --- --print-hash <id> --------------------------------------------------------------------
if [[ "${1:-}" == "--print-hash" ]]; then
  pid="${2:-}"
  if [[ -z "$pid" || ! -f "$REG" ]]; then
    printf 'lint-migrated-rule-ids: --print-hash needs an id and a readable %s\n' "$REG_REL" >&2
    exit 2
  fi
  row="$(grep -E "^${pid}[[:space:]]*\|" "$REG" | head -n 1 || true)"
  if [[ -z "$row" ]]; then
    printf 'lint-migrated-rule-ids: no row for %s\n' "$pid" >&2
    exit 1
  fi
  IFS='|' read -r _ _ _ loc _ <<<"$row"
  loc="$(printf '%s' "$loc" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  locate_body "$pid" "${loc%% :: *}" "${loc#* :: }"
  if [[ -n "$LOC_ERR" ]]; then
    printf 'lint-migrated-rule-ids: %s\n' "$LOC_ERR" >&2
    exit 1
  fi
  hash_text "$BODY"
  printf '\n'
  exit 0
fi

# --- forward: every row -------------------------------------------------------------------
rows=0
matched=0
declare -A REGISTERED=()
if [[ ! -f "$REG" ]]; then
  finding "registry not found: $REG_REL"
else
  lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    if [[ ! "$line" =~ $ROW_RE ]]; then
      finding "malformed row at $REG_REL line $lineno (want: id | YYYY-MM-DD | #PR | path :: heading | sha256): $(printf '%s' "$line" | cut -c1-120)"
      continue
    fi
    id="${BASH_REMATCH[1]}"
    if [[ -n "${REGISTERED[$id]:-}" ]]; then
      finding "duplicate row for $id at $REG_REL line $lineno — one id, one home"
      continue
    fi
    loc="$(printf '%s' "${BASH_REMATCH[4]}" | sed -e 's/[[:space:]]*$//')"
    want="${BASH_REMATCH[5]}"
    rows=$((rows + 1))
    REGISTERED["$id"]=1
    locate_body "$id" "${loc%% :: *}" "${loc#* :: }"
    if [[ -n "$LOC_ERR" ]]; then
      finding "$id: $LOC_ERR"
      continue
    fi
    got="$(hash_text "$BODY")"
    if [[ "$got" != "$want" ]]; then
      finding "$id: body hash mismatch at ${loc%% :: *} (row $want, body $got) — a body edit at the home must update the row hash in the same diff"
      continue
    fi
    matched=$((matched + 1))
  done <"$REG"
fi

if (( rows < FLOOR )); then
  finding "$rows rows checked < floor $FLOOR — a row was dropped, or raise MIN_ROWS only when a tranche adds rows"
fi

# --- identity: the registry equals the migration rows of retired-rule-ids.txt ----------------
declare -A MIGRATED_RETIRED=()
if [[ ! -f "$RETIRED" ]]; then
  finding "retired registry not found: scripts/retired-rule-ids.txt"
else
  while IFS= read -r line; do
    [[ "$line" == *"$MIGRATION_MARK"* ]] || continue
    [[ "$line" =~ ^([a-z0-9][a-z0-9-]{2,79})[[:space:]]*\| ]] || continue
    MIGRATED_RETIRED["${BASH_REMATCH[1]}"]=1
  done <"$RETIRED"
  for rid in "${!MIGRATED_RETIRED[@]}"; do
    [[ -n "${REGISTERED[$rid]:-}" ]] || finding "$rid has a '$MIGRATION_MARK' row in scripts/retired-rule-ids.txt but no row in $REG_REL"
  done
  for rid in "${!REGISTERED[@]}"; do
    [[ -n "${MIGRATED_RETIRED[$rid]:-}" ]] || finding "$rid has a row in $REG_REL but no '$MIGRATION_MARK' row in scripts/retired-rule-ids.txt"
  done
fi

# --- reverse: every banner in the tree ----------------------------------------------------------
scan_md() {
  grep -rn "$1" --include='*.md' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.worktrees \
    -- "$2" "$ROOT" 2>/dev/null || true
}
# `path:line:text` -> HIT_FILE (root-relative), HIT_LINE, HIT_TEXT; returns 1 for excluded paths.
split_hit() {
  HIT_FILE="${1%%:*}"
  local rest="${1#*:}"
  HIT_LINE="${rest%%:*}"
  HIT_TEXT="${rest#*:}"
  HIT_FILE="${HIT_FILE#"$ROOT"/}"
  [[ "$HIT_FILE" != knowledge-base/project/* ]]
}

declare -A BANNER_AT=()
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  split_hit "$hit" || continue
  bid="$(printf '%s' "$HIT_TEXT" | sed -n 's/^ \{0,3\}> \*\*Rule `\([a-z0-9][a-z0-9-]*\)` — migrated out of `AGENTS\.rules\.md` on.*/\1/p')"
  [[ -z "$bid" ]] && continue
  if [[ "$HIT_FILE" != plugins/soleur/* ]]; then
    finding "migration banner for $bid outside plugins/soleur/ ($HIT_FILE:$HIT_LINE) — a home must be under plugins/soleur/"
  fi
  if [[ -n "${BANNER_AT[$bid]:-}" ]]; then
    finding "second migration banner for $bid ($HIT_FILE:$HIT_LINE; first at ${BANNER_AT[$bid]}) — only one copy is hashed"
  else
    BANNER_AT["$bid"]="$HIT_FILE:$HIT_LINE"
  fi
  if [[ -z "${REGISTERED[$bid]:-}" ]]; then
    finding "no registry row for migrated banner $bid ($HIT_FILE:$HIT_LINE) — its SOLEUR_RULE_APPLIED telemetry is dropped"
  fi
done < <(scan_md -F "$CANON")

# A banner carrying a real id but not written as a top-level blockquote line (no `> `, or a
# nested `> > `) is invisible to the extraction above, so it would satisfy nothing and be
# reported by nothing. A `<id>` placeholder in prose is not an id and does not match.
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  split_hit "$hit" || continue
  printf '%s' "$HIT_TEXT" | grep -qE '^ {0,3}> \*\*Rule `[a-z0-9][a-z0-9-]*` — migrated out of' && continue
  lid="$(printf '%s' "$HIT_TEXT" | sed -n 's/.*\*\*Rule `\([a-z0-9][a-z0-9-]*\)` — migrated out of `AGENTS\.rules\.md` on.*/\1/p')"
  [[ -z "$lid" ]] && continue
  finding "migration banner for $lid at $HIT_FILE:$HIT_LINE is not a top-level blockquote line (\`> **Rule\`) — no check can read it"
done < <(scan_md -F "$CANON")

while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  split_hit "$hit" || continue
  if [[ "$HIT_TEXT" != *"$CANON"* ]]; then
    finding "non-canonical migration banner at $HIT_FILE:$HIT_LINE: $(printf '%s' "$HIT_TEXT" | cut -c1-120)"
  fi
done < <(scan_md -iE "$LOOSE_RE")

if (( ${#FINDINGS[@]} > 0 )); then
  printf 'lint-migrated-rule-ids: %s problem(s)\n' "${#FINDINGS[@]}" >&2
  for f in "${FINDINGS[@]}"; do printf '  - %s\n' "$f" >&2; done
  exit 1
fi
printf 'lint-migrated-rule-ids: OK (%s rows checked, %s banners matched)\n' "$rows" "$matched"
