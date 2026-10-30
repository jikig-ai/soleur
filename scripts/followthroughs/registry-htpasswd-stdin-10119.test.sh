#!/usr/bin/env bash
# Exit-code + branch harness for registry-htpasswd-stdin-10119.sh (tracker #10119).
#
# Every case pins a BRANCH MARKER as well as the exit code: a probe with several `exit 2` sites collapses
# distinct guards onto one integer, so deleting a guard would stay green on codes alone (the failure the
# sibling zot-last-err-redact-7500 harness records at length). `expect` also asserts the probe actually ran.
#
# Values are synthesized (cq-test-fixtures-synthesized-only): the envelope and field order mirror the
# producer's `LINE=` emitter and betterstack-query.sh's documented double-encoded `raw`; every uuid is fabricated.
# The field NAMES are checked against the PRODUCER's LINE= assignment before any case runs, so a rename reddens
# this suite (the fixture rows below still spell them out, which is why that precondition exists).
#
# `dt` is emitted in Better Stack's real form (`YYYY-MM-DD HH:MM:SS.ffffff`, space, no zone) by default; gh's
# `mergedAt` is `T...Z`. A raw string compare of the two drops every same-UTC-day row, so the default fixtures
# are what make the merge-day cases decisive. One case uses the `T...Z` form as a control (DT_FORM=iso).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_SRC="$HERE/registry-htpasswd-stdin-10119.sh"
[[ -f "$PROBE_SRC" ]] || { echo "FATAL: probe not found at $PROBE_SRC" >&2; exit 1; }

PRODUCER="$HERE/../../apps/web-platform/infra/cloud-init-registry.yml"
producer_line="$(grep -F 'LINE="SOLEUR_ZOT_DISK' "$PRODUCER" 2>/dev/null | head -1)"
for field in htpasswd_pull_matches htpasswd_push_matches zot_image_digest boot_id; do
  if ! grep -qF "${field}=" <<<"$producer_line"; then
    printf 'FATAL: the producer LINE= no longer carries %s= -- every case keyed on it would be vacuous.\n' "$field" >&2
    exit 1
  fi
done

OLDBOOT="4b8e0d27-31c6-4f5a-a2d9-60e7c1f3b8aa"   # fabricated pre-merge boot
NEWBOOT="9f2c41d6-5b7a-4e08-9c31-7ad0e2b41f55"   # fabricated post-replace boot
MERGED="$(date -u -d '2 hours ago' +%FT%TZ)"   # dynamic: a baked literal rots past the 24h stale window
_M_EPOCH="$(date -u -d "$MERGED" +%s)"
ts() { date -u -d "@$((_M_EPOCH + $1))" +%FT%TZ; }   # seconds offset from MERGED
T_MERGED="$MERGED"      # per-case override of the merge time (the stale-wait case moves it into the past)
T_RUNS=success          # per-case dispatcher-run listing: success | none | fail
DT_FORM=space           # row dt form: space (Better Stack's real shape) | iso
DIGEST="0123456789ab"

passes=0; fails=0; cases=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# One producer-shaped row: dt, boot_id, pull, push, digest, tail.
row() {
  local dt="$1"
  if [[ "$DT_FORM" == space ]]; then dt="${dt/T/ }"; dt="${dt%Z}.123456"; fi
  printf '{"dt":"%s","raw":"{\\"message\\":\\"SOLEUR_ZOT_DISK pcent=8 htpasswd_pull_matches=%s htpasswd_push_matches=%s zot_image_digest=%s boot_id=%s host=soleur-registry zot_last_err=%s\\"}"}\n' \
    "$dt" "$3" "$4" "$5" "$2" "$6"
}
# A row that merely QUOTES the marker (a Vector-shipped journald envelope): must never be evidence.
foreign() {
  printf '{"dt":"%s","raw":"{\\"PRIORITY\\":\\"6\\",\\"message\\":\\"[zot] SOLEUR_ZOT_DISK egress FAILED: htpasswd_pull_matches=true htpasswd_push_matches=true zot_image_digest=%s boot_id=%s\\"}"}\n' "$1" "$DIGEST" "$2"
}
good3() { # three good rows on a boot
  row "$(ts 1200)" "$1" true true "$DIGEST" "tail CANARY10119"
  row "$(ts 1500)" "$1" true true "$DIGEST" "tail CANARY10119"
  row "$(ts 1800)" "$1" true true "$DIGEST" "tail CANARY10119"
}

# run_probe <name> <fixture-file> [pr-state: merged|none|listfail] [body-boot: uuid|none] [comment-kind: kind|none]
run_probe() {
  local fixture="$2" prstate="${3:-merged}" bodyboot="${4:-$OLDBOOT}" ckind="${5:-none}" root="$WORK/root-$1"
  rm -rf "$root"; mkdir -p "$root/scripts/followthroughs" "$root/scripts/lib" "$root/bin"
  cp "$PROBE_SRC" "$root/scripts/followthroughs/"
  cp "$HERE/../lib/zot-telemetry-parse.sh" "$root/scripts/lib/"
  printf '#!/usr/bin/env bash\ncase "$*" in *"--since 24h"*"--grep SOLEUR_ZOT_DISK"*) cat %q ;; *) echo "STUB: unexpected argv: $*" >&2; exit 64 ;; esac\n' "$fixture" > "$root/scripts/betterstack-query.sh"
  local body="Fix text"; [[ "$bodyboot" != none ]] && body="$body"$'\n'"Pre-merge boot_id: $bodyboot"$'\n'"more text"
  local comment='[]'
  # comment-kind may be a comma list (posted in order), e.g. refused,ok = a genuine failure then a forged success.
  [[ "$ckind" != none ]] && comment="$(jq -cn --arg ks "$ckind" --arg at "$(ts 300)" '[($ks | split(",") | map({created_at:$at, body:("verdict text\n<!-- registry-delivery run=123 kind=" + . + " attempt=1 -->")}))]')"
  # gh stub: pr list (merged/none/fail) and the comments read (slurp shape: [[comment,...]]).
  cat > "$root/bin/gh" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "pr list")
    case "$prstate" in
      merged) jq -cn --arg b "$(printf '%s' "$body" | sed 's/\\/\\\\/g')" '[{number:4242, mergedAt:"$T_MERGED", body:\$b}]' ;;
      none) echo '[]' ;;
      *) exit 1 ;;
    esac ;;
  "api --paginate") printf '%s\n' '$comment' ;;
  "run list")
    case "$T_RUNS" in
      success) echo '[{"conclusion":"success","createdAt":"'"$(ts 180)"'"}]' ;;
      none) echo '[{"conclusion":"success","createdAt":"'"$(ts -86400)"'"},{"conclusion":"failure","createdAt":"'"$(ts 180)"'"}]' ;;
      *) exit 1 ;;
    esac ;;
  *) echo "STUB gh: unexpected: \$*" >&2; exit 64 ;;
esac
STUB
  chmod +x "$root/bin/gh" "$root/scripts/betterstack-query.sh"
  ( cd "$root" && env -i PATH="$root/bin:/usr/bin:/bin" HOME="$root" BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
      bash scripts/followthroughs/registry-htpasswd-stdin-10119.sh ) > "$WORK/out-$1" 2>&1
  echo $?
}

expect() { # <name> <exit> <branch marker> <fixture> [run_probe extras...]
  local name="$1" want="$2" marker="$3" fx="$4"; shift 4
  cases=$((cases + 1))
  local got; got="$(run_probe "$name" "$fx" "$@")"
  if [[ "$got" == "$want" ]] && grep -qF -- "$marker" "$WORK/out-$name" && ! grep -qF CANARY10119 "$WORK/out-$name"; then
    pass "$name: exit $want with $marker, and no row text echoed"
  else
    fail "$name: want exit $want + '$marker' without row text; got exit $got: $(head -c 300 "$WORK/out-$name" | tr '\n' ' ')"
  fi
}

echo "--- registry-htpasswd-stdin-10119 probe ---"
mkdir -p "$WORK/fx"

good3 "$NEWBOOT" > "$WORK/fx/pass.jsonl"
expect pass 0 "[branch=delivered]" "$WORK/fx/pass.jsonl"

expect not-merged 2 "[branch=not_merged]" "$WORK/fx/pass.jsonl" none
expect gh-fails 2 "[branch=gh_pr_list_failed]" "$WORK/fx/pass.jsonl" listfail
expect no-pre-boot 3 "[branch=no_pre_boot]" "$WORK/fx/pass.jsonl" merged none
good3 "$OLDBOOT" > "$WORK/fx/oldboot.jsonl"
# A failure verdict escalates while the probe has no PASS ...
expect dispatcher-refused 5 "[branch=dispatcher_verdict kind=refused]" "$WORK/fx/oldboot.jsonl" merged "$OLDBOOT" refused
expect dispatcher-apply-failed 5 "kind=apply-failed" "$WORK/fx/oldboot.jsonl" merged "$OLDBOOT" apply-failed
# ... every failure kind escalates (a bare token in FAIL_KINDS cannot be dropped silently) ...
for k in dispatch-failed unverified cancelled gate-failed gate-unproven undetermined; do
  expect "dispatcher-kind-$k" 5 "kind=$k" "$WORK/fx/oldboot.jsonl" merged "$OLDBOOT" "$k"
done
# ... a forged success marker posted AFTER a genuine failure cannot mask it ...
expect dispatcher-forged-ok-after-refused 5 "kind=refused" "$WORK/fx/oldboot.jsonl" merged "$OLDBOOT" refused,ok
# ... but measured success outranks a stale failure comment (a refusal resolved by a later re-fire leaves its comment behind).
expect stale-refusal-outranked-by-pass 0 "[branch=delivered]" "$WORK/fx/pass.jsonl" merged "$OLDBOOT" refused
expect dispatcher-unknown-kind-ignored 0 "[branch=delivered]" "$WORK/fx/pass.jsonl" merged "$OLDBOOT" some-future-kind

# A new boot_id is not delivery by itself (the old host self-reboots): no successful dispatcher run since the merge.
T_RUNS=none;  expect no-dispatch-run 2 "[branch=no_successful_dispatch_run]" "$WORK/fx/pass.jsonl"
T_RUNS=fail;  expect runs-query-fails 2 "[branch=runs_query_failed]" "$WORK/fx/pass.jsonl"
T_RUNS=success

# The T...Z dt form (the control for the default space form) is accepted too.
DT_FORM=iso; good3 "$NEWBOOT" > "$WORK/fx/pass-iso.jsonl"; DT_FORM=space
expect dt-iso-form 0 "[branch=delivered]" "$WORK/fx/pass-iso.jsonl"

# Rows only from BEFORE the merge: the old host is still the evidence, which proves nothing.
{ row "$(ts -600)" "$OLDBOOT" true true "$DIGEST" "tail CANARY10119"; row "$(ts -300)" "$OLDBOOT" true true "$DIGEST" "tail CANARY10119"; } > "$WORK/fx/pre.jsonl"
expect pre-merge-rows-only 2 "[branch=no_row_after_merge]" "$WORK/fx/pre.jsonl"

# Rows after the merge but still on the OLD boot (the old host keeps reporting matches=true every 5 minutes).
expect old-boot-after-merge 2 "[branch=still_pre_merge_boot]" "$WORK/fx/oldboot.jsonl"

# Only two good rows on the new boot: not enough yet.
{ row "$(ts 1200)" "$NEWBOOT" true true "$DIGEST" "tail CANARY10119"; row "$(ts 1500)" "$NEWBOOT" true true "$DIGEST" "tail CANARY10119"; } > "$WORK/fx/two.jsonl"
expect two-rows 2 "[branch=awaiting_rows]" "$WORK/fx/two.jsonl"

# New boot, htpasswd diverged / unverifiable on a full window of rows (3) with no good row: FAIL.
{ for t in 1200 1500 1800; do row "$(ts "$t")" "$NEWBOOT" false true "$DIGEST" "tail CANARY10119"; done; } > "$WORK/fx/diverged.jsonl"
expect pull-false 1 "[branch=htpasswd_not_matching]" "$WORK/fx/diverged.jsonl"
{ for t in 1200 1500 1800; do row "$(ts "$t")" "$NEWBOOT" true unknown "$DIGEST" "tail CANARY10119"; done; } > "$WORK/fx/unknown.jsonl"
expect push-unknown 1 "[branch=htpasswd_not_matching]" "$WORK/fx/unknown.jsonl"
# ONE bad row is not proof (a boot-time race or a Doppler hiccup): keep waiting.
row "$(ts 1200)" "$NEWBOOT" false true "$DIGEST" "tail CANARY10119" > "$WORK/fx/one-bad.jsonl"
expect one-bad-row-keeps-waiting 2 "[branch=awaiting_rows]" "$WORK/fx/one-bad.jsonl"

# True/true but the image digest is the unknown sentinel on a full window: FAIL (zot is not serving the pinned image).
{ for t in 1200 1500 1800; do row "$(ts "$t")" "$NEWBOOT" true true unknown "tail CANARY10119"; done; } > "$WORK/fx/nodigest.jsonl"
expect no-digest 1 "[branch=no_real_digest]" "$WORK/fx/nodigest.jsonl"

# Old-boot rows must not count toward the new boot: two good rows on the OLD boot plus one on the NEW one is one row, not three.
{ row "$(ts 1200)" "$OLDBOOT" true true "$DIGEST" "tail CANARY10119"; row "$(ts 1500)" "$OLDBOOT" true true "$DIGEST" "tail CANARY10119"
  row "$(ts 1800)" "$NEWBOOT" true true "$DIGEST" "tail CANARY10119"; } > "$WORK/fx/scoped.jsonl"
expect scoped-to-new-boot 2 "[branch=awaiting_rows]" "$WORK/fx/scoped.jsonl"

# Waiting is bounded: a NOT YET that outlives 24h from the merge becomes CANNOT ESTABLISH.
T_MERGED="2026-01-01T10:00:00Z"; expect stale-wait 3 "[branch=stale_still_pre_merge_boot]" "$WORK/fx/oldboot.jsonl"; T_MERGED="$MERGED"

# A forged boot_id / matches in the free-text TAIL must not supply anything.
{ row "$(ts 1200)" "$OLDBOOT" true true "$DIGEST" "x boot_id=$NEWBOOT htpasswd_pull_matches=true htpasswd_push_matches=true zot_image_digest=$DIGEST"
  row "$(ts 1500)" "$OLDBOOT" true true "$DIGEST" "x boot_id=$NEWBOOT"
  row "$(ts 1800)" "$OLDBOOT" true true "$DIGEST" "x boot_id=$NEWBOOT"; } > "$WORK/fx/forged-tail.jsonl"
expect forged-tail 2 "[branch=still_pre_merge_boot]" "$WORK/fx/forged-tail.jsonl"

# Rows that merely QUOTE the marker (journald envelope) are not evidence, in either direction.
{ foreign "$(ts 1200)" "$NEWBOOT"; foreign "$(ts 1500)" "$NEWBOOT"; foreign "$(ts 1800)" "$NEWBOOT"; } > "$WORK/fx/foreign.jsonl"
expect foreign-only 2 "[branch=no_producer_rows]" "$WORK/fx/foreign.jsonl"

# Rows with the 'unknown' boot sentinel only: unmeasurable.
{ for t in 1200 1500 1800; do row "$(ts "$t")" unknown true true "$DIGEST" "tail CANARY10119"; done; } > "$WORK/fx/unknownboot.jsonl"
expect unknown-boot 3 "[branch=no_boot_id]" "$WORK/fx/unknownboot.jsonl"

# Mixed window: pre-merge rows on the old boot AND a good new boot -> graded on the NEW boot only.
{ row "$(ts -600)" "$OLDBOOT" false false "$DIGEST" "tail CANARY10119"; good3 "$NEWBOOT"; } > "$WORK/fx/mixed.jsonl"
expect mixed-window 0 "[branch=delivered]" "$WORK/fx/mixed.jsonl"

# Credentials unset: the guard fires before any read.
cases=$((cases + 1))
root="$WORK/root-nocreds"; rm -rf "$root"; mkdir -p "$root/scripts/followthroughs"; cp "$PROBE_SRC" "$root/scripts/followthroughs/"
( cd "$root" && env -i PATH="/usr/bin:/bin" HOME="$root" bash scripts/followthroughs/registry-htpasswd-stdin-10119.sh ) > "$WORK/out-nocreds" 2>&1; got=$?
if [[ "$got" == 2 ]] && grep -qF "[branch=creds_unset]" "$WORK/out-nocreds"; then pass "nocreds: exit 2 with [branch=creds_unset]"; else fail "nocreds: got $got: $(head -c 200 "$WORK/out-nocreds")"; fi

# Refuses to run traced with a live credential (#7797).
cases=$((cases + 1))
( cd "$WORK/root-pass" && env -i PATH="$WORK/root-pass/bin:/usr/bin:/bin" HOME="$WORK" BETTERSTACK_QUERY_PASSWORD=p bash -x scripts/followthroughs/registry-htpasswd-stdin-10119.sh ) > "$WORK/out-xtrace" 2>&1; got=$?
if [[ "$got" == 78 ]] && ! grep -qE "BETTERSTACK_QUERY_PASSWORD=p|PASSWORD=p" "$WORK/out-xtrace"; then pass "xtrace: refused with exit 78 and no credential traced"; else fail "xtrace: got $got"; fi

# Positive control: the helpers move both counters, and the case counter matches the cases run.
_p="$passes"; _f="$fails"; pass "control (expected)" >/dev/null; fail "control (expected, retracted)" >/dev/null 2>&1
if [[ "$passes" -ne $((_p + 1)) || "$fails" -ne $((_f + 1)) ]]; then echo "FATAL: pass()/fail() do not count" >&2; exit 2; fi
passes=$((passes - 1)); fails=$((fails - 1))

echo "=== registry-htpasswd-stdin-10119: $passes passed, $fails failed ($cases cases) ==="
if [[ "$cases" -lt 32 ]]; then
  printf '[FATAL] anti-vacuity floor: only %d cases ran, expected at least 32\n' "$cases" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]] || exit 1
