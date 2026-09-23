#!/usr/bin/env bash
# §2.9 — every `sentry_alert` the Sentry root declares, diffed field-by-field
# against a reference PROJECTED FROM TERRAFORM (#7650 Phase 2, re-based #8050).
# AC19/AC20/AC22.
#
# ── WHAT THIS CATCHES THAT NOTHING ELSE DOES ───────────────────────────────
# A rule can go dark WEEKS after the apply that created it: it still exists, the
# plan is still clean, and it matches nothing. Every existing control misses
# that, each for a different reason:
#
#   * `assert-byok-rules-exist.sh` covers 4 rules by name and enablement. The
#     rest are outside it entirely, and for the four inside it a `tagged_event`
#     whose key was renamed in the UI still reads as live.
#   * The destroy gate reads a PLAN. A rule edited in the Sentry UI produces a
#     plan diff only when Terraform next refreshes it, and `ignore_changes`
#     hides `environment` regardless.
#   * A green `terraform plan` says config and state agree. It says nothing
#     about whether the live rule still fires on the events it was written for.
#
# So this reads LIVE Sentry and compares it to what the `.tf` declares.
#
# ── WHERE THE REFERENCE COMES FROM ─────────────────────────────────────────
# A projection of `terraform show -json` by tests/scripts/lib/sentry-alert-projection.jq
# (its header owns the rationale, the two normalisations, the allowlists, and
# why `environment` is not compared — read it there, it is not restated here):
#   * apply job: projected from the plan being applied
#     (`SENTRY_REFERENCE_FILE=${RUNNER_TEMP}/sentry-alert-reference.json`), so a
#     divergence right after `terraform apply` is live state Terraform does not
#     own, or evidence the apply did not do what it reported — by construction.
#   * daily job (no Terraform access): the COMMITTED copy at
#     apps/web-platform/infra/sentry/alert-reference.json, held equal to the
#     plan by scripts/sentry-alert-reference-gate.sh in `plan_pr`.
# It used to be a committed live capture; a rule cannot be live-captured before
# it is applied, which redded `main` after a complete apply twice (#7772 -> #7985,
# #7989 -> #8050).
#
# ── DESTINATION PIN AND TRANSPORT CONFINEMENT (#7997, #8023) ───────────────
# The IaC token this probe carries is WRITE-capable and used read-only here. Two
# flags are not enough to keep it home: `--disable` (FIRST argument — it aborts
# ~/.curlrc parsing and is a no-op anywhere later) and `--noproxy '*'` (no
# ALL_PROXY/HTTPS_PROXY can redirect the request). Neither touches the RESOLVER,
# the TRUST ANCHOR or the TLS KEY LOG — LOCALDOMAIN/RES_OPTIONS/HOSTALIASES,
# CURL_CA_BUNDLE/SSL_CERT_FILE/SSL_CERT_DIR and SSLKEYLOGFILE — so those are
# `unset` below before any curl runs. `--proto '=https' -g` close scheme
# downgrade and URL globbing. The destination is pinned by EXACT EQUALITY to two
# literals (`jikigai-eu.sentry.io`, `jikigai-eu`) inside the live branch, and the
# bearer header travels on STDIN (`--header @-`), never in argv. This is defence
# in depth against an accidental or hostile ENVIRONMENT; an actor who can set
# LD_PRELOAD, BASH_ENV or BASH_FUNC_curl%% has a strictly stronger capability
# that no pin can see (measured, #8023) — read this as a floor, not a closure.
#
# Refusals print `ERROR: refusing destination host …` / `ERROR: refusing org …`
# and exit 2: the drift workflow's unavailable-issue body greps that anchor to
# name the refusal CLASS without reproducing the value.
#
# Required env: SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_API_HOST.
# SENTRY_REFERENCE_FILE overrides the reference path (the apply job sets it).
# SENTRY_FROZEN_CAPTURE_FILE overrides the frozen-rule pin's anchor (default: the
# committed 2026-09-09 live capture; empty reads as unset). See "FROZEN-RULE PIN".
# SENTRY_FROZEN_TF_DIR overrides the directory whose *.tf the frozen-rule set is
# derived from (default: apps/web-platform/infra/sentry; empty reads as unset).
# SENTRY_VENDOR_DEFAULTS_FILE overrides the registry of Sentry-created default
# workflows the census accepts (default: apps/web-platform/infra/sentry/
# vendor-default-workflows.json; empty reads as unset). See "THE CENSUS".
# Test injection (its own suite ONLY): SENTRY_FIXTURE_RULES — file path served
# instead of the live GET.
#
# Exit 0 = every declared rule matches live, and every in-scope live rule is declared.
# Exit 1 = a divergence, or the probe could not establish that it checked anything.
set -euo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). Shell tracing echoes commands AFTER
# expansion, so SENTRY_AUTH_TOKEN is printed the moment it is used. `${VAR:+x}`
# is non-emptiness WITHOUT expanding the value -- `${VAR:-}` would print it on
# this very line. Tracing stays available with the credential unset, so this
# refuses a leak without blocking a debugging session.
case "$-" in
  *x*)
    if [ -n "${SENTRY_AUTH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (SENTRY_AUTH_TOKEN). Unset it to trace safely (see #7797).\n' >&2
      exit 78
    fi
    ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTION="$REPO_ROOT/tests/scripts/lib/sentry-alert-projection.jq"
REFERENCE="${SENTRY_REFERENCE_FILE:-$REPO_ROOT/apps/web-platform/infra/sentry/alert-reference.json}"
FROZEN_CAPTURE="${SENTRY_FROZEN_CAPTURE_FILE:-$REPO_ROOT/knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase34-live-workflows-capture-2026-09-09.json}"
FROZEN_TF_DIR="${SENTRY_FROZEN_TF_DIR:-$REPO_ROOT/apps/web-platform/infra/sentry}"
VENDOR_DEFAULTS="${SENTRY_VENDOR_DEFAULTS_FILE:-$REPO_ROOT/apps/web-platform/infra/sentry/vendor-default-workflows.json}"

: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN must be set}"
: "${SENTRY_ORG:?SENTRY_ORG must be set}"

# (a) Strip the environment curl reads that neither --noproxy nor a host pin
#     reaches (#8023). Precedes every curl invocation.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME \
      HOSTALIASES LOCALDOMAIN RES_OPTIONS \
      OPENSSL_CONF OPENSSL_MODULES LD_PRELOAD LD_AUDIT LD_LIBRARY_PATH

# (b) Log-safe rendering of a hostile env value: control chars and the U+2028/
#     U+2029 separators stripped (named as UTF-8 BYTES — `$'\u2028'` renders in
#     the CURRENT locale and cannot represent the codepoint under LC_ALL=C), cut
#     by BYTES (a multi-byte value must not walk past the cap), then `iconv -c`
#     drops any sequence the byte cut truncated mid-character, because this can
#     reach a JSON REST body, not only a log (#8023).
_U2028=$'\xe2\x80\xa8'; _U2029=$'\xe2\x80\xa9'
_safe() {
  local s="${1//[[:cntrl:]]/}"
  s="${s//$_U2028/}"; s="${s//$_U2029/}"
  printf '%s' "$s" | cut -b1-120 | iconv -c -f UTF-8 -t UTF-8
}

# (c) RFC 1035 §2.3.4 label shape (63 octets max). The subshell is MANDATORY:
#     `LC_ALL=C [[ … ]]` is a parse error, and without the C locale the a-z0-9
#     ranges admit ~1,162 non-ASCII characters under en_US.UTF-8. This runs on
#     every path (fixture rows use `SENTRY_ORG=fixture`, which passes); the
#     literal pin below runs on the live path only.
( LC_ALL=C; [[ "$SENTRY_ORG" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] ) || {
  printf 'ERROR: refusing org %s\n' "$(_safe "$SENTRY_ORG")" >&2; exit 2; }

# (d) Nothing downstream may re-point it.
readonly SENTRY_ORG

[[ -r "$PROJECTION" ]] || { echo "ERROR: projection module not readable at $PROJECTION" >&2; exit 1; }
[[ -r "$REFERENCE" ]] || { echo "ERROR: reference not readable at $REFERENCE" >&2; exit 1; }
[[ -r "$FROZEN_CAPTURE" ]] || { echo "ERROR: frozen-rule capture not readable at $FROZEN_CAPTURE. The frozen-rule pin has no anchor, so this probe cannot check the excluded-type rules. Refusing." >&2; exit 1; }

# FIXTURE MODE IS ANNOUNCED, LOUDLY. The override exists for this script's own
# suite, but "its own suite ONLY" was prose, not a mechanism: the PASS line was
# byte-identical whether the rules came from live Sentry or from a local file,
# down to the word "live". Both call sites invoke this bare, in jobs where an
# earlier step writes to `$GITHUB_ENV` — so any future step, repo variable or
# environment value named SENTRY_FIXTURE_RULES would silently convert the one
# post-apply probe covering `byok-art-33-breach` into a self-comparison that can
# never fail, with no trace in the log.
#
# SET HERE, IN THE PARENT SHELL — not inside `fetch_rules`. That function runs
# under `$(…)`, i.e. in a SUBSHELL, so an assignment inside it is discarded and
# the flag would read 0 on every fixture run. That is exactly what the previous
# revision did: it set the flag inside the function, the fixture-mode PASS line
# was never printed, and its suite could not see it because it grepped a
# substring both PASS lines share (#8050 — F1 now asserts the full literal).
FIXTURE_MODE=0
[[ -n "${SENTRY_FIXTURE_RULES:-}" ]] && FIXTURE_MODE=1
fetch_rules() {
  if [[ "$FIXTURE_MODE" -eq 1 ]]; then
    echo "::warning::sentry_alert live fidelity: FIXTURE MODE — SENTRY_FIXTURE_RULES is set, so this run did NOT read live Sentry. A PASS here says the fixture matches the reference and NOTHING about production." >&2
    cat "$SENTRY_FIXTURE_RULES"
    return
  fi
  : "${SENTRY_API_HOST:?SENTRY_API_HOST must be set (org-subdomain, e.g. jikigai-eu.sentry.io)}"
  # THE PINS, inside the live branch and after the fixture `return` — the suite's
  # fixture rows run with SENTRY_ORG=fixture and must not trip them. Exact
  # equality against a LITERAL, never against another variable: on this surface
  # the environment is the adversary, and a pin that reads its expected value
  # from the environment pins nothing (#7997). The literals are the Doppler
  # `prd` SENTRY_API_HOST value and `variables.tf`'s `sentry_org` default. The
  # message anchors (`refusing destination host`, `refusing org`) and exit 2 are
  # the contract the drift workflow's unavailable-issue body greps (#8023); the
  # value is rendered through `_safe`, never raw. Remedy for a drifted repository
  # secret: `gh secret set SENTRY_API_HOST --body jikigai-eu.sentry.io` — a
  # hostname, not a secret.
  case "$SENTRY_API_HOST" in
    "jikigai-eu.sentry.io") ;;
    *) printf 'ERROR: refusing destination host %s (pinned: jikigai-eu.sentry.io)\n' "$(_safe "$SENTRY_API_HOST")" >&2; exit 2 ;;
  esac
  case "$SENTRY_ORG" in
    "jikigai-eu") ;;
    *) printf 'ERROR: refusing org %s (pinned: jikigai-eu)\n' "$(_safe "$SENTRY_ORG")" >&2; exit 2 ;;
  esac
  # The NON-deprecated org workflows endpoint — the same one
  # assert-byok-rules-exist.sh migrated to in #7590. Deliberately not
  # `projects/{org}/{proj}/rules/`: that family was under brownout and has since
  # been removed outright (a persistent 410, #8451).
  #
  # Flag ORDER is load-bearing and pinned by the suite: `--disable` FIRST, then
  # `--noproxy '*'`, then `--proto '=https' -g`. The bearer header arrives on
  # STDIN via `--header @-`, so the token is never in argv (not in `ps`, not in a
  # crash dump of the argument vector). Model: scripts/supabase-logs-query.sh.
  printf 'Authorization: Bearer %s\n' "$SENTRY_AUTH_TOKEN" |
    curl --disable --noproxy '*' --proto '=https' -g -fsS --max-time 15 \
      --header @- \
      "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/workflows/?per_page=100"
}

live_json="$(fetch_rules)"

if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$live_json"; then
  echo "ERROR: Sentry workflows response is not a JSON array. \`curl -fsS\` already aborted on any >=400, so what reaches here is a 200 carrying a non-array body: schema drift, an HTML interstitial, or a proxy injection. Cannot assert fidelity." >&2
  printf '%s\n' "$live_json" | head -c 500 >&2
  exit 1
fi

# PAGINATION CEILING, same reasoning as assert-byok-rules-exist.sh: this fetch
# asks for one page of 100 and follows no cursor. A rule on page 2 is
# indistinguishable from a deleted one, and this probe's whole output would be a
# false "every rule is gone" alarm.
if (( $(jq 'length' <<<"$live_json") >= 100 )); then
  echo "ERROR: the workflows payload returned >= 100 rows, this fetch's unpaginated ceiling. Rules beyond page 1 would read as DELETED and produce a false alarm. Do not trust this verdict. Fix: follow the Link rel=\"next\" cursor, mirroring sentry_fetch_collection in apps/web-platform/scripts/sentry-monitors-audit.sh." >&2
  exit 1
fi

# ── The comparable projection ──────────────────────────────────────────────
# ONE module (tests/scripts/lib/sentry-alert-projection.jq) applied to BOTH
# sides — `live` for the API payload, `reference` for the projected document —
# so a field can never be normalised differently on the two halves. The module's
# header records every normalisation and the measurement behind it. rc is
# captured on its OWN LINE after each of the two module calls (bracketed
# `set +e`/`set -e` because this script is `set -e`): a module `error` exits 5,
# and the probe must turn that into a refusal, never into "compared 0 rules →
# PASS". The stderr capture is a per-invocation `mktemp` — a fixed name in a
# shared TMPDIR loses the message when two probes run at once (measured).
jq_err=$(mktemp "${TMPDIR:-/tmp}/sentry-fidelity-jq.XXXXXX")
trap 'rm -f "$jq_err"' EXIT
set +e
live_proj=$(jq --arg side live -f "$PROJECTION" <<<"$live_json" 2>"$jq_err")
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "ERROR: the live payload did not project (jq rc=$rc): $(tr '\n' ' ' <"$jq_err" | cut -c1-400). Cannot assert fidelity." >&2
  exit 1
fi

set +e
ref_proj=$(jq --arg side reference -f "$PROJECTION" < "$REFERENCE" 2>"$jq_err")
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "ERROR: the reference at ${REFERENCE} did not project (jq rc=$rc): $(tr '\n' ' ' <"$jq_err" | cut -c1-400). It must be a name-indexed projection (jq --arg side tf -f tests/scripts/lib/sentry-alert-projection.jq over terraform show -json), not an API-shaped capture. Refusing." >&2
  exit 1
fi

ref_count=$(jq 'length' <<<"$ref_proj")
live_count=$(jq 'length' <<<"$live_proj")

# Anti-vacuity floor, stated as a POSITIVE requirement on work done. A probe
# that compared nothing must never print a clean verdict — and "the reference
# holds zero rules" is exactly how this would silently become a no-op after a
# botched regeneration (the module's shape floor passes `{}` on purpose so THIS
# floor stays reachable).
if [[ "$ref_count" -eq 0 ]]; then
  echo "ERROR: the reference yielded ZERO in-scope rules. The Sentry root declares nothing, or the reference was regenerated from the wrong document, so this probe would report 'no drift' having compared nothing. Refusing." >&2
  exit 1
fi

findings=0
_finding() { findings=$((findings + 1)); printf '  %s\n' "$*"; }

echo "sentry_alert live fidelity: comparing ${ref_count} declared rule(s) against ${live_count} live in-scope rule(s)"

# ── Per-rule, field-by-field ────────────────────────────────────────────────
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  if ! jq -e --arg n "$name" 'has($n)' >/dev/null <<<"$live_proj"; then
    # ABSENT FROM THE PROJECTION IS NOT ABSENT FROM SENTRY. `project_live` keeps
    # every IN-SCOPE workflow, so a declared name that is missing here while the
    # RAW payload still carries it means the live rule left the scope — it gained
    # a trigger type the provider cannot express (Sentry adds these to existing
    # workflows; Seer did exactly that, #8267). That is a different failure with a
    # different remedy: `DELETED or RENAMED` says "an apply can recreate it", and
    # an apply is NOT a repair here. Hand it to the frozen-rule pass below, which
    # reports it as MANAGED RULE GAINED EXCLUDED TRIGGER.
    if jq -e --arg n "$name" 'any(.[]; .name == $n)' >/dev/null <<<"$live_json"; then
      continue
    fi
    _finding "DELETED or RENAMED: '$name' is declared in the Sentry root and absent from live Sentry. An apply can recreate a deleted rule; a rule renamed in the UI needs the name restored (Terraform owns \`name\`, so the next apply would otherwise create a SECOND rule)."
    continue
  fi
  # DISABLED is judged against the DECLARED value, not against `true`. A rule the
  # root declares `enabled = false` and live Sentry holds disabled is in its desired
  # state; flagging it would red every apply and every daily run for as long as the
  # declaration stands — the #8050 shape one attribute over (a reference that cannot
  # agree with a correct live state). Declared-true/live-false is the DISABLED class;
  # declared-false/live-true is caught below as DRIFT on `enabled`, which an apply fixes.
  if jq -e --arg n "$name" '.[$n].enabled == true' >/dev/null <<<"$ref_proj" \
     && ! jq -e --arg n "$name" '.[$n].enabled == true' >/dev/null <<<"$live_proj"; then
    _finding "DISABLED: '$name' exists but is not enabled — it pages nobody. Enablement is live state; an apply will NOT fix it."
  fi
  # Field-by-field so the report names WHICH attribute moved, not just "differs".
  while IFS= read -r field; do
    [[ -n "$field" ]] || continue
    # `-S` (sort keys) is load-bearing, not tidiness. These values are compared as
    # STRINGS, and `jq -c` preserves key INSERTION order. The module already
    # canonicalises both sides; `-S` here is the belt to that brace.
    local_ref=$(jq -S -c --arg n "$name" --arg f "$field" '.[$n][$f]' <<<"$ref_proj")
    local_live=$(jq -S -c --arg n "$name" --arg f "$field" '.[$n][$f]' <<<"$live_proj")
    if [[ "$local_ref" != "$local_live" ]]; then
      case "$field" in
        detectorIds)
          _finding "MONITOR UNBIND: '$name'.detectorIds declared=$local_ref live=$local_live — the rule is bound to a different detector (or none), so it watches nothing while still appearing healthy." ;;
        triggerLogicType)
          _finding "LOGICTYPE FLIP: '$name'.triggers.logicType declared=$local_ref live=$local_live — the rule now requires all/any of its triggers where it required the other. Live state an apply will NOT touch: the provider always writes any-short, so a rule reading 'all' was edited in Sentry." ;;
        triggerConditions|actionFilters)
          # Narrow to the LEAF PATHS that moved. Printing both whole arrays is
          # technically complete and practically unreadable: a one-key rename
          # inside one condition renders as two ~600-character blobs the reader
          # has to diff by eye, at the moment they are least able to. An
          # element-level `$a - $b` does not help either — the differing element
          # IS the whole object — so this descends to scalars and reports
          # `path: declared -> live`, which is the sentence the operator needs.
          _finding "DRIFT: '$name'.$field"
          while IFS= read -r leaf; do
            [[ -n "$leaf" ]] && _finding "         $leaf"
          # Two views, because the arrays are SORTED before comparison: the
          # element-level multiset diff (`only declared:` / `only live:`) is
          # exact — one changed element is one line each side — while the leaf
          # paths below it are POSITIONAL after the sort, so a single change
          # that re-orders neighbours can pair unrelated elements and print
          # fictitious neighbouring lines. Read the element lines first.
          #
          # `paths` reads the INPUT, and this runs under `-n`, so `$v |` is
          # required — without it every call returns nothing and the loop prints
          # an empty drift report while claiming a divergence.
          #
          # Presence is tested with `has`, never `// "<absent>"`: a leaf whose
          # value is `false` or `null` is falsy, and the `//` form would render
          # a real `false` as absent and hide the exact flip. For the SAME reason
          # the walk tests the TYPE, not `paths(scalars)`: `paths(f)` keeps a
          # path only when `f` is truthy on the value, so `scalars` DROPS every
          # `false`/`null` leaf (`targetIdentifier: null` among them).
          done < <(jq -r --argjson a "$local_ref" --argjson b "$local_live" -n '
            (if ($a | type) == "array" and ($b | type) == "array" then
               (($a - $b)[] | "only declared: \(tojson)"),
               (($b - $a)[] | "only live:     \(tojson)")
             else empty end),
            ( def leaves($v): [ ($v | paths(type != "array" and type != "object")) as $p
                                | {k: ($p | map(tostring) | join(".")), v: ($v | getpath($p))} ]
                              | INDEX(.k);
              leaves($a) as $A | leaves($b) as $B
              | (($A | keys) + ($B | keys) | unique)[] as $k
              | (if ($A | has($k)) then ($A[$k].v | tojson) else "<absent>" end) as $ca
              | (if ($B | has($k)) then ($B[$k].v | tojson) else "<absent>" end) as $li
              | select($ca != $li)
              | "\($k): declared=\($ca) live=\($li)" )
          ') ;;
        *)
          _finding "DRIFT: '$name'.$field declared=$local_ref live=$local_live" ;;
      esac
    fi
  done < <(printf '%s\n' enabled detectorIds frequency triggerLogicType triggerConditions actionFilters)
done < <(jq -r 'keys[]' <<<"$ref_proj")

# ── The other direction: an in-scope live rule the root does not declare ────
# Not cosmetic. A rule in scope that Terraform does not manage is one an apply
# will never repair, and the next reader of `issue-alerts.tf` will not know it
# exists. Since the reference is projected from the plan, UNMANAGED here means
# exactly "undeclared" — never "the reference file is stale" (that is the
# reference gate's job, at PR time).
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  jq -e --arg n "$name" 'has($n)' >/dev/null <<<"$ref_proj" && continue
  _finding "UNMANAGED: '$name' is live and in scope but declared nowhere in apps/web-platform/infra/sentry/ (absent from the reference projected from the plan). Adopt it as a sentry_alert or delete it in Sentry. If Sentry created it (createdBy null) with a trigger type the provider cannot express, register it instead: add the type to `def excluded` in tests/scripts/lib/sentry-alert-projection.jq and {id, name} to apps/web-platform/infra/sentry/vendor-default-workflows.json (#8267)."
done < <(jq -r 'keys[]' <<<"$live_proj")

# ── FROZEN-RULE PIN (Guard 4, #8451) ────────────────────────────────────────
# A workflow whose trigger type is in the projection's `excluded` set is outside
# BOTH projection sides, so every check above is blind to it by construction.
# The rules TERRAFORM FREEZES — `sentry_alert` blocks carrying
# `legacy_trigger_conditions`, adopted under `ignore_changes = all` — are never
# written by an apply, and a UI edit plans "0 changes". This pass is their ONLY
# content check.
#
# TWO SETS, NEITHER A LITERAL:
#   * FROZEN NAMES, derived from the `.tf` below. Each must have a capture entry
#     (else REFUSE: no anchor) and a live workflow (else FROZEN DELETED), and is
#     compared by name on every field that decides paging: enabled, detectorIds,
#     the full trigger {type, comparison} set, triggers.logicType,
#     config.frequency, environment, and actionFilters (logicType; conditions as
#     {type, comparison}; actions as {type, config.targetType,
#     data.fallthroughType}), all canonicalised and order-insensitive.
#   * THE CENSUS: every other live workflow carrying an excluded trigger type.
#     KNOWN = its {id, name} pair is in the capture (the org's "Send a
#     notification for high priority issues" default, captured 2026-09-09) or in
#     the vendor-default registry (Sentry-created defaults that appeared after the
#     capture, e.g. Seer's "Send a notification when pull requests are ready",
#     #8267): NOT a finding. The capture is a dated snapshot and is never
#     appended to; a later default goes in the registry.
#     A known NAME under a different id, or a known name live twice, is a finding:
#     matching by name alone would let any workflow borrow a default's name.
#     This is an IDENTITY check only. A known default's CONTENT is deliberately
#     not pinned (Sentry edits its own defaults; pinning one filed a P1 over a
#     vendor change), so disabling or retargeting it is not detected here.
#     Anything else = UNMANAGED-FROZEN.
#   * MANAGED RULE GAINED EXCLUDED TRIGGER: a census member whose name the
#     reference declares and which is the name of no IN-SCOPE live workflow. That
#     is a Terraform-managed rule Sentry added an unmanageable trigger type to, so
#     it left the projection scope: nothing above compares it any more. Reported
#     before the KNOWN arm and excluded from the census tally — matching it as a
#     "registered Sentry default" is exactly how it used to pass in silence. An
#     apply does not repair it; the finding says what does.
#
# THE EXCLUDED SET IS READ FROM THE MODULE, not restated: the module carries a
# main expression, so `include` is refused ("library should only have function
# definitions"), and the one-line `def excluded:` is lifted verbatim and
# evaluated. A reshaped definition fails that extraction and REFUSES below —
# never an empty set, which would make the census compare nothing silently.
excluded_def=$(grep -m1 -E '^def excluded: \[.*\];[[:space:]]*$' "$PROJECTION" || true)
set +e
excluded_json=$(jq -n -c "${excluded_def} excluded" 2>"$jq_err")
rc=$?
set -e
if [[ "$rc" -ne 0 || -z "$excluded_def" ]] \
   || ! jq -e 'type == "array" and length > 0 and all(.[]; type == "string" and . != "")' >/dev/null 2>&1 <<<"$excluded_json"; then
  echo "ERROR: could not read the excluded trigger-type set from ${PROJECTION} (jq rc=$rc; expected one line 'def excluded: [\"…\", …];'): $(tr '\n' ' ' <"$jq_err" | cut -c1-200). The frozen-rule pin cannot select its census. Refusing." >&2
  exit 1
fi

# FROZEN NAMES FROM THE `.tf`: the top-level `name` of every
# `resource "sentry_alert"` block whose top-level `legacy_trigger_conditions` is
# a NON-EMPTY list. Top-level = two-space indent inside a block that opens at
# column 0 and closes at a column-0 `}` (terraform fmt's layout, which the
# `terraform fmt -check` gate holds). Zero names is a derivation that broke — a
# renamed attribute, a moved directory, a reformatted block — and REFUSES:
# "compared 0 frozen rules" must never read as clean.
tf_files=()
if [[ -d "$FROZEN_TF_DIR" ]]; then
  for f in "$FROZEN_TF_DIR"/*.tf; do [[ -r "$f" ]] && tf_files+=("$f"); done
fi
# The vendor-default registry: a JSON array of {id, name, …}, both non-empty
# strings. Unreadable or mis-shaped REFUSES — an empty registry would silently
# turn every registered default into an UNMANAGED-FROZEN page, and a
# mis-shaped one could match nothing while reading as loaded.
if ! jq -e 'type == "array" and all(.[]; (.id | type) == "string" and .id != "" and (.name | type) == "string" and .name != "")' \
     "$VENDOR_DEFAULTS" >/dev/null 2>&1; then
  echo "ERROR: the vendor-default registry at ${VENDOR_DEFAULTS} is unreadable or not an array of {id, name} string pairs. The census cannot tell a registered Sentry default from an unmanaged workflow. Refusing." >&2
  exit 1
fi
frozen_names_json='[]'
if [[ ${#tf_files[@]} -gt 0 ]]; then
  frozen_names_json=$(awk '
    /^resource "sentry_alert" "[^"]*"[[:space:]]*\{[[:space:]]*$/ { inb = 1; nm = ""; leg = 0; next }
    inb && /^\}/ { if (leg && nm != "") print nm; inb = 0; next }
    inb && /^  name[[:space:]]*=[[:space:]]*"[^"]*"/ { v = $0; sub(/^  name[[:space:]]*=[[:space:]]*"/, "", v); sub(/".*$/, "", v); nm = v; next }
    inb && /^  legacy_trigger_conditions[[:space:]]*=[[:space:]]*\[[[:space:]]*"/ { leg = 1; next }
  ' "${tf_files[@]}" | jq -R -s -c 'split("\n") | map(select(. != "")) | unique')
fi
frozen_tf_n=$(jq 'length' <<<"$frozen_names_json")
if [[ "$frozen_tf_n" -eq 0 ]]; then
  echo "ERROR: derived ZERO frozen rules from ${FROZEN_TF_DIR}/*.tf (${#tf_files[@]} file(s) read; looked for resource \"sentry_alert\" blocks with a non-empty top-level legacy_trigger_conditions). The derivation broke, so the frozen-rule pin would compare nothing. Refusing." >&2
  exit 1
fi
set +e
missing_cap=$(jq -r --argjson fz "$frozen_names_json" --slurpfile cap "$FROZEN_CAPTURE" \
  'if ($cap[0] | type) != "array" then error("frozen-rule capture is not a JSON array of workflows") else . end
   | ($cap[0] | map(.name)) as $cn | $fz[] | select(. as $n | $cn | index($n) | not)' -n 2>"$jq_err")
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "ERROR: the frozen-rule capture at ${FROZEN_CAPTURE} did not evaluate (jq rc=$rc): $(tr '\n' ' ' <"$jq_err" | cut -c1-300). Refusing." >&2
  exit 1
fi
if [[ -n "$missing_cap" ]]; then
  echo "ERROR: Terraform-frozen rule(s) with no entry in the committed capture at ${FROZEN_CAPTURE}: $(sed "s/.*/'&'/" <<<"$missing_cap" | tr '\n' ' ')- the frozen-rule pin has no anchor for them. Refusing." >&2
  exit 1
fi

set +e
frozen_report=$(jq -r -n --arg q "'" --argjson ex "$excluded_json" --argjson live "$live_json" \
    --argjson fz "$frozen_names_json" --slurpfile cap "$FROZEN_CAPTURE" \
    --slurpfile vd "$VENDOR_DEFAULTS" \
    --argjson refnames "$(jq -c 'keys' <<<"$ref_proj")" '
  def excl_type: [ .triggers.conditions[]?.type ] as $t | any($ex[]; . as $e | $t | index($e));
  # Key order is not data: the live API does not sort keys, and `tojson`
  # preserves insertion order (F13 reds without this canonicalisation). Every
  # list is compared as a multiset: canonical elements sorted by their JSON.
  def canon: walk(if type == "object" then (to_entries | sort_by(.key) | from_entries) else . end);
  def mset: map(canon) | sort_by(tojson);
  def trig: [ .triggers.conditions[]? | {type, comparison} ] | mset;
  def dets: (.detectorIds // []) | map(tostring) | sort;
  def filt: [ .actionFilters[]?
              | { logicType,
                  conditions: ([ .conditions[]? | {type, comparison} ] | mset),
                  actions: ([ .actions[]? | {type, targetType: (.config // {}).targetType,
                                             fallthroughType: (.data // {}).fallthroughType} ] | mset) } ]
            | mset;
  def fields: { triggerConditions: trig, triggerLogicType: .triggers.logicType,
                frequency: (.config // {}).frequency, environment: .environment,
                actionFilters: filt };
  # {id, name} membership, used for KNOWN and for GAINED alike.
  def is_in($set): . as $w | any($set[]; .id == ($w.id | tostring) and .name == $w.name);
  $cap[0] as $CAP
  # THE CAPTURE HALF OF KNOWN IS NARROWED to the capture entries this set is
  # ABOUT: excluded-type, and not frozen in Terraform. Built from every capture
  # entry (as it was), KNOWN held all 28 managed rules too — so a managed rule
  # that left the scope, or one dropped from Terraform while still live, matched
  # by {id, name} and was accepted in silence with rc=0, having been compared by
  # nothing. The registry half is unchanged: those entries are excluded-type by
  # construction (that is why they are registered).
  | ([ ($CAP[] | select(excl_type and ((.name as $n | $fz | index($n)) | not)) | {id: (.id | tostring), name}),
       ($vd[0][] | {id: (.id | tostring), name}) ]) as $KNOWN
  | ($live | map(select(excl_type | not) | .name)) as $INSCOPE
  | ($live | map(select(.name as $n | $fz | index($n)))) as $F
  | ($live | map(select(excl_type and (.name as $n | $fz | index($n) | not)))) as $O
  # GAINED: a census member whose name the reference DECLARES (so Terraform manages
  # it) and which is the name of no in-scope live workflow. The second condition is
  # what keeps a same-name excluded COPY of a healthy managed rule out of this arm —
  # the managed rule itself never left scope, so that copy is still UNMANAGED-FROZEN.
  | ($O | map(select(((.name as $n | $refnames | index($n)) != null)
                     and ((.name as $n | $INSCOPE | index($n)) == null)))) as $GAINED
  # The third field counts registered defaults ONLY: KNOWN and not GAINED, so a
  # managed rule that left scope can never inflate "registered Sentry defaults".
  #
  # MEASURED, and recorded because the honest reading is not the obvious one: with
  # the narrowed $KNOWN above, `is_in($GAINED) | not` is an EQUIVALENT mutation —
  # the capture entry of a managed rule is not excluded-type, so it is not in $KNOWN and
  # the tally is the same with or without the subtraction (mutation row 7, measured
  # 2026-09-23: suite green, 63/63). It is kept because the two clauses cover each
  # other: reverting the narrowing ALONE keeps this count correct (row 5 reds only
  # G4-28), and reverting BOTH reds G4-25 on the count assert (row 6). Deleting
  # either one is caught; deleting one silently weakens the other.
  | "COUNT \([ $fz[] as $n | select(any($F[]; .name == $n)) ] | length) \($fz | length) \($O | map(select(is_in($KNOWN) and (is_in($GAINED) | not))) | length)",
    ( $F | group_by(.name) | map(select(length > 1) | .[0].name)[]
      | "FINDING FROZEN DUPLICATE: \($q)\(.)\($q) names more than one live workflow; the pin cannot tell which one the capture describes." ),
    ( $fz[] as $n
      | [ $F[] | select(.name == $n) ] as $ws
      | [ $CAP[] | select(.name == $n) ][0] as $c
      | if ($ws | length) == 0 then
          "FINDING FROZEN DELETED: \($q)\($n)\($q) is frozen in Terraform (legacy_trigger_conditions, ignore_changes = all) and absent from live Sentry (captured id \($c.id | tojson))."
        elif ($ws | length) > 1 then empty
        else $ws[0] as $w
          | (if $w.enabled != $c.enabled then
               (if $w.enabled != true then "FINDING FROZEN DISABLED: \($q)\($n)\($q) live enabled=\($w.enabled | tojson), captured \($c.enabled | tojson)."
                else "FINDING FROZEN DRIFT: \($q)\($n)\($q).enabled captured=\($c.enabled | tojson) live=\($w.enabled | tojson)." end)
             else empty end),
            (if ($w | dets) != ($c | dets) then "FINDING FROZEN MONITOR UNBIND: \($q)\($n)\($q).detectorIds captured=\($c | dets | tojson) live=\($w | dets | tojson)." else empty end),
            ( ($c | fields) as $cf | ($w | fields) as $wf
              | ($cf | keys_unsorted[]) as $k
              | select($cf[$k] != $wf[$k])
              | "FINDING FROZEN DRIFT: \($q)\($n)\($q).\($k) captured=\($cf[$k] | tojson) live=\($wf[$k] | tojson)." )
        end ),
    ( $O[] as $w
      | if ($w.name | type) != "string" or $w.name == "" then
          "FINDING UNMANAGED-FROZEN: an excluded-type live workflow (id \($w.id | tojson)) has an empty or non-string name; the pin cannot match it to the capture."
        elif ([ $O[] | select(.name == $w.name) ] | length) > 1 then
          "FINDING UNMANAGED-FROZEN DUPLICATE: \($q)\($w.name)\($q) names more than one live excluded-type workflow (this one id \($w.id | tojson)); a registered default is matched by id AND name, so a copy borrowing its name is not accepted."
        # BEFORE the KNOWN arm, deliberately: a managed rule that left scope must be
        # reported, never absorbed by an identity match.
        elif ($w | is_in($GAINED)) then
          "FINDING MANAGED RULE GAINED EXCLUDED TRIGGER: \($q)\($w.name)\($q) (id \($w.id | tojson)) is a Terraform-managed sentry_alert and live Sentry now carries trigger type(s) \([ $w.triggers.conditions[]? | select(.type as $t | any($ex[]; . == $t)) | .type ] | join(",")) the provider cannot express, so it left the fidelity scope and nothing compares it. An apply is NOT a repair: provider v0.15.7 reads that trigger by type only (legacy_trigger_conditions) and any write re-sends it as comparison: true or drops it, and scripts/sentry-issue-alert-create-tripwire.sh refuses such a write once a refresh surfaces it. Repair live state instead: PUT the workflow without that trigger, then GET it back — the rule returns to scope and is compared field-for-field. If the trigger is intended, the rule cannot stay a native sentry_alert: take it out of Terraform management in a reviewed PR."
        elif any($KNOWN[]; .id == ($w.id | tostring) and .name == $w.name) then empty
        elif any($KNOWN[]; .name == $w.name) then
          "FINDING UNMANAGED-FROZEN: \($q)\($w.name)\($q) (id \($w.id | tojson)) carries the name of a registered Sentry default under a DIFFERENT id, so it is not that default. GET it and compare with the registered id before trusting it."
        else
          "FINDING UNMANAGED-FROZEN: \($q)\($w.name)\($q) is live with an excluded trigger type (\([ $w.triggers.conditions[]?.type ] | join(","))), is not frozen in Terraform, and is in neither the committed capture nor apps/web-platform/infra/sentry/vendor-default-workflows.json, so neither projection side nor this pin checks it. If Sentry created it (createdBy null), register {id, name} in vendor-default-workflows.json."
        end )
' 2>"$jq_err")
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "ERROR: the frozen-rule pin did not evaluate (jq rc=$rc): $(tr '\n' ' ' <"$jq_err" | cut -c1-400). Cannot assert fidelity." >&2
  exit 1
fi
read -r _ frozen_live frozen_tf other_captured < <(grep -m1 '^COUNT ' <<<"$frozen_report")
echo "sentry_alert live fidelity: frozen-rule pin: compared ${frozen_live} of ${frozen_tf} Terraform-frozen rule(s) against the committed capture (${other_captured} other excluded-type live workflow(s) are registered Sentry defaults, matched by id and name, content not pinned)"
while IFS= read -r line; do
  [[ -n "$line" ]] && _finding "${line#FINDING }"
done < <(grep '^FINDING ' <<<"$frozen_report" || true)
if [[ "$frozen_live" -eq 0 ]]; then
  _finding "FROZEN PIN EMPTY: the frozen-rule pin compared nothing: none of the ${frozen_tf} Terraform-frozen rule(s) is live."
fi

if [[ "$findings" -eq 0 ]]; then
  # The verdict carries the mode. A grep for `PASS (all N` in a log must not be
  # satisfiable by a fixture run. `live fidelity FAILED` below is a CONTRACT with
  # the drift workflow (tests/scripts/test-sentry-alert-drift-workflow.sh W7);
  # the two PASS literals are pinned by this script's own suite.
  if [[ "$FIXTURE_MODE" -eq 1 ]]; then
    echo "sentry_alert live fidelity: PASS (FIXTURE — not live) (all ${ref_count} in-scope rules match the committed reference field-for-field)"
  else
    echo "sentry_alert live fidelity: PASS (all ${ref_count} in-scope rules match the committed reference field-for-field)"
  fi
  exit 0
fi

echo "ERROR: sentry_alert live fidelity FAILED — ${findings} divergence(s) between live Sentry and the reference at ${REFERENCE} (frozen-rule pin anchor: ${FROZEN_CAPTURE})." >&2
echo "A rule that exists, plans clean, and matches nothing is the failure this probe is for. Re-read the findings above: DELETED and DRIFT are repaired by an apply; DISABLED, MONITOR UNBIND and LOGICTYPE FLIP are live state an apply will not touch; UNMANAGED is a rule the root does not declare; FROZEN * are the Terraform-frozen rules (legacy_trigger_conditions, ignore_changes = all), compared against the committed capture: an apply will not touch them; UNMANAGED-FROZEN is an excluded-type live workflow that is neither Terraform-frozen nor in the capture; MANAGED RULE GAINED EXCLUDED TRIGGER is a Terraform-managed rule that left the comparison scope because live Sentry added a trigger type the provider cannot express, and an apply will NOT repair it (repair live state, or take the rule out of Terraform management)." >&2
exit 1
