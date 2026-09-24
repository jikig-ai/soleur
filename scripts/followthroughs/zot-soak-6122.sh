#!/usr/bin/env bash
# Follow-through soak gate for #6122 Phase 5 (registry migration GHCR → self-hosted zot).
#
# zot was provisioned and backfilled before the 2026-07-17 pull-site cutover, and since #8036 1c
# (rolling deploy) and 1d (fresh boot, ADR-096 5.3b-i) no host-side code reads GHCR at all: zot is
# the sole host read path, and a zot miss ends the pull instead of falling back. What this gate
# now authorizes (DECISION: B3 — CI's GHCR push/read is ADR-169's restore source and is NOT
# gated here):
#   - ADR-096 5.6, the flip adopting → accepted, once 5.3b-iii and 5.4 are also done;
#   - #6129, WARN → ENFORCE.
# It PASSES (closes the tracker) only when, over the window from START to now, Sentry shows:
#   (a) ZERO events across BOTH signals the companion alarm
#       (sentry_alert.zot_mirror_fallback_rate) watches — see FAIL_QUERIES below;
#   (a') ZERO web fresh-boot pull fatals (`stage:"pull" level:fatal`) — a separate arm OUTSIDE
#       FAIL_QUERIES, see WEB_FATAL below for why it is not a member;
#   (b) a MIN_SAMPLE of zot-served pulls PER image (registry:"zot" image:"web" /
#       image:"inngest") — so a vacuous "zero events because nothing deployed" cannot
#       close the tracker. Proof the zot path was actually exercised.
#
# The TWO watched signals and their emitters (anchored on EMIT NAMES, not line numbers —
# ADR-096 mandates this; line citations rot), in TWO schema families (feature/op-prefixed vs
# bare-stage) — that split is the whole reason the queries differ.
#   registry:"zot-gate-degraded"   ci-deploy.sh  `zot_gate_degraded_event`
#                                  jq tags: {feature, op, registry, zot_gate_reason}
#                                  The rolling deploy's zot gate degraded; with no GHCR leg left
#                                  the deploy then ends in image_pull_failed.
#   stage:"inngest_pull_fatal"     cloud-init-inngest.yml's host-local
#                                  `soleur-boot-emit inngest_pull_fatal fatal` (write_files)
#                                  tags: {stage, host_id, region, host_name, detail}; AND
#                                  cloud-init.yml's gated colocated block, calling the
#                                  `soleur-boot-emit` defined in soleur-host-bootstrap.sh
#                                  (same tag schema).
#                                  NOT a fallback (#8036 1d): an inngest fresh boot whose zot
#                                  pull failed. There is no second registry, so the boot ENDS —
#                                  this is a host that went dark, not one that was served
#                                  elsewhere. The alarm keeps its old name; read it as
#                                  "zot degraded OR an inngest boot died on the pull".
#
# RETIRED operands, listed so nobody re-adds them (each has no emit site left):
#   registry:"ghcr-fallback"       #8036 1c — ci-deploy.sh's GHCR leg deleted. Structurally dark
#                                  since #7071 (ADR-169 Named residual 3, #7295): the credential
#                                  it needed was revoked on 2026-07-29.
#   stage:"app_ghcr_fallback"      #8036 1d — the web seed block's GHCR login + pull arm deleted.
#   stage:"app_ghcr_served"        #8036 1d — same deletion; exactly one success arm (app_zot)
#                                  remains on a web fresh boot.
#   stage:"inngest_ghcr_fallback"  #8036 1d — RENAMED to inngest_pull_fatal and raised to fatal:
#                                  the GHCR pull after a zot miss is gone, so the old name
#                                  described a fallback that no longer exists. The new name
#                                  deliberately shares no prefix with inngest_zot (Better Stack
#                                  greps are substring matches).
#
# The DENOMINATOR (#6462), queried separately below rather than as a FAIL entry — it is the
# one signal here that is GOOD news, so it cannot live in a set whose sum means "bad":
#   stage:"app_zot"                cloud-init.yml `_emit ... "app_zot" info` — the only success
#                                  arm of a web fresh boot since #8036 1d, so a zero count proves
#                                  the fleet is UNOBSERVED rather than clean. `info` is countable:
#                                  the events endpoint returns it (bootstrap_complete is also info).
#
# ⚠ THE PREFIX ASYMMETRY IS DELIBERATE. Do NOT "normalize" the queries to a common prefix.
# ci-deploy.sh's jq payload carries feature+op, so the registry: queries are prefixed. NEITHER
# boot-path emitter (`soleur-boot-emit` nor `_emit`) writes feature or op — they are separate
# emitters that happen to share that gap — so the stage: queries MUST be bare. Sentry tag
# matching is EXACT: prefixing a stage: query makes it match zero events forever, silently
# restoring the blindness this gate exists to catch. Verify against BOTH boot emitters' tag
# schemas above before touching a query — one of them is not enough.
# Proven live on the bare-vs-prefixed question: stage:"bootstrap_complete" → 9 events; the
# same query prefixed with feature/op → 0. (Caveat, so the evidence is not over-read: that
# beacon comes from a FOURTH emitter, `_sentry_emit` in soleur-host-bootstrap.sh, which emits
# none of the watched signals. It shares soleur-boot-emit's {stage,host_id,region} shape, so it
# demonstrates the bare-vs-prefixed behaviour and covers [freshboot]'s schema; it does NOT
# independently cover `_emit`'s {stage,image_ref,host_id,detail,host_name}, which app_zot and
# the WEB_FATAL arm ride. Those are pinned by the op-contract test's tag-key legs instead — see
# that file.)
#
# ⚠ Do NOT read "9 events" as a statement about how RARE fresh boots are. Those 9 span
# 2026-07-07..07-13 and the emitter only shipped 2026-07-06 (560168055, #6092) — that is ~1.3
# boots/DAY, not 9 ever. It is a bare count over an unstated window, cited here ONLY as
# bare-vs-prefixed evidence. #6462's first draft misread it as scarcity and built a whole
# threshold argument on top; the number cannot carry that weight.
# The FAIL set (whole query strings, not just the tag values) is pinned against the alarm by
# apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts, so drift on
# either side fails CI rather than silently darkening this gate.
#
# ⚠ WHAT THIS GATE CANNOT SEE — it is NECESSARY BUT NOT SUFFICIENT to authorize 5.6 / #6129.
# The old "N of M ways the fleet can end up GHCR-served" ratio retired with those ways: after 1c
# and 1d no host code path can be GHCR-served. What remains is the set of ways zot can FAIL to
# serve. The list below is what is KNOWN, not what exists — the old count grew by DISCOVERY
# inside #6462 (nobody had looked at the dedicated inngest host), and that lesson still holds.
#
#   COVERED:
#     - [gate]      rolling deploy: the zot gate degraded (FAIL_QUERIES).
#     - [freshboot] inngest fresh boot, dedicated host or colocated block: the zot pull failed
#                   and the boot ended (FAIL_QUERIES).
#     - WEB_FATAL   web fresh boot: the seed block's zot login/pull failed and on_err sent
#                   `soleur-hostscript-seed failed` stage=pull at fatal. OUTSIDE FAIL_QUERIES on
#                   purpose: web_terminal_boot_fatal (stage=pull), not zot_mirror_fallback_rate,
#                   pages it, so adding it to the FAIL set without the rule breaks the alarm⇔soak
#                   parity contract, and adding it to both double-pages.
#   NOT COVERED 1/2 — Sentry-dark. ci-deploy.sh returns early when doppler, DOPPLER_TOKEN, or
#     ZOT_REGISTRY_URL is absent, BEFORE every zot_gate_degraded_event call site: the fleet
#     emits NOTHING to Sentry (journald only). Caught ONLY by the insufficient-sample arm
#     below — which is why that arm must keep exit 1. Tracked: #6437.
#   NOT COVERED 2/2 — a fresh boot that dies BEFORE its emitter can send (no egress, a death
#     before runcmd, a DSN fault). A counter of an event the host never sent reads 0. The
#     instruments for that are the denominators (APP_ZOT, INNGEST_ZOT: a success must have been
#     SEEN), the two blocker arms (#6500, #8651: a human verdict), and, on the inngest host, the
#     independently-credentialed Better Stack phone-home, where the emitter reports its own
#     non-delivery as sentry-emit-FAILED. Sentry events are forgeable with the public DSN, so a
#     Sentry count is evidence, not proof — the PASS line says to corroborate on Better Stack.
#   HISTORY (#6500, kept because it briefed the revoke): the dedicated inngest host WAS
#     GHCR-only and reported to Better Stack only, so every query here was blind to it. #7462
#     gave it a zot-primary arm, #6500 a host-local `soleur-boot-emit` (a host BUILT from the
#     template reports on the Sentry `stage:` schema with host_name:"soleur-inngest"), and
#     #8036 1d removed its GHCR arm: its boot now depends ENTIRELY on zot reachability plus a
#     baked pull credential. #6500 is CLOSED (COMPLETED); the blocker arm below still reads it,
#     AND the code, before any exit 0. Name-anchored: any :NNN here rots on its own fix.
#   - Consequence: a PASS here is evidence, not authorization. See ADR-096.
#
# THE WINDOW (#8036 1d). The backfilled window from the 2026-07-17 cutover could not pass: it
# holds SIX fallback events, each on a path fixed since. The operator re-armed the soak BECAUSE
# of that, at the merge of the last fix (#6122 comment 5811202876, 2026-09-24T09:07:09Z), with a
# 7-day minimum. The six events EXCLUDED by the re-armed START, each with the PR that fixed
# its path:
#   - zot-gate-degraded     x2  2026-07-17T19:52:12Z and 20:11:39Z — flip day, during the
#                               cutover itself (the first zot-served web pull is 19:51:49Z).
#   - app_ghcr_served       x3  last 2026-07-27 — web fresh boots served by GHCR. The
#                               probe-then-GHCR seed path was replaced by #8660 (zot by bake, no
#                               /v2/ probe), and #8036 1d deleted the GHCR arm itself.
#   - inngest_ghcr_fallback x1  2026-09-22T07:01:49Z — a dedicated inngest boot whose zot pull
#                               missed; the private-NIC boot race behind it was fixed by #8539.
#
# ENROLLED on #6122 (2026-09-24, #8036 item 1d). The tracker body carries the directive below
# and the `follow-through` label, so sweep-followthroughs.sh runs this script daily from
# `earliest` (START + 7 days). Until this enrolment no sweep had ever executed it; the file's
# exec bit is guarded for the whole probe class by scripts/followthrough-exec-bit.test.sh since
# #6435. ⚠ A PASS CLOSES #6122, the migration EPIC: 5.3b-iii, 5.4 and 5.6 must each keep their
# own open tracker, so the epic's close orphans none of them.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (zero watched events AND sufficient zot sample; sweeper closes the tracker)
#   1 = FAIL       (>=1 watched event OR insufficient zot sample OR an unmet blocker — leave
#                   open: a real event is a regression to investigate; an insufficient
#                   sample means keep soaking)
#   * = TRANSIENT  (Sentry/GitHub API unreachable / auth / parse failure; retry next sweep)
#
# Required env: SENTRY_ACTIONS_RO_TOKEN (wired in scheduled-followthrough-sweeper.yml as
#   secrets.SENTRY_ACTIONS_RO_TOKEN -- the org-level read-only `actions-read-prd` integration, ADR-031;
#   rotation: knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md),
#   and GH_TOKEN (the #8660 START anchor and the two blocker arms).
# Directive on the tracking issue body (#6122):
#   <!-- soleur:followthrough script=scripts/followthroughs/zot-soak-6122.sh earliest=2026-10-01T03:22:41Z secrets=SENTRY_ACTIONS_RO_TOKEN,GH_TOKEN -->

# REFUSE TO RUN UNDER XTRACE (#7797). Shell tracing echoes commands AFTER
# expansion, so a credential is printed the moment it is used. The test below
# covers EVERY credential this file references and uses `${VAR:+x}`, which is
# non-emptiness WITHOUT expanding the value -- `${VAR:-}` would print it here.
# Tracing stays available with the credentials unset, so this refuses a leak
# without blocking a debugging session.
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}${SENTRY_ACTIONS_RO_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (GH_TOKEN, SENTRY_ACTIONS_RO_TOKEN). Unset it to trace safely (see #7797).
' >&2
      exit 78
    fi
    ;;
esac
set -uo pipefail

# Fail-safe env check. Deliberately NOT `: "${VAR:?msg}"` — under a non-interactive shell
# that word-expansion aborts with status 1, which this contract reads as FAIL ("criteria not
# met") when the truth is "the probe could not run". An unprovisioned env must never be able
# to report a verdict on an irreversible retirement. See followthrough-convention.md.
if [[ -z "${SENTRY_ACTIONS_RO_TOKEN:-}" ]]; then
  echo "TRANSIENT: SENTRY_ACTIONS_RO_TOKEN is unset or empty — cannot query Sentry (declare it in the directive's secrets= clause)" >&2
  exit 2
fi

ORG="jikigai-eu"
API="https://sentry.io/api/0"
MIN_SAMPLE="${ZOT_SOAK_MIN_SAMPLE:-3}"   # min zot-served pulls per image to prove exercise
# Validate before use. `[[ -lt ]]` does ARITHMETIC evaluation, which coerces a non-numeric to
# 0 and evaluates a command substitution: MIN_SAMPLE=0, "", or "abc" all make the sample arm
# below pass vacuously and print PASS with zero evidence — silently disabling the ONLY detector
# for the Sentry-dark mode (#6437). `a[$(cmd)]` would also execute cmd with the Sentry token
# in-process. The sweeper's `env -i` cannot forward this var, but a MANUAL run — where it IS
# settable — is exactly where an operator reads a verdict before acting on it.
if [[ ! "$MIN_SAMPLE" =~ ^[1-9][0-9]*$ ]]; then
  echo "TRANSIENT: ZOT_SOAK_MIN_SAMPLE must be a positive integer (got '$MIN_SAMPLE') — refusing to report a verdict." >&2
  exit 2
fi

# Absolute window start: the operator's RE-ARM (#8036 1d), not the cutover. The first window
# ran from the 2026-07-17 cutover (2026-07-17T19:45:00, a few minutes before the first zot-served
# web pull at 19:51:49Z) and could not pass: it held six fallback events, each on a path fixed
# since (listed in the header). The operator re-armed the soak BECAUSE of that, at the merge of
# the last fix — PR #8660, mergedAt 2026-09-24T03:22:41Z — and recorded the literal on #6122
# (comment 5811202876). START is therefore not "chosen before measuring"; it is chosen as the
# merge of the last fix, and both records sit outside this file. zot-soak-6122.test.sh pins the
# default to exactly this literal in exactly one assignment (Guard 3). ZOT_SOAK_START overrides
# it for tests and manual runs only; the sweeper's `env -i` cannot forward it.
START="${ZOT_SOAK_START:-2026-09-24T03:22:41}"
END=$(date -u +%Y-%m-%dT%H:%M:%S)

# Own the malformed-START case rather than delegating it to Sentry's date parser. An override
# can be anything, and relying on Sentry to 400 a bad string is an unverified vendor behaviour
# this gate must not bet a verdict on.
# FULLY anchored (#6500 review): START is spliced into the query URL unencoded, so a
# prefix-only check admitted `2026-01-01T&start=<later>`, a second `start=` that silently moves
# the window.
if [[ ! "$START" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z?$ ]]; then
  echo "TRANSIENT: START is unpinned or malformed ($START) — pin ZOT_SOAK_START in this script to the re-arm UTC before this gate can report a verdict." >&2
  exit 2
fi

# ── The START anchor (#8036 1d, Guard 3's runtime half). The regex above proves START is a
# TIMESTAMP, not the RIGHT one, and a START pinned LATE is a false-PASS route: it drops bad
# events from the window while the remaining days still clear MIN_SAMPLE. The test suite pins
# the literal; this arm pins it against a record no commit can edit — #8660's mergedAt, the
# re-arm the literal cites.
#   - Unreadable (GitHub outage, no GH_TOKEN, an unmerged PR answering null) → TRANSIENT: the
#     probe could not measure, which is never "the measurement is false".
#   - START later than mergedAt → FAIL, not TRANSIENT. That is a measured defect in this file,
#     not a probe failure; TRANSIENT would retry it daily forever instead of saying so.
#   - START earlier than mergedAt is allowed: a wider window can only ADD events, i.e. fail
#     closed.
# DEFAULT ONLY. An explicit ZOT_SOAK_START is the documented test/manual seam (a later override
# is how an operator asks "what about since X?"), and the sweeper cannot set it — so the arm
# guards exactly the value the sweeper grades.
START_ANCHOR_PR=8660
if [[ -z "${ZOT_SOAK_START:-}" ]]; then
  anchor_json=$(gh pr view "$START_ANCHOR_PR" --repo github.com/jikig-ai/soleur --json mergedAt 2>/dev/null)
  anchor=$(printf '%s' "$anchor_json" | jq -r '.mergedAt // empty' 2>/dev/null)
  if [[ ! "$anchor" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    echo "TRANSIENT: cannot read #$START_ANCHOR_PR mergedAt (got '${anchor:-<empty>}') — the default START cannot be checked against the re-arm it cites; retry next sweep. Is GH_TOKEN declared in the directive's secrets= clause?" >&2
    exit 2
  fi
  # ISO-8601 at one precision orders lexically; both sides are compared without the Z.
  if [[ "${START%Z}" > "${anchor%Z}" ]]; then
    echo "FAIL(start-after-anchor): the default START ($START) is LATER than #$START_ANCHOR_PR mergedAt ($anchor), the re-arm it cites (#6122 comment 5811202876). A late START drops events from the window — restore the default to the recorded re-arm literal; do not move the record to match."
    exit 1
  fi
fi

# sentry_count <query> → echoes the event count for the window, or "TRANSIENT" on error.
sentry_count() {
  local q enc url resp status body n
  q="$1"
  enc=$(printf '%s' "$q" | jq -sRr @uri)
  url="${API}/organizations/${ORG}/events/?query=${enc}&start=${START}&end=${END}&per_page=100&field=title&field=timestamp"
  resp=$(curl --disable --noproxy '*' -sS -w '\nHTTP_STATUS:%{http_code}' \
    -H "Authorization: Bearer $SENTRY_ACTIONS_RO_TOKEN" -H "Accept: application/json" "$url" 2>/dev/null)
  status=$(printf '%s' "$resp" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
  body=$(printf '%s' "$resp" | sed '$d')
  if [[ "$status" != "200" ]]; then echo "TRANSIENT"; return; fi
  # Require .data to BE an array. The previous form took `length` with an alternative-operator
  # default of zero, which yields a plain 0 for an unexpected payload shape (an error object has
  # no .data → length of null → 0). That 0 is numeric, so it sailed through the guard below as a
  # COUNTED ZERO — a false-PASS route on the one gate protecting an irreversible action. (The
  # default was also dead code: `length` never returns null.) On a shape mismatch jq now errors →
  # empty → TRANSIENT.
  n=$(printf '%s' "$body" | jq -r 'if (.data | type) == "array" then (.data | length) else error("no data array") end' 2>/dev/null)
  [[ "$n" =~ ^[0-9]+$ ]] && echo "$n" || echo "TRANSIENT"
}

# --- (a) Events across BOTH watched signals. Zero required. ---
#
# Declared, guarded, and summed by ONE loop, so "declared but never counted" — the #6435
# defect — is structurally unrepresentable rather than policed by a reviewer's attention.
# ⚠ [freshboot] is a BARE stage: query. NEVER prefix it (see header).
# #8036 1c dropped `[rolling]` (registry:"ghcr-fallback") and moved the floor 5 -> 4; #8036 1d
# dropped `[appboot]`/`[appserved]` (app_ghcr_fallback/app_ghcr_served, no emit site left),
# renamed `[freshboot]` from inngest_ghcr_fallback to inngest_pull_fatal, and moved the floor
# 4 -> 2 — each IN THE SAME EDIT as its operand change. Dropping an operand without moving the
# floor is the exact defect the floor exists to catch — it makes every sweep a permanent
# `exit 2` TRANSIENT — and moving the floor without dropping the operand leaves the soak
# counting a signal nothing can emit.
declare -A FAIL_QUERIES=(
  [gate]='feature:supply-chain op:image-pull registry:"zot-gate-degraded"'
  [freshboot]='stage:"inngest_pull_fatal"'
)

# Runtime cardinality floor. The array above makes "declared but never counted" unrepresentable
# only in SOURCE; at RUNTIME an absent/emptied FAIL_QUERIES iterates zero times and yields
# FALLBACKS=0 -> PASS. `set -u` does NOT rescue this: expanding "${!FAIL_QUERIES[@]}" on an
# unset array exits 0 with zero iterations (verified, bash 5.3.9), and there is no `set -e` to
# abort a failed `declare`. Without this line the only thing between "the array is gone" and a
# PASS is a CI test that parses source text — but CI parses while the sweeper executes.
# Mirrors the same floor in scripts/followthrough-exec-bit.test.sh.
if (( ${#FAIL_QUERIES[@]} != 2 )); then
  echo "TRANSIENT: FAIL_QUERIES has ${#FAIL_QUERIES[@]} entries, expected 2 — refusing to report a verdict on a partial FAIL set." >&2
  exit 2
fi

declare -A COUNTS
FALLBACKS=0
# Sorted for deterministic output; the array above stays the single source of truth.
for k in $(printf '%s\n' "${!FAIL_QUERIES[@]}" | sort); do
  n=$(sentry_count "${FAIL_QUERIES[$k]}")
  if [[ ! "$n" =~ ^[0-9]+$ ]]; then
    echo "TRANSIENT: Sentry query '$k' failed (window $START..$END) — retry next sweep." >&2
    exit 2
  fi
  COUNTS[$k]=$n
  FALLBACKS=$(( FALLBACKS + n ))
done

# --- (a') The web fresh-boot fatal arm (#8036 1d). OUTSIDE FAIL_QUERIES, deliberately.
#
# A web fresh boot whose zot login or pull fails ends in the seed block's on_err, which sends
# `soleur-hostscript-seed failed` with stage=pull at level fatal (cloud-init.yml `_emit`). Since
# 1d there is no GHCR arm behind it, so this is the web twin of [freshboot]. It is NOT a
# FAIL_QUERIES member because the alarm⇔soak parity contract (the op-contract test) pins the
# FAIL set to the values zot_mirror_fallback_rate watches, and stage=pull is paged by
# web_terminal_boot_fatal instead: adding it here without the rule breaks parity, and adding it
# to both double-pages. #8651 closes 2026-09-25, before this soak's `earliest`, so this arm is
# the only web boot-path check the gate runs by query.
# `level:fatal` because stage=pull is also the STAGE of the whole seed span — only the on_err
# emit carries it at fatal. Bare like [freshboot]: `_emit` writes no feature/op.
# ⚠ Guard the string BEFORE any arithmetic (the TRANSIENT sentinel — see the APP_ZOT note below).
WEB_FATAL=$(sentry_count 'stage:"pull" level:fatal')
if [[ ! "$WEB_FATAL" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: Sentry query 'web-pull-fatal' failed (window $START..$END) — retry next sweep." >&2
  exit 2
fi

# --- (b) zot-served sample per image. >= MIN_SAMPLE required (proof of exercise). ---
ZOT_WEB=$(sentry_count 'feature:supply-chain op:image-pull registry:"zot" image:"web"')
ZOT_INNGEST=$(sentry_count 'feature:supply-chain op:image-pull registry:"zot" image:"inngest"')

for v in "$ZOT_WEB" "$ZOT_INNGEST"; do
  if [[ "$v" == "TRANSIENT" ]]; then
    echo "TRANSIENT: Sentry query failed (window $START..$END) — retry next sweep." >&2
    exit 2
  fi
done

if [[ "$FALLBACKS" -gt 0 ]]; then
  # Per-signal counts, not just the total: the remediation differs by signal.
  # gate-degraded = the rolling deploy's zot gate degraded, so zot was never ATTEMPTED on that
  #   deploy (chase the mirror/network path — #6416 / #6288). With no GHCR leg left, the deploy
  #   then ended in image_pull_failed (IMAGE_PULL journald breadcrumbs).
  # inngest-pull-fatal = an inngest fresh boot's zot pull failed and the boot ENDED. Read the
  #   event's detail (rc=<n>) and the host's Better Stack phone-home tail
  #   (scripts/betterstack-query.sh --grep inngest_pull_fatal) before re-replacing: runcmd is
  #   once-per-instance, so an unchanged re-replace repeats.
  # web-pull-fatal is printed alongside for the whole picture; its own FAIL is the next arm.
  echo "FAIL: $FALLBACKS watched event(s) since $START (gate-degraded=${COUNTS[gate]} inngest-pull-fatal=${COUNTS[freshboot]} web-pull-fatal=$WEB_FATAL) — zot did not serve. Investigate before 5.6 / #6129 (see the per-signal notes in zot-soak-6122.sh)."
  exit 1
fi
if (( WEB_FATAL > 0 )); then
  echo "FAIL(web-pull-fatal): $WEB_FATAL web fresh-boot fatal(s) at stage=pull since $START (gate-degraded=${COUNTS[gate]} inngest-pull-fatal=${COUNTS[freshboot]} web-pull-fatal=$WEB_FATAL) — a web host's seed-block zot login/pull failed and its boot ended. Read the Sentry event's detail (nic=… zot=[login,n,cause] pull_err: …), map cause= to the pull row of runbooks/fresh-host-bootstrap-recovery.md, fix forward, then re-run web-host-replace — runcmd is once-per-instance, so an unchanged re-replace repeats."
  exit 1
fi

# ── The DENOMINATOR (#6462). Everything above counts BAD events; nothing above proves the
# fleet was OBSERVED at all. Reaching this line means FALLBACKS == 0, which on its own is
# indistinguishable from "no fresh boot happened" / "the beacon is dark" / "cloud-init never
# reached the fleet". app_zot is the positive evidence: it fires on every zot-served fresh
# boot, so count(app_zot) == 0 here means the fleet is UNOBSERVED, not clean.
#
# ⚠ Guard the string BEFORE any arithmetic. `sentry_count` (defined above) echoes the bare
# word TRANSIENT on a non-200 and on a jq shape mismatch; an arithmetic zero-test on that word
# errors under `set -u` — and absent `set -u` would read it as 0, i.e. "no evidence" → a FAIL
# that is really a probe failure. The regex guard is what keeps the sentinel alive (the same
# hazard the MIN_SAMPLE comment documents).
#
# Name-anchored, NOT `:NNN` — this file's own header says line citations rot, and an earlier
# draft of THIS comment proved it: it cited :151/:159, which its own PR then shifted 35 lines
# onto a DECOY (the MIN_SAMPLE regex guard, which also echoes TRANSIENT and so falsely
# confirms). Cite names; they are grep-able and they do not move.
# (Deliberately does not quote the zero-test literal: AC7b greps for it and a comment copy
# would make the count 2 — the same false-match class the FAIL_QUERIES/body-grep notes warn of.)
APP_ZOT=$(sentry_count 'stage:"app_zot"')
if [[ ! "$APP_ZOT" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: Sentry query 'app_zot' failed (window $START..$END) — retry next sweep." >&2
  exit 2
fi
# ⚠ HARDCODED == 0 — do NOT reuse MIN_SAMPLE and do NOT add a knob.
#   MIN_SAMPLE counts zot-served PULLS PER IMAGE (rolling deploys); this counts fresh HOST
#   BOOTS. Different quantities — reusing one threshold across both is a category error.
#   And a knob's only useful value here is 1: 0 disarms the floor, >1 buys no extra evidence
#   for the narrow thing this arm proves (the beacon emits and the flip was exercised on the
#   boot path — one boot proves both; proving the flip AT VOLUME is the sample arm's job).
#   A MANUAL run, where env vars ARE settable (see the MIN_SAMPLE note above), is where an
#   operator reads a verdict before acting on it — so a knob here would be a bypass surface on
#   the gate. A hardcoded floor has no such surface.
if (( APP_ZOT == 0 )); then
  echo "FAIL(no-freshboot-evidence): 0 fallbacks, but NO zot-served fresh boot since $START. The fleet is UNOBSERVED, not clean — 'no bad events' here cannot be distinguished from 'nothing was reported'. Most likely cause: this cloud-init predates START (it is ignore_changes-pinned on running hosts, so only a fresh rebuild carries the beacon) — merge, then recreate a web host inside the window."
  exit 1
fi

# ── The DEDICATED-HOST denominator (#6500). app_zot above is the WEB host's evidence; nothing
# above proves the dedicated soleur-inngest host was observed. Same shape, same reasons: guard
# the string before any arithmetic, hardcoded floor, no knob.
# ⚠ HOST-PINNED, while `[freshboot]` stays bare. The colocated inngest block in cloud-init.yml is
# gated by web_colocate_inngest, not deleted: a web host born with it on would emit inngest_zot
# and satisfy a bare denominator while the dedicated host never reported — a false PASS on the
# gate that authorizes the revoke. A filter on a DENOMINATOR can only fail closed (a wrong value
# reads 0 and FAILs); the FAIL queries stay bare because a bare FAIL query can only add failures.
INNGEST_ZOT=$(sentry_count 'stage:"inngest_zot" host_name:"soleur-inngest"')
if [[ ! "$INNGEST_ZOT" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: Sentry query 'inngest_zot host_name:soleur-inngest' failed (window $START..$END) — retry next sweep." >&2
  exit 2
fi
if (( INNGEST_ZOT == 0 )); then
  echo "FAIL(no-inngest-freshboot-evidence): 0 fallbacks, but NO zot-served fresh boot of the dedicated soleur-inngest host since $START. That host is UNOBSERVED, not clean. If NO replace has run in the window: dispatch apply-web-platform-infra.yml with apply_target=inngest-host-replace (the host must be BUILT from the #6500 template), in an ADR-100 maintenance window. If a replace DID run, do not replace again yet — read the host's Better Stack channel first: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since '<window start>' --grep 'stage=inngest_zot' --grep sentry-emit-FAILED --grep SOLEUR_INNGEST_BOOT_TRACE_LOST. inngest_zot present plus sentry-emit-FAILED (or TRACE_LOST) is a DELIVERY fault (DSN or egress), not a missing boot."
  exit 1
fi

# ⚠ This arm MUST keep `exit 1` (FAIL). Do NOT "fix" it to exit 2 (TRANSIENT) on the
# reasoning that a thin sample just means "not enough deploys yet" — that is not the only
# route here. In the Sentry-dark mode (#6437) ci-deploy.sh returns before every
# zot_gate_degraded_event call site, so the fleet emits NOTHING: FALLBACKS=0 with no degrade
# event, and this sample arm is the ONLY detector. TRANSIENT would make a silently
# unconfigured fleet report "retry next sweep" forever instead of blocking the retirement.
# The sample arm is a floor on GOOD evidence, not a ceiling on BAD — except here, where it is
# the only ceiling.
if [[ "$ZOT_WEB" -lt "$MIN_SAMPLE" || "$ZOT_INNGEST" -lt "$MIN_SAMPLE" ]]; then
  echo "FAIL(insufficient-sample): zot-served pulls web=$ZOT_WEB inngest=$ZOT_INNGEST (need >=$MIN_SAMPLE each) — zero fallbacks so far, but keep soaking until each image has been served by zot enough times to be conclusive."
  exit 1
fi

# ── The BLOCKER arm (#6462 C1).
#
# ⚠ READ WITH the header's "a PASS here is evidence, not authorization". Both are true and they
# do NOT contradict: this gate is a NECESSARY condition, never a sufficient one. A human still
# adjudicates 5.6 / #6129 against the header's COVERED / NOT COVERED list. What this arm adds
# is a FLOOR under that decision — exit 0 is a precondition the adjudicator needs, so a gate
# that returns 0 while a KNOWN-FATAL path is open hands them a green light it has not earned.
# The exit code can VETO a retirement; it cannot bless one. A gate is not made trustworthy by
# carrying a comment about the fatal path it ignores — #6462's thesis is that prose is not a
# fix — so the veto lives in the exit code.
#
# (Historical: this arm was written to gate 5.3's GHCR PAT rotate+revoke. That PAT has been
# revoked since 2026-07-29 and #8036 1d removed the last host-side GHCR arm, so what the arm now
# protects is 5.6 / #6129 — and a host that cannot pull zot cannot boot at all.)
#
# #6500: the dedicated inngest host. WAS (until #7462/#7516): a hard-pinned ghcr.io ref with no
# zot path, reporting only to Better Stack, so every query in this file was blind to it. NOW:
# the template pulls zot-primary and (#6500) reports on the Sentry `stage:` schema — but only a
# host BUILT from it does, and closing #6500 is still the human authorization that the live host
# was replaced and observed. It is a LIVE host (hcloud_server.inngest is unconditional); if it
# cannot pull zot it cannot boot (no second registry), while this soak could report PASS.
#
# ⚠ This reads issue STATE, not fixedness. Closing #6500 IS the authorization act — see the
# pinned warning on the issue. Do not close it to make this gate pass, and do not delete this
# arm to make this gate pass; the arm existing is the point.
BLOCKER=6500
# ⚠ --repo is NOT optional. sweep-followthroughs.sh runs this under `env -i` forwarding ONLY
# the directive's secrets= names, so the workflow's GH_REPO is STRIPPED and `gh` falls back to
# resolving the repo from the CWD's git remote. Under the sweeper that resolves correctly —
# but a MANUAL run comes from an uncontrolled CWD, and that is where an operator reads a verdict
# before acting on it. A run from another checkout would read a DIFFERENT repo's #6500, and the
# OPEN/CLOSED allowlist below cannot catch that: a wrong-repo CLOSED is a well-formed answer to
# the wrong question, and it would authorize 5.6. Pinning the repo makes the arm's correctness a stated fact
# rather than a CWD invariant.
# --repo carries the HOST too: GH_HOST is a second unpinned resolver, so `jikig-ai/soleur`
# alone still leaves the enterprise/host axis ambient. `--json state,stateReason` because
# CLOSED alone is not consent — see the stateReason gate below.
st_json=$(gh issue view "$BLOCKER" --repo github.com/jikig-ai/soleur --json state,stateReason 2>/dev/null)
st=$(printf '%s' "$st_json" | jq -r '.state // empty' 2>/dev/null)
st_reason=$(printf '%s' "$st_json" | jq -r '.stateReason // empty' 2>/dev/null)
# ⚠ Fail SAFE on an unreadable state. A gate must never read "I could not measure" as "the
# measurement is false" — treating an unknown state as CLOSED would PASS the gate during a
# GitHub outage while the 7th path is still live. TRANSIENT is correct here (the probe could
# not run); it is NOT correct for the OPEN branch below, where the probe ran fine.
if [[ "$st" != "OPEN" && "$st" != "CLOSED" ]]; then
  echo "TRANSIENT: cannot read #$BLOCKER state (got '${st:-<empty>}') — retry next sweep. Is GH_TOKEN declared in the directive's secrets= clause?" >&2
  exit 2
fi
if [[ "$st" == "OPEN" ]]; then
  echo "FAIL(blocked): soak criteria hold (0 fallbacks, zot served web=$ZOT_WEB inngest=$ZOT_INNGEST, $APP_ZOT zot-served fresh boot(s), $INNGEST_ZOT dedicated-inngest zot-served fresh boot(s)), but #$BLOCKER is OPEN — the operator has not yet authorized that the dedicated inngest host pulls zot-primary and reports on the Sentry stage: schema (RESULT: PASS on #$BLOCKER, then close it as completed). NOT authorized to proceed to 5.6 / #6129."
  exit 1
fi

# ⚠ CLOSED is not the same as FIXED — corroborate it against the code.
#
# The arm above reads issue STATE, so a careless close (closed-as-not-planned, backlog tidying,
# a partial fix) would flip the gate toward exit 0 and authorize the revoke. An earlier draft
# accepted that residual with prose, arguing a repo-local grep could only test the first half of
# #6500's two-part close condition (zot-primary pull AND Sentry `stage:` reporting).
#
# That argument was FALSE, and #6500's own body refutes it: its evidence is the sweep
# `zot|ZURL|ZIREF|/v2/|soleur-boot-emit` → 0 hits — and `soleur-boot-emit` IS the second half.
# Both halves are greppable.
#
# So AND the two rather than replacing either: they fail in OPPOSITE directions. Issue-state
# fails on a careless close but sees the world (e.g. whether the zot mirror is actually
# populated — #6500's own "Caveat on the zot mirror"); the grep fails when the code looks right
# but the mirror is empty, and cannot be closed by accident. Neither subsumes the other.
# ⚠ CLOSED IS NOT CONSENT. GitHub returns CLOSED for EVERY closure reason, so a
# `not planned` / `duplicate` / stale-triage close reads identically to a deliberate "the
# inngest host now pulls zot". That matters concretely: soleur:ticket-triage and
# drain-labeled-backlog operate autonomously over this backlog, so an automated tidy-up is a
# realistic path to authorizing an irreversible PAT revoke. Require an affirmative COMPLETED.
if [[ "$st" == "CLOSED" && "$st_reason" != "COMPLETED" ]]; then
  echo "FAIL(blocker-closed-not-completed): #$BLOCKER is CLOSED with stateReason='${st_reason:-<empty>}', not COMPLETED — a not-planned/duplicate/triage close is not evidence the dedicated inngest host was fixed. Re-open it, or close it as completed only once the host pulls zot-primary AND reports on the Sentry stage: schema."
  exit 1
fi

INNGEST_CI="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/apps/web-platform/infra/cloud-init-inngest.yml"
if [[ ! -f "$INNGEST_CI" ]]; then
  echo "TRANSIENT: cannot read $INNGEST_CI to corroborate #$BLOCKER's closure — refusing to authorize on issue state alone." >&2
  exit 2
fi
# (a) a zot pull path exists at all, and (b) it reports on the Sentry `stage:` schema the
# queries above depend on. Same terms as #6500's filed evidence, so the gate and the issue
# cannot drift apart on what "fixed" means.
# ⚠ ANCHOR ON SYNTAX, NEVER THE BARE WORD. A body-grep sees COMMENTS too, so #6500's filed
# evidence terms (`zot|ZURL|ZIREF|/v2/` + `soleur-boot-emit`) are the right SEMANTICS but the
# wrong PREDICATE for a gate: an earlier draft used them bare, and two comment lines —
# "# TODO: add zot support" and "# soleur-boot-emit would report this" — satisfied BOTH on a
# file that was still GHCR-only. The guard added to close the careless-close bypass was itself
# bypassable by prose (verified, not theorised). A comment line begins with `#`, so it can never
# produce `^\s*IREF=` or `^\s*soleur-boot-emit `. Narrowing is not anchoring.
# ⚠ TWO EMITTER SHAPES, NOT ONE (#7462). The anchors above were written when the only imagined
# fix was "make cloud-init-inngest.yml look like cloud-init.yml". #7462 implemented the zot arm
# with a DIFFERENT and deliberate shape — `ZIREF="$ZOT_EP/…"` + `IREF="$ZIREF"`, reporting via
# `inngest-boot-phone-home.sh` — because at #7462 this host had no `soleur-boot-emit` (#6500
# later added a host-local one) and reads its endpoint from a baked file rather than
# `$ZURL` from Doppler. Measured against that implementation, BOTH original anchors return ZERO
# hits. Left as-is, this arm would have gone from "correctly blocks" to "can never agree": once
# #6500 is legitimately closed the gate would emit `blocker-closed-but-condition-unmet` forever,
# on a factually false premise, and the realistic end state is someone deleting a safety gate.
#
# So accept either host's shape. The SEMANTICS are unchanged — a zot pull path must exist in
# code, and it must report off-box — and the syntax-anchoring rule above is preserved: every
# alternative is `^\s*`-anchored, so a comment line can satisfy none of them.
_zot_path_in_code() {
  grep -qE '^[[:space:]]*IREF=.*\$ZURL' "$1" || grep -qE '^[[:space:]]*ZIREF="\$ZOT_EP/' "$1"
}
_zot_reports_offbox() {
  grep -qE '^[[:space:]]*soleur-boot-emit ' "$1" \
    || grep -qE '^[[:space:]]*/usr/local/bin/inngest-boot-phone-home\.sh inngest_zot ' "$1"
}
# #6500 close condition 2, in the same syntax-anchored form: BOTH outcome arms call the host's
# soleur-boot-emit. Kept alongside the INNGEST_ZOT denominator above because they see different
# things: the denominator proves a report happened in the window, and cannot see a later revert
# of the call sites; this predicate reads the code as it is now.
# #8036 1d: the miss arm's stage is `inngest_pull_fatal` (renamed from inngest_ghcr_fallback,
# raised to fatal); a template still on the old name does NOT satisfy this.
_zot_reports_sentry_stage() {
  grep -qE '^[[:space:]]*soleur-boot-emit inngest_zot ' "$1" \
    && grep -qE '^[[:space:]]*soleur-boot-emit inngest_pull_fatal ' "$1" \
    && grep -qE '^  - path: /usr/local/bin/soleur-boot-emit$' "$1"
}
if ! _zot_path_in_code "$INNGEST_CI" || ! _zot_reports_offbox "$INNGEST_CI" || ! _zot_reports_sentry_stage "$INNGEST_CI"; then
  echo "FAIL(blocker-closed-but-condition-unmet): #$BLOCKER is CLOSED, but $INNGEST_CI still shows no zot pull path, no off-box reporting of it, or no Sentry 'stage:' emit (both outcome arms calling soleur-boot-emit, and the write_files entry that delivers it) — the dedicated host's zot path is not in the CODE. Closing the issue does not fix the host. Re-open #$BLOCKER or fix the host before 5.6."
  exit 1
fi
# The channel reaches this query set once the host is built from the #6500 template: it emits
# inngest_zot / inngest_pull_fatal on the Sentry `stage:` schema, and INNGEST_ZOT above
# requires one of its own zot-served boots in the window. The Sentry event is forgeable with the
# public DSN — as is every Sentry signal this gate reads — so whoever acts on a PASS (5.6 /
# #6129) still corroborates it on the independently-credentialed channel, and the PASS line
# says so:
#   doppler run -p soleur -c prd_terraform -- \
#     scripts/betterstack-query.sh --since <window> --grep inngest_pull_fatal --grep inngest_zot

# ── The WEB-HOST blocker arm (#8651).
#
# WHY A SECOND BLOCKER. The arm above proves the DEDICATED INNGEST host survives a dead GHCR.
# It proves nothing about the WEB hosts, and on 2026-09-23 a `web-host-replace` of web-2 booted
# DARK: cloud-init's 3-second `/v2/` probe lost, REF stayed the GHCR ref, and the pull 401'd on
# the already-revoked PAT (run 35912244388; `soleur-hostscript-seed failed` stage=pull,
# `ghcr_login_fail: … denied` + `pull_err: … unauthorized`). `web-1` is the PRE-EXISTING sole
# live web host, so the same replace strands the web tier. 5.6 must not be authorized while a
# fresh web boot is dark.
#
# WHY THIS IS NOT ANOTHER FAIL_QUERIES ENTRY — and the reason is structural, not stylistic.
# A dark host DIES at stage=pull, before reaching anything that emits the stage a counter would
# read. A counter of a stage the corpse cannot emit is vacuous by construction. This is the same
# blindness #6500 recorded for the inngest host ("the host emits its boot trace only if it gets
# far enough to run the emitter") and is exactly why the existing `app_ghcr_served` query does
# NOT cover this case: #6462 added it for a probe-miss whose pull then SUCCEEDS ("the ref stays
# the GHCR ref, the pull succeeds first try"). A pull that FAILS is silent.
# APP_ZOT does not rescue it either — it is a floor on SUCCESSES (>=1 zot-served fresh boot), so
# a single historical success satisfies it while the CURRENT fresh-boot path is broken. "At
# least one boot worked once" and "a boot works now" are different claims; only the first is
# measured here.
# CORRECTED (#8036 1d): "a pull that FAILS is silent" was true of the GHCR-SERVED stages above,
# not of the boot. The seed block's on_err DOES send `soleur-hostscript-seed failed` stage=pull
# at fatal — the #8651 dark boot is exactly such an event (WEB-PLATFORM-4T,
# 2026-09-23T20:10:21Z) — and the WEB_FATAL arm now counts it. What a counter still cannot see
# is a boot that dies before on_err can send (no egress, a DSN fault), which is why this human
# verdict stays alongside it.
#
# So this arm gates on a HUMAN verdict, exactly as the #6500 arm does, and for the same reason:
# the evidence reachable by query is structurally incomplete, so issue state is the honest
# instrument. It fails in the opposite direction to the counters (it cannot be satisfied by a
# stale success, and it can be satisfied by a careless close — hence the COMPLETED gate below).
# ⚠ Do not delete this arm to make the gate pass, and do not close #8651 to bypass it.
WEB_BLOCKER=8651
web_st_json=$(gh issue view "$WEB_BLOCKER" --repo github.com/jikig-ai/soleur --json state,stateReason 2>/dev/null)
web_st=$(printf '%s' "$web_st_json" | jq -r '.state // empty' 2>/dev/null)
web_st_reason=$(printf '%s' "$web_st_json" | jq -r '.stateReason // empty' 2>/dev/null)
# Fail SAFE on an unreadable state, same rule as the #6500 arm: "could not measure" is never
# "the measurement is false".
if [[ "$web_st" != "OPEN" && "$web_st" != "CLOSED" ]]; then
  echo "TRANSIENT: cannot read #$WEB_BLOCKER state (got '${web_st:-<empty>}') — retry next sweep. Is GH_TOKEN declared in the directive's secrets= clause?" >&2
  exit 2
fi
if [[ "$web_st" == "OPEN" ]]; then
  echo "FAIL(blocked-web): soak criteria hold and #$BLOCKER is settled, but #$WEB_BLOCKER is OPEN — a fresh web-host boot was measured DARK (zot probe lost, GHCR ref retained, 401 on the revoked PAT). web-1 is the sole live web host and a replace of it strands the web tier. NOT authorized to proceed to 5.6 / #6129."
  exit 1
fi
# CLOSED is not consent — same reasoning as the #6500 arm: GitHub returns CLOSED for every
# closure reason, and autonomous triage operates over this backlog.
if [[ "$web_st" == "CLOSED" && "$web_st_reason" != "COMPLETED" ]]; then
  echo "FAIL(web-blocker-closed-not-completed): #$WEB_BLOCKER is CLOSED with stateReason='${web_st_reason:-<empty>}', not COMPLETED — a not-planned/duplicate/triage close is not evidence a fresh web boot reaches zot. Re-open it, or close it as completed only once a web-host replace has been OBSERVED booting zot-served."
  exit 1
fi

echo "PASS: 0 watched events (gate-degraded=${COUNTS[gate]} inngest-pull-fatal=${COUNTS[freshboot]} web-pull-fatal=$WEB_FATAL), zot served web=$ZOT_WEB inngest=$ZOT_INNGEST (>=$MIN_SAMPLE each), $APP_ZOT zot-served fresh boot(s), $INNGEST_ZOT dedicated-inngest zot-served fresh boot(s), and #$BLOCKER + #$WEB_BLOCKER are both CLOSED as COMPLETED — since $START. The zot-only soak holds on Sentry evidence, which is forgeable with the public DSN: before acting on it, corroborate the dedicated host's inngest_zot on Better Stack (scripts/betterstack-query.sh --grep 'stage=inngest_zot'). Then this authorizes ADR-096 5.6 (adopting -> accepted) once 5.3b-iii and 5.4 are also done, and #6129 (WARN -> ENFORCE). It does NOT gate CI's GHCR push/read (DECISION: B3)."
exit 0
