#!/usr/bin/env bash
# Tests inngest-boot-phone-home.sh — the boot-trace emitter embedded in cloud-init-inngest.yml
# (#7228 Phase 2; the plan's "loud emitter", a real cq-silent-fallback-must-mirror-to-sentry
# violation that every plan reviewer independently voted to KEEP).
#
# THE DEFECT. The emitter is the SINGLE delivery path for all eight SOLEUR_INNGEST_BOOT_STAGE
# markers — the entire diagnosis of a boot failure on a host with no SSH. It opened with
#
#     [ -r "$tok_file" ] || exit 0
#     [ -n "$bs_token" ] || exit 0
#     curl ... >/dev/null 2>&1
#     exit 0
#
# so all three of its failure modes were EXIT 0 WITH NO OUTPUT. It could not report its own death
# by construction. Combined with the tmpfs defect (every write of /run/inngest-bs-logs-token lives
# in `runcmd:`, which cloud-init runs on FIRST BOOT ONLY, and /run is cleared every reboot), a
# host that reboots once is dark FOREVER and the silence is indistinguishable from health. That is
# the #7228 shape exactly: a signal whose absence reads as "nothing to report".
#
# WHY journald AND NOT the emitter's own POST. Because the POST is the thing that failed. The two
# channels are INDEPENDENT at the credential level, which is what makes this defense-in-depth
# rather than a loop: the emitter reads /run/inngest-bs-logs-token (staged by cloud-init), while
# vector.service resolves BETTERSTACK_LOGS_TOKEN from Doppler at ExecStart (inngest-bootstrap.sh,
# vector.toml:526). So the exact failure that silences the emitter — a missing/empty token file —
# leaves the journald->Vector->Better Stack path fully operational.
#
# DEVIATION FROM THE PLAN, RECORDED. The plan said to emit on an ALREADY-ALLOWLISTED identifier
# specifically to avoid opening a fresh Source-4 quota decision. That is not available here:
# journald-config.test.sh CF-4 asserted, in BOTH directions, that this emitter never calls
# `logger` and that "inngest-boot-phone-home" is absent from the allowlist — and reusing some
# OTHER script's tag would misattribute these rows to a producer that did not emit them. CF-4's
# rationale is explicitly conditional ("it never calls logger, SO an allowlist entry would be a
# permanently-dead no-op"), so the correct move is the one that file already makes for ci-deploy
# at R1-1.8: flip the negative pair into a POSITIVE pair. The quota cost of the new tag is bounded
# by construction — the emitter is SILENT ON SUCCESS, so a healthy host pays zero rows, and a
# fully-dark one pays one row per phone-home call site per boot (~15).
#
# NO SECRET RIDES THE NEW CHANNEL. The rows carry the stage name plus a numeric reason (curl rc /
# HTTP code) and NEVER $detail — which matters most on the missing-token arm, where the emitter
# exits BEFORE the redaction at :125 has run. This is the P1-SEC lesson from the inngest-redis
# allowlist entry in journald-config.test.sh: opening a Source-4 tag opens a route from that
# producer's output to Better Stack, so the producer's output is what has to be safe.
#
# Run: bash apps/web-platform/infra/inngest-boot-emitter.test.sh

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT="$SCRIPT_DIR/cloud-init-inngest.yml"
VECTOR_TOML="$SCRIPT_DIR/vector.toml"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
assert() {
  local desc="$1" cond="$2"
  if eval "$cond" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

[[ -r "$CLOUD_INIT" ]] || { echo "FATAL: $CLOUD_INIT unreadable"; exit 2; }
[[ -r "$VECTOR_TOML" ]] || { echo "FATAL: $VECTOR_TOML unreadable"; exit 2; }

WORK="$(mktemp -d)" || { echo "FATAL: mktemp failed"; exit 2; }
HEALTH_PID=""
cleanup() { rm -rf "$WORK"; [[ -n "$HEALTH_PID" ]] && kill "$HEALTH_PID" 2>/dev/null; }
trap cleanup EXIT

echo "--- #7228: inngest-boot-phone-home.sh must never fail silently ---"

# --- extract the emitter from the write_files block ------------------------------------------
# Same awk boundary journald-config.test.sh:307 uses (path line to the next `- path:`), then drop
# the `content: |` line and dedent the 6-space YAML block scalar. A harness that silently produced
# an EMPTY script would make every "exits 0" assertion below pass vacuously, so the extraction is
# asserted before anything is driven through it.
EMITTER="$WORK/inngest-boot-phone-home.sh"
awk '/^  - path: \/usr\/local\/bin\/inngest-boot-phone-home\.sh$/{f=1;next} f&&/^  - path: /{f=0} f' \
  "$CLOUD_INIT" | sed -e '/^    content: |$/d' -e 's/^      //' \
  | sed -e '/^    owner:/d' -e '/^    permissions:/d' > "$EMITTER"
chmod +x "$EMITTER"

assert "extraction: the emitter body was recovered (non-empty, has the shebang and the POST)" \
  "[[ -s '$EMITTER' ]] && head -1 '$EMITTER' | grep -q '^#!' && grep -q 'betterstackdata.com' '$EMITTER'"
assert "extraction: the emitter is syntactically valid bash (dedent did not corrupt it)" \
  "bash -n '$EMITTER'"

# --- the tag is DERIVED from the emitter, never restated --------------------------------------
# Two hardcoded copies of the tag would agree with each other while both disagreeing with the
# script — a guard that passes precisely when it is wrong (journald-config.test.sh R1-1.8).
EMITTER_TAG="$(grep -oE '^[[:space:]]*logger -t [A-Za-z0-9._-]+' "$EMITTER" | head -1 | awk '{print $3}' || true)"
assert "the emitter declares a logger tag at all (this is the whole fix: it used to be silent)" \
  "[[ -n \"\$EMITTER_TAG\" ]]"
# The positive half of the pair. An emitter whose tag is not allowlisted is silence that READS AS
# HEALTH — the #6536 defect, where a unit's stderr never left the host because its identifier
# matched no source. Derived tag on one side, the real vector.toml on the other.
assert "the emitter's tag ('${EMITTER_TAG:-<none>}') IS in the vector Source 4 allowlist (else the row never leaves the box)" \
  "[[ -n \"\$EMITTER_TAG\" ]] && grep -qE \"^[[:space:]]*\\\"\$EMITTER_TAG\\\",?\$\" '$VECTOR_TOML'"

# --- the harness's own stubs -------------------------------------------------------------------
# `logger` and `curl` are PATH-resolved by the emitter, so stubs record what it emitted and what
# it tried to send. The curl stub is NOT a blanket no-op: it FAILS on a missing required flag, so
# a future emitter that stops sending the Authorization header cannot pass by accident.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/logger" <<'LOGEOF'
#!/bin/sh
printf '%s\n' "$*" >> "$LOGGER_OUT"
LOGEOF
cat > "$WORK/bin/curl" <<'CURLEOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CURL_OUT"
case "$*" in
  *Authorization*) ;;
  *) echo "curl-stub: refusing a POST with no Authorization header" >&2; exit 64 ;;
esac
exit "${CURL_STUB_RC:-0}"
CURLEOF
chmod +x "$WORK/bin/logger" "$WORK/bin/curl"

LOGGER_OUT="$WORK/logger.txt"
CURL_OUT="$WORK/curl.txt"

fire() {
  # $1 = token-file path (may not exist), $2 = CURL_STUB_RC, $3 = stage
  : > "$LOGGER_OUT"
  : > "$CURL_OUT"
  PATH="$WORK/bin:$PATH" LOGGER_OUT="$LOGGER_OUT" CURL_OUT="$CURL_OUT" \
    CURL_STUB_RC="$2" SOLEUR_INNGEST_BS_TOKEN_FILE="$1" \
    bash "$EMITTER" "$3" "detail-value-must-not-ship"
}

# --- ARM 1: token file ABSENT (the tmpfs defect — every boot after the first) ------------------
TOK="$WORK/token"
rm -f "$TOK"
fire "$TOK" 0 "runcmd-entered" && RC1=0 || RC1=$?
assert "ARM1 missing token -> still exits 0 (fail-OPEN: a broken emitter must never brick a boot)" \
  "[[ '$RC1' -eq 0 ]]"
assert "ARM1 missing token -> emits a LOUD logger row (was: a silent \`|| exit 0\`)" \
  "[[ -s '$LOGGER_OUT' ]]"
assert "ARM1 missing token -> the row names the stage, so the trace says WHERE the boot was" \
  "grep -q 'runcmd-entered' '$LOGGER_OUT'"
assert "ARM1 missing token -> the row never carries \$detail (redaction at :125 has not run yet)" \
  "! grep -q 'detail-value-must-not-ship' '$LOGGER_OUT'"
assert "ARM1 missing token -> no POST was attempted (there is no credential to send)" \
  "[[ ! -s '$CURL_OUT' ]]"

# --- ARM 2: token file present but EMPTY --------------------------------------------------------
# Same silent-exit shape one line down, and a REAL state: cloud-init writes the file before it
# knows whether the Doppler fetch produced anything, so `printf '' > file` leaves exactly this.
: > "$TOK"
fire "$TOK" 0 "doppler-token-fetched" && RC2=0 || RC2=$?
assert "ARM2 empty token -> still exits 0 (fail-open)" \
  "[[ '$RC2' -eq 0 ]]"
assert "ARM2 empty token -> emits a LOUD logger row (the second silent \`|| exit 0\`)" \
  "[[ -s '$LOGGER_OUT' ]]"
assert "ARM2 empty token -> the row is DISTINGUISHABLE from the missing-file arm" \
  "grep -qi 'empty' '$LOGGER_OUT'"
assert "ARM2 empty token -> no POST attempted" \
  "[[ ! -s '$CURL_OUT' ]]"

# --- ARM 3: token present, POST FAILS -----------------------------------------------------------
printf '%s' 'synthetic-token-value' > "$TOK"
fire "$TOK" 7 "oci-pull-rc-1" && RC3=0 || RC3=$?
assert "ARM3 failed POST -> still exits 0 (fail-open)" \
  "[[ '$RC3' -eq 0 ]]"
assert "ARM3 failed POST -> a POST WAS attempted (proves the arm is reached, not short-circuited)" \
  "[[ -s '$CURL_OUT' ]]"
assert "ARM3 failed POST -> emits a LOUD logger row (was: \`curl ... >/dev/null 2>&1\`)" \
  "[[ -s '$LOGGER_OUT' ]]"
assert "ARM3 failed POST -> the row carries curl's exit code, so the failure is diagnosable" \
  "grep -q 'rc=7' '$LOGGER_OUT'"
assert "ARM3 failed POST -> the row never carries the bearer token value" \
  "! grep -q 'synthetic-token-value' '$LOGGER_OUT'"
assert "ARM3 failed POST -> the row never carries \$detail" \
  "! grep -q 'detail-value-must-not-ship' '$LOGGER_OUT'"

# --- ARM 4: the happy path stays SILENT ---------------------------------------------------------
# The load-bearing negative. Without it every assertion above is satisfied by an emitter that logs
# unconditionally — which would ship a row for all ~15 call sites on EVERY boot of a HEALTHY host,
# turning a bounded failure channel into a permanent quota cost. Success is already observable via
# the POST itself; a journald row would be pure duplication.
fire "$TOK" 0 "net-health" && RC4=0 || RC4=$?
assert "ARM4 successful POST -> exits 0" \
  "[[ '$RC4' -eq 0 ]]"
assert "ARM4 successful POST -> a POST was attempted" \
  "[[ -s '$CURL_OUT' ]]"
assert "ARM4 successful POST -> emits NO logger row (silent on success; the quota stays bounded)" \
  "[[ ! -s '$LOGGER_OUT' ]]"

# --- the stub's own non-vacuity ------------------------------------------------------------------
# If the curl stub could not distinguish success from failure, ARM3 and ARM4 would be the same
# test run twice. Prove the seam is consumed.
assert "harness: the curl stub's rc seam is CONSUMED (ARM3 rc=7 and ARM4 rc=0 took different arms)" \
  "[[ '$RC3' -eq 0 && '$RC4' -eq 0 ]] && [[ \$(grep -c . '$LOGGER_OUT') -eq 0 ]]"
# And that the stub would catch a dropped Authorization header rather than passing it through.
CURL_AUTH_PROBE=$(PATH="$WORK/bin:$PATH" CURL_OUT="$WORK/probe.txt" sh -c 'curl -X POST https://x/ -d {} >/dev/null 2>&1; echo $?')
assert "harness: the curl stub REFUSES a POST with no Authorization header (exit 64, not a no-op)" \
  "[[ '$CURL_AUTH_PROBE' -eq 64 ]]"

# --- #7228 AC5: the per-boot token re-stage, asserted over the RENDERED userdata ----------------
# WHY RENDERED AND NOT THE SOURCE. cloud-init-inngest.yml is a Terraform templatefile(), so the
# bytes the host actually receives are not the bytes in this repo: `$${...}` collapses, `%{...}`
# directives evaluate, and a var can inject or delete whole regions. A source-grep therefore
# asserts a property of a file NO HOST EVER SEES — which is the plan-review finding that struck
# AC4 of the first draft. The render is the artifact; assert there.
echo ""
echo "--- #7228 AC5: per-boot token re-stage (asserted over the RENDERED userdata) ---"

if ! command -v terraform >/dev/null 2>&1; then
  # Not a silent skip: an absent renderer means this section proved NOTHING, and a run that
  # reports "all passed" while its load-bearing leg never executed is the false-green this
  # whole PR is about. deploy-script-tests (where this suite is registered) runs
  # hashicorp/setup-terraform, so CI always takes the real branch.
  fail "AC5 REQUIRES terraform to render the userdata, and terraform is not on PATH — this section proved nothing"
else
  RENDER_DIR="$WORK/render"
  RENDERED="$WORK/rendered-userdata.yml"
  mkdir -p "$RENDER_DIR"
  # Keys come from the templatefile() call site in inngest-host.tf — the authoritative statement
  # of what this template receives. A missing key is a render error, not a silent empty string,
  # so a future var addition trips this loudly rather than degrading the assertions to vacuity.
  # #6500: the render expression is kept in a variable so the Guard 2 row 4 mutation can re-render
  # a mutated copy of the template through the SAME map.
  # `sentry_dsn` (#6500) is short, alphanumeric and non-hex on purpose: it must pass the emitter's
  # DSN shape check, and the redaction pattern backstop must NOT be able to catch its key, so the
  # Guard 4 cases prove the explicit enumeration rather than the backstop.
  RENDER_EXPR="$(printf 'templatefile("%s", { inngest_volume_id="v", inngest_luks_volume_id="v2", inngest_expect_luks="false", doppler_token="d", sdk_url="https://sdk", inngest_cli_arch="amd64", inngest_cli_sha256="s", vector_sha256="vs", doppler_arch="amd64", doppler_sha256="ds", ghcr_read_user="u", ghcr_read_token="g", web_host_private_ips="10.0.1.10", inngest_private_ip="10.0.1.40", betterstack_logs_token="BS_TOKEN_SENTINEL_7228", zot_registry_endpoint="10.0.1.30:5000", zot_pull_user="zu", zot_pull_token="zt", sentry_dsn="https://pubKEYx7@o1.ingest.invalid/42" })' "$CLOUD_INIT")"
  printf '%s\n' "$RENDER_EXPR" | terraform -chdir="$RENDER_DIR" console > "$RENDERED" 2>"$WORK/render.err"

  # KEY-SET PARITY WITH THE REAL CALL SITE (#7695). The map above is hand-kept, and the comment
  # above it promises a future var addition "trips this loudly". It does — but it trips as
  # `Invalid function argument`, which reads as a broken test rather than as a drifted key set,
  # and the three assertions that follow then fail for a reason that names nothing.
  #
  # Measured: #7695 added `inngest_expect_luks` to the inngest-host.tf call site and this map was
  # not updated, so all three AC5 assertions went red on `main` with a stderr blob about console
  # input. Deriving the expected set from the .tf and DIFFING it names the missing key instead.
  # `[a-z0-9_]+`, NOT `[a-z_]+`. Both sides used the same digit-blind class, so `comm` compared
  # two lists produced by the SAME broken lexer and reported parity over the subset both could
  # see: the call site carries 16 keys and each side saw 13, with `inngest_cli_sha256`,
  # `vector_sha256` and `doppler_sha256` invisible to both. The drift class this arm was written
  # for (an all-lowercase key) was caught; a drift in any `*_sha256` key was not — and those three
  # are the ones that pin the binaries the host installs.
  # END ANCHOR: the map's own closing line, NOT the wrapper's. It used to be `/^  \}\)\)$/`,
  # which matched the `}))` that closed `base64gzip(replace(templatefile(...)))` when the whole
  # expression lived inline on the resource. #7695 hoisted the render into `locals` so a
  # `lifecycle.precondition` could weigh it (a precondition cannot reference `self`), and the
  # closer became `}), local.inngest_rationale_strip, "")`. The old anchor then matched NOTHING,
  # awk ran the range to EOF, and the extraction swallowed every 4-space-indented assignment in
  # the rest of the file — `app`, `ignore_changes`, `ipv4_enabled`, `ipv6_enabled` — reporting
  # them as keys MISSING from this suite's map. The parity assertion caught it, but as a
  # confusing "you forgot four keys" rather than "the extractor over-read", which is why the
  # explicit bound below now exists.
  #
  # Anchored on `^  })` alone: it matches the map closer under BOTH wrapper forms and any future
  # one, because what terminates the map is the 2-space-indented `})` — the wrapper's remaining
  # arguments trail on that same line and are not part of what this range must capture. Map
  # entries are 4-space indented, so no interior line can match it.
  TF_KEYS="$(awk '/templatefile\("\$\{path\.module\}\/cloud-init-inngest\.yml", \{/,/^  \}\)/' \
    "$SCRIPT_DIR/inngest-host.tf" | grep -oE '^    [a-z0-9_]+ +=' | tr -d ' =' | sort -u)"
  MAP_KEYS="$(grep -oE '\{ inngest_volume_id=.*\}' "${BASH_SOURCE[0]}" | head -1 \
    | grep -oE '[a-z0-9_]+=' | tr -d '=' | sort -u)"
  # Non-vacuity: an extraction that found nothing must not report parity. The floor is the ACTUAL
  # key count, not a round number safely below it (17 -> 18: #6500 threads `sentry_dsn`) — a `-ge 10` passed at 13 while three keys were
  # missing from both sides, which is precisely the state it was supposed to make visible.
  assert "AC5 key-set parity: the .tf call site's keys were extracted" \
    "[[ \$(printf '%s\\n' \"$TF_KEYS\" | grep -c .) -ge 18 ]]"
  # ...and an OVER-extraction bound, the direction the floor above is blind to. A range whose end
  # anchor stops matching runs to EOF and harvests unrelated assignments; that is not a missing
  # key and should not be reported as one. 17 is the call site's actual key count, so this is
  # exact in both directions when paired with the floor. (16 -> 17: #6894 added
  # `inngest_luks_volume_id`, the additive volume's id the two-device resolver needs, and this
  # suite's map was not updated in the same commit — so the over-read guard fired on a real key.)
  assert "AC5 key-set parity: the extraction stopped at the map's closing brace (over-read guard)" \
    "[[ \$(printf '%s\\n' \"$TF_KEYS\" | grep -c .) -le 18 ]]"
  MISSING="$(comm -23 <(printf '%s\n' "$TF_KEYS") <(printf '%s\n' "$MAP_KEYS") | tr '\n' ' ')"
  EXTRA="$(comm -13 <(printf '%s\n' "$TF_KEYS") <(printf '%s\n' "$MAP_KEYS") | tr '\n' ' ')"
  assert "AC5 key-set parity: this suite's render map matches inngest-host.tf (missing:${MISSING:-none} extra:${EXTRA:-none})" \
    "[[ -z '${MISSING}' && -z '${EXTRA}' ]]"

  # A truncated or empty render makes every assertion below pass or fail for the wrong reason.
  assert "AC5 the userdata rendered at all (terraform console produced output)" \
    "[[ -s '$RENDERED' ]]"
  if [[ ! -s "$RENDERED" ]]; then
    echo "    render stderr: $(head -c 400 "$WORK/render.err")"
  fi

  assert "AC5 RENDERED userdata delivers the re-stage script" \
    "grep -qF '/usr/local/bin/inngest-bs-token-restage.sh' '$RENDERED'"
  assert "AC5 RENDERED userdata delivers the re-stage UNIT (so it runs on boot, not just on cloud-init)" \
    "grep -qF '/etc/systemd/system/inngest-bs-token-restage.service' '$RENDERED'"
  # A delivered-but-unenabled unit is the defect verbatim: present on disk, never started, and
  # the channel still dies on the next reboot.
  assert "AC5 RENDERED userdata ENABLES the unit (delivery alone leaves the channel dead on reboot)" \
    "grep -qE 'systemctl enable inngest-bs-token-restage\.service' '$RENDERED'"
  assert "AC5 the unit is WantedBy=multi-user.target (it must fire on EVERY boot)" \
    "grep -qE '^[[:space:]]*WantedBy=multi-user\.target' '$RENDERED'"
  assert "AC5 the unit sets SyslogIdentifier (else its rows retag to the ExecStart basename and ship nowhere)" \
    "grep -qE '^[[:space:]]*SyslogIdentifier=inngest-bs-token-restage' '$RENDERED'"
  assert "AC5 the re-stage tag IS in the vector Source 4 allowlist" \
    "grep -qE '^[[:space:]]*\"inngest-bs-token-restage\",?\$' '$VECTOR_TOML'"

  # THE LOAD-BEARING ONE. "Re-fetch from Doppler, never a baked re-stamp." A unit that re-writes
  # the templatefile's own betterstack_logs_token would satisfy every assertion above while
  # making the token durable on the ROOT DISK (defeating the tmpfs staging) and pinning it at
  # image-build time so a rotation could never reach the host. The sentinel proves it: the
  # rendered SCRIPT BODY must not contain the interpolated token value.
  RESTAGE_BODY="$(awk '/^  - path: \/usr\/local\/bin\/inngest-bs-token-restage\.sh$/{f=1;next} f&&/^  - path: /{f=0} f' "$RENDERED")"
  assert "AC5 the re-stage script body was located in the render (else the two checks below are vacuous)" \
    "[[ -n \"\$RESTAGE_BODY\" ]]"
  assert "AC5 the re-stage RE-FETCHES from Doppler (never a baked re-stamp)" \
    "grep -qF 'doppler secrets get BETTERSTACK_LOGS_TOKEN' <<<\"\$RESTAGE_BODY\""
  assert "AC5 the rendered re-stage script does NOT bake the token value (it would outlive tmpfs and defeat rotation)" \
    "! grep -qF 'BS_TOKEN_SENTINEL_7228' <<<\"\$RESTAGE_BODY\""
  # Non-vacuity for the sentinel: prove the render DID substitute it somewhere, so the negative
  # above is a real absence rather than a var that never landed.
  assert "AC5 non-vacuity: the sentinel IS present elsewhere in the render (the negative above is meaningful)" \
    "grep -qF 'BS_TOKEN_SENTINEL_7228' '$RENDERED'"

  # The re-stage must fail LOUD. A silent failure re-creates the original defect one layer up:
  # the channel is dead and nothing says so.
  assert "AC5 the re-stage emits a loud row when the Doppler fetch yields nothing" \
    "grep -qF 'SOLEUR_INNGEST_BS_TOKEN_RESTAGE_FAILED' <<<\"\$RESTAGE_BODY\""
  assert "AC5 the re-stage emits a positive control on success (else 'no rows' is ambiguous — ADR-117)" \
    "grep -qF 'SOLEUR_INNGEST_BS_TOKEN_RESTAGED' <<<\"\$RESTAGE_BODY\""

  # === #6500: the dedicated host reports its pull outcome on the Sentry `stage:` schema ============
  # Guards 2, 3 and 4 of the #6500 plan (Guard Contract). Everything below runs against the RENDERED
  # userdata above, never the raw template: `$${...}` collapses and `%{...}` evaluates at render, so
  # a raw body is a script no host receives. Each case is a FUNCTION that returns 0 when its property
  # holds, so the same function scores the real body (must PASS) and every mutant (must go RED).
  echo ""
  echo "--- #6500: soleur-boot-emit + inngest-redact.sh DSN enumeration (asserted over the RENDER) ---"

  # Instrument self-test (review P2-2): `assert` must be able to say NO. A neutered assert that
  # always passes would score every case and every mutant below as green. Driven once each way,
  # counters unwound, and reported via printf + exit so the check cannot route through `assert`.
  _st_p=$PASS; _st_f=$FAIL
  assert "self-test: known-true" "true" >/dev/null
  assert "self-test: known-false" "false" >/dev/null
  if [[ $((PASS - _st_p)) -ne 1 || $((FAIL - _st_f)) -ne 1 ]]; then
    printf 'FATAL: the assert helper cannot distinguish true from false (pass +%s, fail +%s)\n' \
      "$((PASS - _st_p))" "$((FAIL - _st_f))"
    exit 1
  fi
  PASS=$_st_p; FAIL=$_st_f

  # write_files body of <path>, from a rendered (or raw) cloud-config: the path line to the next
  # `  - path:`, minus the YAML keys, dedented out of the 6-space block scalar.
  extract_wf() {
    awk -v p="  - path: $1" '$0==p{f=1;next} f&&/^  - path: /{f=0} f' "$2" \
      | sed -e '/^    content: |$/d' -e '/^    owner:/d' -e '/^    permissions:/d' -e 's/^      //'
  }

  EMIT="$WORK/soleur-boot-emit"
  REDACT="$WORK/inngest-redact.sh"
  extract_wf /usr/local/bin/soleur-boot-emit "$RENDERED" > "$EMIT"
  extract_wf /usr/local/bin/inngest-redact.sh "$RENDERED" > "$REDACT"
  # The DSN file exactly as the host receives it (review P3-5): the readers are exercised against
  # the rendered bytes, not a hand-copied format.
  RENDERED_DSN="$WORK/rendered-dsn.env"
  extract_wf /etc/default/soleur-sentry-dsn "$RENDERED" | grep -v '^ *#' | grep -v '^ *$' > "$RENDERED_DSN"
  assert "G3 extraction: the rendered soleur-boot-emit body is non-empty, has a shebang and a curl" \
    "[[ -s '$EMIT' ]] && head -1 '$EMIT' | grep -q '^#!/bin/sh' && grep -q 'curl ' '$EMIT'"
  assert "G3 extraction: the rendered soleur-boot-emit is valid sh" "sh -n '$EMIT'"
  assert "G4 extraction: the rendered inngest-redact.sh body is non-empty and valid bash" \
    "[[ -s '$REDACT' ]] && bash -n '$REDACT'"
  assert "extraction: the rendered DSN file is exactly one SOLEUR_SENTRY_DSN line carrying the render value" \
    "[[ \$(grep -c . '$RENDERED_DSN') -eq 1 ]] && grep -qxF \"SOLEUR_SENTRY_DSN='https://pubKEYx7@o1.ingest.invalid/42'\" '$RENDERED_DSN'"

  # --- stubs ---------------------------------------------------------------------------------------
  # curl records argv (one per line), stdin (where `-K -` carries the auth header) and the `-d` body.
  # It models `-f` (review P1-3): with EC_HTTP >= 400 it exits 22 only when -f/--fail/-sf is in argv,
  # and 0 otherwise — which is what real curl does, so dropping -f is observable. EC_CURL_RC models
  # a transport failure (6/7/28) and wins over EC_HTTP. The phone-home stub records its argv and
  # EXITS 3: a removed `|| true` wrapper then surfaces as a non-zero emitter exit.
  EB="$WORK/emitbin"; mkdir -p "$EB"
  cat > "$EB/curl" <<'ECURL'
#!/bin/sh
echo call >> "$EC_CALLS"
printf '%s\n' "$@" > "$EC_ARGV"
cat > "$EC_STDIN"
prev=""; fail=0
for a in "$@"; do
  [ "$prev" = "-d" ] && printf '%s' "$a" > "$EC_BODY"
  case "$a" in -f|--fail|-sf|-fs) fail=1 ;; esac
  prev="$a"
done
rc="${EC_CURL_RC:-0}"
[ "$rc" -ne 0 ] && exit "$rc"
if [ "${EC_HTTP:-200}" -ge 400 ] && [ "$fail" -eq 1 ]; then exit 22; fi
exit 0
ECURL
  cat > "$EB/phone-home" <<'EPH'
#!/bin/sh
printf '%s\n' "$*" >> "$EC_PH"
exit 3
EPH
  chmod +x "$EB/curl" "$EB/phone-home"

  DSN_OK="https://pubKEYx7@o1.ingest.invalid/42"
  EC_DIR="$WORK/ec"
  # run_emit <emitter> <dsn-file> <curl-rc> <stage> <level> <detail> [http-status]; leaves the
  # recordings in EC_DIR and the emitter's exit code in EC_RC. Every recording is truncated first so
  # a case can never read a previous case's result.
  run_emit() {
    rm -rf "$EC_DIR"; mkdir -p "$EC_DIR"
    : > "$EC_DIR/calls"; : > "$EC_DIR/ph"
    PATH="$EB:$PATH" EC_CALLS="$EC_DIR/calls" EC_ARGV="$EC_DIR/argv" EC_STDIN="$EC_DIR/stdin" \
      EC_BODY="$EC_DIR/body" EC_PH="$EC_DIR/ph" EC_CURL_RC="$3" EC_HTTP="${7:-200}" \
      SOLEUR_INNGEST_SENTRY_DSN_FILE="$2" SOLEUR_INNGEST_PHONE_HOME="$EB/phone-home" \
      sh "$1" "$4" "$5" "$6" < /dev/null > "$EC_DIR/out" 2> "$EC_DIR/err"
    EC_RC=$?
  }
  dsn_file() { printf "SOLEUR_SENTRY_DSN='%s'\n" "$1" > "$WORK/dsn.env"; echo "$WORK/dsn.env"; }
  ncalls() { grep -c . "$EC_DIR/calls" 2>/dev/null || true; }
  # value of the argv element following flag $1 (the curl stub writes one argv element per line)
  argv_after() { awk -v f="$1" 'p{print; exit} $0==f{p=1}' "$EC_DIR/argv"; }

  # G2 + G3 happy path: one POST, the web emitter's event shape, the key only on stdin, bounded.
  # Fed the RENDERED DSN file, so the writer's format and the reader's regex are pinned together.
  case_happy() {
    run_emit "$1" "$RENDERED_DSN" 0 inngest_zot info "ep=10.0.1.30:5000"
    [[ "$EC_RC" -eq 0 ]] || return 1
    [[ "$(ncalls)" -eq 1 ]] || return 1
    [[ -s "$EC_DIR/body" ]] || return 1
    grep -qxF 'https://o1.ingest.invalid/api/42/store/' "$EC_DIR/argv" || return 1
    ! grep -qF 'pubKEYx7' "$EC_DIR/argv" || return 1
    grep -qF 'sentry_key=pubKEYx7' "$EC_DIR/stdin" || return 1
    # argv snapshot (review P2-6/P3-1/P3-2): -q first (no ~/.curlrc), `-K -` reads the header from
    # stdin, the ONLY -H is the content type, -f is present, NO --retry of any kind, and the two
    # time bounds are present AND no larger than stated.
    [[ "$(head -1 "$EC_DIR/argv")" == "-q" ]] || return 1
    [[ "$(argv_after -K)" == "-" ]] || return 1
    [[ "$(grep -cxF -- '-H' "$EC_DIR/argv")" -eq 1 && "$(argv_after -H)" == "Content-Type: application/json" ]] || return 1
    grep -qxE -- '-sf|-f|--fail' "$EC_DIR/argv" || return 1
    ! grep -qE -- '^--retry' "$EC_DIR/argv" || return 1
    local ct mt
    ct="$(argv_after --connect-timeout)"; mt="$(argv_after --max-time)"
    [[ "$ct" =~ ^[0-9]+$ && "$ct" -le 5 && "$mt" =~ ^[0-9]+$ && "$mt" -le 8 ]] || return 1
    [[ ! -s "$EC_DIR/out" ]] || return 1
    ! grep -qF 'pubKEYx7' "$EC_DIR/err" || return 1
    [[ ! -s "$EC_DIR/ph" ]] || return 1
    local keys
    keys="$(jq -r '.tags | keys | join(",")' "$EC_DIR/body" 2>/dev/null)"
    [[ "$keys" == "detail,host_id,host_name,region,stage" ]] || return 1
    jq -e '.message == "soleur-cloud-init boot stage" and .level == "info"
      and .tags.stage == "inngest_zot" and .tags.region == "cloud-init"
      and .tags.host_name == "soleur-inngest" and .tags.detail == "ep=10.0.1.30:5000"' \
      "$EC_DIR/body" >/dev/null 2>&1 || return 1
  }
  # G2 row 6: the level and detail arguments are carried, not hardcoded — and the STAGE too: a
  # SUT that hardcodes the stage would report every fallback as inngest_zot.
  case_warning() {
    run_emit "$1" "$(dsn_file "$DSN_OK")" 0 inngest_ghcr_fallback warning "rc=7"
    [[ "$EC_RC" -eq 0 && "$(ncalls)" -eq 1 ]] || return 1
    jq -e '.level == "warning" and .tags.stage == "inngest_ghcr_fallback" and .tags.detail == "rc=7"' \
      "$EC_DIR/body" >/dev/null 2>&1
  }
  # Review P2-5 + security F4: every argument is interpolated into the body, so every one is
  # reduced to a JSON-safe charset — a hostile stage/level/detail still yields valid JSON with
  # clean values, a level outside the enum falls back to info, and detail is bounded.
  case_sanitize() {
    local long; long="$(printf 'x%.0s' $(seq 1 200))"
    run_emit "$1" "$(dsn_file "$DSN_OK")" 0 'inn"gest_zot\x' 'bogus"level' "a\"b\\c,\"x\":\"y${long}"
    [[ "$EC_RC" -eq 0 && "$(ncalls)" -eq 1 ]] || return 1
    jq -e '.tags.stage == "inngest_zotx" and .level == "info"
      and (.tags.detail | test("^[A-Za-z0-9=.:_-]*$")) and (.tags.detail | length) <= 120
      and (.tags | keys | length) == 5' "$EC_DIR/body" >/dev/null 2>&1
  }
  # G3 row 10 / 6: DSN file absent or empty -> exit 0, no curl, exactly one rc=nodsn phone-home.
  case_nodsn() {
    run_emit "$1" "$WORK/absent-dsn.env" 0 inngest_zot info "ep=x"
    [[ "$EC_RC" -eq 0 && "$(ncalls)" -eq 0 && ! -s "$EC_DIR/out" ]] || return 1
    [[ "$(cat "$EC_DIR/ph")" == "sentry-emit-FAILED stage=inngest_zot rc=nodsn" ]] || return 1
    run_emit "$1" "$(dsn_file "")" 0 inngest_zot info "ep=x"
    [[ "$EC_RC" -eq 0 && "$(ncalls)" -eq 0 ]] || return 1
    [[ "$(cat "$EC_DIR/ph")" == "sentry-emit-FAILED stage=inngest_zot rc=nodsn" ]]
  }
  # G3 row 7: a malformed DSN (a quote that would inject into `curl -K -`, or no `@`) never reaches curl.
  case_baddsn() {
    local d
    for d in 'https://a"b@h/1' 'https://nokeyhost/1' 'https://k\\x@h/1'; do
      run_emit "$1" "$(dsn_file "$d")" 0 inngest_zot info "ep=x"
      [[ "$EC_RC" -eq 0 && "$(ncalls)" -eq 0 ]] || return 1
      [[ "$(head -1 "$EC_DIR/ph")" == "sentry-emit-FAILED stage=inngest_zot rc=baddsn" ]] || return 1
    done
  }
  # G3 row 8 / G4 row 4: the DSN file is READ, never executed. Positive control (review P2-1): the
  # emitter must have got PAST its read — the fixture's value fails the shape check, so exactly one
  # rc=baddsn phone-home proves the read ran and the sentinel is absent because nothing executed it.
  case_inject_emit() {
    rm -f "$WORK/SENTINEL_EMIT"
    printf "SOLEUR_SENTRY_DSN='x'; touch %s; X='y'\n" "$WORK/SENTINEL_EMIT" > "$WORK/evil.env"
    run_emit "$1" "$WORK/evil.env" 0 inngest_zot info "ep=x"
    [[ "$EC_RC" -eq 0 && ! -e "$WORK/SENTINEL_EMIT" ]] || return 1
    [[ "$(cat "$EC_DIR/ph")" == "sentry-emit-FAILED stage=inngest_zot rc=baddsn" ]]
  }
  # G3 rows 1 + 5: curl fails -> exit 0 anyway, and the failure reaches the phone-home seam, numeric.
  case_curlfail() {
    run_emit "$1" "$(dsn_file "$DSN_OK")" 7 inngest_ghcr_fallback warning "rc=1"
    [[ "$EC_RC" -eq 0 && "$(ncalls)" -eq 1 ]] || return 1
    [[ "$(cat "$EC_DIR/ph")" == "sentry-emit-FAILED stage=inngest_ghcr_fallback rc=7" ]]
  }
  # Review P1-3: an HTTP-level rejection (quota 429, revoked key 403) is a non-delivery too, and
  # only -f turns it into a non-zero rc the emitter can report.
  case_http_reject() {
    run_emit "$1" "$(dsn_file "$DSN_OK")" 0 inngest_zot info "ep=x" 403
    [[ "$EC_RC" -eq 0 && "$(ncalls)" -eq 1 ]] || return 1
    [[ "$(cat "$EC_DIR/ph")" == "sentry-emit-FAILED stage=inngest_zot rc=22" ]]
  }
  # G1 row 10 (emitter half): the host_name the event carries is the literal the soak filters on.
  case_hostname_literal() { grep -qxF "  HOST_NAME='soleur-inngest'" "$1"; }
  # Review (pattern P2-1): the emitter's DEFAULT DSN path is the path write_files writes. Every
  # other case swaps it out through the test seam, so without this a drift would be invisible
  # until a host replace phoned home rc=nodsn.
  case_emit_path() {
    grep -qF '  f=/etc/default/soleur-sentry-dsn;' "$1" \
      && grep -qxF '  - path: /etc/default/soleur-sentry-dsn' "$CLOUD_INIT"
  }

  S6500_CASES=(case_happy case_warning case_sanitize case_nodsn case_baddsn case_inject_emit
    case_curlfail case_http_reject case_hostname_literal case_emit_path)
  for c in "${S6500_CASES[@]}"; do
    assert "G2/G3 must-PASS: $c holds for the rendered emitter" "$c '$EMIT'"
  done

  # G2 row 4: the BODY line survives templatefile byte-for-byte (no `%{`/`$${` for the renderer to eat).
  RAW_EMIT="$WORK/raw-soleur-boot-emit"
  extract_wf /usr/local/bin/soleur-boot-emit "$CLOUD_INIT" > "$RAW_EMIT"
  case_body_parity() { # $1 raw body, $2 rendered body
    local r n
    r="$(grep -E '^  BODY=' "$1")"; n="$(grep -E '^  BODY=' "$2")"
    [[ -n "$r" && "$r" == "$n" ]]
  }
  assert "G2 must-PASS: the rendered BODY line equals the raw one (the renderer changed nothing)" \
    "case_body_parity '$RAW_EMIT' '$EMIT'"
  # Cross-file parity (review, 3 seats): the soak's bare [freshboot] query and the
  # zot_mirror_fallback_rate alert read events from BOTH hosts' emitters, so the event format is
  # one contract with two implementations. Pinned byte-for-byte after leading whitespace.
  # shellcheck disable=SC2034 # WEB_BODY/INN_BODY are read inside the eval string of the assert below
  WEB_BODY="$(grep -E '^[[:space:]]*BODY=\$\(printf ' "$SCRIPT_DIR/soleur-host-bootstrap.sh" | sed -E 's/^[[:space:]]+//')"
  # shellcheck disable=SC2034
  INN_BODY="$(grep -E '^[[:space:]]*BODY=\$\(printf ' "$RAW_EMIT" | sed -E 's/^[[:space:]]+//')"
  assert "G2 parity: the inngest BODY line is byte-identical to the web host's soleur-boot-emit" \
    "[[ -n \"\$WEB_BODY\" && \"\$WEB_BODY\" == \"\$INN_BODY\" ]]"
  # The literal host_name is the Terraform server name, which the web emitter gets from TF.
  TF_NAME="$(awk '/^resource "hcloud_server" "inngest"/{f=1} f&&/^  name /{print; exit}' "$SCRIPT_DIR/inngest-host.tf" | sed -E 's/.*"([^"]+)".*/\1/')"
  assert "G1 parity: the emitter's HOST_NAME equals hcloud_server.inngest's name ('${TF_NAME:-<none>}')" \
    "[[ -n \"\$TF_NAME\" ]] && grep -qxF \"  HOST_NAME='\$TF_NAME'\" '$EMIT'"

  # --- the in-suite mutation battery (landed-diff contract) ----------------------------------------
  # mutant_red <label> <sed-script> <case> [<file>]: copy the body, apply the sed, REQUIRE the
  # mutation landed (a non-empty diff — otherwise the row would score the unmutated body and report
  # the baseline as a verdict), then require the case to go RED on the mutant.
  S6500_ROWS=0
  mutant_red() {
    local label="$1" script="$2" fn="$3" src="${4:-$EMIT}" m="$WORK/mutant.$RANDOM"
    S6500_ROWS=$((S6500_ROWS + 1))
    sed -e "$script" "$src" > "$m"
    if cmp -s "$src" "$m"; then
      fail "$label — HARNESS ABORT: the mutation did not land (sed matched nothing)"
      return
    fi
    if "$fn" "$m"; then fail "$label — mutant SURVIVED"; else pass "$label — mutant killed"; fi
  }
  # Harness row: prove the landed-diff check itself fires (G1 row 13 shape, applied here too).
  # shellcheck disable=SC2034 # read inside the eval string of the assert below
  HARNESS_PROBE="$(mutant_red "probe" 's/THIS-STRING-IS-NOT-IN-THE-BODY/x/' case_happy 2>&1; true)"
  assert "harness: a mutation that matches nothing is reported as HARNESS ABORT, never as a verdict" \
    "grep -qF 'HARNESS ABORT' <<<\"\$HARNESS_PROBE\""

  mutant_red "G3 row 1: drop the || true wrapper + final exit 0 (curl 7, phone-home exits 3)" \
    's/^) || true$/)/; /^exit 0$/d' case_curlfail
  mutant_red "G3 row 2: the auth header on argv instead of -K -" \
    "s#printf 'header = [^|]*| curl -q -K - #curl -q -H \"X-Sentry-Auth: Sentry sentry_version=7, sentry_key=\$KEY\" #" case_happy
  mutant_red "G3 row 3: echo the DSN to stderr" '/^  DSN=/a\
  echo "$DSN" >\&2' case_happy
  mutant_red "G3 row 4a: drop --connect-timeout" 's/--connect-timeout 5 //' case_happy
  mutant_red "G3 row 4b: drop --max-time" 's/--max-time 8 //' case_happy
  mutant_red "G3 row 4c: raise --max-time past the bound" 's/--max-time 8 /--max-time 600 /' case_happy
  mutant_red "G3 row 4d: re-add a --retry (a declined retry reads as success)" 's/--max-time 8 /--max-time 8 --retry 1 /' case_happy
  mutant_red "G3 row 4e: drop -q (honour ~/.curlrc)" 's/curl -q -K/curl -K/' case_happy
  mutant_red "G3 row 4f: a second -H that blanks the auth header" "s#-H 'Content-Type: application/json'#-H 'Content-Type: application/json' -H 'X-Sentry-Auth:'#" case_happy
  mutant_red "G3 row 4g: drop -f (an HTTP rejection exits 0)" 's/ -sf / -s /' case_http_reject
  mutant_red "G3 row 5: drop the phone-home on a curl failure" '/rc=\$crc/d' case_curlfail
  mutant_red "G3 row 6: drop the rc=nodsn phone-home" 's/"\$ph" sentry-emit-FAILED "stage=\$STAGE rc=nodsn"/:/' case_nodsn
  mutant_red "G3 row 7: drop the DSN shape check" '/rc=baddsn/d' case_baddsn
  mutant_red "G3 row 8: source the DSN file instead of reading it" \
    's/^  DSN=.*/  . "$f"; DSN="$SOLEUR_SENTRY_DSN"/' case_inject_emit
  mutant_red "G3 row 9: the emitter body is empty (dispatch)" '2,$d' case_happy
  mutant_red "G3 row 9b: the emitter is a no-op (injection case must still see the read)" '2,$d' case_inject_emit
  mutant_red "G3 row 11: the default DSN path drifts" 's#  f=/etc/default/soleur-sentry-dsn;#  f=/etc/default/sentry-dsn;#' case_emit_path
  mutant_red "G3 row 12: DETAIL unsanitised" 's/^  DETAIL=.*/  DETAIL="$3"/' case_sanitize
  mutant_red "G3 row 13: STAGE unsanitised" 's/^  STAGE=.*/  STAGE="$1"/' case_sanitize
  mutant_red "G3 row 14: LEVEL passed through" 's/^  case "\$2" in .*/  LEVEL="$2"/' case_sanitize
  mutant_red "G3 row 15: the stage is hardcoded" 's/"\$LEVEL" "\$STAGE" "\$HOST_ID"/"$LEVEL" inngest_zot "$HOST_ID"/' case_warning
  mutant_red "G2 row 1: change region" 's/"region":"cloud-init"/"region":"host"/' case_happy
  mutant_red "G2 row 2: drop the host_name tag" 's/,"host_name":"%s"//' case_happy
  mutant_red "G2 row 3: add an extra tag key" 's/"detail":"%s"}}/"detail":"%s","shipper":"x"}}/' case_happy
  mutant_red "G1 row 10 (emitter half): HOST_NAME literal drifts" \
    "s/HOST_NAME='soleur-inngest'/HOST_NAME='soleur-inngest-1'/" case_hostname_literal
  # G2 row 4 needs a RE-RENDER of a mutated template: put a `$${...}` into the BODY line so the
  # rendered bytes differ from the raw ones.
  MUT_TPL="$WORK/mut-tpl.yml"
  S6500_ROWS=$((S6500_ROWS + 1))
  sed -e '/^ *BODY=/s/"level":"%s"/"level":"$${LEVEL}"/' "$CLOUD_INIT" > "$MUT_TPL"
  if cmp -s "$CLOUD_INIT" "$MUT_TPL"; then
    fail "G2 row 4 — HARNESS ABORT: the template mutation did not land"
  else
    sed -e "s#\"$CLOUD_INIT\"#\"$MUT_TPL\"#" <<<"$RENDER_EXPR" | terraform -chdir="$RENDER_DIR" console \
      > "$WORK/mut-rendered.yml" 2>/dev/null
    extract_wf /usr/local/bin/soleur-boot-emit "$WORK/mut-rendered.yml" > "$WORK/mut-emit"
    extract_wf /usr/local/bin/soleur-boot-emit "$MUT_TPL" > "$WORK/mut-raw-emit"
    if [[ ! -s "$WORK/mut-emit" ]]; then
      fail "G2 row 4 — HARNESS ABORT: the mutated template did not render"
    elif case_body_parity "$WORK/mut-raw-emit" "$WORK/mut-emit"; then
      fail "G2 row 4: a templatefile escape in the BODY line — mutant SURVIVED"
    else
      pass "G2 row 4: a templatefile escape in the BODY line — mutant killed"
    fi
  fi

  # --- Guard 4: inngest-redact.sh enumerates the DSN and its key by VALUE ---------------------------
  # env -i: the redactor also reads DOPPLER_TOKEN / GHCR_READ_TOKEN from sourced files and would
  # enumerate an operator's live values from their shell; the case must see only the fixture.
  run_redact() { # $1 redactor, $2 dsn file, stdin = tail
    env -i PATH="$PATH" HOME="$WORK" SOLEUR_INNGEST_SENTRY_DSN_FILE="$2" bash "$1"
  }
  case_redact() {
    local out
    out="$(printf 'curl: (22) %s rejected\n' "$DSN_OK" | run_redact "$1" "$RENDERED_DSN")"
    [[ -n "$out" ]] || return 1
    ! grep -qF 'pubKEYx7' <<<"$out" || return 1
    ! grep -qF 'o1.ingest.invalid/42' <<<"$out" || return 1
    out="$(printf 'header sentry_key=pubKEYx7 only\n' | run_redact "$1" "$RENDERED_DSN")"
    [[ -n "$out" ]] && ! grep -qF 'pubKEYx7' <<<"$out" || return 1
    # G4 row 6: a tail with no secret passes through byte-identical.
    out="$(printf 'zot pull rc=1 manifest unknown' | run_redact "$1" "$RENDERED_DSN")"
    [[ "$out" == "zot pull rc=1 manifest unknown" ]]
  }
  # Positive control (review P2-1): the output must be the input, which proves the redactor ran to
  # its printf rather than dying before it.
  case_inject_redact() {
    local out
    rm -f "$WORK/SENTINEL_REDACT"
    printf "SOLEUR_SENTRY_DSN='x'; touch %s; X='y'\n" "$WORK/SENTINEL_REDACT" > "$WORK/evil-r.env"
    out="$(printf 'x' | run_redact "$1" "$WORK/evil-r.env")"
    [[ ! -e "$WORK/SENTINEL_REDACT" && "$out" == "x" ]]
  }
  # G4 row 3: the redactor's default path IS the path write_files writes (the seam masks a drift).
  case_redact_path() {
    grep -qF 'sf=/etc/default/soleur-sentry-dsn;' "$1" \
      && grep -qxF '  - path: /etc/default/soleur-sentry-dsn' "$CLOUD_INIT"
  }
  S6500_REDACT_CASES=(case_redact case_inject_redact case_redact_path)
  for c in "${S6500_REDACT_CASES[@]}"; do
    assert "G4 must-PASS: $c holds for the rendered redactor" "$c '$REDACT'"
  done
  mutant_red "G4 row 1: drop the DSN enumeration" '/soleur-sentry-dsn/d' case_redact "$REDACT"
  mutant_red "G4 row 2: enumerate the DSN but not its key" '/printf %s "\$sdsn"/d' case_redact "$REDACT"
  mutant_red "G4 row 3: point the read at a path write_files never writes" \
    's#sf=/etc/default/soleur-sentry-dsn;#sf=/run/soleur-sentry-dsn;#' case_redact_path "$REDACT"
  mutant_red "G4 row 4: source the DSN file instead of reading it" \
    's/sdsn="\$(sed [^;]*;/. "$sf"; sdsn="$SOLEUR_SENTRY_DSN";/' case_inject_redact "$REDACT"
  mutant_red "G4 row 5: the redactor body is empty (dispatch)" '2,$d' case_redact "$REDACT"
  mutant_red "G4 row 5b: the redactor is a no-op (injection case must still see its output)" '2,$d' case_inject_redact "$REDACT"

  # Section floors (review P2-2): a case dropped from a loop, or a mutant row deleted, must red.
  # Literals adjacent to their `if` so guard-vacuity-floor.test.sh can slice them.
  S6500_NCASES=$(( ${#S6500_CASES[@]} + ${#S6500_REDACT_CASES[@]} ))
  if [[ "$S6500_NCASES" -ne 13 ]]; then
    printf '[FATAL] anti-vacuity floor: #6500 section ran %s must-PASS cases, expected 13 — a case was dropped from a loop\n' "$S6500_NCASES" >&2
    exit 1
  fi
  # Mutation rows: counted by mutant_red itself, so a deleted row lowers it.
  S6500_EXPECTED_ROWS=32
  if [[ "$S6500_ROWS" -lt $S6500_EXPECTED_ROWS ]]; then
    printf '[FATAL] anti-vacuity floor: only %s #6500 mutation rows ran, expected %s — a row was deleted\n' "$S6500_ROWS" "$S6500_EXPECTED_ROWS" >&2
    exit 1
  fi
  # Whole-suite verdict floor: the 40 pre-#6500 assertions plus this section's 53.
  SUITE_VERDICTS=$((PASS + FAIL))
  SUITE_EXPECTED_VERDICTS=93
  if [[ "$SUITE_VERDICTS" -lt $SUITE_EXPECTED_VERDICTS ]]; then
    printf '[FATAL] anti-vacuity floor: only %s assertions ran, expected %s\n' "$SUITE_VERDICTS" "$SUITE_EXPECTED_VERDICTS" >&2
    exit 1
  fi
fi

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "OK inngest-boot-emitter: all assertions passed ($PASS)"
  exit 0
fi
echo "=== Results: $PASS passed, $FAIL failed ==="
exit 1
