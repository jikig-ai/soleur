#!/usr/bin/env bash
# Follow-through verification for #7710.
#
# Asserts that the restored freshness writer is ACTUALLY RUNNING in production,
# by looking for its artifact on the default branch rather than for a green run.
#
# The distinction is the whole point of the issue. Before #7710 the weekly cron
# compared the corpus correctly every week and posted a healthy heartbeat while
# advancing nothing, for 117 days. A probe that asks "did the cron succeed?"
# would have returned PASS throughout. So this probe asks the only question that
# could have caught it: DID THE FIELD MOVE?
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (the field advanced since merge; sweeper closes #7710)
#   1 = FAIL       (no advance in the window; sweeper comments, leaves open)
#   * = TRANSIENT  (gh unavailable / API failure; retry next sweep)
#
# Required env: GH_TOKEN  (the sweeper runs probes under `env -i`, so the
#               enrolment directive MUST carry secrets=GH_TOKEN or `gh` has no
#               credentials and every run is TRANSIENT).
#
# Enrolment (AC24): merge + 8 days — one cron cadence (Mondays 11:17 UTC) plus
# slack, so a single missed week is a real signal rather than a scheduling
# artifact.

set -uo pipefail

NOTICE_PATH="plugins/soleur/skills/gdpr-gate/NOTICE"
REPO="jikig-ai/soleur"

command -v gh >/dev/null 2>&1 || { echo "TRANSIENT: gh CLI not on PATH" >&2; exit 2; }
[[ -n "${GH_TOKEN:-}" ]] || { echo "TRANSIENT: GH_TOKEN not set" >&2; exit 2; }

# Window: 30 days.
#
# It MUST exceed the producer's write interval or a healthy system fails this
# probe. The writer suppresses any write while `last-verified` is under 21 days
# old, so on a weekly cadence consecutive attestation commits are 21-27 days
# apart. An earlier revision asked for a commit in the last 14 days, which is
# SHORTER than that interval: every sweep landing 15-27 days after a write
# would have reported "the restored writer is not advancing the field" on a
# perfectly healthy pipeline (#7710 review). It passed its first evaluation
# only because the field is 117 days stale today, so the first post-merge run
# writes unconditionally.
#
# 30 days is the same threshold the gate's own staleness banner uses, so this
# probe and the banner cannot disagree about what "current" means.
SINCE=$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
  || { echo "TRANSIENT: could not compute window" >&2; exit 2; }

COMMITS=$(gh api \
  "repos/${REPO}/commits?path=${NOTICE_PATH}&since=${SINCE}&per_page=100" \
  --jq '[.[] | {sha: .sha, author: (.author.login // "unknown"), msg: (.commit.message | split("\n")[0])}]' \
  2>/dev/null) || { echo "TRANSIENT: gh api call failed" >&2; exit 2; }

# An empty ARRAY is a real answer (no commits touched the NOTICE); an empty
# STRING means the call produced nothing parseable, which is not the same thing
# and must not read as FAIL.
[[ -n "$COMMITS" ]] || { echo "TRANSIENT: empty response from commits API" >&2; exit 2; }

COUNT=$(printf '%s' "$COMMITS" | jq 'length' 2>/dev/null) \
  || { echo "TRANSIENT: unparseable response" >&2; exit 2; }

# The attestation commits are bot-authored and carry a fixed subject prefix.
# Matching on the SUBJECT rather than the author keeps the probe working if the
# app installation's login changes, which is a rename away.
ATTESTATIONS=$(printf '%s' "$COMMITS" \
  | jq '[.[] | select(.msg | test("attest gosprinto/compliance-skills unchanged"))] | length' 2>/dev/null) \
  || { echo "TRANSIENT: unparseable response" >&2; exit 2; }

# Read the live value too, so a FAIL message says how bad it is rather than
# merely that it is bad.
DAYS_STALE=$(gh api "repos/${REPO}/contents/${NOTICE_PATH}" \
  --jq '.content' 2>/dev/null | base64 -d 2>/dev/null \
  | awk -F': *' '/^last-verified:/ {print $2; exit}')

if [[ -n "$DAYS_STALE" ]]; then
  LV_EPOCH=$(date -u -d "${DAYS_STALE}T00:00:00Z" +%s 2>/dev/null || echo "")
  if [[ -n "$LV_EPOCH" ]]; then
    NOW_EPOCH=$(date -u +%s)
    AGE_DAYS=$(( (NOW_EPOCH - LV_EPOCH) / 86400 ))
  else
    AGE_DAYS="unknown"
  fi
else
  AGE_DAYS="unknown"
fi

if (( ATTESTATIONS > 0 )); then
  echo "PASS: ${ATTESTATIONS} freshness attestation commit(s) on the default branch since ${SINCE}; last-verified is ${AGE_DAYS} day(s) old."
  exit 0
fi

# Second PASS arm: no commit in the window, but the field is fresh.
#
# That is the write-suppression working as designed, not a dead writer — the
# producer deliberately skips a write while the field is under 21 days old.
# Without this arm the probe would fail on exactly the state the suppression
# exists to produce.
if [[ "$AGE_DAYS" != "unknown" ]] && (( AGE_DAYS < 21 )); then
  echo "PASS: no attestation commit in the window, but last-verified is ${AGE_DAYS} day(s) old — the writer's under-21-day suppression is working."
  exit 0
fi

echo "FAIL: no freshness attestation commit on ${NOTICE_PATH} since ${SINCE} (${COUNT} commit(s) touched the file, none of them an attestation). last-verified age: ${AGE_DAYS} day(s)." >&2
echo "The restored writer is not advancing the field. This is the #7710 condition recurring: the cron may still be comparing correctly and reporting healthy while recording nothing." >&2
exit 1
