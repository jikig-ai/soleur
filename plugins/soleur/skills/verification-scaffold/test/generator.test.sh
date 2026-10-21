#!/usr/bin/env bash
# Generator coverage for verification-scaffold.sh (#10404): flags, refusals,
# settings merge, mode flips, re-run refusal, --uninstall, --dry-run. Drives
# throwaway `git init` fixture repos under mktemp — the real tree is untouched.
# Accumulate-then-exit.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
GEN="$REPO_ROOT/plugins/soleur/skills/verification-scaffold/scripts/verification-scaffold.sh"

passes=0; fails=0
pass() { printf 'ok   - %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

mk_repo() {  # $1 = name -> prints abs path of a committed fixture repo
  local fx="$TMPROOT/$1"
  mkdir -p "$fx"
  git -C "$fx" init -q
  printf 'x\n' > "$fx/f.txt"
  git -C "$fx" add f.txt
  git -C "$fx" -c user.email=t@t -c user.name=t commit -qm init
  printf '%s' "$fx"
}
run_gen() {  # $1=target, rest=args -> rc
  local t="$1"; shift
  set +e
  bash "$GEN" --target "$t" "$@" >"$TMPROOT/out.log" 2>&1
  local rc=$?
  set -e
  printf '%s' "$rc"
}

# --list prints the manifest rows
bash "$GEN" --list >"$TMPROOT/list.log" 2>&1
grep -q 'secret-scan' "$TMPROOT/list.log" && grep -q 'orphan-test' "$TMPROOT/list.log" \
  && pass "--list prints the manifest" || fail "--list missing guard rows"

# --mode bogus -> 64
FX="$(mk_repo m1)"; RC="$(run_gen "$FX" --mode bogus)"
[[ "$RC" == "64" ]] && pass "--mode bogus refuses 64" || fail "--mode bogus rc=$RC"

# non-repo target -> 65
RC="$(run_gen /tmp)"
[[ "$RC" == "65" ]] && pass "non-repo target refuses 65" || fail "non-repo rc=$RC"

# unknown guard -> 64
FX="$(mk_repo m2)"; RC="$(run_gen "$FX" --guards not-a-guard)"
[[ "$RC" == "64" ]] && pass "unknown guard refuses 64" || fail "unknown guard rc=$RC"

# --dry-run writes nothing
FX="$(mk_repo m3)"; RC="$(run_gen "$FX" --dry-run)"
[[ "$RC" == "0" && ! -e "$FX/.claude" && ! -e "$FX/.github" && ! -e "$FX/scripts" ]] \
  && pass "--dry-run writes nothing" || fail "dry-run rc=$RC or wrote files"

# pre-existing .gitleaks.toml is kept (not refused — user ruleset wins), but
# a pre-existing exclusive artifact refuses 66 with zero other writes
FX="$(mk_repo m4)"
printf 'title = "mine"\n' > "$FX/.gitleaks.toml"
RC="$(run_gen "$FX" --headless)"
[[ "$RC" == "0" ]] && grep -q 'mine' "$FX/.gitleaks.toml" \
  && pass "existing .gitleaks.toml preserved on install" || fail "gitleaks.toml handling rc=$RC"

FX="$(mk_repo m5)"
mkdir -p "$FX/.claude/hooks"; printf 'x\n' > "$FX/.claude/hooks/secret-scan.sh"
RC="$(run_gen "$FX" --headless)"
[[ "$RC" == "66" && ! -e "$FX/.claude/settings.json" && ! -e "$FX/scripts" ]] \
  && pass "refuse-if-exists: pre-existing hook blocks install, zero writes" || fail "refuse-if-exists rc=$RC"

# malformed settings.json refused pre-write
FX="$(mk_repo m6)"
mkdir -p "$FX/.claude"; printf '{broken' > "$FX/.claude/settings.json"
RC="$(run_gen "$FX" --headless)"
[[ "$RC" == "69" || "$RC" == "66" ]] && [[ ! -e "$FX/.claude/hooks" ]] \
  && pass "malformed settings.json refused pre-write" || fail "malformed settings rc=$RC"

# full install: artifacts + registration + workflow at repo root
FX="$(mk_repo m7)"; RC="$(run_gen "$FX" --headless)"
ok=1
for f in .claude/hooks/secret-scan.sh .claude/hooks/commit-on-main.sh .claude/hooks/block-stash.sh \
         scripts/verification/precommit-guard.sh scripts/verification/lib/wrapper-boundary.sh \
         scripts/verification/orphan-test-check.sh .github/workflows/verification-gates.yml \
         .claude/settings.json .gitleaks.toml; do
  [[ -e "$FX/$f" ]] || { ok=0; fail "missing emitted $f"; }
done
[[ "$RC" == "0" && "$ok" == "1" ]] && pass "--headless install emits the v1 set" || fail "install rc=$RC"
grep -q 'secret-scan.sh' "$FX/.claude/settings.json" \
  && grep -q 'block-stash.sh' "$FX/.claude/settings.json" \
  && pass "settings.json registers all three hooks" || fail "settings.json registration"
grep -q 'continue-on-error: true' "$FX/.github/workflows/verification-gates.yml" \
  && pass "advisory CI jobs carry continue-on-error" || fail "advisory CI marker"
grep -q 'MODE="advisory"' "$FX/.claude/hooks/secret-scan.sh" \
  && pass "advisory hooks stamp MODE=advisory" || fail "MODE stamp"

# unrelated settings entries preserved; re-run refuses
FX="$(mk_repo m8)"
mkdir -p "$FX/.claude"; printf '{"other":1,"hooks":{"PreToolUse":[]}}\n' > "$FX/.claude/settings.json"
RC="$(run_gen "$FX" --headless)"
[[ "$RC" == "0" ]] && grep -q '"other": 1\|"other":1' "$FX/.claude/settings.json" \
  && pass "settings merge preserves unrelated keys" || fail "settings preservation rc=$RC"
n1="$(grep -c 'secret-scan.sh' "$FX/.claude/settings.json")"
RC2="$(run_gen "$FX" --headless)"
n2="$(grep -c 'secret-scan.sh' "$FX/.claude/settings.json")"
[[ "$RC2" == "66" && "$n1" == "$n2" ]] \
  && pass "second run refuses 66, settings untouched" || fail "re-run rc=$RC2 n=$n1->$n2"

# --uninstall removes only that guard; idempotent on a missing guard
RC="$(run_gen "$FX" --uninstall block-stash)"
[[ "$RC" == "0" && ! -e "$FX/.claude/hooks/block-stash.sh" && -e "$FX/.claude/hooks/secret-scan.sh" ]] \
  && pass "--uninstall removes only the named guard" || fail "uninstall rc=$RC"
grep -q 'block-stash.sh' "$FX/.claude/settings.json" \
  && fail "settings entry survived uninstall" || pass "settings entry removed by uninstall"
RC="$(run_gen "$FX" --uninstall block-stash)"
[[ "$RC" == "0" ]] && pass "--uninstall idempotent on absent guard" || fail "uninstall-idem rc=$RC"

# enforce mode stamps deny-capable artifacts
FX="$(mk_repo m9)"; RC="$(run_gen "$FX" --mode enforce --headless)"
[[ "$RC" == "0" ]] && grep -q 'MODE="enforce"' "$FX/.claude/hooks/block-stash.sh" \
  && pass "--mode enforce stamps MODE=enforce" || fail "enforce stamp rc=$RC"

printf 'generator.test.sh: %d passed, %d failed\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
