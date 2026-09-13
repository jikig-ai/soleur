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
  # `projects/{org}/{proj}/rules/`: that family is under brownout and would make
  # this probe red on Sentry's calendar rather than on drift.
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
  _finding "UNMANAGED: '$name' is live and in scope but declared nowhere in apps/web-platform/infra/sentry/ (absent from the reference projected from the plan). Adopt it as a sentry_alert or delete it in Sentry."
done < <(jq -r 'keys[]' <<<"$live_proj")

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

echo "ERROR: sentry_alert live fidelity FAILED — ${findings} divergence(s) between live Sentry and the reference at ${REFERENCE}." >&2
echo "A rule that exists, plans clean, and matches nothing is the failure this probe is for. Re-read the findings above: DELETED and DRIFT are repaired by an apply; DISABLED, MONITOR UNBIND and LOGICTYPE FLIP are live state an apply will not touch; UNMANAGED is a rule the root does not declare." >&2
exit 1
