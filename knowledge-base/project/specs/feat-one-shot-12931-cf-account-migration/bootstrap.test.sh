#!/usr/bin/env bash
# bootstrap.test.sh — the #12931 Doppler bootstrap (bootstrap.sh beside this file), CTO ruling D11.
#
# PROPERTIES
#   P1 the whole stage sequence, driven the way an agent drives it (plan, then the REAL approval
#      hook mints a receipt for the exact apply command, then that command runs), moves a
#      synthesized pre-flip world to the post-swap world, and every write stage is then satisfied
#      (operations=0);
#   P2 branch-copies-tokens refuses (PRECONDITION_FAILED need=swap-0b, zero writes) while any
#      CF_API_TOKEN_PURGE_NEXT / CF_API_TOKEN_DNS_EDIT_NEXT exists — before swap-0b, and after it
#      when a fresh token is staged again;
#   P3 a swap whose write does not read back equal leaves <KEY>_NEXT in place (the digest compare
#      sits ABOVE the delete);
#   P4 a failed scope probe stops a swap before its first write;
#   P5 every plan makes no mutating Doppler call; an apply with no receipt exits 75 and writes
#      nothing; no synthesized secret value ever reaches stdout or stderr.
#
# ASSEMBLY. A fixture git repository per world holds a copy of bootstrap.sh at its real relative
# path, a synthesized doppler-config-inventory.txt, and a stub cf-token-scope.sh (the script runs
# only TRACKED files, so the stub is committed). PATH-stubbed `doppler` keeps state in files and
# logs every call; PATH-stubbed `curl` answers /user/tokens/verify. Nothing reaches a network.
# Fixtures are synthesized (cq-test-fixtures-synthesized-only): the ids are the public account and
# zone ids from the runbook's id table, the token values are sentinel strings.
#
# MUTATIONS (each proven to land: cmp differs, bash -n clean), each must turn its row RED:
#   M1 the _NEXT delete moved ABOVE the digest compare          -> P3 row
#   M2 the branch-copies-tokens _NEXT refusal dropped            -> P2b row
#   M3 the scope probe call dropped from the swap apply          -> P4 row
#
# REGISTRATION: scripts/test-all.sh runs this through tests/scripts/test-cf-account-migration-bootstrap.sh,
# a locator that finds this file by glob, so an archive-kb move of the spec directory breaks nothing.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
export LC_ALL=C

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SUITE_DIR" rev-parse --show-toplevel 2>/dev/null)" || { printf 'HARNESS: not in a git work tree\n' >&2; exit 2; }
SCRIPT_SRC="${SUITE_DIR}/bootstrap.sh"
LIB="${REPO_ROOT}/plugins/soleur/scripts/lib/operator-script.sh"
HOOK="${REPO_ROOT}/plugins/soleur/hooks/operator-stage-approval.sh"
REL="knowledge-base/project/specs/feat-one-shot-12931-cf-account-migration/bootstrap.sh"

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY\n' >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# shellcheck source=../../../../plugins/soleur/test/lib/git-fixture-env.sh
source "${REPO_ROOT}/plugins/soleur/test/lib/git-fixture-env.sh"

for bin in jq timeout git perl cmp; do command -v "$bin" >/dev/null 2>&1 || { printf 'HARNESS: %s is required\n' "$bin" >&2; exit 2; }; done
[[ -r "$SCRIPT_SRC" && -r "$LIB" && -r "$HOOK" ]] || { printf 'HARNESS: script, library or hook missing\n' >&2; exit 2; }

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  [ok] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; }
check() { if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1 (last out: $(printf '%s' "${OUT:-}" | tr '\n' ' ' | cut -c1-300))"; fi; }

# Instrument self-test: both helpers must move their counter.
check "instrument self-test (pass arm)" 0 >/dev/null
check "instrument self-test (fail arm)" 1 >/dev/null 2>&1
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then printf 'INSTRUMENT SELF-TEST FAILED (pass=%s fail=%s)\n' "$PASS" "$FAIL" >&2; exit 2; fi
PASS=0; FAIL=0

SB="$(mktemp -d -t cfam-bootstrap.XXXXXXXX)" || { printf 'HARNESS: mktemp failed\n' >&2; exit 2; }
trap 'chmod -R u+rwx "$SB" 2>/dev/null; rm -rf "$SB"' EXIT
ALL_OUT="$SB/all-output.log"; : > "$ALL_OUT"

readonly NZ=951ce525552201ec6c696b24251abed7 NA=66d4f93f7397f196544e9fe84c3557c2
readonly OZ=5af02a2f394e9ba6e0ea23c381a26b67 OA=4d5ba6f096b2686fbdd404167dd4e125
readonly K0A=(CF_API_TOKEN CF_API_TOKEN_RULESETS CF_API_TOKEN_PAGES)
readonly K0B=(CF_API_TOKEN_ZONE_SETTINGS CF_API_TOKEN_BOT_MANAGEMENT CF_API_TOKEN_DNS_EDIT CF_API_TOKEN_PURGE)
old_val() { printf 'SYNTH-OLD-%s-SENTINEL' "$1"; }
new_val() { printf 'SYNTH-NEW-%s-SENTINEL' "$1"; }

# --- stubs ----------------------------------------------------------------------
write_stubs() { # <bin-dir>
  local b="$1"; assert_fixture_dir "$b"; mkdir -p "$b"
  cat > "$b/doppler" <<'DOPPLER'
#!/usr/bin/env bash
# State: $STUB_D/<config>/<NAME> holds a value (no trailing newline). Flags:
#   $STUB_D/.unreadable/<config>       the names listing of <config> fails
#   $STUB_D/.corrupt/<config>.<NAME>   a set of that name stores a DIFFERENT value
log() { printf '%s\t%s\n' "$1" "$2" >> "$STUB_LOG"; }
args=("$@"); proj=""; cfg=""; i=0
while (( i < ${#args[@]} )); do
  case "${args[i]}" in -p) proj="${args[i+1]:-}"; i=$((i+2)) ;; -c) cfg="${args[i+1]:-}"; i=$((i+2)) ;; *) i=$((i+1)) ;; esac
done
[[ "$proj" == "soleur" && -n "$cfg" ]] || { log mutating "BADARGS $*"; exit 64; }
D="$STUB_D/$cfg"
case "$1 ${2:-}" in
  "secrets --only-names")
    log read "list $cfg"
    [[ "${3:-}" == "--json" ]] || exit 64
    [[ -e "$STUB_D/.unreadable/$cfg" || ! -d "$D" ]] && exit 1
    ls -1 "$D" | jq -R -s -c 'split("\n") | map(select(length > 0)) | map({(.): {}}) | add // {}'
    exit 0 ;;
  "secrets get")
    log read "get $cfg/$3"
    [[ " $* " == *" --plain "* ]] || exit 64
    [[ -f "$D/$3" ]] || exit 1
    cat "$D/$3"; exit 0 ;;
  "secrets set")
    log mutating "set $cfg/$3"
    [[ " $* " == *" --silent "* ]] || exit 64
    mkdir -p "$D"
    if [[ -e "$STUB_D/.corrupt/$cfg.$3" ]]; then { cat; printf 'CORRUPTED'; } > "$D/$3"; else cat > "$D/$3"; fi
    exit 0 ;;
  "secrets delete")
    log mutating "delete $cfg/$3"
    [[ " $* " == *" --yes "* ]] || exit 64
    rm -f "$D/$3"; exit 0 ;;
esac
log mutating "UNMODELLED $*"
exit 64
DOPPLER
  cat > "$b/curl" <<'CURL'
#!/usr/bin/env bash
url=""; for a in "$@"; do case "$a" in https://*) url="$a" ;; esac; done
printf 'read\tcurl %s\n' "$url" >> "$STUB_LOG"
[[ "$url" == "https://api.cloudflare.com/client/v4/user/tokens/verify" ]] || exit 64
cfg="$(cat)"
if [[ ! -e "$STUB_D/.curl-inactive" ]] && grep -qE '^header = "Authorization: Bearer SYNTH-[A-Z0-9_-]+"$' <<<"$cfg"; then
  printf '{"success":true,"result":{"id":"x","status":"active"}}'
else
  printf '{"success":false,"errors":[{"code":1000}]}'
fi
CURL
  chmod +x "$b/doppler" "$b/curl"
}

# make_repo <dir> <bootstrap-src> — a fixture repository tracking the script, the inventory and a
# stub cf-token-scope.sh.
make_repo() {
  local r="$1" src="$2"; assert_fixture_dir "$r"
  mkdir -p "$r/$(dirname "$REL")" "$r/apps/web-platform/infra" "$r/plugins/soleur/skills/cf-token-scope/scripts"
  cp "$src" "$r/$REL"
  printf '# synthesized inventory\nprd_terraform\nprd\nprd_cla\ndev\nprd_other\n' > "$r/apps/web-platform/infra/doppler-config-inventory.txt"
  cat > "$r/plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh" <<'SCOPE'
#!/usr/bin/env bash
printf 'read\tscope %s\n' "$*" >> "$STUB_LOG"
prof=""; [[ "${1:-}" == "--profile" ]] && prof="${2:-}"
if [[ -e "$STUB_D/.scope-fail" ]]; then echo "probe=$prof verdict=denied"; exit 3; fi
echo "cf-token-scope: migration profile $prof (stub)"
echo "probe=$prof verdict=pass"
SCOPE
  printf '.env\n.env.tmp.*\nbootstrap-runs.jsonl\n' > "$r/.gitignore"
  ( git_fixture_env "$r" || exit 1
    cd "$r" && git init -q . && git add -A && git commit -qm fixture ) >/dev/null 2>&1 || { printf 'HARNESS: fixture repo failed\n' >&2; exit 2; }
}

# world <name> [<bootstrap-src>] — fresh state, the pre-flip world, a fixture repo.
world() {
  local src="${2:-$SCRIPT_SRC}" k c
  W="$SB/w-$1"; rm -rf "$W"; mkdir -p "$W/state" "$W/xdg"
  write_stubs "$W/bin"
  make_repo "$W/repo" "$src"
  S="$W/repo/$REL"
  STUB_D="$W/state"; STUB_LOG="$W/calls.log"; : > "$STUB_LOG"
  mkdir -p "$STUB_D/prd_terraform" "$STUB_D/prd" "$STUB_D/prd_cla" "$STUB_D/dev" "$STUB_D/prd_other" "$STUB_D/.corrupt" "$STUB_D/.unreadable"
  sv() { printf '%s' "$3" > "$STUB_D/$1/$2"; }
  sv prd_terraform CF_ZONE_ID "$OZ"; sv prd_terraform CF_ACCOUNT_ID "$OA"; sv prd_terraform CF_R2_ACCOUNT_ID "$OA"
  for k in "${K0A[@]}" "${K0B[@]}"; do sv prd_terraform "$k" "$(old_val "$k")"; sv prd_terraform "${k}_NEXT" "$(new_val "$k")"; done
  sv prd CF_ZONE_ID "$OZ"; sv prd CF_API_TOKEN_PURGE "$(old_val CF_API_TOKEN_PURGE)"; sv prd CF_API_TOKEN_DNS_EDIT "$(old_val CF_API_TOKEN_DNS_EDIT)"
  sv prd OTHER_KEY unrelated
  sv prd_cla CF_ZONE_ID "$OZ"; sv prd_cla OTHER_KEY unrelated
  sv dev CF_ZONE_ID "$OZ"; sv dev OTHER_KEY unrelated
  sv prd_other OTHER_KEY unrelated
  CHILD_ENV=("PATH=$W/bin:$PATH" "SOLEUR_OP_LIB=$LIB" "ENV_FILE=$W/xdg/.env" "SOLEUR_BOOTSTRAP_LEDGER=$W/ledger.jsonl"
             "STUB_D=$STUB_D" "STUB_LOG=$STUB_LOG" "XDG_STATE_HOME=$W/xdg")
}
val() { cat "$STUB_D/$1/$2" 2>/dev/null; }
has() { [[ -f "$STUB_D/$1/$2" ]]; }

OUT=""; RC=0
run() {
  OUT="$(env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_CODE_ENTRYPOINT "${CHILD_ENV[@]}" timeout 60 bash "$S" "$@" </dev/null 2>&1)"; RC=$?
  printf '%s\n' "$OUT" >> "$ALL_OUT"
}
digest() { sed -n 's/^SOLEUR_BOOTSTRAP_PLAN stage=[^ ]* operations=[0-9]* digest=\([0-9a-f]*\)$/\1/p' <<<"$OUT"; }
ops() { sed -n 's/^SOLEUR_BOOTSTRAP_PLAN stage=[^ ]* operations=\([0-9]*\) digest=.*$/\1/p' <<<"$OUT"; }
mut() { grep -c "^mutating" "$STUB_LOG" || true; }
# approve <stage>: plan, the REAL hook mints a receipt for the exact apply command, then the
# rewritten command runs as the harness would run it. Leaves OUT/RC of the apply.
approve() {
  local stage="$1" d cmd in newc
  run --stage "$stage"
  d="$(digest)"
  [[ -n "$d" && "$(ops)" -gt 0 ]] || { OUT="approve(): no plan with operations for ${stage}: ${OUT}"; RC=99; return; }
  cmd="bash $S --stage $stage --apply --plan-digest $d"
  in="$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c},permission_mode:"default",session_id:"s",cwd:"/",hook_event_name:"PreToolUse"}')"
  newc="$(printf '%s' "$in" | env "XDG_STATE_HOME=$W/xdg" CLAUDE_CODE_ENTRYPOINT=cli bash "$HOOK" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
  [[ -n "$newc" ]] || { OUT="approve(): the hook minted nothing for: ${cmd}"; RC=98; return; }
  OUT="$(env -u CLAUDE_PLUGIN_ROOT "${CHILD_ENV[@]}" timeout 60 bash -c "$newc" </dev/null 2>&1)"; RC=$?
  printf '%s\n' "$OUT" >> "$ALL_OUT"
}

# --- rows (each returns 0 when its property holds; callable on a mutant source) ---------
row_p3_mismatch_keeps_next() { # <bootstrap-src>
  world p3 "$1"
  approve prev-0a; [[ "$RC" -eq 0 ]] || return 1
  approve flip-ids; [[ "$RC" -eq 0 ]] || return 1
  : > "$STUB_D/.corrupt/prd_terraform.CF_API_TOKEN_RULESETS"
  approve swap-0a
  [[ "$RC" -ne 0 ]] || return 1
  grep -qF 'SOLEUR_CFAM_SWAP_MISMATCH name=CF_API_TOKEN_RULESETS kept=CF_API_TOKEN_RULESETS_NEXT' <<<"$OUT" || return 1
  has prd_terraform CF_API_TOKEN_RULESETS_NEXT || return 1
  [[ "$(val prd_terraform CF_API_TOKEN_RULESETS_NEXT)" == "$(new_val CF_API_TOKEN_RULESETS)" ]] || return 1
  # the two keys whose writes read back equal were swapped and their staging keys deleted
  ! has prd_terraform CF_API_TOKEN_NEXT && ! has prd_terraform CF_API_TOKEN_PAGES_NEXT
}
row_p2b_restaged_refuses() { # <bootstrap-src>
  local s
  world p2b "$1"
  for s in prev-0a flip-ids swap-0a branch-copies-zone-id prev-0b swap-0b; do approve "$s"; [[ "$RC" -eq 0 ]] || return 1; done
  printf '%s' "SYNTH-NEW2-CF_API_TOKEN_PURGE-SENTINEL" > "$STUB_D/prd_terraform/CF_API_TOKEN_PURGE_NEXT"
  : > "$STUB_LOG"
  run --stage branch-copies-tokens
  [[ "$RC" -eq 1 && -z "$(digest)" && "$(mut)" -eq 0 ]] && grep -qF 'SOLEUR_BOOTSTRAP_PRECONDITION_FAILED stage=branch-copies-tokens need=swap-0b' <<<"$OUT"
}
row_p4_probe_fail_stops() { # <bootstrap-src>
  world p4 "$1"
  approve prev-0a; [[ "$RC" -eq 0 ]] || return 1
  approve flip-ids; [[ "$RC" -eq 0 ]] || return 1
  : > "$STUB_D/.scope-fail"
  : > "$STUB_LOG"
  approve swap-0a
  [[ "$RC" -ne 0 ]] || return 1
  grep -qE '^read[[:space:]]scope --profile redirects-dns --staged$' "$STUB_LOG" || return 1
  [[ "$(mut)" -eq 0 ]] || return 1
  [[ "$(val prd_terraform CF_API_TOKEN)" == "$(old_val CF_API_TOKEN)" ]] && has prd_terraform CF_API_TOKEN_NEXT
}

echo "== --list =="
world list
run --list
[[ "$RC" -eq 0 && "$(grep -c '^SOLEUR_BOOTSTRAP_STAGE_DECL ' <<<"$OUT")" -eq 9 ]] \
  && grep -qx 'SOLEUR_BOOTSTRAP_STAGE_DECL stage=inventory class=read' <<<"$OUT" \
  && grep -qx 'SOLEUR_BOOTSTRAP_STAGE_DECL stage=branch-copies-tokens class=write' <<<"$OUT" \
  && grep -qx 'SOLEUR_BOOTSTRAP_STAGE_DECL stage=verify class=read' <<<"$OUT" \
  && [[ "$(grep -c . "$STUB_LOG")" -eq 0 ]]
check "--list: nine stages (inventory and verify read, the rest write), no vendor call" $?

echo "== P5: plans write nothing; no receipt, no write =="
world plans
for st in prev-0a flip-ids swap-0a branch-copies-zone-id prev-0b swap-0b branch-copies-tokens; do
  : > "$STUB_LOG"
  run --stage "$st"
  [[ "$(mut)" -eq 0 ]] && { [[ -n "$(digest)" ]] || grep -qF "SOLEUR_BOOTSTRAP_PRECONDITION_FAILED stage=${st}" <<<"$OUT"; }
  check "plan of ${st}: a plan or a named precondition, zero mutating calls" $?
done
run --stage prev-0a
d="$(digest)"; : > "$STUB_LOG"
run --stage prev-0a --apply --plan-digest "$d"
[[ "$RC" -eq 75 && "$(mut)" -eq 0 ]] && grep -qF 'SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED stage=prev-0a' <<<"$OUT"
check "prev-0a --apply with no receipt: exit 75 APPROVAL_REQUIRED, nothing written" $?
run --stage flip-ids
[[ "$RC" -eq 1 && "$(mut)" -eq 0 ]] && grep -qF 'SOLEUR_BOOTSTRAP_PRECONDITION_FAILED stage=flip-ids need=prev-0a' <<<"$OUT"
check "flip-ids before prev-0a: PRECONDITION_FAILED need=prev-0a" $?
run --stage swap-0a
grep -qF 'SOLEUR_BOOTSTRAP_PRECONDITION_FAILED stage=swap-0a need=flip-ids' <<<"$OUT"
check "swap-0a before the flip: PRECONDITION_FAILED need=flip-ids" $?

echo "== P1: the whole sequence =="
world seq
run --stage inventory
[[ "$RC" -eq 0 ]] && grep -qx 'SOLEUR_CFAM_HOLDER config=prd name=CF_API_TOKEN_PURGE' <<<"$OUT" \
  && grep -qx 'SOLEUR_CFAM_STAGED config=prd_terraform name=CF_API_TOKEN_RULESETS_NEXT' <<<"$OUT" \
  && ! grep -q 'config=prd_other' <<<"$OUT"
check "inventory: names holders and staged keys by name, nothing for a config with no watched key" $?
approve prev-0a
[[ "$RC" -eq 0 && "$(val prd_terraform CF_ZONE_ID_PREV)" == "$OZ" && "$(val prd_terraform CF_API_TOKEN_PAGES_PREV)" == "$(old_val CF_API_TOKEN_PAGES)" ]] \
  && grep -qF 'SOLEUR_BOOTSTRAP_STAGE_OK stage=prev-0a changed=1 approval=harness-receipt' <<<"$OUT"
check "prev-0a: revert copies of both ids and the three 0a tokens, through a harness receipt" $?
approve flip-ids
[[ "$RC" -eq 0 && "$(val prd_terraform CF_ZONE_ID)" == "$NZ" && "$(val prd_terraform CF_ACCOUNT_ID)" == "$NA" && "$(val prd_terraform CF_R2_ACCOUNT_ID)" == "$OA" ]]
check "flip-ids: zone and account flipped, CF_R2_ACCOUNT_ID untouched" $?
run --stage prev-0a
[[ "$RC" -eq 0 && "$(ops)" == "0" ]]
check "prev-0a after the flip: satisfied (an existing revert copy is never overwritten)" $?
: > "$STUB_LOG"
approve swap-0a
[[ "$RC" -eq 0 ]] && grep -qE '^read[[:space:]]scope --profile redirects-dns --staged$' "$STUB_LOG" \
  && [[ "$(val prd_terraform CF_API_TOKEN_RULESETS)" == "$(new_val CF_API_TOKEN_RULESETS)" ]] \
  && ! has prd_terraform CF_API_TOKEN_NEXT && ! has prd_terraform CF_API_TOKEN_RULESETS_NEXT && ! has prd_terraform CF_API_TOKEN_PAGES_NEXT
check "swap-0a: staged probe ran, live keys hold the new tokens, staging keys deleted" $?
s_idx="$(grep -nE '^read[[:space:]]scope ' "$STUB_LOG" | head -1 | cut -d: -f1)"; w_idx="$(grep -nE '^mutating' "$STUB_LOG" | head -1 | cut -d: -f1)"
[[ -n "$s_idx" && -n "$w_idx" && "$s_idx" -lt "$w_idx" ]]
check "swap-0a: the scope probe ran before the first write" $?
approve branch-copies-zone-id
[[ "$RC" -eq 0 && "$(val prd CF_ZONE_ID)" == "$NZ" && "$(val prd_cla CF_ZONE_ID)" == "$NZ" && "$(val dev CF_ZONE_ID)" == "$NZ" ]] && ! has prd_other CF_ZONE_ID
check "branch-copies-zone-id: every holder gets the new id, a non-holder gets nothing" $?
: > "$STUB_LOG"
run --stage branch-copies-tokens
[[ "$RC" -eq 1 && "$(mut)" -eq 0 && -z "$(digest)" ]] && grep -qF 'SOLEUR_BOOTSTRAP_PRECONDITION_FAILED stage=branch-copies-tokens need=swap-0b' <<<"$OUT" \
  && [[ "$(val prd CF_API_TOKEN_PURGE)" == "$(old_val CF_API_TOKEN_PURGE)" ]]
check "P2a branch-copies-tokens before swap-0b: PRECONDITION_FAILED need=swap-0b, prd keeps its value" $?
approve prev-0b; check "prev-0b applies" "$RC"
: > "$STUB_LOG"
approve swap-0b
[[ "$RC" -eq 0 ]] && grep -qE '^read[[:space:]]scope --profile zone-rest --staged$' "$STUB_LOG" \
  && [[ "$(grep -c 'curl https://api.cloudflare.com/client/v4/user/tokens/verify' "$STUB_LOG")" -eq 2 ]] \
  && [[ "$(val prd_terraform CF_API_TOKEN_PURGE)" == "$(new_val CF_API_TOKEN_PURGE)" ]] && ! has prd_terraform CF_API_TOKEN_DNS_EDIT_NEXT
check "swap-0b: zone-rest probe plus two active checks (DNS_EDIT, PURGE), then the swap" $?
approve branch-copies-tokens
[[ "$RC" -eq 0 && "$(val prd CF_API_TOKEN_PURGE)" == "$(new_val CF_API_TOKEN_PURGE)" && "$(val prd CF_API_TOKEN_DNS_EDIT)" == "$(new_val CF_API_TOKEN_DNS_EDIT)" ]] && ! has prd_cla CF_API_TOKEN_PURGE
check "branch-copies-tokens: prd takes the new PURGE and DNS_EDIT from prd_terraform; non-holders untouched" $?
run --stage verify
[[ "$RC" -eq 0 ]] && grep -qx 'SOLEUR_CFAM_VERIFY verdict=ok' <<<"$OUT" && ! grep -q 'verdict=fail' <<<"$OUT"
check "verify: every check ok" $?
allzero=0
for st in prev-0a flip-ids swap-0a branch-copies-zone-id prev-0b swap-0b branch-copies-tokens; do
  : > "$STUB_LOG"; run --stage "$st"
  [[ "$RC" -eq 0 && "$(ops)" == "0" && "$(mut)" -eq 0 ]] || { allzero=1; echo "    not satisfied: $st ($(ops))"; }
done
check "every write stage is satisfied afterwards (operations=0, no write)" "$allzero"
printf '%s' "$OA" > "$STUB_D/prd_terraform/CF_ZONE_ID"
run --stage verify
[[ "$RC" -eq 1 ]] && grep -qx 'SOLEUR_CFAM_VERIFY check=prd_terraform/CF_ZONE_ID=new verdict=fail' <<<"$OUT"
check "verify goes red (STAGE_FAILED) when a checked value regresses" $?

echo "== flip-ids guard (D8 parity) =="
world r2
approve prev-0a
printf '%s' "$NA" > "$STUB_D/prd_terraform/CF_R2_ACCOUNT_ID"
run --stage flip-ids
[[ "$RC" -eq 1 && -z "$(digest)" ]] && grep -qF 'SOLEUR_BOOTSTRAP_PRECONDITION_FAILED stage=flip-ids need=inventory' <<<"$OUT"
check "flip-ids refuses while CF_R2_ACCOUNT_ID holds the new account id" $?

echo "== unreadable is inconclusive, never absent =="
world unread
approve prev-0a; approve flip-ids
: > "$STUB_D/.unreadable/prd_cla"
run --stage branch-copies-zone-id
[[ "$RC" -eq 1 && -z "$(digest)" ]] && grep -qF 'SOLEUR_BOOTSTRAP_PRECONDITION_FAILED stage=branch-copies-zone-id need=inventory' <<<"$OUT"
check "branch-copies-zone-id refuses when one config's names listing is unreadable" $?

echo "== P2b / P3 / P4 on the real script =="
row_p2b_restaged_refuses "$SCRIPT_SRC"; check "P2b branch-copies-tokens refuses while a fresh _NEXT is staged after swap-0b" $?
row_p3_mismatch_keeps_next "$SCRIPT_SRC"; check "P3 a write that does not read back equal keeps <KEY>_NEXT" $?
row_p4_probe_fail_stops "$SCRIPT_SRC"; check "P4 a failed scope probe stops swap-0a before any write" $?

echo "== P5: no synthesized secret value in any output =="
! grep -qE 'SYNTH-(OLD|NEW)[^ ]*SENTINEL' "$ALL_OUT"
check "no SYNTH-*-SENTINEL value appears in any stdout/stderr" $?

echo "== mutations =="
mutate() { # <label> <dst> — perl program on stdin; proves it landed
  local label="$1" dst="$2" prog; prog="$(cat)"
  assert_fixture_dir "$dst"
  cp "$SCRIPT_SRC" "$dst"; perl -0777 -pi -e "$prog" "$dst"
  if cmp -s "$dst" "$SCRIPT_SRC"; then fail "mutation ${label} did not land"; return 1; fi
  bash -n "$dst" 2>/dev/null || { fail "mutation ${label} does not parse"; return 1; }
  pass "mutation ${label} landed (differs from the source, bash -n clean)"
}
if mutate M1 "$SB/m1.sh" <<'PERL'; then
s{(  for k in \$\{COPY_KEYS\[\@\]\+"\$\{COPY_KEYS\[\@\]\}"\} \$\{DEL_KEYS\[\@\]\+"\$\{DEL_KEYS\[\@\]\}"\}; do\n)}{$1    doppler secrets delete "\$\{k\}_NEXT" -p "\$PROJ" -c "\$TFC" --yes >/dev/null 2>&1 || true\n}
PERL
  row_p3_mismatch_keeps_next "$SB/m1.sh"; r=$?
  [[ "$r" -ne 0 ]]; check "M1 (delete above the compare) turns P3 RED" $?
fi
if mutate M2 "$SB/m2.sh" <<'PERL'; then
s{    in_names "\$\{k\}_NEXT" "\$TF_NAMES" \\\n      && soleur_op_precondition_failed branch-copies-tokens swap-0b [^\n]*\n}{}
PERL
  row_p2b_restaged_refuses "$SB/m2.sh"; r=$?
  [[ "$r" -ne 0 ]]; check "M2 (the _NEXT refusal dropped) turns P2b RED" $?
fi
if mutate M3 "$SB/m3.sh" <<'PERL'; then
s{    run_scope_probe "\$profile" \|\| return 1\n}{}
PERL
  row_p4_probe_fail_stops "$SB/m3.sh"; r=$?
  [[ "$r" -ne 0 ]]; check "M3 (the scope probe dropped) turns P4 RED" $?
fi

# --- anti-vacuity floor (reported directly, never through fail()) ---------------
TOTAL=$((PASS + FAIL))
FLOOR=37
if [[ "$TOTAL" -lt "$FLOOR" ]]; then
  printf '  [FAIL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$TOTAL" "$FLOOR" >&2
  printf 'Total: %s assertions, %s failed\n' "$TOTAL" "$((FAIL + 1))"
  exit 1
fi
echo "Total: ${TOTAL} assertions, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
