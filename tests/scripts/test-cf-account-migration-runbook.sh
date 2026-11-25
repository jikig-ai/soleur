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
#   M22-M60 one per guard of the executable blocks and the text contract -> R14..R18;
#   T1-T12 remove each R18 sentence in turn -> R18.
#
# EXECUTABLE BLOCKS (review fix round 2). R14..R17 extract the first-PATCH read, the restore block, the
# recreate block and the DNS snapshot functions verbatim from the runbook and run them with stub
# `doppler`, `curl` and `gh` first on PATH. No row reaches a network, Doppler or GitHub. Only the
# restore and recreate blocks' first line (their placeholders) is replaced, after it is checked.
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

# --- the runbook's executable blocks, run verbatim against stubs (review fix round 2) --------------
STUBS="$SB/stubs"; CASE="$SB/case"; mkdir -p "$STUBS"
readonly STUB_TOKEN='stub-bearer-value.not-a-real-token'
cat >"$STUBS/doppler" <<'STUB'
#!/usr/bin/env bash
# `doppler run ... -- <cmd>`: runs <cmd> with the synthetic token.
while [[ $# -gt 0 && "$1" != -- ]]; do shift; done; shift
export CF_API_TOKEN="$CFAM_STUB_TOKEN"
exec "$@"
STUB
cat >"$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
# Answers from $CFAM_STUB_DIR/<METHOD>.<n>[.code]; logs argv, the stdin config and each request.
d="$CFAM_STUB_DIR"; printf '%s\n' "$*" >>"$d/argv"
m=GET; u=""; o=""; w=""; data=""; cfg=0
while (($#)); do
  case "$1" in
    -X) m="$2"; shift 2 ;;
    -o) o="$2"; shift 2 ;;
    -w) w="$2"; shift 2 ;;
    --data-binary) data="$2"; shift 2 ;;
    --config) [[ "$2" == - ]] && cfg=1; shift 2 ;;
    -H|--max-time|--noproxy) shift 2 ;;
    https://*) u="$1"; shift ;;
    *) shift ;;
  esac
done
if [[ "$u" == https://cloudflare-dns.com/* ]]; then
  if [[ -e "$d/doh.fail" && "$u" == *"name=$(<"$d/doh.fail")&"* ]]; then exit 22; fi
  printf '{"Status":0,"Answer":[]}'; exit 0
fi
[[ "$cfg" -eq 0 ]] || cat >>"$d/stdin"
n=1; [[ ! -e "$d/$m.log" ]] || n=$(($(wc -l <"$d/$m.log") + 1))
printf '%s\t%s\n' "$u" "$data" >>"$d/$m.log"
code=000; [[ ! -e "$d/$m.$n.code" ]] || code="$(<"$d/$m.$n.code")"
if [[ "$o" != /dev/null && -e "$d/$m.$n" ]]; then cat "$d/$m.$n"; fi
w="${w//\\n/$'\n'}"; printf '%s' "${w//%\{http_code\}/$code}"
STUB
cat >"$STUBS/gh" <<'STUB'
#!/usr/bin/env bash
# The comments list prints each page before fetching the next, as the real --paginate --jq does.
d="$CFAM_STUB_DIR"
if [[ "$1 $2" == "issue comment" ]]; then cat >>"$d/gh.posted"; exit 0; fi
[[ "$1" == api ]] || exit 64
path="$2"; shift 2; filter=""
while (($#)); do if [[ "$1" == --jq ]]; then filter="$2"; shift 2; else shift; fi; done
case "$path" in
  */issues/12931/comments)
    for p in 1 2; do
      if [[ -e "$d/page.fail" && "$(<"$d/page.fail")" == "$p" ]]; then echo 'gh: Bad Gateway (HTTP 502)' >&2; exit 1; fi
      [[ ! -e "$d/page.$p" ]] || jq -rs "$filter" "$d/page.$p" || exit 1
    done ;;
  */collaborators/*/permission)
    login="${path##*collaborators/}"; login="${login%/permission}"
    v="$(cat "$d/perm.$login" 2>/dev/null)"
    case "$v" in
      404) echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
      5*) echo "gh: upstream failure (HTTP $v)" >&2; exit 1 ;;
      *) printf '%s\n' "$v" ;;
    esac ;;
  *) exit 64 ;;
esac
STUB
chmod +x "$STUBS/doppler" "$STUBS/curl" "$STUBS/gh"

fresh() { rm -rf "$CASE"; mkdir -p "$CASE"; }
# run_case [<cwd>]: runs $CASE/run.sh under the stubs; stdout only.
run_case() {
  ( cd "${1:-$REPO_ROOT}" && PATH="$STUBS:$PATH" CFAM_STUB_DIR="$CASE" CFAM_STUB_TOKEN="${CASE_TOKEN:-$STUB_TOKEN}" bash "$CASE/run.sh" 2>/dev/null )
}
count() { if [[ -e "$1" ]]; then wc -l <"$1" | tr -d ' '; else echo 0; fi; }
say() { printf '%s' "$3" >"$CASE/$1"; printf '%s' "$2" >"$CASE/$1.code"; } # <METHOD.n> <http> <body>
# fence_after <runbook> <anchor>: the first ```bash block after the anchor line, with its indent removed.
fence_after() {
  awk -v a="$2" '
    !seen { if (index($0, a)) seen = 1; next }
    !inb { if ($0 ~ /^ *```bash$/) { match($0, /^ */); ind = RLENGTH; inb = 1 } next }
    /^ *```$/ { exit }
    { print substr($0, ind + 1) }' "$1"
}
pin_of() { bash -c 'source "$1" && cf_account_migrate_record_pins redirects-dns' _ "$GATE" | awk -F'\t' -v a="$1" '$1 == a {print $2}'; }
token_clean() { # the bearer reached curl on stdin and never in argv
  grep -qF -- "$STUB_TOKEN" "$CASE/stdin" 2>/dev/null && ! grep -qF -- "$STUB_TOKEN" "$CASE/argv" 2>/dev/null
}

# R14: the first-PATCH read holds on any read failure other than a 404. Every scenario is one that
# the security review ran; the two read-failure inputs are its Input 1 and Input 2.
fp_comment() { # <page> <login> <created> <updated> <first line>
  jq -cn --arg l "$2" --arg c "$3" --arg u "$4" --arg b "$5" \
    '{user: {login: $l}, created_at: $c, updated_at: $u, body: ($b + "\nnote")}' >>"$CASE/page.$1"
}
fp_expect() { # <runbook> <label> <expected stdout>
  local got
  fence_after "$1" '`Agent:` read the decision:' >"$CASE/run.sh"
  [[ -s "$CASE/run.sh" ]] || { echo "    no first-PATCH block" >&2; return 1; }
  got="$(run_case)"
  [[ "$got" == "$3" ]] || { echo "    first-PATCH $2: want [$3] got [$got]" >&2; return 1; }
}
row_r14() {
  local A='CF-MIGRATE-FIRST-PATCH: accept-unobserved' O='CF-MIGRATE-FIRST-PATCH: observe-first' t1=2026-11-24T10:00:00Z t2=2026-11-24T11:00:00Z t3=2026-11-24T11:30:00Z
  fresh; fp_comment 1 owner "$t1" "$t1" "$A"; fp_comment 1 owner "$t2" "$t2" "$O"; echo admin >"$CASE/perm.owner"
  fp_expect "$1" 'newest admin decision wins' observe-first || return 1
  fresh; fp_comment 1 owner "$t1" "$t1" "$A"; echo admin >"$CASE/perm.owner"
  fp_expect "$1" 'accept alone passes' accept-unobserved || return 1
  fresh; fp_comment 1 owner "$t1" "$t1" "$A"; fp_comment 1 flaky "$t2" "$t2" "$O"; echo admin >"$CASE/perm.owner"; echo 502 >"$CASE/perm.flaky"
  fp_expect "$1" 'security input 1: the newer permission read answers 502' unreadable || return 1
  fresh; fp_comment 1 owner "$t1" "$t1" "$A"; fp_comment 2 owner "$t2" "$t2" "$O"; echo admin >"$CASE/perm.owner"; echo 2 >"$CASE/page.fail"
  fp_expect "$1" 'security input 2: comments page 2 fails after page 1' unreadable || return 1
  fresh; fp_comment 1 owner "$t1" "$t1" "$A"; echo 1 >"$CASE/page.fail"
  fp_expect "$1" 'comments page 1 fails' unreadable || return 1
  fresh; fp_comment 1 owner "$t1" "$t1" "$A"; fp_comment 1 stranger "$t2" "$t2" "$O"; echo admin >"$CASE/perm.owner"; echo read >"$CASE/perm.stranger"
  fp_expect "$1" 'a non-admin cannot block the decision' accept-unobserved || return 1
  fresh; fp_comment 1 owner "$t1" "$t1" "$O"; fp_comment 1 stranger "$t2" "$t2" "$A"; echo admin >"$CASE/perm.owner"; echo read >"$CASE/perm.stranger"
  fp_expect "$1" 'a non-admin cannot set the decision' observe-first || return 1
  fresh; fp_comment 1 owner "$t1" "$t1" "$A"; fp_comment 1 gone "$t2" "$t2" "$O"; echo admin >"$CASE/perm.owner"; echo 404 >"$CASE/perm.gone"
  fp_expect "$1" 'a deleted account (404) is not a read failure' accept-unobserved || return 1
  fresh; fp_comment 1 owner "$t1" "$t2" "$A"; echo admin >"$CASE/perm.owner"
  fp_expect "$1" 'an edited comment holds' edited || return 1
  fresh; fp_comment 1 owner "$t1" "$t1" 'CF-MIGRATE-FIRST-PATCH: accept-unobserved extra'; echo admin >"$CASE/perm.owner"
  fp_expect "$1" 'no exact token is empty' '' || return 1
  fresh; fp_comment 1 flaky "$t1" "$t1" "$O"; fp_comment 1 owner "$t2" "$t2" "$O"; fp_comment 1 owner "$t3" "$t3" "$A"; echo admin >"$CASE/perm.owner"; echo 503 >"$CASE/perm.flaky"
  fp_expect "$1" 'a failure below the newest admin comment is never reached' accept-unobserved
}

# R15: the restore block. One PATCH of the pinned record, built from a first GET, then a separate GET
# on all eight compared fields. Bad input and a read that is not the pin write nothing.
rec_json() { # <id> <content> [<ttl>] [<tags json>] [<comment json>]
  jq -cn --arg id "$1" --arg z "$NZ" --arg c "$2" --argjson ttl "${3:-1}" --argjson tags "${4:-[]}" --argjson cm "${5:-null}" \
    '{success: true, result: {id: $id, zone_id: $z, type: "TXT", name: "_dmarc.soleur.ai", content: $c, ttl: $ttl,
      proxied: false, priority: null, comment: $cm, tags: $tags}}'
}
restore_prep() { # <runbook> <addr> <field> <value>
  local b; b="$(fence_after "$1" '`Operator-authorizes:` one edit of the named field')"
  [[ "${b%%$'\n'*}" == "ADDR='<addr>'; FIELD='<field>'; VALUE='<json value>'" ]] || { echo "    restore block's first line changed" >&2; return 1; }
  { printf 'ADDR=%q; FIELD=%q; VALUE=%q\n' "$2" "$3" "$4"; printf '%s\n' "${b#*$'\n'}"; } >"$CASE/run.sh"
}
want() { # <label> <expected stdout> <got>
  [[ "$3" == "$2" ]] || { echo "    $1: want [${2//$'\n'/ }] got [${3//$'\n'/ }]" >&2; return 1; }
}
row_r15() {
  local a=cloudflare_record.dmarc id got v
  id="$(pin_of "$a")"; [[ "$id" =~ ^[0-9a-f]{32}$ ]] || { echo "    no pin for $a" >&2; return 1; }
  fresh; restore_prep "$1" "$a" content '"right"' || return 1
  say GET.1 200 "$(rec_json "$id" wrong)"; say PATCH.1 200 '{"success":true}'; say GET.2 200 "$(rec_json "$id" right)"
  got="$(run_case)"; want 'a good edit' $'patch_http=200\nreadback=ok' "$got" || return 1
  [[ "$(count "$CASE/PATCH.log")" -eq 1 ]] || { echo "    not exactly one PATCH" >&2; return 1; }
  [[ "$(cut -f1 "$CASE/PATCH.log")" == "https://api.cloudflare.com/client/v4/zones/$NZ/dns_records/$id" ]] || { echo "    PATCH url" >&2; return 1; }
  v="$(cut -f2 "$CASE/PATCH.log")"
  [[ "$(jq -cS . <<<"$v")" == '{"content":"right","name":"_dmarc.soleur.ai","ttl":1,"type":"TXT"}' ]] || { echo "    PATCH body: $v" >&2; return 1; }
  token_clean || { echo "    the bearer is in argv or missed stdin" >&2; return 1; }
  fresh; restore_prep "$1" "$a" content '"right"' || return 1
  say GET.1 200 "$(rec_json "$id" wrong)"; say PATCH.1 403 '{}'; say GET.2 200 "$(rec_json "$id" wrong)"
  got="$(run_case)"; want 'a 403' $'patch_http=403\nreadback=differs' "$got" || return 1
  fresh; restore_prep "$1" "$a" content '"right"' || return 1
  say GET.1 200 "$(rec_json "$id" wrong)"; say PATCH.1 200 '{}'; say GET.2 200 "$(rec_json "$id" other)"
  got="$(run_case)"; want 'the named field did not land' $'patch_http=200\nreadback=differs' "$got" || return 1
  fresh; restore_prep "$1" "$a" content '"right"' || return 1
  say GET.1 200 "$(rec_json "$id" wrong)"; say PATCH.1 200 '{}'; say GET.2 200 "$(rec_json "$id" right 300)"
  got="$(run_case)"; want 'a neighbouring field moved' $'patch_http=200\nreadback=differs' "$got" || return 1
  fresh; restore_prep "$1" "$a" content '"right"' || return 1
  say GET.1 200 "$(rec_json "$id" wrong)"; say PATCH.1 200 '{}'; say GET.2 200 "$(jq -c '.result.id = "ffffffffffffffffffffffffffffffff"' <<<"$(rec_json "$id" right)")"
  got="$(run_case)"; want 'the read-back is another record' $'patch_http=200\nreadback=differs' "$got" || return 1
  fresh; restore_prep "$1" "$a" tags '["a","b"]' || return 1
  say GET.1 200 "$(rec_json "$id" same 1 '["x"]')"; say PATCH.1 200 '{}'; say GET.2 200 "$(rec_json "$id" same 1 '["b","a"]')"
  got="$(run_case)"; want 'tags compare sorted' $'patch_http=200\nreadback=ok' "$got" || return 1
  fresh; restore_prep "$1" "$a" content '"right"' || return 1
  say GET.1 200 "$(rec_json "$id" wrong 1 '["b","a"]')"; say PATCH.1 200 '{}'; say GET.2 200 "$(rec_json "$id" right 1 '["a","b"]')"
  got="$(run_case)"; want 'a neighbouring array compares sorted' $'patch_http=200\nreadback=ok' "$got" || return 1
  fresh; restore_prep "$1" "$a" comment 'null' || return 1
  say GET.1 200 "$(rec_json "$id" same 1 '[]' '"stray"')"; say PATCH.1 200 '{}'; say GET.2 200 "$(rec_json "$id" same 1 '[]' '""')"
  got="$(run_case)"; want 'an empty comment equals null' $'patch_http=200\nreadback=ok' "$got" || return 1
  fresh; restore_prep "$1" "$a" content '"right"' || return 1
  say GET.1 200 "$(rec_json ffffffffffffffffffffffffffffffff wrong)"
  got="$(run_case)"; want 'the first GET is another record' $'pin_http=200\ninput-refused' "$got" || return 1
  [[ "$(count "$CASE/PATCH.log")" -eq 0 ]] || { echo "    wrote after a wrong first GET" >&2; return 1; }
  fresh; restore_prep "$1" "$a" content '"right"' || return 1
  say GET.1 404 '{"success":false,"result":null}'
  got="$(run_case)"; want 'the first GET is a 404' $'pin_http=404\ninput-refused' "$got" || return 1
  [[ "$(count "$CASE/PATCH.log")" -eq 0 ]] || { echo "    wrote after a 404" >&2; return 1; }
  fresh; restore_prep "$1" "$a" content '"right"' || return 1
  say GET.1 500 "$(rec_json "$id" wrong)"
  got="$(run_case)"; want 'the first GET is a 500 holding the pin' $'pin_http=500\ninput-refused' "$got" || return 1
  [[ "$(count "$CASE/PATCH.log")" -eq 0 ]] || { echo "    wrote after a 500" >&2; return 1; }
  local bad
  for bad in "$a|data|\"x\"" "$a|content,ttl|\"x\"" "cloudflare_record.nope|content|\"x\"" "$a|content|{" "$a|content|1 2" "$a|content|"; do
    fresh; restore_prep "$1" "${bad%%|*}" "$(cut -d'|' -f2 <<<"$bad")" "${bad##*|}" || return 1
    got="$(run_case)"; want "bad input [$bad]" input-refused "$got" || return 1
    [[ ! -e "$CASE/argv" ]] || { echo "    curl ran on bad input [$bad]" >&2; return 1; }
  done
  fresh; restore_prep "$1" "$a" content '"right"' || return 1
  got="$(CASE_TOKEN=$'x"\nheader = "evil' run_case)"; want 'a bad token shape' token-shape-refused "$got" || return 1
  [[ ! -e "$CASE/argv" ]] || { echo "    curl ran on a bad token" >&2; return 1; }
}

# R16: the recreate block. Fields come from the record's dns.tf block, the pinned id must answer 404,
# one POST to the new zone, and the returned id is read back on every field.
NEW_REC_ID=abcdef0123456789abcdef0123456789
recreate_prep() { # <runbook> <addr> [<pages subdomain>]
  local b; b="$(fence_after "$1" '`<addr>:notfound`: a re-dispatch cannot repair')"
  [[ "${b%%$'\n'*}" == "ADDR='<addr>'; PAGES_SUBDOMAIN=''" ]] || { echo "    recreate block's first line changed" >&2; return 1; }
  { printf 'ADDR=%q; PAGES_SUBDOMAIN=%q\n' "$2" "${3:-}"; printf '%s\n' "${b#*$'\n'}"; } >"$CASE/run.sh"
}
# created_json <POST body>: the record the API would hold after that POST.
created_json() { jq -c --arg id "$NEW_REC_ID" --arg z "$NZ" '{success: true, result: (. + {id: $id, zone_id: $z, comment: null})}' <<<"$1"; }
row_r16() {
  local a=cloudflare_record.mx_send id got body want_body
  id="$(pin_of "$a")"; [[ "$id" =~ ^[0-9a-f]{32}$ ]] || { echo "    no pin for $a" >&2; return 1; }
  want_body='{"content":"feedback-smtp.eu-west-1.amazonses.com","name":"send.soleur.ai","priority":10,"proxied":false,"tags":[],"ttl":1,"type":"MX"}'
  fresh; recreate_prep "$1" "$a" || return 1
  say GET.1 404 '{"success":false}'; say POST.1 200 "$(created_json "$want_body")"; say GET.2 200 "$(created_json "$want_body")"
  got="$(run_case)"; want 'a good recreate' $'post_http=200\nnew_id=abcdef01\nreadback=ok' "$got" || return 1
  [[ "$(count "$CASE/POST.log")" -eq 1 ]] || { echo "    not exactly one POST" >&2; return 1; }
  [[ "$(cut -f1 "$CASE/POST.log")" == "https://api.cloudflare.com/client/v4/zones/$NZ/dns_records" ]] || { echo "    POST url" >&2; return 1; }
  body="$(cut -f2 "$CASE/POST.log")"
  [[ "$(jq -cS . <<<"$body")" == "$want_body" ]] || { echo "    POST body: $body" >&2; return 1; }
  [[ "$(sed -n 2p "$CASE/GET.log" | cut -f1)" == "https://api.cloudflare.com/client/v4/zones/$NZ/dns_records/$NEW_REC_ID" ]] || { echo "    the read-back is not the returned id" >&2; return 1; }
  token_clean || { echo "    the bearer is in argv or missed stdin" >&2; return 1; }
  # A TXT block: no priority key, no proxied key in dns.tf, and a value with ; : @ = and a comma.
  local dm='{"content":"v=DMARC1; p=reject; rua=mailto:dmarc-reports@soleur.ai,mailto:re+yyggnc2ymkj@dmarc.postmarkapp.com; pct=100","name":"_dmarc.soleur.ai","proxied":false,"tags":[],"ttl":1,"type":"TXT"}'
  fresh; recreate_prep "$1" cloudflare_record.dmarc || return 1
  say GET.1 404 '{}'; say POST.1 200 "$(created_json "$dm")"; say GET.2 200 "$(created_json "$dm")"
  got="$(run_case)"; want 'a TXT recreate' $'post_http=200\nnew_id=abcdef01\nreadback=ok' "$got" || return 1
  [[ "$(cut -f2 "$CASE/POST.log" | jq -cS .)" == "$dm" ]] || { echo "    TXT POST body" >&2; return 1; }
  # The apex: a trailing HCL comment on `name`, the Pages reference and an explicit proxied.
  local ap='{"content":"soleur-docs-40x.pages.dev","name":"soleur.ai","proxied":true,"tags":[],"ttl":1,"type":"CNAME"}'
  fresh; recreate_prep "$1" cloudflare_record.pages_apex soleur-docs-40x.pages.dev || return 1
  say GET.1 404 '{}'; say POST.1 200 "$(created_json "$ap")"; say GET.2 200 "$(created_json "$ap")"
  got="$(run_case)"; want 'the Pages apex recreate' $'post_http=200\nnew_id=abcdef01\nreadback=ok' "$got" || return 1
  [[ "$(cut -f2 "$CASE/POST.log" | jq -cS .)" == "$ap" ]] || { echo "    apex POST body" >&2; return 1; }
  local p
  for p in '' evil.pages.dev; do
    fresh; recreate_prep "$1" cloudflare_record.www "$p" || return 1
    got="$(run_case)"; want "www with subdomain [$p]" input-refused "$got" || return 1
    [[ ! -e "$CASE/argv" ]] || { echo "    curl ran with subdomain [$p]" >&2; return 1; }
  done
  for p in 200 500 000; do
    fresh; recreate_prep "$1" "$a" || return 1
    say GET.1 "$p" "$(rec_json "$id" live)"
    got="$(run_case)"; want "the pinned id answers $p" "pin_http=$p"$'\ninput-refused' "$got" || return 1
    [[ "$(count "$CASE/POST.log")" -eq 0 ]] || { echo "    POST after a $p pin" >&2; return 1; }
  done
  for p in cloudflare_record.nope cloudflare_record.deploy cloudflare_record.app 'cloudflare_record.mx_send"'; do
    fresh; recreate_prep "$1" "$p" || return 1
    got="$(run_case)"; want "unknown address [$p]" input-refused "$got" || return 1
    [[ ! -e "$CASE/argv" ]] || { echo "    curl ran for [$p]" >&2; return 1; }
  done
  fresh; recreate_prep "$1" "$a" || return 1
  say GET.1 404 '{}'; say POST.1 400 '{"success":false,"errors":[{"code":81058}]}'
  got="$(run_case)"; want 'a refused POST' $'post_http=400\nnew_id=none\nreadback=differs' "$got" || return 1
  [[ "$(count "$CASE/GET.log")" -eq 1 ]] || { echo "    a read-back ran with no id" >&2; return 1; }
  local k drift
  for k in type name content ttl proxied priority comment tags; do
    case "$k" in
      ttl|priority) drift='.result[$k] = 300' ;;
      proxied) drift='.result[$k] = true' ;;
      tags) drift='.result[$k] = ["x"]' ;;
      *) drift='.result[$k] = "drifted"' ;;
    esac
    fresh; recreate_prep "$1" "$a" || return 1
    say GET.1 404 '{}'; say POST.1 200 "$(created_json "$want_body")"
    say GET.2 200 "$(jq -c --arg k "$k" "$drift" <<<"$(created_json "$want_body")")"
    got="$(run_case)"; want "the read-back differs on $k" $'post_http=200\nnew_id=abcdef01\nreadback=differs' "$got" || return 1
  done
  fresh; recreate_prep "$1" "$a" || return 1
  say GET.1 404 '{}'; say POST.1 200 "$(created_json "$want_body")"
  say GET.2 200 "$(jq -c '.result.id = "ffffffffffffffffffffffffffffffff"' <<<"$(created_json "$want_body")")"
  got="$(run_case)"; want 'the read-back is another record' $'post_http=200\nnew_id=abcdef01\nreadback=differs' "$got" || return 1
  fresh; recreate_prep "$1" "$a" || return 1
  got="$(CASE_TOKEN=$'x"\nheader = "evil' run_case)"; want 'a bad token shape' token-shape-refused "$got" || return 1
  [[ ! -e "$CASE/argv" ]] || { echo "    curl ran on a bad token" >&2; return 1; }
  # A dns.tf whose value is interpolated or a reference is refused. A private tree holds the edited
  # copy; the gate library and the imports file are the real ones, through symlinks.
  local tree="$SB/tree" expr
  for expr in 's|"feedback-smtp.eu-west-1.amazonses.com"|"${var.x}.example"|' 's|"feedback-smtp.eu-west-1.amazonses.com"|var.mail_host|'; do
    rm -rf "$tree"; mkdir -p "$tree/apps/web-platform/infra"
    ln -s "$REPO_ROOT/tests" "$tree/tests"
    ln -s "$REPO_ROOT/apps/web-platform/infra/cf-account-migration-imports.tf" "$tree/apps/web-platform/infra/cf-account-migration-imports.tf"
    sed "/^resource \"cloudflare_record\" \"mx_send\" {/,/^}/ $expr" "$REPO_ROOT/apps/web-platform/infra/dns.tf" >"$tree/apps/web-platform/infra/dns.tf"
    cmp -s "$tree/apps/web-platform/infra/dns.tf" "$REPO_ROOT/apps/web-platform/infra/dns.tf" && { echo "    HARNESS: the dns.tf edit did not land" >&2; return 1; }
    fresh; recreate_prep "$1" "$a" || return 1
    got="$(run_case "$tree")"; want "a non-literal dns.tf value [$expr]" input-refused "$got" || return 1
    [[ ! -e "$CASE/argv" ]] || { echo "    curl ran on a non-literal value" >&2; return 1; }
  done
  # A fully literal block with no pin: only the pin check can refuse it.
  rm -rf "$tree"; mkdir -p "$tree/apps/web-platform/infra"
  ln -s "$REPO_ROOT/tests" "$tree/tests"
  ln -s "$REPO_ROOT/apps/web-platform/infra/cf-account-migration-imports.tf" "$tree/apps/web-platform/infra/cf-account-migration-imports.tf"
  { cat "$REPO_ROOT/apps/web-platform/infra/dns.tf"
    printf 'resource "cloudflare_record" "unpinned" {\n  zone_id = var.cf_zone_id\n  name    = "unpinned"\n  content = "literal.example"\n  type    = "CNAME"\n  ttl     = 1\n}\n'
  } >"$tree/apps/web-platform/infra/dns.tf"
  fresh; recreate_prep "$1" cloudflare_record.unpinned || return 1
  got="$(run_case "$tree")"; want 'a literal block with no pin' input-refused "$got" || return 1
  [[ ! -e "$CASE/argv" ]] || { echo "    curl ran for a record with no pin" >&2; return 1; }
}

# R17: the DNS snapshot, its completeness check and the once-only baseline.
dns_prep() { # <runbook> <call...>: the functions block, then one call
  local rb="$1"; shift
  { fence_after "$rb" '`Agent:` compare public DNS answers'; printf '%s\n' "$*"; } >"$CASE/run.sh"
}
base_comment() { # <page> <login> <created> <updated> <rows>
  jq -cn --arg l "$2" --arg c "$3" --arg u "$4" --arg r "$5" \
    '{user: {login: $l}, created_at: $c, updated_at: $u, body: ("CF-MIGRATE-DNS-BASELINE\n" + $r)}' >>"$CASE/page.$1"
}
row_r17() {
  local got rows t1=2026-11-24T10:00:00Z t2=2026-11-24T11:00:00Z
  fresh; dns_prep "$1" "cfam_dns_snapshot >'$SB/snap'; cfam_dns_complete '$SB/snap'"
  got="$(run_case)"; want 'a full snapshot from the root' snapshot=complete "$got" || return 1
  [[ "$(grep -c . "$SB/snap")" -eq 19 ]] || { echo "    snapshot is not 19 rows" >&2; return 1; }
  rows="$(<"$SB/snap")"
  fresh; dns_prep "$1" "cfam_dns_snapshot >'$SB/snap0'; cfam_dns_complete '$SB/snap0'"
  got="$(run_case "$SB")"; want 'a run outside the repository root (0 rows)' snapshot=incomplete "$got" || return 1
  [[ ! -s "$SB/snap0" ]] || { echo "    the wrong-directory run produced rows" >&2; return 1; }
  fresh; echo api.soleur.ai >"$CASE/doh.fail"; dns_prep "$1" "cfam_dns_snapshot >'$SB/snap1'; cfam_dns_complete '$SB/snap1'"
  got="$(run_case)"; want 'one NO-VERDICT row' snapshot=incomplete "$got" || return 1
  [[ "$(grep -c . "$SB/snap1")" -eq 19 ]] || { echo "    the NO-VERDICT case is not 19 rows" >&2; return 1; }
  head -18 "$SB/snap" >"$SB/snap18"
  fresh; dns_prep "$1" "cfam_dns_complete '$SB/snap18'"
  got="$(run_case)"; want '18 rows' snapshot=incomplete "$got" || return 1
  { cat "$SB/snap"; echo extra.soleur.ai TXT x; } >"$SB/snap20"
  fresh; dns_prep "$1" "cfam_dns_complete '$SB/snap20'"
  got="$(run_case)"; want '20 rows' snapshot=incomplete "$got" || return 1
  # The baseline: saved once, read back, never replaced, and only from an admin's unedited comment.
  fresh; dns_prep "$1" "cfam_dns_save '$SB/snap'"
  got="$(run_case)"; want 'the first save' baseline=saved "$got" || return 1
  [[ "$(head -1 "$CASE/gh.posted")" == CF-MIGRATE-DNS-BASELINE && "$(tail -n +2 "$CASE/gh.posted")" == "$rows" ]] || { echo "    the posted baseline is wrong" >&2; return 1; }
  fresh; base_comment 1 owner "$t1" "$t1" "$rows"; echo admin >"$CASE/perm.owner"; dns_prep "$1" "cfam_dns_save '$SB/snap1'"
  got="$(run_case)"; want 'a second save' baseline=exists "$got" || return 1
  [[ ! -e "$CASE/gh.posted" ]] || { echo "    a saved baseline was overwritten" >&2; return 1; }
  fresh; base_comment 1 owner "$t1" "$t1" 'api.soleur.ai CNAME x'; echo admin >"$CASE/perm.owner"; dns_prep "$1" "cfam_dns_save '$SB/snap'"
  got="$(run_case)"; want 'an existing baseline with too few rows' baseline=incomplete "$got" || return 1
  [[ ! -e "$CASE/gh.posted" ]] || { echo "    posted over a short baseline" >&2; return 1; }
  fresh; base_comment 1 owner "$t1" "$t1" "$(cat "$SB/snap1")"; echo admin >"$CASE/perm.owner"; dns_prep "$1" "cfam_dns_save '$SB/snap'"
  got="$(run_case)"; want 'an existing baseline holding a NO-VERDICT' baseline=incomplete "$got" || return 1
  [[ ! -e "$CASE/gh.posted" ]] || { echo "    posted over a NO-VERDICT baseline" >&2; return 1; }
  fresh; dns_prep "$1" "cfam_dns_save '$SB/snap1'"
  got="$(run_case)"; want 'saving an incomplete snapshot' snapshot=incomplete "$got" || return 1
  [[ ! -e "$CASE/gh.posted" ]] || { echo "    an incomplete snapshot was posted" >&2; return 1; }
  fresh; base_comment 1 owner "$t1" "$t2" "$rows"; echo admin >"$CASE/perm.owner"; dns_prep "$1" "cfam_dns_save '$SB/snap'"
  got="$(run_case)"; want 'saving over an edited baseline' baseline=edited "$got" || return 1
  [[ ! -e "$CASE/gh.posted" ]] || { echo "    posted over an edited baseline" >&2; return 1; }
  fresh; echo 1 >"$CASE/page.fail"; dns_prep "$1" "cfam_dns_save '$SB/snap'"
  got="$(run_case)"; want 'saving when the list is unreadable' baseline=unreadable "$got" || return 1
  [[ ! -e "$CASE/gh.posted" ]] || { echo "    posted with an unreadable list" >&2; return 1; }
  fresh; base_comment 1 owner "$t1" "$t1" "$rows"; base_comment 1 owner "$t2" "$t2" 'later.soleur.ai TXT forged'; echo admin >"$CASE/perm.owner"; dns_prep "$1" cfam_dns_baseline
  got="$(run_case)"; want 'the oldest admin baseline wins' "$rows" "$got" || return 1
  fresh; base_comment 1 stranger "$t1" "$t1" 'forged.soleur.ai TXT forged'; base_comment 1 owner "$t2" "$t2" "$rows"; echo read >"$CASE/perm.stranger"; echo admin >"$CASE/perm.owner"; dns_prep "$1" cfam_dns_baseline
  got="$(run_case)"; want 'a stranger cannot plant the baseline' "$rows" "$got" || return 1
  fresh; base_comment 1 gone "$t1" "$t1" 'forged.soleur.ai TXT forged'; base_comment 1 owner "$t2" "$t2" "$rows"; echo 404 >"$CASE/perm.gone"; echo admin >"$CASE/perm.owner"; dns_prep "$1" cfam_dns_baseline
  got="$(run_case)"; want 'a deleted account is skipped' "$rows" "$got" || return 1
  fresh; base_comment 1 flaky "$t1" "$t1" "$rows"; echo 502 >"$CASE/perm.flaky"; dns_prep "$1" cfam_dns_baseline
  got="$(run_case)"; want 'a failed permission read' baseline=unreadable "$got" || return 1
  fresh; dns_prep "$1" cfam_dns_baseline
  got="$(run_case)"; want 'no baseline' baseline=none "$got" || return 1
}

# R18: the prose half of the same contract, on a joined copy.
R18_NEEDLES=(
  'Output `accept-unobserved` passes. `observe-first`, `edited`, `unreadable` and empty all hold.'
  'The check proves an admin account posted, not that a person did; the environment approval remains the human control.'
  'A real difference wins over `NO-VERDICT`.'
  'The wait runs from the apply job'"'"'s completion, whichever way it ended'
  '.jobs[] | select(.name == "cf_account_migrate_apply") | .completedAt'
  'A later snapshot would hold post-write answers, so save nothing. Post `dns-answers=unverified baseline-lost`'
  'If it persists, `Operator-authorizes:` a rehearsal.'
  '`VALUE` is `null` for `comment` and `priority`, `[]` for `tags`, and `false` for `proxied`'
  'Re-rehearse, then re-dispatch the same phase.'
  '`unnormalized <addr>`: rehearse, then re-dispatch the phase whose spec lists `<addr>`.'
  '`cloudflare_record.app` an import that plans the admitted `import-normalize` update'
  'pinned, read live after the plan and re-read after the apply exactly as the `redirects-dns` records are'
)
row_r18() {
  local j k bad=0
  j="$(joined <"$1")"
  for k in "${R18_NEEDLES[@]}"; do
    grep -qF -- "$k" <<<"$j" || { echo "    runbook lacks: $k" >&2; bad=1; }
  done
  ! grep -qF 'a pure import' <<<"$j" || { echo "    the pure-import sentence is back" >&2; bad=1; }
  ! grep -qF 'At least 360 s after `applied=true`' <<<"$j" || { echo "    the wait is anchored on applied=true" >&2; bad=1; }
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
row_r14 "$RUNBOOK"; check "R14 the first-PATCH read holds on any read failure but a 404 (run verbatim)" $?
row_r15 "$RUNBOOK"; check "R15 the restore block: pin first, one PATCH, eight-field read-back (run verbatim)" $?
row_r16 "$RUNBOOK"; check "R16 the recreate block: dns.tf fields, pin 404, one POST, read-back (run verbatim)" $?
row_r17 "$RUNBOOK"; check "R17 the DNS snapshot is 19 rows or incomplete; the baseline is saved once (run verbatim)" $?
row_r18 "$RUNBOOK"; check "R18 the hold list, wait anchor, precedence, owner labels and the tunnel-phase app-record read" $?

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

# Executable-block mutants (review fix round 2): each removes one guard from the runbook's block.
if mutate M22 "$SB/m22.md" <<'PERL'; then
s{(--jq '\.\[\]\n\s+\| \(\.body \| split\("\\n"\)\[0\] \| rtrimstr\("\\r"\)\) as \$l.*?\@tsv'\)") \|\| \{ echo unreadable; exit 0; \}}{$1}s
PERL
  expect_red "M22 (a failed comments list no longer holds)" row_r14 "$SB/m22.md"
fi
if mutate M23 "$SB/m23.md" <<'PERL'; then
s{\*\) echo unreadable; break ;;}{*) continue ;;}
PERL
  expect_red "M23 (a failed permission read falls through to an older token)" row_r14 "$SB/m23.md"
fi
if mutate M24 "$SB/m24.md" <<'PERL'; then
s{    \[ "\$perm" = admin \] \|\| continue\n}{}
PERL
  expect_red "M24 (the first-PATCH read drops the admin check)" row_r14 "$SB/m24.md"
fi
if mutate M25 "$SB/m25.md" <<'PERL'; then
s{if \[ "\$created" = "\$updated" \]; then printf '%s\\n' "\$value"; else echo edited; fi}{printf '%s\\n' "\$value"}
PERL
  expect_red "M25 (an edited first-PATCH comment passes)" row_r14 "$SB/m25.md"
fi
if mutate M26 "$SB/m26.md" <<'PERL'; then
s{IS_PIN='[^']*'}{IS_PIN='true'}
PERL
  expect_red "M26 (the restore block's first GET need not be the pin)" row_r15 "$SB/m26.md"
fi
if mutate M27 "$SB/m27.md" <<'PERL'; then
s{if \[ "\$pin" != 200 \] \|\| !}{if !}
PERL
  expect_red "M27 (the restore block accepts a non-200 first GET)" row_r15 "$SB/m27.md"
fi
if mutate M28 "$SB/m28.md" <<'PERL'; then
s{BODY_OF='\(\.result \| \{type, name, ttl\}\) \+ \{\(\$f\): \$v\}'}{BODY_OF='{(\$f): \$v}'}
PERL
  expect_red "M28 (the PATCH drops type, name and ttl)" row_r15 "$SB/m28.md"
fi
if mutate M29 "$SB/m29.md" <<'PERL'; then
s{ and \(\(\$r\[\$f\] \| n\) == \(\$v \| n\)\)}{}
PERL
  expect_red "M29 (the read-back no longer checks the named field)" row_r15 "$SB/m29.md"
fi
if mutate M30 "$SB/m30.md" <<'PERL'; then
s{"comment","tags"\] - \[\$f\]}{"comment","tags"] - ["type","name","content","ttl","proxied","priority","comment","tags"]}
PERL
  expect_red "M30 (the read-back no longer checks the other seven fields)" row_r15 "$SB/m30.md"
fi
if mutate M31 "$SB/m31.md" <<'PERL'; then
s{elif \. == "" then null }{}
PERL
  expect_red "M31 (the read-back no longer reads an empty string as null)" row_r15 "$SB/m31.md"
fi
if mutate M32 "$SB/m32.md" <<'PERL'; then
s{if type == "array" then sort elif}{if false then . elif}
PERL
  expect_red "M32 (the read-back no longer sorts arrays)" row_r15 "$SB/m32.md"
fi
if mutate M33 "$SB/m33.md" <<'PERL'; then
s{\&\& jq -en --argjson v "\$VALUE" 'true' >/dev/null 2>&1; then}{; then}
PERL
  expect_red "M33 (the restore block no longer refuses a bad VALUE)" row_r15 "$SB/m33.md"
fi
if mutate M34 "$SB/m34.md" <<'PERL'; then
s#(u="https://api\.cloudflare\.com/client/v4/zones/\$1/dns_records/\$2"\n\s+api\(\) \{ curl --disable --noproxy "\*" -sS --max-time 10) --config - "\$@" < <\(printf "header = \\"Authorization: Bearer %s\\"\\n" "\$t"\); \}#$1 -H "Authorization: Bearer \$t" "\$@"; }#
PERL
  expect_red "M34 (the restore block puts the bearer in argv)" row_r15 "$SB/m34.md"
fi
if mutate M35 "$SB/m35.md" <<'PERL'; then
s{if \[ "\$pin" != 404 \]; then}{if [ "\$pin" = never ]; then}
PERL
  expect_red "M35 (the recreate block runs when the pinned id still answers)" row_r16 "$SB/m35.md"
fi
if mutate M36 "$SB/m36.md" <<'PERL'; then
s{then \(if \$pages == "soleur-docs-40x\.pages\.dev" then \$pages else error\("pages"\) end\)}{then \$pages}
PERL
  expect_red "M36 (the recreate block takes any Pages subdomain)" row_r16 "$SB/m36.md"
fi
if mutate M37 "$SB/m37.md" <<'PERL'; then
s{\| all\(\. as \$k \| \(\$r\[\$k\] \| n\) == \(\$want\[\$k\] \| n\)\)\)}{| length > 0)}
PERL
  expect_red "M37 (the recreate read-back no longer compares the fields)" row_r16 "$SB/m37.md"
fi
if mutate M38 "$SB/m38.md" <<'PERL'; then
s{and \(\$r\.id == \$id\) and \(\$r\.zone_id == null or \$r\.zone_id == \$z\)}{and (\$r.zone_id == null or \$r.zone_id == \$z)}
PERL
  expect_red "M38 (the recreate read-back no longer binds the returned id)" row_r16 "$SB/m38.md"
fi
if mutate M39 "$SB/m39.md" <<'PERL'; then
s#(base="https://api\.cloudflare\.com/client/v4/zones/\$1/dns_records"\n\s+api\(\) \{ curl --disable --noproxy "\*" -sS --max-time 10) --config - "\$@" < <\(printf "header = \\"Authorization: Bearer %s\\"\\n" "\$t"\); \}#$1 -H "Authorization: Bearer \$t" "\$@"; }#
PERL
  expect_red "M39 (the recreate block puts the bearer in argv)" row_r16 "$SB/m39.md"
fi
if mutate M40 "$SB/m40.md" <<'PERL'; then
s{\[ "\$\(grep -c \. "\$1"\)" -eq 19 \] && }{}
PERL
  expect_red "M40 (the snapshot check no longer counts 19 rows)" row_r17 "$SB/m40.md"
fi
if mutate M41 "$SB/m41.md" <<'PERL'; then
s{ && ! grep -q 'NO-VERDICT' "\$1"}{}
PERL
  expect_red "M41 (the snapshot check accepts a NO-VERDICT)" row_r17 "$SB/m41.md"
fi
if mutate M42 "$SB/m42.md" <<'PERL'; then
s{\*\) echo baseline=exists; return 0 ;;}{*) ;;}
PERL
  expect_red "M42 (a saved baseline can be overwritten)" row_r17 "$SB/m42.md"
fi
if mutate M43 "$SB/m43.md" <<'PERL'; then
s{  \[ "\$\(cfam_dns_complete "\$1"\)" = snapshot=complete \] \|\| \{ echo snapshot=incomplete; return 1; \}\n}{}
PERL
  expect_red "M43 (an incomplete snapshot can be saved)" row_r17 "$SB/m43.md"
fi
if mutate M44 "$SB/m44.md" <<'PERL'; then
s{(cfam_dns_baseline\(\) \{.*?)    \[ "\$perm" = admin \] \|\| continue\n}{$1}s
PERL
  expect_red "M44 (a stranger's comment can plant the baseline)" row_r17 "$SB/m44.md"
fi
if mutate M45 "$SB/m45.md" <<'PERL'; then
s{\*\) echo baseline=unreadable; return 0 ;;}{*) continue ;;}
PERL
  expect_red "M45 (a failed baseline permission read is skipped)" row_r17 "$SB/m45.md"
fi
if mutate M46 "$SB/m46.md" <<'PERL'; then
s{\z}{\n`cloudflare_record.app` a pure import\n}
PERL
  expect_red "M46 (the pure-import sentence comes back)" row_r18 "$SB/m46.md"
fi
if mutate M47 "$SB/m47.md" <<'PERL'; then
s{At least 360 s after the apply job's `completedAt`}{At least 360 s after `applied=true`}
PERL
  expect_red "M47 (the wait re-anchored on applied=true)" row_r18 "$SB/m47.md"
fi
if mutate M48 "$SB/m48.md" <<'PERL'; then
s{\*'\(HTTP 404\)'\*\) continue ;; \*\) echo unreadable; break ;;}{*) echo unreadable; break ;;}
PERL
  expect_red "M48 (a deleted account blocks the first-PATCH decision)" row_r14 "$SB/m48.md"
fi
if mutate M49 "$SB/m49.md" <<'PERL'; then
s{\^\(type\|name\|content\|ttl\|proxied\|priority\|comment\|tags\)\$}{^.+\$}
PERL
  expect_red "M49 (the restore block takes any field name)" row_r15 "$SB/m49.md"
fi
if mutate M50 "$SB/m50.md" <<'PERL'; then
s{\.result as \$r \| \(\.success == true\) and \(\$r\.id == \$id\) and \(\(\$r\[\$f\]}{.result as \$r | (.success == true) and ((\$r[\$f]}
PERL
  expect_red "M50 (the restore read-back no longer binds the pinned id)" row_r15 "$SB/m50.md"
fi
if mutate M51 "$SB/m51.md" <<'PERL'; then
s{t="\$\{CF_API_TOKEN:-\}"; case "\$t" in ""\|\*\[!A-Za-z0-9\._~\+/=-\]\*\) echo token-shape-refused; exit 3 ;; esac\n(\s+u="https)}{t="\$\{CF_API_TOKEN:-\}"\n$1}
PERL
  expect_red "M51 (the restore block drops the token-shape guard)" row_r15 "$SB/m51.md"
fi
if mutate M52 "$SB/m52.md" <<'PERL'; then
s{\n\s+elif test\("\[\$%\]\\\\\{"\) then error\("interpolation"\) else fromjson end\)}{\n          else fromjson end)}
PERL
  expect_red "M52 (the recreate block accepts an interpolated value)" row_r16 "$SB/m52.md"
fi
if mutate M53 "$SB/m53.md" <<'PERL'; then
s{\@tsv'\)" \|\| \{ echo baseline=unreadable; return 0; \}}{\@tsv')"}
PERL
  expect_red "M53 (a failed baseline list reads as no baseline)" row_r17 "$SB/m53.md"
fi
if mutate M54 "$SB/m54.md" <<'PERL'; then
s{if \[ "\$created" = "\$updated" \]; then printf '%s' "\$body" \| base64 -d \| tail -n \+2; else echo baseline=edited; fi}{printf '%s' "\$body" | base64 -d | tail -n +2}
PERL
  expect_red "M54 (an edited baseline is trusted)" row_r17 "$SB/m54.md"
fi
if mutate M55 "$SB/m55.md" <<'PERL'; then
s{(echo baseline=edited; fi\n    return 0\n  done) <<<"\$rows"}{$1 < <(tac <<<"\$rows")}
PERL
  expect_red "M55 (the newest baseline replaces the oldest)" row_r17 "$SB/m55.md"
fi
if mutate M56 "$SB/m56.md" <<'PERL'; then
s{baseline=\*\) printf '%s\\n' "\$have"; return 1 ;;}{baseline=*) ;;}
PERL
  expect_red "M56 (a save proceeds over an edited or unreadable baseline)" row_r17 "$SB/m56.md"
fi
if mutate M57 "$SB/m57.md" <<'PERL'; then
s{t="\$\{CF_API_TOKEN:-\}"; case "\$t" in ""\|\*\[!A-Za-z0-9\._~\+/=-\]\*\) echo token-shape-refused; exit 3 ;; esac\n(\s+base="https)}{t="\$\{CF_API_TOKEN:-\}"\n$1}
PERL
  expect_red "M57 (the recreate block drops the token-shape guard)" row_r16 "$SB/m57.md"
fi
if mutate M58 "$SB/m58.md" <<'PERL'; then
s{if \[\[ "\$Z" =~ \^\[0-9a-f\]\{32\}\$ && "\$ID" =~ \^\[0-9a-f\]\{32\}\$ && -n "\$BODY" \]\]}{if [[ "\$Z" =~ ^[0-9a-f]{32}\$ && -n "\$BODY" ]]}
PERL
  expect_red "M58 (the recreate block runs with no pin)" row_r16 "$SB/m58.md"
fi
if mutate M59 "$SB/m59.md" <<'PERL'; then
s{if \[\[ "\$Z" =~ \^\[0-9a-f\]\{32\}\$ && "\$ID" =~ \^\[0-9a-f\]\{32\}\$ && "\$FIELD"}{if [[ "\$Z" =~ ^[0-9a-f]{32}\$ && "\$FIELD"}
PERL
  expect_red "M59 (the restore block runs with no pin)" row_r15 "$SB/m59.md"
fi
if mutate M60 "$SB/m60.md" <<'PERL'; then
s{echo baseline=incomplete; return 1; fi}{:; fi}
PERL
  expect_red "M60 (an unusable existing baseline passes as saved)" row_r17 "$SB/m60.md"
fi
# T1..T12: removing any one sentence of the R18 text contract turns R18 red (matched across line wraps).
i=0
for k in "${R18_NEEDLES[@]}"; do
  i=$((i + 1)); f="$SB/t$i.md"
  NEEDLE="$k" perl -0777 -pe 'my $n = quotemeta($ENV{NEEDLE}); $n =~ s/\\ /\\s+/g; s/$n/MUTATED/' "$RUNBOOK" >"$f"
  if cmp -s "$f" "$RUNBOOK"; then fail "mutation T$i did not land"; continue; fi
  pass "mutation T$i landed"
  expect_red "T$i (the R18 sentence is removed: ${k:0:40})" row_r18 "$f"
done

TOTAL=$((PASS + FAIL)); FLOOR=165
if [[ "$TOTAL" -lt "$FLOOR" ]]; then
  printf '  [FAIL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$TOTAL" "$FLOOR" >&2
  echo "Total: ${TOTAL} assertions, $((FAIL + 1)) failed"; exit 1
fi
echo "Total: ${TOTAL} assertions, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
