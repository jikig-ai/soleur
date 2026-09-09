#!/usr/bin/env bash
# Discoverability probe for the ops-email alert path (#7995 / PR #7989).
#
# THE QUESTION IT ANSWERS: if Resend refuses one of the cron ops-email POSTs,
# is there a path from that refusal to something an operator can read? For 111
# days there was not -- both call sites POSTed from a domain with no Resend
# verification records, neither inspected the response, and no Sentry rule
# matched. This probe asserts the three links of the repaired chain.
#
# WHY THIS PROBE AND NOT THE CUTOVER PROBE. The plan this block belongs to is
# the jikigai.com Cloudflare cutover, which is DEFERRED to #7995 -- its probe
# names a script that is not committed and a zone that does not exist, so it
# could only ever be prose in a `command:` field. What this PR actually SHIPS on
# a sensitive path is the alert-path repair, so that is what is verified here.
#
# WHY IT IS NOT VACUOUS. Every arm is derived from a committed artifact rather
# than restated: the feature list comes out of the Terraform rule, the sender
# domains out of the guard suite. Substituting either one reddens the probe.
#
# ARM 4 IS THE INSTRUMENT CONTROL, and it is the point. This session's defining
# error was reading a uniform verdict as data three times over -- a DNS answer
# that is "present" for every name asked (or "absent" for every name asked) is a
# broken instrument, not a measurement. So arm 4 falsifies the resolver in BOTH
# directions before arm 3 is believed: a name that MUST resolve, and a name that
# CANNOT. If either control misbehaves the probe reports UNRESOLVED and refuses
# to pass -- it never reports OK, or FAIL, on an instrument it has not checked.
#
# Read-only: touches nothing in the repository, writes no temp files.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$REPO_ROOT/apps/web-platform/infra/sentry/issue-alerts.tf"
GUARD="$REPO_ROOT/apps/web-platform/test/resend-sender-domain.test.ts"
FN_DIR="$REPO_ROOT/apps/web-platform/server/inngest/functions"

fail() { echo "RESEND_ALERT_PATH_FAIL $*"; exit 1; }

for f in "$TF" "$GUARD"; do
  [[ -r "$f" ]] || fail "missing artifact: ${f#"$REPO_ROOT"/}"
done

# --- Arm 1: the rule that pages on this failure exists, keyed on the emitted op.
RULE_BLOCK=$(awk '/resource "sentry_alert" "ops_email_delivery_failure"/{i=1} i{print} i&&/^}/{exit}' "$TF")
[[ -n "$RULE_BLOCK" ]] || fail "sentry_alert.ops_email_delivery_failure absent from issue-alerts.tf"
printf '%s' "$RULE_BLOCK" | grep -q 'key = "op".*value = "notify-ops-email"' \
  || fail "the rule does not filter on op eq notify-ops-email"

# --- Arm 2: every feature the RULE names actually emits that op.
#     Derived from the .tf, so adding a feature to the rule without wiring the
#     emit -- or renaming the op at one call site -- reddens this arm.
FEATURES=$(printf '%s' "$RULE_BLOCK" \
  | sed -n 's/.*key = "feature".*value = "\([^"]*\)".*/\1/p' | tr ',' ' ')
[[ -n "$FEATURES" ]] || fail "could not parse the rule's feature list"
#     A bare "at least one site mentions it" check is NOT enough, and that is
#     measured, not assumed: renaming the op at one of a file's two ops-email
#     sites left an earlier draft of this probe green. The rule matches on an
#     EXACT tag value, so a partial rename silently drops half the alert path --
#     which is the 111-day bug in miniature. Arm 2b therefore rejects any op
#     whose value is a near-miss of the target: equal once case and separators
#     are normalised away, but not byte-equal. That is derived from the target
#     rather than a denylist of the one spelling this PR happened to fix, and it
#     leaves the files' legitimate unrelated ops (probeOauth, relabel-*, ...)
#     untouched.
for feat in $FEATURES; do
  src="$FN_DIR/$feat.ts"
  [[ -r "$src" ]] || fail "rule names feature '$feat' but $feat.ts does not exist"
  grep -q 'op: "notify-ops-email"' "$src" \
    || fail "$feat.ts does not emit op: notify-ops-email, so the rule cannot match it"
  while IFS= read -r opval; do
    [[ "$opval" == "notify-ops-email" ]] && continue
    norm=$(printf '%s' "$opval" | tr '[:upper:]' '[:lower:]' | tr -d '_-')
    [[ "$norm" == "notifyopsemail" ]] \
      && fail "$feat.ts emits op: \"$opval\", a near-miss of notify-ops-email; the rule matches the tag EXACTLY, so this site is unreachable by the alert"
  done < <(sed -n 's/.*op: "\([^"]*\)".*/\1/p' "$src")
done

# --- Arms 3+4 need DNS. Degrade explicitly rather than silently skipping.
if ! command -v dig >/dev/null 2>&1; then
  echo "RESEND_ALERT_PATH_SKIP_NO_DIG static arms passed; dig absent so the sender-domain arms did not run"
  exit 0
fi

# --- Arm 4 FIRST: falsify the instrument BOTH WAYS before trusting arm 3.
#
# Both arms are needed and an earlier draft shipped only the negative one. With
# `dig` installed but no egress, every lookup returns empty: the negative arm
# passes (nothing resolved) and arm 3 then reports "domain has no DKIM" -- a red
# that is both false and the wrong diagnosis, blamed on the domain instead of on
# the network. A probe that cannot tell "absent" from "cannot look" is the exact
# defect this whole PR is about, so the positive arm runs first.
POS_CONTROL="soleur.ai"
if [[ -z "$(dig +short A "$POS_CONTROL" 2>/dev/null)" ]]; then
  echo "RESEND_ALERT_PATH_UNRESOLVED positive control $POS_CONTROL did not resolve;"
  echo "  DNS is unreachable from here, so an empty DKIM answer would mean nothing."
  exit 1
fi
NEG_CONTROL="resend._domainkey.probe-control-must-not-exist.soleur.ai"
if [[ -n "$(dig +short TXT "$NEG_CONTROL" 2>/dev/null)" ]]; then
  echo "RESEND_ALERT_PATH_UNRESOLVED resolver answered for $NEG_CONTROL, which cannot exist;"
  echo "  a resolver that answers every name cannot evidence that any domain is verified."
  exit 1
fi

# --- Arm 3: every sender domain the guard permits has a live Resend DKIM key.
#     Derived from the guard's allowlist, so repointing a sender at a domain
#     Resend has never verified reddens this arm.
DOMAINS=$(sed -n 's/.*VERIFIED_SENDER_DOMAINS = new Set(\[\(.*\)\]).*/\1/p' "$GUARD" \
  | tr -d '"' | tr ',' ' ')
[[ -n "$DOMAINS" ]] || fail "could not parse VERIFIED_SENDER_DOMAINS from the guard"
for d in $DOMAINS; do
  [[ -n "$(dig +short TXT "resend._domainkey.$d" 2>/dev/null)" ]] \
    || fail "sender domain $d has no resend._domainkey TXT -- Resend will refuse mail from it"
done

echo "RESEND_ALERT_PATH_OK rule+emit wired for [$FEATURES]; DKIM present for [$DOMAINS]; controls both ways"
