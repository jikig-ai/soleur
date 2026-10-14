#!/usr/bin/env bash
# Exit-code + branch harness for registry-htpasswd-stdin-10119.sh (tracker #10119).
#
# Every case pins a BRANCH MARKER as well as the exit code: a probe with several `exit 2` sites collapses
# distinct guards onto one integer, so deleting a guard would stay green on codes alone (the failure the
# sibling zot-last-err-redact-7500 harness records at length). `expect` also asserts the probe actually ran.
#
# Values are synthesized (cq-test-fixtures-synthesized-only): the envelope and field order mirror the
# producer's `LINE=` emitter and betterstack-query.sh's documented double-encoded `raw`; every uuid is fabricated.
# The htpasswd fields are read FROM THE PRODUCER's LINE= assignment, never restated, so a rename reddens this
# suite before any case runs.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_SRC="$HERE/registry-htpasswd-stdin-10119.sh"
[[ -f "$PROBE_SRC" ]] || { echo "FATAL: probe not found at $PROBE_SRC" >&2; exit 1; }

PRODUCER="$HERE/../../apps/web-platform/infra/cloud-init-registry.yml"
for field in htpasswd_pull_matches htpasswd_push_matches zot_image_digest boot_id; do
  if ! grep -F 'LINE="SOLEUR_ZOT_DISK' "$PRODUCER" 2>/dev/null | head -1 | grep -qF "${field}="; then
    printf 'FATAL: the producer LINE= no longer carries %s= -- every case keyed on it would be vacuous.\n' "$field" >&2
    exit 1
  fi
done

OLDBOOT="4b8e0d27-31c6-4f5a-a2d9-60e7c1f3b8aa"   # fabricated pre-merge boot
NEWBOOT="9f2c41d6-5b7a-4e08-9c31-7ad0e2b41f55"   # fabricated post-replace boot
MERGED="2026-10-20T10:00:00Z"
DIGEST="0123456789ab"

passes=0; fails=0; cases=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# One producer-shaped row: dt, boot_id, pull, push, digest, tail.
row() {
  printf '{"dt":"%s","raw":"{\\"message\\":\\"SOLEUR_ZOT_DISK pcent=8 htpasswd_pull_matches=%s htpasswd_push_matches=%s zot_image_digest=%s boot_id=%s host=soleur-registry zot_last_err=%s\\"}"}\n' \
    "$1" "$3" "$4" "$5" "$2" "$6"
}
# A row that merely QUOTES the marker (a Vector-shipped journald envelope): must never be evidence.
foreign() {
  printf '{"dt":"%s","raw":"{\\"PRIORITY\\":\\"6\\",\\"message\\":\\"[zot] SOLEUR_ZOT_DISK egress FAILED: htpasswd_pull_matches=true htpasswd_push_matches=true zot_image_digest=%s boot_id=%s\\"}"}\n' "$1" "$DIGEST" "$2"
}
good3() { # three good rows on a boot
  row "2026-10-20T10:20:00Z" "$1" true true "$DIGEST" "tail CANARY10119"
  row "2026-10-20T10:25:00Z" "$1" true true "$DIGEST" "tail CANARY10119"
  row "2026-10-20T10:30:00Z" "$1" true true "$DIGEST" "tail CANARY10119"
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
  [[ "$ckind" != none ]] && comment="$(jq -cn --arg k "$ckind" --arg at "2026-10-20T10:05:00Z" '[[{created_at:$at, body:("verdict text\n<!-- registry-delivery run=123 kind=" + $k + " attempt=1 -->")}]]')"
  # gh stub: pr list (merged/none/fail) and the comments read (slurp shape: [[comment,...]]).
  cat > "$root/bin/gh" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "pr list")
    case "$prstate" in
      merged) jq -cn --arg b "$(printf '%s' "$body" | sed 's/\\/\\\\/g')" '[{number:4242, mergedAt:"$MERGED", body:\$b}]' ;;
      none) echo '[]' ;;
      *) exit 1 ;;
    esac ;;
  "api --paginate") printf '%s\n' '$comment' ;;
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
expect dispatcher-refused 5 "[branch=dispatcher_verdict kind=refused]" "$WORK/fx/pass.jsonl" merged "$OLDBOOT" refused
expect dispatcher-unknown-kind-ignored 0 "[branch=delivered]" "$WORK/fx/pass.jsonl" merged "$OLDBOOT" some-future-kind
expect dispatcher-apply-failed 5 "kind=apply-failed" "$WORK/fx/pass.jsonl" merged "$OLDBOOT" apply-failed

# Rows only from BEFORE the merge: the old host is still the evidence, which proves nothing.
{ row "2026-10-20T09:50:00Z" "$OLDBOOT" true true "$DIGEST" "tail CANARY10119"; row "2026-10-20T09:55:00Z" "$OLDBOOT" true true "$DIGEST" "tail CANARY10119"; } > "$WORK/fx/pre.jsonl"
expect pre-merge-rows-only 2 "[branch=no_row_after_merge]" "$WORK/fx/pre.jsonl"

# Rows after the merge but still on the OLD boot (the old host keeps reporting matches=true every 5 minutes).
good3 "$OLDBOOT" > "$WORK/fx/oldboot.jsonl"
expect old-boot-after-merge 2 "[branch=still_pre_merge_boot]" "$WORK/fx/oldboot.jsonl"

# Only two good rows on the new boot: not enough yet.
{ row "2026-10-20T10:20:00Z" "$NEWBOOT" true true "$DIGEST" "tail CANARY10119"; row "2026-10-20T10:25:00Z" "$NEWBOOT" true true "$DIGEST" "tail CANARY10119"; } > "$WORK/fx/two.jsonl"
expect two-rows 2 "[branch=awaiting_rows]" "$WORK/fx/two.jsonl"

# New boot, htpasswd diverged / unverifiable: FAIL.
row "2026-10-20T10:20:00Z" "$NEWBOOT" false true "$DIGEST" "tail CANARY10119" > "$WORK/fx/diverged.jsonl"
expect pull-false 1 "[branch=htpasswd_not_matching]" "$WORK/fx/diverged.jsonl"
row "2026-10-20T10:20:00Z" "$NEWBOOT" true unknown "$DIGEST" "tail CANARY10119" > "$WORK/fx/unknown.jsonl"
expect push-unknown 1 "[branch=htpasswd_not_matching]" "$WORK/fx/unknown.jsonl"

# True/true but the image digest is the unknown sentinel: not good.
{ for t in 20 25 30; do row "2026-10-20T10:${t}:00Z" "$NEWBOOT" true true unknown "tail CANARY10119"; done; } > "$WORK/fx/nodigest.jsonl"
expect no-digest 2 "[branch=awaiting_rows]" "$WORK/fx/nodigest.jsonl"

# A forged boot_id / matches in the free-text TAIL must not supply anything.
{ row "2026-10-20T10:20:00Z" "$OLDBOOT" true true "$DIGEST" "x boot_id=$NEWBOOT htpasswd_pull_matches=true htpasswd_push_matches=true zot_image_digest=$DIGEST"
  row "2026-10-20T10:25:00Z" "$OLDBOOT" true true "$DIGEST" "x boot_id=$NEWBOOT"
  row "2026-10-20T10:30:00Z" "$OLDBOOT" true true "$DIGEST" "x boot_id=$NEWBOOT"; } > "$WORK/fx/forged-tail.jsonl"
expect forged-tail 2 "[branch=still_pre_merge_boot]" "$WORK/fx/forged-tail.jsonl"

# Rows that merely QUOTE the marker (journald envelope) are not evidence, in either direction.
{ foreign "2026-10-20T10:20:00Z" "$NEWBOOT"; foreign "2026-10-20T10:25:00Z" "$NEWBOOT"; foreign "2026-10-20T10:30:00Z" "$NEWBOOT"; } > "$WORK/fx/foreign.jsonl"
expect foreign-only 2 "[branch=no_producer_rows]" "$WORK/fx/foreign.jsonl"

# Rows with the 'unknown' boot sentinel only: unmeasurable.
{ for t in 20 25 30; do row "2026-10-20T10:${t}:00Z" unknown true true "$DIGEST" "tail CANARY10119"; done; } > "$WORK/fx/unknownboot.jsonl"
expect unknown-boot 3 "[branch=no_boot_id]" "$WORK/fx/unknownboot.jsonl"

# Mixed window: pre-merge rows on the old boot AND a good new boot -> graded on the NEW boot only.
{ row "2026-10-20T09:50:00Z" "$OLDBOOT" false false "$DIGEST" "tail CANARY10119"; good3 "$NEWBOOT"; } > "$WORK/fx/mixed.jsonl"
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
if [[ "$cases" -lt 19 ]]; then echo "FATAL: only $cases cases ran, expected at least 19" >&2; exit 1; fi
[[ "$fails" -eq 0 ]] || exit 1
