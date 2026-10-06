#!/usr/bin/env bash
# kb-search-support-path.test.sh — Guard 2 for #9559 (support-persona tool path).
#
# Pins the contract between `plugins/soleur/skills/kb-search/SKILL.md` and the
# committed support corpus it reads. The support persona (Soleur Support) has
# `kb-search` as its ONLY loaded skill and every non-safe-bash Bash call on the
# support surface is denied AND records a support escalation that renders a
# false "Ask an agent" handoff — so the skill must document a Read/Grep/Glob
# execution path, and the corpus that path reads must exist committed.
#
# Asserts:
#   (i)   the literal marker `Support-persona path (no Bash)` is present in
#         SKILL.md — that string is the REQUIRED marker; the plan names it and
#         this header names it, so a diff weakening both sides is bounded;
#   (ii)  the support section (marker line → next `##`/`###` heading) contains
#         NO fenced ```bash block. The section legitimately names Bash in prose
#         ("do NOT execute any of the ` ```bash ` blocks below"), so the anchor
#         is the fenced-block form only, never the bare word;
#   (iii) `plugins/soleur/knowledge-base/{INDEX.md,kb-tags.txt,
#         kb-categories.txt}` exist non-empty (the corpus the tool path reads).
#
# Auto-discovered by scripts/test-all.sh via `plugins/soleur/test/*.test.sh`.
# Pair with kb-search-lockstep.test.sh (byte-equality on the
# stage-2-paraphrase-union-v1 marker + SENSITIVE_QUERY_REGEX — must stay green
# through the SKILL.md edit).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Byte-copy of the canonical assert_fixture_dir (test-helpers.sh). The mktemp
# window below opens BEFORE the source line that defines the helper, so the
# copy must live here. fixture-dir-operand-assert.test.sh asserts every inline
# copy stays byte-equal to the canonical body — do not reword. #7652
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# This script's owning EXIT trap goes BEFORE the source of test-helpers.sh:
# the helper composes a prior EXIT trap with its incident-sandbox cleanup,
# while a trap installed after the source would REPLACE that cleanup and leak
# the sandbox (ADR-129 rule (c); same shape as vendor-bundle-coverage.test.sh).
WORK="$(mktemp -d -t kbsupport.XXXXXXXX)" || { printf 'FATAL: mktemp failed\n' >&2; exit 2; }
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT

source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL="$REPO_ROOT/plugins/soleur/skills/kb-search/SKILL.md"
KB_DIR="$REPO_ROOT/plugins/soleur/knowledge-base"
MARKER="Support-persona path (no Bash)"

# Extracts the support-persona section: from the line containing the literal
# marker to the line BEFORE the next `##`/`###` heading. `index()` is a
# fixed-string match — the marker's parens are data, not regex. The
# `!index($0, m)` guard keeps the range open even if a heading ever carries
# the marker text.
# The marker must LEAD the line (index==1 on the bolded form): an earlier
# TOC entry or cross-reference quoting the marker (e.g. a `- [` link) must
# not open a wrong window and leave the real section unscanned.
support_section() { # $1 = file → prints the section body
  awk -v m="$MARKER" -v ml="**$MARKER" '
    index($0, ml) == 1                        { in_sec = 1 }
    in_sec && /^#{2,3}[[:space:]]/ && !index($0, m) { exit }
    in_sec                                    { print }
  ' "$1"
}

# Any fenced block, not the word "bash": the support section is prose+table
# and legitimately contains ZERO fences, so "no fence at all" is the honest
# property — it subsumes every info-string variant (```bash, ```Bash,
# ```text hiding shell, bare ```, ~~~sh, 4+-char fences) without a language
# allowlist to maintain. Prefix classes cover indentation, blockquote
# (`> `), and list markers (`- `, `* `, `1. `). Owned boundaries: a
# `##`/`###` heading inside the section truncates the window (awk range
# above), HTML <pre>/<code> blocks are not fences, and indirection into a
# second file is outside a text guard's reach — the marker-anchored window
# plus the deny+escalate tripwire on Bash itself are the layered contract.
SHELL_FENCE_RE='^[[:space:]>*-]*([0-9]+[.)][[:space:]]*)?(`{3,}|~{3,})'

echo "=== kb-search support-persona path drift guard (#9559) ==="
echo ""

assert_file_exists "$SKILL" "kb-search SKILL.md exists"

# Bail before the extraction rows if the file under test is missing — every
# assertion below would otherwise run on an unreadable input.
if [[ "$FAIL" -gt 0 ]]; then
  print_results
fi

# --- (i) the marker exists ---------------------------------------------------
if grep -qF "$MARKER" "$SKILL"; then
  echo "  PASS: SKILL.md carries the literal marker '$MARKER'"
  PASS=$((PASS + 1))
else
  echo "  FAIL: marker '$MARKER' absent from SKILL.md — the support-persona path section is missing"
  FAIL=$((FAIL + 1))
fi

SECTION="$(support_section "$SKILL")"

# Guard-own-dispatch: an empty extraction would make the no-fence assertion
# below vacuous, so the section must be non-empty before the negative counts.
if [[ -n "$SECTION" ]]; then
  echo "  PASS: support section extracts non-empty (marker line → next ##/### heading)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: support-section extraction returned empty — the no-shell-fence row would be vacuous"
  FAIL=$((FAIL + 1))
fi

# --- (ii) no fenced shell block inside the section ---------------------------
if grep -qiE "$SHELL_FENCE_RE" <<<"$SECTION"; then
  echo "  FAIL: a fenced shell block sits inside the support-persona section:"
  grep -niE "$SHELL_FENCE_RE" <<<"$SECTION" | sed 's/^/        /' >&2 || true
  FAIL=$((FAIL + 1))
else
  echo "  PASS: no fenced code block of any kind inside the support section"
  PASS=$((PASS + 1))
fi

# Positive control on the SAME input: append a fenced bash block to the real
# extracted section and require the detector to fire. Without this, a neutered
# regex would report the negative row green while detecting nothing.
CONTROL="$(printf '%s\n```bash\ngit grep -ilE needle\n```\n' "$SECTION")"
if grep -qiE "$SHELL_FENCE_RE" <<<"$CONTROL"; then
  echo "  PASS: control — the fence detector flags a bash block on the same input"
  PASS=$((PASS + 1))
else
  echo "  FAIL: control — the fence detector MISSED a bash block appended to the extracted section"
  FAIL=$((FAIL + 1))
fi

# Second control on the SAME input: a widened-form fence (tilde fence,
# capitalized info string, list-marker prefix) must also fire — regression
# pin for the fence-shape coverage the first control can't reach.
CONTROL2="$(printf '%s\n- ~~~Bash\ngit grep -ilE needle\n~~~\n' "$SECTION")"
if grep -qiE "$SHELL_FENCE_RE" <<<"$CONTROL2"; then
  echo "  PASS: control — the fence detector flags a widened-form shell fence"
  PASS=$((PASS + 1))
else
  echo "  FAIL: control — the fence detector MISSED a tilde/case/list-marker shell fence"
  FAIL=$((FAIL + 1))
fi

# End-to-end control: run the SAME extractor + detector over a synthetic SKILL
# carrying marker + fenced block inside the section window.
FIX_FENCED="$WORK/skill-with-fence.md"
cat > "$FIX_FENCED" <<'FIXEOF'
## Execution

**Support-persona path (no Bash).** Synthetic prose naming Bash is legal.

```bash
git grep -ilE needle
```

| Phase | Tool-path equivalent |
|---|---|

### Phase 0: Parse Arguments
FIXEOF
FIX_SECTION="$(support_section "$FIX_FENCED")"
if grep -qiE "$SHELL_FENCE_RE" <<<"$FIX_SECTION"; then
  echo "  PASS: control — extractor + detector flag a fenced block inside a synthetic section"
  PASS=$((PASS + 1))
else
  echo "  FAIL: control — the extractor/detector pipeline missed a fenced block in a synthetic section"
  FAIL=$((FAIL + 1))
fi

# Extractor anchoring control: a file with NO marker must extract empty —
# otherwise the window is not marker-anchored and a marker deletion could
# leave a stale "section" scanning the whole file (or the wrong one).
FIX_NOMARKER="$WORK/skill-no-marker.md"
printf '## Execution\n\nSome prose.\n\n### Phase 0: Parse Arguments\n' > "$FIX_NOMARKER"
if [[ -z "$(support_section "$FIX_NOMARKER")" ]]; then
  echo "  PASS: control — extractor is marker-anchored (no marker → empty section)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: control — extractor produced output for a file with no marker"
  FAIL=$((FAIL + 1))
fi

# --- (iii) the committed corpus exists non-empty ------------------------------
for f in INDEX.md kb-tags.txt kb-categories.txt; do
  if [[ -s "$KB_DIR/$f" ]]; then
    echo "  PASS: corpus file plugins/soleur/knowledge-base/$f exists non-empty"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: corpus file plugins/soleur/knowledge-base/$f missing or empty — the tool path has nothing to read"
    FAIL=$((FAIL + 1))
  fi
done

# The section's Phase-2 tool path Globs knowledge-base/project/learnings/*.md —
# an empty or missing learnings dir leaves that path dead with every file
# check above still green.
shopt -s nullglob
learnings=( "$KB_DIR"/project/learnings/*.md )
shopt -u nullglob
if (( ${#learnings[@]} >= 1 )); then
  echo "  PASS: corpus holds ${#learnings[@]} learning(s) under knowledge-base/project/learnings/"
  PASS=$((PASS + 1))
else
  echo "  FAIL: no learnings under plugins/soleur/knowledge-base/project/learnings/ — Phase 2/3 tool path reads nothing"
  FAIL=$((FAIL + 1))
fi

# kb-tags.txt freshness: every tag used in corpus frontmatter must appear in
# the artifact — a stale kb-tags.txt makes `kb-search --tag <real>` emit
# "No matches" on the support path (ship-advisor finding, PR #9570). INDEX.md
# is hand-curated (not generator output) so it is NOT freshness-checked here.
if (( ${#learnings[@]} >= 1 )); then
  STALE_TAGS=$(grep -h '^tags:' "${learnings[@]}" 2>/dev/null \
    | sed 's/^tags:[[:space:]]*//; s/[][]//g' | tr ',' '\n' | tr -d ' ' \
    | sort -u | grep -vFxf "$KB_DIR/kb-tags.txt" || true)
else
  # empty corpus already failed above; an unset grep would read stdin and hang
  STALE_TAGS=""
fi
if [[ -z "$STALE_TAGS" ]]; then
  echo "  PASS: kb-tags.txt covers every tag used in corpus frontmatter"
  PASS=$((PASS + 1))
else
  echo "  FAIL: kb-tags.txt is stale — tags used in corpus frontmatter but absent: $(echo "$STALE_TAGS" | tr '\n' ' ')"
  FAIL=$((FAIL + 1))
fi

# Floor = the green-run assertion count (13): exists + marker + non-empty
# section + no-fence + 4 controls + 3 corpus files + learnings + tag
# freshness. Re-derive from a green run rather than lowering by feel.
print_results 13
