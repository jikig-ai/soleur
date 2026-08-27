#!/usr/bin/env bash
# lint-supabase-deprecated-endpoints.sh — two properties over every tracked non-doc file that
# talks to the Supabase Management API:
#
#   ARM 1 (deprecation). No file calls a Management API path Supabase has marked deprecated,
#          except under a dated, inline-justified waiver.
#   ARM 2 (host pin).    Every such caller pins the HOST SPAN to the literal
#          https://api.supabase.com, so no env-controlled value can redirect a PAT-bearing
#          request. The PAT here is an ACCOUNT-level token; a redirect is credential exfil.
#
# ─────────────────────────────────────────────────────────────────────────────────────────
# WHY ARM 1 IS FILE-SCOPED AND NOT LINE-SCOPED. A line-scoped implementation of arm 1 is
# fail-open and would ship green. BOTH live `advisors/security` calls sit far below the
# assignment that resolves their host: `.github/workflows/apply-inngest-rls.yml:238` is 131
# lines BELOW its `API="https://api.supabase.com"` at `:107`, and
# `scripts/supabase-advisor-scan.sh:159` is 101 lines below its `API=` at `:58`. The same
# split holds in `apply-inngest-rls-dev.yml` (`:113` vs `:134,157,171`) and
# `apps/web-platform/infra/inngest-rls/anon-probe.sh` (`:30` vs `:55,66`). Line-scoped, this
# guard finds ZERO deprecated paths and the ratchet reports green — the exact class closed by
# `924994b2f fix(gates): close four fail-open gates that reported success while doing
# nothing`. So `$API` / `${REF}` / `$PROJECT_REF` are resolved WITHIN the file first.
#
# WHY ARM 2 INVERTS THE QUANTIFIER. Arm 2 must NOT key its assembly on the pinned literal.
# A caller whose host has been redirected does not CONTAIN the literal, so a literal-keyed
# assembly never enumerates the exfil shape it exists to catch:
# `API="${SUPABASE_API_HOST:-https://evil.example.com}"` would pass silently while the benign
# `API="${SUPABASE_API_HOST:-https://api.supabase.com}"` reddens. Property 5 would be
# unenforceable by construction. Therefore arm 2's assembly is keyed on the CALLER SHAPE
# (`/v1/projects/` or a PAT variable) and MEMBERSHIP IS THE ASSERTION: every member either
# contains the bare literal or sits on the dated allowlist below. A redirected host is then a
# MISSING MEMBER, which this guard can see.
#
# WHY ARM 2 ASSERTS THE HOST SPAN ONLY. Scheme through authority, nothing after the first
# `/v1`. The four existing per-script guards assert their whole `API=` LINE is expansion-free,
# which is right for a bare shell assignment and wrong as an assembly rule: PATH interpolation
# is legitimate and near-universal. A whole-line check is RED on ~8 correctly-pinned files
# including `apps/web-platform/lib/supabase/service.ts:66`, a template literal whose *path*
# interpolates `${projectRef}`.
#
# ─────────────────────────────────────────────────────────────────────────────────────────
# THE PATHSPEC, VERBATIM. Both assemblies are computed with (from the repo root):
#
#   git grep -lI --fixed-strings -e 'https://api.supabase.com' \
#       -- . ':(exclude)*.md' ':(exclude)*.mdx' ':(exclude)knowledge-base/**'
#   git grep -lIE -e '/v1/projects/|SUPABASE_ACCESS_TOKEN|SUPABASE_PAT' \
#       -- . ':(exclude)*.md' ':(exclude)*.mdx' ':(exclude)knowledge-base/**'
#
# `tests/` AND `*.test.sh` ARE DELIBERATELY IN SCOPE, and the decision is load-bearing.
# `tests/scripts/test-supabase-advisor-scan.sh:321` is a fully-formed `curl` to the deprecated
# endpoint, at rest in a tracked file — a third `advisors/security` CALL CONSTRUCT. Stated
# precisely, because the distinction matters and the looser claim was wrong: that line is a
# mutation stub, and the suite executes it under `PATH="$STUB_DIR:$PATH"`, so it resolves to a
# synthetic `curl` and never reaches the network. It is not a live call.
#
# It is still counted, deliberately. This census measures DEPRECATED-PATH LITERALS THE
# EXTRACTOR CAN SEE, not production traffic: when a deprecated endpoint is withdrawn, a
# hard-coded path in a test breaks the test exactly as a path in a script breaks the script,
# and a guard that can see one but not the other is the fail-open shape this file exists to
# prevent. A pathspec that hid it would also buy the tidy "RED on two call sites" headline by
# narrowing what the guard can see, which is the same move one level up. Excluding `*.test.sh`
# would additionally drop `supabase-advisor/scan-workflow.test.sh` and
# `postgrest-reload-schema.test.sh` — the very per-invocation snapshots this layer sits above.
# The assertion-string false positives that motivated an exclusion are handled by the CALL
# CONSTRUCT anchor instead (see below), which is `cq-assert-anchor-not-bare-token` applied
# correctly rather than routed around. Consequence: the census counts THREE `advisors/security`
# call sites, not two.
#
# THE CALL-CONSTRUCT ANCHOR. Detection requires `<host-token>/v1/projects/…<deprecated-path>`
# on a non-comment line, never a bare token. This is what keeps the guard off the
# guard-of-the-guard: `apps/web-platform/test/server/inngest/cron-supabase-advisor-scan.test.ts:95`
# asserts the ABSENCE of a Management API call while itself containing the string
# `advisors/security`, and `tests/scripts/test-supabase-advisor-scan.sh:78` routes a FAKE
# server on `*"/advisors/security"*)`. Neither carries a host token, so neither is a call.
# `apps/web-platform/infra/cron-egress-allowlist.txt:66` is the bare hostname `api.supabase.com`
# with no scheme and no path; it is in NEITHER assembly by construction, not by exclusion.
#
# THE DENYLIST IS A HAND-CURATED SUBSET OF A VENDOR-PUBLISHED SET. The live Management API
# spec marks FIVE paths `deprecated: true`, not the two denied here, and NO deprecated path
# carries a sunset date in the spec — so a spec diff can detect deprecation but cannot detect
# an announced removal, which is why the removal date below is carried by hand. The three
# unlisted paths have zero in-repo non-doc callers. Measurement, counts and method:
# knowledge-base/project/specs/feat-one-shot-supabase-analytics-logs-endpoint-migration/phase-0-endpoint-evidence.md
# §"Five paths are deprecated, not two".
#
# ENFORCEMENT LEVEL: ADVISORY at the CI wiring layer. This guard lands in the
# `lint-bot-statuses` job, which `.github/workflows/ci.yml` records as advisory — absent from
# `scripts/required-checks.txt` and from the ruleset, so a PR can merge with it red. NO
# MERGE-GATING CLAIM IS MADE HERE. Promotion is deferred, not forgotten, and is real work:
# `required-checks.txt` carries an AUTO-FABRICATION GUARD (#6049) that makes the bot-PR
# composite action post a fabricated green for any content-scoped gate name added to it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# TEST SEAM. A lint whose only input is the live tree cannot be observed FAILING, and a guard
# never observed failing is indistinguishable from one that cannot fail. The suite points this
# at fixture trees (each `git init`-ed, so the same `git grep` code path runs — there is no
# second, untested listing path).
REPO_ROOT="${LINT_SUPABASE_ENDPOINTS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
HIGHWATER_FILE="${LINT_SUPABASE_ENDPOINTS_HIGHWATER:-$SCRIPT_DIR/lint-supabase-deprecated-endpoints.highwater}"

HOST_LITERAL='https://api.supabase.com'
HOST_LITERAL_RE='https://api\.supabase\.com'

# Terminator classes, built from octal escapes so the literal quote/backtick characters never
# have to survive shell quoting inside a bracket expression.
SQ=$'\047'
BT=$'\140'
AUTHORITY_CH="[^/[:space:]\"${SQ}${BT})]"   # authority characters, up to the first '/'
PATHSEG_CH="[^[:space:]\"${SQ}${BT}]"       # URL path characters

# ── DENYLIST ────────────────────────────────────────────────────────────────────────────
# Format: <path fragment>|<waiver>|<justification>
# A waiver of NONE means any call site is a hard failure. Any other value is a dated waiver
# and must carry its justification on the same line — that is the whole audit trail.
#
#   analytics/endpoints/logs.all  Supabase announced REMOVAL on 2026-09-23. No waiver: a call
#                                 site here is a dated outage, not a style question.
#   advisors/security             Deprecated with NO announced removal date. WAIVED-2026-08-26
#                                 because the three call sites are the advisor scan, its
#                                 RLS-apply sibling and a test's mutation stub (two of the
#                                 three run in production), there is no replacement endpoint yet,
#                                 and nothing breaks on a known date. Re-examine when the spec
#                                 gains a sunset field (see phase-0-endpoint-evidence.md).
#
# advisors/performance is DELIBERATELY NOT LISTED. It is deprecated in the spec but has ZERO
# non-doc callers — its only occurrences are two SQL migration comments citing what an advisor
# once reported. Listing it would put a permanent zero-yield row in the denylist and invite the
# bare-token match over prose that the call-construct anchor exists to prevent.
DENY=(
  'analytics/endpoints/logs.all|NONE|removal announced 2026-09-23 — no waiver'
  'advisors/security|WAIVED-2026-08-26|deprecated, no announced removal date; no replacement endpoint exists yet'
)

# ── ARM 2 NON-CALLER ALLOWLIST ──────────────────────────────────────────────────────────
# Format: <repo-relative path>|<date triaged>|<reason, verified by reading the file>
# Every entry was read. An allowlisted file is ADDITIONALLY required to make zero Management
# API calls (site count 0) — so if one of these ever grows a real call, the allowlist stops
# covering it and this guard reds. The allowlist buys "this file is not a caller", never
# "this file is exempt".
ALLOWLIST=(
  '.github/workflows/cutover-inngest.yml|2026-08-26|env plumbing only (secrets.SUPABASE_ACCESS_TOKEN into a step env); the call lives in scripts/cutover-inngest.sh, which is pinned'
  '.github/workflows/scheduled-followthrough-sweeper.yml|2026-08-26|env plumbing only; the calls live in scripts/followthroughs/*.sh, all three pinned'
  '.github/workflows/scheduled-supabase-advisor-scan.yml|2026-08-26|env plumbing plus remediation prose naming the secret; the call lives in scripts/supabase-advisor-scan.sh, which is pinned'
  'apps/web-platform/infra/cutover-inngest-workflow.test.sh|2026-08-26|snapshot assertion on the string secrets.SUPABASE_ACCESS_TOKEN in the workflow; makes no HTTP call'
  'apps/web-platform/infra/inngest.tf|2026-08-27|env plumbing only: a github_actions_secret resource whose secret_name is the literal SUPABASE_ACCESS_TOKEN, writing var.supabase_access_token to GitHub via the github provider. There is no supabase provider, no data "http" and no curl in the file, so Terraform makes no Management API call; the one host literal is a # comment recording a live pgbouncer-drift check. Same category as the three env-plumbing workflows above. Surfaced 2026-08-27 when the host pin stopped counting comment text as a pin'
  'scripts/lint-supabase-deprecated-endpoints.highwater|2026-08-27|this guard'"'"'s own baseline. Its only non-comment line is the integer; every /v1/projects and the one host literal sit in the # provenance header that documents what the census counts. A data file cannot make an HTTP call. The guard-of-the-guard shape, one level down — and NOT excluded from the pathspec, because narrowing what the guard can see is the move this header exists to refuse'
  'apps/web-platform/infra/inngest-rls/0002_dev_inngest_tables_lockdown.sql|2026-08-26|SQL comment describing the workflow identity check (GET /v1/projects/<ref>); SQL cannot call an HTTP API'
  'apps/web-platform/infra/inngest-rls/apply-inngest-rls-dev-workflow.test.sh|2026-08-26|python assertion strings checking that /v1/projects/ appears in a captured run log; makes no HTTP call'
  'apps/web-platform/scripts/run-migrations.sh|2026-08-26|comment about a missing SUPABASE_PAT never failing the run; delegates to postgrest-reload-schema.sh, which is pinned'
  'apps/web-platform/test/server/inngest/cron-supabase-advisor-scan.test.ts|2026-08-26|the guard-of-the-guard: asserts the ABSENCE of SUPABASE_ACCESS_TOKEN and advisors/security in-process'
  'plugins/soleur/test/terraform-target-parity.test.ts|2026-08-26|comment naming the SUPABASE_ACCESS_TOKEN GitHub-secret terraform resource; makes no HTTP call'
)

# ── Assemblies ──────────────────────────────────────────────────────────────────────────
PATHSPEC=( '.' ':(exclude)*.md' ':(exclude)*.mdx' ':(exclude)knowledge-base/**' )

assembly_deprecation() {
  git -C "$REPO_ROOT" grep -lI --fixed-strings -e "$HOST_LITERAL" -- "${PATHSPEC[@]}" 2>/dev/null || true
}
assembly_hostpin() {
  git -C "$REPO_ROOT" grep -lIE -e '/v1/projects/|SUPABASE_ACCESS_TOKEN|SUPABASE_PAT' -- "${PATHSPEC[@]}" 2>/dev/null || true
}

# Comment markers are per-language. `--` is a comment ONLY in .sql: in shell and YAML a huge
# share of the real call sites are curl continuation lines that START with `--url`
# (apply-inngest-rls.yml:155,178 and inngest-rls/anon-probe.sh:55 among them), so a global `--`
# rule would silently drop the majority of the corpus and the ratchet would report the loss
# as green.
comment_re_for() {
  case "$1" in
    *.sql)                       printf '%s' '^[0-9]+:[[:space:]]*(--|/\*)' ;;
    *.ts|*.tsx|*.js|*.jsx|*.mjs) printf '%s' '^[0-9]+:[[:space:]]*(//|\*|/\*)' ;;
    *)                           printf '%s' '^[0-9]+:[[:space:]]*#' ;;
  esac
}

# `NNN:text` for every non-comment line.
code_lines() {
  grep -nE '^' -- "$1" 2>/dev/null | grep -vE "$(comment_re_for "$1")" || true
}

# Variable names used as the HOST TOKEN immediately before /v1/projects in this file.
#
# THE TRAILING SLASH IS NOT PART OF THE ANCHOR, and requiring it was a hole. A caller that
# builds its base in one step and appends the path in the next --
#   BASE="${API}/v1/projects";  curl "$BASE/$REF/analytics/endpoints/logs.all"
# -- has NO `/v1/projects/` anywhere: the segment ends at a closing quote. Anchored on the
# slash, this file yielded zero host vars, zero census sites, and a clean bill of health for a
# PAT-bearing call to a no-waiver deprecated path. `/v1/projects` alone is the anchor; what
# follows it (a slash, a quote, end of line) is the caller's business, not the guard's.
used_host_vars() {
  code_lines "$1" \
    | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/v1/projects' \
    | sed -E 's#^\$\{?##; s#\}?/v1/projects$##' \
    | sort -u || true
}

# Every RHS assigned to $2 in file $1, trailing comment and one layer of quoting removed.
# Reads CODE LINES only. A commented-out assignment is not an assignment, and documenting the
# exfil shape you are defending against ("# never write API=\"${SUPABASE_API_HOST:-...}\"") is a
# thing this repo does constantly -- a raw grep here would red the very comment explaining the
# rule, which is the bare-token-over-prose defect (cq-assert-anchor-not-bare-token) reappearing
# on the resolution side rather than the detection side.
#
# ASSIGNMENT SYNTAX IS NOT SHELL-ONLY. Recognising only the shell's space-free `V=` made this
# resolver FAIL-CLOSED on every TypeScript caller: `const API = "https://api.supabase.com"`
# is an assignment the guard could not see, so a correctly-pinned .ts file reported
# UNRESOLVABLE-HOST. Fail-closed is the right direction to be wrong in, but a guard that reds
# on the compliant shape gets switched off, so `const|let|var NAME =` (with the spaces, the
# trailing `;`/`,` and backtick template literals that come with it) is recognised too.
var_rhs() {
  local f="$1" v="$2"
  local pre='^[[:space:]]*((export|local|readonly|const|let|var)[[:space:]]+)?'
  local eq='[[:space:]]*=[[:space:]]*'
  code_lines "$f" | sed -E 's/^[0-9]+://' | grep -hE "${pre}${v}${eq}" 2>/dev/null \
    | sed -E "s#${pre}${v}${eq}##" \
    | sed -E 's/[[:space:]]+(#|\/\/).*$//' \
    | sed -E 's/[[:space:]]*[;,]+[[:space:]]*$//' \
    | sed -E 's/^"(.*)"$/\1/' \
    | sed -E "s/^'(.*)'\$/\1/" \
    | sed -E "s/^${BT}(.*)${BT}\$/\1/" || true
}

# Scheme through authority, nothing after the first /v1. This is the ONLY span arm 2 asserts.
host_span() { printf '%s' "$1" | sed -E 's#/v1/.*$##'; }

# ── Scan ────────────────────────────────────────────────────────────────────────────────
FINDINGS=()
WAIVED_NOTES=()
SITES=0

dep_files="$(assembly_deprecation)"
pin_files="$(assembly_hostpin)"
union="$(printf '%s\n%s\n' "$dep_files" "$pin_files" | grep -vE '^[[:space:]]*$' | sort -u)"

union_n=0
[[ -n "$union" ]] && union_n="$(printf '%s\n' "$union" | grep -c '^' || true)"

# SCOPE LOSS IS A HARD ERROR, never a quiet zero. An empty assembly and a clean repo must not
# produce the same answer: a moved tree, a broken pathspec or a non-git root all yield zero
# files, and this guard would then certify silence forever.
if [[ "$union_n" -lt 1 ]]; then
  echo "error: lint-supabase-deprecated-endpoints enumerated 0 files under $REPO_ROOT." >&2
  echo "       Zero enumerated files is scope loss, not a clean result. Is \$REPO_ROOT a git repo with tracked files?" >&2
  exit 2
fi

while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  abs="$REPO_ROOT/$rel"
  [[ -f "$abs" ]] || continue
  # os.walk-equivalent symlink hazard: this guard open()s and echoes matched lines, so a
  # tracked symlink pointing outside the tree would be a read primitive. Nothing here is one.
  [[ -L "$abs" ]] && continue

  code="$(code_lines "$abs")"

  # Host tokens usable for arm 1 in THIS file: the literal, plus every variable used as a host
  # token — resolved or not. Including UNRESOLVED vars is deliberate: a deprecated call made
  # through a redirected host is still a deprecated call, and arm 2 reports the redirect
  # separately. Narrowing this to pinned vars only would hide the worst case.
  hostalt="$HOST_LITERAL_RE"
  vars="$(used_host_vars "$abs")"
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    hostalt="$hostalt"'|\$'"$v"'|\$\{'"$v"'\}'
  done <<< "$vars"

  # ── Census: Management API call sites on non-comment lines. Counted over the UNION, so it
  # moves when any caller is added or deleted. `/v1/projects` (not `/v1/`) is the anchor:
  # scripts/cutover-inngest.sh also calls https://api.hetzner.cloud/v1/servers/… and
  # /v1/actions/…, and a bare `/v1/` anchor would drag Hetzner into a Supabase host-pin rule
  # and red three correct lines. The anchor stops at `projects` and does NOT require the
  # trailing slash — see used_host_vars: a base built in one statement and used in the next
  # ends the segment on a quote, and demanding the slash made that whole caller invisible.
  site_re="(https?://${AUTHORITY_CH}+|\\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?)/v1/projects"
  file_sites=0
  if [[ -n "$code" ]]; then
    file_sites="$(printf '%s\n' "$code" | grep -cE "$site_re" || true)"
  fi
  [[ "$file_sites" =~ ^[0-9]+$ ]] || file_sites=0
  SITES=$((SITES + file_sites))

  # ── ARM 1: deprecated call sites ──────────────────────────────────────────────────────
  for entry in "${DENY[@]}"; do
    dpath="${entry%%|*}"
    rest="${entry#*|}"
    waiver="${rest%%|*}"
    dpath_re="$(printf '%s' "$dpath" | sed -E 's/\./\\./g')"
    hits=""
    if [[ -n "$code" ]]; then
      hits="$(printf '%s\n' "$code" | grep -E "(${hostalt})/v1/projects/${PATHSEG_CH}*${dpath_re}" || true)"
    fi
    [[ -n "$hits" ]] || continue
    while IFS= read -r hit; do
      [[ -n "$hit" ]] || continue
      lno="${hit%%:*}"
      if [[ "$waiver" == "NONE" ]]; then
        FINDINGS+=("$rel:$lno: DEPRECATED-NO-WAIVER $dpath — ${entry##*|}")
      else
        WAIVED_NOTES+=("$rel:$lno: waived ($waiver) $dpath")
      fi
    done <<< "$hits"
  done

  # ── ARM 2: host pin ───────────────────────────────────────────────────────────────────
  # NO `grep -q` MID-PIPE. Under `pipefail` a matching `grep -q` exits early, the `printf`
  # producer takes SIGPIPE (141), and the PIPELINE reports 141 even though grep MATCHED — so
  # `... | grep -qxF "$rel" && in_pin=1` silently skips arm 2 for exactly the files it matched.
  # Latent at 30 paths (well under the 64 KB pipe buffer) and load-bearing the moment it is not.
  # A herestring has no producer process and cannot take the signal.
  in_pin=0
  grep -qxF -- "$rel" <<< "$pin_files" && in_pin=1
  if [[ "$in_pin" -eq 1 ]]; then
    # MEMBERSHIP IS MEASURED OVER CODE LINES, never the raw file. Arm 1 and the census both
    # read `$code`; if arm 2 read the raw bytes, a file could satisfy the host pin on COMMENT
    # TEXT alone — one `# see https://api.supabase.com` and an env-redirected PAT-bearing call
    # below it reports clean. That was live: apps/web-platform/infra/inngest.tf carries
    # SUPABASE_ACCESS_TOKEN and its ONLY host literal is a `#` comment, so it passed the host
    # pin on prose. A comment is not a pin.
    has_literal=0
    if [[ -n "$code" ]]; then
      has_literal="$(printf '%s\n' "$code" | grep -cF -- "$HOST_LITERAL" || true)"
    fi
    [[ "$has_literal" =~ ^[0-9]+$ ]] || has_literal=0

    allow_reason=""
    for a in "${ALLOWLIST[@]}"; do
      [[ "${a%%|*}" == "$rel" ]] && { allow_reason="$a"; break; }
    done

    if [[ "$has_literal" -eq 0 && -z "$allow_reason" ]]; then
      # MEMBERSHIP IS THE ASSERTION. This branch is the exfil detector: a caller whose host
      # was redirected away from the literal shows up here as a missing member.
      FINDINGS+=("$rel:0: UNPINNED-HOST — carries a Management API path or PAT variable but does not contain the literal $HOST_LITERAL on a non-comment line, and is not on the dated non-caller allowlist")
    fi

    # ALLOWLIST STALENESS IS INDEPENDENT OF THE PIN, and nesting it under `has_literal -eq 0`
    # made it unreachable in its main case. The allowlist's claim is "this file is NOT A
    # CALLER" — so it goes stale the moment the file grows a call, whether that call is
    # correctly pinned or not. Nested, an allowlisted file that added a properly-pinned
    # PAT-bearing curl scored has_literal>0, skipped the branch entirely, and reported clean:
    # the header's promise that "if one of these ever grows a real call, the allowlist stops
    # covering it and this guard reds" was false for the likeliest way it happens.
    if [[ -n "$allow_reason" && "$file_sites" -gt 0 ]]; then
      FINDINGS+=("$rel:0: ALLOWLIST-STALE — allowlisted as a non-caller but now makes $file_sites Management API call(s); re-triage or pin it")
    fi

    # Host span via a resolved variable.
    while IFS= read -r v; do
      [[ -n "$v" ]] || continue
      rhs_all="$(var_rhs "$abs" "$v")"
      if [[ -z "$rhs_all" ]]; then
        FINDINGS+=("$rel:0: UNRESOLVABLE-HOST — \$$v is used as the host before /v1/projects/ but is assigned nowhere in this file, so the host span cannot be proven pinned")
        continue
      fi
      while IFS= read -r rhs; do
        [[ -n "$rhs" ]] || continue
        span="$(host_span "$rhs")"
        if [[ "$span" != "$HOST_LITERAL" ]]; then
          FINDINGS+=("$rel:0: HOST-SPAN-NOT-PINNED — \$$v resolves to host span '$span', expected the bare literal $HOST_LITERAL (an expansion here is a PAT-exfil-via-redirect seam)")
        fi
      done <<< "$rhs_all"
    done <<< "$vars"

    # Host span written inline as a literal URL.
    if [[ -n "$code" ]]; then
      while IFS= read -r span_hit; do
        [[ -n "$span_hit" ]] || continue
        span="${span_hit%/v1/projects}"
        [[ "$span" == "$HOST_LITERAL" ]] && continue
        FINDINGS+=("$rel:0: HOST-SPAN-NOT-PINNED — inline URL host span '$span', expected $HOST_LITERAL")
      done < <(printf '%s\n' "$code" | grep -oE "[A-Za-z][A-Za-z0-9+.-]*://${AUTHORITY_CH}+/v1/projects" | sort -u || true)
    fi
  fi
done <<< "$union"

detail=""
[[ ${#FINDINGS[@]} -gt 0 ]] && detail="$(printf '%s\n' "${FINDINGS[@]}" | sort)"

MODE="${1:-scan}"
case "$MODE" in
  --census) echo "$SITES"; exit 0 ;;
  --files)  echo "$union_n"; exit 0 ;;
  --detail) [[ -n "$detail" ]] && echo "$detail"; exit 0 ;;
esac

# ── Anti-vacuity ratchet ────────────────────────────────────────────────────────────────
# A MISSING BASELINE IS A HARD ERROR, never a pass — a ratchet whose baseline vanished would
# otherwise certify any population at all.
if [[ ! -f "$HIGHWATER_FILE" ]]; then
  echo "error: $HIGHWATER_FILE is missing — the ratchet has no baseline, so this run can certify nothing." >&2
  exit 2
fi
allowed="$(sed 's/#.*//' "$HIGHWATER_FILE" | tr -d '[:space:]')"
if ! [[ "$allowed" =~ ^[0-9]+$ ]]; then
  echo "error: $HIGHWATER_FILE does not contain a non-negative integer (got '${allowed}')." >&2
  exit 2
fi

ratchet_rc=0
# DIRECTION. This census is COVERAGE, not offenders — it counts the call sites the guard can
# still SEE. So the failing direction is DOWNWARD, and the number a future author would be
# tempted to edit to make a build pass is a LOWER one. That inverts the wording carried by the
# repo's offender ratchets (lint-diagnosis-claims.highwater et al.) and the inversion is
# deliberate, not a copy error: an extractor that silently stops matching, a pathspec typo, or
# a deleted call site all show up as a DROP. Growth is legitimate (new callers) and is reported
# as a note asking you to raise the baseline.
if [[ "$SITES" -lt "$allowed" ]]; then
  echo "lint-supabase-deprecated-endpoints: FAIL — census is $SITES Management API call sites, below the committed baseline of $allowed." >&2
  echo "" >&2
  echo "  A DROP means one of two things, and both are defects until proven otherwise:" >&2
  echo "    1. a call site was deleted — confirm it, then LOWER $HIGHWATER_FILE to $SITES in the same commit; or" >&2
  echo "    2. the extractor stopped matching — a pathspec change, a renamed tree, a reworded" >&2
  echo "       assignment. That is a guard that has gone blind while still printing OK." >&2
  echo "" >&2
  echo "  Do NOT lower the baseline to make this pass without establishing which of the two it is." >&2
  ratchet_rc=1
fi
if [[ "$SITES" -gt "$allowed" ]]; then
  echo "note: census is $SITES, above the baseline of $allowed — new Management API call sites."
  echo "      Raise $HIGHWATER_FILE to $SITES to lock the coverage in."
fi

if [[ "$MODE" == "--check-highwater" ]]; then
  [[ "$ratchet_rc" -eq 0 ]] && echo "lint-supabase-deprecated-endpoints: OK — census $SITES (baseline $allowed)."
  exit "$ratchet_rc"
fi

if [[ ${#WAIVED_NOTES[@]} -gt 0 ]]; then
  echo "waived deprecated call sites (${#WAIVED_NOTES[@]}):"
  printf '  %s\n' "${WAIVED_NOTES[@]}" | sort
fi

if [[ ${#FINDINGS[@]} -gt 0 ]]; then
  echo "$detail" >&2
  echo "" >&2
  echo "lint-supabase-deprecated-endpoints: FAIL — ${#FINDINGS[@]} violation(s) across $union_n enumerated file(s)." >&2
  echo "" >&2
  echo "  DEPRECATED-NO-WAIVER    : migrate off the path. It has an announced removal date." >&2
  echo "  UNPINNED-HOST           : the file reaches the Management API (or holds a PAT) without the" >&2
  echo "                            literal $HOST_LITERAL. Pin it, or add a dated allowlist entry" >&2
  echo "                            in this script explaining why it is not a caller." >&2
  echo "  HOST-SPAN-NOT-PINNED    : the scheme-through-authority span is expansion-controlled." >&2
  echo "                            Path interpolation is fine; HOST interpolation is a PAT-exfil seam." >&2
  echo "  UNRESOLVABLE-HOST       : the host variable is not assigned in this file, so the pin is unprovable." >&2
  echo "  ALLOWLIST-STALE         : an allowlisted non-caller has grown a real call." >&2
  exit 1
fi

[[ "$ratchet_rc" -ne 0 ]] && exit "$ratchet_rc"
echo "lint-supabase-deprecated-endpoints: OK — $union_n files enumerated, $SITES Management API call sites (baseline $allowed), ${#WAIVED_NOTES[@]} waived, 0 violations."
exit 0
