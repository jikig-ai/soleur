#!/usr/bin/env bash
# markdown-lint.sh -- the SINGLE invoker for markdownlint in this repository.
#
# WHY (#7927, also #7837 #7832 #2685). markdownlint existed only as a lefthook
# pre-commit command running `npx --yes markdownlint-cli {staged_files}`. Three
# consequences, each measured rather than supposed:
#
#   1. `npx --yes` resolves the LATEST markdownlint-cli on every invocation, so the
#      verdict drifts under files nobody edited. plugins/soleur/skills/ship/SKILL.md
#      was staged and committed 12 times in 30 days while carrying errors that only
#      became errors when a release added the rule. Pinning is the actual fix, and it
#      is why this script refuses to run an unpinned binary.
#   2. PRs land on main by SQUASH MERGE, where lefthook never runs. A red file reaches
#      main whenever its PR had no local commit that staged it.
#   3. Nothing in CI ran markdownlint at all, so 1 and 2 accumulated silently to
#      32,356 errors across 3,818 tracked files.
#
# The operation that broke is a contributor's local `git merge origin/main`: the hook
# lints {staged_files}, and a merge commit stages every file the merge brings in, so
# the merge is blocked by errors the contributor did not write.
#
# ONE SOURCE OF SCOPE. The swept set is derived from .markdownlintignore, and BOTH
# callers -- the lefthook hook and the CI job -- reach markdownlint only through this
# script. A second place to declare scope would be a second thing to drift.

set -euo pipefail

# LC_ALL=C, exported and pinned again at each sort/comm. `comm` compares in its own
# collation and requires its inputs sorted in that SAME collation; under a UTF-8 locale
# glibc's sort ignores punctuation at the primary level, so paths differing only by `-`
# vs `/` order differently than byte order and `comm` emits an undefined diff. Measured
# in scripts/lint-orphan-test-suites.sh as 48 phantom results.
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$REPO_ROOT/.markdownlint.json"
IGNORE="$REPO_ROOT/.markdownlintignore"
BIN="$REPO_ROOT/node_modules/.bin/markdownlint"
MANIFEST="$REPO_ROOT/package.json"

die() { printf 'markdown-lint: %s\n' "$*" >&2; exit 2; }

# --- Preconditions -----------------------------------------------------------------
#
# Fail LOUDLY and never fall back to the network. A `npx --yes` fallback here would
# reintroduce defect 1 above at the exact moment the pin is missing, which is the
# moment it matters.
INVOCATION_CWD="$PWD"
cd "$REPO_ROOT" || die "cannot enter repository root $REPO_ROOT"
[[ -f "$CONFIG" ]] || die "missing $CONFIG"
[[ -f "$IGNORE" ]] || die "missing $IGNORE"
[[ -x "$BIN" ]] || die "markdownlint is not installed at $BIN -- run: npm install --ignore-scripts. This script will NOT fall back to npx: an unpinned binary is the defect #7927 exists to close."

PINNED="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["devDependencies"]["markdownlint-cli"])' "$MANIFEST")"
[[ -n "$PINNED" ]] || die "package.json declares no markdownlint-cli pin"
case "$PINNED" in
  *'^'*|*'~'*|*'*'*|*'x'*) die "the markdownlint-cli pin '$PINNED' is a RANGE. It must be exact, or the verdict drifts under unchanged files -- see WHY 1 above." ;;
esac
INSTALLED="$("$BIN" --version 2>/dev/null | tail -1 | tr -d '[:space:]')"
[[ "$INSTALLED" == "$PINNED" ]] || die "installed markdownlint-cli is $INSTALLED but package.json pins $PINNED -- run: npm install --ignore-scripts"

# THE CLI VERSION IS NOT THE THING THAT DECIDES VERDICTS. markdownlint-cli declares its
# rules engine as `"markdownlint": "~0.41.1"` -- a RANGE. Asserting only the CLI leaves
# the engine free to float within that range on a plain `npm install`, and the verdict
# then moves under files nobody edited: precisely defect 1 above, which this script
# claims to close. `npm ci` pins the engine through package-lock.json, so CI is already
# deterministic; this makes the same guarantee hold locally, where the hook runs.
ENGINE_PIN="$(python3 -c '
import json,sys
lock=json.load(open(sys.argv[1]))
for k, v in lock["packages"].items():
    if k == "node_modules/markdownlint" or k.endswith("/node_modules/markdownlint"):
        print(v.get("version","")); break
' "$REPO_ROOT/package-lock.json")"
[[ -n "$ENGINE_PIN" ]] || die "package-lock.json declares no markdownlint rules-engine version -- the pin cannot be verified, and an unverifiable pin is the defect this script exists to close"
ENGINE_INSTALLED="$(python3 -c '
import json,sys
print(json.load(open(sys.argv[1]))["version"])
' "$REPO_ROOT/node_modules/markdownlint/package.json" 2>/dev/null)"
[[ -n "$ENGINE_INSTALLED" ]] || die "the markdownlint rules engine is not installed -- run: npm install --ignore-scripts"
[[ "$ENGINE_INSTALLED" == "$ENGINE_PIN" ]] || die "installed markdownlint rules engine is $ENGINE_INSTALLED but package-lock.json pins $ENGINE_PIN. The CLI version matching is NOT sufficient: the CLI depends on the engine by RANGE (~), so this is the version that actually decides verdicts -- run: npm ci --ignore-scripts"

# --- Scope derivation --------------------------------------------------------------
#
# NUL-DELIMITED THROUGHOUT. `git ls-files` C-quotes any path outside printable ASCII
# (measured: two tracked paths carry Cyrillic homoglyphs), and a quoted path is not the
# path -- it would be handed to the linter as a literal with embedded quotes and
# backslashes. `-z` sidesteps quoting entirely rather than trying to undo it.
scope_nul() {
  comm -z -23 \
    <(git ls-files -z '*.md' | LC_ALL=C sort -z) \
    <(git ls-files -z -c -i --exclude-from="$IGNORE" -- '*.md' | LC_ALL=C sort -z)
}

MODE="${1:-}"
declare -a FILES=()

if [[ "$MODE" == "--repo-sweep" ]]; then
  mapfile -d '' -t FILES < <(scope_nul)

  # --- Anti-vacuity, SWEEP MODE ONLY -----------------------------------------------
  #
  # A linter that enumerates nothing exits 0 and is byte-identical to a clean repo.
  # Two independent guards, because they fail differently and neither sees the other's
  # failure.

  # (a) COUNT FLOOR. Absolute and hand-ratcheted -- deriving it from `git ls-files`
  # would be deriving the floor from its own subject. 1250 measured 2026-09-09 against
  # 9660 tracked *.md (was 1345 before the fixture and vendored corpora were excluded; see
  # .markdownlintignore for why a linter must not rewrite a suite's input bytes). The
  # slack is NARROWING BUDGET, not safety margin: keep just enough that a real
  # documentation cleanup does not red the gate.
  MIN_SWEPT_FILES=1200
  if (( ${#FILES[@]} < MIN_SWEPT_FILES )); then
    die "the sweep enumerated ${#FILES[@]} files, below the floor of ${MIN_SWEPT_FILES} -- the producer has narrowed or broken, so a PASS below would certify a SUBSET of the repo while reporting on all of it."
  fi

  # (b) ROOTS SUPERSET. A count cannot see a SUBSTITUTION that keeps the total up, nor
  # a whole root silently dropping out while other roots grow. Asserted as a SUPERSET,
  # not an equality: a new top-level directory of documentation is a normal event and
  # must not red the gate, whereas an expected root going missing means the walk
  # stopped covering it. Measured from this producer's own output, not from memory.
  # Re-derived 2026-09-08 against this producer, by running the arithmetic rather than
  # narrating it: these 13 roots hold 1,334 of the 1,345 swept files. The original
  # 8-root set held 1,136, leaving 209 outside the assertion against a floor slack of
  # 145 -- so dropping .grok/ (67) and .openhands/ (63) would have passed BOTH guards
  # at 1,215 files, which is exactly the narrowing this assertion exists to catch.
  #
  # The 11 still uncovered are: two one-file roots (infra, spike) whose last *.md can
  # legitimately be deleted, and the nine repo-root *.md (AGENTS.md, README.md and
  # friends), which are files rather than roots and so have no directory to assert.
  # The count floor is their only cover. That is a deliberate trade; it is stated with
  # the real numbers because an earlier revision of this comment claimed 1,325/20 and
  # listed .gemini as uncovered while it is a member below -- a justification narrated
  # from memory instead of measured, in the paragraph justifying the trade.
  EXPECTED_ROOTS=(.claude .gemini .github .grok .openhands apps docs knowledge-base plugins scripts test tests todos)
  actual_roots="$(printf '%s\0' "${FILES[@]}" | cut -z -d/ -f1 | tr '\0' '\n' | LC_ALL=C sort -u)"
  missing=""
  for r in "${EXPECTED_ROOTS[@]}"; do
    grep -qxF -- "$r" <<<"$actual_roots" || missing+="$r "
  done
  # (c) DISTINCTNESS. Both guards read ${#FILES[@]}, a multiset cardinality. Duplicating
  # the producer (`scope_nul; scope_nul`) doubles it, so the floor is satisfiable while
  # more than half the real corpus is narrowed away -- measured: 2,690 entries, 1,345
  # distinct, floor 1200 green. A count nothing reconciles is not a floor.
  distinct="$(printf '%s\0' "${FILES[@]}" | LC_ALL=C sort -zu | tr -cd '\0' | wc -c)"
  (( distinct == ${#FILES[@]} )) || die "the sweep enumerated ${#FILES[@]} entries but only $distinct are distinct -- the producer is emitting duplicates, so the count floor above is measuring a multiset and can be satisfied while real files are dropped."

  # (d) DEPTH REACH. `git ls-files '*.md'` matches at every depth; `'*/*.md'` -- a
  # two-character edit -- silently drops every repo-root file (AGENTS.md, CLAUDE.md,
  # CONTRIBUTING.md, README.md and five more: 9 files, leaving 1,336, so the floor stays
  # green). Those files are also invisible to the roots assertion by construction, since
  # `cut -d/ -f1` on a depth-1 path yields the filename itself and it can never be named
  # as a directory. This is the cheapest narrowing available and it takes out the
  # repository's front door.
  depth1="$(printf '%s\0' "${FILES[@]}" | tr '\0' '\n' | grep -cv '/' || true)"
  (( depth1 >= 1 )) || die "the sweep reached no depth-1 file. Every tracked *.md at the repository root (AGENTS.md, README.md, CLAUDE.md, ...) has been dropped -- the producer's pathspec no longer matches at depth 1, and neither the count floor nor the roots assertion can see it."

  # (c) INLINE SILENCING. Both guards above count ${#FILES[@]}, so a file that carries a
  # bare `<!-- markdownlint-disable -->` with no matching `-enable` stays in the swept
  # set, reads identically to both, and is unlinted to EOF -- a whole file removed from
  # coverage without moving a number either guard can see. Same for
  # `markdownlint-configure-file`, which can switch rules off document-wide.
  # Scoped `-disable-line` / `-disable-next-line` are deliberately permitted: they
  # silence one line, they are visible at the site, and this corpus uses them for the
  # deliberate-space MD038 idiom the remediation block describes.
  # ONE batched grep per directive, not one per file: a per-file loop over 1,345 files
  # (and 1,650 in the suite's sandbox, times every case) turns a 12-second run into
  # minutes. `grep -oh` prints one line per MATCH across all files; `|| true` because
  # grep exits 1 on no matches and this runs under `set -e`.
  count_directive() { # <ere>
    printf '%s\0' "${FILES[@]}" | xargs -0 grep -ohE "$1" 2>/dev/null | wc -l || true
  }
  dis="$(count_directive '<!--[[:space:]]*markdownlint-disable[[:space:]]*-->')"
  ena="$(count_directive '<!--[[:space:]]*markdownlint-enable[[:space:]]*-->')"
  cfg="$(count_directive 'markdownlint-configure-file')"
  (( cfg == 0 )) || die "$cfg markdownlint-configure-file directive(s) in the swept set -- these switch rules off document-wide while the file still counts toward the floor above, so coverage drops with no number moving. Remove them, or exclude the file in .markdownlintignore where the exclusion is at least visible."
  (( dis == ena )) || die "unbalanced file-level directives in the swept set: $dis markdownlint-disable vs $ena markdownlint-enable. An unmatched disable silences its file to EOF while the file still counts toward the floor above -- coverage drops and neither guard moves. Pair it with an enable, or use -disable-line for a single site."

  [[ -z "$missing" ]] || die "the sweep reached roots but did NOT reach [${missing% }] -- the producer stopped walking a root it is expected to cover. A count floor cannot see this: a dropped root leaves the total above any floor loose enough not to red on a real cleanup."

elif [[ -n "$MODE" ]]; then
  # --- Explicit paths (the lefthook hook passes {staged_files}) ---------------------
  #
  # Filtered through the same exclusion as the sweep. NOT for scope agreement -- the
  # linter honours .markdownlintignore for explicit paths on its own, so that would
  # hold anyway. This exists for the MESSAGE: when every passed path is excluded the
  # bare CLI takes its help() branch and dumps 20 lines of usage at exit 0, and since
  # knowledge-base/project/ is 8,235 of 9,627 tracked *.md, the all-excluded case is
  # the COMMON one here -- every plan/spec/learning commit would print that dump.
  declare -A IN_SCOPE=()
  while IFS= read -r -d '' f; do IN_SCOPE["$f"]=1; done < <(scope_nul)
  # ARGUMENTS ARE RESOLVED AGAINST THE CALLER'S CWD, then made repo-root-relative.
  # The script cd's to the repo root, so a bare map lookup silently misses any
  # cwd-relative path and reports "nothing to lint" at exit 0 -- a GREEN that means
  # nothing. Measured from plugins/: `markdown-lint.sh soleur/README.md` reported
  # "nothing to lint" while `plugins/soleur/README.md` reported "1 file(s) clean".
  # lefthook always passes root-relative paths so the hook was never affected, but a
  # human or agent following the remediation block from a subdirectory was.
  for arg in "$@"; do
    if [[ -n "${IN_SCOPE[$arg]:-}" ]]; then
      FILES+=("$arg"); continue
    fi
    resolved=""
    if [[ "$arg" == /* ]]; then
      resolved="$(realpath -m --relative-to="$REPO_ROOT" -- "$arg" 2>/dev/null || true)"
    else
      resolved="$(realpath -m --relative-to="$REPO_ROOT" -- "$INVOCATION_CWD/$arg" 2>/dev/null || true)"
    fi
    if [[ -n "$resolved" && -n "${IN_SCOPE[$resolved]:-}" ]]; then
      FILES+=("$resolved")
    fi
  done
  if (( ${#FILES[@]} == 0 )); then
    # No anti-vacuity floor here, deliberately: the hook passes whatever is staged, and
    # "nothing staged is in scope" is the ordinary case, not a degraded one. The floor
    # belongs to sweep mode, where an empty set IS the failure. The cost is that a
    # broken producer reads green locally until the next CI sweep.
    echo "markdown-lint: none of the $# given path(s) are in scope (excluded by .markdownlintignore, or not tracked *.md) -- nothing to lint."
    exit 0
  fi
else
  die "usage: markdown-lint.sh --repo-sweep | markdown-lint.sh <path>..."
fi

# --- Run ---------------------------------------------------------------------------
#
# Capture rather than pipe: `cmd | tail` reports the PIPE's status and destroys the
# evidence in the same stroke.
set +e
# --ignore-path /dev/null makes git the SOLE interpreter of scope. Without it the
# linter reads .markdownlintignore ITSELF and silently drops explicitly-passed paths,
# so scope is declared once and INTERPRETED TWICE -- by git's gitignore engine in
# scope_nul() and again by the npm `ignore` package in here. The two disagree on POSIX
# classes ([[:alpha:]], which git supports and `ignore` does not), escaped leading
# characters, and mid-pattern **. Measured: with `sub/` ignored, `markdownlint clean.md
# sub/red.md` exits 0 and prints nothing; with this flag it reports the error.
#
# That divergence would defeat both guards above, because they count ${#FILES[@]} --
# the PRE-filter set. The script would print "N file(s) clean" having linted fewer
# than N, and exit 0. A floor placed upstream of a filter it must guard is the
# vacuity class this whole file exists to close.
output="$(printf '%s\0' "${FILES[@]}" | xargs -0 "$BIN" --config "$CONFIG" --ignore-path /dev/null 2>&1)"
rc=$?
set -e

if (( rc == 0 )); then
  echo "markdown-lint: ${#FILES[@]} file(s) clean."
  exit 0
fi

printf '%s\n' "$output"
# Same stream as the findings above: `--repo-sweep > log` must not separate a
# finding from the block that says how to fix it.
cat <<'REMEDIATION'

--------------------------------------------------------------------------------
markdownlint failed. What to do:

  * Fix in place, then re-run:   bash scripts/markdown-lint.sh --repo-sweep
  * Most rules auto-fix:         ./node_modules/.bin/markdownlint --fix <file>

    DO NOT --fix these four:     MD037 MD038 MD049 MD050
    They rewrite PROSE, not markup. Measured on this corpus: --fix deleted real
    spaces BETWEEN WORDS seven times on one line, and mangled a currency amount.
    Resolve those four by hand, per site.

  * A space inside a code span is sometimes DELIBERATE -- a command prefix, a
    heading marker, a formatter's alignment. CommonMark preserves it (a span is
    only stripped when it both begins AND ends with a space), so MD038 is a false
    positive there. Mark the line, never delete the illustrated space:
        <!-- markdownlint-disable-line MD038 -->

  * A backslash CANNOT escape a backtick into a code span (CommonMark has no such
    escape). Use a longer delimiter run instead, with real inner backticks.

  * Scope is declared in ONE place: .markdownlintignore. Rules: .markdownlint.json
--------------------------------------------------------------------------------
REMEDIATION
exit 1
