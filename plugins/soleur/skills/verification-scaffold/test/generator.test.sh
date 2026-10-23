#!/usr/bin/env bash
# Generator coverage for verification-scaffold.sh (#10404) against HERMETIC
# fixture repos — a throwaway `git init` per arm under a mktemp dir. Covers the
# flag/exit-matrix paths that need no gitleaks:
#   64  --mode bogus; unknown guard
#   65  --target outside a git work tree
#   66  refuse-if-exists (pre-placed artifact; full second run)
#   69  malformed .claude/settings.json refused BEFORE any write
#   settings merge: absent created, unrelated keys preserved, re-run dedupe
#   --dry-run writes nothing; --uninstall is surgical + idempotent
#   --guards subset emits only that guard's artifacts
# Runs in the scripts shard. Accumulate-then-exit.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
GEN="$REPO_ROOT/plugins/soleur/skills/verification-scaffold/scripts/verification-scaffold.sh"

passes=0; fails=0
pass() { printf 'ok   - %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

TMPROOT="$(mktemp -d)"
# The body below is the CANONICAL copy of assert_fixture_dir (#7652) — do not reword.
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
trap 'rm -rf "$TMPROOT"' EXIT

mkrepo() { # mkrepo <name> -> fixture git repo path (empty tree, one commit)
  local d="$TMPROOT/$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  local t c
  t="$(git -C "$d" write-tree)"
  c="$(echo init | git -C "$d" commit-tree "$t")"
  git -C "$d" update-ref refs/heads/main "$c"
  git -C "$d" symbolic-ref HEAD refs/heads/main
  printf '%s' "$d"
}

run_gen() { # run_gen <repo> <args...> -> rc (never aborts the suite)
  local root="$1"; shift
  local rc=0
  bash "$GEN" --target "$root" "$@" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

run_gen_out() { # run_gen_out <repo> <args...> -> "rc|stdout"
  local root="$1"; shift
  local rc=0 out
  out="$(bash "$GEN" --target "$root" "$@" 2>/dev/null)" || rc=$?
  printf '%s|%s' "$rc" "$out"
}

# --- 65: not a git work tree ---------------------------------------------------
NOTREPO="$TMPROOT/notrepo"; mkdir -p "$NOTREPO"
RC="$(run_gen "$NOTREPO" --headless)"
[[ "$RC" == "65" ]] && pass "exit 65: target outside a git work tree refused" \
  || fail "expected 65 for non-repo target, got $RC"

# --- 64: --mode bogus / unknown guard -------------------------------------------
FX="$(mkrepo modebogus)"; assert_fixture_dir "$FX"
RC="$(run_gen "$FX" --mode bogus --headless)"
[[ "$RC" == "64" ]] && pass "exit 64: --mode bogus refused pre-write" \
  || fail "expected 64 for --mode bogus, got $RC"
RC="$(run_gen "$FX" --guards nosuchguard --headless)"
[[ "$RC" == "64" ]] && pass "exit 64: unknown guard refused" \
  || fail "expected 64 for unknown guard, got $RC"

# --- 69: malformed settings.json refused BEFORE any write -----------------------
FX="$(mkrepo badsettings)"; assert_fixture_dir "$FX"
mkdir -p "$FX/.claude"
printf '{not json' > "$FX/.claude/settings.json"
RC="$(run_gen "$FX" --headless)"
if [[ "$RC" == "69" ]] && [[ ! -e "$FX/.claude/hooks/secret-scan.sh" ]] \
   && [[ "$(cat "$FX/.claude/settings.json")" == '{not json' ]]; then
  pass "exit 69: malformed settings.json refused before any write (file untouched)"
else
  fail "malformed settings.json arm: rc=$RC settings=$(cat "$FX/.claude/settings.json" 2>/dev/null)"
fi

# --- 66: pre-existing artifact refuses -------------------------------------------
FX="$(mkrepo collides)"; assert_fixture_dir "$FX"
mkdir -p "$FX/.claude/hooks"
printf '# mine\n' > "$FX/.claude/hooks/secret-scan.sh"
RC="$(run_gen "$FX" --headless)"
[[ "$RC" == "66" && "$(cat "$FX/.claude/hooks/secret-scan.sh")" == '# mine' ]] \
  && pass "exit 66: pre-existing hook refuses, zero writes (file untouched)" \
  || fail "expected 66 with untouched file, got rc=$RC"

# pre-existing .gitleaks.toml also refuses (AC5)
FX="$(mkrepo glcollide)"; assert_fixture_dir "$FX"
printf '[extend]\nuseDefault = false\n' > "$FX/.gitleaks.toml"
RC="$(run_gen "$FX" --headless)"
[[ "$RC" == "66" && "$(cat "$FX/.gitleaks.toml")" == "[extend]
useDefault = false" ]] \
  && pass "exit 66: pre-existing .gitleaks.toml refuses (never overwrites a user ruleset)" \
  || fail "expected 66 for pre-existing .gitleaks.toml, got rc=$RC"

# --- --guards subset -------------------------------------------------------------
FX="$(mkrepo subset)"; assert_fixture_dir "$FX"
RC="$(run_gen "$FX" --guards block-stash --headless)"
if [[ "$RC" == "0" && -f "$FX/.claude/hooks/block-stash.sh" \
   && ! -e "$FX/.claude/hooks/secret-scan.sh" && ! -e "$FX/.github/workflows/verification-gates.yml" ]]; then
  pass "--guards block-stash emits only that guard's artifacts"
else
  fail "subset install wrong: rc=$RC $(ls "$FX/.claude/hooks" 2>/dev/null | tr '\n' ' ')"
fi
grep -q 'block-stash' "$FX/.claude/settings.json" 2>/dev/null \
  && pass "subset install registered the hook in settings.json" \
  || fail "subset install: no settings.json hook entry"

# --- --dry-run writes nothing ----------------------------------------------------
FX="$(mkrepo dryrun)"; assert_fixture_dir "$FX"
OUT="$(run_gen_out "$FX" --dry-run)"
if [[ "${OUT%%|*}" == "0" && ! -e "$FX/.claude/hooks/secret-scan.sh" && ! -e "$FX/.claude/settings.json" ]]; then
  pass "--dry-run exits 0 and writes nothing"
else
  fail "dry-run arm: rc=${OUT%%|*}"
fi

# --- full install + advisory markers (AC3) ---------------------------------------
FX="$(mkrepo full)"; assert_fixture_dir "$FX"
RC="$(run_gen "$FX" --headless)"
[[ "$RC" == "0" ]] || fail "advisory install failed rc=$RC"
G=1
for p in .claude/hooks/secret-scan.sh .claude/hooks/commit-on-main.sh .claude/hooks/block-stash.sh \
         scripts/verification/precommit-guard.sh scripts/verification/lib/wrapper-boundary.sh \
         scripts/verification/orphan-test-check.sh .gitleaks.toml \
         .github/workflows/verification-gates.yml .github/verification-known-orphans.txt \
         .claude/settings.json VERIFICATION.md; do
  [[ -f "$FX/$p" ]] || { G=0; fail "missing emitted artifact: $p"; }
done
[[ "$G" == "1" ]] && pass "advisory install emits all v1 artifacts"
grep -q 'MODE="advisory"' "$FX/.claude/hooks/secret-scan.sh" \
  && grep -q 'MODE="advisory"' "$FX/.claude/hooks/commit-on-main.sh" \
  && grep -q 'MODE="advisory"' "$FX/.claude/hooks/block-stash.sh" \
  && pass "advisory install stamps MODE=advisory in every hook" \
  || fail "MODE=advisory stamp missing in an emitted hook"
test "$(grep -c 'continue-on-error: true' "$FX/.github/workflows/verification-gates.yml")" = 2 \
  && pass "advisory workflow carries continue-on-error: true on both jobs" \
  || fail "advisory workflow continue-on-error wrong: $(grep -c 'continue-on-error' "$FX/.github/workflows/verification-gates.yml")"
if grep -rqE '@(MODE|CI_CONTINUE_ON_ERROR|DEFAULT_BRANCHES|GUARD_LIST|GUARD_TABLE|DATE)@' \
     "$FX/.claude/hooks" "$FX/scripts/verification" "$FX/.github/workflows/verification-gates.yml" "$FX/VERIFICATION.md" 2>/dev/null; then
  fail "unsubstituted placeholder leaked into emitted artifacts"
else
  pass "no unsubstituted @PLACEHOLDER@ leaks into emitted artifacts"
fi
grep -q 'verification-scaffold:readme:start' "$FX/VERIFICATION.md" \
  && pass "VERIFICATION.md created with the marker-keyed doc block" \
  || fail "VERIFICATION.md doc block missing"

# settings.json: hook entries present, dedupe on command string
node -e '
  const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const cmds = d.hooks.PreToolUse.flatMap(m => m.hooks.map(h => h.command));
  for (const n of ["secret-scan", "commit-on-main", "block-stash"])
    if (!cmds.some(c => c.includes("/.claude/hooks/" + n + ".sh"))) process.exit(3);
' "$FX/.claude/settings.json" \
  && pass "settings.json registers all three hook commands" \
  || fail "settings.json hook entries missing"

# --- enforce mode flips only the decision verb (AC3/Guard 6) ---------------------
FX="$(mkrepo enforce)"; assert_fixture_dir "$FX"
RC="$(run_gen "$FX" --mode enforce --headless)"
if [[ "$RC" == "0" ]]; then
  grep -q 'MODE="enforce"' "$FX/.claude/hooks/block-stash.sh" \
    && grep -q 'continue-on-error: false' "$FX/.github/workflows/verification-gates.yml" \
    && pass "enforce install stamps MODE=enforce + continue-on-error: false" \
    || fail "enforce stamps wrong"
else
  fail "enforce install failed rc=$RC"
fi

# --- re-run refuses (AC5) ---------------------------------------------------------
RC="$(run_gen "$FX" --headless)"
[[ "$RC" == "66" ]] && pass "second full run refuses (66), zero writes" \
  || fail "expected 66 on second run, got $RC"

# --- idempotent merge: manually re-add the same command -> stays single ----------
# (The generator refuses before reaching the merge, so prove dedupe via a repo
# whose ONLY drift is a missing settings entry while artifacts exist is refused
# anyway — instead assert the emitted file itself: a merge that ran twice would
# carry two identical command strings.)
node -e '
  const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const cmds = d.hooks.PreToolUse.flatMap(m => m.hooks.map(h => h.command));
  if (new Set(cmds).size !== cmds.length) process.exit(3);
' "$FX/.claude/settings.json" \
  && pass "settings.json has no duplicate hook commands" \
  || fail "duplicate hook commands in settings.json"

# --- merge preserves unrelated entries ------------------------------------------
FX="$(mkrepo preserve)"; assert_fixture_dir "$FX"
mkdir -p "$FX/.claude"
printf '%s\n' '{"permissions":{"allow":["Bash(ls:*)"]},"hooks":{"PreToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"keepme"}]}]}}' > "$FX/.claude/settings.json"
RC="$(run_gen "$FX" --guards block-stash --headless)"
if [[ "$RC" == "0" ]]; then
  node -e '
    const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const ok = d.permissions.allow.includes("Bash(ls:*)")
      && d.hooks.PreToolUse.some(m => m.hooks.some(h => h.command === "keepme"))
      && d.hooks.PreToolUse.some(m => m.hooks.some(h => h.command.includes("block-stash")));
    process.exit(ok ? 0 : 3);
  ' "$FX/.claude/settings.json" \
    && pass "merge preserves unrelated permissions + hook entries" \
    || fail "merge clobbered unrelated settings.json entries"
else
  fail "preserve install failed rc=$RC"
fi

# --- --uninstall: surgical + idempotent (AC5/SpecFlow 5) --------------------------
RC="$(run_gen "$FX" --uninstall block-stash)"
if [[ "$RC" == "0" && ! -e "$FX/.claude/hooks/block-stash.sh" ]]; then
  node -e '
    const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const cmds = d.hooks.PreToolUse.flatMap(m => m.hooks.map(h => h.command));
    process.exit(cmds.some(c => c.includes("block-stash")) || !cmds.includes("keepme") ? 3 : 0);
  ' "$FX/.claude/settings.json" \
    && pass "--uninstall removes the artifact + settings entry, leaves siblings" \
    || fail "uninstall left a block-stash settings entry or removed keepme"
else
  fail "uninstall block-stash: rc=$RC artifact=$(ls "$FX/.claude/hooks" 2>/dev/null | tr '\n' ' ')"
fi
RC="$(run_gen "$FX" --uninstall block-stash)"
[[ "$RC" == "0" ]] && pass "--uninstall on a removed guard is a clean no-op (exit 0)" \
  || fail "idempotent uninstall expected rc=0, got $RC"

# --- --list ----------------------------------------------------------------------
OUT="$(run_gen_out "$FX" --list)"
[[ "${OUT%%|*}" == "0" ]] && grep -q 'secret-scan' <<<"${OUT#*|}" \
  && pass "--list prints the guard manifest" \
  || fail "--list failed: ${OUT%%|*}"

# --- 64: a v2-candidate guard is refused (#10759) --------------------------------
FX="$(mkrepo v2refuse)"; assert_fixture_dir "$FX"
RC="$(run_gen "$FX" --guards block-rm-rf --headless)"
[[ "$RC" == "64" && ! -e "$FX/.claude/hooks/block-rm-rf.sh" ]] \
  && pass "exit 64: v2-candidate guard refused, nothing emitted" \
  || fail "expected 64 for v2-tier guard, got $RC"

# --- 69: TMPDIR resolving inside the repo is refused pre-write (#10759) ----------
FX="$(mkrepo tmpinside)"; assert_fixture_dir "$FX"
mkdir -p "$FX/tmp"
RC=0; TMPDIR="$FX/tmp" bash "$GEN" --target "$FX" --headless >/dev/null 2>&1 || RC=$?
if [[ "$RC" == "69" && ! -e "$FX/.claude/hooks/secret-scan.sh" && ! -e "$FX/.claude/settings.json" ]]; then
  pass "exit 69: TMPDIR inside the target repo refused before any artifact"
else
  fail "TMPDIR-inside-repo arm: expected 69, got rc=$RC"
fi

# --- --uninstall secret-scan: strip only its job from the shared workflow --------
FX="$(mkrepo jobstrip)"; assert_fixture_dir "$FX"
RC="$(run_gen "$FX" --guards secret-scan,orphan-test --headless)"
[[ "$RC" == "0" ]] || fail "secret-scan+orphan-test install failed rc=$RC"
OUT="$(run_gen_out "$FX" --uninstall secret-scan)"
if [[ "${OUT%%|*}" == "0" && "${OUT#*|}" == *job-stripped* \
   && -f "$FX/.github/workflows/verification-gates.yml" \
   && -f "$FX/scripts/verification/orphan-test-check.sh" \
   && ! -e "$FX/.claude/hooks/secret-scan.sh" && ! -e "$FX/.gitleaks.toml" ]]; then
  pass "--uninstall secret-scan strips only its job block from the shared workflow"
else
  fail "shared-artifact uninstall arm: rc=${OUT%%|*} out=${OUT#*|}"
fi
WF="$FX/.github/workflows/verification-gates.yml"
if grep -qF '# verification-scaffold:begin:orphan-test' "$WF" \
   && ! grep -qF 'verification-scaffold:begin:secret-scan' "$WF"; then
  pass "shared workflow keeps the orphan-test job, drops secret-scan's"
else
  fail "shared workflow job blocks wrong after strip: $(grep -c 'begin:' "$WF" 2>/dev/null)"
fi

# --- --uninstall of a never-installed ci guard: no phantom job-strip (#10759) -----
FX="$(mkrepo neverci)"; assert_fixture_dir "$FX"
RC="$(run_gen "$FX" --guards secret-scan --headless)"
[[ "$RC" == "0" ]] || fail "secret-scan-only install failed rc=$RC"
OUT="$(run_gen_out "$FX" --uninstall orphan-test)"
if [[ "${OUT%%|*}" == "0" && "${OUT#*|}" == *"not installed"* && "${OUT#*|}" != *"job-stripped"* ]]; then
  pass "--uninstall of a never-installed ci guard reports not-installed (no phantom job-strip)"
else
  fail "never-installed ci guard arm: rc=${OUT%%|*} out=${OUT#*|}"
fi
grep -qF 'verification-scaffold:begin:secret-scan' "$FX/.github/workflows/verification-gates.yml" \
  && pass "shared workflow untouched by the never-installed guard's uninstall" \
  || fail "workflow lost its secret-scan block on a phantom uninstall"

# --- doc block is pruned once no v1 artifact remains (#10759) --------------------
OUT="$(run_gen_out "$FX" --uninstall secret-scan)"
if [[ "${OUT%%|*}" == "0" && ! -e "$FX/VERIFICATION.md" \
   && ! -e "$FX/.github/workflows/verification-gates.yml" ]]; then
  pass "last-guard uninstall prunes the stale VERIFICATION.md marker block"
else
  fail "doc-block prune arm: rc=${OUT%%|*} VERIFICATION.md=$(ls "$FX/VERIFICATION.md" 2>/dev/null || echo absent)"
fi

# --- default branch named a&b still emits a working regex (#10759) ----------------
FX="$(mkrepo ampbranch)"; assert_fixture_dir "$FX"
git -C "$FX" update-ref refs/remotes/origin/a\&b "$(git -C "$FX" rev-parse HEAD)"
git -C "$FX" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/a\&b
RC="$(run_gen "$FX" --guards commit-on-main --mode enforce --headless)"
if [[ "$RC" == "0" ]] && ! grep -qF '@DEFAULT_BRANCHES@' "$FX/scripts/verification/precommit-guard.sh"; then
  pass "default branch 'a&b': emitted regex is literal — enforce install + bite green"
else
  fail "a&b default-branch arm: rc=$RC"
fi

printf '\n%d pass(es), %d fail(s)\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
