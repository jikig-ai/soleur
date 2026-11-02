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
body=$(awk '/^lc__safe_path_case\(\) \{/ {f=1} f {print} f && /^\}/ {exit}' "$SW")
check "extractor finds the case body (anti-vacuity)" test -n "$body"
miss=0; while IFS= read -r p; do [ -z "$p" ] && continue; printf '%s' "$body" | grep -qF -- "$p" || { fail "safe_path lacks code-to-prd pattern: $p"; miss=1; }; done <<<"$pats"
[ "$miss" = 0 ] && pass "safe_path contains every code-to-prd pattern"
for p in '*.tfstate' '*.tfvars' '*.sql' '*.csv' '*.sqlite' 'fixtures/*'; do
  check "launch-check addition present: $p" bash -c 'printf "%s" "$1" | grep -qF -- "$2"' _ "$body" "$p"
done
# shellcheck source=/dev/null
source "$SW"
# lc_safe_path is a shell function: it must be called IN-PROCESS. A `bash -c '! lc_safe_path ...'` child shell does not
# have it, exits 127, and `!` turns that into a pass -- a denied-path assertion that can never fail.
not() { ! "$@"; }
check "instrument: not() turns a failing call into a pass and a passing call into a fail" bash -c 'not() { ! "$@"; }; not false && ! not true'
check "positive control: lc_safe_path really does deny a path (a stub that allows everything would fail this)" not lc_safe_path .env
for deny in .env .env.local app/.env key.pem a/b/server.key credentials.json secrets.yml .git/config x/.git/HEAD terraform.tfstate prod.tfvars dump.sql users.csv db.sqlite fixtures/a.json \
            a.tfstate.backup prod.tfvars.json backup.dump db.sqlite3 app.db x/fixtures/a.json __fixtures__/a.json x/__fixtures__/a.json seeds/a.json x/seeds/a.json \
            id_rsa deploy/id_ed25519 .npmrc a/.npmrc .netrc .pypirc .htpasswd .git-credentials .dev.vars kubeconfig .aws/credentials a/.aws/config .kube/config \
            deploy/server.p12 a.pfx b.jks c.keystore d.ppk prod.env .envrc sa/service-account-prod.json secrets/prod.json credentials \
            .ENV KEY.PEM Id_RSA .NPMRC Credentials.JSON; do
  check "denied: $deny" not lc_safe_path "$deny"
done
for allow in docs/environment.md src/index.js README.md src/envelope.ts .github/workflows/ci.yml src/credentials-guide.md docs/secretsmanager.md; do
  check "allowed: $allow" lc_safe_path "$allow"
done
# Every name SEC-02 calls a credential must be on the never-read list (one definition of "secret-class").
samples='.env a/.env.local x.key id_rsa deploy/id_ed25519 s.p12 a.pfx b.jks c.keystore d.ppk .npmrc .netrc .pypirc .htpasswd .git-credentials .dev.vars kubeconfig .aws/credentials .kube/config sa/service-account-prod.json credentials.json secrets.yml terraform.tfstate prod.tfvars server-key.pem .envrc prod.env'
flagged=$(for s in $samples; do printf '%s\n' "$s"; done | lc_credential_paths)
check "SEC-02 name predicate flags every sample (anti-vacuity)" test "$(printf '%s\n' "$flagged" | grep -c .)" -eq "$(printf '%s\n' $samples | grep -c .)"
leak=0; while IFS= read -r p; do [ -z "$p" ] && continue; lc_safe_path "$p" && { fail "SEC-02 credential name offered to the model: $p"; leak=1; }; done <<<"$flagged"
[ "$leak" = 0 ] && pass "every SEC-02 credential name is on the never-read list"
check "SEC-02 predicate spares templates and public keys" bash -c 'source "$1"; [ -z "$(printf "%s\n" .env.example id_rsa.pub a/key.pem.sample | lc_credential_paths)" ]' _ "$SW"
# Source scan: file CONTENT is read only inside lc_grep_files (checks.sh).
bad=$(awk '/^lc_grep_files\(\) \{/ {f=1} !f && /(cat|head|tail|grep|sed|awk)[^|]*"\$TARGET/ && !/^[[:space:]]*#/ && !/git -C/ && !/\/dev\/null/ {print FILENAME":"NR": "$0} f && /^\}/ {f=0}' "$SKILL/scripts/lib/checks.sh")
check "no detector reads repo files outside lc_grep_files" test -z "$bad"
finish 76
