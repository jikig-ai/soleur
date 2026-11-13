#!/usr/bin/env bash
# Text pins for the D2-2 relay script (#9927 / #12158, CTO ruling D1c): the relay is the only
# path from the Terraform-declared write token to the `inngest-cutover` environment secret,
# because the Terraform GitHub App cannot write environment secrets. The pins assert the
# CONTRACT, not its wording: a `sensitive` output read via `terraform output -raw`, delivery
# to `gh secret set --env` over STDIN, no echo of the key anywhere, the xtrace refusal, the
# generated-operator-script v2 contract, and the stage table.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
RELAY="$ROOT/knowledge-base/project/specs/feat-one-shot-9927-d2-2-new-write-path/relay-inngest-write-token.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '[FAIL] %s\n' "$1" >&2; }
assert() { # <desc> <cond-string>
  if eval "$2"; then ok "$1"; else bad "$1 :: $2"; fi
}

[ -f "$RELAY" ] || { printf '[FATAL] relay script missing: %s\n' "$RELAY" >&2; exit 1; }
[ -x "$RELAY" ] && ok "relay script is executable" || bad "relay script lacks exec bit"

# Contract anchors (D1c build pins).
assert "carries the generated-operator-script v2 header" "grep -qF 'SOLEUR-GENERATED-OPERATOR-SCRIPT v2' '$RELAY'"
assert "refuses xtrace with exit 78 before any command" "grep -qE '\*x\*.*exit 78|exit 78' '$RELAY'"
OUT="$(env -i PATH="$PATH" bash -x "$RELAY" --list 2>&1)"; RC=$?
assert "xtrace run exits 78" "[[ $RC -eq 78 ]]"
assert "--list prints the three stages (static, no credentials)" "env -i PATH=\"$PATH\" bash '$RELAY' --list | grep -c 'SOLEUR_BOOTSTRAP_STAGE_DECL' | grep -qx 3"
assert "stage table has preflight(read), relay-env-secret(write), verify(read)" \
  "env -i PATH=\"$PATH\" bash '$RELAY' --list | grep -q 'stage=relay-env-secret class=write' && env -i PATH=\"$PATH\" bash '$RELAY' --list | grep -q 'stage=preflight class=read' && env -i PATH=\"$PATH\" bash '$RELAY' --list | grep -q 'stage=verify class=read'"
assert "reads the sensitive output with terraform output -raw" "grep -qF 'terraform output -raw \"\$TF_OUTPUT\"' '$RELAY' || grep -qE 'terraform output -raw' '$RELAY'"
assert "the output read runs under doppler run -p soleur -c prd_terraform (state creds)" "grep -qF 'doppler run -p soleur -c prd_terraform -- terraform output -raw' '$RELAY'"
assert "the token name constant is inngest_cutover_write_token" "grep -qF 'TF_OUTPUT=\"inngest_cutover_write_token\"' '$RELAY'"
assert "delivers via gh secret set --env inngest-cutover on stdin (never argv)" \
  "grep -qF '| gh secret set \"\$ENV_SECRET\" --env \"\$GH_ENVIRONMENT\"' '$RELAY' && grep -qF '\"\$tokval\" |' '$RELAY'"
assert "the environment is the pinned inngest-cutover" "grep -qF 'GH_ENVIRONMENT=\"inngest-cutover\"' '$RELAY'"
assert "the secret name is DOPPLER_TOKEN_INNGEST_CUTOVER_WRITE" "grep -qF 'ENV_SECRET=\"DOPPLER_TOKEN_INNGEST_CUTOVER_WRITE\"' '$RELAY'"
assert "the key is never echoed (no echo/printf of tokval outside the gh pipe)" \
  "! grep -nE 'echo[^|]*tokval|printf[^|]*tokval[^|]*>[^|]' '$RELAY' | grep -v 'gh secret set'"
assert "records only a SHA-256 hash of the key in .env (never the key)" \
  "grep -qF 'RELAY_TOKEN_SHA256' '$RELAY' && ! grep -qE 'env_upsert .*(tokval|TOKEN_VALUE|TF_OUTPUT)' '$RELAY'"
assert "sources the shared operator-script library" "grep -qE 'source .\\\$SOLEUR_OP_LIB.' '$RELAY'"
assert "declares the staged gate (SOLEUR-STAGE lines present)" "grep -c '^# SOLEUR-STAGE ' '$RELAY' | grep -qx 3"
assert "syntax-clean (bash -n)" "bash -n '$RELAY'"
assert "ledger/env file is .gitignore-covered (the contract's own check stays)" "git -C '$ROOT' check-ignore -q knowledge-base/project/specs/feat-one-shot-9927-d2-2-new-write-path/.env"

echo ""
echo "=== Results: $pass passed, $fail failed ==="
[ "$fail" -gt 0 ] && exit 1
exit 0
