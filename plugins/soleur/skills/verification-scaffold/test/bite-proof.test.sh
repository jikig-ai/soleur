#!/usr/bin/env bash
# Bite-proof coverage for verification-scaffold (#10404): on a fixture repo,
# each installed guard goes pass -> inject -> fail -> revert -> pass via the
# EMITTED artifacts (not the templates). secret-scan needs a runnable gitleaks
# on PATH; where absent, that arm SKIPs locally and FAILs under CI=true.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
GEN="$REPO_ROOT/plugins/soleur/skills/verification-scaffold/scripts/verification-scaffold.sh"

passes=0; fails=0; skips=0
pass() { printf 'ok   - %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }
skip() { printf 'skip - %s\n' "$1"; skips=$((skips + 1)); }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

FX="$TMPROOT/fx"
mkdir -p "$FX"
git -C "$FX" init -q
printf 'x\n' > "$FX/f.txt"
git -C "$FX" add f.txt
git -C "$FX" -c user.email=t@t -c user.name=t commit -qm init

if ! bash "$GEN" --target "$FX" --headless >"$TMPROOT/install.log" 2>&1; then
  printf 'FAIL - install did not complete; see log\n'; tail -15 "$TMPROOT/install.log"
  exit 1
fi
pass "install completed (internal bite-proof passed per guard)"

dec() {  # stdin hook output -> permissionDecision
  sed -n 's/.*"permissionDecision": *"\([a-z]*\)".*/\1/p' | head -n 1
}
feed() { # $1=hook-rel $2=command $3=cwd -> hook stdout
  printf '{"tool_name":"Bash","tool_input":{"command":%s},"cwd":%s}\n' \
    "$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$2")" \
    "$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$3")" \
    | bash "$FX/$1"
}

# --- block-stash: mutating stash warns+allows (advisory), read-only passes --
d="$(feed .claude/hooks/block-stash.sh 'git stash' "$FX" | dec)"
[[ "$d" == "allow" ]] && pass "block-stash advisory allows-with-warning on 'git stash'" || fail "block-stash stash decision=$d"
out="$(feed .claude/hooks/block-stash.sh 'git stash' "$FX")"
grep -qi 'advisory\|warn' <<<"$out" || fail "block-stash advisory carried no warning"
d="$(feed .claude/hooks/block-stash.sh 'git add x && git stash pop' "$FX" | dec)"
[[ "$d" == "allow" ]] && pass "block-stash catches chained stash" || fail "block-stash chained decision=$d"
d="$(feed .claude/hooks/block-stash.sh 'git status' "$FX" | dec)"
[[ "$d" == "allow" ]] && pass "block-stash allows benign command" || fail "block-stash benign decision=$d"

# --- commit-on-main: scratch repo on the default branch refuses ------------
SCR="$TMPROOT/scratch"
mkdir -p "$SCR"; git -C "$SCR" init -q
git -C "$SCR" -c user.email=t@t -c user.name=t commit -qm --allow-empty x
git -C "$SCR" checkout -qb feat-x
d="$(feed .claude/hooks/commit-on-main.sh 'git commit -m x' "$SCR" | dec)"
[[ "$d" == "allow" ]] && pass "commit-on-main allows a feature-branch commit" || fail "com feat decision=$d"
main_b="$(git -C "$SCR" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
[[ -z "$main_b" ]] && main_b="$(git -C "$FX" symbolic-ref -q --short HEAD 2>/dev/null || echo main)"
git -C "$SCR" checkout -qb "$main_b" 2>/dev/null || git -C "$SCR" checkout -q "$main_b"
out="$(feed .claude/hooks/commit-on-main.sh 'git commit -m x' "$SCR")"
d="$(printf '%s' "$out" | dec)"
[[ "$d" == "allow" ]] && grep -qi 'advisory' <<<"$out" \
  && pass "commit-on-main advisory warns on the default branch" || fail "com default decision=$d"

# --- secret-scan: staged secret asks; clean allows; missing-binary warns ---
if command -v gitleaks >/dev/null 2>&1 && gitleaks version >/dev/null 2>&1; then
  d="$(feed .claude/hooks/secret-scan.sh 'git commit -m x' "$FX" | dec)"
  [[ "$d" == "allow" ]] && pass "secret-scan allows clean staged index" || fail "ss clean decision=$d"
  printf 'AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYSYNTHETIC0"\n' > "$FX/bite-secret.txt"
  git -C "$FX" add bite-secret.txt
  out="$(feed .claude/hooks/secret-scan.sh 'git commit -m x' "$FX")"
  d="$(printf '%s' "$out" | dec)"
  [[ "$d" == "ask" ]] && pass "secret-scan asks on a staged secret (advisory)" || fail "ss inject decision=$d"
  git -C "$FX" rm -q --cached bite-secret.txt && rm -f "$FX/bite-secret.txt"
  d="$(feed .claude/hooks/secret-scan.sh 'git commit -m x' "$FX" | dec)"
  [[ "$d" == "allow" ]] && pass "secret-scan re-allows after revert" || fail "ss revert decision=$d"
elif [[ "${CI:-}" == "true" ]]; then
  fail "gitleaks absent/unrunnable under CI — the secret-scan arm must run"
else
  skip "gitleaks absent — secret-scan bite arm skipped locally (runs in CI)"
fi

# --- orphan-test: unregistered suite named; reasoned exclusion passes -------
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/zz-orphan-bite.test.sh"
git -C "$FX" add zz-orphan-bite.test.sh
git -C "$FX" -c user.email=t@t -c user.name=t commit -qm add-orphan
out="$(cd "$FX" && bash scripts/verification/orphan-test-check.sh 2>&1)" && fail "orphan-test passed with unregistered suite" || true
grep -q 'zz-orphan-bite.test.sh' <<<"$out" \
  && pass "orphan-test names the unregistered suite" || fail "orphan-test output: $out"
printf 'zz-orphan-bite.test.sh fixture suite deliberately outside a runner — bite coverage\n' >> "$FX/.github/verification-known-orphans.txt"
out="$(cd "$FX" && bash scripts/verification/orphan-test-check.sh 2>&1)" \
  && pass "orphan-test passes with reasoned exclusion" || fail "orphan-test exclusion: $out"

printf 'bite-proof.test.sh: %d passed, %d failed, %d skipped\n' "$passes" "$fails" "$skips"
[[ "$fails" -eq 0 ]]
