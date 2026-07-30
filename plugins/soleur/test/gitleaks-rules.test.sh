#!/usr/bin/env bash
# Pins the custom gitleaks rules in .gitleaks.toml against synthesized
# fixtures (#5079). Two non-obvious decisions are asserted:
#   1. The custom Slack rule is named `soleur-slack-webhook-url` so it ADDS to
#      the default-pack `slack-webhook-url` rule instead of shadowing it —
#      same-id child rules REPLACE default rules under [extend] useDefault,
#      which would silently drop /workflows/ webhook detection and apply our
#      per-rule allowlists to the default rule.
#   2. The second path segment is [A-Z0-9]+ (not hardcoded /B) — Slack does
#      not contractually guarantee a B prefix across webhook generations.
# All fixture URLs are synthesized (cq-test-fixtures-synthesized-only).
# Run via:  bash plugins/soleur/test/gitleaks-rules.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONFIG="$REPO_ROOT/.gitleaks.toml"

# T8/T9/T10/T11b are pure CONFIG-TEXT assertions — they need no binary, so they
# run unconditionally. Only the fixture-driven rows (T1-T7, T11) require
# gitleaks. A blanket `exit 0` here used to skip the arity/anchor guards too,
# which meant an allowlist widening could land un-guarded on any runner lacking
# the binary.
HAVE_GITLEAKS=1
if ! command -v gitleaks >/dev/null 2>&1; then
  HAVE_GITLEAKS=0
  echo "NOTE: gitleaks not installed — fixture rows (T1-T7, T11) skipped;"
  echo "      config-text guards (T8/T9/T10/T11b) still run."
fi

PASS=0
FAIL=0
fail() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}
pass() {
  echo "  pass: $1"
  PASS=$((PASS + 1))
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Fixture URLs are assembled from parts at runtime so no contiguous
# secret-shaped literal exists in this source file (GitHub push protection
# and the repo's own gitleaks scan would both flag it otherwise).
SLACK_BASE="https://hooks.slack"
SLACK_BASE="${SLACK_BASE}.com"
FAKE_TOKEN="aaaabbbbccccdddd"
FAKE_TOKEN="${FAKE_TOKEN}eeeeffff"
DC_BASE="https://discord"
DC_BASE="${DC_BASE}.com/api/webhooks"
# 64 synthesized chars built by repetition — no >16-char contiguous literal.
DC_TOKEN="SYNTH$(printf 'aBc9%.0s' {1..14})xyz"
# Same split-literal reason as above: this file is NOT in the
# database-url-with-password path allowlist, so a contiguous credential-shaped
# DSN literal here trips our own rule. Only the angle-bracket placeholder form
# `postgres://<user>:<pw>@host` is safe to write out in full.
# BOTH schemes are assembled at runtime. Interpolating a shell variable into the
# password position does NOT make a line safe: `$`, `{` and `}` all sit inside the
# rule's password class `[^@/\s]+`, so a scheme+user+$VAR+@host line still matches.
# Keep every DSN in this file either fully assembled at runtime or in the
# angle-bracket placeholder form.
PG="postgres"
PGQL="${PG}ql://"
PG="${PG}://"
# The REAL password tail in a multi-@ DSN (#6723): everything after the first
# '@' up to the host. Split for the same reason as the literals above.
SEC_TAIL="Xq7vNp2"
SEC_TAIL="${SEC_TAIL}LmWd4"
# Scheme variants (T7d/T7e), assembled for the same reason as the literals above.
PG_DRV1="${PGQL%://}"; PG_DRV1="${PG_DRV1}+psycopg2://"
PG_DRV2="${PGQL%://}"; PG_DRV2="${PG_DRV2}+asyncpg://"
PG_CAPS="Post"; PG_CAPS="${PG_CAPS}gres://"
PG_UPPER="POST"; PG_UPPER="${PG_UPPER}GRES://"

# The token-drift harness's invented Cloudflare Access service-token secret
# (#7071) and a same-shape sibling used as the value-dimension control. Split
# into 8-char chunks for the same reason as the literals above, with one extra
# constraint: `generic-api-key` matches `<kw>[:=]` followed by 16+ chars of
# [A-Za-z0-9_-], so a 16-char chunk on a `*_SECRET=` line is already a finding.
# 8-char chunks stay under that floor, and appends interpolate `${...}` — `$`,
# `{` and `}` all sit OUTSIDE the rule's secret class, so an append line cannot
# match either. The variable names are deliberately keyword-free for the same
# reason. This file is NOT the path the #7071 carve-out is scoped to, so a
# contiguous literal here would be a real finding, not an allowlisted one.
DRIFT_VAL="fedcba98"; DRIFT_VAL="${DRIFT_VAL}76543210"
DRIFT_VAL="${DRIFT_VAL}${DRIFT_VAL}"; DRIFT_VAL="${DRIFT_VAL}${DRIFT_VAL}"
OTHER_VAL="0f1e2d3c"; OTHER_VAL="${OTHER_VAL}4b5a6978"
OTHER_VAL="${OTHER_VAL}${OTHER_VAL}"; OTHER_VAL="${OTHER_VAL}${OTHER_VAL}"
# The path the carve-out is scoped to, assembled so this line is not itself the
# thing under test when someone greps for it.
DRIFT_PATH="scripts/check-cloudflare-token-drift.test.sh"

# scan_rules <fixture-line> -> newline-separated RuleIDs that fired
scan_rules() {
  local fixture_dir="$TMP/scan.$RANDOM"
  mkdir -p "$fixture_dir"
  printf '%s\n' "$1" > "$fixture_dir/fixture.txt"
  gitleaks dir "$fixture_dir" --config "$CONFIG" --no-banner \
    --report-format json --report-path "$fixture_dir/report.json" >/dev/null 2>&1
  jq -r '.[].RuleID' "$fixture_dir/report.json" 2>/dev/null | sort -u
}

# scan_rules_at <scan-root-relative-path> <fixture-line>
#   -> sets SCAN_RULES to the newline-separated RuleIDs that fired.
#
# Distinct from scan_rules because `paths` allowlist entries are matched against
# the scan-root-relative path, and scan_rules always writes `fixture.txt` — so a
# path-scoped carve-out is structurally INVISIBLE to it. T11 tests the
# path/value INTERACTION, so it needs control over both halves.
#
# Returns through a GLOBAL, not stdout, and callers must invoke it DIRECTLY —
# never as `x=$(scan_rules_at …)`. Command substitution runs the callee in a
# SUBSHELL, which discards every effect except stdout: the per-call sequence
# counter this helper first used was incremented there, so the increment was
# thrown away, all four T11 rows scanned ONE accumulating tree, and each
# must-FIRE row passed off a SIBLING row's fixture — three green positive
# controls that could not see the mutation they existed to catch (measured: the
# path-anchor and path-widening mutants both stayed green). A subshell would
# also swallow the FATAL `exit 2` below, turning a fixture error into a verdict
# about the config.
#
# The report is written OUTSIDE the scan root: a report.json landing inside the
# tree being scanned is a fixture the next assertion never asked for.
#
# The `cd "$root" && gitleaks dir .` shape is LOAD-BEARING and not a style
# choice. gitleaks reports `File` relative to the target it was given, so
# `gitleaks dir "$root"` emits ABSOLUTE paths and every `^`-anchored `paths`
# entry silently stops matching — measured: the #7071 row read as a config
# regression when the config was correct and the harness was not. CI invokes
# `gitleaks dir .` from the repo root, so mirroring that is what makes an
# anchored entry mean here what it means in CI. Subshelled so CWD cannot leak
# into a later row.
SCAN_RULES=""
scan_rules_at() {
  local rel="$1" content="$2" root report nfiles
  root=$(mktemp -d "$TMP/root.XXXXXXXX") \
    || { echo "FATAL: scan_rules_at could not create a scan root" >&2; exit 2; }
  # Derived from the unique root, so it is unique too, and it sits beside the
  # root rather than inside it.
  report="${root}.report.json"
  mkdir -p "$root/$(dirname "$rel")" \
    || { echo "FATAL: scan_rules_at mkdir failed for $rel" >&2; exit 2; }
  printf '%s\n' "$content" > "$root/$rel" \
    || { echo "FATAL: scan_rules_at write failed for $rel" >&2; exit 2; }
  # Isolation self-check. Exactly one fixture per scan root is the property that
  # makes a must-FIRE row mean anything; without it a row can pass off a
  # neighbour's file. Fail as a FIXTURE error, never as a verdict about the SUT.
  nfiles=$(find "$root" -type f | wc -l | tr -d ' ')
  if [[ "$nfiles" != "1" ]]; then
    echo "FATAL: scan root holds $nfiles files, expected 1 — T11 fixtures are leaking across rows" >&2
    exit 2
  fi
  ( cd "$root" && gitleaks dir . --config "$CONFIG" --no-banner \
      --report-format json --report-path "$report" >/dev/null 2>&1 )
  SCAN_RULES=$(jq -r '.[].RuleID' "$report" 2>/dev/null | sort -u)
}

echo "=== gitleaks custom-rule fixture tests ==="
echo ""

if [[ "$HAVE_GITLEAKS" == "1" ]]; then

echo "T1: canonical /services/ Slack webhook fires BOTH rules (no default shadowing)"
rules=$(scan_rules "${SLACK_BASE}/services/T0000FAKE/B0000FAKE/${FAKE_TOKEN}")
if grep -qx 'soleur-slack-webhook-url' <<<"$rules"; then
  pass "soleur-slack-webhook-url fires"
else
  fail "soleur-slack-webhook-url must fire (got: ${rules:-<none>})"
fi
if grep -qx 'slack-webhook-url' <<<"$rules"; then
  pass "default-pack slack-webhook-url still live (rename did not shadow it)"
else
  fail "default-pack slack-webhook-url must also fire (got: ${rules:-<none>})"
fi

echo "T2: non-B second segment still detected by the custom rule"
rules=$(scan_rules "${SLACK_BASE}/services/T0000FAKE/XQ99ZZ11Y/${FAKE_TOKEN}")
if grep -qx 'soleur-slack-webhook-url' <<<"$rules"; then
  pass "non-B segment fires soleur-slack-webhook-url"
else
  fail "non-B segment must fire soleur-slack-webhook-url (got: ${rules:-<none>})"
fi

echo "T3: /workflows/ webhook covered by the unshadowed default rule"
rules=$(scan_rules "${SLACK_BASE}/workflows/T0000FAKE/A0000FAKE/11111111/${FAKE_TOKEN}")
if grep -qx 'slack-webhook-url' <<<"$rules"; then
  pass "/workflows/ URL fires default slack-webhook-url"
else
  fail "/workflows/ URL must fire the default rule (got: ${rules:-<none>})"
fi

echo "T4: Discord webhook rule still fires"
rules=$(scan_rules "${DC_BASE}/000000000000000001/${DC_TOKEN}")
if grep -qx 'discord-webhook-url' <<<"$rules"; then
  pass "discord-webhook-url fires"
else
  fail "discord-webhook-url must fire (got: ${rules:-<none>})"
fi

echo "T5: benign content fires nothing"
rules=$(scan_rules 'release notes link: https://github.com/jikig-ai/soleur/releases/tag/v1.0.0')
if [[ -z "$rules" ]]; then
  pass "no rule fires on benign content"
else
  fail "benign content must not fire (got: $rules)"
fi

echo "T6: documentation placeholder shapes stay allowlisted (#6706)"
# The shapes the rule is MEANT to permit. This is the pre-existing allowlist —
# #6706 deliberately does NOT widen it (see T7's note).
for ph in "user:password" "USER:PASSWORD" "postgres:secret" "<user>:<pw>" "user:***"; do
  rules=$(scan_rules "${PG}${ph}@db.example.com")
  if grep -qx 'database-url-with-password' <<<"$rules"; then
    fail "placeholder ${ph} must stay allowlisted (rule fired)"
  else
    pass "placeholder ${ph} quiet"
  fi
done

echo "T7: real credentials still fire — one VARIED dimension per row (#6706)"
# T7 is also T6's POSITIVE CONTROL. T6 is a pure must-not-fire block, so it
# passes vacuously whenever the scanner is degraded (e.g. `jq` missing =>
# scan_rules returns empty for every input, so every T6 row "passes"). T7 is the
# must-fire half that goes loud in exactly that case. Do not delete or skip T7
# without replacing that control, or T6 silently becomes a permanent no-op.
#
# Each row holds every dimension at a known-good value and varies exactly ONE.
# Sampling a single point per dimension is what makes a guard like this vacuous:
# with all rows sharing one host/scheme/user, mutating the rule's host class,
# dropping `postgresql://`, or adding a password length floor each leave the
# suite fully green while real credentials go undetected.
REALPW="Xk9tR2m"          # split so no contiguous credential literal lives here
REALPW="${REALPW}Qw7vLp4Zc"
for row in \
  "USER-side|${PG}postgres:${REALPW}@db.example.com" \
  "host|${PG}user:${REALPW}@prod.internal.corp" \
  "scheme-ql|${PGQL}user:${REALPW}@db.example.com" \
  "short-password|${PG}user:pw2@db.example.com" \
  "placeholder-prefix-only|${PG}user:pass-but-longer@db.example.com" \
  ; do
  label="${row%%|*}"
  fixture="${row#*|}"
  rules=$(scan_rules "$fixture")
  if grep -qx 'database-url-with-password' <<<"$rules"; then
    pass "real credential still fires (${label})"
  else
    fail "real credential MUST fire (${label}) — rule regex or allowlist over-matches"
  fi
done

echo "T7b: multi-@ credentials fire (#6723 — the bypass this rule change closes)"
# Every real URL parser takes userinfo to the LAST '@'. The old rule's password
# class stopped at the FIRST '@', and the allowlist entry was an unanchored
# SEARCH against that truncated match — so a real password containing '@' put a
# placeholder prefix (`user:password@`) at the start of the match and silenced
# the whole finding. Measured: all four were silenced before this change.
#
#   <scheme>://user:password@<REAL>@db.prod.example.com
#                ^^^^^^^^^^^^ allowlist matched this substring
#                             ^^^^^^ ...while THIS was the actual password
#
# The scheme is written `<scheme>` rather than spelled out: the rule is
# keyword-gated on the literal `postgres://`, so a spelled-out example here
# would make this very comment a finding under the widened rule — the trap
# this PR exists to close, re-entering through the file that documents it.
for row in \
  "multi-at-password|${PG}user:password@${SEC_TAIL}@db.prod.example.com/appdb" \
  "multi-at-user|${PG}<anything>:password@${SEC_TAIL}@db.prod.example.com" \
  "multi-at-secret|${PG}user:secret@${SEC_TAIL}@db.example.com" \
  "multi-at-redacted|${PG}user:***@${SEC_TAIL}@db.example.com" \
  ; do
  label="${row%%|*}"
  fixture="${row#*|}"
  rules=$(scan_rules "$fixture")
  if grep -qx 'database-url-with-password' <<<"$rules"; then
    pass "multi-@ credential fires (${label})"
  else
    fail "multi-@ credential MUST fire (${label}) — #6723 bypass is open"
  fi
done

echo "T7d: scheme variants fire (case-insensitive + SQLAlchemy/asyncpg +driver)"
# Both were measured rc=0 (undetected) before this change. The keyword prefilter
# is the load-bearing half: it runs BEFORE the regex, so `keywords =
# ["postgres://"]` suppressed `postgresql+psycopg2://` no matter how correct the
# regex was — a fix that widened only the regex would have been silently vacuous.
for row in \
  "sqlalchemy-driver|${PG_DRV1}svc_prod:${SEC_TAIL}@db.prod.internal/appdb" \
  "asyncpg-driver|${PG_DRV2}svc_prod:${SEC_TAIL}@db.prod.internal/appdb" \
  "capitalised-scheme|${PG_CAPS}svc_prod:${SEC_TAIL}@db.prod.internal/appdb" \
  "upper-scheme|${PG_UPPER}svc_prod:${SEC_TAIL}@db.prod.internal/appdb" \
  ; do
  label="${row%%|*}"
  fixture="${row#*|}"
  rules=$(scan_rules "$fixture")
  if grep -qx 'database-url-with-password' <<<"$rules"; then
    pass "scheme variant fires (${label})"
  else
    fail "scheme variant MUST fire (${label}) — check the keywords prefilter, not just the regex"
  fi
done

echo "T7e: placeholders stay quiet under the case-insensitive rule"
# The allowlist is anchored `^...$`; widening the rule with (?i) without
# mirroring (?i) here would make a capitalised placeholder a finding.
for row in \
  "placeholder-capitalised|${PG_CAPS}USER:PASSWORD@host" \
  "placeholder-driver|${PG_DRV1}user:password@host" \
  ; do
  label="${row%%|*}"
  fixture="${row#*|}"
  rules=$(scan_rules "$fixture")
  if grep -qx 'database-url-with-password' <<<"$rules"; then
    fail "placeholder MUST stay quiet (${label}) — allowlist did not mirror the rule's widening"
  else
    pass "placeholder stays quiet (${label})"
  fi
done

echo "T7c: bracket-userinfo credentials fire (regression net for the widened class)"
# These are the reason this PR does NOT ship the fix proposed in #6723's body.
# Widening the password class to `[^/\s]+` lets '@' and ':' live inside the
# password. The issue's candidate kept an `<[^>]+>` placeholder branch, which
# ALSO permits '@' and ':' — so an entire real credential fits inside what the
# allowlist certifies as "a placeholder":
#
#   <scheme>://user:<admin:R3alPassw0rd@prod.db.internal>@x.com
#                   ^-------- allowlisted as a "placeholder" --------^
#
# Measured: all three are DETECTED today and SILENCED by the issue's candidate —
# it would have made the gate strictly worse for them, the same defect class that
# got the earlier widening reverted, re-entering through a different branch.
# The shipped form hardens both branches to `<[^>@:]+>`. These rows are the
# guard: they go RED against the unhardened candidate.
for row in \
  "bracket-userinfo-colon|${PG}user:<admin:${REALPW}@prod.db.internal>@x.com" \
  "bracket-userinfo-plain|${PG}user:<${REALPW}@prod-db.internal.corp>@localhost" \
  "bracket-userinfo-port|${PG}user:<admin:${REALPW}@prod.db.internal>@x.com:5432/appdb" \
  ; do
  label="${row%%|*}"
  fixture="${row#*|}"
  rules=$(scan_rules "$fixture")
  if grep -qx 'database-url-with-password' <<<"$rules"; then
    pass "bracket-userinfo credential fires (${label})"
  else
    fail "bracket-userinfo credential MUST fire (${label}) — allowlist bracket branch permits @ or :"
  fi
done

echo "T11: the token-drift secret carve-out is value AND path scoped (#7071)"
# The carve-out silences ONE invented 64-hex Access service-token secret in ONE
# file. `condition = "AND"` is what makes that true, and each row below varies
# exactly one dimension so a collapse in either direction goes RED:
#
#   row 1  must NOT fire — the case the carve-out exists for
#   row 2  must FIRE     — same path, different value. Goes RED if the AND
#                          degrades to OR (the default), which would blind the
#                          whole file to generic-api-key.
#   row 3  must FIRE     — same value, sibling path under scripts/. Goes RED if
#                          the entry is ever widened to `scripts/.*\.test\.sh$`.
#   row 4  must FIRE     — same value, laundering parent dir. Goes RED if the
#                          path entry's leading ^ is dropped: gitleaks matches
#                          `paths` as a SEARCH, so unanchored, any parent
#                          directory carries the exemption with it.
#
# Row 1 alone would be a pure must-not-fire block — vacuous the moment the
# scanner degrades (jq missing => every row "passes"). Rows 2-4 are its positive
# control; do not delete them without replacing that control.
# Every scan_rules_at call below is a DIRECT invocation reading SCAN_RULES —
# see the helper's contract for why `$(scan_rules_at …)` is forbidden here.
drift_fixture() { printf 'FIX_SECRET="%s"' "$1"; }

scan_rules_at "$DRIFT_PATH" "$(drift_fixture "$DRIFT_VAL")"
if grep -qx 'generic-api-key' <<<"$SCAN_RULES"; then
  fail "the carved-out fixture value MUST stay quiet at $DRIFT_PATH (got: ${SCAN_RULES:-<none>})"
else
  pass "carved-out fixture value quiet at its own path"
fi

for row in \
  "different-value-same-path|${DRIFT_PATH}|${OTHER_VAL}" \
  "same-value-sibling-path|scripts/check-some-other-thing.test.sh|${DRIFT_VAL}" \
  "same-value-laundered-parent|evil/${DRIFT_PATH}|${DRIFT_VAL}" \
  ; do
  label="${row%%|*}"
  rest="${row#*|}"
  relpath="${rest%%|*}"
  value="${rest#*|}"
  scan_rules_at "$relpath" "$(drift_fixture "$value")"
  if grep -qx 'generic-api-key' <<<"$SCAN_RULES"; then
    pass "still fires (${label})"
  else
    fail "MUST still fire (${label}) — the #7071 carve-out has collapsed from value-AND-path to a whole-file or whole-value exemption"
  fi
done

fi  # HAVE_GITLEAKS

echo "T8: the placeholder allowlist stays a SINGLE entry"
# Arity guard. Every behavioural row above tests the SHAPE of one regex; none can
# see a SECOND array element being appended. That is the cheapest real escape:
# generalising the Supabase-CLI loopback carve-out into a broad
# `postgres://postgres:<anything>@` branch silences production credentials while
# T6/T7 stay entirely green. Block-scoped with an explicit `[[rules]]` terminator
# so a sibling rule's `regexes` line cannot be swallowed into the count.
db_block=$(awk '/^id = "database-url-with-password"/{f=1; next} f && /^\[\[rules\]\]/{exit} f{print}' "$CONFIG")
regexes_line=$(grep '^  regexes = ' <<<"$db_block" || true)
regexes_count=$(grep -c '^  regexes = ' <<<"$db_block" || true)
# 2 triple-quote runs == exactly one '''...''' element.
quote_runs=$(grep -o "'''" <<<"$regexes_line" | wc -l | tr -d ' ')
if [[ "$regexes_count" == "1" && "$quote_runs" == "2" ]]; then
  pass "database-url-with-password carries exactly one regexes entry"
else
  fail "expected 1 regexes line holding 1 entry; got lines=${regexes_count} quote_runs=${quote_runs} (2 == one entry)"
fi

echo "T9: the placeholder allowlist entry stays FULLY ANCHORED and @/:-free"
# Behavioural rows cannot see the anchors being dropped while the sampled rows
# coincidentally survive. Allowlist `regexes` match the SECRET (the whole rule
# match, there being no secretGroup), so an unanchored entry is a SEARCH: a
# placeholder prefix anywhere inside a real credential silences it — precisely
# the #6723 bypass. Both anchors are load-bearing; removing either must go RED.
#
# The bracket branches must also exclude '@' and ':'. With the widened password
# class those characters are legal inside the password, so a bare `<[^>]+>`
# lets a whole credential masquerade as a placeholder (see T7c). Guarding the
# anchors alone would not catch that.
# Scope every assertion below to the `regexes` LINE, never the whole rule block.
# The block also holds the `paths` line, whose last entry ends `...\.md$'''` — so
# a block-scoped end-anchor check matches THAT and passes even when the regexes
# entry is unanchored. (Observed: this exact false pass, on the first run of this
# guard. A guard that matches a sibling line is the defect this PR exists to fix.)
# `^` must come FIRST. An inline flag group may follow it: the rule became
# case-insensitive with the +driver / capitalised-scheme widening (T7d), and the
# allowlist has to mirror that or a capitalised PLACEHOLDER becomes a finding
# (T7e). `^` has no case, so anchor-then-flag is equivalent to anchor-only and
# keeps this guard exactly as strict — the flag cannot be used to smuggle the
# anchor away.
if grep -qE "^  regexes = \['''\^(\(\?i\))?postgres" <<<"$regexes_line"; then
  pass "allowlist entry is start-anchored (^)"
else
  fail "allowlist entry MUST start with ^ — unanchored, a placeholder prefix inside a real credential silences it (#6723)"
fi
if grep -qE "\\\$'''\]$" <<<"$regexes_line"; then
  pass "allowlist entry is end-anchored (\$)"
else
  fail "allowlist entry MUST end with \$ — without it the entry matches a prefix of a longer credential"
fi
bracket_unsafe=$(grep -c '<\[^>\]+>' <<<"$regexes_line" || true)
if [[ "$bracket_unsafe" == "0" ]]; then
  pass "no bare <[^>]+> branch (brackets exclude @ and :)"
else
  fail "found $bracket_unsafe bare <[^>]+> branch(es) — with the widened password class a whole credential fits inside the brackets (T7c)"
fi

echo "T10: the database-url-with-password PATHS allowlist stays pinned"
# Nothing guarded `paths` before this. T6-T9 are all fixture- or regex-shaped,
# and scan_rules writes every fixture to `fixture.txt`, where no realistic path
# entry can ever match — so appending e.g. '''plugins/soleur/.*\.md$''' would
# blind an entire subtree to this rule while every other row stayed green.
# Pinned to the shipped count; widening it is a deliberate, visible edit.
EXPECTED_PATHS=13
paths_line=$(grep '^  paths = ' <<<"$db_block" || true)
paths_count=$(grep -o "'''" <<<"$paths_line" | wc -l | tr -d ' ')
paths_entries=$((paths_count / 2))
if [[ "$paths_entries" == "$EXPECTED_PATHS" ]]; then
  pass "paths allowlist holds exactly $EXPECTED_PATHS entries"
else
  fail "paths allowlist entry count changed: expected $EXPECTED_PATHS, got $paths_entries — widening this blinds whole subtrees to the DSN rule; update EXPECTED_PATHS deliberately"
fi
# The review-skill carve-out is the one path entry added for #6723. Its leading
# ^ is load-bearing: gitleaks matches path entries as a SEARCH against the
# scan-root-relative path, so unanchored, ANY parent directory launders a real
# DSN (measured: evil/plugins/soleur/skills/review/SKILL.md silenced).
if grep -qF "'''^plugins/soleur/skills/review/SKILL\\.md\$'''" <<<"$paths_line"; then
  pass "review-skill path carve-out is anchored ^...\$"
else
  fail "review-skill path carve-out must be anchored '^plugins/soleur/skills/review/SKILL\\.md\$' — unanchored, any parent dir launders a real DSN"
fi

echo "T11b: the #7071 generic-api-key carve-out stays single-entry and AND-scoped"
# The arity half of T11. T11's fixture rows all test the SHAPE of the two
# entries; none can see a SECOND element being appended to either array, which
# is the cheapest real escape — one extra path or one extra regex widens the
# exemption while every T11 row stays green. Block-scoped from the rule's `id`
# line to the next `[[rules]]` so a sibling rule's lines cannot be counted.
gak_block=$(awk '/^id = "generic-api-key"/{f=1; next} f && /^\[\[rules\]\]/{exit} f{print}' "$CONFIG")

# `condition` is load-bearing and has no safe default here: gitleaks defaults to
# OR, under which the path entry alone blinds the entire file to this rule. T11
# row 2 catches that behaviourally; this is the direct pin, and it survives on a
# runner with no gitleaks binary.
cond_count=$(grep -c '^  condition = "AND"$' <<<"$gak_block" || true)
if [[ "$cond_count" == "1" ]]; then
  pass "carve-out declares exactly one condition = \"AND\""
else
  fail "expected exactly 1 'condition = \"AND\"' line in the generic-api-key rule; got ${cond_count} — without it gitleaks defaults to OR and the path entry alone blinds the whole file"
fi

# 2 triple-quote runs == exactly one '''...''' element, matching T8/T10's idiom.
drift_paths_line=$(grep '^  paths = ' <<<"$gak_block" | grep -F 'check-cloudflare-token-drift' || true)
drift_paths_runs=$(grep -o "'''" <<<"$drift_paths_line" | wc -l | tr -d ' ')
# 0 runs and 4+ runs are different failures and must not share a message: 0 means
# the carve-out's paths line is gone or no longer names the fixture at all, 4+
# means a second entry was appended. Reporting the second wording for the first
# sends the reader looking for an entry that is not there.
if [[ "$drift_paths_runs" == "2" ]]; then
  pass "carve-out paths array holds exactly one entry"
elif [[ "$drift_paths_runs" == "0" ]]; then
  fail "no paths line in the generic-api-key rule names check-cloudflare-token-drift — the #7071 carve-out was removed or its path predicate was rewritten"
else
  fail "carve-out paths array must hold exactly 1 entry; got quote_runs=${drift_paths_runs} (2 == one entry) — a second path entry widens the exemption invisibly to T11"
fi
if grep -qF "'''^scripts/check-cloudflare-token-drift\\.test\\.sh\$'''" <<<"$drift_paths_line"; then
  pass "carve-out path entry is anchored ^...\$"
else
  fail "carve-out path entry must be exactly '^scripts/check-cloudflare-token-drift\\.test\\.sh\$' — gitleaks matches paths as a SEARCH, so unanchored, any parent dir carries the exemption (T11 row 4)"
fi

# The generic-api-key rule has exactly one `regexes` line — the carve-out's.
gak_regexes_line=$(grep '^  regexes = ' <<<"$gak_block" || true)
gak_regexes_count=$(grep -c '^  regexes = ' <<<"$gak_block" || true)
gak_regexes_runs=$(grep -o "'''" <<<"$gak_regexes_line" | wc -l | tr -d ' ')
if [[ "$gak_regexes_count" == "1" && "$gak_regexes_runs" == "2" ]]; then
  pass "carve-out regexes array holds exactly one entry"
else
  fail "expected 1 regexes line holding 1 entry in the generic-api-key rule; got lines=${gak_regexes_count} quote_runs=${gak_regexes_runs} (2 == one entry)"
fi
# Allowlist `regexes` match the SECRET. Unanchored, this value as a PREFIX of a
# longer real credential would silence it — the same defect class as #6723.
if grep -qE "^  regexes = \['''\^[a-f0-9]{64}\\\$'''\]$" <<<"$gak_regexes_line"; then
  pass "carve-out regex entry is a fully-anchored ^<64 hex>\$ literal"
else
  fail "carve-out regex entry must be a fully-anchored '^<64 hex>\$' literal — unanchored or widened, it silences any credential containing the fixture value (#6723 class)"
fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
