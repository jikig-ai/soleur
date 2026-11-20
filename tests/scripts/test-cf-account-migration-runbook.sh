#!/usr/bin/env bash
# test-cf-account-migration-runbook.sh — the text contract of the #12931 Cloudflare account-migration
# runbook, against the tools it tells an agent to run (CTO rulings D3, D4, D5, D11, 2026-11-19).
#
# PROPERTIES (each row is a function over a runbook path, so a mutant copy can be fed to it):
#   R1 (D4) no line runs `terraform state push`: the full revert is withdrawn, the backup is DR
#      evidence only; and a `## Halt` section exists;
#   R2 (D5) in the Phase 3 reopen step the `git log … -- apps/web-platform/infra` line and the
#      scheduled-terraform-drift read both come BEFORE the `apply_target=manual-rerun` dispatch;
#   R3 (D3) the reopen step's expected output names a `cloudflare_ruleset.cache_shared_binaries`
#      create, and the redirects-dns expectation says the cache rule is not in that phase;
#   R4 (D11) every stage bootstrap.sh declares is named in the runbook, and every
#      `--stage <name>` the runbook issues is a declared stage;
#   R5 the probe verdict the runbook expects is the one cf-token-scope.sh prints
#      (`probe=<phase> verdict=pass`), and the withdrawn `verdict=authorized` / "plus a live
#      connector" wording is gone;
#   R6 the agent-never-approves-its-own-environment line and the revoke read-back are present;
#   R7 the B line resolves exactly one bootstrap.sh or stops;
#   R8..R13 the Halt state machine (review fr3): per-key NEW/OLD reads for the revert-copy check
#      (D1); every bootstrap failure marker has a Halt action, derived from bootstrap.sh (D20);
#      forget-committed is a cross-run fact and the cancel arms are ordered (D7); verify-failed
#      step 4's positive control and expected_in_state_updates (D8); the import-block class flip,
#      the half-replace row and the gptbot=>403 action (D11); /health prints redirect_url, the
#      revert keeps the new token in _NEXT, and the --preserve-env precedence (D30b, D10).
#
# MUTATIONS (each proven to land, then must turn its row RED):
#   M1 append a `terraform state push -force` line            -> R1
#   M2 move the manual-rerun dispatch above the git-log line   -> R2
#   M3 delete the reopen step's cache_shared_binaries create   -> R3
#   M4 rename one runbook mention of branch-copies-tokens      -> R4
#   M5 reintroduce `verdict=authorized`                        -> R5
#   M6-M7 an undeclared stage -> R4; M8 the B line's stop no longer fails -> R7;
#   M9-M21 one per Halt guard -> R8..R13 (M12 mutates a copy of bootstrap.sh, not the runbook).
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null)" || { echo "HARNESS: not in a git work tree" >&2; exit 2; }
RUNBOOK="${REPO_ROOT}/knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md"
# Exactly one copy, or a stale second copy (an untracked leftover, a re-archive) is what R4 reads.
mapfile -t _bs < <(git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard --full-name '*feat-one-shot-12931-cf-account-migration/bootstrap.sh')
[[ "${#_bs[@]}" -eq 1 ]] || { echo "HARNESS: expected exactly 1 bootstrap.sh, found ${#_bs[@]}" >&2; exit 2; }
BOOTSTRAP="${_bs[0]}"
SCOPE_TOOL="${REPO_ROOT}/plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh"
[[ -r "$RUNBOOK" && -n "$BOOTSTRAP" && -r "${REPO_ROOT}/${BOOTSTRAP}" && -r "$SCOPE_TOOL" ]] \
  || { echo "HARNESS: runbook, bootstrap or cf-token-scope.sh missing" >&2; exit 2; }
BOOTSTRAP="${REPO_ROOT}/${BOOTSTRAP}"

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  [ok] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; }
check() { if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1"; fi; }

check "instrument self-test (pass arm)" 0 >/dev/null
check "instrument self-test (fail arm)" 1 >/dev/null 2>&1
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then echo "INSTRUMENT SELF-TEST FAILED" >&2; exit 2; fi
PASS=0; FAIL=0

SB="$(mktemp -d -t cfam-runbook.XXXXXXXX)" || { echo "HARNESS: mktemp failed" >&2; exit 2; }
# shellcheck source=../../plugins/soleur/test/lib/git-fixture-env.sh
source "${REPO_ROOT}/plugins/soleur/test/lib/git-fixture-env.sh"
trap 'rm -rf "$SB"' EXIT

# The reopen step: from its bold title to the next numbered step.
reopen_block() { awk '/\*\*Reopen the routine path\*\*/{on=1} on && /^7\. /{exit} on' "$1"; }

row_r1() {
  ! grep -nE 'terraform[[:space:]]+state[[:space:]]+push' "$1" >/dev/null && grep -qx '## Halt' "$1"
}
row_r2() {
  local b gl dr mr
  b="$(reopen_block "$1")"; [[ -n "$b" ]] || return 1
  gl="$(grep -nF 'git log --oneline <PR1-merge-sha>..origin/main -- apps/web-platform/infra' <<<"$b" | head -1 | cut -d: -f1)"
  dr="$(grep -nF 'gh run list --workflow scheduled-terraform-drift.yml' <<<"$b" | head -1 | cut -d: -f1)"
  mr="$(grep -nF 'apply_target=manual-rerun' <<<"$b" | head -1 | cut -d: -f1)"
  [[ -n "$gl" && -n "$dr" && -n "$mr" && "$gl" -lt "$mr" && "$dr" -lt "$mr" ]]
}
row_r3() {
  grep -qF '`cloudflare_ruleset.cache_shared_binaries` create' < <(reopen_block "$1") \
    && grep -qF '`cache_shared_binaries` is not in this phase (CTO ruling D3)' "$1"
}
declared_stages() { grep -a '^# SOLEUR-STAGE ' "$BOOTSTRAP" | sed 's/^# SOLEUR-STAGE //' | cut -d'|' -f1; }
row_r4() {
  local s n bad=0
  for s in $(declared_stages); do grep -qF "\`${s}\`" "$1" || grep -qF -- "--stage ${s}" "$1" || { echo "    undeclared in runbook: $s" >&2; bad=1; }; done
  n="$(declared_stages | wc -l)"; [[ "$n" -ge 9 ]] || bad=1
  for s in $(grep -oE -- '--stage [a-z0-9-]+' "$1" | awk '{print $2}' | sort -u); do
    grep -qxF -- "$s" < <(declared_stages) || { echo "    runbook issues an undeclared stage: $s" >&2; bad=1; }
  done
  # every numbered stage item in Phase 2 ("1. `prev-0a`: …") is a declared stage
  for s in $(grep -oE '^[0-9]+\. `[a-z0-9-]+`:' "$1" | sed -E 's/^[0-9]+\. `([a-z0-9-]+)`:/\1/' | sort -u); do
    grep -qxF -- "$s" < <(declared_stages) || { echo "    numbered stage not declared: $s" >&2; bad=1; }
  done
  [[ "$bad" -eq 0 ]]
}
# R7: the runbook's B line resolves exactly one bootstrap.sh or stops: one copy prints its absolute
# path (exit 0); zero or two print verdict=stop with the count and exit non-zero, never an empty or
# multi-line B a later `bash "$B"` would run.
b_line() { grep -oE '^  `B="\$\(git ls-files.*; fi`\.$' "$1" | sed -e 's/^  `//' -e 's/`\.$//'; }
row_r7() {
  local line d n out rc
  line="$(b_line "$1")"; [[ -n "$line" ]] || { echo "    no B line" >&2; return 1; }
  for n in 0 1 2; do
    d="$SB/r7-$n"; rm -rf "$d"; mkdir -p "$d"
    (
      git_fixture_env "$d" || exit 1
      cd "$d" && git init -q . \
        && { [[ "$n" -lt 1 ]] || { mkdir -p a/feat-one-shot-12931-cf-account-migration && : > a/feat-one-shot-12931-cf-account-migration/bootstrap.sh; }; } \
        && { [[ "$n" -lt 2 ]] || { mkdir -p b/feat-one-shot-12931-cf-account-migration && : > b/feat-one-shot-12931-cf-account-migration/bootstrap.sh; }; } \
        && : > keep && git add -A && git commit -qm fixture ) >/dev/null 2>&1 || { echo "    HARNESS: r7 fixture $n" >&2; return 1; }
    # The B line runs git too, so it runs under the same fixture env (never the operator's git config).
    rc=0; out="$(
      git_fixture_env "$d" || exit 97
      cd "$d" && bash -c "$line" 2>&1
    )" || rc=$?
    case "$n" in
      1) [[ "$rc" -eq 0 && "$out" == "SOLEUR_CFAM_BOOTSTRAP path=$(cd "$d" && pwd -P)/a/feat-one-shot-12931-cf-account-migration/bootstrap.sh" ]] || { echo "    one copy: rc=$rc out=$out" >&2; return 1; } ;;
      *) [[ "$rc" -ne 0 && "$out" == "SOLEUR_CFAM_BOOTSTRAP verdict=stop matches=$n" ]] || { echo "    $n copies: rc=$rc out=$out" >&2; return 1; } ;;
    esac
  done
}
row_r5() {
  grep -qF 'probe=<phase> verdict=pass' "$1" \
    && ! grep -qE 'verdict=authorized|plus a live connector' "$1"
}
row_r6() {
  grep -qF '**The agent never approves its own environment gate.**' "$1" \
    && grep -qF 'Expected: `.success` is `false`' "$1"
}

# --- the Halt state machine (review fr3: D1, D7, D8, D10, D11, D20, D30b) -------------------------
# Prose wraps at ~120 columns, so a phrase is matched on a JOINED copy (newlines and runs of spaces
# folded to one space); table rows survive the join as substrings.
joined() { paste -sd' ' | tr -s ' '; }
halt_text() { awk '/^## Halt$/{on=1} on' "$1"; }
# halt_bullet <runbook> <anchor>: the top-level Halt bullet `- **<anchor>…` up to the next one, joined.
halt_bullet() { halt_text "$1" | awk -v a="- **$2" 'index($0, a) == 1 {on=1; print; next} on && /^- /{exit} on' | joined; }
# pos_of <haystack> <needle>: the needle's 0-based offset, or -1.
pos_of() { local pre="${1%%"$2"*}"; if [[ "$pre" == "$1" ]]; then echo -1; else echo "${#pre}"; fi; }
before() { local a b; a="$(pos_of "$1" "$2")"; b="$(pos_of "$1" "$3")"; [[ "$a" -ge 0 && "$b" -ge 0 && "$a" -lt "$b" ]]; }

JOB="${REPO_ROOT}/apps/web-platform/infra/scripts/cf-account-migrate-job.sh"
FORGET="${REPO_ROOT}/apps/web-platform/infra/scripts/cf-account-state-migrate.sh"
GATE="${REPO_ROOT}/tests/scripts/lib/cf-account-migrate-gate.sh"
[[ -r "$JOB" && -r "$FORGET" && -r "$GATE" ]] || { echo "HARNESS: job, state-migrate or gate lib missing" >&2; exit 2; }
bs_id() { sed -n "s/^readonly $1=\"\\([0-9a-f]\\{32\\}\\)\"\$/\\1/p" "$BOOTSTRAP"; }
NZ="$(bs_id NEW_ZONE)"; NA="$(bs_id NEW_ACCT)"; OZ="$(bs_id OLD_ZONE)"; OA="$(bs_id OLD_ACCT)"
[[ -n "$NZ" && -n "$NA" && -n "$OZ" && -n "$OA" ]] || { echo "HARNESS: bootstrap ids not found" >&2; exit 2; }
bs_keys() { sed -n -E 's/^readonly KEYS_0[AB]=\(([A-Z_ ]+)\)$/\1/p' "$BOOTSTRAP" | tr ' ' '\n' | grep .; }
# new_read <KEY>: the key's own read on the NEW resource. The job's token_probe_path is the source
# for every key it probes; DNS_EDIT and PURGE have no job probe, so they carry the ledger's D1 reads
# (DNS records; zone details, which Cloudflare accepts for Cache Purge).
new_read() {
  local lk m
  case "$1" in
    CF_API_TOKEN_DNS_EDIT) printf 'zones/%s/dns_records?per_page=1\n' "$NZ"; return 0 ;;
    CF_API_TOKEN_PURGE) printf 'zones/%s\n' "$NZ"; return 0 ;;
  esac
  lk="$(tr 'A-Z' 'a-z' <<<"$1")"
  m="$(sed -n -E "s/^[[:space:]]+${lk}\\) printf '([^']+)' \"\\\$CFAM_NEW_(ZONE|ACCOUNT)_ID\" ;;\$/\\1 \\2/p" "$JOB")"
  [[ -n "$m" ]] || return 1
  case "${m##* }" in ZONE) printf '%s\n' "${m% *}" | sed "s/%s/$NZ/" ;; ACCOUNT) printf '%s\n' "${m% *}" | sed "s/%s/$NA/" ;; esac
}
# R8 (D1): the "revert copy is not sound" check reads each key with its OWN read on the NEW and the
# OLD resource (a zone read fails for an account-scoped token), never a bare zone read; NEW means NEW
# success AND OLD not; any ambiguity or transport failure stops; the token stays off argv.
row_r8() {
  local b k nr or n=0 bad=0
  b="$(halt_bullet "$1" 'A revert copy is not sound')"; [[ -n "$b" ]] || { echo "    no revert-copy bullet" >&2; return 1; }
  for k in $(bs_keys); do
    n=$((n + 1))
    nr="$(new_read "$k")" || { echo "    no NEW read derivable for $k" >&2; bad=1; continue; }
    or="$(sed -e "s/$NZ/$OZ/" -e "s/$NA/$OA/" <<<"$nr")"
    grep -qF "| \`$k\` | \`$nr\` | \`$or\` |" <<<"$b" || { echo "    no per-key read row for $k: $nr / $or" >&2; bad=1; }
  done
  [[ "$n" -ge 7 ]] || { echo "    only $n bootstrap keys" >&2; bad=1; }
  grep -qF 'A key reads as NEW when its NEW read prints `true` AND its OLD read prints `false`' <<<"$b" || { echo "    no NEW rule" >&2; bad=1; }
  grep -qF 'If both keys read as NEW, or neither does, or any read fails in transport, stop for an owner decision: never pick one' <<<"$b" || { echo "    no stop rule" >&2; bad=1; }
  grep -qF 'printf "Authorization: Bearer %s\n" "$<KEY_OR_PREV>" \ | curl --disable --noproxy "*" -sS --max-time 30 --header @-' <<<"$b" || { echo "    token not on the stdin header form" >&2; bad=1; }
  ! grep -qF 'The one that prints `false` and verifies active' <<<"$b" || { echo "    withdrawn single zone-read rule still present" >&2; bad=1; }
  [[ "$bad" -eq 0 ]]
}
# failure_markers <bootstrap>: every SOLEUR_CFAM_* marker bootstrap.sh prints on a failure path, one
# key per line ("NAME" or "NAME verdict=<v>"). A printf is a failure emit when its format carries
# verdict=fail|not-pass, its name is a failure name, or the rest of its statement (up to the next
# printf) or the next line sets a failure (return/exit >0, fail=1, bad=1, VBAD=1). Formats with
# verdict=ok|pass are success emits.
failure_markers() {
  perl -0777 -ne '
    while (/printf \x27(SOLEUR_CFAM_[A-Z_]+)([^\x27]*)\x27(?=([^\n]*)\n([^\n]*))/g) {
      my ($n, $f, $rest, $nx) = ($1, $2, $3, $4);
      next if $f =~ /verdict=(ok|pass)\b/;
      $rest =~ s/printf \x27.*//;
      my $v = ($f =~ /verdict=(fail|not-pass)\b/) ? "verdict=$1" : "";
      my $bad = $v ne ""
        || $n =~ /_(FAILED|MISMATCH|MALFORMED|NOT_[A-Z]+|UNREADABLE|UNREACHABLE|IN_FLIGHT)$/
        || $rest =~ /\b(return [1-9]|exit [1-9]|fail=1|bad=1|VBAD=1)\b/
        || $nx =~ /^\s*(return [1-9]|exit [1-9]|fail=1|bad=1|VBAD=1)\b/;
      print $v ne "" ? "$n $v\n" : "$n\n" if $bad;
    }' "$1" | sort -u
}
# R9 (D20): every failure marker bootstrap.sh prints has a Halt action (named in backticks, with its
# verdict when it carries one). Derived from the script, so a new marker reds this row until the
# Halt names it. Anti-vacuity: at least 9 markers, and no success marker classified as a failure.
row_r9() {
  local h set n v cnt=0 bad=0
  h="$(halt_text "$1")"; set="$(failure_markers "${2:-$BOOTSTRAP}")"
  while read -r n v; do
    [[ -n "$n" ]] || continue
    cnt=$((cnt + 1))
    if [[ -n "$v" ]]; then
      grep -qE "\`${n} [^\`]*${v}" <<<"$h" || { echo "    Halt has no action for $n $v" >&2; bad=1; }
    else
      grep -qE "\`${n}[ \`]" <<<"$h" || { echo "    Halt has no action for $n" >&2; bad=1; }
    fi
  done <<<"$set"
  [[ "$cnt" -ge 9 ]] || { echo "    only $cnt failure markers derived" >&2; bad=1; }
  ! grep -qxE 'SOLEUR_CFAM_(COPIED|SWAPPED|ID_SET|TOKEN_ACTIVE|HOLDER|STAGED|REVERT)( .*)?' <<<"$set" || { echo "    a success marker was classified as a failure" >&2; bad=1; }
  [[ "$bad" -eq 0 ]]
}
# R10 (D7): "is the forget committed" is a cross-run fact; the cancelled-run arms are ordered
# applying=true first, read only with a positive control, and use the markers the scripts print;
# "Verify first" covers only stops after applying=true.
row_r10() {
  local c k a b bad=0
  c="$(halt_bullet "$1" 'Is the forget committed?')"
  for k in 'never of one run' 'gh issue view 12931 --json comments' '`pre-cf-account-migration-*` object' \
           '`forget=unknown` (on `state-migrate-failed` only): this run printed no `backup=uploaded`, so this run forgot nothing' \
           'only a `redirects-dns` `rehearsal=false` refusal carries it' 'cf-state-migrate verdict=abort reason=<code>'; do
    grep -qF -- "$k" <<<"$c" || { echo "    committed bullet lacks: $k" >&2; bad=1; }
  done
  # fr4 F1: a gh error is never silence. The loop prints an `unreadable` line for a run it cannot
  # read (no 2>/dev/null on gh run view), the bucket listing is a command, and "not committed"
  # needs all three sources answered.
  ! grep -qF 'gh run view "$r" --log 2>/dev/null' <<<"$c" && grep -qF 'echo "run=$r unreadable"' <<<"$c" \
    && grep -qF -- '--prefix "${CFAM_BACKUP_PREFIX}pre-cf-account-migration-"' <<<"$c" \
    && grep -qF 'ALL THREE' <<<"$c" && grep -qF 'Never read silence as "not committed"' <<<"$c" \
    || { echo "    committed record can read a gh error as not committed" >&2; bad=1; }
  c="$(halt_bullet "$1" 'The apply run was cancelled')"
  for k in 'gh run view <run-id> --json conclusion --jq .conclusion' \
           "gh run view <run-id> --log | grep -oE 'cf-account-migrate inflight=none|cf-state-migrate backup=uploaded|mode=apply (applying|applied)=true|verdict=refuse reason=[a-z-]+' | sort -u" \
           'Read an absence only when the output holds the job'"'"'s start line `cf-account-migrate inflight=none` or a `reason=` line'; do
    grep -qF -- "$k" <<<"$c" || { echo "    cancelled bullet lacks: $k" >&2; bad=1; }
  done
  before "$c" '1. `mode=apply applying=true` is present' '2. No `mode=apply applying=true`' || { echo "    applying=true arm is not first" >&2; bad=1; }
  ! grep -qF 'none of `backup=uploaded` means nothing was forgotten' "$1" || { echo "    withdrawn per-run arm present" >&2; bad=1; }
  a="$(halt_bullet "$1" 'A stop after `applying=true`')"; b="$(halt_bullet "$1" 'A stop before `applying=true`')"
  grep -qF 'Verify block first' <<<"$a" && ! grep -qE 'gate-refused|state-migrate-failed' <<<"$a" || { echo "    Verify-first bullet names a stop before applying=true" >&2; bad=1; }
  for k in '`gate-refused`' '`entrypoint-gate-refused`' '`state-migrate-failed`' 'no `mode=apply applying=true`' 're-rehearse, re-dispatch'; do
    grep -qF -- "$k" <<<"$b" || { echo "    before-applying bullet lacks: $k" >&2; bad=1; }
  done
  # The markers the runbook greps are the ones the scripts print.
  grep -qF "printf '%s phase=%s mode=apply applying=true\\n'" "$JOB" && grep -qF "printf '%s phase=%s mode=apply applied=true\\n'" "$JOB" \
    && grep -qF "printf '%s inflight=none workflows=" "$JOB" && grep -qxF 'readonly P="cf-account-migrate"' "$JOB" \
    && grep -qF "printf '%s backup=uploaded uri=%s\\n'" "$FORGET" && grep -qxF 'readonly P="cf-state-migrate"' "$FORGET" \
    || { echo "    a grepped marker is not printed by the scripts" >&2; bad=1; }
  [[ "$bad" -eq 0 ]]
}
# R11 (D8): Halt verify-failed step 4 reads the gate's own lines with a positive control (exactly one
# PASS line), names every address step 1 can edit as must-NOT, carries the set into the apply's
# expected_in_state_updates, and scopes the "only" rule to create-class addresses.
row_r11() {
  local s k bad=0
  s="$(halt_text "$1" | awk '/^  4\. Rehearse that phase\./{on=1} on && /^- \*\*/{exit} on' | joined)"
  [[ -n "$s" ]] || { echo "    no step 4" >&2; return 1; }
  for k in "grep -E 'cf_account_migrate_gate: (in-state-update |phase=[a-z-]+ verdict=PASS)'" \
           'Trust an absence only when the output holds exactly one `cf_account_migrate_gate: phase=<phase> verdict=PASS` line' \
           'must NOT be among the `in-state-update` lines' '`cloudflare_ruleset.seo_config_settings`' \
           '`cloudflare_ruleset.seo_page_redirects`' '`cloudflare_list.legal_redirects`' \
           "-f expected_in_state_updates='<address> …'" 'For a create-class address'; do
    grep -qF -- "$k" <<<"$s" || { echo "    step 4 lacks: $k" >&2; bad=1; }
  done
  grep -qF 'cf_account_migrate_gate: in-state-update ' "$GATE" && grep -qF 'cf_account_migrate_gate: phase=${phase} verdict=PASS' "$GATE" \
    || { echo "    the gate no longer prints the grepped lines" >&2; bad=1; }
  for k in seo_config_settings seo_page_redirects; do grep -qF "\"cloudflare_ruleset.${k}\": \"create\"" "$GATE" || { echo "    $k not create-class in the spec" >&2; bad=1; }; done
  grep -qF '"cloudflare_list.legal_redirects": "create"' "$GATE" || bad=1
  [[ "$bad" -eq 0 ]]
}
# R12 (D11): the import-block remedy names the spec-class flip; the half-applied dns_edit replace has
# a Halt row; a gptbot=>403 from Bot Fight Mode is the one allowed next-phase start, owner-authorized.
row_r12() {
  local j h bad=0
  j="$(joined <"$1")"; h="$(halt_text "$1" | joined)"
  grep -qF 'commit the printed import block first, and in the same reviewed PR flip that address'"'"'s spec class from `create` to `import`' <<<"$j" || { echo "    dispatch refusal lacks the class flip" >&2; bad=1; }
  grep -qF 'the import block and the class flip are part of the same go' <<<"$j" || { echo "    0c lacks the class flip" >&2; bad=1; }
  grep -qF -- '- **A `zone-rest` apply failed between the halves of the `doppler_secret.cf_api_token_dns_edit` replace**' <<<"$h" \
    && grep -qF '"doppler_secret.cf_api_token_dns_edit": "replace"' "$GATE" || { echo "    no half-replace row" >&2; bad=1; }
  grep -qF 'it is Bot Fight Mode, which only `zone-rest` turns off: this is the one next-phase start the Halt allows. `Operator-authorizes:`' <<<"$h" \
    && grep -qF 'bad+=" gptbot=>' "$JOB" || { echo "    no gptbot=>403 action" >&2; bad=1; }
  [[ "$bad" -eq 0 ]]
}
# R13 (D30b, D10, preserve-env): every /health curl prints the redirect target; the pre-forget revert
# keeps the new token in _NEXT before restoring _PREV and restores prd_terraform only; the flip prose
# names the --preserve-env precedence the job really uses.
row_r13() {
  local j r bad=0
  j="$(joined <"$1")"
  [[ "$(grep -cF 'https://app.soleur.ai/health' "$1")" -ge 2 ]] || bad=1
  ! grep -qF 'curl ' < <(grep -F 'https://app.soleur.ai/health' "$1" | grep -vF -- "-w '%{http_code} %{redirect_url}\\n'") || { echo "    a /health curl lacks %{redirect_url}" >&2; bad=1; }
  r="$(halt_bullet "$1" 'Before the forget is committed')"
  grep -qF 'The revert restores `prd_terraform` only' <<<"$r" || { echo "    revert scope unstated" >&2; bad=1; }
  before "$r" 'first copy `<KEY>` to `<KEY>_NEXT`' 'copy each token `<KEY>_PREV` back over `<KEY>`' || { echo "    _NEXT copy not before the _PREV restore" >&2; bad=1; }
  grep -qF 'reads its values through `doppler run --preserve-env`' <<<"$j" && grep -qF 'soleur-infra-privileged` wins over `prd_terraform`' <<<"$j" \
    && grep -qF 'doppler run --preserve-env' "$JOB" || { echo "    preserve-env precedence unstated" >&2; bad=1; }
  [[ "$bad" -eq 0 ]]
}

echo "== the tool side of R5 =="
grep -qxF 'echo "probe=$PROFILE verdict=pass"' "$SCOPE_TOOL"
check "cf-token-scope.sh prints the run line probe=<profile> verdict=pass" $?
grep -qF -- '--staged' "$SCOPE_TOOL" && grep -qF 'redirects-dns' "$SCOPE_TOOL" && grep -qF 'zone-rest' "$SCOPE_TOOL"
check "cf-token-scope.sh has --staged and the redirects-dns and zone-rest profiles" $?

echo "== the runbook =="
row_r1 "$RUNBOOK"; check "R1 no terraform state push line; a Halt section exists (D4)" $?
row_r2 "$RUNBOOK"; check "R2 git-log and drift-plan reads precede the manual-rerun dispatch (D5)" $?
row_r3 "$RUNBOOK"; check "R3 reopen step names the one cache_shared_binaries create (D3)" $?
row_r4 "$RUNBOOK"; check "R4 runbook and bootstrap.sh name the same stages (D11)" $?
row_r5 "$RUNBOOK"; check "R5 the expected probe verdict is the tool's; withdrawn wording gone" $?
row_r6 "$RUNBOOK"; check "R6 no self-approval line and the revoke read-back are present" $?
row_r7 "$RUNBOOK"; check "R7 the B line prints one absolute path, or verdict=stop for zero or two copies" $?
row_r8 "$RUNBOOK"; check "R8 the revert-copy check reads each key on its own NEW and OLD resource (D1)" $?
row_r9 "$RUNBOOK"; check "R9 every failure marker bootstrap.sh prints has a Halt action (D20)" $?
row_r10 "$RUNBOOK"; check "R10 forget-committed is cross-run; cancel arms ordered; Verify-first scoped (D7)" $?
row_r11 "$RUNBOOK"; check "R11 verify-failed step 4: one PASS line, must-NOT set, expected_in_state_updates (D8)" $?
row_r12 "$RUNBOOK"; check "R12 import-block class flip, half-replace row, gptbot=>403 action (D11)" $?
row_r13 "$RUNBOOK"; check "R13 /health prints redirect_url; revert keeps _NEXT; preserve-env (D30b, D10)" $?

echo "== mutations =="
mutate() { # <label> <dst> — perl program on stdin
  local label="$1" dst="$2" prog; prog="$(cat)"
  cp "$RUNBOOK" "$dst"; perl -0777 -pi -e "$prog" "$dst"
  if cmp -s "$dst" "$RUNBOOK"; then fail "mutation ${label} did not land"; return 1; fi
  pass "mutation ${label} landed"
}
expect_red() { # <label> <row> <file>
  if "$2" "$3" 2>/dev/null; then fail "$1 stayed GREEN"; else pass "$1 turns its row RED"; fi
}
if mutate M1 "$SB/m1.md" <<'PERL'; then
s{\z}{\nterraform state push -force backup.tfstate\n}
PERL
  expect_red "M1 (state push line added)" row_r1 "$SB/m1.md"
fi
if mutate M2 "$SB/m2.md" <<'PERL'; then
s{(   git[ ]fetch origin main\n)}{   gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun -f reason='#12931 reopen'\n$1}
PERL
  expect_red "M2 (manual-rerun moved above the reads)" row_r2 "$SB/m2.md"
fi
if mutate M3 "$SB/m3.md" <<'PERL'; then
s{(\*\*Reopen the routine path\*\*.*?)`cloudflare_ruleset\.cache_shared_binaries` create}{$1cache rule}s;
s{(\*\*Reopen the routine path\*\*.*?)`cloudflare_ruleset\.cache_shared_binaries` create}{$1cache rule}s
PERL
  expect_red "M3 (reopen cache_shared_binaries create dropped)" row_r3 "$SB/m3.md"
fi
if mutate M4 "$SB/m4.md" <<'PERL'; then
s{`branch-copies-tokens`}{`branch-copy-tokens`}g
PERL
  expect_red "M4 (a stage renamed in the runbook)" row_r4 "$SB/m4.md"
fi
if mutate M5 "$SB/m5.md" <<'PERL'; then
s{probe=<phase> verdict=pass}{probe=<phase> verdict=authorized}
PERL
  expect_red "M5 (verdict=authorized reintroduced)" row_r5 "$SB/m5.md"
fi
if mutate M6 "$SB/m6.md" <<'PERL'; then
s{\z}{\nbash "\$B" --stage bogus-stage\n}
PERL
  expect_red "M6 (the runbook issues an undeclared --stage)" row_r4 "$SB/m6.md"
fi
if mutate M7 "$SB/m7.md" <<'PERL'; then
s{\z}{\n9. `bogus-stage`: not a stage of the script\n}
PERL
  expect_red "M7 (a numbered stage item the script does not declare)" row_r4 "$SB/m7.md"
fi
if mutate M8 "$SB/m8.md" <<'PERL'; then
s{; false; fi`\.}{; fi`.}
PERL
  [[ -n "$(b_line "$SB/m8.md")" ]]; check "M8 mutant still yields a B line (so R7 reds on its run, not on extraction)" $?
  expect_red "M8 (the B line's stop no longer fails)" row_r7 "$SB/m8.md"
fi

# Halt state-machine mutants (review fr3).
if mutate M9 "$SB/m9.md" <<'PERL'; then
s{\| `CF_API_TOKEN_PAGES` \| `accounts/66d4f93f7397f196544e9fe84c3557c2/pages/projects` \|}{| `CF_API_TOKEN_PAGES` | `zones/951ce525552201ec6c696b24251abed7` |}
PERL
  expect_red "M9 (the Pages key read on the zone again)" row_r8 "$SB/m9.md"
fi
if mutate M10 "$SB/m10.md" <<'PERL'; then
s{If both keys read as NEW, or\n?\s*neither does}{If both keys read as NEW}
PERL
  expect_red "M10 (the neither-reads-NEW stop dropped)" row_r8 "$SB/m10.md"
fi
if mutate M11 "$SB/m11.md" <<'PERL'; then
s{`SOLEUR_CFAM_ID_READBACK_FAILED target}{`SOLEUR_CFAM_ID_READBACK target}
PERL
  expect_red "M11 (a bootstrap failure marker loses its Halt action)" row_r9 "$SB/m11.md"
fi
# M12 mutates the BOOTSTRAP, not the runbook: a new failure marker must red R9 on the pristine runbook.
cp "$BOOTSTRAP" "$SB/m12.sh"
printf '%s\n' "  [[ -n \"\$x\" ]] || { printf 'SOLEUR_CFAM_BOGUS_REFUSED name=%s\\n' \"\$k\"; return 1; }" >> "$SB/m12.sh"
if ! cmp -s "$SB/m12.sh" "$BOOTSTRAP" && [[ "$(failure_markers "$SB/m12.sh" | grep -c BOGUS_REFUSED)" -eq 1 ]]; then
  pass "mutation M12 landed (bootstrap gains a failure marker)"
  row_r9_with() { row_r9 "$RUNBOOK" "$1"; }
  expect_red "M12 (a new bootstrap failure marker with no Halt action)" row_r9_with "$SB/m12.sh"
else fail "mutation M12 did not land"; fi
if mutate M13 "$SB/m13.md" <<'PERL'; then
s{(  1\. `mode=apply applying=true` is present[^\n]*\n)(  2\. No `mode=apply applying=true`[^\n]*\n[^\n]*\n)}{$2$1}
PERL
  expect_red "M13 (the cancelled-run applying=true arm no longer first)" row_r10 "$SB/m13.md"
fi
if mutate M14 "$SB/m14.md" <<'PERL'; then
s{\z}{\nnone of `backup=uploaded` means nothing was forgotten\n}
PERL
  expect_red "M14 (the per-run forget arm reintroduced)" row_r10 "$SB/m14.md"
fi
if mutate M15 "$SB/m15.md" <<'PERL'; then
s{(\*\*A stop after `applying=true`\*\* \()}{$1`gate-refused`, }
PERL
  expect_red "M15 (Verify-first widened to a stop before applying=true)" row_r10 "$SB/m15.md"
fi
if mutate M16 "$SB/m16.md" <<'PERL'; then
s{Trust an absence only when the output holds exactly one}{Trust an absence when the output holds one}
PERL
  expect_red "M16 (step 4 reads an absence with no PASS-line control)" row_r11 "$SB/m16.md"
fi
if mutate M17 "$SB/m17.md" <<'PERL'; then
s{and `-f expected_in_state_updates='<address> …'`}{and the same inputs}
PERL
  expect_red "M17 (the re-dispatch drops expected_in_state_updates)" row_r11 "$SB/m17.md"
fi
if mutate M18 "$SB/m18.md" <<'PERL'; then
s{flip that address's spec class from `create` to `import`}{update it}
PERL
  expect_red "M18 (the import-block remedy loses the class flip)" row_r12 "$SB/m18.md"
fi
if mutate M19 "$SB/m19.md" <<'PERL'; then
s{this is the one next-phase start\n?\s*the Halt allows}{run zone-rest}
PERL
  expect_red "M19 (the gptbot=>403 next-phase start unauthorized)" row_r12 "$SB/m19.md"
fi
if mutate M20 "$SB/m20.md" <<'PERL'; then
s{-w '%\{http_code\} %\{redirect_url\}\\n' https://app\.soleur\.ai/health}{-w '%{http_code}\\n' https://app.soleur.ai/health}
PERL
  expect_red "M20 (a /health curl drops redirect_url)" row_r13 "$SB/m20.md"
fi
if mutate M21 "$SB/m21.md" <<'PERL'; then
s{  1\. for each token key whose swap ran[^\n]*\n(?:     [^\n]*\n)*}{}
PERL
  expect_red "M21 (the revert no longer keeps the new token in _NEXT)" row_r13 "$SB/m21.md"
fi

TOTAL=$((PASS + FAIL)); FLOOR=58
if [[ "$TOTAL" -lt "$FLOOR" ]]; then
  printf '  [FAIL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$TOTAL" "$FLOOR" >&2
  echo "Total: ${TOTAL} assertions, $((FAIL + 1)) failed"; exit 1
fi
echo "Total: ${TOTAL} assertions, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
