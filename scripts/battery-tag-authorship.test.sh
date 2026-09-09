#!/usr/bin/env bash
# battery-tag-authorship — every tag-authoring git command reachable from the battery either
# suppresses tag creation on its own command line, or declares itself.
#
# WHY THIS EXISTS (#7917). `scripts/lib/repo-write-boundary.sh` softens a collision-free
# `refs/tags/*` CREATION to REPORT when sibling worktrees share the ref store (ADR-207,
# exemption cell 6). That softening is correct — a sibling's fetch auto-follows tags and there
# is no attributable author — but it is safe only while the battery is not itself a tag author,
# and under `shared_store` the classifier CANNOT distinguish a suite-authored tag from a fetched
# one, by construction (ADR-207 §2's anti-laundering invariant refuses to re-derive attribution
# after the measurement window closes). So every in-battery tag author is a real false negative
# on the operator's machine — the only place the softening applies.
#
# THE PROPERTY IS DECLARATION-BASED, AND THAT IS THE LOAD-BEARING DESIGN DECISION.
# "No battery git command writes a tag into the LIVE repo" is not statically decidable: the
# working directory is set by callers frames away, and `git -C "$x"` with `$x` empty is a
# documented NO-OP that runs in the caller's cwd (measured on git 2.53.0). Two prior static
# adjudications of this same question reached OPPOSITE answers, which is the evidence that the
# undecidable form is the wrong question. This guard therefore asserts a decidable property:
#
#   every tag-authoring command in the closure either suppresses tags ON ITS OWN COMMAND LINE,
#   or carries a `repo-boundary-tag-exempt:` marker within the two preceding lines AND a
#   matching entry in this file's exemption ledger.
#
# VERB SET, and why it is not "git fetch". ADR-207 cell 6 softens a tag CREATED BY ANYTHING, so
# a fetch-scoped guard would be literally true about fetches while green over every other route
# a tag reaches the ref store. In class: `git fetch`, `git pull`, `git remote update`,
# `git tag` in its creating forms, `git update-ref refs/tags/…`.
# Out of class, each for a stated reason rather than by omission:
#   git push … refs/tags/…  writes the REMOTE, never the local ref store
#   git clone               creates refs in the NEW repo, which by construction is not the live one
#   git tag -d / --list/-l  delete or read; create nothing
#   git ls-remote           reads the remote; writes no ref
#   git checkout/switch/worktree add   move HEAD, never write refs/tags/*
#   git replace/notes/bundle unbundle  write refs/replace|notes|bundle — other namespaces
#   git fetch --prune       (without --prune-tags) prunes remote-tracking refs only
#
# PER-VERB REACHABLE VERDICTS. `--no-tags` is accepted by `git fetch` and `git pull` only.
# Measured: `git remote update --no-tags` → "error: unknown option 'no-tags'"; its tag-following
# is governed by `remote.<name>.tagOpt` in config, never on the command line. So for
# `git remote update`, `git tag` creations and `git update-ref`, the SUPPRESSED arm is
# unsatisfiable BY CONSTRUCTION and the only reachable verdicts are EXEMPT or OFFENDER. That is
# stated here rather than leaving a reader to discover an arm that can never fire.
#
# DECLARED APPROXIMATIONS (AC33). This guard over-approximates; every approximation below fails
# toward a FALSE OFFENDER, which reddens and is closed by a declaration — never toward a false
# green:
#   1. Comment exclusion drops FULL-LINE comments only. A trailing comment after code is not
#      excluded.
#   2. Heredoc exclusion is best-effort. Reliably excluding a heredoc body needs a real shell
#      parser; no grep-shaped rule is correct in general.
#   3. The closure is over TRACKED files only, and any tracked executable path literal appearing
#      in a closure member joins the closure. An unresolvable reference JOINS the closure rather
#      than leaving it.
#   4. `bun test <dir>/` is expanded by a glob over the directory, which approximates what bun
#      itself would collect.
#
# ENVIRONMENT DELTA, measured 2026-09-09, so a reader comparing a local census against a CI one
# does not misread it as drift. Under CI the relevance gate's bypass is an unconditional early
# return, so a decline is unreachable and `skip_suite` is never invoked — those registrations
# arrive as real commands instead. Measured: roots 452 (local) vs 455 (CI=1), and unclassified
# 1 vs 2 (the second inline `bash -c` registration is a decline locally). The CLASSIFICATION is
# environment-independent — occurrences=49 and offenders=39 in both — because the extra roots
# carry no tag-authoring command. MIN_ROOTS is set below the lower of the two.
#
# SEAM. BATTERY_TAG_REPO_ROOT / BATTERY_TAG_RUNNER let the mutation battery point this exact
# program at a sandbox copy. The seam lives HERE, in the guard, so the program that produces the
# RED transcript is the same program the battery grades.

set -uo pipefail

REPO_ROOT="${BATTERY_TAG_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
case "$REPO_ROOT" in
  /*) : ;;
  *) printf 'ERROR: REPO_ROOT is not absolute (%s) — refusing to run with a degenerate root\n' "$REPO_ROOT" >&2; exit 2 ;;
esac
readonly REPO_ROOT
RUNNER="${BATTERY_TAG_RUNNER:-$REPO_ROOT/scripts/test-all.sh}"
readonly RUNNER

# One binding per line, no `;`. guard-vacuity-floor.test.sh carries the floor block plus its
# threshold BINDINGS into a mutant, and its binding extractor is anchored
# `^[[:space:]]*VAR=[^;]*$` — a semicolon-joined line is rejected, `asserted` arrives
# unbound, and the mutant dies as a CONSTRUCTION FAILURE rather than being scored. That
# reports as an uncovered floor, which is the opposite of what this floor is for.
passes=0
fails=0
asserted=0
ck() { asserted=$((asserted + 1)); }
pass() { passes=$((passes + 1)); printf '  [ok] %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  [FAIL] %s\n' "$1" >&2; }

# --- helper self-test (Stage D) -------------------------------------------------------------
# Runs BEFORE any case, drives each helper once, asserts each moved its OWN counter, and reports
# through NEITHER helper. A suite whose pass()/fail()/ck() have been neutered otherwise reports
# a clean run having asserted nothing.
_st_p=$passes; _st_f=$fails; _st_a=$asserted
{ pass "self-test"; fail "self-test"; ck; } >/dev/null 2>&1
if (( passes != _st_p + 1 || fails != _st_f + 1 || asserted != _st_a + 1 )); then
  printf '\n[FATAL] helper self-test: pass()/fail()/ck() did not each move their OWN counter\n' >&2
  printf '        passes %d->%d  fails %d->%d  asserted %d->%d\n' \
    "$_st_p" "$passes" "$_st_f" "$fails" "$_st_a" "$asserted" >&2
  exit 1
fi
passes=$_st_p; fails=$_st_f; asserted=$_st_a

# --- exclusions (two arrays, separately size-asserted) --------------------------------------
SELF_EXCLUSION=("scripts/battery-tag-authorship.test.sh")
FIXTURE_EXCLUSION=("scripts/battery-tag-authorship-mutations.test.sh")
(( ${#SELF_EXCLUSION[@]} == 1 )) || { printf 'ERROR: SELF_EXCLUSION must hold exactly 1 entry\n' >&2; exit 2; }
(( ${#FIXTURE_EXCLUSION[@]} == 1 )) || { printf 'ERROR: FIXTURE_EXCLUSION must hold exactly 1 entry\n' >&2; exit 2; }

_excluded() {
  local p="$1" e
  for e in "${SELF_EXCLUSION[@]}" "${FIXTURE_EXCLUSION[@]}"; do
    [[ "$p" == "$e" ]] && return 0
  done
  return 1
}

# --- exemption ledger (Stage C.2) -----------------------------------------------------------
# KEY: "<repo-relative path>|<exempted command text, whitespace-collapsed>".
# Line numbers drift, so the key is the command text; path granularity alone would let a
# copy-pasted marker on a NEW command in an already-exempt file be silently absorbed.
# Each entry MUST cite an OPEN tracking issue or a stated re-review trigger — `#7917` is closed
# by the PR that adds this file, so citing it would leave every entry pointing at a dead ref.
# CEILING: raising it is an ADR-207 edit, not a local decision.
LEDGER_CEILING=12
LEDGER=(
  # scripts/lib/repo-write-boundary.test.sh — 11 deliberate probe-tag creations. This is the
  # suite that TESTS the refs/tags boundary, so it is the one place a real tag author belongs;
  # every one runs inside a mktemp sandbox the suite creates. No removal is planned, so these
  # carry a RE-REVIEW TRIGGER rather than a tracking issue: filing an issue for work with no
  # removal path is phantom backlog. Trigger: an entry is void if its site stops creating the
  # tag inside a sandbox root the suite itself created.
  #
  # SINGLE-quoted, deliberately: these keys carry the command text verbatim, which includes
  # shell variables such as "$p". Double quotes would EXPAND them — measured, that made the
  # suite die with `p: unbound variable` under set -u before any classification ran.
  'scripts/lib/repo-write-boundary.test.sh|git -C "$p" -c tag.gpgSign=false -c tag.forceSignAnnotated=false tag probe-tag 2>/dev/null'
  'scripts/lib/repo-write-boundary.test.sh|git -C "$p" -c tag.gpgSign=false tag -f probe-tag >/dev/null 2>&1'
  'scripts/lib/repo-write-boundary.test.sh|git -C "$p" -c tag.gpgSign=false tag probe-tag'
  'scripts/lib/repo-write-boundary.test.sh|pgit -C "$d" tag "$t"'
  'scripts/lib/repo-write-boundary.test.sh|pgit -C "$p" tag -a v9.9.7 -m '"'"'annotated release'"'"''
  'scripts/lib/repo-write-boundary.test.sh|pgit -C "$p" tag -f moved-tag "$mix_c2" >/dev/null 2>&1'
  'scripts/lib/repo-write-boundary.test.sh|pgit -C "$p" tag doomed-tag'
  'scripts/lib/repo-write-boundary.test.sh|pgit -C "$p" tag fresh-tag'
  'scripts/lib/repo-write-boundary.test.sh|pgit -C "$p" tag moved-tag'
  'scripts/lib/repo-write-boundary.test.sh|pgit -C "$p" tag v3.258.3'
  'scripts/lib/repo-write-boundary.test.sh|pgit -C "$p" tag v9.9.9'
)

# --- out-of-class registration ledger (Stage A, AC6) ----------------------------------------
# A registration is accounted for in exactly one of two places: resolved into the root set, or
# recorded HERE with a reason. A shape that is neither is UNCLASSIFIED and fails the run — there
# is no third, silent option.
#
# Matching is by SUBSTRING on the joined argv, because the same registration appears in two
# shapes: locally one `npm run test:ci` inline script is a decline, under CI both are live
# (the relevance gate's bypass makes declines unreachable). Keying on the exact argv would make
# the ledger environment-dependent, which is the drift this file exists to avoid.
OUT_OF_CLASS_CEILING=4
OUT_OF_CLASS=(
  # Runs a PACKAGE SCRIPT, not a tracked executable path. `npm run test:ci` expands through
  # vitest's own project config, so there is no path literal for this guard to resolve, and
  # inventing one would be a guess presented as a root. The vitest suites it runs are TypeScript
  # under apps/web-platform, which cannot author a git tag without going through a spawn whose
  # argv this guard already scans in its array-form spelling.
  'npm run test:ci'
)

# --- Stage A: roots -------------------------------------------------------------------------
ROOTS_RAW="$(mktemp -t battery-tag-roots.XXXXXXXX)"
UNCLASSIFIED_LOG="$(mktemp -t battery-tag-unclassified.XXXXXXXX)"
CENSUS="$(mktemp -t battery-tag-census.XXXXXXXX)"
trap 'rm -f "$ROOTS_RAW" "$UNCLASSIFIED_LOG" "$CENSUS"' EXIT

enum_rc=0
timeout 120 env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1 \
  bash "$RUNNER" --enumerate-commands all > "$ROOTS_RAW" 2>/dev/null || enum_rc=$?
if (( enum_rc != 0 )); then
  printf 'ERROR: --enumerate-commands exited %d — refusing to classify against an empty root set\n' "$enum_rc" >&2
  exit 1
fi
records=$({ grep -c '^SUITE_COMMAND' "$ROOTS_RAW" || true; })
if (( records == 0 )); then
  printf 'ERROR: --enumerate-commands produced zero records — refusing to fall through to an empty root set\n' >&2
  exit 1
fi

declare -A ROOTS=()
unclassified=0
out_of_class=0

_add_root() {
  local p="${1#./}"
  [[ -n "$p" ]] || return 0
  [[ -f "$REPO_ROOT/$p" ]] || return 0
  ROOTS["$p"]=1
}

_resolve_command() {
  # argv arrives as "$@"; strip leading VAR=… assignments and interpreter prefixes.
  local -a a=("$@")
  local i=0
  while (( i < ${#a[@]} )); do
    case "${a[$i]}" in
      *=*) i=$((i + 1)) ;;
      env|sudo|timeout) i=$((i + 1)) ;;
      [0-9]*s) i=$((i + 1)) ;;   # timeout's duration operand
      *) break ;;
    esac
  done
  local head="${a[$i]:-}"
  local next="${a[$((i + 1))]:-}"
  case "$head" in
    bash|sh)
      if [[ "$next" == "-c" ]]; then
        printf 'INLINE_SCRIPT\t%s\n' "${a[*]}" >> "$UNCLASSIFIED_LOG"
        return 1
      fi
      _add_root "$next"; return 0 ;;
    python3|python)
      if [[ "$next" == "-m" ]]; then
        local mod="${a[$((i + 2))]:-}"
        _add_root "${mod//./\/}.py"; return 0
      fi
      _add_root "$next"; return 0 ;;
    node)
      [[ "$next" == "--test" ]] && next="${a[$((i + 2))]:-}"
      _add_root "$next"; return 0 ;;
    bun)
      local j=$((i + 1)) op=""
      while (( j < ${#a[@]} )); do
        case "${a[$j]}" in
          test|-*) j=$((j + 1)) ;;
          *) op="${a[$j]}"; break ;;
        esac
      done
      [[ -n "$op" ]] || return 1
      if [[ "$op" == */ || -d "$REPO_ROOT/$op" ]]; then
        # DECLARED APPROXIMATION 4: glob expansion approximates bun's own collection.
        local f
        while IFS= read -r f; do _add_root "$f"; done < <(
          cd "$REPO_ROOT" && { git ls-files "${op%/}" | grep -E '\.(test|spec)\.(ts|tsx|js|mjs)$' || true; }
        )
        return 0
      fi
      _add_root "$op"; return 0 ;;
    cd) printf 'CD_COMPOUND\t%s\n' "${a[*]}" >> "$UNCLASSIFIED_LOG"; return 1 ;;
    *)
      if [[ "$head" == *.sh || "$head" == *.py ]]; then _add_root "$head"; return 0; fi
      return 1 ;;
  esac
}

NESTED_RUNNERS=("apps/web-platform/infra/run-registered-suites.sh" ".github/scripts/test/run-all.sh")
MIN_INFRA_DERIVED=1

while IFS= read -r line; do
  [[ "$line" == SUITE_COMMAND$'\t'* ]] || continue
  IFS=$'\t' read -r _rt _label rest <<<"$line"
  IFS=$'\t' read -r -a argv <<<"$(printf '%s' "${line#*$'\t'*$'\t'}")"
  # Nested runners are a second chokepoint: delegate rather than re-derive.
  nested=""
  for nr in "${NESTED_RUNNERS[@]}"; do
    case " ${argv[*]} " in *" $nr "*) nested="$nr" ;; esac
  done
  if [[ -n "$nested" ]]; then
    _add_root "$nested"
    if [[ "$nested" == *run-registered-suites.sh ]]; then
      derived=0
      while IFS= read -r sub; do
        [[ -n "$sub" ]] || continue
        _add_root "$sub"; derived=$((derived + 1))
      done < <( cd "$REPO_ROOT" && INFRA_ORPHAN_LIST=/dev/null timeout 60 bash "$nested" --list 2>/dev/null || true )
      if (( derived < MIN_INFRA_DERIVED )); then
        printf 'NESTED_PARSE_FLOOR\t%s derived=%d\n' "$nested" "$derived" >> "$UNCLASSIFIED_LOG"
      fi
    fi
    continue
  fi
  if ! _resolve_command "${argv[@]}"; then
    _ooc=0
    for _o in "${OUT_OF_CLASS[@]}"; do
      case "${argv[*]}" in *"$_o"*) _ooc=1 ;; esac
    done
    if (( _ooc == 1 )); then
      out_of_class=$((out_of_class + 1))
    else
      unclassified=$((unclassified + 1))
    fi
  fi
done < "$ROOTS_RAW"

root_count=${#ROOTS[@]}

# MIN_ROOTS — hand-ratcheted, DOWNWARD RATCHET REFUSED. The only legitimate direction is up; a
# shrinking registration surface reddens rather than being absorbed.
MIN_ROOTS=400

# --- Stage B: closure to fixpoint -----------------------------------------------------------
declare -A CLOSURE=()
for r in "${!ROOTS[@]}"; do CLOSURE["$r"]=1; done

DEPTH_BOUND=6
depth=0
while (( depth < DEPTH_BOUND )); do
  added=0
  for f in "${!CLOSURE[@]}"; do
    [[ -f "$REPO_ROOT/$f" ]] || continue
    while IFS= read -r cand; do
      cand="${cand#./}"
      [[ -n "$cand" ]] || continue
      [[ -n "${CLOSURE[$cand]:-}" ]] && continue
      [[ -f "$REPO_ROOT/$cand" ]] || continue
      CLOSURE["$cand"]=1; added=$((added + 1))
    done < <(
      # NO DIRECTORY ALLOWLIST. An earlier revision enumerated top-level dirs
      # (scripts|plugins|apps|tests|.github|.claude) and therefore could not reach
      # `.openhands/hooks/pre-merge-rebase.sh`, which `pre-merge-rebase-parity.test.sh` — a
      # battery suite — invokes by path. That is UNDER-approximation, i.e. fail-OPEN: a real
      # tag author outside the listed dirs was invisible. The plan's design is explicit that any
      # tracked executable path literal joins the closure, so the allowlist is the defect. The
      # `-f` test below is what bounds this; a prose mention of a non-existent path is dropped.
      { grep -oE '(\$\{CLAUDE_PLUGIN_ROOT:-[^}]*\}/|"\$REPO_ROOT"/|\$REPO_ROOT/|"\$GIT_ROOT"/)?[A-Za-z0-9._][A-Za-z0-9._/-]*\.(sh|py|ts|mjs|cjs)' \
        "$REPO_ROOT/$f" || true; } \
      | sed -E 's#^.*\}/##; s#^"?\$[A-Za-z_]+"?/##'
    )
  done
  (( added == 0 )) && break
  depth=$((depth + 1))
done
closure_count=${#CLOSURE[@]}

# --- Stage C: classify ----------------------------------------------------------------------
# Spelling axis: `git` may carry any interleaving of -c k=v, -C path, --git-dir= before the verb.
GITOPT='([[:space:]]+(-c[[:space:]]+[^[:space:]]+|-C[[:space:]]+("[^"]*"|[^[:space:]]+)|--git-dir=[^[:space:]]+))*'
VERB_RE="git${GITOPT}[[:space:]]+(fetch|pull|remote[[:space:]]+update|tag|update-ref)([[:space:]]|\$)"
ARRAY_RE='\["(git", *")?(fetch|pull|tag|update-ref)"'

occurrences=0; offenders=0; suppressed=0; exempt=0
declare -A EXEMPT_SEEN=()

# A git verb inside a STRING LITERAL is prose, not an invocation: an error message, a
# `::warning::` line, or a grep pattern naming the command it looks for. Counting those as
# tag authors is a false OFFENDER whose only "fix" would be editing an error message, and
# declaring them in the ledger would spend its ceiling on things that author no tag.
#
# The test is quote parity BEFORE the match: an odd number of unescaped quotes means the verb
# sits inside a string. It is applied ONLY to the shell-verb pattern — the TS array form
# (`["git", "fetch", …]`) is BY CONSTRUCTION inside quotes and is a real invocation, so a
# blanket parity rule would silently stop detecting it. Measured: 6 of 39 first-run offenders
# were this class, and the array-form site is not one of them.
_in_string_literal() {
  local line="$1" verb="$2" prefix dq sq
  prefix="${line%%$verb*}"
  [[ "$prefix" == "$line" ]] && return 1
  prefix="${prefix//\\\"/}"
  prefix="${prefix//\\\'/}"
  dq="${prefix//[!\"]/}"
  sq="${prefix//[!\']/}"
  (( ${#dq} % 2 == 1 || ${#sq} % 2 == 1 )) && return 0
  return 1
}

_is_in_class() {
  # $1 = the code line. Decide whether a matched verb is actually tag-authoring.
  local l="$1"
  # Out of class, explicitly.
  [[ "$l" =~ git[^\|]*[[:space:]]push[[:space:]] ]] && return 1
  [[ "$l" =~ git[^\|]*[[:space:]]clone[[:space:]] ]] && return 1
  [[ "$l" =~ [[:space:]]ls-remote([[:space:]]|$) ]] && return 1
  if [[ "$l" =~ [[:space:]]tag([[:space:]]|$) ]]; then
    # creating forms only
    [[ "$l" =~ [[:space:]]tag[[:space:]]+(-d|--delete|-l|--list|--verify|-n|--contains|--points-at) ]] && return 1
  fi
  if [[ "$l" =~ update-ref ]]; then
    [[ "$l" =~ refs/tags/ ]] || return 1
  fi
  return 0
}

_suppresses() {
  local l="$1"
  [[ "$l" =~ --no-tags ]] || return 1
  # Negative conjunct — a positive tag request on the SAME command defeats --no-tags.
  # `git fetch --no-tags origin '+refs/tags/*:refs/tags/*'` is documented to fetch tags anyway,
  # and `--no-tags --tags` precedence is NOT formally documented, so the guard refuses to guess.
  [[ "$l" =~ (--tags|[[:space:]]-t([[:space:]]|$)|refs/tags/|tagOpt) ]] && return 1
  # Only fetch and pull can reach SUPPRESSED at all. BOTH SPELLINGS: the shell form
  # (`git fetch …`) and the array form (`["fetch", "--no-tags", …]`). Matching only the
  # space-delimited shell form graded a correctly-suppressed array-form site OFFENDER — the
  # occurrence pattern already covers the array spelling, so the verdict arm has to as well or
  # the two axes disagree and the guard demands a fix that is already present.
  [[ "$l" =~ [[:space:]](fetch|pull)([[:space:]]|$) || "$l" =~ [\"\'](fetch|pull)[\"\'] ]] || return 1
  return 0
}

for f in $(printf '%s\n' "${!CLOSURE[@]}" | LC_ALL=C sort); do
  _excluded "$f" && continue
  [[ -f "$REPO_ROOT/$f" ]] || continue
  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    ln="${hit%%:*}"
    code="${hit#*:}"
    # DECLARED APPROXIMATION 1: full-line comments only.
    [[ "$code" =~ ^[[:space:]]*# ]] && continue
    _is_in_class "$code" || continue
    # Array form is inside quotes by construction — never parity-skipped.
    if ! [[ "$code" =~ $ARRAY_RE ]]; then
      _in_string_literal "$code" "git" && continue
    fi
    occurrences=$((occurrences + 1))
    ctx="$({ grep -n -B2 -E "$VERB_RE|$ARRAY_RE" "$REPO_ROOT/$f" || true; } | awk -v L="$ln" -F'[-:]' '$1>=L-2 && $1<=L')"
    cmd_key="$(printf '%s' "$code" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"
    if _suppresses "$code"; then
      verdict=SUPPRESSED; suppressed=$((suppressed + 1))
    elif [[ "$ctx" =~ repo-boundary-tag-exempt: ]]; then
      key="$f|$cmd_key"
      in_ledger=0
      for e in ${LEDGER[@]+"${LEDGER[@]}"}; do [[ "$e" == "$key" ]] && in_ledger=1; done
      if (( in_ledger )); then
        verdict=EXEMPT; exempt=$((exempt + 1)); EXEMPT_SEEN["$key"]=1
      else
        verdict=OFFENDER; offenders=$((offenders + 1))
      fi
    else
      verdict=OFFENDER; offenders=$((offenders + 1))
    fi
    printf '%s:%s\t%s\t%s\t%s\n' "$f" "$ln" "$verdict" "battery-reachable" "$cmd_key" >> "$CENSUS"
  done < <( { grep -nE "$VERB_RE|$ARRAY_RE" "$REPO_ROOT/$f" || true; } )
done

# --- assertions -----------------------------------------------------------------------------
printf '\n=== battery tag-authorship census ===\n'
if [[ -s "$CENSUS" ]]; then LC_ALL=C sort "$CENSUS"; else printf '(no occurrences)\n'; fi
printf '\n'

ck; if (( root_count >= MIN_ROOTS )); then
  pass "root set has $root_count members (floor $MIN_ROOTS)"
else
  fail "root set collapsed: $root_count < MIN_ROOTS=$MIN_ROOTS"
fi

for w in scripts/lib/repo-write-boundary.test.sh scripts/suite-exit-class-parity.test.sh tests/scripts/test-plan-gate-preamble.sh; do
  ck; if [[ -n "${ROOTS[$w]:-}" ]]; then
    pass "source-coverage witness present: $w"
  else
    fail "source-coverage witness MISSING from root set: $w"
  fi
done

ck; if (( out_of_class <= OUT_OF_CLASS_CEILING )); then
  pass "out-of-class registrations within ceiling ($out_of_class <= $OUT_OF_CLASS_CEILING)"
else
  fail "out-of-class registrations exceed ceiling ($out_of_class > $OUT_OF_CLASS_CEILING) — each needs a stated reason"
fi

ck; if (( unclassified == 0 )); then
  pass "every registration accounted for (0 unclassified)"
else
  fail "$unclassified registration(s) UNCLASSIFIED — see below"
  LC_ALL=C sort -u "$UNCLASSIFIED_LOG" | sed 's/^/      /' >&2
fi

ck; if (( offenders == 0 )); then
  pass "no undeclared tag-authoring command in the battery closure"
else
  fail "$offenders undeclared tag-authoring command(s) in the battery closure"
fi

# Ledger bijection, BOTH directions.
orphans=0
for e in ${LEDGER[@]+"${LEDGER[@]}"}; do
  [[ -n "${EXEMPT_SEEN[$e]:-}" ]] || { orphans=$((orphans + 1)); printf '      ORPHAN LEDGER ENTRY: %s\n' "$e" >&2; }
done
ck; if (( orphans == 0 )); then
  pass "exemption ledger has no orphan entries"
else
  fail "$orphans orphan ledger entr(ies) — the site was fixed, deleted, or its marker removed"
fi
# The ceiling has ONE home: ADR-207 section 5. Assert the local constant equals it, so a ceiling
# raised locally to make a run green cannot drift away from the decision record that governs it.
# Fail CLOSED: an unreadable ADR or an unparseable line is a failure, never a skipped check.
_adr="$REPO_ROOT/knowledge-base/engineering/architecture/decisions/ADR-207-repo-write-boundary-harm-partition.md"
_adr_ceiling="$({ grep -oE "The exemption ledger's ceiling is \*\*[0-9]+\*\*" "$_adr" 2>/dev/null || true; } | grep -oE '[0-9]+' | head -1)"
ck; if [[ -n "$_adr_ceiling" && "$_adr_ceiling" == "$LEDGER_CEILING" ]]; then
  pass "ledger ceiling matches its single home in ADR-207 section 5 ($LEDGER_CEILING)"
else
  fail "ledger ceiling drift: guard says '$LEDGER_CEILING', ADR-207 section 5 says '${_adr_ceiling:-<unreadable>}' — the ADR is the one home"
fi

ck; if (( ${#LEDGER[@]} <= LEDGER_CEILING )); then
  pass "exemption ledger within ceiling (${#LEDGER[@]} <= $LEDGER_CEILING)"
else
  fail "exemption ledger exceeds ceiling (${#LEDGER[@]} > $LEDGER_CEILING) — raising it is an ADR-207 edit"
fi

# --- Stage D: floors and conservation --------------------------------------------------------
printf '\nbattery-tag-authorship: %d passed, %d failed, %d assertion(s) executed; roots=%d closure=%d occurrences=%d offenders=%d unclassified=%d out-of-class=%d\n' \
  "$passes" "$fails" "$asserted" \
  "$root_count" "$closure_count" "$occurrences" "$offenders" "$unclassified" "$out_of_class"

# Reported DIRECTLY, never through fail() — a neutered fail() is exactly what this backstops
# (ADR-193). Zero slack: the floor is the measured count.
#
# THE BINDING BELOW SITS FLUSH AGAINST THE `if`, WITH NO BLANK LINE OR COMMENT BETWEEN THEM,
# AND THAT ADJACENCY IS LOAD-BEARING. `scripts/guard-vacuity-floor.test.sh` builds its mutant
# by slicing the floor block and widening BACKWARD over CONTIGUOUS simple assignments; it stops
# at the first line that is not one. With the threshold declared further up, the mutant loses
# the binding, dies at an unbound variable under `set -u` before reaching the floor, and is
# scored CONSTRUCTION — an UNCOVERED floor, which is the opposite of what this floor is for.
# Measured: the earlier layout put this suite in that file's construction-failure set.
BATTERY_TAG_MIN_ASSERTIONS=9
if (( asserted < BATTERY_TAG_MIN_ASSERTIONS )); then
  printf '[FATAL] assertion floor: executed %d < BATTERY_TAG_MIN_ASSERTIONS=%d\n' "$asserted" "$BATTERY_TAG_MIN_ASSERTIONS" >&2
  exit 1
fi
if (( passes + fails != asserted )); then
  printf '[FATAL] accounting conservation: passes(%d) + fails(%d) != asserted(%d)\n' "$passes" "$fails" "$asserted" >&2
  exit 1
fi

(( fails == 0 )) || exit 1
exit 0
