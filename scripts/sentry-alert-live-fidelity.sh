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
# instead of the live GET; SENTRY_FIXTURE_UPTIME — the same for the uptime
# detectors GET, with SENTRY_UPTIME_TF_DIR (fixture mode only) overriding the
# directory the declared sentry_uptime_monitor blocks are counted in. See
# "SENTRY UPTIME" below (#6606).
#
# Exit 0 = every declared rule matches live, every in-scope live rule is declared,
#          and no live uptime monitor is unmanaged.
# Exit 1 = a divergence (an unmanaged uptime monitor included), or the probe could
#          not establish that it checked any rule. An UNAVAILABLE uptime check does
#          not change the exit code: it is carried by the SENTRY_UPTIME marker line.
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
FROZEN_CAPTURE="${SENTRY_FROZEN_CAPTURE_FILE:-$REPO_ROOT/knowledge-base/project/specs/archive/20261013-051752-fix-7650-sentry-alert-migration/phase34-live-workflows-capture-2026-09-09.json}"
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

# THE DESTINATION PINS, shared by both credentialed GETs (the uptime detectors
# below and the workflows in `fetch_rules`). Exact equality against a LITERAL,
# never against another variable: on this surface the environment is the
# adversary, and a pin that reads its expected value from the environment pins
# nothing (#7997). The literals are the Doppler `prd` SENTRY_API_HOST value and
# `variables.tf`'s `sentry_org` default. The message anchors (`refusing
# destination host`, `refusing org`) and exit 2 are the contract the drift
# workflow's unavailable-issue body greps (#8023); the value is rendered through
# `_safe`, never raw. Remedy for a drifted repository secret: `gh secret set
# SENTRY_API_HOST --body jikigai-eu.sentry.io` — a hostname, not a secret.
# Called on the LIVE branches only: the suite's fixture rows run with
# SENTRY_ORG=fixture and must not trip it.
_pin_destination() {
  : "${SENTRY_API_HOST:?SENTRY_API_HOST must be set (org-subdomain, e.g. jikigai-eu.sentry.io)}"
  case "$SENTRY_API_HOST" in
    "jikigai-eu.sentry.io") ;;
    *) printf 'ERROR: refusing destination host %s (pinned: jikigai-eu.sentry.io)\n' "$(_safe "$SENTRY_API_HOST")" >&2; exit 2 ;;
  esac
  case "$SENTRY_ORG" in
    "jikigai-eu") ;;
    *) printf 'ERROR: refusing org %s (pinned: jikigai-eu)\n' "$(_safe "$SENTRY_ORG")" >&2; exit 2 ;;
  esac
}

# The ONE scrubber for API-supplied strings (names, ids, leaf keys, URLs),
# prefixed to every jq program that prints one: C0/DEL, the two Unicode line
# separators, and the zero-width and bidi-override ranges (a name reordered by
# U+202E prints like another rule's). See the pin's comment on why live strings
# are scrubbed at all.
SAFE_JQ='def safe: tostring | gsub("[\u0000-\u001f\u007f\u2028\u2029\u200b-\u200f\u202a-\u202e\u2060-\u2064\u2066-\u2069\ufeff]"; "") | .[0:200];'

# Defined BEFORE the uptime section, which reports through it, so an uptime
# finding counts toward the one FAILED line and exit 1 the workflows read.
findings=0
_finding() { findings=$((findings + 1)); printf '  %s\n' "$*"; }

# ── SENTRY UPTIME: no unmanaged uptime monitor (Guard 1, #6606) ─────────────
# Sentry auto-detects uptime monitors from the app's traffic (mode 3; a
# re-detected one may start in mode 2). Its code turns auto-detection off after
# the first one and does not re-create a deleted monitor, but a setting flip or
# a monitor created in the UI is just as invisible to Terraform. Either way it
# bills a slot and no apply ever removes it. The PROPERTY: every live uptime
# detector in the org has `mode == 1` (manual: created by Terraform, the UI or the
# API; a mode != 1 row is always an auto-detected one), and the live count is not
# above the number of declared `resource "sentry_uptime_monitor"` blocks in
# apps/web-platform/infra/sentry/*.tf (ruling D-F-B): more live than declared is
# drift, and fewer is UNAVAILABLE (the check cannot vouch for a monitor it cannot
# see). A UI-made monitor is mode 1, so only the count can see it.
#
# PLACED BEFORE every rule-side `exit`, so a rule-side refusal cannot skip it.
# It never exits on its own except at the destination pin (exit 2, as above):
#   * drift        -> one `_finding` per monitor (`UPTIME UNMANAGED: id:mode:url`)
#   * unavailable  -> NO finding, so the rule-side verdict is untouched; the
#                     marker below carries it, and the drift workflow files the
#                     probe-unavailable issue from it. 0 declared blocks, a
#                     failed GET, a non-array body, a row of another type, a
#                     row whose id or mode is not a number or whose shape the
#                     row parse cannot read, live < declared (a declared monitor
#                     missing live, or the query lost visibility: `[]` must never
#                     read clean), and >= 100 rows (one page, no cursor) are all
#                     unavailable — never clean.
# ONE MARKER LINE at column 0, always printed (findings are indented, so a live
# URL cannot forge it):
#   SENTRY_UPTIME uptime_verdict=<clean|drift|unavailable> unmanaged=<n> live=<n|?> declared=<n>
# `unmanaged` is a LOWER BOUND on monitors nothing manages:
# max(rows with mode != 1, live - declared), so a mode-3 extra is not counted twice.
#
# FIXTURE SEAM, its suite ONLY: SENTRY_FIXTURE_UPTIME=<json file> is served
# instead of the live GET, announced loudly, and a clean verdict reads
# `uptime_verdict=fixture-clean`. SENTRY_UPTIME_TF_DIR overrides the declared
# directory IN FIXTURE MODE ONLY; on the live branch it is ignored, so no
# environment value can point the declared count somewhere else.
UPTIME_FIXTURE_MODE=0
[[ -n "${SENTRY_FIXTURE_UPTIME:-}" ]] && UPTIME_FIXTURE_MODE=1
UPTIME_TF_DIR="$REPO_ROOT/apps/web-platform/infra/sentry"
if [[ "$UPTIME_FIXTURE_MODE" -eq 1 && -n "${SENTRY_UPTIME_TF_DIR:-}" ]]; then
  UPTIME_TF_DIR="$SENTRY_UPTIME_TF_DIR"
fi

# DECLARED: `resource "sentry_uptime_monitor" "<label>" {` headers, counted after
# comments are stripped. Both .tf files name removed resources in comments, so a
# bare grep overcounts, and an overcount is the dangerous direction (it lets an
# unmanaged monitor pass). A header must be the first token on its line, so a
# `#` or `//` line comment never counts; a `/* … */` region that opens a line is
# skipped to its `*/` (a `/*` mid-line is NOT treated as a comment opener: the
# Sentry root's crontab strings carry `*/` and the strip must not eat them).
# A trailing `#`/`//` comment after the `{` is allowed.
uptime_tf_files=()
if [[ -d "$UPTIME_TF_DIR" ]]; then
  for f in "$UPTIME_TF_DIR"/*.tf; do [[ -r "$f" ]] && uptime_tf_files+=("$f"); done
fi
uptime_declared=0
if [[ ${#uptime_tf_files[@]} -gt 0 ]]; then
  uptime_declared=$(awk '
    FNR == 1 { inc = 0 }
    {
      line = $0
      if (inc) { p = index(line, "*/"); if (!p) next; line = substr(line, p + 2); inc = 0 }
      sub(/^[[:space:]]+/, "", line)
      while (substr(line, 1, 2) == "/*") {
        p = index(substr(line, 3), "*/")
        if (!p) { inc = 1; next }
        line = substr(line, p + 4); sub(/^[[:space:]]+/, "", line)
      }
      if (line ~ /^resource[[:space:]]+"?sentry_uptime_monitor"?[[:space:]]+"?[A-Za-z_][A-Za-z0-9_-]*"?[[:space:]]*\{[[:space:]]*((#|\/\/).*)?$/) n++
    }
    END { print n + 0 }' "${uptime_tf_files[@]}")
fi

uptime_json=''
uptime_unavail=''
if [[ "$UPTIME_FIXTURE_MODE" -eq 1 ]]; then
  echo "::warning::sentry uptime: FIXTURE MODE — SENTRY_FIXTURE_UPTIME is set, so this run did NOT read live Sentry uptime detectors. Its verdict reads fixture-clean and says NOTHING about production." >&2
  if [[ -r "$SENTRY_FIXTURE_UPTIME" ]]; then
    uptime_json=$(cat "$SENTRY_FIXTURE_UPTIME")
  else
    uptime_unavail="the fixture file is not readable"
  fi
else
  _pin_destination
  # Same transport confinement as `fetch_rules` (flag ORDER pinned by the suite,
  # bearer header on STDIN). rc captured on its own line: a failed GET is
  # UNAVAILABLE for this section and must not abort the rule-side check.
  set +e
  uptime_json=$(printf 'Authorization: Bearer %s\n' "$SENTRY_AUTH_TOKEN" |
    curl --disable --noproxy '*' --proto '=https' -g -fsS --max-time 15 \
      --header @- \
      "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/detectors/?query=type:uptime_domain_failure&project=-1&per_page=100")
  uptime_rc=$?
  set -e
  [[ "$uptime_rc" -eq 0 ]] || uptime_unavail="the detectors GET failed (curl rc=${uptime_rc})"
fi

uptime_live='?'
uptime_bad_mode=0
uptime_lines=''
if [[ -z "$uptime_unavail" ]]; then
  if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$uptime_json"; then
    uptime_unavail="the detectors response is not a JSON array"
  elif (( $(jq 'length' <<<"$uptime_json") >= 100 )); then
    uptime_unavail="the detectors payload returned >= 100 rows, this fetch's unpaginated ceiling (pagination ceiling); a detector on page 2 would go unseen"
  elif ! jq -e 'all(.[]; type == "object" and .type == "uptime_domain_failure")' >/dev/null 2>&1 <<<"$uptime_json"; then
    uptime_unavail="a detectors row is not of type uptime_domain_failure, so the query filter was not honoured"
  elif ! jq -e 'all(.[]; ((.id | tostring) | test("^[0-9]+$")) and ((try (.config.mode // .dataSources[0].queryObj.mode) catch null) | type == "number"))' >/dev/null 2>&1 <<<"$uptime_json"; then
    # A non-numeric id could start a listing line with `::` (a workflow
    # command), and a mode this parse cannot read is not evidence of drift.
    uptime_unavail="a detectors row has a non-numeric id or mode, or a shape the row parse cannot read"
  else
    uptime_live=$(jq 'length' <<<"$uptime_json")
    # One TSV line per detector: id, mode, the URL reduced to scheme://host/path,
    # and the name. The drift issue body is PUBLIC, so userinfo, port, query and
    # fragment are dropped here, and every field goes through `safe`. An authority
    # carrying `@` or a backslash prints as `<userinfo-host>`, never as the part
    # after the `@`: that part is attacker-chosen and could name the real host.
    # rc captured on its own line: a parse failure is UNAVAILABLE, never an exit
    # that skips the rule-side check.
    set +e
    uptime_lines=$(jq -r "${SAFE_JQ}"'
      def url_shape:
        if type != "string" then "<no-url>" else
          (split("?")[0] | split("#")[0]) as $u
          | ([ $u | capture("^(?<s>[A-Za-z][A-Za-z0-9+.-]*)://(?<r>.*)$") ][0]) as $c
          | if $c == null then "<unparsed-url>" else
              ($c.r | index("/")) as $i
              | (if $i == null then $c.r else $c.r[:$i] end) as $a
              # A host that can be shown must be plain ASCII host characters. An
              # authority with userinfo (`@`, or a backslash some parsers read as
              # `/`), an empty one (`https:///…`, which a WHATWG parser resolves
              # past), or any other byte (a homoglyph such as Cyrillic `а`) prints
              # as a placeholder, so a crafted URL cannot display as the real host.
              | (if ($a | test("[@\\\\]")) then "<userinfo-host>"
                 elif ($a == "" or ($a | test("^[A-Za-z0-9.:\\[\\]-]+$") | not)) then "<unprintable-host>"
                 else ($a | sub(":[0-9]*$"; "")) end) as $h
              | (if $i == null then "" else $c.r[$i:] end) as $p
              | "\($c.s)://\($h)\($p)"
            end
        end;
      .[] | (.config.mode // .dataSources[0].queryObj.mode) as $m
          | [ (.id | safe),
              (if $m == 1 then "1" else ($m | tojson) end),
              (.dataSources[0].queryObj.url | url_shape | safe),
              ((.name // "<no-name>") | safe) ] | join("\t")' <<<"$uptime_json")
    uptime_lines_rc=$?
    set -e
    if [[ "$uptime_lines_rc" -ne 0 ]]; then
      uptime_unavail="the detectors rows could not be parsed (jq rc=${uptime_lines_rc})"
    elif (( uptime_live < uptime_declared )); then
      uptime_unavail="live=${uptime_live} < declared=${uptime_declared}: a declared monitor is missing live, or the detectors query lost visibility of it"
    fi
    if [[ -z "$uptime_unavail" && "$uptime_declared" -eq 0 ]]; then
      uptime_unavail="zero resource \"sentry_uptime_monitor\" blocks parsed from ${UPTIME_TF_DIR}/*.tf (${#uptime_tf_files[@]} file(s) read), so there is nothing to compare the live set against"
    fi
  fi
elif [[ "$uptime_declared" -eq 0 ]]; then
  uptime_unavail+="; and zero resource \"sentry_uptime_monitor\" blocks parsed from ${UPTIME_TF_DIR}/*.tf"
fi

if [[ -n "$uptime_unavail" ]]; then
  echo "ERROR: sentry uptime: UNAVAILABLE — ${uptime_unavail}. This run says NOTHING about unmanaged uptime monitors." >&2
  echo "SENTRY_UPTIME uptime_verdict=unavailable unmanaged=0 live=${uptime_live} declared=${uptime_declared}"
else
  while IFS=$'\t' read -r up_id up_mode up_url up_name; do
    [[ -n "$up_id" ]] || continue
    if [[ "$up_mode" != "1" ]]; then
      uptime_bad_mode=$((uptime_bad_mode + 1))
      _finding "UPTIME UNMANAGED: $(_safe "${up_id}:${up_mode}:${up_url}") name=$(_safe "$up_name") — this uptime monitor is not in manual mode (1), so Sentry auto-detected it. DELETE it through the API (an import block fails sentry-adoption-plan-assert.sh): GET https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/detectors/<id>/, DELETE the same URL, GET again expecting 404. Re-running the apply does not fix it."
    fi
  done <<<"$uptime_lines"
  uptime_excess=$(( uptime_live - uptime_declared ))
  if (( uptime_excess > 0 )); then
    _finding "UPTIME UNMANAGED: live=${uptime_live} > declared=${uptime_declared} — the org has more uptime monitors than resource \"sentry_uptime_monitor\" blocks in apps/web-platform/infra/sentry/*.tf, so at least ${uptime_excess} of them is managed by nothing. Keep the monitor whose id Terraform holds: the \`sentry_uptime_monitor.<name>: Refreshing state... [id=<n>]\` line (or \`Creation complete after ... [id=<n>]\` on the run that created it) in the latest apply-sentry-infra run log (names are not unique in Sentry, so a name match is not proof). DELETE only the others through the API (an import block fails sentry-adoption-plan-assert.sh): GET https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/detectors/<id>/, DELETE the same URL, GET again expecting 404. If the latest apply-sentry-infra run did not finish, the extras may be monitors it was about to destroy: re-run that apply first. Live mode-1 monitors (one of these is the extra unless a mode != 1 finding above names it):"
    while IFS=$'\t' read -r up_id up_mode up_url up_name; do
      [[ -n "$up_id" && "$up_mode" == "1" ]] || continue
      _finding "         $(_safe "${up_id}:${up_mode}:${up_url}") name=$(_safe "$up_name")"
    done <<<"$uptime_lines"
  fi
  uptime_unmanaged=$uptime_bad_mode
  (( uptime_excess > uptime_unmanaged )) && uptime_unmanaged=$uptime_excess
  if [[ "$uptime_unmanaged" -gt 0 ]]; then
    uptime_verdict=drift
  elif [[ "$UPTIME_FIXTURE_MODE" -eq 1 ]]; then
    uptime_verdict='fixture-clean'
  else
    uptime_verdict=clean
  fi
  echo "SENTRY_UPTIME uptime_verdict=${uptime_verdict} unmanaged=${uptime_unmanaged} live=${uptime_live} declared=${uptime_declared}"
fi

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
  # THE PINS, inside the live branch and after the fixture `return` — the suite's
  # fixture rows run with SENTRY_ORG=fixture and must not trip them. Defined once
  # in `_pin_destination` (above the uptime section, which calls it too).
  _pin_destination
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

# SAFE_JQ (the one scrubber for API-supplied strings) and `_finding` are defined
# above the uptime section, which reports through both.

# THE HAND-OFF LEDGER. The per-rule loop below defers some declared names to the
# frozen-rule pass instead of reporting them itself. A deferral is only safe if
# something downstream actually classifies the name — and for one shape it does
# not (see the reconciliation after the pin). Every deferral is recorded here and
# reconciled at the end, so "handed off" can never read as "compared".
handed_off=()

echo "sentry_alert live fidelity: comparing ${ref_count} declared rule(s) against ${live_count} live in-scope rule(s)"

# ── Per-rule, field-by-field ────────────────────────────────────────────────
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  if ! jq -e --arg n "$name" 'has($n)' >/dev/null <<<"$live_proj"; then
    # ABSENT FROM THE PROJECTION IS NOT ABSENT FROM SENTRY. `project_live` keeps
    # every IN-SCOPE workflow, so a declared name that is missing here while the
    # RAW payload still carries it means the live rule left the scope — it gained
    # a trigger type the provider cannot express (Sentry CAN add one to an existing
    # workflow; #8267 is the adjacent case, where Seer CREATED a workflow carrying
    # one). That is a different failure with a
    # different remedy: `DELETED or RENAMED` says "an apply can recreate it", and
    # an apply is NOT a repair here. Hand it to the frozen-rule pass below, which
    # reports it as MANAGED RULE GAINED EXCLUDED TRIGGER.
    #
    # THE DEFERRAL IS RECORDED, NOT ASSUMED. The census can only classify members
    # of `$O`, which excludes every Terraform-FROZEN name — so a declared name
    # whose live bearer is frozen lands in `$F`, is compared against the CAPTURE
    # rather than against the reference, and emits nothing at all when it matches
    # the capture. Measured: that shape printed `PASS (all 29 in-scope rules
    # match …)` at rc=0 while 28 were compared, which is the silent-clean verdict
    # this probe exists to prevent. The ledger plus the reconciliation after the
    # pin is what makes the hand-off total; it is also what keeps the PASS line's
    # `${ref_count}` honest, since an unreconciled deferral always emits.
    if jq -e --arg n "$name" 'any(.[]; .name == $n)' >/dev/null <<<"$live_json"; then
      handed_off+=("$name")
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
          # A set difference, not two full arrays: cron-monitor-failure binds ~59 ids (#8630).
          only_ref=$(jq -nc --argjson a "$local_ref" --argjson b "$local_live" '($a // []) - ($b // [])')
          only_live=$(jq -nc --argjson a "$local_ref" --argjson b "$local_live" '($b // []) - ($a // [])')
          _finding "MONITOR UNBIND: '$name'.detectorIds only-declared=$only_ref only-live=$only_live — the rule is bound to a different detector set (or none), so those detectors page nobody while it still appears healthy." ;;
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
          done < <(jq -r --argjson a "$local_ref" --argjson b "$local_live" -n "${SAFE_JQ}"'
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
              | "\($k | safe): declared=\($ca) live=\($li)" )
          ') ;;
        *)
          _finding "DRIFT: '$name'.$field declared=$local_ref live=$local_live" ;;
      esac
    fi
  done < <(printf '%s\n' enabled detectorIds frequency triggerLogicType triggerConditions actionFilters)
done < <(jq -r 'keys[]' <<<"$ref_proj")

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
frozen_raw=''
legacy_lines=0
if [[ ${#tf_files[@]} -gt 0 ]]; then
  frozen_raw=$(awk '
    /^resource "sentry_alert" "[^"]*"[[:space:]]*\{[[:space:]]*$/ { inb = 1; nm = ""; leg = 0; next }
    inb && /^\}/ { if (leg && nm != "") print nm; inb = 0; next }
    inb && /^  name[[:space:]]*=[[:space:]]*"[^"]*"/ { v = $0; sub(/^  name[[:space:]]*=[[:space:]]*"/, "", v); sub(/".*$/, "", v); nm = v; next }
    inb && /^  legacy_trigger_conditions[[:space:]]*=[[:space:]]*\[[[:space:]]*"/ { leg = 1; next }
  ' "${tf_files[@]}")
  frozen_names_json=$(jq -R -s -c 'split("\n") | map(select(. != "")) | unique' <<<"$frozen_raw")
  # A frozen block this awk cannot read (e.g. a multi-line list, which terraform
  # fmt accepts) would drop out of the pin SILENTLY, and a zero floor only sees
  # the loss of every name. So every non-empty top-level list must yield a name.
  legacy_lines=$(awk '/^  legacy_trigger_conditions[[:space:]]*=/ && !/=[[:space:]]*(\[[[:space:]]*\]|null)[[:space:]]*(#.*)?$/ { n++ } END { print n + 0 }' "${tf_files[@]}")
fi
frozen_tf_n=$(jq 'length' <<<"$frozen_names_json")
frozen_raw_n=$(grep -c . <<<"$frozen_raw" || true)
if [[ "$frozen_raw_n" -ne "$legacy_lines" ]]; then
  echo "ERROR: ${FROZEN_TF_DIR}/*.tf carries ${legacy_lines} non-empty top-level legacy_trigger_conditions line(s) but the frozen-name derivation read ${frozen_raw_n} frozen rule(s). A frozen block it could not parse (a multi-line list, a reformatted name) would silently leave the frozen-rule pin. Write each list on one line as legacy_trigger_conditions = [\"<type>\"]. Refusing." >&2
  exit 1
fi
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

# ── The other direction: an in-scope live rule the root does not declare ────
# Not cosmetic. A rule in scope that Terraform does not manage is one an apply
# will never repair, and the next reader of `issue-alerts.tf` will not know it
# exists. Since the reference is projected from the plan, UNMANAGED here means
# exactly "undeclared" — never "the reference file is stale" (that is the
# reference gate's job, at PR time).
#
# A TERRAFORM-FROZEN NAME IS NOT UNDECLARED (#4781). A frozen rule whose live
# copy loses its excluded trigger enters this scope, where the committed
# reference cannot declare it (tf_legacy_floor); it is reported as FROZEN RULE
# LEFT SCOPE, never as UNMANAGED ("delete it in Sentry"). Reclassified, never
# skipped: a skip is safe only while every frozen capture entry carries an
# excluded type, and nothing enforces that.
#
# Classified whole in jq (a `keys[] | read` split names at LF, F36) and printed
# through `safe` with the live id, because a scrubbed name can read exactly like
# another rule's. Runs after the frozen-name refusals above; a run that refuses
# there prints no UNMANAGED/LEFT lines, but the per-rule DRIFT lines print first.
set +e
undeclared_report=$(jq -r --argjson lj "$live_json" --argjson rp "$ref_proj" --argjson fz "$frozen_names_json" \
    --slurpfile cap "$FROZEN_CAPTURE" "${SAFE_JQ}"'
  # Tab-separated with no empty field: an empty middle field collapses under
  # IFS=$tab and shifts every later field left.
  keys[] | select(. as $n | $rp | has($n) | not) | . as $raw
  | ($raw | safe) as $s
  | ([ $lj[] | select(.name == $raw) | .id | safe ] | if length == 0 then "?" else join(",") end) as $ids
  | (if $s == "" then "<no printable characters>" else $s end) as $disp
  | (if $s != $raw then "altered" else "-" end) as $alt
  | if ($fz | index($raw)) != null then
      "LEFT\t\($disp)\t\($ids)\t\([ $cap[0][] | select(.name == $raw) | .id | safe ][0] // "?")\t\($alt)"
    else "UNMANAGED\t\($disp)\t\($ids)\t-\t\($alt)" end
' <<<"$live_proj" 2>"$jq_err")
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "ERROR: the undeclared-rule classification did not evaluate (jq rc=$rc): $(tr '\n' ' ' <"$jq_err" | cut -c1-300). Cannot assert fidelity." >&2
  exit 1
fi
while IFS=$'\t' read -r cls name ids cap_id alt; do
  altered=''
  [[ "$alt" == altered ]] && altered=' [DISPLAY NAME ALTERED: the live name carries control characters or exceeds 200 characters, so it is NOT necessarily the rule it resembles; act by id only.]'
  case "$cls" in
    LEFT)
      _finding "FROZEN RULE LEFT SCOPE: '$name' (live id $ids; captured id $cap_id) is Terraform-frozen (legacy_trigger_conditions, ignore_changes = all), but its live workflow no longer carries an excluded trigger type, so it entered the comparison scope, where the committed reference cannot declare it. It is NOT undeclared. If the live id is the captured id, PUT its capture entry back (PUT /api/0/organizations/<org>/workflows/<captured id>/, body from ${FROZEN_CAPTURE}) and GET it to compare; if it is not, it is a same-name copy: GET both ids and remove the one that is not the captured id. Never delete the captured id or register it as a vendor default.${altered}" ;;
    UNMANAGED)
      _finding "UNMANAGED: '$name' (live id $ids) is live and in scope but declared nowhere in apps/web-platform/infra/sentry/ (absent from the reference projected from the plan). GET it by id first: if that id belongs to a rule the reference declares under another name (a UI rename; see any DELETED or RENAMED finding above) or is a Terraform-frozen rule's captured id, restore its name instead. Otherwise adopt it as a sentry_alert or delete it in Sentry. If Sentry created it (createdBy null) with a trigger type the provider cannot express, register it instead: add the type to \`def excluded\` in tests/scripts/lib/sentry-alert-projection.jq and {id, name} to apps/web-platform/infra/sentry/vendor-default-workflows.json (#8267).${altered}" ;;
  esac
done <<<"$undeclared_report"

set +e
frozen_report=$(jq -r -n --arg q "'" --argjson ex "$excluded_json" --argjson live "$live_json" \
    --argjson fz "$frozen_names_json" --slurpfile cap "$FROZEN_CAPTURE" \
    --slurpfile vd "$VENDOR_DEFAULTS" \
    --argjson refnames "$(jq -c 'keys' <<<"$ref_proj")" "${SAFE_JQ}"'
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
  # LIVE STRINGS ARE SCRUBBED BEFORE THEY ARE PRINTED. The probe stdout is
  # `cat`-ed verbatim into a PUBLIC issue body between ``` fences, and a workflow
  # name is written by the vendor whose unilateral edits this probe exists to
  # detect. Measured: a name carrying a newline terminates the finding line, and
  # the remainder renders as markdown once it escapes the fence (a 3-space-indented
  # fence closes it), and reaches the Actions runner as its own `::`-prefixed line.
  # `_safe` already does this for the two env values; this is the same treatment
  # for the values the API supplies. Cap well under the issue-body limit so one name cannot push the
  # body past it and abort the filer. `safe` is SAFE_JQ, prefixed above.
  # {id, name} membership, used for KNOWN and for GAINED alike. BOTH sides are
  # `tostring`-normalised, not only on the probe side: $KNOWN is built from
  # `{id: (.id | tostring), …}` while $GAINED holds RAW live workflows, so a
  # one-sided normalisation compares a number against a string and returns false
  # for a member that IS present. Measured in jq: with a numeric id the raw form
  # answers false where the string form answers true. The live API returns string
  # ids today, so every fixture derived from the capture passes either way — which
  # is exactly why this cannot be caught by a suite row.
  def is_in($set): . as $w | any($set[]; (.id | tostring) == ($w.id | tostring) and .name == $w.name);
  $cap[0] as $CAP
  # THE CAPTURE HALF OF KNOWN IS NARROWED to the capture entries this set is
  # ABOUT: excluded-type, and not frozen in Terraform. Built from every capture
  # entry (as it was), KNOWN held all 28 managed rules too — so a managed rule
  # that left the scope, or one dropped from Terraform while still live, matched
  # by {id, name} and was accepted in silence with rc=0, having been compared by
  # nothing. The registry half is unchanged: those entries are excluded-type by
  # construction (that is why they are registered) — asserted, not enforced here.
  # The `$fz` clause is a structural invariant rather than a measured guard: every
  # arm that consults $KNOWN requires `.name == $w.name` and every $w comes from
  # $O, which already excludes frozen names, so dropping it is an equivalent
  # mutation. It stays so the set means what its comment says it means.
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
  # The third field counts registered defaults ONLY: KNOWN and not GAINED, so the
  # tally agrees with the finding arm, which puts GAINED before KNOWN. The case it
  # covers is the REGISTRY half, which the narrowing above does not touch: a name
  # carried by both alert-reference.json and vendor-default-workflows.json is
  # reported as GAINED and would otherwise also be counted as a registered default.
  # Against the CAPTURE half the subtraction is an equivalent mutation (the capture
  # entry of a managed rule is not excluded-type, so it is not in $KNOWN) — measured
  # 2026-09-23, mutation row 7 survived at 63/63, and no fixture instantiates the
  # registry overlap, so that row says nothing about this clause either way.
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
          # The pin matches by NAME; a same-name workflow under another id (the
          # captured rule deleted, a copy left) would otherwise compare clean.
          | (if ($w.id | tostring) != ($c.id | tostring) then
               "FINDING FROZEN ID MISMATCH: \($q)\($n)\($q) live id \($w.id | safe | tojson), captured id \($c.id | tojson): the live workflow bearing this frozen name is not the captured rule. GET both ids; if the captured id is gone, recreate it from the capture entry per FROZEN DELETED and remove the copy."
             else empty end),
            (if $w.enabled != $c.enabled then
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
          "FINDING UNMANAGED-FROZEN: an excluded-type live workflow (id \($w.id | safe | tojson)) has an empty or non-string name; the pin cannot match it to the capture."
        elif ([ $O[] | select(.name == $w.name) ] | length) > 1 then
          "FINDING UNMANAGED-FROZEN DUPLICATE: \($q)\($w.name | safe)\($q) names more than one live excluded-type workflow (this one id \($w.id | tojson)); a registered default is matched by id AND name, so a copy borrowing its name is not accepted.\(if ($w.name as $n | $refnames | index($n)) != null then " This name is ALSO declared in the Sentry root, so one of these may be a Terraform-managed rule that gained an excluded trigger: GET both ids before touching either, and register neither as a vendor default." else "" end)"
        # BEFORE the KNOWN arm, deliberately: a managed rule that left scope must be
        # reported, never absorbed by an identity match.
        elif ($w | is_in($GAINED)) then
          "FINDING MANAGED RULE GAINED EXCLUDED TRIGGER: \($q)\($w.name | safe)\($q) (id \($w.id | safe | tojson)) carries the NAME of a sentry_alert the reference declares — matched by name only, because the Terraform side carries no id for a rule it would Create, so GET this id and compare it against Terraform state before writing to it; if the name is declared but this id is not the managed rule, the managed one is DELETED and Terraform still points at the old id. Live Sentry now carries trigger type(s) \([ $w.triggers.conditions[]? | select(.type as $t | any($ex[]; . == $t)) | .type ] | join(",")) the provider cannot express, so it left the fidelity scope and nothing compares it. An apply is NOT a repair: provider v0.15.7 reads that trigger by type only (legacy_trigger_conditions) and any write re-sends it as comparison: true or drops it, and scripts/sentry-issue-alert-create-tripwire.sh refuses such a write once a refresh surfaces it. Repair live state instead: GET /api/0/organizations/<org>/workflows/<id>/, remove that trigger from the body, PUT it back, then GET it again — the rule returns to scope and is compared field-for-field. If the trigger is intended, the rule cannot stay a native sentry_alert: take it out of Terraform management in a reviewed PR with removed { from = sentry_alert.<label> lifecycle { destroy = false } } — deleting the block plans a DESTROY instead, which the destroy gate reds."
        elif ($w | is_in($KNOWN)) then empty
        elif any($KNOWN[]; .name == $w.name) then
          "FINDING UNMANAGED-FROZEN: \($q)\($w.name | safe)\($q) (id \($w.id | safe | tojson)) carries the name of a registered Sentry default under a DIFFERENT id, so it is not that default. GET it and compare with the registered id before trusting it."
        else
          "FINDING UNMANAGED-FROZEN: \($q)\($w.name | safe)\($q) is live with an excluded trigger type (\([ $w.triggers.conditions[]?.type | safe ] | join(","))), is not frozen in Terraform, and is in neither the committed capture nor apps/web-platform/infra/sentry/vendor-default-workflows.json, so neither projection side nor this pin checks it. FIRST `git grep -nw <name> -- apps/web-platform/infra/sentry/`: if the name IS declared there it is Terraform-managed and must NOT be registered as a vendor default (the apply job projects its reference from the plan, where a refreshed legacy trigger takes the rule out of tf scope, so a managed rule that gained an excluded trigger reaches THIS arm rather than the GAINED one). Only if it is undeclared, and Sentry created it (createdBy null), register {id, name} in vendor-default-workflows.json."
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

# ── RECONCILE THE HAND-OFF ──────────────────────────────────────────────────
# Every name the per-rule loop deferred must have been NAMED by the pin. A
# deferral the pin never mentions was compared by nothing: the loop skipped it
# because some live workflow bears the name, and the pin skipped it because the
# workflow is either Terraform-frozen and equal to its capture entry, or absent
# from the census for a reason the loop could not see. Either way the REFERENCE's
# declaration of that name went unchecked, and without this the run reports a
# clean verdict over it (measured: rc=0, `all 29 in-scope rules match`, 28
# compared). Matching on the quoted name is the same anchor every pin finding
# prints, so a name that appears in ANY pin finding counts as classified.
for _ho in ${handed_off[@]+"${handed_off[@]}"}; do
  grep -qF -- "'${_ho}'" <<<"$frozen_report" && continue
  _finding "UNRECONCILED HAND-OFF: '$(_safe "$_ho")' is declared in the Sentry root and some live workflow bears that name, but NOTHING compared the declaration: the per-rule loop deferred it to the frozen-rule pin, and the pin never named it. The reference entry for this rule is UNVERIFIED by this run. A well-formed Terraform projection cannot declare a frozen name (tf_legacy_floor in tests/scripts/lib/sentry-alert-projection.jq refuses it), so on the daily job compare the committed reference against apps/web-platform/infra/sentry/*.tf and regenerate alert-reference.json per that directory README if they disagree. Touch NOTHING in Sentry."
done

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
echo "A rule that exists, plans clean, and matches nothing is the failure this probe is for. Re-read the findings above: UPTIME UNMANAGED is a live Sentry uptime monitor Terraform does not manage (mode != 1, or more live than declared): if the latest apply-sentry-infra run on main did not finish, re-run it first, otherwise DELETE it through the API after checking its name against the declared blocks (a finished apply does not fix it); DELETED and DRIFT are repaired by an apply; DISABLED, MONITOR UNBIND and LOGICTYPE FLIP are live state an apply will not touch; UNMANAGED is a rule the root does not declare; FROZEN RULE LEFT SCOPE is a Terraform-frozen rule whose live copy lost its excluded trigger: repair it from the capture, never delete the captured id; FROZEN * are the Terraform-frozen rules (legacy_trigger_conditions, ignore_changes = all), compared against the committed capture: an apply will not touch them; UNMANAGED-FROZEN is an excluded-type live workflow that is neither Terraform-frozen nor in the capture; MANAGED RULE GAINED EXCLUDED TRIGGER is a Terraform-managed rule that left the comparison scope because live Sentry added a trigger type the provider cannot express, and an apply will NOT repair it (repair live state, or take the rule out of Terraform management)." >&2
exit 1
