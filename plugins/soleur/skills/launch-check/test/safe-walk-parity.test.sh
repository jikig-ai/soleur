#!/usr/bin/env bash
# The never-read list: a superset of code-to-prd's, plus launch-check's own classes.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
check "instrument self-test" selftest
C2P="$PLUGIN/skills/code-to-prd/scripts/code-to-prd.sh"; SW="$SKILL/scripts/lib/safe-walk.sh"
# Extract the case patterns of is_excluded() by FUNCTION NAME (not line number).
pats=$(awk '/^is_excluded\(\) \{/ {f=1; next} f && /^\}/ {f=0} f && /\) return 0 ;;/ {sub(/\).*/, ""); gsub(/^[ \t]+/, ""); print}' "$C2P" | tr '|' '\n' | grep -v '^$')
n=$(printf '%s\n' "$pats" | grep -c .)
check "extractor finds code-to-prd's patterns (anti-vacuity: >= 6)" test "$n" -ge 6
body=$(awk '/^lc_safe_path\(\) \{/ {f=1} f {print} f && /^\}/ {exit}' "$SW")
miss=0; while IFS= read -r p; do [ -z "$p" ] && continue; printf '%s' "$body" | grep -qF -- "$p" || { fail "safe_path lacks code-to-prd pattern: $p"; miss=1; }; done <<<"$pats"
[ "$miss" = 0 ] && pass "safe_path contains every code-to-prd pattern"
for p in '*.tfstate' '*.tfvars' '*.sql' '*.csv' '*.sqlite' 'fixtures/*'; do
  check "launch-check addition present: $p" bash -c 'printf "%s" "$1" | grep -qF -- "$2"' _ "$body" "$p"
done
# shellcheck source=/dev/null
source "$SW"
for deny in .env .env.local app/.env key.pem a/b/server.key credentials.json secrets.yml .git/config x/.git/HEAD terraform.tfstate prod.tfvars dump.sql users.csv db.sqlite fixtures/a.json; do
  check "denied: $deny" bash -c '! lc_safe_path "$1"' _ "$deny"
done
for allow in docs/environment.md src/index.js README.md src/envelope.ts .github/workflows/ci.yml; do
  check "allowed: $allow" lc_safe_path "$allow"
done
# Source scan: file CONTENT is read only inside lc_grep_files (checks.sh).
bad=$(awk '/^lc_grep_files\(\) \{/ {f=1} !f && /(cat|head|tail|grep|sed|awk)[^|]*"\$TARGET/ && !/^[[:space:]]*#/ && !/git -C/ && !/\/dev\/null/ {print FILENAME":"NR": "$0} f && /^\}/ {f=0}' "$SKILL/scripts/lib/checks.sh")
check "no detector reads repo files outside lc_grep_files" test -z "$bad"
finish 25
