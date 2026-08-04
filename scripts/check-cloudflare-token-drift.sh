#!/usr/bin/env bash
# Detect Cloudflare API tokens that are DEAD or inconsistent across Doppler configs.
#
# WHY THIS EXISTS (2026-07-29 incident response)
# ----------------------------------------------
# Every `doppler_secret` that carries a Cloudflare token declares
# `lifecycle { ignore_changes = [value] }` (cf-cert-reissue-token.tf,
# tunnel.tf, zot-registry.tf). That rule is deliberate — it stops refresh-time
# churn — but it has a consequence nothing surfaces: **Terraform can never
# propagate a rotated token**. `terraform apply` reports `No changes` while the
# `prd` root config still holds the dead value — and so does every OTHER config
# that carries its own copy. Branch configs do NOT inherit values from the `prd`
# root config; measured 2026-08-02, `CF_API_TOKEN_DNS_EDIT` is carried
# independently by seven configs. That is what makes the fan-out the problem
# rather than a single stale copy.
#
# The failure is silent and delayed. Rotating a token in the Cloudflare
# dashboard and updating `prd_terraform` looks completely successful — the
# operator verifies the one config they edited, gets a green result, and moves
# on. The stale copies surface days later as an unrelated-looking 403 in cron,
# GHCR, or the LUKS workflow, with nothing pointing back at the rotation.
#
# Observed three times in a single session, each time only because the fan-out
# was checked by hand:
#   - REGISTRY_PUSH_ACCESS_TOKEN_*  — `prd` root stale after a Terraform replace
#   - CF_API_TOKEN_DNS_EDIT         — 5 of 7 configs stale after a dashboard roll
#   - CF_API_TOKEN_PURGE            — 6 of 7 configs stale after a dashboard roll
#
# This script makes that class fail loudly. It does NOT change the lifecycle
# rules: removing `ignore_changes` would trade a silent-staleness bug for a
# churn bug the comments say was hit before. Detection is the safer fix.
#
# USAGE
#   DOPPLER_TOKEN=<a Doppler read credential> bash scripts/check-cloudflare-token-drift.sh
#   DOPPLER_TOKEN_MAP='{"<config>":"<read token>", …}' bash scripts/check-cloudflare-token-drift.sh
#   bash scripts/check-cloudflare-token-drift.sh --json
#
# THE CREDENTIALS — TWO MODES SINCE #7234, AND THIS SECTION USED TO DENY THE SECOND
#   This block said "exactly ONE credential, taken from DOPPLER_TOKEN, and there is
#   deliberately no credential-iteration surface: this script loops over CONFIGS, never
#   over credentials". That was true before #7234 and is false now, and it is false in the
#   direction that matters: it is the paragraph an editor opens before deleting the
#   per-config plumbing as dead weight. The full mode contract lives at `declare -A
#   CRED_FOR` below; the short version:
#
#     MAP     `DOPPLER_TOKEN_MAP` non-empty — a JSON object of one config-scoped READ token
#             per config, minted by `doppler_service_token.token_drift` under a `for_each`
#             over the committed inventory and published as ONE Actions secret. This is the
#             twice-daily fan-out scan. There IS a credential-iteration surface: the scan
#             holds N credentials and selects `CRED_FOR[<config>]` per config.
#     SINGLE  `DOPPLER_TOKEN` non-empty — one credential, N enumerated configs, N reads.
#             Byte-for-byte the pre-#7234 behaviour, which five call sites still use.
#
#   Setting BOTH is a hard error (`unknown`, exit 2): they select different scan modes and
#   there is no defensible precedence.
#
#   WHY THE MAP EXISTS AT ALL. #7159 wired this scan to a project-scoped
#   `doppler_service_account` on the INFERRED premise that a project membership can
#   enumerate and read every config. #7234 measured it: that credential could do NEITHER —
#   `doppler configs -p soleur --json` returned null and reading `prd` returned "Could not
#   find requested config 'prd'". No credential in this repository can enumerate the
#   project, which is why in map mode the config list comes from the map's KEYS rather than
#   from an enumeration.
#
#   In BOTH modes every source variable is snapshotted into a local and DOPPLER_TOKEN /
#   DOPPLER_TOKEN_MAP / DOPPLER_CONFIG are then UNSET, so every Doppler read has to name its
#   config explicitly. A read site that forgets its `-c <cfg>` fails loudly instead of
#   silently binding whatever config the ambient environment happened to carry — which, at
#   13 configs, would grade the wrong config's bytes and report a confident wrong answer.
#
#   DO NOT DROP `-p`/`-c` FROM THE READS. A config-scoped token ERRORS on a wrong `-c`
#   (measured against live Doppler, both on `main` and on this branch). That error IS the
#   binding control: it is why no self-identification probe exists, and why a mis-bound
#   token surfaces as a failed read rather than as a confident wrong answer.
#
#   An unset or EMPTY credential is a failed credential, never a fallback: the Doppler CLI
#   treats an empty value as unset and rebinds to whatever ambient credential the runner
#   carries. This script refuses to invoke the CLI at all in that state, and map entries are
#   rejected outright if the token side is empty.
#
# COVERAGE LADDER (--configs-floor / --inventory)
#   `coverage` is unknown | degraded | at-floor, evaluated in that order.
#     degraded  configs < configs_floor  — the credential is missing, empty, revoked, or
#               has been narrowed (role downgrade, environment scoping, or a swap back to
#               a config-scoped token). Producible, and actionable.
#     at-floor  configs >= configs_floor — `>=`, NOT `==`: the live config set is expected
#               to grow, and growth must not red a twice-daily cron.
#   `configs` counts configs whose secret-NAME LISTING succeeded, not configs the project
#   enumerated. A membership that can see a config but cannot open it is excluded from the
#   count and named in `configs_unread`, so it cannot satisfy the floor.
#   BE EXACT: this is a NAME listing, not a VALUE read, and NO value-read failure
#   decrements `configs`. A role that lists names but cannot read values still counts every
#   config here — five prose sites in this repo used to claim such a role "scores 0", and
#   the code has never done that. That case is caught by the NON-VACUITY GATE at the foot
#   of this file instead: with a non-empty keyset and zero conclusions drawn it prints
#   "PROBED ZERO" and exits 2, which the workflow publishes as `verdict: unavailable`, and
#   the coverage-issue close arm is gated on `verdict != unavailable` so it cannot fire.
#   The FLOOR gates. The `--inventory` FLAG gates nothing IN THIS SCRIPT — it supplies only
#   configs_expected, configs_unread and inventory_age_days, so a short, long, stale or
#   missing inventory changes the printed ratio and NO state here.
#
#   BUT THE INVENTORY FILE IS NOT INERT, AND THIS SENTENCE USED TO SAY IT WAS. Since #7234
#   `apps/web-platform/infra/token-drift-read-tokens.tf` reads the SAME file with `file()`
#   and derives the `for_each` key set of `doppler_service_token.token_drift` from it, so
#   its name lines DETERMINE REACH: deleting one destroys that config's read token and drops
#   the config out of the scan entirely. The flag and the file have different consequences
#   and the unqualified "the inventory gates nothing" conflated them — in the direction that
#   invites a line deletion. See the inventory's own header, which states both jobs.
#
# COVERAGE
#   CF_API_TOKEN*             Cloudflare API tokens (single value, Bearer-verified).
#   *ACCESS_TOKEN_ID/_SECRET  Cloudflare ACCESS SERVICE TOKENS (client-id/secret pair,
#                             verified against the Access-protected hostname). Added
#                             2026-07-30: this family is the FIRST case the header above
#                             cites, and the original enumeration regex could not match
#                             it, so the script reported a clean bill of health for a
#                             question it never asked.
#
# EXIT CODES
#   0  every token value resolves LIVE, and every enumerated token was verifiable
#   1  at least one DEAD token value found (rotation did not propagate), OR at least one
#      token could not be verified. UNVERIFIABLE has several disjoint causes with
#      different remedies — a missing hostname mapping is only one of them; see the
#      `cause` field in the report and in --json. Unverified never renders as LIVE.
#   2  preconditions missing (doppler CLI, curl, python3), OR the run drew NO conclusion
#      at all (nothing was measured, so a clean fleet cannot be claimed)

set -uo pipefail

PROJECT="${DOPPLER_PROJECT:-soleur}"
JSON_OUT=0
# --only <SUBSTRING> narrows the scan to keys containing SUBSTRING. It exists for the
# release preflight, which cares about exactly one credential (the registry-push Access
# token) and must not spend a full fleet-wide sweep — one curl per distinct value across
# every config — on the critical path of every release.
#
# It narrows the SCAN, never the enumeration source: keys still come from Doppler, so a
# newly-added token in the matched family is still picked up. A hardcoded key list is how
# CF_API_TOKEN_AUDIT was missed during the incident that motivated this script.
ONLY_MATCH=""
# --json-file <PATH> writes the machine-readable verdict to PATH while STILL printing the
# human report to stdout. It exists because the two consumers want different things from
# ONE scan: the run log needs the prose (which remediation applies, and specifically the
# "fix the DETECTOR, not the credential" warning for unverifiable rows), while the caller
# needs counts it can branch on to pick an email body. Running the script twice was the
# obvious alternative and is wrong — it doubles the Cloudflare probes, which the calling
# workflow's own comment forbids for exactly that reason.
JSON_FILE=""
# --configs-floor <n> is the coverage floor this invocation DEMANDS OF ITS OWN CREDENTIAL:
# "the identity I was handed must reach at least this many configs". It is a DECLARATION,
# not a measurement — a caller cannot be wrong about a number it declares — and it is the
# only input that gates `coverage`.
#
# Default 1, so the three pre-existing call sites keep exactly their current behaviour and
# only the scheduled token-drift step raises it. A denominator taken from the scan's own
# credential would be satisfied by construction (a project-scoped credential lists the
# project's true total, so `configs == expected` always holds and `degraded` would have no
# producer) — which is why the gate compares against a declared floor and never against
# the inventory.
CONFIGS_FLOOR_RAW="1"
# --inventory <path> supplies the DENOMINATOR and gates nothing IN THIS SCRIPT. It
# contributes `configs_expected`, `configs_unread` and `inventory_age_days` to the verdict,
# and no state here depends on it: a short, long, stale or missing inventory changes the
# printed ratio and nothing else. A denominator that gated would let a two-line file derive
# the healthy state and silence the channel, which is the fail-open direction.
#
# THAT IS A STATEMENT ABOUT THIS FLAG, NOT ABOUT THE FILE. Since #7234 the same file is the
# `for_each` key set for `doppler_service_token.token_drift`, so its name lines decide which
# configs get a read token at all — a line deleted there is a config the scan can never
# reach, whatever this flag does. Do not read "gates nothing" as "is safe to shorten".
INVENTORY_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUT=1; shift ;;
    --json-file)
      # Same arity guard, and for the same reason, as --only below: a bare `shift 2` with
      # $#==1 shifts nothing, returns non-zero, and (with no `set -e`) spins the loop
      # forever with no output.
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "ERROR: --json-file requires a non-empty path" >&2; exit 2; }
      JSON_FILE="$2"; shift 2 ;;
    --only)
      # `shift 2` with $#==1 shifts NOTHING and returns non-zero. There is no `set -e`
      # here, so the failure is ignored and `while [[ $# -gt 0 ]]` spins forever with no
      # output — a silent hang, in a script three separate error messages tell an operator
      # to run by hand under incident pressure. Measured: still looping at 2001 iterations.
      # An empty value is rejected too: it would silently widen a scoped check back to a
      # full fleet sweep, which is the opposite of what the caller asked for.
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "ERROR: --only requires a non-empty value" >&2; exit 2; }
      ONLY_MATCH="$2"; shift 2 ;;
    --configs-floor)
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "ERROR: --configs-floor requires a non-empty integer" >&2; exit 2; }
      CONFIGS_FLOOR_RAW="$2"; shift 2 ;;
    --inventory)
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "ERROR: --inventory requires a non-empty path" >&2; exit 2; }
      INVENTORY_PATH="$2"; shift 2 ;;
    # An unrecognised argument is an ERROR, not something to skip. The previous
    # `*) shift ;;` catch-all silently swallowed a typo, and every flag this script takes
    # narrows or instruments the scan: a misspelled `--only` widens a scoped check back to
    # a full sweep, and a misspelled `--inventory` silently drops the denominator and
    # prints a caveat nobody asked for. Silent degradation is the defect class this whole
    # script exists to remove; the argument loop should not be the one place that still
    # commits it.
    *)
      echo "ERROR: unrecognised argument '$1'" >&2
      echo "       Known flags: --json | --json-file <path> | --only <substring> | --configs-floor <n> | --inventory <path>" >&2
      exit 2 ;;
  esac
done

for bin in doppler curl python3 jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: $bin not on PATH" >&2; exit 2; }
done

# ── VERDICT STATE ───────────────────────────────────────────────────────────
# Every variable emit_json reads is declared and initialised HERE, above the first
# possible `exit 2`, because emit_json now runs BEFORE every one of them. It used to run
# only on the success path, so a revoked credential produced no verdict file at all: the
# caller parsed `configs` as -1, coverage landed on `unknown`, and `unknown`'s remedy
# ("fix the verdict file first") is unperformable for a revoked credential. Publishing
# first makes a revoked credential surface as `degraded` at 0/N — a state with a remedy —
# instead of blinding the whole scan. The exit codes themselves are unchanged.
CONFIGS=()             # every config name the credential ENUMERATED
CONFIG_NAMES=()        # configs whose --only-names read SUCCEEDED — the `configs` count
FAILED_CONFIGS=()      # enumerated but unreadable; contributes to configs_unread
LIVE_N=0
DEAD_N=0
UNVERIFIABLE_N=0
DEAD_ROWS=()
UNVERIFIABLE_ROWS=()
# Positive-work counter, incremented at every real probe. Declared here, beside the other
# counters, because verify_value below already touches it and `set -u` makes a later
# declaration a fatal ordering bug rather than a silent zero.
PROBES_MADE=0
CONFIGS_EXPECTED=-1    # -1 = no usable inventory. NEVER a gate; see the block below.
INVENTORY_AGE_DAYS=-1
INVENTORY_NAMES=()
CONFIGS_UNREAD=()
COVERAGE_RATIO="-"
COVERAGE_CAVEAT=""
VERDICT_PUBLISHED=""

# The floor must PARSE. `unknown` is the fail-closed default of the ladder and this is its
# one producer inside the detector: a floor that is not a non-negative integer means the
# gate has no threshold, and deriving `at-floor` from an unparseable demand would be a
# confident state drawn from garbage.
CONFIGS_FLOOR=0
FLOOR_OK=0
if [[ "$CONFIGS_FLOOR_RAW" =~ ^[0-9]+$ ]]; then
  CONFIGS_FLOOR="$CONFIGS_FLOOR_RAW"
  FLOOR_OK=1
fi

# ── THE INVENTORY: A DENOMINATOR THAT REPORTS AND NEVER GATES ───────────────
# Read once, here, so a file that appears or vanishes mid-scan cannot change the verdict
# halfway through.
#
# THE PARSE IS `grep -E '^[a-z0-9_]+$' | sort -u`, AND THE `sort -u` IS PART OF THE
# CONTRACT. An earlier version of this comment claimed the expression was "byte-identical
# to the repo-internal CI check that pins the workflow's declared floor against this
# file's name count". THAT CLAIM WAS FALSE, and it was exactly the claim the pin rested
# on: the CI check counted `grep -cE '^[a-z0-9_]+$'` — RAW lines, no dedup. Measured on
# this very file: append one duplicate `prd` line and set the floor to 14, and the CI
# check sees 14 == 14 while this parse sees 13, so the scan lands on a permanent
# `degraded` that every gate waves through. The two sides must count the SAME thing or
# the pin measures nothing; `plugins/soleur/test/token-drift-workflow-causes.test.sh`
# now dedups too AND asserts the raw and deduped counts agree, so a duplicate line is a
# loud CI failure rather than a silent divergence.
if [[ -n "$INVENTORY_PATH" ]]; then
  if [[ -r "$INVENTORY_PATH" ]]; then
    mapfile -t INVENTORY_NAMES < <(LC_ALL=C grep -E '^[a-z0-9_]+$' "$INVENTORY_PATH" | sort -u || true)
    if (( ${#INVENTORY_NAMES[@]} > 0 )); then
      CONFIGS_EXPECTED=${#INVENTORY_NAMES[@]}
      # Staleness is bounded WITHOUT a credential: the header says when the file was
      # generated, and a stale denominator prints a caveat rather than moving a state.
      _inv_ts=$(grep -m1 -E '^#[[:space:]]*generated:' "$INVENTORY_PATH" | sed -E 's/^#[[:space:]]*generated:[[:space:]]*//' || true)
      if [[ -n "$_inv_ts" ]]; then
        INVENTORY_AGE_DAYS=$(python3 -c '
import sys, datetime
s = sys.argv[1].strip()
try:
    d = datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    if d.tzinfo is None:
        d = d.replace(tzinfo=datetime.timezone.utc)
    print(int((datetime.datetime.now(datetime.timezone.utc) - d).total_seconds() // 86400))
except Exception:
    print(-1)
' "$_inv_ts" 2>/dev/null || printf '%s' -1)
      fi
    else
      COVERAGE_CAVEAT="inventory '$INVENTORY_PATH' carries no parseable config names — ratio unavailable; the floor still decides"
    fi
  else
    COVERAGE_CAVEAT="inventory '$INVENTORY_PATH' is missing or unreadable — ratio unavailable; the floor still decides"
  fi
fi

# ── THE LADDER ──────────────────────────────────────────────────────────────
# Evaluation order is pinned: unknown -> degraded -> at-floor.
#
# The gate reads the FLOOR and the READ COUNT, and nothing else. `configs_expected` is
# computed alongside it and is deliberately absent from every comparison below: the whole
# point of the gate/report split is that a denominator can be short, long, stale or
# missing without starting or stopping a single arm.
compute_coverage() {
  local n=${#CONFIG_NAMES[@]}
  COVERAGE=unknown
  # CONTROL C-b, evaluated FIRST. A credential SOURCE this run could not parse is not a
  # measurement, so it publishes `unknown` — the fail-closed state — rather than falling
  # through to the `n == 0` positive-work floor and publishing `degraded`. The distinction
  # is operator-facing and load-bearing: `degraded` asserts "the credential is absent or
  # narrowed", a claim a run that never made a Doppler call cannot support, and it points
  # at a remedy (widen or republish the credential) that would not fix a malformed map.
  if (( ${MAP_SHAPE_OK:-1} == 0 )); then
    COVERAGE=unknown
    if (( CONFIGS_EXPECTED >= 0 )); then COVERAGE_RATIO="${n}/${CONFIGS_EXPECTED}"; fi
    return 0
  fi
  if (( FLOOR_OK == 1 )); then
    if (( n < CONFIGS_FLOOR || n == 0 )); then
      # `n == 0` is a POSITIVE-WORK FLOOR, independent of the declared floor. Without it a
      # floor of 0 makes `0 < 0` false and the confident state is assigned to a run that
      # read nothing and probed nothing — measured: `--configs-floor 0` with an empty
      # credential published `configs: 0, probes: 0, coverage: at-floor` while this
      # script's own stderr said "0 configs read, so coverage is 'degraded'". A threshold
      # of zero is a threshold that gates nothing; the confident state must never be
      # reachable without at least one successful read. No shipped call site passes 0
      # today (the scheduled step declares 13, the other three take the default 1), so
      # this is the detector honouring its own contract rather than depending on every
      # future caller to pass a sane floor.
      COVERAGE=degraded
    else
      # `>=`, not `==`. The live config set is expected to grow (a new config at git-data
      # birth, ephemeral rehearsal configs), and an equality gate would red a twice-daily
      # cron the first time growth was legitimate. Growth pushes the ratio above 1 and
      # changes no state.
      #
      # NOTE for the consumer: `at-floor` means "read at least the declared floor", NOT
      # "read the right configs". `n` counts configs this run READ, which is not the same
      # set the inventory NAMES — an ephemeral config (a rehearsal dispatch) counts toward
      # `n` and can pad it back to the floor one-for-one after a real config's read fails.
      # `configs_unread` is the discriminator for that case and is deliberately NOT read
      # here (the gate stays credential-derived and inventory-independent). The workflow's
      # close arm gates on it in its `if:` EXPRESSION —
      # `steps.token_drift.outputs.configs_unread == '-'` — not in its run body, whose
      # `env:` deliberately does not carry the field. Do not "fix" that env block: moving
      # the check into the body would put it behind `continue-on-error: true` and an
      # `exit 0`, where a failure to evaluate it is indistinguishable from a pass. See
      # scheduled-terraform-drift.yml.
      COVERAGE=at-floor
    fi
  fi
  if (( CONFIGS_EXPECTED >= 0 )); then
    COVERAGE_RATIO="${n}/${CONFIGS_EXPECTED}"
    if (( INVENTORY_AGE_DAYS > 90 )); then
      COVERAGE_CAVEAT="inventory is ${INVENTORY_AGE_DAYS} days old (>90) — the denominator may no longer describe the project"
    fi
  else
    # Absent, not fabricated. A `-` cannot be mistaken for a measurement, and it keeps the
    # field non-empty so a whitespace-splitting consumer cannot shift its later fields.
    COVERAGE_RATIO="-"
  fi
  # configs_unread = (inventory minus read) UNION (enumerated but unreadable), sorted and
  # deduped. The second half matters on its own: a config that lists but whose secret read
  # fails is the subtle form of a narrowed role, and it must be nameable even when no
  # inventory was supplied at all.
  CONFIGS_UNREAD=()
  local want got seen
  for want in ${INVENTORY_NAMES[@]+"${INVENTORY_NAMES[@]}"} ${FAILED_CONFIGS[@]+"${FAILED_CONFIGS[@]}"}; do
    seen=0
    for got in ${CONFIG_NAMES[@]+"${CONFIG_NAMES[@]}"}; do
      [[ "$want" == "$got" ]] && { seen=1; break; }
    done
    (( seen == 0 )) && CONFIGS_UNREAD+=("$want")
  done
  if (( ${#CONFIGS_UNREAD[@]} > 0 )); then
    mapfile -t CONFIGS_UNREAD < <(printf '%s\n' "${CONFIGS_UNREAD[@]}" | grep -v '^$' | sort -u || true)
  fi
}

# Extracted so --json (stdout) and --json-file (file, alongside the human report) render
# from ONE code path. Two renderers would be a second unsynchronized pin on the same
# schema, which is how the two sides drift apart silently.
emit_json() {
  compute_coverage
  # `split("|", 1)` — maxsplit 1, so a diagnostic containing a pipe cannot shift fields.
  # Unverifiable rows get their own key rather than riding in "stale" with the diagnostic
  # sentence mis-rendered into the "config" field.
  #
  # ARGV CONTRACT. ELEVEN positional scalars, then FOUR variable-length lists behind THREE
  # DISTINCT sentinels. `rest.index("--")` returns the FIRST match, so one sentinel cannot
  # separate more than two lists — a second `--` would silently fold two lists into one.
  # Inserting a scalar shifts every index, so the scalar count and the `range(1, 9)` /
  # `sys.argv[9:12]` / `sys.argv[12:]` reads move together or not at all.
  python3 - \
    "$LIVE_N" "$DEAD_N" "${#UNVERIFIABLE_ROWS[@]}" "$PROBES_MADE" "${#CONFIG_NAMES[@]}" \
    "$CONFIGS_FLOOR" "$CONFIGS_EXPECTED" "$INVENTORY_AGE_DAYS" \
    "$COVERAGE" "$COVERAGE_RATIO" "${COVERAGE_CAVEAT:--}" \
    ${DEAD_ROWS[@]+"${DEAD_ROWS[@]}"} "--" \
    ${UNVERIFIABLE_ROWS[@]+"${UNVERIFIABLE_ROWS[@]}"} "--names--" \
    ${CONFIG_NAMES[@]+"${CONFIG_NAMES[@]}"} "--unread--" \
    ${CONFIGS_UNREAD[@]+"${CONFIGS_UNREAD[@]}"} <<'PY'
import json, sys
live, dead, unver, probes, configs, floor, expected, age = (int(sys.argv[i]) for i in range(1, 9))
coverage, ratio, caveat = sys.argv[9], sys.argv[10], sys.argv[11]
rest = sys.argv[12:]
i_unver = rest.index("--")
i_names = rest.index("--names--")
i_unread = rest.index("--unread--")
def rows(xs, second):
    out = []
    for r in xs:
        if not r:
            continue
        k, _, v = r.partition("|")
        out.append({"key": k, second: v})
    return out
def unver_rows(xs):
    # Three fields: key|cause|reason. `cause` is a closed vocabulary the workflow can
    # branch on — the previous shape forced any consumer to pattern-match English prose,
    # so it sent one static remedy for four disjoint causes.
    out = []
    for r in xs:
        if not r:
            continue
        k, _, tail = r.partition("|")
        cause, _, reason = tail.partition("|")
        out.append({"key": k, "cause": cause, "reason": reason})
    return out
print(json.dumps({
    # `configs` counts configs whose secret-NAME LISTING succeeded, not configs LISTED by
    # the project enumeration. A membership scoped away from a config lists it and cannot
    # open it, so it is excluded here and named in `configs_unread`.
    # It is NOT a count of value reads: a role that can list names but not read values
    # still counts every config. The non-vacuity gate ("PROBED ZERO", exit 2 ->
    # verdict: unavailable) is what catches that one, not this field.
    "live": live, "dead": dead, "unverifiable": unver, "probes": probes, "configs": configs,
    "stale": rows(rest[:i_unver], "config"),
    "unverifiable_keys": unver_rows(rest[i_unver + 1:i_names]),
    # The gate: `configs >= configs_floor`. The report: everything below it.
    "config_names": [c for c in rest[i_names + 1:i_unread] if c],
    "configs_floor": floor,
    "configs_expected": expected,
    "configs_unread": [c for c in rest[i_unread + 1:] if c],
    "coverage": coverage,
    "coverage_ratio": ratio,
    "inventory_age_days": age,
    # "-" is the non-empty stand-in for "no caveat", so a whitespace-splitting consumer
    # cannot lose a field to an empty string.
    "coverage_caveat": caveat,
}, indent=2))
PY
}

# Publish the verdict to whichever sinks the caller asked for, exactly once.
#
# Called before EVERY exit-2 return as well as on the success path, so `configs`,
# `configs_floor`, `coverage` and `coverage_ratio` reach the caller on every path — a
# revoked credential included. The idempotence guard is what lets the error paths call it
# unconditionally without the success path emitting twice.
publish_verdict() {
  [[ -n "$VERDICT_PUBLISHED" ]] && return 0
  VERDICT_PUBLISHED=1
  local rc=0
  if [[ "$JSON_OUT" -eq 1 ]]; then
    emit_json || rc=1
  fi
  if [[ -n "$JSON_FILE" ]]; then
    emit_json > "$JSON_FILE" || { echo "ERROR: could not write --json-file '$JSON_FILE'" >&2; rc=1; }
  fi
  return "$rc"
}

if (( FLOOR_OK == 0 )); then
  echo "ERROR: --configs-floor '$CONFIGS_FLOOR_RAW' is not a non-negative integer — the coverage gate has no threshold." >&2
  echo "       Publishing coverage: unknown rather than deriving a state from an unparseable demand." >&2
  publish_verdict || true
  exit 2
fi

# Register a scanned value with the Actions log masker, once per distinct value, BEFORE it
# can reach any probe. Actions auto-masks only `secrets.*`-sourced values, so everything
# this detector pulls out of Doppler is unmasked in the job log by default — in the same
# script that deliberately un-swallows stderr from the subsystem handling those values.
#
# DEFINED BEFORE THE CREDENTIAL BLOCK, because the credential block now masks. See the
# NFR1 note there for why the prohibition that used to stand here was overturned.
declare -A MASKED=()
mask_value() {
  local v="$1"
  [[ -z "$v" ]] && return 0
  [[ -n "${MASKED[$v]:-}" ]] && return 0
  MASKED["$v"]=1
  [[ "${GITHUB_ACTIONS:-}" == "true" ]] && echo "::add-mask::$v"
  return 0
}

# ── THE CREDENTIALS ─────────────────────────────────────────────────────────
# `CRED_FOR[<config>]` — one credential per config this run may read. Snapshotted, then
# every source variable is unset. The caller keeps them in the step environment for the
# whole run, so a read site that forgets its `-c <cfg>` would silently bind the ambient
# config and grade the wrong config's bytes. Unsetting makes that failure loud BY
# CONSTRUCTION rather than by a test noticing it at review time.
#
# TWO MODES, ONE DOWNSTREAM PATH:
#
#   MAP    `DOPPLER_TOKEN_MAP` non-empty — a JSON object {"<config>": "<token>", …}. The
#          twice-daily fan-out scan (#7234). No credential in this repository can
#          enumerate the `soleur` project, so the config list comes from the map's KEYS,
#          which Terraform derives from the committed inventory.
#   SINGLE `DOPPLER_TOKEN` non-empty — one credential, N enumerated configs, N reads.
#          Byte-for-byte what every pre-#7234 caller had. Five call sites still use it,
#          none passing --configs-floor, two of them branch-scoped.
#
# SELECTION IS ON NON-EMPTINESS (`-n`), NOT DEFINEDNESS, AND THAT IS PINNED. A workflow
# writing `DOPPLER_TOKEN_MAP: ${{ secrets.X }}` with the secret absent yields a variable
# that is DEFINED and EMPTY. `-n` routes that to the "neither" arm → `degraded 0/N`, the
# correct diagnosis (a credential is missing) and exactly the shape of the merge→apply
# window before the secret is first published. Selecting on `${x+set}` would route it to a
# malformed-map fault → `unknown`, whose operator-facing remedy says the Doppler identity
# is NOT at fault — the wrong remedy in the one window it is guaranteed to fire.
declare -A CRED_FOR=()
MAP_SHAPE_OK=1
_cred_map_raw="${DOPPLER_TOKEN_MAP:-}"
_cred_single="${DOPPLER_TOKEN:-}"
unset DOPPLER_TOKEN_MAP DOPPLER_TOKEN DOPPLER_CONFIG

if [[ -n "$_cred_map_raw" && -n "$_cred_single" ]]; then
  # FAIL CLOSED TO `unknown`, NOT `degraded`. `degraded` asserts the credential is absent
  # or narrowed; this run made no Doppler call and cannot support that claim — it is the
  # same distinction compute_coverage's C-b arm exists to draw, and without this line the
  # positive-work floor (`n == 0`) publishes `degraded` and sends the operator to re-mint a
  # token when the actual fault is a workflow that set two variables.
  MAP_SHAPE_OK=0
  echo "::error::token_drift_credential_mode_ambiguous — both DOPPLER_TOKEN_MAP and DOPPLER_TOKEN are set; refusing to choose a scan mode." >&2
  {
    echo "ERROR: both DOPPLER_TOKEN_MAP and DOPPLER_TOKEN are set and non-empty."
    echo "       These select different scan modes (fan-out over a config map vs a single"
    echo "       credential) and there is no defensible precedence between them."
    echo "       Refusing to guess: no config was read and none was probed."
  } >&2
  publish_verdict || true
  exit 2
fi

if [[ -n "$_cred_map_raw" ]]; then
  # ── CONTROL C-b: shape validation, BEFORE any network call ────────────────
  # A malformed credential SOURCE is not a measurement, so it publishes `unknown` (the
  # fail-closed state) rather than `degraded` (which asserts "the credential is absent or
  # narrowed", a claim a run that made no Doppler call cannot support). Parsed with `jq`,
  # never a regex.
  #
  # ⚠️ STDERR IS CAPTURED SEPARATELY, NEVER `2>&1`, AND THAT IS A CREDENTIAL BOUNDARY.
  # jq is a STREAMING parser: given more than one JSON value (`{...} {...}`, or a valid
  # object followed by trailing bytes) it emits the `config\ttoken` lines for every value
  # it processed successfully BEFORE it hits the fault. Folding stdout into the error
  # variable with `2>&1` therefore puts live read tokens into a variable this block echoes
  # to the job log — and masking has not run yet on this path, because it happens only
  # after a successful parse. Measured: `{"prd":"dp.st.prd.X"} junk` printed the token pair
  # alongside the parse error, with zero `::add-mask::` emitted. Keep the streams apart.
  #
  # ANCHORS ARE `\A`/`\z`, NOT `^`/`$`. jq's regex engine is Oniguruma, where `$` matches
  # before a FINAL NEWLINE — so `test("^[a-z0-9_]+$")` accepts `"prd\n"`. A key or value
  # containing a newline then splits the `key\tvalue` record below, yielding a forged entry
  # whose credential is the EMPTY STRING, which the Doppler CLI treats as unset and rebinds
  # to whatever ambient credential the runner carries. That is the precise hazard the
  # snapshot-and-unset discipline above exists to close, reintroduced through the
  # validator. `\A`/`\z` anchor to the whole string and admit neither.
  #
  # VALUES ARE CHARSET-CHECKED TOO, not merely "a non-empty string". A Doppler token is
  # `dp.st.<name>.<url-safe>`, so the alphabet below is a superset of what the provider
  # can mint and still excludes every whitespace and control character that could split a
  # record.
  _map_err=""
  _map_jq_err=$(mktemp) || _map_jq_err=/dev/null
  if ! _map_norm=$(jq -e -r '
        def bad_key:   (.|test("\\A[a-z0-9_]+\\z")|not);
        def bad_value: (.|type != "string") or (. == "") or (.|test("\\A[A-Za-z0-9._-]+\\z")|not);
        if type != "object" then error("not a JSON object")
        elif (keys|length) == 0 then error("object has zero keys")
        elif (keys|map(select(bad_key))|length) > 0 then error("a key is not a Doppler config name")
        elif ([.[]]|map(select(bad_value))|length) > 0 then error("a value is not a Doppler read token")
        else (to_entries|map(.key + "\t" + .value)|.[])
        end' <<<"$_cred_map_raw" 2>"$_map_jq_err"); then
    # ONLY the classification, never jq's stdout. `head -c 200` bounds a hostile parser
    # message; the message itself is one of the `error(...)` strings above or a jq parse
    # error, neither of which echoes input values.
    _map_err="$(tr -d '\r' <"$_map_jq_err" | head -c 200)"
    MAP_SHAPE_OK=0
  fi
  [[ "$_map_jq_err" != /dev/null ]] && rm -f "$_map_jq_err"
  unset _map_jq_err
  if (( MAP_SHAPE_OK == 0 )); then
    # NAMED ANNOTATION, not just a stderr line. The `unknown` issue body tells the operator
    # to discriminate a credential fault from a detector fault by looking for exactly this
    # marker; without it that instruction resolves to "no annotation → detector fault",
    # which is the wrong branch on the one path that IS a credential fault.
    echo "::error::token_drift_map_malformed — DOPPLER_TOKEN_DRIFT_MAP is not a usable credential map: ${_map_err}" >&2
    {
      echo "ERROR: DOPPLER_TOKEN_MAP is not a usable credential map."
      echo "       ${_map_err}"
      echo "       Expected a JSON object of {\"<config>\": \"<read token>\"} whose keys are"
      echo "       Doppler config names and whose values are read tokens, as published by"
      echo "       github_actions_secret.doppler_token_drift_map."
      echo "       Publishing coverage: unknown — a credential source this run could not parse"
      echo "       is not evidence that the credential is absent or narrowed, which is what"
      echo "       'degraded' would assert. NO Doppler call was made."
    } >&2
    publish_verdict || true
    exit 2
  fi
  # Mask EVERY credential before the first `doppler` invocation of any kind.
  #
  # NFR1 — THIS REVERSES AN EXPLICIT PROHIBITION THAT USED TO STAND HERE, and the reversal
  # is the point rather than an oversight. The old comment read: "The credential itself is
  # deliberately NOT masked here: `::add-mask::<value>` writes the value to stdout, and the
  # credential must reach no sink at all." That reasoning was sound for a WHOLE-SECRET
  # credential, which Actions masks automatically from `secrets.*` — registering it again
  # bought nothing and cost one more sink. It does NOT hold for a MAP: Actions masks the
  # map as ONE OPAQUE STRING, so the values extracted out of it are unmasked, and this
  # script deliberately does not suppress the Doppler CLI's stderr precisely so a rejected
  # credential is loud. A rejected token can therefore print itself into a workflow log.
  # Masking each extracted value is the lesser exposure: `::add-mask::` reaches the Actions
  # log processor, the alternative reaches the log itself.
  while IFS=$'\t' read -r _cfg _tok; do
    [[ -z "$_cfg" ]] && continue
    # DEFENCE IN DEPTH behind the validator above. If a record ever splits despite the
    # anchors, the fragment arrives with an empty token — and an empty DOPPLER_TOKEN is an
    # ambient-credential rebind, not a failed read. Fail the whole map closed rather than
    # scanning one config with someone else's credential.
    if [[ -z "$_tok" ]]; then
      MAP_SHAPE_OK=0
      echo "::error::token_drift_map_malformed — DOPPLER_TOKEN_DRIFT_MAP yielded an entry with an empty credential (key '${_cfg}')." >&2
      echo "ERROR: refusing to scan with an empty credential — the Doppler CLI treats it as unset and rebinds to the runner's ambient credential." >&2
      publish_verdict || true
      exit 2
    fi
    mask_value "$_tok"
    CRED_FOR["$_cfg"]="$_tok"
  done <<<"$_map_norm"
  unset _map_norm
  CRED_MODE=map
elif [[ -n "$_cred_single" ]]; then
  CRED_MODE=single
else
  # An EMPTY credential is a failed credential, not a fallback. The Doppler CLI treats an
  # empty `--token` / env value as UNSET and rebinds to whatever ambient credential the
  # runner carries, so invoking it here would report a confident answer about a config set
  # nobody asked for. This is a CONFIGURATION fault, and it surfaces as `degraded` at 0/N.
  #
  # BOTH variables are named because either satisfies this script, and the caller that
  # reaches this path most often — the twice-daily scan during the window between merging
  # the credential change and the infra apply that publishes the secret — sets only
  # DOPPLER_TOKEN_MAP. Naming only the other would point the operator at a variable their
  # workflow no longer sets.
  {
    echo "ERROR: neither DOPPLER_TOKEN_MAP nor DOPPLER_TOKEN is set and non-empty —"
    echo "       no Doppler credential to scan with."
    echo "       Refusing to invoke the Doppler CLI without one: it treats an empty value as"
    echo "       unset and would silently bind whatever ambient credential this runner carries."
    echo "       0 configs read, so coverage is 'degraded' against the declared floor of ${CONFIGS_FLOOR}."
    echo "       If this is the fan-out scan, DOPPLER_TOKEN_MAP comes from the Actions secret"
    echo "       DOPPLER_TOKEN_DRIFT_MAP, published by the infra apply."
  } >&2
  publish_verdict || true
  exit 2
fi

# ── WHICH CONFIGS THIS RUN COVERS ───────────────────────────────────────────
# Never a list hardcoded HERE. A hardcoded list is exactly how CF_API_TOKEN_AUDIT was
# missed during the incident: it lived only in the dev* configs, which the audit sweep
# never looked at. Where the list comes from instead differs by mode, and the difference
# is the substance of #7234 — see each branch.
#
# In BOTH modes the credential is delivered as an ENV PREFIX, never as `--token <value>`
# on argv: /proc/<pid>/cmdline is world-readable and /proc/<pid>/environ is 0400. That
# defends against a different-UID local observer, NOT against a compromised runner where
# every step shares one UID — stated accurately rather than overstated.
if [[ "$CRED_MODE" == "map" ]]; then
  # MAP MODE — the config list is the map's KEYS, and Doppler is never asked to enumerate.
  #
  # That is not an optimisation, it is the whole correction #7234 makes: enumerating the
  # project is a capability NO credential in this repository has. A config-scoped token
  # answers `doppler configs` with a list SILENTLY SCOPED TO ITSELF (one entry,
  # `success: true`, no error), so under the old shape the denominator narrowed in lockstep
  # with the numerator and `13/13` printed through every possible narrowing. The map's keys
  # come from the committed inventory via Terraform's `for_each`, so the list is fixed
  # before the run starts and cannot be shrunk by a narrowed credential.
  mapfile -t CONFIGS < <(printf '%s\n' "${!CRED_FOR[@]}" | LC_ALL=C sort)
else
  # SINGLE MODE — unchanged.
  #
  # `2>/dev/null` is deliberately GONE from the enumeration. A non-empty credential that
  # enumerates nothing must be loud, and its stderr — the one line that says whether the
  # credential was rejected, expired, or merely scoped to nothing — was being swallowed.
  mapfile -t CONFIGS < <(DOPPLER_TOKEN="$_cred_single" doppler configs -p "$PROJECT" --json |
    python3 -c 'import json,sys; [print(c["name"]) for c in json.load(sys.stdin)]' 2>/dev/null)
  if [[ ${#CONFIGS[@]} -eq 0 ]]; then
    echo "ERROR: could not enumerate Doppler configs for project '$PROJECT'" >&2
    publish_verdict || true
    exit 2
  fi
  # EVERY enumerated config maps to the ONE credential. This is today's behaviour exactly,
  # and it is deliberately NOT "exactly one config".
  #
  # It is tempting to assume a single credential implies a single config — a config-scoped
  # service token does enumerate exactly itself. But the credential class is not fixed:
  # `DOPPLER_TOKEN_PRD` is prd-ROOT scoped, and the whole fan-out this detector performs —
  # enumerate N, read N — is what the five legacy call sites and this suite's multi-config
  # fixtures exercise. Refusing N > 1 here would convert the detector's core behaviour into
  # an error on its own tests.
  #
  # What single mode gives up is the per-config binding assertion: one credential cannot be
  # wrong about which config it is bound to, so `-c "$cfg"` is a scoping instruction here
  # rather than an assertion. That is why the fan-out scan uses the map instead.
  for _c in "${CONFIGS[@]}"; do CRED_FOR["$_c"]="$_cred_single"; done
  unset _c
fi
unset _cred_single _cred_map_raw

# Enumerate token-shaped keys the same way — never a fixed list.
#
# TWO FAMILIES, because they authenticate completely differently:
#
#   CF_API_TOKEN*            — a Cloudflare API token. One value. Verified as a Bearer
#                              against /user/tokens/verify.
#   *ACCESS_TOKEN_ID/_SECRET — a Cloudflare ACCESS SERVICE TOKEN. A client-id/secret
#                              PAIR. It is not an API token and /user/tokens/verify
#                              cannot say anything about it; it is verified by presenting
#                              the pair to an Access-protected hostname.
#
# The second family was the coverage gap this script shipped with. Its own header cites
# REGISTRY_PUSH_ACCESS_TOKEN_* as the FIRST case that motivated it, and the enumeration
# regex `CF_API_TOKEN[A-Z0-9_]*` cannot match that key — the anchor is at the start, so
# no amount of trailing wildcard reaches a name that does not begin with CF_API_TOKEN.
# The script reported "0 dead" on a fleet where a REGISTRY_PUSH_ACCESS_TOKEN_* rotation
# had not propagated, which is worse than not running at all: it is a green light for a
# question it never asked.
declare -A KEYSET=()          # API tokens:            KEY -> 1
declare -A ACCESS_BASESET=()  # Access service tokens: BASE (no _ID/_SECRET) -> 1
declare -A ALL_ID_KEYS=()     # every *_ACCESS_TOKEN_ID name seen anywhere in the fleet

# One reused file for the name-read's stderr, not one mktemp per config: a per-call
# mktemp+rm leaks on any signal, and the loop runs once per config. If allocation fails the
# reads must still run — `2>` to an unwritable path would abort them — so fall back to
# /dev/null and let the cause discrimination degrade to `identify_empty`, the honest answer
# when the diagnostic could not be captured.
READ_ERR_FILE=$(mktemp) || READ_ERR_FILE=/dev/null

# THE script's single EXIT trap, deliberately. `trap ... EXIT` REPLACES rather than
# appends, so the probe-header cleanup further down used to be installed second and would
# have silently disarmed this one. Both temp files are freed here instead; `PROBE_HDR` is
# a global assigned much later, hence the `:-` guard.
# shellcheck disable=SC2317  # invoked by the EXIT trap below, which shellcheck cannot see
_tmpfile_cleanup() {
  [[ -n "${READ_ERR_FILE:-}" && "${READ_ERR_FILE:-}" != /dev/null ]] && rm -f "$READ_ERR_FILE"
  [[ -n "${PROBE_HDR:-}" ]] && rm -f "$PROBE_HDR"
  return 0
}
trap _tmpfile_cleanup EXIT

for cfg in "${CONFIGS[@]}"; do
  # ONE `--only-names` read per config, reused by both families. Two calls doubled the
  # Doppler request count for no benefit (measured: 26 of 53 calls on the release
  # preflight), and a second call is a second chance to silently return empty.
  #
  # The exit status is CAPTURED, not discarded. `2>/dev/null || true` on a read whose
  # emptiness decides the verdict is how a scope-denied token renders as a clean fleet.
  #
  # A FAILED read no longer aborts the whole scan. It records the config BY NAME in the
  # failed set, and that config does NOT enter `configs` — which is the entire reason
  # `configs` counts configs whose NAME LISTING succeeded rather than configs the project
  # enumeration returned. A membership scoped away from a config still sees it in
  # `doppler configs`; counting that would let a narrowed credential satisfy the floor on
  # configs it cannot open. The partial enumeration is still refused, just one level up:
  # the unread configs surface in `configs_unread` and drag `coverage` to `degraded`
  # instead of taking the scan down.
  #
  # WHAT THIS DOES NOT CATCH, stated plainly because five prose sites used to claim the
  # opposite: a role that can list NAMES but not read VALUES passes this read for every
  # config and is counted for every config. Nothing below decrements `configs` when a
  # VALUE read comes back empty. That credential is caught by the non-vacuity gate at the
  # foot of this file — zero conclusions from a non-empty keyset is "PROBED ZERO", exit 2,
  # `verdict: unavailable` — and the workflow's close arm is gated on
  # `verdict != unavailable` so it cannot close the standing coverage issue on such a run.
  #
  # The config is named EXPLICITLY on every read (`-c "$cfg"`). DOPPLER_CONFIG was unset
  # above, so an implicit bind is not merely discouraged here — it has nothing to bind to.
  # ── CONTROL C-c: this read IS the credential/config binding assertion ─────
  # Measured 2026-08-03 (Phase 0 of #7234): a config-scoped Doppler service token ERRORS
  # on a wrong `-c` — "This token does not have access to requested config 'X'", rc=1 —
  # rather than silently serving whatever config it is bound to. Confirmed in both
  # directions on root and branch configs. So `-c "$cfg"` is not decoration: pairing
  # CRED_FOR[$cfg] with `-c "$cfg"` asserts the binding on every read, and the producible
  # Terraform defect (`config = "prd"` in place of `config = each.key`, which mints 13
  # distinct tokens all bound to one config) fails twelve of these reads, counts twelve
  # configs UNREAD, and grades the run `1/13 degraded` naming them.
  #
  # That is why NO separate self-identification probe is made. An earlier design issued one
  # `doppler configs` call per credential to re-derive a binding this very next call
  # enforces — 13 extra API calls to learn what the read already tells us. The three causes
  # that design distinguished are preserved below, from the read's own failure shape.
  #
  # ONE call, with stderr captured to a reused file — not a second invocation to re-read
  # the error, which would double the round-trips and undo that argument.
  #
  # DO NOT DROP `-p`/`-c` FROM THESE READS. Without `-c` the token serves its bound config
  # regardless of which config the loop believes it is on, and the assertion silently
  # becomes a tautology.
  # CONFIGS and CRED_FOR must agree. If they ever diverge, `${CRED_FOR[$cfg]}` expands to
  # the EMPTY STRING (measured: bash does NOT abort on a missing key of an existing
  # associative array under `set -u`), and an empty DOPPLER_TOKEN is an ambient-credential
  # rebind, not a failed read — the same hazard the map validator closes one level up.
  #
  # NO REACHABLE PRODUCER TODAY, AND THIS COMMENT WILL NOT CLAIM ONE. In map mode CONFIGS
  # *is* `${!CRED_FOR[@]}`; in single mode every enumerated config is assigned the one
  # credential. So this is a floor, not a gate, and deleting it leaves the suite green —
  # stated because the alternative is a `mutation-proven` adjective with nothing behind it.
  # What made it worth adding: pointing CONFIGS at the inventory instead of the map's keys
  # produced exactly this divergence, and the resulting empty-token read was
  # indistinguishable from an honest read failure. It is here so that the NEXT edit which
  # lets the two lists drift fails loudly instead of scanning with the runner's ambient
  # credential.
  if [[ -z "${CRED_FOR[$cfg]:-}" ]]; then
    echo "::error::token_drift_missing_credential — config '$cfg' is in the scan list but has no credential; refusing to read it with an empty token." >&2
    echo "WARNING: config '$cfg' is counted UNREAD — no credential was mapped to it. The config list and the credential map disagree." >&2
    FAILED_CONFIGS+=("$cfg")
    continue
  fi
  _names=""
  _read_err=""
  if ! _names="$(DOPPLER_TOKEN="${CRED_FOR[$cfg]}" doppler secrets -p "$PROJECT" -c "$cfg" --only-names 2>"$READ_ERR_FILE")"; then
    _read_err="$(tr -d '\r' <"$READ_ERR_FILE" | head -c 400)"
    # THREE DISTINCT CAUSES, never collapsed into one. Reporting "this credential is
    # mis-bound" for what was actually a Doppler 5xx is the defect this script condemns
    # elsewhere in its own comments; each cause carries its own annotation so the
    # operator's remedy differs. All three count the config UNREAD, which is what gives
    # them a channel: it depresses `configs` below the floor, so the coverage issue files
    # and the workflow's close arm cannot fire.
    if [[ "$_read_err" == *"does not have access to requested config"* ]]; then
      echo "::error::token_drift_config_binding_mismatch — the credential mapped to config '$cfg' is not bound to it. Doppler: ${_read_err}" >&2
      echo "WARNING: config '$cfg' is counted UNREAD. Its credential is bound to a DIFFERENT config, so the minted token set and the map keys disagree — check that doppler_service_token.token_drift sets 'config = each.key' and not a string literal." >&2
    elif [[ -z "$_read_err" ]]; then
      echo "::error::token_drift_identify_empty — reading names for config '$cfg' failed with no diagnostic from the Doppler CLI." >&2
      echo "WARNING: config '$cfg' is counted UNREAD, and this run cannot say why." >&2
    else
      echo "::error::token_drift_identify_unreachable — reading names for config '$cfg' failed. Doppler: ${_read_err}" >&2
      echo "WARNING: config '$cfg' is counted UNREAD, not scanned — this is a read FAILURE, not a statement about the credential's binding." >&2
    fi
    FAILED_CONFIGS+=("$cfg")
    continue
  fi
  CONFIG_NAMES+=("$cfg")
  while read -r k; do
    [[ -z "$k" ]] && continue
    [[ -n "$ONLY_MATCH" && "$k" != *"$ONLY_MATCH"* ]] && continue
    KEYSET["$k"]=1
  done < <(printf '%s\n' "$_names" | grep -oE 'CF_API_TOKEN[A-Z0-9_]*' || true)
  # Record every key name this config carries, so the Access arm below can require that a
  # base's `_ID` half actually EXISTS somewhere in the fleet before treating it as a
  # Cloudflare Access service-token pair (see ACCESS_ID_SEEN).
  while read -r k; do
    [[ -n "$k" ]] && ALL_ID_KEYS["$k"]=1
  done < <(printf '%s\n' "$_names" | grep -oE '[A-Z0-9_]*ACCESS_TOKEN_ID' || true)
  while read -r k; do
    [[ -z "$k" ]] && continue
    [[ -n "$ONLY_MATCH" && "$k" != *"$ONLY_MATCH"* ]] && continue
    # Chained suffix strips, NOT an extglob `_@(ID|SECRET)` pattern: extglob is off by
    # default in a non-interactive shell, and an unmatched extglob silently strips
    # nothing, so the base names would keep their _ID/_SECRET suffix and the pair would
    # never be assembled. Each key ends in exactly one of the two, so chaining is exact.
    _base="${k%_ID}"; _base="${_base%_SECRET}"
    ACCESS_BASESET["$_base"]=1
  done < <(printf '%s\n' "$_names" | grep -oE '[A-Z0-9_]*ACCESS_TOKEN_(ID|SECRET)' || true)
done

# Sorted, because `config_names` is a published contract field and two runs that read the
# same set must render it identically — a consumer diffing the list should see a change
# only when the SET changed, never when Doppler's listing order did.
#
# ── CONTROL C-d: THE `-u` ───────────────────────────────────────────────────
# `configs` — the number the whole coverage ladder grades — is this array's LENGTH, so a
# duplicate in it inflates coverage directly. The producer is the enumeration: in map mode
# the keys of a JSON object are unique by construction, but in single mode the list is
# whatever `doppler configs` returned, and nothing downstream re-checks it. A duplicate
# there would length-2 this array for one config actually read.
#
# Mutation-proven by the "a duplicate in the enumeration must not inflate configs" case:
# removing `-u` makes a two-entry listing of one config report 2. Do not "simplify" it.
if (( ${#CONFIG_NAMES[@]} > 0 )); then
  mapfile -t CONFIG_NAMES < <(printf '%s\n' "${CONFIG_NAMES[@]}" | sort -u)
fi

# ── NON-VACUITY GATE ────────────────────────────────────────────────────────
# `CONFIGS` emptiness was guarded; key emptiness was not, so every path that enumerated
# NOTHING fell through to `exit 0` — a clean bill of health for a question never asked.
# That is the exact defect this script's own header condemns, one level up, and it was
# reachable two ways: a typo'd/renamed `--only` filter, and a Doppler read the caller is
# not scoped for.
#
# It matters most at the two call sites wired in the same PR as this guard: the release
# preflight prints "verified live" on exit 0, and the twice-daily scheduled arm is the only
# CONTINUOUS coverage there is.
#
# "Fleet-wide" is a claim about the CREDENTIAL, not about this gate, and #7152 measured it
# false: a config-scoped Doppler service token enumerates exactly ONE config, so a scan
# carrying one inspected 1 of 13 while reporting the same clean exit code as a scan that
# read all 13 — the "clean bill of health for a question never asked" shape of the
# paragraph above, one layer up at the scheduling layer. That is why the coverage ladder
# exists and why `configs` counts configs READ: the caller can now tell 1 of 13 from 13 of
# 13, so a `clean` verdict is only ever as wide as the published `coverage_ratio` says.
if (( ${#KEYSET[@]} + ${#ACCESS_BASESET[@]} == 0 )); then
  {
    echo "ERROR: enumerated 0 token-shaped keys across ${#CONFIG_NAMES[@]} readable config(s) of ${#CONFIGS[@]} enumerated${ONLY_MATCH:+ under --only '$ONLY_MATCH'}."
    echo "       This is a COVERAGE GAP, not a clean bill of health — nothing was checked."
    echo "       Likely causes: the --only filter matches no key; or this Doppler token"
    echo "       cannot read secret names in the scanned configs."
  } >&2
  publish_verdict || true
  exit 2
fi

declare -A VERDICT=()   # token value -> LIVE|DEAD  (verify each distinct value once)

# Sets REPLY, for the same subshell reason as verify_access_pair below: called as
# `state=$(verify_value ...)` the VERDICT writes never reached the parent, so the
# "verify each distinct value once" promise in the --only rationale was not being kept.
verify_value() {
  local v="$1"
  if [[ -z "${VERDICT[$v]:-}" ]]; then
    local ok
    ok=$(curl -s --max-time 20 -H "Authorization: Bearer $v" \
      "https://api.cloudflare.com/client/v4/user/tokens/verify" |
      python3 -c 'import json,sys
try: print("LIVE" if json.load(sys.stdin).get("success") else "DEAD")
except Exception: print("DEAD")' 2>/dev/null)
    VERDICT[$v]="${ok:-DEAD}"
    PROBES_MADE=$((PROBES_MADE + 1))
  fi
  REPLY="${VERDICT[$v]}"
}

# ── Cloudflare ACCESS SERVICE TOKENS ────────────────────────────────────────
#
# An Access service token is a client-id/secret PAIR, not an API token, so
# verify_value() above is the wrong instrument for it — /user/tokens/verify with a
# `Authorization: Bearer` header cannot say anything about a pair, and the 400/401 it
# returns would be read as DEAD for a perfectly live token. The pair is verified the way
# it is actually used: presented to an Access-protected hostname.
#
# The verdict is drawn from the presence of Cloudflare Access's own denial stamp
# (`cf-access-aud` / `cf-access-domain`), NOT from the status code — see the block above
# verify_access_pair() for the measurement that settled this and why the status code is
# the wrong instrument. Stamp present with credentials attached => DEAD; stamp gone => the
# credentials were accepted => LIVE.
#
# The 200 here is EMPTY, and that is correct, not suspicious. registry.<domain> is a
# `tcp://` tunnel ingress consumable only via `cloudflared access tcp`, so a plain HTTPS
# GET is not the WebSocket upgrade that stream needs and nothing is proxied. Cloudflare
# answers on its own. The response therefore says exactly one thing — whether Access
# ACCEPTED the credentials — which is precisely the question this script asks, and
# nothing about whether the origin is healthy. Misreading that empty 200 as "Cloudflare
# is answering without a working origin" is what consumed the 2026-07-29 incident's
# diagnostic budget; it is called out here so the next reader of this code does not
# repeat it.
#
# HOSTNAME MAPPING: which hostname a given token is authorised for is not derivable from
# its Doppler key name, so it is mapped explicitly. An enumerated token with no mapping
# is reported UNVERIFIABLE and fails the run — never silently counted LIVE. That keeps
# the enumeration Doppler-derived (a new token cannot be missed) while refusing to
# guess: a green light this script has not earned is the exact failure it exists to end.
APP_DOMAIN_BASE="${APP_DOMAIN_BASE:-soleur.ai}"
access_hostname_for() {
  case "$1" in
    REGISTRY_PUSH_ACCESS_TOKEN) printf 'registry.%s' "$APP_DOMAIN_BASE" ;;
    CI_SSH_ACCESS_TOKEN)        printf 'ssh.%s' "$APP_DOMAIN_BASE" ;;
    *) printf '' ;;
  esac
}

# NOTE ON WHY THERE IS NO ORIGIN-PROTOCOL TABLE HERE.
#
# An earlier revision (#7127) graded non-HTTP origins on the status code, mapping 5xx to
# LIVE on the theory that an ADMITTED request reaches cloudflared, which then fails to
# speak HTTP to sshd. That theory is false, and the file already said so ~25 lines above:
# a plain GET to a raw-TCP ingress is not the WebSocket upgrade the stream needs, so
# nothing is proxied and Cloudflare answers on its own.
#
# MEASURED 2026-08-01 against registry.soleur.ai with a LIVE credential — the admitted
# response is `HTTP/2 200`, zero-byte body, and NO cf-access-* header:
#
#   admitted   -> 200, 0 bytes, no Access stamp        (edge answered; origin untouched)
#   rejected   -> 403, ~39 kB, cf-access-aud + -domain (Access's own denial page)
#
# tunnel.tf's own comment records that `ssh://` and `tcp://` are the SAME raw-TCP service
# type, so ssh.<base> answers the same way. A 5xx-means-LIVE rule can therefore never
# fire, and 200 would fall to the catch-all — trading DEAD-forever for UNVERIFIABLE-
# forever. Grading on the status code is the wrong instrument regardless of which codes
# it maps, because the status is a property of the ORIGIN and the question is about the
# GATE.
#
# So the discriminator is the Access stamp, not the status. Cloudflare Access marks its
# own rejections with `cf-access-aud` / `cf-access-domain`; an admitted request is
# answered by the edge or the origin and carries neither. That is a DIFFERENTIAL proof and
# it holds for every origin protocol, which is why the http/opaque taxonomy is gone rather
# than corrected — there is nothing left for it to decide.
# A one-line hint per unmapped base, so the report can say what to DO. Without this the
# remediation printed for an unverifiable row is the DEAD-token one ("set the live value
# on the prd ROOT config"), which is wrong twice over: nothing is stale, and no Doppler
# edit fixes a missing mapping.
access_config_hint() {
  printf 'no probe configured — add a hostname mapping for %s to access_hostname_for() in %s' \
    "$1" "$(basename "${BASH_SOURCE[0]}")"
}

# ── VALUE PRE-PASS ──────────────────────────────────────────────────────────
# Every secret VALUE this scan will grade is read here, in one pass, and registered with
# the Actions log masker as it is read — so no value can reach a probe before it has been
# masked. Mask-on-read would already give "masked before ITS OWN first probe"; a full
# pre-pass gives the stronger and testable "masked before the FIRST probe of the run",
# which is what the requirement asks for and what a stub can observe.
#
# It also concentrates the four Doppler read sites: this pass owns three of them
# (`secrets get` × key / _ID / _SECRET) and the name enumeration above owns the fourth.
# Each one names its config with an explicit `-c "$cfg"` and iterates CONFIG_NAMES — the
# configs whose names were actually READ — so a config the credential cannot read is never
# graded on an empty value.
declare -A API_VALS=()       # "<key>\x1f<cfg>"  -> value
declare -A ACC_ID_VALS=()    # "<base>\x1f<cfg>" -> client id
declare -A ACC_SEC_VALS=()   # "<base>\x1f<cfg>" -> client secret
declare -A ACCESS_HOST_OF=() # base -> hostname ('' = no mapping configured)
ACCESS_BASES=()              # bases that are genuinely Cloudflare Access pairs, sorted

for key in $(printf '%s\n' "${!KEYSET[@]}" | sort); do
  for cfg in ${CONFIG_NAMES[@]+"${CONFIG_NAMES[@]}"}; do
    val=$(DOPPLER_TOKEN="${CRED_FOR[$cfg]}" doppler secrets get "$key" -p "$PROJECT" -c "$cfg" --plain 2>/dev/null)
    [[ -z "$val" ]] && continue
    API_VALS["${key}"$'\x1f'"${cfg}"]="$val"
    mask_value "$val"
  done
done

for base in $(printf '%s\n' "${!ACCESS_BASESET[@]}" | sort); do
  # A Cloudflare Access service token is a PAIR. If no `<base>_ID` exists anywhere in the
  # fleet, this base is not one — it is some other vendor's credential whose name merely
  # ends in _ACCESS_TOKEN_SECRET, and treating it as an Access pair invents a key that
  # does not exist.
  #
  # Measured against live Doppler before this guard: `X_ACCESS_TOKEN_SECRET` (an X/Twitter
  # OAuth 1.0a secret, present in 11 of 13 configs) produced base `X_ACCESS_TOKEN`, and the
  # reporting path below rendered a FABRICATED `X_ACCESS_TOKEN_ID/_SECRET` row — a
  # credential name that has never existed — inside an ops email whose entire job is naming
  # a real stale key. The scheduled arm would have sent that twice daily, forever.
  if [[ -z "${ALL_ID_KEYS[${base}_ID]:-}" ]]; then
    continue
  fi
  ACCESS_BASES+=("$base")
  ACCESS_HOST_OF["$base"]="$(access_hostname_for "$base")"
  # An unmapped base is a DETECTOR coverage gap reported without any probe, so its values
  # are never read — nothing would be done with them.
  [[ -z "${ACCESS_HOST_OF[$base]}" ]] && continue
  for cfg in ${CONFIG_NAMES[@]+"${CONFIG_NAMES[@]}"}; do
    tid=$(DOPPLER_TOKEN="${CRED_FOR[$cfg]}" doppler secrets get "${base}_ID" -p "$PROJECT" -c "$cfg" --plain 2>/dev/null)
    tsec=$(DOPPLER_TOKEN="${CRED_FOR[$cfg]}" doppler secrets get "${base}_SECRET" -p "$PROJECT" -c "$cfg" --plain 2>/dev/null)
    [[ -n "$tid" ]] && { ACC_ID_VALS["${base}"$'\x1f'"${cfg}"]="$tid"; mask_value "$tid"; }
    [[ -n "$tsec" ]] && { ACC_SEC_VALS["${base}"$'\x1f'"${cfg}"]="$tsec"; mask_value "$tsec"; }
  done
done

for key in $(printf '%s\n' "${!KEYSET[@]}" | sort); do
  for cfg in ${CONFIG_NAMES[@]+"${CONFIG_NAMES[@]}"}; do
    val="${API_VALS["${key}"$'\x1f'"${cfg}"]:-}"
    [[ -z "$val" ]] && continue
    verify_value "$val"; state="$REPLY"
    if [[ "$state" == "DEAD" ]]; then
      DEAD_N=$((DEAD_N + 1)); DEAD_ROWS+=("$key|$cfg")
    else
      LIVE_N=$((LIVE_N + 1))
    fi
  done
done

# Probe results. Set as GLOBALS and read by the caller, never returned on stdout.
#
# Every memoised helper in this file used to be invoked as `state=$(verify_...)`. Command
# substitution runs the body in a SUBSHELL, so each `CACHE[key]=...` write was discarded
# before the parent could see it and the caches never held anything: measured 3 curl calls
# for 3 configs holding one byte-identical pair, against a comment promising one. That is
# not merely wasted requests — with no cache each config re-probes independently, so one
# transient blip inside a single run grades the SAME BYTES live in four configs and dead in
# the fifth, and the DEAD remediation then tells the operator to overwrite the ROOT config
# that all five inherit. The suite's own harness comment documents this exact trap for
# run_sut; it was never applied to the code under test.
PROBE_CODE=''
PROBE_STAMPED=''              # 1 = response carries Cloudflare Access's own denial stamp
PROBE_MITIGATED=''            # 1 = Cloudflare stamped it as its OWN block/challenge
PROBE_ACCESS_REDIRECT=''      # 1 = 302 to the Access IdP login (an Access refusal too)
PROBE_SETUP_FAILED=''         # 1 = the probe could not be SET UP; not a network fact

# One HTTPS GET. With no id/secret this is the CONTROL probe.
#
# Deliberately NOT following redirects: there is no -L/--location, and T27 asserts its
# absence. curl APPENDS each response's headers into one -D file, so under -L the stamp
# grep (an OR across the whole file) would see an early block's stamp while %{http_code}
# reports the FINAL response — the two halves of the verdict would come from different
# responses, and an admitted-after-redirect would grade DEAD, the destructive direction.
PROBE_HDR=""
# ONE owning trap for the whole run (ADR-129 / lint-trap-tempfile-ownership rule (c)).
# One reused file rather than one per probe: a per-call mktemp+rm leaks on any signal
# between allocation and cleanup. The cleanup hangs off the SINGLE EXIT trap installed
# near the config loop (`_tmpfile_cleanup`), which frees this file too — installing a
# second `trap ... EXIT` here would REPLACE that one rather than add to it, silently
# disarming the read-error file's cleanup.

access_probe() {
  local host="$1" id="${2:-}" secret="${3:-}"
  local rc=0
  PROBE_SETUP_FAILED=0
  # A local disk failure is NOT a network fact. Funnelling it into the same 000 the caller
  # maps to "unreachable" sends the operator to investigate Cloudflare DNS when the real
  # cause is a full runner disk.
  if [[ -z "$PROBE_HDR" ]]; then
    PROBE_HDR=$(mktemp) || { PROBE_CODE=000; PROBE_STAMPED=0; PROBE_MITIGATED=0; PROBE_ACCESS_REDIRECT=0; PROBE_SETUP_FAILED=1; return 0; }
  fi
  # Truncate before every probe. This is belt-and-braces, NOT a live fix, and the
  # distinction is worth recording because the reuse above is what makes the question
  # arise: measured 2026-08-01, curl opens the -D dump in truncating mode unconditionally
  # — a DNS failure left the file at 0 bytes, wiping a planted `cf-access-aud`. So no
  # stale stamp can survive into the next probe today, and the `PROBE_CODE == 000` arm
  # short-circuits ahead of the stamp read in any case. The line costs nothing and keeps
  # the file's reuse obviously safe if either of those ever changes.
  : > "$PROBE_HDR" || { PROBE_CODE=000; PROBE_STAMPED=0; PROBE_MITIGATED=0; PROBE_ACCESS_REDIRECT=0; PROBE_SETUP_FAILED=1; return 0; }
  local hdr="$PROBE_HDR"
  local -a args=(-s -o /dev/null -D "$hdr" -w '%{http_code}' --max-time 20)
  [[ -n "$id" ]] && args+=(-H "CF-Access-Client-Id: $id" -H "CF-Access-Client-Secret: $secret")
  # Assigned then normalised, NOT `$(curl ... || printf '000')`. curl prints its -w output
  # AND exits non-zero on a transport failure, so the `||` form CONCATENATES: measured
  # `000000` on a DNS failure, and `200000` when a healthy 200 hits a post-header timeout —
  # which the old three-character `200)` arm then graded DEAD.
  PROBE_CODE=$(curl "${args[@]}" "https://${host}/" 2>/dev/null) || rc=$?
  (( rc != 0 )) && PROBE_CODE=000
  [[ "$PROBE_CODE" =~ ^[0-9]{3}$ ]] || PROBE_CODE=000
  if grep -qiE '^cf-access-(aud|domain):' "$hdr" 2>/dev/null; then PROBE_STAMPED=1; else PROBE_STAMPED=0; fi
  # Cloudflare stamps its OWN blocks and challenges with cf-mitigated. That is a positive
  # discriminator for the whole class the stamp alone is blind to — a rate-limit 429, a
  # managed-challenge 503, a WAF rule with a custom response status. Without it those are
  # unstamped non-refusals and would read as admission.
  if grep -qiE '^cf-mitigated:' "$hdr" 2>/dev/null; then PROBE_MITIGATED=1; else PROBE_MITIGATED=0; fi
  # An Access app with an IDENTITY policy refuses by redirecting to the IdP login rather
  # than 403-ing, and a plain 302 carries no cf-access-* header. Treating that as "no gate"
  # would report a fully-gated host as exposed. The Location host is the discriminator.
  if [[ "$PROBE_CODE" == 30? ]] && grep -qiE '^location:.*(cloudflareaccess\.com|/cdn-cgi/access/)' "$hdr" 2>/dev/null; then
    PROBE_ACCESS_REDIRECT=1
  else
    PROBE_ACCESS_REDIRECT=0
  fi
  PROBES_MADE=$((PROBES_MADE + 1))
}

declare -A PAIR_VERDICT=()   # host\x1fid\x1fsecret -> LIVE | DEAD:<code> | UNVERIFIABLE:<cause>
declare -A HOST_GATE=()      # host -> gated | ungated | blocked | indeterminate | unreachable | setup-failed

# Sets REPLY. Call directly; see the PROBE_CODE comment for why not `$( )`.
verify_access_pair() {
  local host="$1" id="$2" secret="$3"
  # Unit separator, not `|`: `id="a", secret="b|c"` and `id="a|b", secret="c"` collide
  # under a pipe join. Unreachable with real Access credentials (<32hex>.access / 64 hex),
  # but a key that can collide at all is the wrong key for a verdict that authorises an
  # overwrite of production secrets.
  local cache_key="${host}"$'\x1f'"${id}"$'\x1f'"${secret}"
  if [[ -n "${PAIR_VERDICT[$cache_key]:-}" ]]; then
    REPLY="${PAIR_VERDICT[$cache_key]}"; return 0
  fi

  # CONTROL PROBE (no credentials), once per host. Without it, "the origin is broken" and
  # "the Access application is GONE" are the same observation — and the second one grades
  # LIVE under any status-code rule, because an ungated request reaches the origin exactly
  # like an admitted one. LIVE is the only verdict this script emits with no email and no
  # annotation, so that false-LIVE rides the silent channel: the gate protecting host shell
  # access disappears and the detector reports a clean fleet.
  #
  # Classifying the control answer POSITIVELY matters as much here as it does for the
  # credential. "Unstamped" alone is not evidence of a missing gate: an Access app with an
  # IDENTITY policy refuses by 302-ing to the IdP (no stamp), a WAF/rate-limit rule refuses
  # in FRONT of Access (no stamp), and a 530 means the tunnel is down. Calling any of those
  # "nothing is gating this host" puts a fabricated SECURITY claim in an operator email —
  # the same naming-an-unmeasured-cause defect this script exists to drain, aimed at the
  # gate instead of the credential. Only an anonymous request that actually SUCCEEDS is
  # evidence that nothing refused it.
  if [[ -z "${HOST_GATE[$host]:-}" ]]; then
    access_probe "$host"
    if [[ "$PROBE_SETUP_FAILED" == 1 ]]; then HOST_GATE[$host]=setup-failed
    elif [[ "$PROBE_CODE" == 000 ]]; then HOST_GATE[$host]=unreachable
    elif [[ "$PROBE_STAMPED" == 1 || "$PROBE_ACCESS_REDIRECT" == 1 ]]; then HOST_GATE[$host]=gated
    elif [[ "$PROBE_MITIGATED" == 1 ]]; then HOST_GATE[$host]=blocked
    elif [[ "$PROBE_CODE" == 2?? ]]; then HOST_GATE[$host]=ungated
    else HOST_GATE[$host]=indeterminate
    fi
  fi

  case "${HOST_GATE[$host]}" in
    setup-failed)
      # LOCAL fault (mktemp). Not a network fact, and must not be reported as one: telling
      # the operator the host is unreachable sends them to Cloudflare/DNS when the runner
      # disk is full. Zero requests were sent.
      PAIR_VERDICT[$cache_key]="UNVERIFIABLE:detector-env" ;;
    unreachable)
      PAIR_VERDICT[$cache_key]="UNVERIFIABLE:host-unreachable" ;;
    blocked)
      PAIR_VERDICT[$cache_key]="UNVERIFIABLE:control-blocked" ;;
    indeterminate)
      PAIR_VERDICT[$cache_key]="UNVERIFIABLE:gate-indeterminate" ;;
    ungated)
      # An anonymous request SUCCEEDED (2xx, no stamp, no mitigation, no Access redirect).
      # Only that is evidence nothing refused it. Refuse to grade the credential; the
      # finding is the missing gate.
      PAIR_VERDICT[$cache_key]="UNVERIFIABLE:gate-absent" ;;
    gated)
      access_probe "$host" "$id" "$secret"
      if [[ "$PROBE_SETUP_FAILED" == 1 ]]; then
        PAIR_VERDICT[$cache_key]="UNVERIFIABLE:detector-env"
      elif [[ "$PROBE_CODE" == 000 ]]; then
        PAIR_VERDICT[$cache_key]="UNVERIFIABLE:probe-failed"
      elif [[ "$PROBE_STAMPED" == 1 ]]; then
        # Access's own page WITH credentials attached. DEAD is the destructive verdict —
        # its remedy overwrites a live credential in EVERY config that carries a copy, and
        # the report below names them one by one — so it requires the answer to actually BE
        # a refusal, not merely to carry the stamp. (This comment used to justify DEAD's
        # cost as "overwrites the prd ROOT secret every branch config inherits". That
        # premise is FALSIFIED — the same file says so ~90 lines below, and the 2026-08-02
        # census is the evidence: `CF_API_TOKEN_DNS_EDIT` is carried independently by 7
        # configs and `prd_terraform` does not carry the `REGISTRY_PUSH_ACCESS_TOKEN_*`
        # pair that `prd` root does. The cost is HIGHER than the old sentence implied, not
        # lower: there is no single write that fixes the fan-out, so a wrong DEAD costs one
        # overwrite per carrying config. The conclusion the comment defends is unchanged;
        # only its false justification is replaced.) A
        # stamped 200 is not a rejection whatever else it is; calling it one would print
        # "HTTP 200 ... rejected by Access" and order an overwrite on the strength of it.
        if [[ "$PROBE_CODE" == 401 || "$PROBE_CODE" == 403 ]]; then
          PAIR_VERDICT[$cache_key]="DEAD:${PROBE_CODE}"
        else
          PAIR_VERDICT[$cache_key]="UNVERIFIABLE:stamped-non-refusal"
        fi
      elif [[ "$PROBE_MITIGATED" == 1 || "$PROBE_ACCESS_REDIRECT" == 1 ]]; then
        # Cloudflare's own block/challenge, or an Access IdP redirect. Both are refusals
        # that carry no cf-access-* stamp.
        PAIR_VERDICT[$cache_key]="UNVERIFIABLE:refused-unstamped"
      elif [[ "$PROBE_CODE" == 2?? ]]; then
        # Stamp GONE and the request actually SUCCEEDED. Only admission does that, and this
        # is the MEASURED admitted shape (200, zero-byte body, no cf-access-*).
        #
        # This is an ALLOWLIST, and the first revision of this rewrite got it wrong: it
        # asserted LIVE as the catch-all `else` and narrowed only 401/403 out of it, which
        # certified a rate-limit 429, a challenge 503, an identity-policy 302 and a tunnel
        # 530 as healthy — measured, all rc=0, on the one verdict that emails nobody. That
        # is the absence-based reasoning this whole file rejects, and enumerating refusals
        # cannot work when the refusing layer's status is operator-configurable. LIVE now
        # requires positive evidence of success; everything unrecognised is loud.
        PAIR_VERDICT[$cache_key]="LIVE"
      else
        PAIR_VERDICT[$cache_key]="UNVERIFIABLE:unexpected-status"
      fi ;;
  esac
  REPLY="${PAIR_VERDICT[$cache_key]}"
}

for base in ${ACCESS_BASES[@]+"${ACCESS_BASES[@]}"}; do
  # The `<base>_ID must exist somewhere in the fleet` discrimination happened in the value
  # pre-pass, which is what built ACCESS_BASES — see the comment there for the fabricated
  # X_ACCESS_TOKEN_ID/_SECRET row that made it necessary.
  host="${ACCESS_HOST_OF[$base]}"
  if [[ -z "$host" ]]; then
    UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|no-probe-configured|$(access_config_hint "$base")")
    continue
  fi
  for cfg in ${CONFIG_NAMES[@]+"${CONFIG_NAMES[@]}"}; do
    tid="${ACC_ID_VALS["${base}"$'\x1f'"${cfg}"]:-}"
    tsec="${ACC_SEC_VALS["${base}"$'\x1f'"${cfg}"]:-}"
    # Both halves absent = this config simply does not carry the token. ONE half present
    # is a distinct and worse state — a half-propagated rotation, which authenticates as
    # nothing — so it is reported rather than skipped.
    if [[ -z "$tid" && -z "$tsec" ]]; then continue; fi
    if [[ -z "$tid" || -z "$tsec" ]]; then
      DEAD_N=$((DEAD_N + 1)); DEAD_ROWS+=("${base}_ID/_SECRET (only one half present)|$cfg")
      continue
    fi
    verify_access_pair "$host" "$tid" "$tsec"; state="$REPLY"
    if [[ "$state" == LIVE ]]; then
      LIVE_N=$((LIVE_N + 1))
    elif [[ "$state" == UNVERIFIABLE:* ]]; then
      # Kept OUT of DEAD_ROWS deliberately. "the probe measured nothing" and "Cloudflare
      # rejected this pair" are different facts with opposite remedies, and the DEAD
      # heading tells the operator to overwrite the secret — which, on a probe that
      # measured nothing, destroys a working credential to fix an unobserved problem.
      #
      # The CAUSE is a structured field, not prose. UNVERIFIABLE now has four disjoint
      # causes with four different remedies, and the previous revision routed all of them
      # into a section headed "this script has no probe for these keys" whose footer said
      # "add a hostname mapping to access_hostname_for()" — false for every cause except
      # the unmapped one, and reproduced verbatim in the operator's email.
      case "${state#UNVERIFIABLE:}" in
        gate-absent)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|gate-absent|${host} answered an UNCREDENTIALED request WITHOUT a Cloudflare Access denial — nothing is gating it, so this credential could not be graded and the host may be exposed. Check the Access application for ${host}. Do NOT rotate; rotating changes nothing while the gate is missing. (seen in ${cfg})") ;;
        host-unreachable)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|host-unreachable|the control probe to ${host} got no answer at all (timeout / DNS / TLS), so nothing is known about the credential. Do NOT rotate on the strength of this row; re-run once ${host} is reachable. (seen in ${cfg})") ;;
        detector-env)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|detector-env|the detector could not allocate a temp file on this runner, so NOTHING was sent to ${host}. This is a LOCAL fault (full or read-only TMPDIR), not a network or credential one. Do NOT rotate. (seen in ${cfg})") ;;
        gate-indeterminate)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|gate-indeterminate|${host} answered an uncredentialed request with HTTP ${PROBE_CODE} and no Cloudflare Access stamp, which characterises neither a gate nor its absence — a tunnel outage (530) looks like this. Nothing is known about the credential. Do NOT rotate; re-run. (seen in ${cfg})") ;;
        control-blocked)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|control-blocked|Cloudflare itself blocked or challenged the uncredentialed probe to ${host} (cf-mitigated), so the request never reached Access and the credential could not be graded. Check the WAF / rate-limit / bot-fight rules for ${host}. Do NOT rotate. (seen in ${cfg})") ;;
        stamped-non-refusal)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|stamped-non-refusal|${host} returned HTTP ${PROBE_CODE} carrying a Cloudflare Access stamp — a stamp on something that is not a refusal. This is not evidence the credential was rejected, so it is deliberately NOT reported as stale. Do NOT rotate; investigate the Access application for ${host}. (seen in ${cfg})") ;;
        unexpected-status)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|unexpected-status|${host} returned HTTP ${PROBE_CODE} with no Access stamp and no success. LIVE requires positive evidence of admission (a 2xx), so this is NOT certified — and it is not evidence of a stale credential either. Do NOT rotate; re-run and investigate the edge. (seen in ${cfg})") ;;
        refused-unstamped)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|refused-unstamped|${host} refused the credentialed request WITHOUT a Cloudflare Access stamp, while the uncredentialed control WAS stamped. Something other than Access is refusing (WAF rule, IP access rule, bot-fight), so the credential could not be graded. Do NOT rotate; investigate the rule set for ${host}. (seen in ${cfg})") ;;
        *)
          UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|probe-failed|${host} is reachable and gated, but the credentialed probe got no answer, so nothing is known about the credential. Do NOT rotate on the strength of this row; re-run. (seen in ${cfg})") ;;
      esac
    else
      DEAD_N=$((DEAD_N + 1)); DEAD_ROWS+=("${base}_ID/_SECRET (HTTP ${state#DEAD:} from ${host}, rejected by Access)|$cfg")
    fi
  done
done

# An enumerated-but-unmappable token is a real gap in this script's coverage, so it stays
# loud and non-zero (see the exit at the foot of the file).
#
# It is NOT folded into DEAD_ROWS. "Unverified" and "rejected by Cloudflare" are different
# facts with different remedies, and merging them printed unverifiable rows under the
# heading "STALE — these configs hold a token value Cloudflare no longer accepts" followed
# by "set the live value on the prd ROOT config" — sending an operator to rotate a healthy
# credential. Reporting a cause nothing measured is the defect this PR exists to drain;
# the workflow got per-stage `mirror_reason` labels for exactly this reason, and the
# detector should not be the one place that still conflates them.
UNVERIFIABLE_N=${#UNVERIFIABLE_ROWS[@]}

if [[ "$JSON_OUT" -eq 1 ]]; then
  publish_verdict || true
else
  compute_coverage
  echo "Cloudflare token drift check — project '$PROJECT'"
  # The NAMES, not just the count. `configs scanned: 1` and `configs scanned: 13` are the
  # difference between a claim about one config and a claim about the fleet, and a reader
  # of this report cannot tell WHICH configs a partial scan reached from a bare integer —
  # which is exactly the question a fan-out detector's output has to answer.
  _scanned_list="none"
  (( ${#CONFIG_NAMES[@]} > 0 )) && _scanned_list=$(IFS=,; printf '%s' "${CONFIG_NAMES[*]}")
  echo "  configs scanned: ${#CONFIG_NAMES[@]} (${_scanned_list})   API-token keys: ${#KEYSET[@]}   Access service tokens: ${#ACCESS_BASESET[@]}"
  echo "  coverage: ${COVERAGE} (ratio ${COVERAGE_RATIO}, declared floor ${CONFIGS_FLOOR})"
  if (( ${#CONFIGS_UNREAD[@]} > 0 )); then
    _unread_list=$(IFS=,; printf '%s' "${CONFIGS_UNREAD[*]}")
    echo "  configs NOT read: ${_unread_list}"
  fi
  [[ -n "$COVERAGE_CAVEAT" ]] && echo "  coverage caveat: $COVERAGE_CAVEAT"
  # `network probes` is reported, not just computed. It is the one number that separates
  # "conclusions drawn from something measured" from "conclusions drawn from Doppler reads
  # alone", and a consumer that has it does not have to re-derive this class.
  echo "  live entries: $LIVE_N   dead entries: $DEAD_N   unverifiable: $UNVERIFIABLE_N   network probes: $PROBES_MADE"
  if [[ "$DEAD_N" -gt 0 ]]; then
    echo
    echo "STALE — these configs hold a token value Cloudflare no longer accepts:"
    for r in "${DEAD_ROWS[@]}"; do echo "  ${r%%|*}  in  ${r##*|}"; done
    echo
    echo "A rotation did not propagate. Terraform will NOT fix this: the"
    echo "doppler_secret resources carry lifecycle.ignore_changes = [value], so"
    echo "'terraform apply' reports 'No changes' while the stale value persists."
    # The previous line here read "Set the live value on the 'prd' ROOT config; branch
    # configs inherit it." That is FALSIFIED, and it was the remedy printed on the acute
    # path: measured 2026-08-02, CF_API_TOKEN_DNS_EDIT is carried independently by seven
    # configs, and `prd_terraform` does not carry the REGISTRY_PUSH_ACCESS_TOKEN_* pair
    # that `prd` root does — so setting root alone repairs neither fan-out. An operator
    # who performed it would verify the one config they edited, get a green result, and
    # leave every other stale copy in place: the exact silent-and-delayed shape this
    # script's own header cites as the reason it exists.
    echo "Set the live value in EVERY config named above — Doppler branch configs do NOT"
    echo "inherit values from the 'prd' root config. Setting root alone leaves the other"
    echo "stale copies in place and looks completely successful."
  fi
  if [[ "$UNVERIFIABLE_N" -gt 0 ]]; then
    echo
    echo "UNVERIFIABLE — no conclusion was drawn about these keys."
    echo "Nothing below is known to be stale; nothing below is known to be live."
    # Rendered per CAUSE. A single static footer is what previously told the operator to
    # "add a hostname mapping" for a key that already had one — naming a cause nothing
    # measured, which is the failure this whole section exists to avoid.
    for r in "${UNVERIFIABLE_ROWS[@]}"; do
      _k="${r%%|*}"; _rest="${r#*|}"; _cause="${_rest%%|*}"; _why="${_rest#*|}"
      echo "  [${_cause}] ${_k}  —  ${_why}"
    done
    echo
    # HERESTRINGS, NOT PIPES, on all six. `printf … | grep -q` is a SIGPIPE trap under
    # `set -o pipefail`: `grep -q` exits the instant it matches, `printf` is then killed
    # with SIGPIPE, and the PIPELINE status becomes 141 — so the `if` reads FALSE on a run
    # where the pattern DID match. Reproduced here at 20,000 rows: false negative, pipeline
    # rc=141. It does not bite at today's row counts (~50 rows / ~17.5 kB fits the pipe
    # buffer, so printf finishes before grep exits), but this change takes the scan from 1
    # config to 13 — a 13x row increase — and the failure direction is silent: the
    # per-cause remedy footer vanishes from the operator's output during exactly the
    # outage that produces the most rows (host-unreachable across every config). A
    # herestring materialises the whole string first and has no second process to kill.
    if grep -q '|no-probe-configured|' <<<"$(printf '%s\n' "${UNVERIFIABLE_ROWS[@]}")"; then
      echo "  no-probe-configured: fix the DETECTOR, not the credential — add a hostname"
      echo "    mapping to access_hostname_for(). Do NOT rotate these tokens."
    fi
    if grep -q '|gate-absent|' <<<"$(printf '%s\n' "${UNVERIFIABLE_ROWS[@]}")"; then
      echo "  gate-absent: an UNCREDENTIALED request was not refused by Cloudflare Access."
      echo "    This is a GATE finding, not a credential finding — check the Access"
      echo "    application and policy for the host. Rotating the token changes nothing."
    fi
    if grep -qE '\|(host-unreachable|probe-failed)\|' <<<"$(printf '%s\n' "${UNVERIFIABLE_ROWS[@]}")"; then
      echo "  host-unreachable / probe-failed: the probe measured nothing. Re-run. Do NOT"
      echo "    rotate — an overwrite here destroys a credential no one has shown to be bad."
    fi
    if grep -qE '\|(refused-unstamped|control-blocked)\|' <<<"$(printf '%s\n' "${UNVERIFIABLE_ROWS[@]}")"; then
      echo "  refused-unstamped / control-blocked: something in FRONT of Cloudflare Access"
      echo "    refused the probe. Check the WAF / rate-limit / IP rules for the host, not"
      echo "    the credential."
    fi
    if grep -qE '\|(unexpected-status|stamped-non-refusal|gate-indeterminate)\|' <<<"$(printf '%s\n' "${UNVERIFIABLE_ROWS[@]}")"; then
      echo "  unexpected-status / stamped-non-refusal / gate-indeterminate: the edge gave an"
      echo "    answer this probe cannot classify. LIVE requires positive proof of admission"
      echo "    and DEAD requires positive proof of refusal, so neither was claimed. Do NOT"
      echo "    rotate on the strength of these rows."
    fi
    if grep -q '|detector-env|' <<<"$(printf '%s\n' "${UNVERIFIABLE_ROWS[@]}")"; then
      echo "  detector-env: a LOCAL fault on the runner (could not allocate a temp file)."
      echo "    No request was sent. Nothing about the credential or the host is implied."
    fi
  fi
fi

# --json-file is written AFTER the report above so both consumers see the same scan.
# A write failure is exit 2, not a warning: the caller branches its operator email on
# this file, and a missing file would silently take the "could not determine" arm and
# report a wrong cause — the defect class this whole script exists to prevent.
publish_verdict || exit 2

# POSITIVE-WORK FLOOR. The non-vacuity gate above counts enumerated key NAMES, which is a
# different question from whether anything was ever measured. Every value read is
# `doppler secrets get ... 2>/dev/null` followed by a skip-on-empty, so a token scoped to
# read names but not VALUES — or a Doppler 5xx mid-scan — makes every read empty, every
# loop `continue`, and the script fall through to exit 0 with `live: 0  dead: 0`. The
# caller's ladder reads that as `clean`: no email, no annotation, green job, and the
# heartbeat checks in OK. Reproduced: 0 curl invocations, exit 0.
#
# Exit 2 routes to the existing `unavailable` arm, whose email already says the right
# thing ("the detector could not run"); that channel was simply unreachable from here.
# Keyed on CONCLUSIONS DRAWN, not probes made. A half-propagated pair and an unmappable
# base are real findings reached without any probe, and gating on PROBES_MADE alone turned
# both into exit 2 "the detector could not run" — replacing a true finding with a false
# claim of coverage failure, which is the same class of lie in the other direction.
if (( LIVE_N + DEAD_N + UNVERIFIABLE_N == 0 )); then
  echo "ERROR: enumerated ${#KEYSET[@]} API key(s) and ${#ACCESS_BASESET[@]} Access base(s) but PROBED ZERO values." >&2
  echo "       Nothing was measured, so this run cannot report a clean fleet. Most likely the" >&2
  echo "       Doppler token can read secret NAMES but not VALUES, or a read failed mid-scan." >&2
  publish_verdict || true
  exit 2
fi

# Either condition is non-zero: a dead token is a live outage waiting, and an unverifiable
# one means this run cannot claim the fleet is clean.
[[ "$DEAD_N" -gt 0 || "$UNVERIFIABLE_N" -gt 0 ]] && exit 1
exit 0
