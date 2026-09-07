#!/usr/bin/env bash
# Guard 5 — fixture-env adoption (static).
#
# PROPERTY. Every test file that spawns `git` with a MUTATING invocation, in the roots Phase 2
# (#7849) covered, obtains its environment from the shared fixture-env helper — and every shell call
# of that helper checks its return.
#
# WHY THIS FILE EXISTS. Review found Phase 2 otherwise unverified: the mutation battery
# (git-fixture-env.mutation.sh) and `tsc` both stay GREEN if the conversions are simply skipped.
# They assert that the HELPER is correct, never that anything CALLS it. This guard is the only thing
# in the repository that reddens when someone reverts a conversion.
#
# ── ASSEMBLY: TWO INDEPENDENT DERIVATIONS, DIFFERENCED ────────────────────────────────────────────
#
#   A = git-spawn sites, derived from INVOCATION SHAPE (never from a name mention).
#   B = fixture-env helper CALL sites, derived from call syntax.
#   DIFFERENCE = A \ B, PRINTED IN FULL, and every member must be accounted for by one of the two
#   declared lists below.
#
# Differenced, not counted. Equal cardinality does not imply the same set: convert one suite while
# a second regresses and a count comparison reads green over both. (Harness row H1 mutates this
# check into a count comparison and requires RED.)
#
# Each derivation carries its OWN non-empty floor. A derivation that returns empty makes every
# set-equality assertion pass for the wrong reason — the failure mode a guard like this dies of.
#
# ── ANCHOR ON SYNTAX, NEVER ON A BARE TOKEN ───────────────────────────────────────────────────────
#
# A body-grep sees comments, prose and test DATA. This repo has shipped guards that matched their
# own explanatory paragraph and stayed green under the exact mutation they existed to catch; on this
# branch an assertion reading `"gitCleanEnv" not in source` matched the comment naming the old
# helper. So:
#   * comment lines are dropped before matching (`//`, `*`, `#` at line start);
#   * for shell, quoted spans are stripped BEFORE the command-position match, because
#     `detect_bypass "cd /tmp && git commit --no-verify"` (tests/hooks/test_incidents.sh:169) and
#     `echo "... (git fetch --unshallow) ..."` (infra-config-apply.test.sh:1487) are test DATA, not
#     spawns, and both matched a naive command-position regex;
#   * for code, a single-quoted or backtick span CONTAINING a double quote is code-as-data and is
#     stripped, because `classify('const child = spawn("git", ["status"]);')`
#     (cron-containment-classify.test.ts:408) is a classifier's INPUT, not a spawn. Plain
#     `spawnSync('git', ['init'])` is untouched by that rule — it has no embedded double quote.
#
# ── READ vs MUTATE, FAIL-CLOSED ───────────────────────────────────────────────────────────────────
#
# The property is about fixtures that WRITE. A suite running `git rev-parse --show-toplevel` against
# the real checkout to find the repo root needs no fixture environment and requiring one would be
# noise. So a spawn is classified by its subcommand token, with the READ set as an explicit
# ALLOWLIST: an unknown or absent verb classifies as MUTATING. That direction is deliberate — an
# omission in a write list is fail-OPEN (a new mutating verb reads green), an omission in the read
# list is fail-CLOSED and merely asks an author for a helper they may not have needed.
#
# ── SCOPE ─────────────────────────────────────────────────────────────────────────────────────────
#
# The plan's stated roots are `apps/web-platform/test/**`, `tests/**` and `.github/scripts/test/**`.
# MEASUREMENT CONTRADICTED THAT and the scope below is the corrected one: three of Phase 2's own
# conversions live outside those roots (`test/pre-merge-rebase.test.ts`,
# `plugins/soleur/test/welcome-hook.test.ts`, `apps/web-platform/infra/workspaces-luks-loopback.test.sh`)
# and BOTH #7889 deferrals live under `plugins/soleur/test/`. A guard scoped to the literal three
# would have been blind to over a third of the work it exists to verify. The scope is therefore
# "the plan's declared roots, plus every root in which Phase 2 landed a conversion", stated per
# language because the code and shell conversions landed in different roots.
#
# One root is DELIBERATELY OUTSIDE the shell scope and is NOT hidden: `plugins/soleur/test/*.sh`
# holds 20+ suites that `git init` a fixture and never call the builder. Phase 2 did not cover them.
# They are counted, printed and ratcheted at the bottom of this file rather than absorbed silently —
# the same treatment Guard 3 gives its unchokepointed set.
#
# ── DISPOSITION OF THE TWO #7889 DEFERRALS ────────────────────────────────────────────────────────
#
# `gdpr-gate-repo-scan.test.ts` and `web-platform-runtime-plugin-trigger.test.ts` are still on the
# weaker `gitCleanEnv()`. They belong in the DIFFERENCE SET, not in the waiver list, and they are
# listed under DEFERRED below. The reasoning: the waiver list records suites that are CORRECT as
# they stand and will never be converted; the difference set records suites that are NOT correct and
# whose entry must be deleted when they are fixed. These two are the second kind — `gitCleanEnv()`
# gives the prefix sweep but none of the three things a fixture that WRITES needs (an identity, a
# discovery ceiling, config hermeticity), so `git init` under it still walks up into an enclosing
# repository. Filing them as waivers would assert they are fine, which is false, and would make the
# guard permanently silent about them. As DEFERRED entries the guard prints them on every run, and
# the stale-entry assertion below FORCES the entry to be removed the moment either is converted.
#
# ── SELF-DISCIPLINE ───────────────────────────────────────────────────────────────────────────────
#
# `set -uo pipefail` (never `-e`: this guard accumulates and reports, it does not stop at the first
# finding). Never `grep -q` on a pipe — under `pipefail` an early match closes the pipe, the
# producer takes SIGPIPE and the pipeline exits non-zero EVEN THOUGH GREP MATCHED. `grep -c` and
# herestrings only. The assertion-count floor is reported with `printf` + `exit 1` and never through
# `fail()`, because it backstops `fail()` (ADR-193).
#
# This suite does NOT source test-helpers.sh: that file arms the git tripwire, and this guard must
# stay runnable while diagnosing a hostile environment.
#
# Auto-registered by the `plugins/soleur/test/*.test.sh` glob in scripts/test-all.sh — no
# `run_suite` line, which would double-run it.
#
# Refs #7849.

export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$SCRIPT_DIR" in
  ""|/|//|/.) printf 'FATAL: SCRIPT_DIR degenerate (%s); refusing\n' "$SCRIPT_DIR" >&2; exit 2 ;;
  /*) : ;;
  *) printf 'FATAL: SCRIPT_DIR is relative; refusing\n' >&2; exit 2 ;;
esac
readonly SCRIPT_DIR
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)" || exit 2
readonly REPO_ROOT
cd "$REPO_ROOT" || { printf 'FATAL: cannot cd to REPO_ROOT %s\n' "$REPO_ROOT" >&2; exit 2; }

# `comm` compares in the collation `sort` produced. Under a UTF-8 locale glibc ignores punctuation
# at the primary level, so `a-b/c.ts` and `a/b-c.ts` order differently than byte order and `comm`
# emits an undefined diff over input it considers unsorted. Pinned, and pinned again per call.
export LC_ALL=C

PASS=0
FAIL=0
ASSERTIONS=0

pass() { printf '  [ok]   %s\n' "$1"; PASS=$((PASS+1)); ASSERTIONS=$((ASSERTIONS+1)); }
fail() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); ASSERTIONS=$((ASSERTIONS+1)); }

# --- instrument self-test ------------------------------------------------------------------------
# Drive both counters once and refuse to continue unless both moved. A guard whose reporting helper
# has been neutered reports "0 failed" over a broken tree, which is indistinguishable from a pass.
_p0=$PASS; _f0=$FAIL; _a0=$ASSERTIONS
pass "instrument self-test: pass() increments"
fail "instrument self-test: fail() increments (expected; subtracted below)"
if (( PASS != _p0 + 1 || FAIL != _f0 + 1 || ASSERTIONS != _a0 + 2 )); then
  printf 'FATAL: instrument self-test did not move both counters (pass %d->%d, fail %d->%d)\n' \
    "$_p0" "$PASS" "$_f0" "$FAIL" >&2
  exit 2
fi
PASS=$((PASS-1)); FAIL=$((FAIL-1)); ASSERTIONS=$((ASSERTIONS-2))
printf '  (instrument verified; counters reset)\n\n'
unset _p0 _f0 _a0

# --- scope ----------------------------------------------------------------------------------------
# Overridable so the mutation harness can point the derivations at a scratch tree without editing
# this file. Defaults are the measured Phase 2 population; see the SCOPE section of the header.
CODE_ROOTS=(${SOLEUR_G5_CODE_ROOTS:-'apps/web-platform/test/*' 'plugins/soleur/test/*' 'test/*' 'tests/*'})
SHELL_ROOTS=(${SOLEUR_G5_SHELL_ROOTS:-'tests/*' '.github/scripts/test/*' 'apps/web-platform/infra/*'})
# The out-of-scope shell root, printed and ratcheted rather than absorbed.
OUT_OF_SCOPE_SHELL_ROOTS=('plugins/soleur/test/*')

# --- the READ allowlist ---------------------------------------------------------------------------
# Subcommands that cannot mutate a repository. Everything else — including an absent or unknown verb
# — classifies as MUTATING. See the READ vs MUTATE section of the header for why this direction.
READ_VERBS='rev-parse|ls-files|ls-remote|ls-tree|log|show|status|diff|cat-file|rev-list|describe|blame|grep|for-each-ref|check-ignore|check-attr|var|count-objects|verify-pack|shortlog|name-rev|show-ref|diff-tree|diff-index|merge-base|version|--version|help|show-branch|whatchanged|cherry|check-ref-format'

# SCOPE LIMIT, stated because it is invisible from the output: both derivations enumerate through
# `git ls-files`, so an UNTRACKED file is not in the population. Measured — a new in-scope suite
# spawning bare git passes this guard until it is staged, and reds the moment it is (`git add -N` is
# enough). That is the right boundary for a repo guard, but it means this cannot be the only thing
# standing between a new suite and the operator's state; the runtime tripwire and the chokepoint
# redirect are what cover an unstaged file.
#
# --- derivation A: git-spawn sites, by invocation shape --------------------------------------------
#
# Three shapes for code, covering `execFileSync`, `execFile`, `execFileAsync`, `spawnSync`, `spawn`,
# any promisified wrapper of them (the shape is the ARGUMENT list, not the callee name — which is
# why `execFileP("git", [...])` in cron-safe-commit.test.ts is seen), `execSync`, `Bun.spawn`,
# `Bun.spawnSync` and python's `subprocess.run` / `check_output` / `Popen`:
#
#   ARGV  `(… "git" , [ …`   execFileSync("git", ["init"]) / execFileP("git", args)
#   ARR   `(… [ "git" , …`   Bun.spawnSync(["git","init"]) / subprocess.run(["git","-C",d,"add"])
#   STR   `execSync("git …`  a whole command line as one string; anchored on the exec-family callee
#                            NAME, because `redactCommandForDisplay(\`git clone https://…\`)` is
#                            also "a call whose first argument is a string starting `git `" and is
#                            not a spawn (apps/web-platform/test/lib/redact-command-for-display.test.ts:32).
_Q="[\"'\`]"
CODE_ARGV="\([[:space:]]*${_Q}git${_Q}[[:space:]]*,[[:space:]]*\["
CODE_ARR="\([[:space:]]*\[[[:space:]]*${_Q}git${_Q}[[:space:]]*,"
CODE_STR="(execSync|exec|execAsync|execFileSync|execFile|spawnSync|spawn)[[:space:]]*\([[:space:]]*${_Q}git[[:space:]]"
readonly CODE_SPAWN_RE="${CODE_ARGV}|${CODE_ARR}|${CODE_STR}"

# Command position for shell: line start, or after `;`, `&&`, `||`, `|`, backtick, `$(`. A bare `(`
# is deliberately NOT a command-position anchor here — quoted spans are stripped first, so the only
# thing a bare `(` still admits is prose inside an unbalanced quote.
readonly SHELL_SPAWN_RE='(^|[;&|`]|\$\()[[:space:]]*(command[[:space:]]+)?git[[:space:]]+[^[:space:]]'

# Strip code-as-data spans: a single-quoted or backtick span containing a DOUBLE quote is a source
# fragment passed as an argument, not a call. Plain `spawnSync('git', ['init'])` carries no embedded
# double quote and survives untouched.
_strip_code_data() { sed -E "s/'[^']*\"[^']*'//g; s/\`[^\`]*\"[^\`]*\`//g" "$1"; }
# Strip every quoted span for shell. `git -C "$dir" init` becomes `git -C  init` — the verb, which
# is all the classifier reads, survives; a whole `"… git commit …"` argument does not.
_strip_shell_data() { sed -E 's/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g' "$1"; }

# The return-check (assertion 4) needs to find CALLS, and `_strip_shell_data` is the wrong tool for
# that: deleting EVERY double-quoted span deletes the call itself in the two commonest checked
# forms. Measured against the sed above:
#     eval "$(git_fixture_env "$d")"            ->  eval $d
#     out="$(git_fixture_env "$d")" || exit 1   ->  out=$d || exit 1
# Both lose the call name entirely, so an unchecked call in either form was invisible to the very
# assertion that exists to find it -- a false NEGATIVE, the direction that matters. And comments
# were not stripped at all, so a commented-out call counted as a live call site and was reported
# unchecked, inflating the floor that certifies the check is non-vacuous.
#
# A command substitution inside double quotes is CODE, not data, so double-quoted spans are NOT
# stripped here at all. Two reasons. First, sed cannot pair quotes: a rule that removes spans
# "containing no $" matched the ` || setup_die ` BETWEEN two quoted arguments and spliced a real,
# properly-checked call into an unrecognisable one -- measured on
# test-infra-suite-registration-mutations.sh:89, reported as unchecked when its own line ends in
# `|| setup_die`. Second, stripping them is unnecessary: SHELL_HELPER_CALL_RE anchors the call to a
# statement boundary (^, ;, &, |, backtick, $(), and prose inside a string is preceded by a quote,
# which is not one. So: drop single-quoted literals (no expansion is possible inside them) and drop
# comment lines.
_strip_shell_calls() {
  # Comment lines are BLANKED, not deleted: the failure message reports file:line, and dropping
  # lines here would renumber every call site below the first comment.
  sed -E "s/'[^']*'//g; s/^[[:space:]]*#.*\$//" "$1"
}

# A LINE is mutating iff none of its own tokens is in the READ allowlist. Classified PER LINE and
# the file admitted if ANY line is mutating — never pooled per file. Pooling was the first
# implementation and it was wrong in the fail-OPEN direction: `test/pre-merge-rebase.test.ts` spawns
# `["git","init","--bare"]` AND `["git","rev-parse"]`, and one pooled `rev-parse` classified the
# whole file read-only, silently dropping a converted suite out of the derivation that is supposed
# to notice when it regresses.
_line_is_mutating() { # stdin: one line's candidate tokens
  awk -v r="^(${READ_VERBS})$" '$0 ~ r { seen=1 } END { exit(seen ? 1 : 0) }'
}

# Code: the tokens of a spawn line are its quoted string literals.
_code_line_tokens() { grep -oE "${_Q}[^\"'\`]*${_Q}" <<<"$1" | tr -d "\"'\`"; }
# Shell: the whitespace-separated words of the command starting at `git`, up to the next separator.
_shell_line_tokens() { grep -oE "$SHELL_SPAWN_RE[^;&|\`)]*" <<<"$1" | tr ' \t' '\n\n'; }

derive_A() {
  local f line
  for f in $(git ls-files "${CODE_ROOTS[@]}" 2>/dev/null | grep -E '\.(ts|tsx|js|mjs|py)$'); do
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if _line_is_mutating <<<"$(_code_line_tokens "$line")"; then printf '%s\n' "$f"; break; fi
    done < <(_strip_code_data "$f" | grep -E "$CODE_SPAWN_RE" 2>/dev/null \
             | grep -vE '^[[:space:]]*(//|\*|#)')
  done
  for f in $(git ls-files "${SHELL_ROOTS[@]}" 2>/dev/null \
             | grep -E '/(([^/]*\.test\.sh)|(test[-_][^/]*\.sh))$'); do
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if _line_is_mutating <<<"$(_shell_line_tokens "$line")"; then printf '%s\n' "$f"; break; fi
    done < <(_strip_shell_data "$f" | grep -E "$SHELL_SPAWN_RE" 2>/dev/null \
             | grep -vE '^[[:space:]]*#')
  done
}

# --- derivation C: PARTIAL conversion within an adopted file --------------------------------------
#
# A and B are both FILE-granular: each emits a filename once and stops looking. That is correct for
# "was this suite converted at all", and structurally blind to "was it converted EVERYWHERE".
# Measured on this branch: removing ONE of the five `env: gitFixtureEnv(dir)` bindings in
# worktree-config-seed.test.ts left both derivations unchanged and the guard green, while a spawn in
# that file ran with a fully inherited environment.
#
# That is not a cosmetic gap. It is the exact shape of #7853 one level over: partial isolation greps
# identically to full isolation, so a static check for the helper's NAME reports clean on a file
# that leaks. Two prior per-call-site sweeps in this repo passed their own review for the same
# reason.
#
# So: for every CODE file that has adopted the helper at all, every mutating git-spawn line must
# carry an `env` binding. A spawn with no env argument whatsoever is unambiguously unprotected,
# which makes this precise rather than heuristic — it does not require guessing whether some
# in-scope identifier was bound from the helper, only that the caller passed SOMETHING.
#
# CODE only, deliberately. `git_fixture_env` exports into the calling shell rather than being passed
# per-invocation, so a shell spawn correctly carries no per-line env and this check would be
# nonsense there. The shell side is covered instead by the return-check assertion below.
# Matches BOTH `env: value` and the ES6 shorthand `{ cwd, env, encoding }`. Requiring the colon
# reported two shorthand call sites in git-fixture-env.test.ts as unprotected -- a false positive in
# the direction that matters, since it would have trained the next reader to dismiss this assertion.
readonly CODE_ENV_BINDING_RE='\benv([[:space:]]*[:,}]|[[:space:]]*$)'
# DIRECT spawn primitives only. Derivation A deliberately matches any callee taking a git argv,
# because a wrapper is still a spawn site for the purpose of "was this file converted". C asks a
# narrower question -- does THIS call pass an env -- and only a primitive takes an `env` option at
# all. Measured: including wrappers reported test/pre-merge-rebase.test.ts as partially converted
# because its own `spawnChecked(["git", ...], { cwd })` helper carries no env at the CALL site; the
# env is bound once inside the wrapper, which C then checks on the wrapper's own definition line.
readonly CODE_DIRECT_SPAWN_RE='\b(execFileSync|execSync|spawnSync|execFile|spawn|Bun\.spawn|Bun\.spawnSync)[[:space:]]*\('

# Counters go to a FILE, not shell variables. `derive_C` is consumed as `$(derive_C | sort -u)`,
# and command substitution runs it in a SUBSHELL: a variable incremented there is discarded, so the
# floor below would read 0 on every run and fire on a healthy tree. Measured -- it did exactly that.
_C_COUNTS="$(mktemp "$TMPDIR/g5-c-counts.XXXXXXXX")" || {
  printf '[FATAL] mktemp failed for derivation C counters\n' >&2; exit 2; }
printf '0 0\n' > "$_C_COUNTS"
_c_bump() { # $1=files delta  $2=spawns delta
  local f sp; read -r f sp < "$_C_COUNTS"
  printf '%d %d\n' "$((f + $1))" "$((sp + $2))" > "$_C_COUNTS"
}
derive_C() { # files in B that still contain an env-less mutating spawn
  # Scans a WINDOW, not a line. A spawn call is routinely written across several lines with the
  # `env:` binding on its own — checking only the line bearing the callee reports every multi-line
  # call as unprotected, which measured as 4 false positives out of 4 hits on the first cut.
  # The window ends at the call's closing `});`/`})` or after CALL_WINDOW lines, whichever is first.
  local f n line window
  local -r CALL_WINDOW=12
  # Reuse the ALREADY-COMPUTED B_SET rather than re-running derive_B. derive_B is a pure function of
  # the tracked tree and cannot change mid-run; recomputing it here measured 4.85 s of this suite's
  # 20.66 s (23%), for nothing.
  for f in $(printf '%s\n' "$B_SET" | grep -E '\.(ts|tsx|js|mjs)$'); do
    _c_bump 1 0
    # The helper's own implementation is not a consumer of itself.
    [[ "$f" == plugins/soleur/test/lib/git-fixture-env.ts ]] && continue
    while IFS=: read -r n line; do
      [[ -z "${n:-}" ]] && continue
      case "$line" in *//*|*'*'*) ;; esac
      _c_bump 0 1
      _line_is_mutating <<<"$(_code_line_tokens "$line")" || continue
      # Read forward from the callee line to the end of the CALL EXPRESSION, by paren depth.
      #
      # The obvious spelling -- `sed -n "$n,$endp" | sed -n '1,/})/p'` -- is WRONG, and wrong in the
      # silent direction. In a sed range the end-address is only searched from the line AFTER the
      # start, so a call that opens and closes on its own line does not terminate the window: it
      # runs on and picks up the NEXT call's `env:`. Measured on this branch -- reverting one of the
      # five bindings in worktree-config-seed.test.ts left a bare `execFileSync("git", ["init"...])`
      # that this check reported as protected, borrowing the `env:` of the `cfg()` call ten lines
      # below it. The whole point of derivation C is that exact mutation, so the guard was passing
      # over the only thing it was added to catch.
      #
      # Counting parens terminates on the real end of the expression in both shapes. Depth is only
      # counted from the callee line onward, and `awk` exits at depth 0 so a stray `)` later in the
      # file cannot extend the window.
      window="$(_strip_code_data "$f" | awk -v start="$n" -v maxlines="$CALL_WINDOW" '
        NR < start { next }
        { line = $0; print line
          n_open = gsub(/\(/, "(", line); n_close = gsub(/\)/, ")", line)
          depth += n_open - n_close
          if (NR > start && NR - start >= maxlines) exit
          if (depth <= 0) exit }')"
      if ! grep -qE "$CODE_ENV_BINDING_RE" <<<"$window"; then
        printf '%s\n' "$f"; break
      fi
    done < <(_strip_code_data "$f" | grep -nE "$CODE_DIRECT_SPAWN_RE" 2>/dev/null \
             | grep -vE ':[[:space:]]*(//|\*|#)')
  done
}

# --- derivation B: fixture-env helper CALL sites ---------------------------------------------------
#
# Independent of A: it reads CALL SYNTAX for the three siblings of the helper
# (plugins/soleur/test/lib/git-fixture-env.{ts,sh} and tests/scripts/_git_fixture_env.py), never a
# spawn shape and never an import line. An import is not adoption — a file can import the helper and
# still hand a bare `process.env` to the spawn, which is precisely the regression this guard exists
# to catch.
readonly CODE_HELPER_CALL_RE='\b(gitFixtureEnv|gitFixture|git_fixture_env)[[:space:]]*\('
readonly SHELL_HELPER_CALL_RE='(^|[;&|`]|\$\()[[:space:]]*git_fixture_env[[:space:]]+[^[:space:]]'

derive_B() {
  local f
  for f in $(git ls-files "${CODE_ROOTS[@]}" 2>/dev/null | grep -E '\.(ts|tsx|js|mjs|py)$'); do
    if [[ "$(_strip_code_data "$f" | grep -cE "$CODE_HELPER_CALL_RE")" != 0 ]]; then
      printf '%s\n' "$f"
    fi
  done
  for f in $(git ls-files "${SHELL_ROOTS[@]}" 2>/dev/null \
             | grep -E '/(([^/]*\.test\.sh)|(test[-_][^/]*\.sh))$'); do
    if [[ "$(_strip_shell_data "$f" | grep -cE "$SHELL_HELPER_CALL_RE")" != 0 ]]; then
      printf '%s\n' "$f"
    fi
  done
}

# --- the declared lists ----------------------------------------------------------------------------
#
# WAIVED — correct for their runtime, permanently. vitest runs on Node, where a deletion from
# `process.env` propagates to every child spawned afterwards, so a suite that scrubs the
# git-location family at module scope has already given every later spawn a clean environment.
# `agent-ready-git-worktree.test.ts` additionally sets GIT_DIR deliberately: the inherited
# git-location environment IS its subject, and handing it a fixture env would delete the test.
# Printed on every run, and each entry is checked for the `process.env` shape below so the waiver
# cannot rot into a blanket exemption.
readonly WAIVED=(
  apps/web-platform/test/workspace.test.ts
  apps/web-platform/test/workspace-auth-preflight.test.ts
  apps/web-platform/test/workspace-cleanup.test.ts
  apps/web-platform/test/workspace-error-handling.test.ts
  apps/web-platform/test/workspace-symlink-hardening.test.ts
  apps/web-platform/test/mu1-integration.test.ts
  apps/web-platform/test/server/agent-ready-git-worktree.test.ts
)

# DEFERRED — NOT correct; tracked, printed on every run, and ratcheted. Each entry must still be in
# the difference set, so converting one FORCES its line here to be deleted (a stale entry fails).
readonly DEFERRED=(
  # #7889 — still on `gitCleanEnv()`, which gives the prefix sweep and none of the identity,
  # ceiling or config hermeticity a fixture that WRITES needs. See the header for why these are
  # difference-set members and not waivers.
  plugins/soleur/test/gdpr-gate-repo-scan.test.ts
  plugins/soleur/test/web-platform-runtime-plugin-trigger.test.ts
  # Classifier boundary, not a real adoption gap: `git -C "$SCRIPT_DIR" tag --list 'vinngest-v*'`
  # is a READ through a verb that is mutating in every other mode. The classifier reads the verb
  # and is deliberately fail-closed, so this lands here rather than widening the read allowlist
  # into `tag`, which would exempt `git tag -a` everywhere.
  apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh
  # Classifier boundary, the other direction: `spawnSimple("git", ["definitely-not-a-git-subcommand"])`
  # is a deliberately UNCLASSIFIABLE verb — the suite's subject is git's own error path — and the
  # read allowlist structurally cannot exempt it. The neighbouring `["--version"]` spawn IS
  # classified read. Neither touches a fixture. Kept as a listed entry rather than special-cased,
  # because the honest statement is "the classifier is fail-closed and this is what that costs".
  apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts
)

# --- report ----------------------------------------------------------------------------------------
printf '=== Guard 5 — fixture-env adoption ===\n\n'

A_SET="$(derive_A | LC_ALL=C sort -u)"
B_SET="$(derive_B | LC_ALL=C sort -u)"
A_N=$(printf '%s' "$A_SET" | grep -c . || true)
B_N=$(printf '%s' "$B_SET" | grep -c . || true)

printf -- '--- derivation A: mutating git-spawn sites (%d) ---\n' "$A_N"
printf '%s\n' "$A_SET" | sed 's/^/    /'
printf -- '\n--- derivation B: fixture-env helper call sites (%d) ---\n' "$B_N"
printf '%s\n' "$B_SET" | sed 's/^/    /'
printf '\n'

# --- floors: one per derivation --------------------------------------------------------------------
# A derivation that matches nothing satisfies every set relation below for the wrong reason. These
# floors are what row M5 (make the git-spawn derivation match nothing) and row M6 of Guard 3's
# family fire against. The numbers are BELOW the measured population deliberately: they are a
# liveness floor, not a census, and a census would fail on every unrelated file addition.
readonly A_FLOOR=12
readonly B_FLOOR=10
if (( A_N >= A_FLOOR )); then
  pass "derivation A floor: $A_N mutating git-spawn sites (>= $A_FLOOR)"
else
  fail "derivation A floor: only $A_N mutating git-spawn sites (< $A_FLOOR) — the spawn-shape extractor matched (almost) nothing; every set assertion below is vacuous"
fi
if (( B_N >= B_FLOOR )); then
  pass "derivation B floor: $B_N helper call sites (>= $B_FLOOR)"
else
  fail "derivation B floor: only $B_N helper call sites (< $B_FLOOR) — the helper-call extractor matched (almost) nothing; every set assertion below is vacuous"
fi

# The two derivations must not be the same query wearing two hats. Equal cardinality is the
# signature of an accidentally-shared extractor, and it is also what makes a count comparison
# (harness row H1) read green over a swapped member.
if (( A_N != B_N )); then
  pass "the two derivations are independent: |A|=$A_N != |B|=$B_N, so a count comparison could not stand in for the difference below"
else
  fail "|A| == |B| == $A_N — check the two extractors have not collapsed into one query"
fi

# --- the difference, printed -----------------------------------------------------------------------
DIFF_SET="$(LC_ALL=C comm -23 <(printf '%s\n' "$A_SET" | LC_ALL=C sort -u) \
                              <(printf '%s\n' "$B_SET" | LC_ALL=C sort -u))"
DIFF_N=$(printf '%s' "$DIFF_SET" | grep -c . || true)

printf -- '\n--- DIFFERENCE A \\ B: spawns git, does not call the helper (%d) ---\n' "$DIFF_N"
if (( DIFF_N == 0 )); then
  printf '    (empty)\n'
else
  while IFS= read -r m; do
    [[ -z "$m" ]] && continue
    tag="UNACCOUNTED"
    for w in "${WAIVED[@]}";   do [[ "$w" == "$m" ]] && tag="waived"   && break; done
    [[ "$tag" == UNACCOUNTED ]] && for d in "${DEFERRED[@]}"; do [[ "$d" == "$m" ]] && tag="deferred" && break; done
    printf '    %-12s %s\n' "[$tag]" "$m"
  done <<<"$DIFF_SET"
fi

printf -- '\n--- declared waiver list (%d) — must PASS ---\n' "${#WAIVED[@]}"
printf '    %s\n' "${WAIVED[@]}"
printf -- '\n--- declared deferred list (%d) — tracked, must stay in the difference ---\n' "${#DEFERRED[@]}"
printf '    %s\n' "${DEFERRED[@]}"
printf '\n'

# --- assertion 1: nothing unaccounted in the difference --------------------------------------------
unaccounted=""
while IFS= read -r m; do
  [[ -z "$m" ]] && continue
  known=0
  for w in "${WAIVED[@]}";   do [[ "$w" == "$m" ]] && known=1 && break; done
  (( known )) || for d in "${DEFERRED[@]}"; do [[ "$d" == "$m" ]] && known=1 && break; done
  (( known )) || unaccounted+="$m"$'\n'
done <<<"$DIFF_SET"
if [[ -z "$unaccounted" ]]; then
  pass "every difference-set member is accounted for by the waiver or deferred list"
else
  fail "difference-set members accounted for by NEITHER list:"$'\n'"$(printf '%s' "$unaccounted" | sed 's/^/           /')"
fi

# --- assertion 2: the waiver is non-vacuous and has not rotted --------------------------------------
# Two independent ways a waiver list goes bad: it names a file that no longer exists (dead entry),
# or it names a file that never had the property the waiver claims (blanket exemption). Both checked
# — the second on the `process.env` deletion shape, which is the whole justification for the waiver.
for w in "${WAIVED[@]}"; do
  if [[ ! -f "$w" ]]; then
    fail "waived file does not exist: $w — delete the entry or fix the path"
  elif [[ "$(grep -cE 'delete[[:space:]]+process\.env\.GIT_[A-Z_]+|process\.env\.GIT_CEILING_DIRECTORIES[[:space:]]*=|process\.env\.GIT_DIR[[:space:]]*=' "$w")" == 0 ]]; then
    fail "waived file carries no process.env git-scrub: $w — the waiver's stated justification is false for it"
  else
    pass "waiver justified by a real process.env git-scrub: $w"
  fi
done
# The waiver must be load-bearing: at least some of it must actually be suppressing a difference-set
# member. A waiver list that suppresses nothing is decoration, and decoration is what a reviewer
# reads as coverage. (Harness row H2 asserts these PASS; this asserts they are being exercised.)
waived_in_diff=0
for w in "${WAIVED[@]}"; do
  [[ "$(printf '%s\n' "$DIFF_SET" | grep -cxF "$w")" != 0 ]] && waived_in_diff=$((waived_in_diff+1))
done
if (( waived_in_diff >= 2 )); then
  pass "waiver list is load-bearing: $waived_in_diff of ${#WAIVED[@]} entries are suppressing a live difference-set member"
else
  fail "waiver list suppresses only $waived_in_diff member(s) — it has stopped doing work; re-derive it or delete it"
fi

# --- assertion 3: no stale deferred entry (the ratchet) ---------------------------------------------
for d in "${DEFERRED[@]}"; do
  if [[ ! -f "$d" ]]; then
    fail "deferred file does not exist: $d — delete the entry"
  elif [[ "$(printf '%s\n' "$DIFF_SET" | grep -cxF "$d")" == 0 ]]; then
    fail "deferred entry is STALE: $d is no longer in the difference set — it has been converted; delete its line (ratchet)"
  else
    pass "deferred entry still live: $d"
  fi
done

# --- assertion 4: every shell helper call checks its return ------------------------------------------
# `git_fixture_env` returns non-zero WITHOUT EXPORTING ANYTHING when the ceiling would be
# unenforceable. An unchecked call therefore proceeds with the caller's own hostile environment while
# reading exactly like protection — the silent degradation the helper was written to prevent. The
# check is on the SAME LINE as the call: `||` or `&&`, or an `if`/`while` head.
call_sites=0
unchecked=""
for f in $(git ls-files "${SHELL_ROOTS[@]}" 2>/dev/null \
           | grep -E '/(([^/]*\.test\.sh)|(test[-_][^/]*\.sh))$'); do
  while IFS= read -r ln; do
    [[ -z "$ln" ]] && continue
    call_sites=$((call_sites+1))
    body="${ln#*:}"
    if [[ "$body" != *"||"* && "$body" != *"&&"* && ! "$body" =~ ^[[:space:]]*(if|while|until)[[:space:]] ]]; then
      unchecked+="$f:$ln"$'\n'
    fi
  done < <(_strip_shell_calls "$f" | grep -nE "$SHELL_HELPER_CALL_RE" 2>/dev/null)
done
readonly CALL_SITE_FLOOR=10
if (( call_sites >= CALL_SITE_FLOOR )); then
  pass "return-check derivation floor: $call_sites shell git_fixture_env call sites (>= $CALL_SITE_FLOOR)"
else
  fail "return-check derivation floor: only $call_sites shell call sites (< $CALL_SITE_FLOOR) — the call-site extractor matched (almost) nothing, so the check below is vacuous"
fi
if [[ -z "$unchecked" ]]; then
  pass "all $call_sites shell git_fixture_env call sites check the return value"
else
  fail "shell git_fixture_env call sites with NO return check (a refusal exports nothing and is silently ignored):"$'\n'"$(printf '%s' "$unchecked" | sed 's/^/           /')"
fi

# --- the out-of-scope shell root: counted, printed, ratcheted ----------------------------------------
# NOT part of the difference set above, and NOT hidden. Phase 2 did not cover plugins/soleur/test's
# shell suites; ~20 of them `git init` a fixture and never call the builder. They source
# test-helpers.sh, so the #7833 tripwire IS armed for them (they cannot run under an inherited
# git-location environment) — but the builder's ceiling, identity and config hermeticity are absent.
# Recorded as a ceiling on the count, so the number can only go down. A count ceiling is swap-blind
# by construction; that is a stated limitation, not an oversight — closing it means bringing this
# root into scope, which is a conversion PR, not a guard change.
OUT_SET=""
for f in $(git ls-files "${OUT_OF_SCOPE_SHELL_ROOTS[@]}" 2>/dev/null \
           | grep -E '/(([^/]*\.test\.sh)|(test[-_][^/]*\.sh))$'); do
  [[ "$(_strip_shell_data "$f" | grep -cE "$SHELL_HELPER_CALL_RE")" != 0 ]] && continue
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if _line_is_mutating <<<"$(_shell_line_tokens "$line")"; then OUT_SET+="$f"$'\n'; break; fi
  done < <(_strip_shell_data "$f" | grep -E "$SHELL_SPAWN_RE" 2>/dev/null | grep -vE '^[[:space:]]*#')
done
OUT_N=$(printf '%s' "$OUT_SET" | grep -c . || true)
printf -- '\n--- OUT OF SCOPE, counted and ratcheted: plugins/soleur/test shell suites that\n'
printf -- '    mutate git without the builder (%d; tripwire armed via test-helpers.sh) ---\n' "$OUT_N"
printf '%s' "$OUT_SET" | sed 's/^/    /'
printf '\n'
readonly OUT_CEILING=20
if (( OUT_N <= OUT_CEILING )); then
  pass "out-of-scope unconverted count $OUT_N <= ceiling $OUT_CEILING (ratchet: lower the ceiling when you convert one)"
else
  fail "out-of-scope unconverted count $OUT_N EXCEEDS ceiling $OUT_CEILING — a new plugins/soleur/test shell suite mutates git with no fixture env; convert it or raise the ceiling with a reason"
fi

# --- verdict -----------------------------------------------------------------------------------------
# --- partial-conversion check (derivation C) ------------------------------------------------------
PARTIAL="$(derive_C | sort -u)"
PARTIAL_N=$(printf '%s' "$PARTIAL" | grep -c . || true)
# Derivation C's OWN non-vacuity floor (A, B and the return-check each carry one; C did not).
# Without it, two independent one-line edits flip a genuinely RED tree green with the assertion count
# unchanged, so MIN_ASSERTIONS never notices: narrowing CODE_DIRECT_SPAWN_RE to match nothing, or
# widening CODE_ENV_BINDING_RE to match everything. Both were measured surviving.
#
# Floors the WORK DONE, not the findings: a clean run and a run that scanned nothing are otherwise
# byte-identical. Derived from the current tree (14 code files in B, 40+ direct spawn sites) with
# headroom for ordinary shrinkage, and it is a floor rather than an equality so converting a suite
# does not red it.
# NON-VACUITY CONTROL for derivation C's predicate pair.
#
# The scan floors below prove C LOOKED at something; they cannot prove it can still DISCRIMINATE.
# Measured: widening CODE_ENV_BINDING_RE to match everything leaves both floors satisfied (the scan
# happened, it just concluded wrongly) and flips a genuinely partial tree green. A floor counts work
# done; only a known-unprotected input proves the predicate still says NO.
#
# Two synthetic lines, run through the SAME two regexes the real derivation uses -- not a
# reimplementation, or this would drift from what it certifies.
_c_control() {
  local unprotected='  execFileSync("git", ["init", dir], { cwd: dir });'
  local protected='  execFileSync("git", ["init", dir], { cwd: dir, env: gitFixtureEnv(dir) });'
  local must_flag=0 must_pass=0
  grep -qE "$CODE_DIRECT_SPAWN_RE" <<<"$unprotected" \
    && ! grep -qE "$CODE_ENV_BINDING_RE" <<<"$unprotected" && must_flag=1
  grep -qE "$CODE_DIRECT_SPAWN_RE" <<<"$protected" \
    && grep -qE "$CODE_ENV_BINDING_RE" <<<"$protected" && must_pass=1
  if (( must_flag == 1 && must_pass == 1 )); then
    pass "derivation C control: an env-less spawn is flagged AND an env-bound spawn is not"
  else
    fail "derivation C control FAILED (flags-unprotected=$must_flag accepts-protected=$must_pass) -- the predicate pair no longer discriminates, so the partial-conversion assertion is vacuous whatever it reports"
  fi
}
_c_control

read -r _C_FILES_SCANNED _C_SPAWNS_SCANNED < "$_C_COUNTS"
rm -f "$_C_COUNTS"
readonly C_FILE_FLOOR=8
readonly C_SPAWN_FLOOR=20
if (( _C_FILES_SCANNED < C_FILE_FLOOR )); then
  fail "derivation C scanned only $_C_FILES_SCANNED code files (floor $C_FILE_FLOOR) -- its population collapsed, so the partial-conversion assertion below is vacuous"
elif (( _C_SPAWNS_SCANNED < C_SPAWN_FLOOR )); then
  fail "derivation C examined only $_C_SPAWNS_SCANNED direct spawn sites (floor $C_SPAWN_FLOOR) -- CODE_DIRECT_SPAWN_RE matches (almost) nothing, so a partial conversion cannot be seen"
else
  pass "derivation C scanned $_C_FILES_SCANNED files / $_C_SPAWNS_SCANNED spawn sites (floors $C_FILE_FLOOR / $C_SPAWN_FLOOR)"
fi

if [[ "$PARTIAL_N" -eq 0 ]]; then
  pass "no adopted CODE file still spawns git with no env binding (partial conversion)"
else
  fail "PARTIALLY converted — these adopted files still spawn git with no env binding:"
  printf '%s\n' "$PARTIAL" | sed 's/^/        /'
fi

printf '\n=== %d passed, %d failed, %d assertions ===\n' "$PASS" "$FAIL" "$ASSERTIONS"

# Assertion-count floor. Reported with printf and exit, NEVER through fail() — this backstops fail()
# and the counters it maintains (ADR-193). Deleting the body of any loop above leaves the counters
# untouched and this guard would otherwise read "0 failed" over a tree it never examined.
readonly MIN_ASSERTIONS=22
if (( ASSERTIONS < MIN_ASSERTIONS )); then
  printf '\nFATAL: only %d assertions ran (expected >= %d).\n' "$ASSERTIONS" "$MIN_ASSERTIONS" >&2
  printf 'A guard that reports "0 failed" after running almost nothing is worse than no guard.\n' >&2
  exit 1
fi

(( FAIL == 0 )) || exit 1
exit 0
