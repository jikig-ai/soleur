#!/usr/bin/env bash
set -uo pipefail

# Boot-stage error-channel guard (#6969 / ADR-147).
#
# CONTEXT: soleur-web-2 booted DARK at cloud-init stage=doppler_download. The Sentry fatal
# carried ONLY `stage=doppler_download` + host_id — the Doppler CLI's own stderr and exit code,
# the deciding datum, were discarded at the source behind a generic `echo "FATAL: ..." >&2`.
# The host's journald never reached Better Stack either (Vector's token comes from the very
# fetch that failed), so no hypothesis could be discriminated after the fact.
#
# This guard proves the NEXT occurrence names its own cause. Two halves:
#   (A) STRUCTURAL drift-guards over the authored emitter + helper and their cloud-init wiring.
#   (B) BEHAVIORAL: extract the baked heredoc bodies and RUN them under stubbed commands + path
#       seams, driving helper -> trap -> the REAL soleur-boot-emit, asserting on the emitted
#       body. A static grep alone is evadable: `if ! soleur-doppler-download` reintroduces the
#       $?-is-zero defect and still satisfies a grep for the call.
#
# Mechanical rules (learned the hard way, see the plan's R27/R28/R32):
#   - NEVER `grep -c ... = 0`: grep -c exits 1 on zero matches and aborts a pipefail runner.
#   - Absence-checks anchor on NON-COMMENT lines: this file's own subject matter guarantees the
#     production code carries comments containing `head -c` and the filtered stage names.
#   - Read FILES directly, never `producer | grep -q` (SIGPIPE early-match fail-open).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT="$DIR/soleur-host-bootstrap.sh"
CI="$DIR/cloud-init.yml"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

# ─────────────────────────── extract the two heredoc bodies ───────────────────────────

EMIT="$(awk "/cat > \/usr\/local\/bin\/soleur-boot-emit <<'EMITEOF'/{f=1;next} f&&/^EMITEOF\$/{f=0} f{print}" "$BOOT")"
if [ -n "$EMIT" ]; then
  ok "X1: extracted the soleur-boot-emit heredoc body"
else
  no "X1: could not extract the soleur-boot-emit heredoc body (delimiter EMITEOF?)"
fi

HELPER="$(awk "/cat > \/usr\/local\/bin\/soleur-doppler-download <<'DDLEOF'/{f=1;next} f&&/^DDLEOF\$/{f=0} f{print}" "$BOOT")"
if [ -n "$HELPER" ]; then
  ok "X2: extracted the soleur-doppler-download heredoc body"
else
  no "X2: could not extract the soleur-doppler-download heredoc body (delimiter DDLEOF?)"
fi

# ─────────────────────────────── (A) STRUCTURAL ───────────────────────────────

# AC-F: the helper is authored as a HEREDOC (not the install -D seed loop — a seed file would
# force edits to local.host_script_files, the image bake and the coherence preflight), is
# chmod 0755, and carries a FAILED_FILE + `test -x` assertion. A truncated heredoc otherwise
# still writes /run/soleur-hostscripts.ok and the terminal block dies `command not found` (127).
if grep -qF "cat > /usr/local/bin/soleur-doppler-download <<'DDLEOF'" "$BOOT"; then
  ok "AC-F1: soleur-doppler-download is heredoc-authored (baked, 0 user_data)"
else
  no "AC-F1: expected a 'cat > /usr/local/bin/soleur-doppler-download <<'DDLEOF'' heredoc"
fi
if grep -qF 'chmod 0755 /usr/local/bin/soleur-doppler-download' "$BOOT"; then
  ok "AC-F2: soleur-doppler-download is chmod 0755"
else
  no "AC-F2: missing 'chmod 0755 /usr/local/bin/soleur-doppler-download'"
fi
for h in soleur-boot-emit soleur-doppler-download; do
  if grep -qE "FAILED_FILE=$h" "$BOOT" && grep -qF "test -x /usr/local/bin/$h" "$BOOT"; then
    ok "AC-F3: $h has a FAILED_FILE + 'test -x' assertion (R25)"
  else
    no "AC-F3: $h needs both 'FAILED_FILE=$h' and 'test -x /usr/local/bin/$h'"
  fi
  # AC-F3b: ORDER, not just co-presence. The file runs under a top-level `set -e`, so an
  # existence assertion placed ABOVE the heredoc that authors the file asserts a file that does
  # not exist yet and aborts EVERY fresh boot at STAGE=assert — before the emitter exists, so
  # the failure is itself unreportable. An earlier revision of this PR shipped exactly that, and
  # AC-F3 above passed the whole time because co-presence is not ordering.
  a_line="$(grep -nF "test -x /usr/local/bin/$h" "$BOOT" | head -1 | cut -d: -f1)"
  c_line="$(grep -nF "cat > /usr/local/bin/$h <<" "$BOOT" | head -1 | cut -d: -f1)"
  if [ -z "$a_line" ] || [ -z "$c_line" ]; then
    no "AC-F3b: could not locate both the assertion and the authoring line for $h (anchors drifted)"
  elif [ "$a_line" -gt "$c_line" ]; then
    ok "AC-F3b: $h is asserted (line $a_line) AFTER it is authored (line $c_line)"
  else
    no "AC-F3b: $h asserted at line $a_line BEFORE it is authored at line $c_line — this aborts every fresh boot"
  fi
done

# AC-F4: the @@SOLEUR_HOST_NAME@@ sentinel is spliced, and NO residual @@ survives in the
# emitter body. A typo'd sentinel would otherwise ship host_name=@@SOLEUR_HOST_NAME@@ silently
# on every single event.
if grep -qF '@@SOLEUR_HOST_NAME@@' "$BOOT" && grep -qE "sed -i .*@@SOLEUR_HOST_NAME@@.*/usr/local/bin/soleur-boot-emit" "$BOOT"; then
  ok "AC-F4a: @@SOLEUR_HOST_NAME@@ sentinel is spliced into soleur-boot-emit via sed -i"
else
  no "AC-F4a: expected an @@SOLEUR_HOST_NAME@@ sentinel + a 'sed -i' splice into soleur-boot-emit"
fi

# AC-H (most valuable criterion in the plan): NEVER merge the streams. `--format docker` writes
# the ENTIRE prd secret set to stdout. A `2>&1` / `&>` — or any stray stdout write inside the
# helper — turns this feature into credential exfiltration, or corrupts the env file so the
# fatal is misattributed to docker_run. Spans BOTH files, scoped to code lines.
helper_code="$(printf '%s\n' "$HELPER" | LC_ALL=C sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d')"
# Non-vacuity gate: every negative assertion below is a `grep -q` that CANNOT fail against an
# empty body. Without this, a missing/renamed heredoc delimiter turns the whole AC-H block —
# the most valuable criterion in the plan — into a silent, permanent green.
if [ -n "$helper_code" ]; then
  ok "AC-H0: the extracted helper body is non-empty (negative assertions below can fail)"
else
  no "AC-H0: helper body is EMPTY — every AC-H/AC-D/AC-E negative check below is VACUOUS"
fi
if printf '%s\n' "$helper_code" | grep -qE '2>&1|&>'; then
  no "AC-H1: soleur-doppler-download must never merge stderr into stdout (2>&1 / &>)"
else
  ok "AC-H1: no stream merge (2>&1 / &>) in the soleur-doppler-download body"
fi
# AC-H2: exactly ONE line may write to "$OUT", and it must be the doppler invocation.
# The previous form grepped `^\s*(echo|printf)[^>]*$` — whose `[^>]*$` clause structurally
# EXCLUDES every line containing `>`, i.e. precisely the shape that can corrupt the env file.
# A `printf 'INJECTED=x\n' >> "$OUT"` inside the loop passed that assertion and landed in the
# file `docker run --env-file` ingests. Count the write sites instead of pattern-matching prose.
out_writes="$(printf '%s\n' "$helper_code" | grep -cE '>>?[[:space:]]*"\$OUT"' || true)"
if [ "$out_writes" = 1 ]; then
  ok "AC-H2a: exactly one line writes to \$OUT (the CLI invocation)"
else
  no "AC-H2a: expected exactly 1 write to \$OUT, found $out_writes — a second writer corrupts the env file"
fi
# Join backslash-continuations first: the doppler call wraps, so `> "$OUT"` sits on the second
# physical line and a per-line match would compare against a fragment.
helper_joined="$(printf '%s\n' "$helper_code" | sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta')"
if printf '%s\n' "$helper_joined" | grep -E '>>?[[:space:]]*"\$OUT"' | grep -q 'doppler secrets download'; then
  ok "AC-H2b: the sole \$OUT writer is the doppler invocation"
else
  no "AC-H2b: the line writing \$OUT is not the doppler invocation"
fi
# ...and nothing may write to the helper's own stdout (unredirected printf/echo).
if printf '%s\n' "$helper_code" | grep -qE '^[[:space:]]*(echo|printf)([[:space:]][^|>]*)?$'; then
  no "AC-H2c: soleur-doppler-download writes to stdout (every printf/echo must be redirected)"
else
  ok "AC-H2c: soleur-doppler-download never writes to its own stdout"
fi
# The cloud-init terminal doppler region must not merge streams either.
ci_dl_region="$(awk '/^[[:space:]]*stage=doppler_download$/{f=1} f&&/^[[:space:]]*stage=docker_run$/{f=0} f{print}' "$CI" \
  | LC_ALL=C sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d')"
if [ -n "$ci_dl_region" ]; then
  ok "AC-H3a: located the cloud-init doppler_download region"
else
  no "AC-H3a: could not locate the cloud-init doppler_download region"
fi
if printf '%s\n' "$ci_dl_region" | grep -qE '2>&1|&>'; then
  no "AC-H3b: the cloud-init doppler_download region must not merge streams"
else
  ok "AC-H3b: no stream merge in the cloud-init doppler_download region"
fi

# AC-E(iii) STRUCTURAL half: the call site captures rc via the `&& rc=0 || rc=$?` form AND
# re-raises. The AND-OR list is set -e EXEMPT, so the capture ALONE deletes the fail-closed
# `exit` that lived inside the `if !` branch it replaces — worst case a host reporting
# cloud_init_complete with NO prd secrets, strictly worse than #6969 itself.
if printf '%s\n' "$ci_dl_region" | grep -qF 'soleur-doppler-download "$TMPENV" && rc=0 || rc=$?'; then
  ok "AC-E1: call site captures rc via the set -e-exempt AND-OR form (R9)"
else
  no "AC-E1: expected 'soleur-doppler-download \"\$TMPENV\" && rc=0 || rc=\$?' at the call site"
fi
if printf '%s\n' "$ci_dl_region" | grep -qE '\[ "\$rc" = 0 \] \|\| exit "\$rc"'; then
  ok "AC-E2: call site RE-RAISES the failure — boot stays fail-closed (R26)"
else
  no "AC-E2: missing the mandatory '[ \"\$rc\" = 0 ] || exit \"\$rc\"' re-raise (R26)"
fi
# The `if !` form must be gone: it yields $? = 0 in both dash and bash, so any exit_code it
# recorded would read 0 on EVERY failure.
if printf '%s\n' "$ci_dl_region" | grep -qE '^[[:space:]]*if ! '; then
  no "AC-E3: the 'if ! <cmd>' form must not gate the doppler download (\$? is 0 inside it)"
else
  ok "AC-E3: no 'if !' gate remains in the doppler_download region (R9)"
fi

# AC-D(ii): the attempt stage must not string-PREFIX any alert-filtered stage. The op-contract
# test asserts toContain("stage=doppler_download"); "doppler_download_attempt" satisfies that
# assertion without the real assignment, making the anti-rename guarantee vacuous.
# Anchored on CODE lines, not the raw body: this very carve-out guarantees the helper carries a
# comment naming the forbidden identifier, so a raw-token absence grep would red-fail forever on
# correct code. Non-vacuity for this check rides on AC-H0 above.
if printf '%s\n' "$helper_code" | grep -qF 'doppler_download_attempt'; then
  no "AC-D2: attempt stage must not be 'doppler_download_attempt' (string-prefixes the filtered stage, R20)"
else
  ok "AC-D2: attempt stage does not string-prefix an alert-filtered stage"
fi
if printf '%s\n' "$helper_code" | grep -qF 'doppler_retry'; then
  ok "AC-D2b: attempts use the distinct, non-prefixing stage 'doppler_retry'"
else
  no "AC-D2b: expected the attempt stage 'doppler_retry' in the helper"
fi

# AC-D(iii): the alert's filter VALUES are unchanged (scoped to `value = "..."` entries, not the
# block's raw text — the corrected payload comment may legitimately mention doppler_retry).
ALERTS="$DIR/sentry/issue-alerts.tf"
if [ -f "$ALERTS" ]; then
  vals="$(grep -oE 'value[[:space:]]*=[[:space:]]*"[a-z_]+"' "$ALERTS" | grep -oE '"[a-z_]+"' | tr -d '"' | sort -u | tr '\n' ' ')"
  if [ -z "$(printf '%s' "$vals" | tr -d '[:space:]')" ]; then
    no "AC-D3: extracted ZERO filter values from issue-alerts.tf — the negative below is vacuous"
  elif ! printf '%s' "$vals" | grep -qF 'doppler_download'; then
    no "AC-D3: extraction did not find the known filter value doppler_download — anchor drifted"
  fi
  if printf '%s' "$vals" | grep -qF 'doppler_retry'; then
    no "AC-D3: doppler_retry must NOT appear in the alert's filter values (would page on a healthy boot)"
  else
    ok "AC-D3: doppler_retry is absent from the alert's filter values (no false page, RK9)"
  fi
else
  no "AC-D3: could not read sentry/issue-alerts.tf"
fi

# AC-G: docker_run stderr is captured to the per-stage channel (the one alert-filtered sibling
# that dies with no echo at all, and the most likely next dark boot).
# AC-G1 (INVERTED from the plan, deliberately): docker's stderr must NOT be captured into the
# detail channel. `docker run --env-file` holds the entire prd secret set and quotes offending
# lines back verbatim on a parse error, so capturing it routes secret bytes into a tag on a
# PAGING alert. No regex closes it — a secret VALUE is arbitrary text. Tracked in #6971.
if grep -qF '2>/run/soleur-stage-detail.d/docker_run' "$CI"; then
  no "AC-G1: docker stderr must NOT be captured to the detail channel (prd-secret echo path)"
else
  ok "AC-G1: docker stderr is not routed into the detail channel (credential path closed)"
fi

# Bounded call: the failing download was the ONLY unbounded Doppler invocation in the file
# (11 bounded siblings). An unbounded hang emits NOTHING, so the channel would be structurally
# blind to the leading hypothesis' most common shape.
if printf '%s\n' "$helper_code" | grep -qE 'timeout -k [0-9]+ "\$TMO" doppler'; then
  ok "AC-E4: the doppler invocation is timeout-bounded WITH -k (a TERM-ignoring hang is still bounded)"
else
  no "AC-E4: the helper's doppler invocation must be wrapped in 'timeout' (R19)"
fi
if printf '%s\n' "$helper_code" | grep -qF 'NO_COLOR=1'; then
  ok "AC-A5: helper invokes the CLI with NO_COLOR=1 (deterministic payload)"
else
  no "AC-A5: helper must set NO_COLOR=1 for a deterministic stderr payload"
fi

# The message literal is FROZEN: changing it mints a NEW Sentry issue group, where value = 1
# means ">1" and a single fatal would then not page AT ALL (R12) — and darks the birth gate.
if printf '%s\n' "$EMIT" | grep -qF '"message":"soleur-cloud-init boot stage"'; then
  ok "AC-J1: the emitter's message literal is unchanged (paging correctness + gate lockstep)"
else
  no "AC-J1: the emitter's message literal MUST stay '\"message\":\"soleur-cloud-init boot stage\"'"
fi

# ─────────────────────────────── (B) BEHAVIORAL ───────────────────────────────
# Drive helper -> trap -> the REAL soleur-boot-emit. The detail gate lives INSIDE the emitter,
# so a stubbed emitter would remove the component under test (R24). Only `curl` is stubbed:
# it is the emitter's transport, and its captured argv IS the emitted body.

# Build a sandbox whose PATH carries: a `doppler` stub with scripted behavior, the REAL extracted
# emitter (with its sentinels resolved), and a `curl` stub capturing every POST body.
mk_sandbox() { # mk_sandbox <sandbox-dir> <doppler-script-body>
  local sb="$1"; local dop="$2"
  mkdir -p "$sb/bin" "$sb/detail.d" "$sb/tmp"
  # Write the RAW heredoc body, then run the SHIPPED `sed -i` splice lines against it. Doing our
  # own substitution here would make a typo in the production sentinel (which ships an empty DSN
  # and darkens the entire channel) invisible to every assertion in this file.
  printf '%s\n' "$EMIT" > "$sb/bin/soleur-boot-emit"
  splice="$(grep -F 'sed -i' "$BOOT" | grep -F '/usr/local/bin/soleur-boot-emit')"
  if [ -z "$splice" ]; then
    no "MK: could not extract the shipped sentinel splice lines from $BOOT"
  fi
  printf '%s\n' "$splice" \
    | sed "s#/usr/local/bin/soleur-boot-emit#$sb/bin/soleur-boot-emit#g" > "$sb/splice.sh"
  SOLEUR_SENTRY_DSN="https://pub@sentry.invalid/42" SOLEUR_HOST_NAME="soleur-web-test" \
    sh "$sb/splice.sh"
  if grep -q '@@' "$sb/bin/soleur-boot-emit"; then
    no "MK: residual @@ sentinel after the SHIPPED splice — a typo'd sentinel darkens the channel"
  fi
  printf '%s\n' "$HELPER" > "$sb/bin/soleur-doppler-download"
  # curl stub: record the -d body (the emitted event) one per line, always succeed.
  cat > "$sb/bin/curl" <<CURLSTUB
#!/bin/sh
prev=""
for a in "\$@"; do
  if [ "\$prev" = "-d" ]; then printf '%s\n' "\$a" >> "$sb/events.jsonl"; fi
  prev="\$a"
done
exit 0
CURLSTUB
  printf '%s\n' "$dop" > "$sb/bin/doppler"
  chmod +x "$sb/bin/"*
  : > "$sb/events.jsonl"
}

# Read back the Nth emitted event's field. Uses jq when present; the suite is gated on it.
ev_field() { # ev_field <events-file> <index 1-based> <jq-path>
  jq -r "$3 // empty" < <(sed -n "$2p" "$1") 2>/dev/null
}

if ! command -v jq >/dev/null 2>&1; then
  no "B0: jq is required for the behavioral half of this suite"
else
  ok "B0: jq present"

  # ── AC-B (THE headline invariant): exhaustion -> the fatal carries the CAUSE ──
  # Asserting only "one fatal tagged doppler_download" is the PROXY that let the first draft
  # ship green — that is byte-for-byte the #6969 symptom. Assert the detail is NON-EMPTY and
  # actually contains the CLI error line, the exit code and the attempt count.
  sb="$(mktemp -d -t ddl-acb.XXXXXXXX)"
  mk_sandbox "$sb" '#!/bin/sh
c="$(cat "$SOLEUR_TEST_CALLCOUNT" 2>/dev/null || echo 0)"; echo $((c+1)) > "$SOLEUR_TEST_CALLCOUNT"
printf "Using DOPPLER_TOKEN from the environment variable DOPPLER_TOKEN\n" >&2
printf "Using DOPPLER_CONFIG_DIR from the environment variable DOPPLER_CONFIG_DIR\n" >&2
printf "Doppler Error: Invalid Auth token\n" >&2
exit 7'
  out="$sb/envfile"; : > "$sb/callcount"
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    SOLEUR_TEST_CALLCOUNT="$sb/callcount" \
    SOLEUR_DOPPLER_BACKOFF_1=0 SOLEUR_DOPPLER_BACKOFF_2=0 \
    sh -c '
      set -e
      stage=terminal_preamble
      trap '"'"'rc=$?; [ "$rc" = 0 ] || soleur-boot-emit "$stage" fatal'"'"' EXIT
      stage=doppler_download
      soleur-doppler-download "'"$out"'" && rc=0 || rc=$?
      [ "$rc" = 0 ] || exit "$rc"
      stage=docker_run
      : > "'"$sb"'/REACHED_DOCKER_RUN"
    ' ) >/dev/null 2>&1
  rcmain=$?

  # m02/m03: `attempts=%s` prints the CONFIGURED value, so a loop that stops early still claims
  # the full count — the detail would LIE about how many times the CLI actually ran. Count the
  # stub's invocations and require the reported number to equal them.
  real_calls="$(cat "$sb/callcount" 2>/dev/null || echo 0)"
  if [ "$real_calls" = 3 ]; then
    ok "AC-B6a: the exhaust path really invoked the CLI 3 times"
  else
    no "AC-B6a: expected 3 CLI invocations on the exhaust path, counted $real_calls"
  fi
  exh_warns="$(grep -c '"level":"warning"' "$sb/events.jsonl" || true)"
  if [ "$exh_warns" = 2 ]; then
    ok "AC-B6b: exhaust path emits ATTEMPTS-1 = 2 retry breadcrumbs (none on the exhausting attempt)"
  else
    no "AC-B6b: expected 2 retry breadcrumbs on the exhaust path, got $exh_warns"
  fi
  fatal_line="$(grep -n '"level":"fatal"' "$sb/events.jsonl" | head -1 | cut -d: -f1)"
  if [ -n "$fatal_line" ]; then
    fstage="$(ev_field "$sb/events.jsonl" "$fatal_line" '.tags.stage')"
    fdetail="$(ev_field "$sb/events.jsonl" "$fatal_line" '.tags.detail')"
    if [ "$fstage" = "doppler_download" ]; then
      ok "AC-B1: exactly the doppler_download stage carries the fatal"
    else
      no "AC-B1: fatal stage was '$fstage', expected 'doppler_download'"
    fi
    if [ -n "$fdetail" ]; then
      ok "AC-B2: the fatal's detail is NON-EMPTY (the R15 defect stays dead)"
    else
      no "AC-B2: the fatal shipped an EMPTY detail — this is the #6969 symptom itself"
    fi
    if printf '%s' "$fdetail" | grep -qF 'Doppler Error'; then
      ok "AC-B3: the fatal's detail carries the CLI's own error line"
    else
      no "AC-B3: detail must contain the CLI error line, got: '$fdetail'"
    fi
    if printf '%s' "$fdetail" | grep -qE 'rc=7'; then
      ok "AC-B4: the fatal's detail carries the real exit code (rc=7, not 0 — R9)"
    else
      no "AC-B4: detail must carry rc=7, got: '$fdetail'"
    fi
    if printf '%s' "$fdetail" | grep -qF 'cond=error'; then
      ok "AC-B4b: the fatal names the CONDITION class (cond=error), not just the code"
    else
      no "AC-B4b: detail must carry cond=error, got: '$fdetail'"
    fi
    if printf '%s' "$fdetail" | grep -qE 'attempts=3'; then
      ok "AC-B5: the fatal's detail carries the attempt count"
    else
      no "AC-B5: detail must carry attempts=3, got: '$fdetail'"
    fi
    if printf '%s' "$fdetail" | grep -qF 'Using DOPPLER'; then
      no "AC-A1: the 'Using DOPPLER_*' preamble must be dropped (it is what defeated head -c)"
    else
      ok "AC-A1: the CLI preamble is dropped before the cap (R1)"
    fi
    dlen=$(printf '%s' "$fdetail" | wc -c)
    if [ "$dlen" -le 180 ]; then
      ok "AC-A2: detail is within the byte cap ($dlen <= 180)"
    else
      no "AC-A2: detail exceeded the cap ($dlen > 180)"
    fi
    fhost="$(ev_field "$sb/events.jsonl" "$fatal_line" '.tags.host_name')"
    if [ "$fhost" = "soleur-web-test" ]; then
      ok "AC-F4b: the fatal carries a resolved host_name tag (no residual @@)"
    else
      no "AC-F4b: host_name tag was '$fhost', expected the spliced 'soleur-web-test'"
    fi
  else
    no "AC-B1..B5/AC-A1..A2/AC-F4b: no fatal event was emitted at all"
  fi

  # AC-E(iii) BEHAVIORAL: the boot must NOT reach docker_run when the download fails.
  if [ -e "$sb/REACHED_DOCKER_RUN" ]; then
    no "AC-E5: execution reached docker_run after a failed download — boot is FAIL-OPEN (R26)"
  else
    ok "AC-E5: execution stopped before docker_run — boot stays fail-closed (R26)"
  fi
  if [ "$rcmain" = 7 ]; then
    ok "AC-E6: the terminal block exits with the CLI's own exit code (7)"
  else
    no "AC-E6: terminal block exited $rcmain, expected 7"
  fi
  rm -rf "$sb"

  # ── AC-E(ii): a HANG is recorded as rc=124 (previously produced NO event at all) ──
  sb="$(mktemp -d -t ddl-ace.XXXXXXXX)"
  mk_sandbox "$sb" '#!/bin/sh
sleep 30
exit 0'
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    SOLEUR_DOPPLER_TIMEOUT=1 SOLEUR_DOPPLER_ATTEMPTS=1 \
    SOLEUR_DOPPLER_BACKOFF_1=0 SOLEUR_DOPPLER_BACKOFF_2=0 \
    sh -c '
      set -e
      stage=doppler_download
      trap '"'"'rc=$?; [ "$rc" = 0 ] || soleur-boot-emit "$stage" fatal'"'"' EXIT
      soleur-doppler-download "'"$sb"'/envfile" && rc=0 || rc=$?
      [ "$rc" = 0 ] || exit "$rc"
    ' ) >/dev/null 2>&1
  hang_line="$(grep -n '"level":"fatal"' "$sb/events.jsonl" | head -1 | cut -d: -f1)"
  hdetail="$(ev_field "$sb/events.jsonl" "${hang_line:-1}" '.tags.detail')"
  if printf '%s' "$hdetail" | grep -qE 'rc=124'; then
    ok "AC-E7: a hang is recorded as rc=124, a distinct named condition (R19)"
  else
    no "AC-E7: expected rc=124 for a hung CLI, got: '$hdetail'"
  fi
  if printf '%s' "$hdetail" | grep -qF 'cond=timeout'; then
    ok "AC-E7b: the hang is CLASSIFIED as cond=timeout (distinguishes it from an auth failure)"
  else
    no "AC-E7b: expected cond=timeout for a hung CLI, got: '$hdetail'"
  fi
  rm -rf "$sb"

  # ── AC-C: evidence preserved on SUCCESS (fail-once-then-succeed) ──
  sb="$(mktemp -d -t ddl-acc.XXXXXXXX)"
  mk_sandbox "$sb" '#!/bin/sh
C="$SOLEUR_TEST_COUNTER"
n=$(cat "$C" 2>/dev/null || echo 0)
n=$((n+1)); printf "%s" "$n" > "$C"
if [ "$n" = 1 ]; then printf "Doppler Error: transient 503\n" >&2; exit 5; fi
printf "SECRET_A=1\n"
exit 0'
  : > "$sb/counter"
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    SOLEUR_TEST_COUNTER="$sb/counter" \
    SOLEUR_DOPPLER_BACKOFF_1=0 SOLEUR_DOPPLER_BACKOFF_2=0 \
    sh -c '
      set -e
      stage=doppler_download
      trap '"'"'rc=$?; [ "$rc" = 0 ] || soleur-boot-emit "$stage" fatal'"'"' EXIT
      soleur-doppler-download "'"$sb"'/envfile" && rc=0 || rc=$?
      [ "$rc" = 0 ] || exit "$rc"
    ' ) >/dev/null 2>&1
  succ_rc=$?
  if [ "$succ_rc" = 0 ]; then
    ok "AC-C1: a transient failure retries and the download SUCCEEDS"
  else
    no "AC-C1: expected success after one transient failure, exit was $succ_rc"
  fi
  if grep -qF 'SECRET_A=1' "$sb/envfile" 2>/dev/null; then
    ok "AC-C2: the secret payload landed in the target env file uncorrupted"
  else
    no "AC-C2: the target env file did not receive the CLI's stdout payload"
  fi
  if grep -qF '"level":"fatal"' "$sb/events.jsonl"; then
    no "AC-C3: no fatal may be emitted when the download ultimately succeeds"
  else
    ok "AC-C3: no fatal emitted on eventual success"
  fi
  warns="$(grep -c '"level":"warning"' "$sb/events.jsonl" || echo 0)"
  if [ "$warns" = 1 ]; then
    ok "AC-C4: exactly one warning breadcrumb for the one failed attempt"
  else
    no "AC-C4: expected exactly 1 warning breadcrumb, got $warns"
  fi
  wline="$(grep -n '"level":"warning"' "$sb/events.jsonl" | head -1 | cut -d: -f1)"
  wstage="$(ev_field "$sb/events.jsonl" "${wline:-1}" '.tags.stage')"
  wdetail="$(ev_field "$sb/events.jsonl" "${wline:-1}" '.tags.detail')"
  if [ "$wstage" = "doppler_retry" ]; then
    ok "AC-D1: the warning uses stage=doppler_retry at RUNTIME (not a filtered stage — RK9)"
  else
    no "AC-D1: warning stage was '$wstage', expected 'doppler_retry'"
  fi
  if [ -n "$wdetail" ] && printf '%s' "$wdetail" | grep -qF 'transient 503'; then
    ok "AC-C5: the retry warning carries the attempt's own cause"
  else
    no "AC-C5: retry warning detail must carry the attempt's cause, got: '$wdetail'"
  fi
  # AC-D(i): NO warning-level emit may carry any alert-filtered stage value at runtime.
  bad=""
  ln=0
  while IFS= read -r line; do
    ln=$((ln+1))
    lvl="$(printf '%s' "$line" | jq -r '.level // empty' 2>/dev/null)"
    stg="$(printf '%s' "$line" | jq -r '.tags.stage // empty' 2>/dev/null)"
    [ "$lvl" = "warning" ] || continue
    case "$stg" in
      terminal_preamble|doppler_download|docker_run|hostscripts_incomplete) bad="$bad $stg" ;;
    esac
  done < "$sb/events.jsonl"
  if [ -z "$bad" ]; then
    ok "AC-D4: no warning-level emit carries an alert-filtered stage value (no false page)"
  else
    no "AC-D4: warning-level emit(s) carried filtered stage(s):$bad — would page on a healthy boot"
  fi
  # T5a: no stderr temp-file residue on the SUCCESS path. Read the find output into a variable
  # rather than `find | grep -q` — this file's own rule (see header): under pipefail an early
  # match SIGPIPEs the producer, the pipeline exits non-zero, and the negative assertion silently
  # reports "clean" on a run that DID leak. The earlier form was also vacuous: it compared
  # -newer against a stamp the stub rewrote after the buffer was truncated, so it could never
  # be true regardless of the code under test.
  leaked_ok="$(find "$sb/tmp" -name 'doppler-err.*' 2>/dev/null | head -3)"
  if [ -z "$leaked_ok" ]; then
    ok "T5a: no stderr temp-file residue after a successful download"
  else
    no "T5a: a doppler stderr temp file leaked on the success path: $leaked_ok"
  fi
  rm -rf "$sb"

  # ── T5b: temp-file hygiene on the FAILURE path ──
  # The helper mktemps its stderr buffer and owns its own EXIT trap for it: it runs as a separate
  # process, so the cloud-init terminal block's trap cannot see that variable. The failure path is
  # the one that matters — it is the path that runs on the boot nobody is watching.
  sb="$(mktemp -d -t ddl-t5b.XXXXXXXX)"
  mk_sandbox "$sb" '#!/bin/sh
printf "Doppler Error: fail\n" >&2
exit 4'
  touch "$sb/.stamp"
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    SOLEUR_DOPPLER_ATTEMPTS=1 SOLEUR_DOPPLER_BACKOFF_1=0 SOLEUR_DOPPLER_BACKOFF_2=0 \
    sh -c 'soleur-doppler-download "'"$sb"'/envfile"' ) >/dev/null 2>&1
  leaked="$(find "$sb/tmp" -name 'doppler-err.*' 2>/dev/null | head -3)"
  if [ -z "$leaked" ]; then
    ok "T5b: no stderr temp-file residue after an EXHAUSTED (failing) download"
  else
    no "T5b: stderr temp file leaked on the failure path: $leaked"
  fi
  rm -rf "$sb"

  # ── T7b: the emitter reads ONLY the per-stage file — no legacy-buffer fallback ──
  # An earlier revision fell back to the shared /run/soleur-stage-detail when a stage had no
  # per-stage file. That made every detail-less stage — including INFO emits on HEALTHY boots —
  # ship whatever the ghcr/pull producers had left in the shared buffer, i.e. another stage's
  # captured output presented as this stage's cause. A plausible WRONG cause is worse than none.
  sb="$(mktemp -d -t ddl-t7b.XXXXXXXX)"
  mk_sandbox "$sb" '#!/bin/sh
exit 0'
  printf 'ghcr_login_fail: legacy-buffer-content\n' > "$sb/legacy"
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    SOLEUR_STAGE_DETAIL_FILE="$sb/legacy" \
    sh -c 'soleur-boot-emit pull fatal' ) >/dev/null 2>&1
  leg="$(ev_field "$sb/events.jsonl" 1 '.tags.detail')"
  if [ -z "$leg" ]; then
    ok "T7b: a stage with no per-stage file emits an EMPTY detail (no legacy-buffer bleed)"
  else
    no "T7b: legacy buffer bled into an unrelated stage's detail: '$leg'"
  fi
  # ...and a healthy INFO emit must not pick up the buffer either.
  : > "$sb/events.jsonl"
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    SOLEUR_STAGE_DETAIL_FILE="$sb/legacy" \
    sh -c 'soleur-boot-emit cloud_init_complete info' ) >/dev/null 2>&1
  legi="$(ev_field "$sb/events.jsonl" 1 '.tags.detail')"
  if [ -z "$legi" ]; then
    ok "T7c: a healthy cloud_init_complete INFO emit carries no captured output"
  else
    no "T7c: a green boot's INFO emit shipped captured output: '$legi'"
  fi
  rm -rf "$sb"

  # ── Emitter-DIRECT redaction (each layer pinned independently) ──
  # The helper scrubs AND the emitter scrubs. Driving only the helper path means mutating either
  # layer alone leaves the other covering for it, so neither is actually verified. These fixtures
  # write straight to the detail dir, so only the emitter can redact them.
  # Every literal below is SYNTHESIZED and split across concatenation so no contiguous
  # vendor-token shape exists in source (GitHub push protection), while the runtime value keeps
  # the redactor-matching shape.
  sb="$(mktemp -d -t ddl-red.XXXXXXXX)"
  mk_sandbox "$sb" '#!/bin/sh
exit 0'
  {
    printf 'Doppler Error: KEEPTHISCAUSE token %s rejected\n' "dp.""st.prd.aB3xK9mQ7zP1wR5tY8uI2oL4nH6gF0dS"
    printf 'dial %s failed\n' "postgres://svc:S3cr3tP4ss@db.internal:5432/app"
    printf 'auth %s\n' "Bearer ""eyJhbGciOiJIUzI1NiJ9.PAYLOAD.sig"
    printf 'gh %s\n' "ghp_""AbCdEfGhIjKlMnOpQrStUvWxYz0123456789"
    printf 'image ghcr.io/jikig-ai/soleur-web-platform:latest@sha256:deadbeef\n'
  } > "$sb/detail.d/redstage"
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    sh -c 'soleur-boot-emit redstage fatal' ) >/dev/null 2>&1
  red="$(ev_field "$sb/events.jsonl" 1 '.tags.detail')"
  for shape in 'aB3xK9mQ7zP1wR5tY8uI2oL4nH6gF0dS:doppler-token-entropy' \
               'S3cr3tP4ss:URI-userinfo password' \
               'PAYLOAD.sig:Bearer token' \
               'AbCdEfGhIjKlMnOpQrStUvWxYz:GitHub token'; do
    pat="${shape%%:*}"; label="${shape#*:}"
    if printf '%s' "$red" | grep -qF "$pat"; then
      no "AC-A14: the EMITTER leaked a $label into the detail tag"
    else
      ok "AC-A14: the emitter redacts $label"
    fi
  done
  rm -rf "$sb"

  # ── AC-A15: the OTHER direction — redaction must not eat the diagnostic ──
  # Its own fixture, deliberately SHORT: the 180-byte cap keeps the TAIL, so a multi-shape
  # fixture pushes the marker out and the assertion silently reads the filler instead. The
  # keep-marker sits on the SAME line as the token, so a rule that DELETES matching lines
  # (rather than substituting) is caught — that rule yields an empty cause, i.e. the #6969
  # symptom, while every absence-assertion above stays green.
  sb="$(mktemp -d -t ddl-red2.XXXXXXXX)"
  mk_sandbox "$sb" '#!/bin/sh
exit 0'
  printf 'KEEPTHISCAUSE bad token %s here\n' "dp.""st.prd.aB3xK9mQ7zP1wR5tY8uI2oL4nH6gF0dS" \
    > "$sb/detail.d/keepstage"
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    sh -c 'soleur-boot-emit keepstage fatal' ) >/dev/null 2>&1
  keep="$(ev_field "$sb/events.jsonl" 1 '.tags.detail')"
  if printf '%s' "$keep" | grep -qF 'KEEPTHISCAUSE'; then
    ok "AC-A15a: redaction preserves the non-secret remainder of a token-bearing line"
  else
    no "AC-A15a: the redactor destroyed the diagnostic line — empty cause is the #6969 symptom"
  fi
  if printf '%s' "$keep" | grep -qF 'aB3xK9mQ7zP1wR5tY8uI2oL4nH6gF0dS'; then
    no "AC-A15a2: FIXTURE/SUT ERROR — the token survived on the very line being kept"
  else
    ok "AC-A15a2: ...while still redacting the token on that same line"
  fi
  printf 'image ghcr.io/jikig-ai/soleur-web-platform:latest@sha256:deadbeef pull denied\n' \
    > "$sb/detail.d/imgstage"
  : > "$sb/events.jsonl"
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    sh -c 'soleur-boot-emit imgstage fatal' ) >/dev/null 2>&1
  img="$(ev_field "$sb/events.jsonl" 1 '.tags.detail')"
  if printf '%s' "$img" | grep -qF 'soleur-web-platform:latest@sha256:'; then
    ok "AC-A15b: redaction preserves docker image refs (userinfo rule is scheme-anchored)"
  else
    no "AC-A15b: the userinfo rule ate a docker image ref — the primary docker_run diagnostic"
  fi
  rm -rf "$sb"

  # ── rc=0 with an EMPTY payload must be a named failure, not success ──
  # `doppler` can exit 0 having written nothing, and `docker run --env-file <empty>` then STARTS
  # the container: the host reaches cloud_init_complete and the gate reports "booted clean" while
  # it serves with zero prd secrets. Strictly worse than a dark host.
  sb="$(mktemp -d -t ddl-empty.XXXXXXXX)"
  mk_sandbox "$sb" '#!/bin/sh
exit 0'
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    SOLEUR_DOPPLER_ATTEMPTS=1 SOLEUR_DOPPLER_BACKOFF_1=0 SOLEUR_DOPPLER_BACKOFF_2=0 \
    sh -c '
      set -e
      stage=doppler_download
      trap '"'"'rc=$?; [ "$rc" = 0 ] || soleur-boot-emit "$stage" fatal'"'"' EXIT
      soleur-doppler-download "'"$sb"'/envfile" && rc=0 || rc=$?
      [ "$rc" = 0 ] || exit "$rc"
      : > "'"$sb"'/REACHED_DOCKER_RUN"
    ' ) >/dev/null 2>&1
  if [ -e "$sb/REACHED_DOCKER_RUN" ]; then
    no "AC-C6a: a zero-exit EMPTY payload was treated as success — host would serve with no prd secrets"
  else
    ok "AC-C6a: a zero-exit EMPTY payload is fail-closed (never reaches docker_run)"
  fi
  emptyd="$(ev_field "$sb/events.jsonl" 1 '.tags.detail')"
  if printf '%s' "$emptyd" | grep -qF 'cond=empty_payload'; then
    ok "AC-C6b: the empty-payload failure is CLASSIFIED distinctly (cond=empty_payload)"
  else
    no "AC-C6b: expected cond=empty_payload, got: '$emptyd'"
  fi
  rm -rf "$sb"

  # ── AC-I: channel isolation — a detail written for one stage must not bleed into another ──
  sb="$(mktemp -d -t ddl-aci.XXXXXXXX)"
  mk_sandbox "$sb" '#!/bin/sh
exit 0'
  printf 'doppler_download failed rc=9 attempts=3 Doppler Error: isolated\n' > "$sb/detail.d/doppler_download"
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    sh -c 'soleur-boot-emit docker_run fatal' ) >/dev/null 2>&1
  iso="$(ev_field "$sb/events.jsonl" 1 '.tags.detail')"
  if [ -z "$iso" ]; then
    ok "AC-I1: a doppler_download detail does not bleed into a docker_run emit (RK10)"
  else
    no "AC-I1: cross-stage detail contamination — docker_run read '$iso'"
  fi
  : > "$sb/events.jsonl"
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    sh -c 'soleur-boot-emit doppler_download fatal' ) >/dev/null 2>&1
  iso2="$(ev_field "$sb/events.jsonl" 1 '.tags.detail')"
  if printf '%s' "$iso2" | grep -qF 'isolated'; then
    ok "AC-I2: the matching stage DOES read its own per-stage detail file"
  else
    no "AC-I2: doppler_download emit did not read .d/doppler_download, got: '$iso2'"
  fi
  rm -rf "$sb"

  # ── AC-A (sanitizer): adversarial fixture through the SHIPPED emitter ──
  # SYNTHESIZED fixture only (cq-test-fixtures-synthesized-only): the token below is fake and
  # is split across a concatenation at no point because it never matches a real vendor prefix
  # scanner shape beyond the redaction pattern this asserts.
  sb="$(mktemp -d -t ddl-aca.XXXXXXXX)"
  mk_sandbox "$sb" '#!/bin/sh
exit 0'
  # TWO fixtures, deliberately. An earlier single fixture appended 4 KB of junk AFTER the
  # adversarial content; because the sanitizer keeps the LAST 180 bytes, the detail was a run of
  # 180 'J's and every sanitization assertion below passed against content that could not
  # violate them — four vacuous greens from one over-stuffed fixture. `advstage` now carries
  # ONLY the adversarial content (short enough to survive the cap, so each property is asserted
  # against bytes that could actually break it); `capstage` carries the oversize junk and is the
  # only fixture the cap assertion reads.
  {
    printf 'Using DOPPLER_TOKEN from the environment variable DOPPLER_TOKEN\n'
    printf 'Doppler Error: quote" backslash\\ and \033[31mANSI\033[0m plus \007bell\n'
    printf 'line two\nline three\n'
    printf '   trailing and leading   \n'
  } > "$sb/detail.d/advstage"
  { head -c 4000 /dev/zero | tr '\0' 'J'; printf '\n'; } > "$sb/detail.d/capstage"
  # UTF-8 split fixture for the post-cap printable-ASCII pass. The cap is a BYTE-wise `tail`, so
  # it can cut a multi-byte sequence in half and emit a lone continuation byte. Lengths are
  # chosen so the cut MUST land mid-character: 50x U+20AC (3 B) + 20x U+00E9 (2 B) = 190 B, so
  # keeping the last 180 drops 10 bytes and starts the tail 2 bytes into a 3-byte sequence.
  # Without a fixture that actually splits, the ASCII pass is untested (every other fixture is
  # already ASCII after the control-strip, so deleting the step changes nothing).
  # The ASCII marker sits at the END so it survives the tail: without it the fixture sanitizes
  # to the empty string (everything was non-ASCII) and the assertion could not tell "stripped
  # the split residue" from "stripped absolutely everything".
  { for _ in $(seq 50); do printf '\342\202\254'; done
    for _ in $(seq 20); do printf '\303\251'; done
    printf ' OK-TAIL-MARKER\n'; } > "$sb/detail.d/utf8stage"
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    sh -c 'soleur-boot-emit advstage fatal' ) >/dev/null 2>&1
  raw="$(sed -n 1p "$sb/events.jsonl")"
  if printf '%s' "$raw" | jq -e . >/dev/null 2>&1; then
    ok "AC-A3: adversarial fixture still yields VALID JSON through the shipped emitter"
  else
    no "AC-A3: adversarial fixture produced INVALID JSON: $(printf '%s' "$raw" | head -c 200)"
  fi
  adv="$(printf '%s' "$raw" | jq -r '.tags.detail // empty' 2>/dev/null)"
  # Precondition self-check: if the adversarial fixture ever grows past the cap again, every
  # assertion below silently degrades to testing the tail filler instead of the content. Fail
  # as a clear FIXTURE error rather than a phantom pass.
  if printf '%s' "$adv" | grep -qF 'Doppler Error'; then
    ok "AC-A4a: the adversarial content survived the cap (assertions below are non-vacuous)"
  else
    no "AC-A4a: FIXTURE ERROR — adversarial content was capped away; assertions below are vacuous"
  fi
  # The cap is asserted against its OWN oversize fixture.
  : > "$sb/events.jsonl"
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    sh -c 'soleur-boot-emit capstage fatal' ) >/dev/null 2>&1
  capd="$(ev_field "$sb/events.jsonl" 1 '.tags.detail')"
  caplen=$(printf '%s' "$capd" | wc -c)
  # EXACT equality, not <=: the fixture is a deterministic 4000-byte run, so the output length is
  # fully determined. `<= 180` passed identically with the cap set to 100, leaving the value free.
  if [ "$caplen" = 180 ]; then
    ok "AC-A4b: a 4 KB detail is capped to exactly 180 bytes"
  else
    no "AC-A4b: oversize detail length was $caplen (expected exactly 180)"
  fi
  # Newline folding: lines must be joined by a SPACE, not concatenated. Newlines are documented
  # as impermissible in Sentry tag values; the trailing printable-ASCII pass would strip them
  # either way, so without this assertion the fold step is untested and words would silently run
  # together in the one field an operator reads to diagnose a dark boot.
  if printf '%s' "$adv" | grep -qF 'line two line three'; then
    ok "AC-A4c: newlines fold to spaces (multi-line stderr stays readable)"
  else
    no "AC-A4c: expected 'line two line three' (folded), got: '$adv'"
  fi
  # ISOLATING assertion for the EMITTER's own preamble strip. AC-B/AC-A1 above exercise the
  # helper->emitter composition, where the helper has already dropped the preamble — so they
  # stay green if the emitter's strip is deleted. This fixture is written straight to the
  # detail dir, so only the emitter can remove it.
  if printf '%s' "$adv" | grep -qF 'Using DOPPLER'; then
    no "AC-A12: the EMITTER must drop the '^Using ' preamble itself (defence in depth, R1)"
  else
    ok "AC-A12: the emitter independently drops the CLI preamble"
  fi
  if printf '%s' "$adv" | grep -qE '\[3[0-9]m|\[0m'; then
    no "AC-A7: ANSI escape residue survived the sanitizer"
  else
    ok "AC-A7: no ANSI residue in the sanitized detail"
  fi
  if printf '%s' "$adv" | LC_ALL=C grep -q '[^ -~]'; then
    no "AC-A8: non-ASCII/control bytes survived the sanitizer"
  else
    ok "AC-A8: sanitized detail is printable-ASCII only"
  fi
  case "$adv" in
    ' '*|*' ') no "AC-A9: sanitized detail has leading/trailing whitespace" ;;
    *) ok "AC-A9: sanitized detail is trimmed" ;;
  esac
  # AC-A13: the byte-wise cap must never emit a partial multi-byte sequence.
  : > "$sb/events.jsonl"
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    sh -c 'soleur-boot-emit utf8stage fatal' ) >/dev/null 2>&1
  u8raw="$(sed -n 1p "$sb/events.jsonl")"
  if printf '%s' "$u8raw" | jq -e . >/dev/null 2>&1; then
    ok "AC-A13a: a cap that splits a UTF-8 sequence still yields valid JSON"
  else
    no "AC-A13a: split UTF-8 produced INVALID JSON"
  fi
  u8="$(printf '%s' "$u8raw" | jq -r '.tags.detail // empty' 2>/dev/null)"
  if ! printf '%s' "$u8" | grep -qF 'OK-TAIL-MARKER'; then
    no "AC-A13b: FIXTURE ERROR — the ASCII tail marker did not survive; assertion is vacuous"
  elif printf '%s' "$u8" | LC_ALL=C grep -q '[^ -~]'; then
    no "AC-A13b: non-ASCII/partial-sequence bytes survived the cap, got: '$(printf '%s' "$u8" | head -c 60)'"
  else
    ok "AC-A13b: the post-cap pass leaves printable ASCII only (no split-sequence residue)"
  fi
  rm -rf "$sb"

  # ── Secret-scrub: a token-shaped string in stderr is redacted before ANY write ──
  sb="$(mktemp -d -t ddl-scr.XXXXXXXX)"
  # The literal below is SYNTHESIZED and split so no contiguous vendor-token shape exists in
  # source (GitHub push protection); the runtime value keeps the redactor-matching shape.
  mk_sandbox "$sb" '#!/bin/sh
printf "Doppler Error: bad token %s\n" "dp.""st.SYNTHETICPLACEHOLDERVALUE0000" >&2
exit 3'
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    SOLEUR_DOPPLER_ATTEMPTS=1 SOLEUR_DOPPLER_BACKOFF_1=0 SOLEUR_DOPPLER_BACKOFF_2=0 \
    sh -c '
      stage=doppler_download
      trap '"'"'rc=$?; [ "$rc" = 0 ] || soleur-boot-emit "$stage" fatal'"'"' EXIT
      soleur-doppler-download "'"$sb"'/envfile" && rc=0 || rc=$?
      [ "$rc" = 0 ] || exit "$rc"
    ' ) >/dev/null 2>&1
  scrubbed="$(ev_field "$sb/events.jsonl" 1 '.tags.detail')"
  if printf '%s' "$scrubbed" | grep -qE 'dp\.st\.SYNTHETIC'; then
    no "AC-A10: a token-shaped string reached the emitted payload unredacted (RK3)"
  else
    ok "AC-A10: token-shaped strings are scrubbed before any write (RK3)"
  fi
  if grep -rqE 'dp\.st\.SYNTHETIC' "$sb/detail.d" 2>/dev/null; then
    no "AC-A11: a token-shaped string was written to the detail file unredacted"
  else
    ok "AC-A11: the detail file on disk carries no token-shaped string"
  fi
  rm -rf "$sb"

  # ── Non-vacuity control: with NO detail file, the emitter must still emit valid JSON ──
  sb="$(mktemp -d -t ddl-nv.XXXXXXXX)"
  mk_sandbox "$sb" '#!/bin/sh
exit 0'
  ( PATH="$sb/bin:$PATH" SOLEUR_STAGE_DETAIL_DIR="$sb/detail.d" SOLEUR_DOPPLER_ERRDIR="$sb/tmp" \
    sh -c 'soleur-boot-emit nodetail info' ) >/dev/null 2>&1
  nv="$(sed -n 1p "$sb/events.jsonl")"
  if printf '%s' "$nv" | jq -e '.tags.stage == "nodetail"' >/dev/null 2>&1; then
    ok "CTL1: the emitter still emits a valid event when no detail file exists (fail-open)"
  else
    no "CTL1: emitter broke when no detail file was present"
  fi
  rm -rf "$sb"
fi


# ───────────────── (C) BIRTH-PATH GATE: the RUN must name the cause (AC-M) ─────────────────
# The gate's jq is embedded in YAML inside a shell heredoc, three quoting layers deep. A filter
# that is merely MALFORMED returns empty and the gate degrades to exactly the uninformative
# "last-reached stage: doppler_download" annotation this PR exists to replace — silently, and on
# the one run an operator is actually reading. So run the SHIPPED filter against a fixture.
WF="$(cd "$DIR/../../.." && pwd)/.github/workflows/apply-web-platform-infra.yml"
# #6969: the boot-trail reader was EXTRACTED out of the workflow's web_host_create `run:`
# block into a script, so the REPLACE path (web_host_replace) executes the same bytes rather
# than a second copy. Every AC below that inspects the READER's own filter logic therefore
# reads this file; the workflow is still the subject of AC-M0 (it must exist and wire it).
# Missing this re-point is what turned this suite red at run-registered-suites.sh — the
# observability suite next door was re-pointed in the same change and this sibling was not,
# which is the orphan-suite class exactly.
TRAIL="$(cd "$DIR/../../.." && pwd)/apps/web-platform/infra/scripts/fresh-host-boot-trail.sh"
if [ ! -f "$WF" ]; then
  no "AC-M0: could not locate apply-web-platform-infra.yml"
elif [ ! -s "$TRAIL" ]; then
  no "AC-M0: could not locate the extracted boot-trail reader ($TRAIL) — every reader-scoped assertion below would grep nothing and pass vacuously"
elif ! grep -qF 'apps/web-platform/infra/scripts/fresh-host-boot-trail.sh' "$WF"; then
  no "AC-M0: the workflow no longer invokes scripts/fresh-host-boot-trail.sh — the reader can be perfect and still never run"
else
  ok "AC-M0: located the birth-path workflow, the extracted boot-trail reader, and the wiring between them"
  # Pull the host-matching jq function out of the workflow itself (single source — a copy here
  # would drift and this suite would then be verifying its own copy, not the shipped gate).
  # The workflow defines it as a jq `def` so its jq programs can stay single-quoted, which is
  # what keeps the `test($re)` literal that the observability suite's AC16 pins byte-identical.
  HOSTDEF_WF="$(grep -F "JQ_HOSTDEF='" "$TRAIL" | head -1 | sed -e "s/^[[:space:]]*JQ_HOSTDEF='//" -e "s/'$//")"
  if [ -n "$HOSTDEF_WF" ]; then
    ok "AC-M1: extracted the host-matching jq def from the shipped workflow"
  else
    no "AC-M1: could not extract JQ_HOSTDEF from the workflow"
  fi
  HOSTSEL_WF='hostok($eh)'
  fx="$(mktemp -t ddl-fx.XXXXXXXX.json)"
  cat > "$fx" <<'FIXEOF'
[
  {"message":"soleur-cloud-init boot stage","dateCreated":"2026-07-26T16:51:58Z",
   "tags":[{"key":"stage","value":"doppler_download"},{"key":"level","value":"fatal"},
           {"key":"host_name","value":"soleur-web-2"},
           {"key":"detail","value":"doppler_download rc=124 cond=timeout attempts=3 Doppler Error: context deadline exceeded"}]},
  {"message":"soleur-cloud-init boot stage","dateCreated":"2026-07-26T16:51:40Z",
   "tags":[{"key":"stage","value":"doppler_retry"},{"key":"level","value":"warning"},
           {"key":"host_name","value":"soleur-web-2"},
           {"key":"detail","value":"doppler_retry rc=124 cond=timeout attempt=1/3 Doppler Error: context deadline exceeded"}]},
  {"message":"soleur-cloud-init boot stage","dateCreated":"2026-07-26T16:40:00Z",
   "tags":[{"key":"stage","value":"cloud_init_complete"},{"key":"level","value":"info"},
           {"key":"host_name","value":"soleur-web-platform"},{"key":"detail","value":""}]},
  {"message":"soleur-cloud-init boot stage","dateCreated":"2026-07-26T16:30:00Z",
   "tags":[{"key":"stage","value":"docker_run"},{"key":"level","value":"info"}]}
]
FIXEOF
  MSG_RE_T='soleur-cloud-init boot stage'
  EH='soleur-web-2'
  m_stage="$(jq -r --arg re "$MSG_RE_T" --arg eh "$EH" "$HOSTDEF_WF
    [ .[] | select(((.message // .title) // \"\") | test(\$re)) | select($HOSTSEL_WF)
          | ([ (.tags // [])[]? | select(.key==\"stage\") | .value ][0] // \"?\") ][0] // \"\"" < "$fx" 2>/dev/null)"
  m_detail="$(jq -r --arg re "$MSG_RE_T" --arg eh "$EH" "$HOSTDEF_WF
    [ .[] | select(((.message // .title) // \"\") | test(\$re)) | select($HOSTSEL_WF)
          | ([ (.tags // [])[]? | select(.key==\"detail\") | .value ][0] // \"\") ][0] // \"\"" < "$fx" 2>/dev/null)"
  if [ "$m_stage" = "doppler_download" ]; then
    ok "AC-M2: the gate's jq selects the failing stage"
  else
    no "AC-M2: gate jq returned stage '$m_stage', expected 'doppler_download'"
  fi
  if printf '%s' "$m_detail" | grep -qF 'rc=124'; then
    ok "AC-M3: the gate's jq surfaces the detail (cause), not just the stage"
  else
    no "AC-M3: gate jq returned detail '$m_detail', expected one containing rc=124"
  fi
  # HOST SCOPING: the web-1 event must NOT be selected when web-2 is the host under test. This
  # is the ambiguity that forced a Hetzner API lookup during the #6969 investigation.
  m_other="$(jq -r --arg re "$MSG_RE_T" --arg eh "soleur-web-9" "$HOSTDEF_WF
    [ .[] | select(((.message // .title) // \"\") | test(\$re)) | select($HOSTSEL_WF)
          | ([ (.tags // [])[]? | select(.key==\"stage\") | .value ][0] // \"?\") ][0] // \"\"" < "$fx" 2>/dev/null)"
  if [ "$m_other" = "docker_run" ]; then
    ok "AC-M4: host scoping excludes other hosts' events (only the untagged legacy event matches)"
  else
    no "AC-M4: host scoping returned '$m_other', expected only the untagged legacy event 'docker_run'"
  fi
  # Retry detection on an otherwise-green birth.
  if jq -e --arg re "$MSG_RE_T" --arg eh "$EH" "$HOSTDEF_WF
    [ .[] | select(((.message // .title) // \"\") | test(\$re)) | select($HOSTSEL_WF)
          | select([ (.tags // [])[]? | select(.key==\"stage\") | .value ][0] == \"doppler_retry\") ] | length > 0" < "$fx" >/dev/null 2>&1; then
    ok "AC-M5: the gate detects a doppler_retry breadcrumb (::warning:: on a green birth)"
  else
    no "AC-M5: the gate failed to detect the doppler_retry breadcrumb"
  fi
  rm -f "$fx"
  # AC-M5 above proves the FILTER SHAPE works, but it runs a copy written here — so it stays
  # green even if the workflow drops retry detection entirely. Pin the shipped wiring too:
  # the workflow must both SELECT doppler_retry and EMIT a ::warning:: for it, or a
  # retry-that-succeeded leaves its cause buried in a green run's collapsed summary.
  # Anchored on the SELECTOR construct, not the bare token: the token also appears in the two
  # operator-facing echo strings, so a presence-grep stays green against a selector neutered to
  # `select(false)` — detection dead, messages intact, nobody the wiser.
  # COUNT, not presence. There are two doppler_retry selectors — the RETRIED detector and the
  # RETRY_DETAIL capture — and a presence-grep is satisfied by either, so neutering one alone was
  # invisible. This is the "a second copy of a guarded literal disarms the guard" class, created
  # by this PR's own RETRY_DETAIL addition.
  retry_sel="$(grep -cF '.value ][0] == "doppler_retry"' "$TRAIL" || true)"
  if [ "$retry_sel" = 2 ]; then
    ok "AC-M7a: both doppler_retry selectors present (detector + RETRY_DETAIL capture)"
  else
    no "AC-M7a: expected 2 doppler_retry selectors in the workflow, found $retry_sel"
  fi
  if grep -qE '::warning::.*(RETRIED|doppler_retry)' "$TRAIL"; then
    ok "AC-M7b: a green birth that retried raises a ::warning:: annotation"
  else
    no "AC-M7b: no ::warning:: annotation fires for a retry on an otherwise-green birth"
  fi
  # AC-M7c: and it must carry the RETRY event's detail. LAST_DETAIL is [0] of the newest-first
  # list, which on this branch is cloud_init_complete (no per-stage file) — so interpolating it
  # renders "<none>" on every run, discarding the very cause the annotation exists to surface.
  if grep -E '::warning::.*RETRIED' "$TRAIL" | grep -qF '${RETRY_DETAIL'; then
    ok "AC-M7c: the retry warning interpolates RETRY_DETAIL (the retry event's own cause)"
  else
    no "AC-M7c: the retry warning must interpolate \${RETRY_DETAIL}, not the terminal event's detail"
  fi
  # The ::error:: ANNOTATION (not merely the job summary) must interpolate the detail — the
  # annotation is what renders at the top of the run page.
  if grep -qE '^\s*echo "::error::\$\{WEB_HOST_KEY\}.*booted DARK.*\$\{FATAL_DETAIL' "$TRAIL"; then
    ok "AC-M6: the dark-boot ::error:: annotation interpolates the captured detail"
  else
    no "AC-M6: the dark-boot ::error:: annotation must interpolate \${FATAL_DETAIL}"
  fi
  # ── AC-M8 (#6969 review): the RUN ANCHOR ──
  # host_name is soleur-<key> for BOTH a destroyed host and its replacement, and the query is
  # statsPeriod=1h with sort=-timestamp. Without a lower bound the first poll iteration reads
  # the PREDECESSOR's terminal event — a healthy predecessor yields TERMINAL=complete and a
  # GREEN run with the replacement's boot never verified, which is #6969's originating
  # incident re-created inside the mechanism built to prevent it. Pin the predicate AND its
  # application to every host-scoped selection: a def nothing calls is decoration.
  if grep -qF 'def sincok($s)' "$TRAIL"; then
    ok "AC-M8: the reader defines the run-anchor predicate"
  else
    no "AC-M8: the reader must define sincok(\$s) to discard events predating this run"
  fi
  hostsel=$({ grep -cF 'select(hostok($eh))' "$TRAIL" || true; })
  bothsel=$({ grep -cF 'select(hostok($eh)) | select(sincok($since))' "$TRAIL" || true; })
  if [ "$hostsel" -gt 0 ] && [ "$hostsel" -eq "$bothsel" ]; then
    ok "AC-M8: all ${hostsel} host-scoped selections also apply the run anchor"
  else
    no "AC-M8: ${bothsel} of ${hostsel} host-scoped selections apply sincok — an unanchored selection can read the predecessor's terminal event"
  fi
  # CALLER side: a perfect predicate is inert if nobody stamps the epoch.
  for prov_job in web_host_create web_host_replace; do
    PROV="$(awk -v want="^  ${prov_job}:" '/^  [A-Za-z0-9_-]+:/ { cap = ($0 ~ want) } /^  #/ { cap = 0 } cap' "$WF" || true)"
    if grep -qE '^[[:space:]]*run:[[:space:]]*printf .BOOT_TRAIL_SINCE=' <<<"$PROV"; then
      ok "AC-M8: ${prov_job} stamps BOOT_TRAIL_SINCE before its apply"
    else
      no "AC-M8: ${prov_job} must stamp BOOT_TRAIL_SINCE before apply, or its boot-trail read is unanchored"
    fi
  done

  # QUERY message literals stay byte-identical: renaming one darks the gate AND mints a new
  # Sentry issue group where value=1 means '>1', so a single fatal would stop paging entirely.
  if grep -qF 'QUERY='"'"'message:"soleur-hostscript-seed failed" OR message:"soleur-host-bootstrap failed" OR message:"soleur-host-bootstrap complete" OR message:"soleur-cloud-init boot stage"'"'" "$TRAIL"; then
    ok "AC-J2: the workflow QUERY message literals are byte-identical (lockstep held)"
  else
    no "AC-J2: the workflow QUERY message literals changed — this darks the gate and breaks paging"
  fi
fi

# ───────────────────────── (C) $HOME is defined for the CLI (#6981) ─────────────────────────
#
# soleur-web-2 booted dark TWICE at stage=doppler_download with "Doppler Error: $HOME is not
# defined". cloud-final.service runs runcmd as root and declares no `User=`; systemd synthesises
# $HOME only for units that DO declare one, so runcmd inherits HOME unset. The CLI resolves its
# home directory BEFORE reading DOPPLER_CONFIG_DIR, so the config dir cloud-init already sets is
# NOT a substitute (verified against the pinned 3.75.3).
#
# Every assertion here strips comments first: the production code this guards carries comments
# that discuss HOME at length, so a bare token match would be satisfied by prose alone
# (cq-assert-anchor-not-bare-token).

CI_CODE="$(grep -vE '^[[:space:]]*#' "$CI")"

if grep -qE '^[[:space:]]*export HOME=/root[[:space:]]*$' <<<"$CI_CODE"; then
  ok "AC-HOME1: runcmd exports HOME on a non-comment line"
else
  no "AC-HOME1: runcmd must 'export HOME=/root' — without it every doppler call dies 'Unable to determine home directory'"
fi

# ORDERING is load-bearing: an export placed after the first doppler call leaves that call broken
# while the grep above still passes.
home_ln=$(grep -nE '^[[:space:]]*export HOME=/root[[:space:]]*$' <<<"$CI_CODE" | head -1 | cut -d: -f1)
dop_ln=$(grep -nE 'doppler secrets|soleur-doppler-download' <<<"$CI_CODE" | head -1 | cut -d: -f1)
if [ -n "$home_ln" ] && [ -n "$dop_ln" ] && [ "$home_ln" -lt "$dop_ln" ]; then
  ok "AC-HOME2: the export precedes the first doppler invocation (line $home_ln < $dop_ln)"
else
  no "AC-HOME2: 'export HOME' must precede the first doppler call (export=${home_ln:-none} first-doppler=${dop_ln:-none})"
fi

# Second layer: the baked helper is on PATH and any caller may invoke it, so it must not depend
# on cloud-init having exported HOME first.
if grep -vE '^[[:space:]]*#' <<<"$HELPER" | grep -qF ': "${HOME:=/root}"'; then
  ok "AC-HOME3: the helper defaults HOME independently of its caller"
else
  no "AC-HOME3: soleur-doppler-download must default HOME (: \"\${HOME:=/root}\") — it is invocable outside runcmd"
fi

# The DELIBERATE omission, pinned so a future 'consistency' edit cannot silently break deploys:
# webhook.service declares User=deploy, so systemd already gives it the right per-user HOME.
# Writing HOME into its EnvironmentFile would override that with /root, which `deploy` cannot
# read and its own ProtectHome=read-only would not let it write.
if grep -E '^[[:space:]]*- printf .*> /etc/default/webhook-deploy' <<<"$CI_CODE" | grep -q 'HOME='; then
  no "AC-HOME4: /etc/default/webhook-deploy must NOT set HOME — it is webhook.service's EnvironmentFile (User=deploy), and /root would be unreadable to that user"
else
  ok "AC-HOME4: the webhook EnvironmentFile leaves HOME to systemd's per-user value"
fi

echo "=== doppler-download-error-channel: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
