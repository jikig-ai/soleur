#!/usr/bin/env bash
# Follow-through soak gate for #6122 Phase 5 (registry migration GHCR → self-hosted zot).
#
# After the operator provisions (1.8) + backfills (1.9) zot and the pull-site flip goes
# live, the fleet must run zot-primary for a soak window with ZERO GHCR fallbacks before
# GHCR push/egress can be retired (tasks 5.3-5.5) and ADR-096 flips adopting → accepted
# (5.6). This script is that gate. It PASSES (closes the tracker) only when, over the
# window from just-after cutover to now, Sentry shows:
#   (a) ZERO fallback events across ALL FIVE signals the companion alarm
#       (sentry_issue_alert.zot_mirror_fallback_rate) watches — see FAIL_QUERIES below;
#   (b) a MIN_SAMPLE of zot-served pulls PER image (registry:"zot" image:"web" /
#       image:"inngest") — so a vacuous "zero fallbacks because nothing deployed" cannot
#       close the tracker. Proof the flip was actually exercised.
#
# The five watched signals and their emitters (anchored on EMIT NAMES, not line numbers —
# ADR-096 mandates this; line citations rot). FOUR emit functions across three files, in TWO
# schema families (feature/op-prefixed vs bare-stage) — that split is the whole reason the
# queries differ:
#   registry:"ghcr-fallback"       ci-deploy.sh  `registry_pull_event ghcr-fallback`
#                                  jq tags: {feature, op, registry, image}
#   registry:"zot-gate-degraded"   ci-deploy.sh  `zot_gate_degraded_event`
#                                  jq tags: {feature, op, registry, zot_gate_reason}
#   stage:"inngest_ghcr_fallback"  cloud-init.yml calls `soleur-boot-emit inngest_ghcr_fallback`
#                                  (defined in soleur-host-bootstrap.sh) tags: {stage, host_id, region}
#   stage:"app_ghcr_fallback"      cloud-init.yml `_emit ... "app_ghcr_fallback" warning`
#                                  tags: {stage, image_ref, host_id, detail}
#   stage:"app_ghcr_served"        cloud-init.yml `_emit ... "app_ghcr_served" warning` (#6462)
#                                  tags: {stage, image_ref, host_id, detail} — same _emit, so
#                                  BARE like [appboot]. Fires on EVERY GHCR-served fresh boot,
#                                  including the probe-miss branch where the pull succeeds
#                                  first try and app_ghcr_fallback stays silent.
#
# The DENOMINATOR (#6462), queried separately below rather than as a FAIL entry — it is the
# one signal here that is GOOD news, so it cannot live in a set whose sum means "bad":
#   stage:"app_zot"                cloud-init.yml `_emit ... "app_zot" info` — the zot-served
#                                  counterpart. Exactly one of app_zot / app_ghcr_served fires
#                                  per successful fresh boot, so a zero count proves the fleet
#                                  is UNOBSERVED rather than clean. `info` is countable: the
#                                  events endpoint returns it (bootstrap_complete is also info).
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
# none of the five watched signals. It shares soleur-boot-emit's {stage,host_id,region} shape,
# so it demonstrates the bare-vs-prefixed behaviour and covers [freshboot]'s schema; it does
# NOT independently cover `_emit`'s {stage,image_ref,host_id,detail}, which [appboot] and
# [appserved] ride. Both are pinned by the op-contract test's tag-key legs instead — see
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
# ⚠ WHAT THIS GATE CANNOT SEE — it is NECESSARY BUT NOT SUFFICIENT to authorize 5.3-5.5.
# There are SEVEN KNOWN ways the fleet can end up GHCR-served; this gate's FAIL set covers FIVE.
# ⚠ KNOWN, not total: the count went 6 → 7 by DISCOVERY inside #6462 (nobody had looked at the
# dedicated inngest host). That is direct evidence the enumeration is not closed. Treat 7 as a
# lower bound and the ratio as "what we can currently see", never "what exists".
#
# ⚠ READ THE RATIO, NOT THE DELTA: #6462 closed one gap (fresh-boot probe-miss) and SURFACED
# a new one (the dedicated inngest host), so coverage went 4-of-6 → 5-of-7. The numerator AND
# the denominator both went up: the count of KNOWN-UNCOVERED paths is unchanged at 2. This is
# stated as a ratio, not flipped to "COVERED", precisely so a reader sees that rather than
# inferring completeness from "+1 signal". ADR-096 has already had to publicly correct one
# over-claim; do not author a second.
#
#   COVERED (the five FAIL_QUERIES below): rolling-deploy pull fallback; gate-degraded;
#     inngest fresh-boot fallback; app fresh-boot fallback (post-probe-hit branch);
#     app fresh-boot GHCR-served (#6462 — covers the probe-miss branch AND post-flip).
#   NOT COVERED 1/2 — Sentry-dark. ci-deploy.sh returns early when doppler, DOPPLER_TOKEN, or
#     ZOT_REGISTRY_URL is absent, BEFORE every zot_gate_degraded_event call site: the fleet
#     emits NOTHING to Sentry (journald only). Caught ONLY by the insufficient-sample arm
#     below — which is why that arm must keep exit 1. Tracked: #6437.
#   NOT COVERED 2/2 — the DEDICATED INNGEST HOST (the 7th path, surfaced by #6462). It is a
#     LIVE host (hcloud_server.inngest is unconditional — inngest-host.tf:181) whose
#     cloud-init-inngest.yml:337 hard-pins a ghcr.io ref with NO zot path, NO /v2/ probe and
#     NO fallback, and whose pull is FAIL-CLOSED (:349). It reports via
#     inngest-boot-phone-home.sh to Better Stack, NOT the Sentry `stage:` schema — so every
#     query in this file is structurally blind to it, and it could not emit
#     inngest_ghcr_fallback even if it were wired to Sentry (it never attempts zot).
#     Consequence: 5.3 revokes the PAT ⇒ its next fresh boot 401s ⇒ the host never comes up.
#     Tracked: #6500 — and MACHINE-ENFORCED by the blocker arm at the bottom of this file,
#     which refuses exit 0 while #6500 is OPEN. That arm is why this residual cannot silently
#     authorize a retirement. Do not delete it; do not close #6500 to bypass it.
#   RESOLVED by #6462 (was NOT COVERED 2/2): fresh-boot (web) probe-miss — if cloud-init's
#     /v2/ probe MISSES, the ref stays the GHCR ref, the pull succeeds first try, and the
#     app_ghcr_fallback guard (N>=2 && REF != IMAGE_REF) never fires. Now emitted
#     unconditionally as app_ghcr_served, and app_zot supplies the missing DENOMINATOR: "0
#     fallbacks" is no longer indistinguishable from "no fresh boot happened".
#   - Consequence: a PASS here is evidence, not authorization. See ADR-096.
#
# ⚠ NOT YET ENROLLED — no query in this file has ever executed, and THIS PR DOES NOT CHANGE THAT.
# Two independent reasons, in the order they bite:
#   1. UNREACHABLE (the operative one). sweep-followthroughs.sh enumerates
#      `gh issue list --label follow-through --state open` and reads a `soleur:followthrough`
#      directive from each body. #6122 carries neither the label nor a directive, and no issue
#      in the repo references this script — so the sweeper never calls run_one for it at all.
#   2. NON-EXECUTABLE (latent, fixed by #6435). The file was committed mode 100644. Had it ever
#      been enrolled, sweep-followthroughs.sh would have rejected it at its `[[ ! -x "$script" ]]`
#      guard BEFORE the `env -i` exec, via fail() — which is `printf ... >&2` and nothing else —
#      then `return 0`: no run, no exit code, no comment on the tracker, no TRANSIENT bucket.
#      scripts/followthrough-exec-bit.test.sh now guards that for the whole probe class.
#
# Enrollment is deliberately deferred, NOT an oversight: the cutover has not happened
# (registry:"zot" = 0 events over 30d — zot has never served a pull), and START below is still
# the unpinned placeholder. Enrolling now would make the daily sweeper post a TRANSIENT comment
# to the tracker every day forever without ever converging. Enrollment = add the `follow-through`
# label + the directive at the bottom of this header to the tracker, AND pin START, at cutover.
# #6122 owns the cutover UTC and the enrollment decision.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (zero fallbacks AND sufficient zot sample; sweeper closes the tracker)
#   1 = FAIL       (>=1 fallback on any watched signal OR insufficient zot sample — leave
#                   open: a real fallback is a regression to investigate; an insufficient
#                   sample means keep soaking, do NOT retire GHCR yet)
#   * = TRANSIENT  (Sentry API unreachable / auth / parse failure; retry next sweep)
#
# Required env: SENTRY_AUTH_TOKEN (wire as secrets.SENTRY_IAC_AUTH_TOKEN in the sweeper).
# Directive for the tracking issue body (pin START to the cutover UTC, earliest to >=7d):
#   <!-- soleur:followthrough script=scripts/followthroughs/zot-soak-6122.sh earliest=<UTC+7d> secrets=SENTRY_AUTH_TOKEN,GH_TOKEN -->

set -uo pipefail

# Fail-safe env check. Deliberately NOT `: "${VAR:?msg}"` — under a non-interactive shell
# that word-expansion aborts with status 1, which this contract reads as FAIL ("criteria not
# met") when the truth is "the probe could not run". An unprovisioned env must never be able
# to report a verdict on an irreversible retirement. See followthrough-convention.md.
if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
  echo "TRANSIENT: SENTRY_AUTH_TOKEN is unset or empty — cannot query Sentry (declare it in the directive's secrets= clause)" >&2
  exit 2
fi

ORG="jikigai-eu"
API="https://sentry.io/api/0"
MIN_SAMPLE="${ZOT_SOAK_MIN_SAMPLE:-3}"   # min zot-served pulls per image to prove exercise
# Validate before use. `[[ -lt ]]` does ARITHMETIC evaluation, which coerces a non-numeric to
# 0 and evaluates a command substitution: MIN_SAMPLE=0, "", or "abc" all make the sample arm
# below pass vacuously and print "Safe to retire GHCR" with zero evidence — silently disabling
# the ONLY detector for the Sentry-dark mode (#6437). `a[$(cmd)]` would also execute cmd with
# the Sentry token in-process. The sweeper's `env -i` cannot forward this var, but the header
# says enrollment is deferred, so every near-term run is a manual one where it IS settable —
# exactly when the retirement decision gets made.
if [[ ! "$MIN_SAMPLE" =~ ^[1-9][0-9]*$ ]]; then
  echo "TRANSIENT: ZOT_SOAK_MIN_SAMPLE must be a positive integer (got '$MIN_SAMPLE') — refusing to report a verdict." >&2
  exit 2
fi

# Absolute window start — PIN THIS to just after the cutover flip (the same UTC the
# operator records in the revert runbook). Placeholder until pinned; the earliest= gate in
# the issue directive still defers the first real check to >=7 days after cutover.
START="${ZOT_SOAK_START:-<POST_CUTOVER_UTC>}"
END=$(date -u +%Y-%m-%dT%H:%M:%S)

# Own the unpinned-START case rather than delegating it to Sentry's date parser. Until START
# is pinned it holds the literal placeholder above; today's fail-safety rests on Sentry 400ing
# that string — an unverified vendor behaviour this gate must not bet an irreversible
# retirement on.
#
# NOTE: this proves START is a TIMESTAMP, not that it is the RIGHT one. Nothing here asserts
# START <= cutover_utc, and a START pinned LATE is a false-PASS route: it excludes flip-day
# fallbacks while the remaining days still clear MIN_SAMPLE. The window bound is
# operator-asserted and unverified. Tracked on #6122 (which owns the true cutover UTC).
if [[ ! "$START" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
  echo "TRANSIENT: START is unpinned ($START) — pin ZOT_SOAK_START in this script to the cutover UTC before this gate can report a verdict." >&2
  exit 2
fi

# sentry_count <query> → echoes the event count for the window, or "TRANSIENT" on error.
sentry_count() {
  local q enc url resp status body n
  q="$1"
  enc=$(printf '%s' "$q" | jq -sRr @uri)
  url="${API}/organizations/${ORG}/events/?query=${enc}&start=${START}&end=${END}&per_page=100&field=title&field=timestamp"
  resp=$(curl -sS -w '\nHTTP_STATUS:%{http_code}' \
    -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" -H "Accept: application/json" "$url" 2>/dev/null)
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

# --- (a) Fallback events across ALL FIVE watched signals. Zero required. ---
#
# Declared, guarded, and summed by ONE loop, so "declared but never counted" — the #6435
# defect — is structurally unrepresentable rather than policed by a reviewer's attention.
# ⚠ [freshboot], [appboot] and [appserved] are BARE stage: queries. NEVER prefix them (see header).
#
# ⚠ appserved ⊇ appboot — FALLBACKS is a TRIPWIRE SUM, not an event count. Every path that
# emits app_ghcr_fallback also emits app_ghcr_served one line later (the flip sets
# REF=IMAGE_REF, which is exactly the app_ghcr_served condition), so ONE bad boot contributes
# 2 to FALLBACKS and double-fires the alarm. Harmless to the verdict — both are >0 ⇒ FAIL —
# but do not read FALLBACKS as "how many bad boots". They stay SEPARATE entries because the
# remediation differs: appboot = zot was attempted and the pull failed (chase the pull path);
# appserved without appboot = the /v2/ probe missed and zot was never attempted (chase the
# probe — #6416 / #6288). Collapsing them would erase that routing.
declare -A FAIL_QUERIES=(
  [rolling]='feature:supply-chain op:image-pull registry:"ghcr-fallback"'
  [gate]='feature:supply-chain op:image-pull registry:"zot-gate-degraded"'
  [freshboot]='stage:"inngest_ghcr_fallback"'
  [appboot]='stage:"app_ghcr_fallback"'
  [appserved]='stage:"app_ghcr_served"'
)

# Runtime cardinality floor. The array above makes "declared but never counted" unrepresentable
# only in SOURCE; at RUNTIME an absent/emptied FAIL_QUERIES iterates zero times and yields
# FALLBACKS=0 -> PASS. `set -u` does NOT rescue this: expanding "${!FAIL_QUERIES[@]}" on an
# unset array exits 0 with zero iterations (verified, bash 5.3.9), and there is no `set -e` to
# abort a failed `declare`. Without this line the only thing between "the array is gone" and
# "retire GHCR" is a CI test that parses source text — but CI parses while the sweeper
# executes. Mirrors the same floor in scripts/followthrough-exec-bit.test.sh.
if (( ${#FAIL_QUERIES[@]} != 5 )); then
  echo "TRANSIENT: FAIL_QUERIES has ${#FAIL_QUERIES[@]} entries, expected 5 — refusing to report a verdict on a partial FAIL set." >&2
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
  # gate-degraded = zot was never ATTEMPTED (the gate degraded → fleet silently on GHCR;
  #   chase the mirror/network path — #6416 / #6288).
  # ghcr-fallback = zot WAS attempted and the pull failed (chase the pull path).
  # inngest_/app_ghcr_fallback = a fresh boot could not pull from zot.
  # app-served = a fresh boot was served by GHCR. Its DOMINANT route is a /v2/ probe-miss,
  # where the GHCR pull succeeds first try and app-freshboot stays 0 — so app-served > 0 with
  # app-freshboot == 0 means "chase the probe", not "chase the pull". See the FAIL_QUERIES note.
  echo "FAIL: $FALLBACKS fallback event(s) since $START (rolling=${COUNTS[rolling]} gate-degraded=${COUNTS[gate]} inngest-freshboot=${COUNTS[freshboot]} app-freshboot=${COUNTS[appboot]} app-served=${COUNTS[appserved]}) — the fleet was served by GHCR. Investigate before retiring GHCR (do NOT proceed to 5.3-5.5)."
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
#   Since enrollment is deferred, every near-term run is a MANUAL one where env vars ARE
#   settable (see the MIN_SAMPLE note above) — so a knob here would be a bypass surface on
#   the gate authorizing an irreversible PAT revoke. A hardcoded floor has no such surface.
if (( APP_ZOT == 0 )); then
  echo "FAIL(no-freshboot-evidence): 0 fallbacks, but NO zot-served fresh boot since $START. The fleet is UNOBSERVED, not clean — 'no bad events' here cannot be distinguished from 'nothing was reported'. Most likely cause: this cloud-init predates START (it is ignore_changes-pinned on running hosts, so only a fresh rebuild carries the beacon) — merge, then recreate a web host inside the window."
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
# adjudicates 5.3 against the 5-of-7 ratio and the two disclosed residuals. What this arm adds
# is a FLOOR under that decision — exit 0 is a precondition the adjudicator needs, so a gate
# that returns 0 while a KNOWN-FATAL path is open hands them a green light it has not earned.
# The exit code can VETO a retirement; it cannot bless one. A gate is not made trustworthy by
# carrying a comment about the fatal path it ignores — #6462's thesis is that prose is not a
# fix — so the veto lives in the exit code.
#
# 5.3 rotates AND revokes the GHCR PAT: after it, a fleet that still needs GHCR can pull from
# neither registry, with no rollback.
#
# #6500: the dedicated inngest host (cloud-init-inngest.yml:337) hard-pins a ghcr.io ref with
# NO zot path and a fail-closed pull (:349), and reports to Better Stack rather than the
# Sentry `stage:` schema — so every query in this file is structurally blind to it. It is a
# LIVE host (hcloud_server.inngest is unconditional, inngest-host.tf:181). Revoke the PAT and
# its next fresh boot 401s and never comes up, while this soak reports PASS.
#
# ⚠ This reads issue STATE, not fixedness. Closing #6500 IS the authorization act — see the
# pinned warning on the issue. Do not close it to make this gate pass, and do not delete this
# arm to make this gate pass; the arm existing is the point.
BLOCKER=6500
# ⚠ --repo is NOT optional. sweep-followthroughs.sh runs this under `env -i` forwarding ONLY
# the directive's secrets= names, so the workflow's GH_REPO is STRIPPED and `gh` falls back to
# resolving the repo from the CWD's git remote. Under the sweeper that resolves correctly —
# but the header states enrollment is deferred, so every near-term run is a MANUAL one from an
# uncontrolled CWD, which is exactly when the retirement decision gets made. A run from
# another checkout would read a DIFFERENT repo's #6500, and the OPEN/CLOSED allowlist below
# cannot catch that: a wrong-repo CLOSED is a well-formed answer to the wrong question, and it
# would authorize the revoke. Pinning the repo makes the arm's correctness a stated fact
# rather than a CWD invariant.
st=$(gh issue view "$BLOCKER" --repo jikig-ai/soleur --json state --jq .state 2>/dev/null)
# ⚠ Fail SAFE on an unreadable state. A gate must never read "I could not measure" as "the
# measurement is false" — treating an unknown state as CLOSED would PASS the gate during a
# GitHub outage while the 7th path is still live. TRANSIENT is correct here (the probe could
# not run); it is NOT correct for the OPEN branch below, where the probe ran fine.
if [[ "$st" != "OPEN" && "$st" != "CLOSED" ]]; then
  echo "TRANSIENT: cannot read #$BLOCKER state (got '${st:-<empty>}') — retry next sweep. Is GH_TOKEN declared in the directive's secrets= clause?" >&2
  exit 2
fi
if [[ "$st" == "OPEN" ]]; then
  echo "FAIL(blocked): soak criteria hold (0 fallbacks, zot served web=$ZOT_WEB inngest=$ZOT_INNGEST, $APP_ZOT zot-served fresh boot(s)), but #$BLOCKER is OPEN — the dedicated inngest host pulls GHCR fail-closed with no zot path, so 5.3 (PAT revoke) would leave it unable to boot. NOT authorized to retire GHCR."
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
INNGEST_CI="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/apps/web-platform/infra/cloud-init-inngest.yml"
if [[ ! -f "$INNGEST_CI" ]]; then
  echo "TRANSIENT: cannot read $INNGEST_CI to corroborate #$BLOCKER's closure — refusing to authorize on issue state alone." >&2
  exit 2
fi
# (a) a zot pull path exists at all, and (b) it reports on the Sentry `stage:` schema the
# queries above depend on. Same terms as #6500's filed evidence, so the gate and the issue
# cannot drift apart on what "fixed" means.
if ! grep -qiE 'zot|ZURL|ZIREF|/v2/' "$INNGEST_CI" || ! grep -q 'soleur-boot-emit' "$INNGEST_CI"; then
  echo "FAIL(blocker-closed-but-condition-unmet): #$BLOCKER is CLOSED, but $INNGEST_CI still shows no zot pull path and/or no soleur-boot-emit reporting — the 7th GHCR-served path is still open in the CODE. Closing the issue does not retire the path. Re-open #$BLOCKER or fix the host before 5.3."
  exit 1
fi

echo "PASS: 0 ghcr-fallbacks, zot served web=$ZOT_WEB inngest=$ZOT_INNGEST (>=$MIN_SAMPLE each), $APP_ZOT zot-served fresh boot(s), and #$BLOCKER is CLOSED — since $START. zot-primary soak holds. Safe to retire GHCR (5.3-5.5) and flip ADR-096 accepted (5.6)."
exit 0
