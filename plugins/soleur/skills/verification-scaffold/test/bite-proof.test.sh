#!/usr/bin/env bash
# Bite-proof coverage for verification-scaffold.sh (#10404): installs the v1 set
# into a fixture repo and drives each emitted guard pass -> fail -> pass —
# independent of the generator's own internal bite (this suite RE-drives the
# emitted artifacts as a consumer would). Needs gitleaks on PATH for the
# secret-scan arm; that arm is skipped loudly when the binary is absent
# (matching the guard's own contract: a missing scanner is a tool error, not a
# finding). Runs in the scripts shard. Accumulate-then-exit.
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

mkrepo() { # mkrepo <name> -> committed fixture repo on main
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

payload() { jq -nc --arg c "$1" --arg w "$2" '{tool_name:"Bash",tool_input:{command:$c},cwd:$w}'; }
decide() { sed -n 's/.*"permissionDecision": *"\([a-z]*\)".*/\1/p' | head -n 1; }

# --- install into the fixture ---------------------------------------------------
FX="$(mkrepo installed)"; assert_fixture_dir "$FX"
OUT="$(bash "$GEN" --target "$FX" --headless 2>&1)" || { fail "install failed: $OUT"; printf '\n%d pass(es), %d fail(s)\n' "$passes" "$fails"; exit 1; }
grep -q 'bite-proof' <<<"$OUT" \
  && pass "install reports the internal bite-proof per guard" \
  || fail "install output carries no bite-proof lines: $OUT"
# The internal bite must have run all four arms (a SKIP is a failure HERE —
# gitleaks is expected on this host; on a host without it the arm prints SKIP).
for g in secret-scan commit-on-main block-stash orphan-test; do
  if grep -q "bite-proof $g: pass -> fail" <<<"$OUT"; then
    pass "internal bite-proof: $g pass -> fail -> pass"
  elif [[ "$g" == "secret-scan" ]] && ! command -v gitleaks >/dev/null 2>&1 \
       && grep -q "bite-proof secret-scan: SKIP" <<<"$OUT"; then
    pass "internal bite-proof: secret-scan SKIP (no gitleaks on PATH — documented)"
  else
    fail "internal bite-proof arm missing or failed for $g: $(grep 'bite-proof' <<<"$OUT" | tr '\n' ';')"
  fi
done

# --- commit-on-main, re-driven against the emitted pair --------------------------
HOOK="$FX/.claude/hooks/commit-on-main.sh"
# A fixture repo ON a feature branch: pass arm.
F2="$TMPROOT/feat-repo"; assert_fixture_dir "$F2"
mkdir -p "$F2"
git -C "$F2" init -q; git -C "$F2" config user.email t@t; git -C "$F2" config user.name t
git -C "$F2" symbolic-ref HEAD refs/heads/main
t="$(git -C "$F2" write-tree)"; c="$(echo x | git -C "$F2" commit-tree "$t")"; git -C "$F2" update-ref refs/heads/main "$c"
git -C "$F2" checkout -qb feat-x
OUT="$(cd "$FX" && payload "git -C $F2 commit -m x" "$F2" | bash "$HOOK")"
[[ "$(decide <<<"$OUT")" == "allow" ]] && pass "commit-on-main: feature-branch payload allowed" \
  || fail "commit-on-main feature branch: $OUT"
# On main: advisory warn+allow with a refusal WARN on stderr.
git -C "$F2" checkout -q main
ERR="$TMPROOT/err"; OUT="$(cd "$FX" && payload "git -C $F2 commit -m x" "$F2" | bash "$HOOK" 2>"$ERR")"
if [[ "$(decide <<<"$OUT")" == "allow" ]] && grep -qE 'not allowed|refused' "$ERR"; then
  pass "commit-on-main: main payload warns+allows (advisory)"
else
  fail "commit-on-main main arm: out=$OUT err=$(cat "$ERR")"
fi
# Enforce flip is one line: MODE=enforce denies.
sed 's/^MODE="advisory"$/MODE="enforce"/' "$HOOK" > "$TMPROOT/hook-enf.sh"
OUT="$(cd "$FX" && payload "git -C $F2 commit -m x" "$F2" | bash "$TMPROOT/hook-enf.sh" 2>/dev/null)"
[[ "$(decide <<<"$OUT")" == "deny" ]] && pass "commit-on-main: MODE=enforce flip denies (one-line promotion)" \
  || fail "enforce flip did not deny: $OUT"

# --- block-stash ------------------------------------------------------------------
HOOK="$FX/.claude/hooks/block-stash.sh"
OUT="$(cd "$FX" && payload "git status" "$FX" | bash "$HOOK")"
[[ "$(decide <<<"$OUT")" == "allow" ]] && pass "block-stash: git status allowed" \
  || fail "block-stash status: $OUT"
ERR="$TMPROOT/err2"; OUT="$(cd "$FX" && payload "git add x && git stash pop" "$FX" | bash "$HOOK" 2>"$ERR")"
if [[ "$(decide <<<"$OUT")" == "allow" ]] && grep -q 'not allowed' "$ERR"; then
  pass "block-stash: chained 'git stash pop' warns+allows"
else
  fail "block-stash stash arm: out=$OUT err=$(cat "$ERR")"
fi
OUT="$(cd "$FX" && payload "git stash list" "$FX" | bash "$HOOK")"
[[ "$(decide <<<"$OUT")" == "allow" ]] && pass "block-stash: read-only 'git stash list' allowed" \
  || fail "block-stash stash list: $OUT"

# --- orphan-test ------------------------------------------------------------------
CHECK="$FX/scripts/verification/orphan-test-check.sh"
OUT="$(cd "$FX" && bash "$CHECK" 2>&1)" && pass "orphan-test: clean tree passes" \
  || fail "orphan-test clean tree: $OUT"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/scratch.test.sh"
git -C "$FX" add scratch.test.sh
RC=0; OUT="$(cd "$FX" && bash "$CHECK" 2>&1)" || RC=$?
if [[ "$RC" -ne 0 && "$OUT" == *scratch.test.sh* ]]; then
  pass "orphan-test: injected unregistered suite named by path"
else
  fail "orphan-test injected suite: rc=$RC out=$OUT"
fi
# Reason-carrying exclusion registers it.
printf 'scratch.test.sh # deliberate exclusion for the bite suite\n' >> "$FX/.github/verification-known-orphans.txt"
OUT="$(cd "$FX" && bash "$CHECK" 2>&1)" && pass "orphan-test: reasoned exclusion passes" \
  || fail "orphan-test exclusion arm: $OUT"
# A reasonless exclusion line is itself a finding.
printf 'scratch.test.sh\n' >> "$FX/.github/verification-known-orphans.txt"
RC=0; OUT="$(cd "$FX" && bash "$CHECK" 2>&1)" || RC=$?
[[ "$RC" -ne 0 && "$OUT" == *reasonless* ]] && pass "orphan-test: reasonless exclusion is a finding" \
  || fail "orphan-test reasonless arm: rc=$RC out=$OUT"
git -C "$FX" rm -q --cached scratch.test.sh 2>/dev/null; rm -f "$FX/scratch.test.sh"
git -C "$FX" checkout -q -- .github/verification-known-orphans.txt 2>/dev/null \
  || git -C "$FX" restore --staged --worktree .github/verification-known-orphans.txt 2>/dev/null || true

# --- secret-scan (skipped without gitleaks) ---------------------------------------
HOOK="$FX/.claude/hooks/secret-scan.sh"
if command -v gitleaks >/dev/null 2>&1; then
  printf 'x\n' > "$FX/clean.txt"; git -C "$FX" add clean.txt
  OUT="$(cd "$FX" && payload "git commit -m x" "$FX" | bash "$HOOK" 2>/dev/null)"
  [[ "$(decide <<<"$OUT")" == "allow" ]] && pass "secret-scan: clean staged file allows" \
    || fail "secret-scan clean arm: $OUT"
  # Synthetic-but-shaped secret (the AWS docs example key is allowlisted in
  # gitleaks's default ruleset — this variant keeps the 40-char shape only).
  printf 'AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYSYNTHETIC0"\n' > "$FX/secret.txt"
  git -C "$FX" add secret.txt
  OUT="$(cd "$FX" && payload "git commit -m x" "$FX" | bash "$HOOK" 2>/dev/null)"
  [[ "$(decide <<<"$OUT")" == "ask" ]] && pass "secret-scan: staged secret surfaces as ask (advisory)" \
    || fail "secret-scan secret arm: $OUT"
  git -C "$FX" rm -q --cached secret.txt; rm -f "$FX/secret.txt"
  OUT="$(cd "$FX" && payload "git commit -m x" "$FX" | bash "$HOOK" 2>/dev/null)"
  [[ "$(decide <<<"$OUT")" == "allow" ]] && pass "secret-scan: reverted tree allows again" \
    || fail "secret-scan revert arm: $OUT"
else
  pass "secret-scan arms skipped (no gitleaks on PATH — the hook warns+allows per commit)"
fi

printf '\n%d pass(es), %d fail(s)\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
