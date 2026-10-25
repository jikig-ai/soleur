#!/usr/bin/env bash
# merge-effect-class.test.sh - behavioural suite for merge-effect-class.sh (#10923, ADR-297).
#
# What it pins: the exit/stdout contract (exit 0 only for not-production-effecting; stdout is
# production-effecting on exit 1 and exit 2), the closed-world allowlist, the --pr wrapper against a gh fake
# that accepts exactly the modelled argv, the applicability sentinel, the consumer text in operator-holds.md,
# and six executable mutants (marker lines `# mut:<name>` in the script).
# Harness rules: a stub SUT that exits 0 with no output must turn the suite RED; a crashed mutant is not a
# killed one; every verdict helper has a control proving it can still reject; the minimum-assertion floor
# is reported with printf + exit, never through the helpers it backstops.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${MEC_SUT:-$HERE/merge-effect-class.sh}"
OPHOLDS="$HERE/../skills/ship/references/operator-holds.md"
PARITY="$HERE/../test/merge-effect-class-parity.test.sh"
PASS=0
FAIL=0
FLOOR=190

ok() { PASS=$((PASS + 1)); }
bad() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1" >&2
}
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then ok; else bad "$1 (got [$2], want [$3])"; fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/mec-test.XXXXXXXX")" || exit 2
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# ── helpers ────────────────────────────────────────────────────────────────────────────────────
R_OUT=""; R_ERR=""; R_RC=0
run_sut() { # run_sut <sut> args... (stdin passed through)
  local sut="$1"
  shift
  R_RC=0
  bash "$sut" "$@" >"$TMP/o" 2>"$TMP/e" || R_RC=$?
  R_OUT="$(cat "$TMP/o")"
  R_ERR="$(cat "$TMP/e")"
}
files_run() { # files_run <list text exactly as given>
  printf '%s' "$1" >"$TMP/list"
  run_sut "$SUT" --files-from "$TMP/list"
}
NOT="not-production-effecting"
EFF="production-effecting"
expect() { # expect <name> <rc> <stdout> <list text>
  files_run "$4"
  if [ "$R_RC" = "$2" ] && [ "$R_OUT" = "$3" ]; then ok; else bad "$1 (rc=$R_RC out=[$R_OUT], want rc=$2 out=[$3])"; fi
}

# Instrument self-test: every verdict-owning helper must be able to REJECT. Each control drives the helper
# with an input that must fail, requires its failure counter to move, then unwinds the counters so the floor
# stays exact. Reported with printf + exit, never through the helpers under test.
control() { # control <name> <command...>: the command must move FAIL
  local name="$1" f0="$FAIL" p0="$PASS"
  shift
  "$@" 2>/dev/null
  if [ "$FAIL" -le "$f0" ]; then
    printf 'FATAL: verdict helper control [%s] did not reject a bad input\n' "$name" >&2
    exit 2
  fi
  FAIL=$f0
  PASS=$((p0 + 1))
}
control "check" check ctl a b
control "expect (wrong rc)" expect ctl 9 "$EFF" $'apps/x.ts\n'
control "expect (wrong stdout)" expect ctl 1 "$NOT" $'apps/x.ts\n'

# ── 1. the exit and stdout contract, table-driven ─────────────────────────────────────────────
expect "kb+root md is safe" 0 "$NOT" $'knowledge-base/a/b.md\nREADME.md\n'
expect "deep kb path with spaces and non-ASCII is safe" 0 "$NOT" $'knowledge-base/project/deep path/\xc3\xa9 notes.md\n'
expect "CHANGELOG.md is safe" 0 "$NOT" $'CHANGELOG.md\n'
expect "README.md alone is safe" 0 "$NOT" $'README.md\n'
expect "kb non-md file is safe" 0 "$NOT" $'knowledge-base/project/diagram.png\n'
expect "app path is effecting" 1 "$EFF" $'knowledge-base/a/b.md\nREADME.md\napps/web-platform/x.ts\n'
expect "unsafe path in the middle of the list" 1 "$EFF" $'knowledge-base/a.md\napps/x.ts\nREADME.md\n'
expect "apps/x/README.md is effecting" 1 "$EFF" $'apps/x/README.md\n'
expect "docs/legal terms is effecting" 1 "$EFF" $'docs/legal/terms.md\n'
expect "plugins docs md is effecting" 1 "$EFF" $'plugins/soleur/docs/x.md\n'
expect "AGENTS.md is effecting" 1 "$EFF" $'AGENTS.md\n'
expect "AGENTS.rules.md is effecting" 1 "$EFF" $'AGENTS.rules.md\n'
expect "CLAUDE.md is effecting" 1 "$EFF" $'CLAUDE.md\n'
expect "kb nested CLAUDE.md is effecting" 1 "$EFF" $'knowledge-base/x/CLAUDE.md\n'
expect "kb nested AGENTS.md is effecting" 1 "$EFF" $'knowledge-base/AGENTS.md\n'
expect "lowercase agents.md is effecting" 1 "$EFF" $'agents.md\n'
expect "mixed-case Agents.md is effecting" 1 "$EFF" $'Agents.md\n'
expect "nested lowercase claude.md is effecting" 1 "$EFF" $'knowledge-base/x/claude.md\n'
expect "CLAUDE.local.md is effecting" 1 "$EFF" $'CLAUDE.local.md\n'
expect "GEMINI.md is effecting" 1 "$EFF" $'GEMINI.md\n'
expect "unknown top-level path is effecting" 1 "$EFF" $'zzz-unknown\n'
expect "LICENSE is effecting" 1 "$EFF" $'LICENSE\n'
expect "root package.json is effecting" 1 "$EFF" $'package.json\n'
expect "root bun.lock is effecting" 1 "$EFF" $'bun.lock\n'
expect "root Dockerfile is effecting" 1 "$EFF" $'Dockerfile\n'
expect "root build.md.sh is effecting" 1 "$EFF" $'build.md.sh\n'
expect "root notes.mdx is effecting" 1 "$EFF" $'notes.mdx\n'
expect "root run.cmd is effecting" 1 "$EFF" $'run.cmd\n'
expect "workflow file is effecting" 1 "$EFF" $'.github/workflows/ci.yml\n'
expect "the script itself is effecting" 1 "$EFF" $'plugins/soleur/scripts/merge-effect-class.sh\n'
expect "kb lookalike prefix is effecting" 1 "$EFF" $'knowledge-base-evil/x.md\n'
expect "scripts dir is effecting" 1 "$EFF" $'scripts/x.sh\n'
expect "rename: safe old side, effecting new side" 1 "$EFF" $'knowledge-base/a.md\napps/x.ts\n'
expect "rename: effecting old side, safe new side" 1 "$EFF" $'apps/x.ts\nknowledge-base/a.md\n'
expect "unterminated final line is still judged" 1 "$EFF" $'knowledge-base/a.md\napps/x.ts'
expect "unterminated safe final line is safe" 0 "$NOT" $'knowledge-base/a.md\nREADME.md'
expect "unterminated malformed final line is unusable" 2 "$EFF" $'knowledge-base/a.md\nknowledge-base/../apps/x.ts'
expect "forged verdict as a path reads effecting" 1 "$EFF" $'not-production-effecting\n'
expect "empty input is unusable" 2 "$EFF" ''
expect "blank line is unusable" 2 "$EFF" $'knowledge-base/a.md\n\nREADME.md\n'
expect "dotdot is unusable" 2 "$EFF" $'knowledge-base/../apps/x.ts\n'
expect "single dot segment is unusable" 2 "$EFF" $'knowledge-base/./a.md\n'
expect "leading ./ is unusable" 2 "$EFF" $'./README.md\n'
expect "leading slash is unusable" 2 "$EFF" $'/etc/passwd.md\n'
expect "empty segment is unusable" 2 "$EFF" $'knowledge-base//a.md\n'
expect "trailing slash is unusable" 2 "$EFF" $'knowledge-base/\n'
expect "backslash is unusable" 2 "$EFF" $'knowledge-base\\a.md\n'
expect "CR is unusable" 2 "$EFF" $'knowledge-base/a.md\r\n'
expect "tab is unusable" 2 "$EFF" $'knowledge-base/a\tb.md\n'
expect "git-quoted path is unusable" 2 "$EFF" $'"knowledge-base/caf\\303\\251.md"\n'
expect "bad path after an effecting one still exits 2" 2 "$EFF" $'apps/x.ts\n\n'

# a NUL byte would be dropped by `read` and join two paths into one; it is refused outright
printf 'knowledge-base/a\000../x\n' >"$TMP/list"
run_sut "$SUT" --files-from "$TMP/list"
check "NUL in a path: rc" "$R_RC" 2
check "NUL in a path: stdout" "$R_OUT" "$EFF"
case "$R_ERR" in *"reason=bad-path"*) ok ;; *) bad "NUL in a path: reason token [$R_ERR]" ;; esac

# nonexistent / unreadable list, usage and mode errors
run_sut "$SUT"
check "no args: rc" "$R_RC" 2
check "no args: stdout" "$R_OUT" "$EFF"
run_sut "$SUT" --bogus
check "unknown flag: rc" "$R_RC" 2
check "unknown flag: stdout" "$R_OUT" "$EFF"
run_sut "$SUT" --files-from
check "--files-from without operand: rc" "$R_RC" 2
run_sut "$SUT" --pr abc
check "--pr non-numeric: rc" "$R_RC" 2
check "--pr non-numeric: stdout" "$R_OUT" "$EFF"
case "$R_ERR" in *"reason=usage"*) ok ;; *) bad "--pr non-numeric: reason token [$R_ERR]" ;; esac
run_sut "$SUT" --files-from "$TMP/does-not-exist"
check "unreadable list: rc" "$R_RC" 2
check "unreadable list: stdout" "$R_OUT" "$EFF"
case "$R_ERR" in *"reason=list-unreadable"*) ok ;; *) bad "unreadable list reason token [$R_ERR]" ;; esac

# stdin form, exactly one stdout line, reason token, no path echo
printf 'knowledge-base/a.md\n' | bash "$SUT" --files-from - >"$TMP/o" 2>"$TMP/e"
check "stdin list: stdout" "$(cat "$TMP/o")" "$NOT"
check "stdin list: stdout line count" "$(wc -l <"$TMP/o" | tr -d ' ')" 1
files_run $'apps/web-platform/secret-looking-name.ts\n'
case "$R_ERR" in *"merge-effect-class: production-effecting reason=outside-allowlist"*) ok ;; *) bad "stderr line shape [$R_ERR]" ;; esac
case "$R_OUT$R_ERR" in *secret-looking-name*) bad "a path was echoed" ;; *) ok ;; esac
files_run $'knowledge-base/a.md\n'
case "$R_ERR" in *"merge-effect-class: not-production-effecting reason=allowlisted"*) ok ;; *) bad "allowlisted stderr shape [$R_ERR]" ;; esac
files_run $'zzz\xc3\xa9-leaky.ts\n'
case "$R_OUT$R_ERR" in *leaky*) bad "a non-ASCII path was echoed" ;; *) ok ;; esac

# a failed stdout write must not read as a verdict: a full device exits 2
R_RC=0
printf 'knowledge-base/a.md\n' >"$TMP/list"
bash "$SUT" --files-from "$TMP/list" >/dev/full 2>/dev/null || R_RC=$?
check "stdout on /dev/full exits 2" "$R_RC" 2

# ── 2. witnesses, filter, self-check ──────────────────────────────────────────────────────────
run_sut "$SUT" --print-witnesses
check "witnesses: rc" "$R_RC" 0
WITNESSES="$R_OUT"
if [ "$(printf '%s\n' "$WITNESSES" | grep -c .)" -ge 2 ]; then ok; else bad "witnesses: expected at least two lines"; fi
while IFS= read -r w; do
  [ -n "$w" ] || continue
  files_run "$w"$'\n'
  check "witness [$w] reads safe" "$R_OUT/$R_RC" "$NOT/0"
done <<<"$WITNESSES"

printf 'knowledge-base/a.md\napps/x.ts\nREADME.md\nAGENTS.md\n\nknowledge-base/../x.md\nknowledge-base/b.md\n' >"$TMP/list"
run_sut "$SUT" --filter-allowed <"$TMP/list"
check "filter-allowed: rc" "$R_RC" 0
check "filter-allowed: admitted paths only" "$R_OUT" $'knowledge-base/a.md\nREADME.md\nknowledge-base/b.md'

run_sut "$SUT" --self-check
check "self-check: stdout" "$R_OUT" "self-check=ok"
check "self-check: rc" "$R_RC" 0
printf 'ci.yml\t\n' >"$TMP/empty-reason.tsv"
MEC_CI_ONLY_LIST="$TMP/empty-reason.tsv" run_sut "$SUT" --self-check
check "self-check with an empty reason: stdout" "$R_OUT" "self-check=FAILED"
check "self-check with an empty reason: rc" "$R_RC" 1
printf 'ci.yml\t   \n' >"$TMP/blank-reason.tsv"
MEC_CI_ONLY_LIST="$TMP/blank-reason.tsv" run_sut "$SUT" --self-check
check "self-check with a whitespace reason: stdout" "$R_OUT" "self-check=FAILED"
MEC_CI_ONLY_LIST="$TMP/missing.tsv" run_sut "$SUT" --self-check
check "self-check with a missing list: stdout" "$R_OUT" "self-check=FAILED"

# the section-1 and section-2 rows are all a nested stub-SUT run needs to turn red
if [ -n "${MEC_NESTED:-}" ]; then
  printf '%s passed, %s failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ] && exit 0
  exit 1
fi

# ── 3. --pr against a gh fake that accepts exactly the modelled argv ──────────────────────────
mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
fx="${MEC_FX:?}"
printf '%s\n' "$*" >>"$fx/calls"
case "$*" in
  "pr view "[0-9]*" --json state,baseRefName,headRefOid,changedFiles")
    [ ! -f "$fx/pr.rc" ] || exit "$(cat "$fx/pr.rc")"
    cat "$fx/pr.json" ;;
  "pr view "[0-9]*" --json headRefOid")
    cat "$fx/head2.json" ;;
  "api --paginate --slurp repos/{owner}/{repo}/pulls/"[0-9]*"/files?per_page=100")
    [ ! -f "$fx/files.rc" ] || exit "$(cat "$fx/files.rc")"
    cat "$fx/files.json" ;;
  "repo view --json nameWithOwner")
    [ ! -f "$fx/repo.rc" ] || exit "$(cat "$fx/repo.rc")"
    cat "$fx/repo.json" ;;
  *) echo "gh-fake: unmodelled argv: $*" >&2; exit 64 ;;
esac
GHEOF
chmod +x "$TMP/bin/gh"

SHA_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SHA_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

mkrepo() { # mkrepo <dir> <with-sentinel 1|0> <with-list 1|0>
  mkdir -p "$1"
  (
    cd "$1" || exit 1
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.invalid
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CEILING_DIRECTORIES
    git init -q . || exit 1
    echo seed >seed.txt
    if [ "$2" = 1 ]; then mkdir -p .github/workflows && echo "name: x" >.github/workflows/web-platform-release.yml; fi
    if [ "$3" = 1 ]; then mkdir -p plugins/soleur/scripts && printf 'ci.yml\ta reason\n' >plugins/soleur/scripts/merge-effect-class.ci-only.tsv; fi
    git add -A && git commit -q -m seed
  )
}
mkrepo "$TMP/repo-ok" 1 1
mkrepo "$TMP/repo-nosentinel" 0 1
mkrepo "$TMP/repo-nolist" 1 0
mkrepo "$TMP/repo-untracked-list" 1 0
mkdir -p "$TMP/repo-untracked-list/plugins/soleur/scripts"
printf 'ci.yml\ta reason\n' >"$TMP/repo-untracked-list/plugins/soleur/scripts/merge-effect-class.ci-only.tsv"

fx() { # fx <state> <base> <head> <changed> <files json (slurped)> [head2]
  rm -rf "$TMP/fx" && mkdir -p "$TMP/fx"
  printf '{"state":"%s","baseRefName":"%s","headRefOid":"%s","changedFiles":%s}\n' "$1" "$2" "$3" "$4" >"$TMP/fx/pr.json"
  printf '%s\n' "$5" >"$TMP/fx/files.json"
  printf '{"headRefOid":"%s"}\n' "${6:-$3}" >"$TMP/fx/head2.json"
  printf '{"nameWithOwner":"acme/widgets"}\n' >"$TMP/fx/repo.json"
}
PR_SUT="$SUT"
pr_run() { # pr_run <repo dir> args...   (runs PR_SUT with the gh fake first on PATH)
  local repo="$1"
  shift
  R_RC=0
  (cd "$repo" && PATH="$TMP/bin:$PATH" MEC_FX="$TMP/fx" bash "$PR_SUT" "$@") >"$TMP/o" 2>"$TMP/e" || R_RC=$?
  R_OUT="$(cat "$TMP/o")"
  R_ERR="$(cat "$TMP/e")"
}
pr_expect() { # pr_expect <name> <rc> <stdout> <reason token> <repo> args...
  local name="$1" rc="$2" out="$3" reason="$4" repo="$5"
  shift 5
  pr_run "$repo" "$@"
  if [ "$R_RC" = "$rc" ] && [ "$R_OUT" = "$out" ]; then ok; else bad "$name (rc=$R_RC out=[$R_OUT], want rc=$rc out=[$out])"; fi
  case "$R_ERR" in *"reason=$reason"*) ok ;; *) bad "$name: reason token [$R_ERR], want $reason" ;; esac
}
ONE_SAFE='[[{"filename":"README.md","status":"modified"}]]'

PAGE1='[{"filename":"knowledge-base/a.md","status":"modified"},{"filename":"README.md","status":"modified"}]'
PAGE2='[{"filename":"knowledge-base/b.md","status":"added"}]'
fx OPEN main "$SHA_A" 3 "[$PAGE1,$PAGE2]"
pr_expect "--pr two-page safe list" 0 "$NOT" allowlisted "$TMP/repo-ok" --pr 7
case "$R_ERR" in *"sha=$SHA_A"*) ok ;; *) bad "--pr prints the head sha [$R_ERR]" ;; esac
check "--pr gh call shapes" "$(cat "$TMP/fx/calls")" "$(printf 'pr view 7 --json state,baseRefName,headRefOid,changedFiles\napi --paginate --slurp repos/{owner}/{repo}/pulls/7/files?per_page=100\npr view 7 --json headRefOid')"

fx OPEN main "$SHA_A" 2 '[[{"filename":"knowledge-base/a.md","status":"modified"},{"filename":"apps/web-platform/x.ts","status":"modified"}]]'
pr_expect "--pr list with an app file" 1 "$EFF" outside-allowlist "$TMP/repo-ok" --pr 7

fx OPEN main "$SHA_A" 1 '[[{"filename":"knowledge-base/new.md","previous_filename":"knowledge-base/old.md","status":"renamed"}]]'
pr_expect "--pr kb-internal rename is safe" 0 "$NOT" allowlisted "$TMP/repo-ok" --pr 7
fx OPEN main "$SHA_A" 1 '[[{"filename":"knowledge-base/x.md","previous_filename":"apps/x.ts","status":"renamed"}]]'
pr_expect "--pr rename from app into kb is effecting" 1 "$EFF" outside-allowlist "$TMP/repo-ok" --pr 7
fx OPEN main "$SHA_A" 1 '[[{"filename":"knowledge-base/x.md","status":"renamed"}]]'
pr_expect "--pr rename without previous_filename is unusable" 2 "$EFF" list-unreadable "$TMP/repo-ok" --pr 7
fx OPEN main "$SHA_A" 1 '[[{"filename":"README.md","status":"modified","previous_filename":5}]]'
pr_expect "--pr non-string previous_filename is unusable" 2 "$EFF" list-unreadable "$TMP/repo-ok" --pr 7

fx MERGED main "$SHA_A" 1 "$ONE_SAFE"
pr_expect "--pr merged" 2 "$EFF" not-open "$TMP/repo-ok" --pr 7
fx CLOSED main "$SHA_A" 1 "$ONE_SAFE"
pr_expect "--pr closed" 2 "$EFF" not-open "$TMP/repo-ok" --pr 7
fx OPEN develop "$SHA_A" 1 "$ONE_SAFE"
pr_expect "--pr base develop" 2 "$EFF" base-mismatch "$TMP/repo-ok" --pr 7
fx OPEN release/x "$SHA_A" 1 "$ONE_SAFE"
pr_expect "--pr base release/x" 2 "$EFF" base-mismatch "$TMP/repo-ok" --pr 7
fx OPEN main-evil "$SHA_A" 1 "$ONE_SAFE"
pr_expect "--pr base main-evil" 2 "$EFF" base-mismatch "$TMP/repo-ok" --pr 7
fx OPEN main "$SHA_A" 1 "$ONE_SAFE" "$SHA_B"
pr_expect "--pr head moved between reads" 2 "$EFF" head-moved "$TMP/repo-ok" --pr 7

# the 3000 cap and the count compare, each on its own boundary
BIG2999="$(jq -c -n '[[range(2999) | {filename: "knowledge-base/f\(.).md", status: "added"}]]')"
BIG3000="$(jq -c -n '[[range(3000) | {filename: "knowledge-base/f\(.).md", status: "added"}]]')"
BIG3001="$(jq -c -n '[[range(3001) | {filename: "knowledge-base/f\(.).md", status: "added"}]]')"
fx OPEN main "$SHA_A" 2999 "$BIG2999"
pr_expect "--pr 2999 of 2999 files is judged" 0 "$NOT" allowlisted "$TMP/repo-ok" --pr 7
fx OPEN main "$SHA_A" 3000 "$BIG3000"
pr_expect "--pr 3000 of 3000 files hits the cap" 2 "$EFF" incomplete-list "$TMP/repo-ok" --pr 7
fx OPEN main "$SHA_A" 3001 "$BIG3001"
pr_expect "--pr 3001 of 3001 files hits the cap" 2 "$EFF" incomplete-list "$TMP/repo-ok" --pr 7
fx OPEN main "$SHA_A" 5 "[$PAGE1,$PAGE2]"
pr_expect "--pr fewer entries than changedFiles" 2 "$EFF" incomplete-list "$TMP/repo-ok" --pr 7
fx OPEN main "$SHA_A" 1 "[$PAGE1,$PAGE2]"
pr_expect "--pr more entries than changedFiles" 2 "$EFF" incomplete-list "$TMP/repo-ok" --pr 7

# a non-integer changedFiles must never skip the count guard
for cf in '"x"' null '"1"' 1.5 -1; do
  fx OPEN main "$SHA_A" "$cf" "$ONE_SAFE"
  pr_expect "--pr changedFiles=$cf" 2 "$EFF" list-unreadable "$TMP/repo-ok" --pr 7
done

# the head sha is exactly 40 lowercase hex characters
for sha in "short" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"; do
  fx OPEN main "$sha" 1 "$ONE_SAFE"
  pr_expect "--pr head sha [$sha]" 2 "$EFF" list-unreadable "$TMP/repo-ok" --pr 7
done

fx OPEN main "$SHA_A" 1 'not json'
pr_expect "--pr unparseable files body" 2 "$EFF" list-unreadable "$TMP/repo-ok" --pr 7
fx OPEN main "$SHA_A" 1 "$ONE_SAFE"
echo 1 >"$TMP/fx/pr.rc"
pr_expect "--pr gh pr view failure" 2 "$EFF" list-unreadable "$TMP/repo-ok" --pr 7
fx OPEN main "$SHA_A" 1 "$ONE_SAFE"
echo 1 >"$TMP/fx/files.rc"
pr_expect "--pr gh files failure" 2 "$EFF" list-unreadable "$TMP/repo-ok" --pr 7
fx OPEN main "$SHA_A" 1 '[[{"filename":"knowledge-base/a\nb.md","status":"modified"}]]'
pr_expect "--pr filename holding a newline is unusable" 2 "$EFF" bad-path "$TMP/repo-ok" --pr 7
fx OPEN main "$SHA_A" 2 '[[{"filename":"knowledge-base/a\nb.md","status":"modified","previous_filename":5},{"filename":"README.md","status":"modified"}]]'
pr_expect "--pr malformed entry beside a newline filename never skips the control-char guard" 2 "$EFF" list-unreadable "$TMP/repo-ok" --pr 7

# applicability: temp repos built by the suite
fx OPEN main "$SHA_A" 1 "$ONE_SAFE"
pr_expect "--pr outside the sentinel repo" 2 "$EFF" not-applicable "$TMP/repo-nosentinel" --pr 7
pr_expect "--pr without a tracked ci-only list" 2 "$EFF" not-applicable "$TMP/repo-nolist" --pr 7
pr_expect "--pr with an untracked ci-only list" 2 "$EFF" not-applicable "$TMP/repo-untracked-list" --pr 7
pr_expect "--pr --repo naming another repository" 2 "$EFF" not-applicable "$TMP/repo-ok" --pr 7 --repo other/repo
pr_expect "--pr --repo equal to the current repository" 0 "$NOT" allowlisted "$TMP/repo-ok" --pr 7 --repo acme/widgets
echo 1 >"$TMP/fx/repo.rc"
pr_expect "--pr --repo when the repo name cannot be read" 2 "$EFF" not-applicable "$TMP/repo-ok" --pr 7 --repo acme/widgets
run_sut "$SUT" --pr 7 --repo notaslug
check "--pr bad --repo form: rc" "$R_RC" 2

# the gh fake refuses an unmodelled shape (so a mutated call shape reds)
R_RC=0
(PATH="$TMP/bin:$PATH" MEC_FX="$TMP/fx" gh pr list >/dev/null 2>"$TMP/e") || R_RC=$?
check "gh fake refuses unmodelled argv" "$R_RC" 64

# ── 4. the consumer text (operator-holds.md section 3 step 2) ─────────────────────────────────
anchor() { # anchor <literal> <what>: the literal must be present in the consumer text
  if grep -qF -- "$1" "$OPHOLDS"; then ok; else bad "operator-holds.md lacks: $2"; fi
}
control "anchor" anchor "this sentence is in no file zzqx" "a literal that is absent"
anchor 'merge-effect-class.sh" --pr <N>' "the --pr invocation"
anchor 'rc=0 || rc=$?' "the set-e-safe rc capture"
anchor 'echo "rc=$rc out=[$out]"' "the line that makes rc and out visible to the agent"
anchor '[ "$out" = "not-production-effecting" ]' "the whole-line equality"
anchor 'merge with `--match-head-commit` and that sha' "the head pin"
anchor 'run the command again and ask again only when the clause changed' "the head-change rule"
anchor 'this change may trigger a production apply or deploy when it merges' "the exit-1 sentence"
anchor 'I could not check whether this changes production, so I am treating it as if it does' "the could-not-check sentence"
anchor '`reason=not-applicable` is itself a bug signal' "the bug signal"
anchor 'never evidence in a `Gate:` line or a receipt' "the never-evidence rule"
anchor 'any workflow that runs on push to main for the changed paths' "the prior production-deploy obligation kept for the other cases"

# ── 5. discoverability command and the parity suite's missing-PyYAML failure ──────────────────
run_sut "$SUT" --self-check
check "discoverability command prints self-check=ok" "$R_OUT" "self-check=ok"
if [ -f "$PARITY" ]; then
  R_RC=0
  MEC_PYTHON=false bash "$PARITY" >"$TMP/o" 2>"$TMP/e" || R_RC=$?
  if [ "$R_RC" -ne 0 ]; then ok; else bad "parity test must fail without PyYAML, not skip"; fi
  case "$(cat "$TMP/o" "$TMP/e")" in *PyYAML*) ok ;; *) bad "parity test names the missing PyYAML" ;; esac
fi

# ── 6. executable mutants (marker lines `# mut:<name>` in the script) ─────────────────────────
MUT="$TMP/mut"
mkdir -p "$MUT"
PRISTINE="$SUT"
crashed() {
  if [ "$R_RC" = 127 ]; then return 0; fi
  case "$R_ERR" in *"syntax error"* | *"unbound variable"* | *"command not found"*) return 0 ;; esac
  return 1
}

mutate() { # mutate <name> <sed expression applied to the marker line>; sets MUTSUT
  local name="$1" expr="$2" n
  MUTSUT="$MUT/$name.sh"
  n="$(grep -c "# mut:$name\$" "$PRISTINE")"
  if [ "$n" != 1 ]; then bad "mutant $name: marker count is $n, want 1"; return 1; fi
  sed "/# mut:$name\$/ $expr" "$PRISTINE" >"$MUT/$name.tmp" && mv "$MUT/$name.tmp" "$MUTSUT"
  return 0
}
landed() { if cmp -s "$PRISTINE" "$MUTSUT"; then bad "mutant $1 did not land"; return 1; fi; return 0; }
killed() { # killed <name> <rc> <stdout> <list text>: the pristine answer; a mutant must differ and not crash
  local name="$1" rc="$2" out="$3" list="$4"
  printf '%s' "$list" >"$TMP/list"
  run_sut "$MUTSUT" --files-from "$TMP/list"
  if crashed; then bad "mutant $name CRASHED; a crash is not a kill"; return; fi
  if [ "$R_RC" = "$rc" ] && [ "$R_OUT" = "$out" ]; then bad "mutant $name SURVIVED"; else ok; fi
}

# the mutant harness must recognise a crash by rc alone, by stderr alone, and must not call a healthy run crashed
R_RC=127; R_ERR=""
if crashed; then ok; else bad "crashed() must report rc 127 with empty stderr"; fi
R_RC=1; R_ERR="line 3: foo: command not found"
if crashed; then ok; else bad "crashed() must report a command-not-found message"; fi
R_RC=1; R_ERR="merge-effect-class: production-effecting reason=outside-allowlist"
if crashed; then bad "crashed() reports a healthy run as crashed"; else ok; fi
# a mutant that changes nothing must be scored SURVIVED
MUTSUT="$PRISTINE"
control "killed (no-op mutant)" killed ctl 1 "$EFF" $'apps/x.ts\n'

if mutate widen 's/("knowledge-base\/")/("knowledge-base\/" "apps\/")/' && landed widen; then
  killed widen 1 "$EFF" $'apps/web-platform/x.ts\n'
fi
if mutate gutted 's/classify_file "\$WORK\/list"/emit 0 allowlisted/' && landed gutted; then
  killed gutted 2 "$EFF" ''
fi
if mutate first-only 's/continue/break/' && landed first-only; then
  killed first-only 1 "$EFF" $'knowledge-base/a.md\napps/x.ts\n'
fi
if mutate exit2-not 's/-eq 0/-ne 1/' && landed exit2-not; then
  killed exit2-not 2 "$EFF" ''
fi
if mutate no-slash-guard 's/^.*$/  :/' && landed no-slash-guard; then
  killed no-slash-guard 1 "$EFF" $'apps/x/README.md\n'
fi
# drop-prev works on the --pr path, so it needs the gh fake
if mutate drop-prev 's/, (\.previous_filename \/\/ empty)//' && landed drop-prev; then
  fx OPEN main "$SHA_A" 1 '[[{"filename":"knowledge-base/x.md","previous_filename":"apps/x.ts","status":"renamed"}]]'
  PR_SUT="$MUTSUT"
  pr_run "$TMP/repo-ok" --pr 7
  PR_SUT="$SUT"
  if crashed; then bad "mutant drop-prev CRASHED"; elif [ "$R_RC/$R_OUT" = "1/$EFF" ]; then bad "mutant drop-prev SURVIVED"; else ok; fi
fi

# ── floor and the stub-SUT control ────────────────────────────────────────────────────────────
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
if [ "$PASS" -lt "$FLOOR" ]; then
  printf 'FATAL: only %s assertions passed; floor is %s (a stub or a gutted suite)\n' "$PASS" "$FLOOR" >&2
  exit 1
fi
if [ -z "${MEC_NESTED:-}" ] && [ -z "${MEC_SUT:-}" ]; then
  # A SUT that exits 0 with no output must turn the whole suite RED.
  printf '#!/bin/sh\nexit 0\n' >"$TMP/stub.sh"
  R_RC=0
  MEC_NESTED=1 MEC_SUT="$TMP/stub.sh" bash "${BASH_SOURCE[0]}" >/dev/null 2>&1 || R_RC=$?
  if [ "$R_RC" -eq 0 ]; then
    printf 'FATAL: the suite stayed green against a stub SUT that exits 0 with no output\n' >&2
    exit 1
  fi
fi
[ "$FAIL" -eq 0 ]
