#!/usr/bin/env bash
#
# #6604 — the /workspaces LUKS cutover body (ADR-119, epic #6588 PR 2).
#
# Migrates web-1's sole-copy user data from the LIVE plaintext ext4 /mnt/data onto the FRESH
# LUKS-encrypted volume (already +created + attached by apply_target=workspaces-luks-cutover), then
# re-points the mapper so /mnt/data (hardcoded into the app's `-v /mnt/data/workspaces:/workspaces`
# bind mount) becomes LUKS-backed with ZERO path changes. Copies the SHAPE of git-data-cutover.sh;
# it NEVER sources or invokes it (that script calls services defined nowhere — R3).
#
# ⚠️ DP-6 — HOST-SIDE recovery. This script runs ON web-1 over the workflow's CF-Tunnel SSH bridge,
# so `trap cleanup EXIT` is HOST-LOCAL and rolls back (unmount-mapper → remount-plaintext → restart)
# even if the CI SSH session dies mid-freeze (F3). Freeze state is persisted to a HOST FILE
# (/var/lib/workspaces-luks/state), not shell vars, so a deliberate reboot (C15) does not destroy
# the trap or the recovery state; the post-reboot re-canary is its OWN gated step reading that file
# (a pre-reboot CANARY_OK MUST NOT satisfy it — F5). A host-local dead-man timer auto-remounts
# plaintext if no orchestrator heartbeat lands within the window.
#
# ⚠️ R7/C3 — the escrow proof runs AFTER prepare_luks_target, against the REAL device via the host's
# prd_workspaces_luks token path (`doppler secrets get WORKSPACES_LUKS_KEY --plain --config
# prd_workspaces_luks`, R9 — NEVER `doppler run`/`download`, the CWE-522 hole). A throwaway-format
# proof passes for any string; only luksOpen --test-passphrase against the real header is real.
#
# ⚠️ C1 — the delta rsync verify is the ITEMIZED form (`-aHAXi … --dry-run --out-format='%i %n' |
# wc -l == 0`), caches dropped first (else you verify the page cache, not that bytes round-tripped
# through dm-crypt); NOT a rev-list identity (which passes while dropping the working-tree +
# refs/checkpoints/* data — R4).
#
# Observability: any failed at-rest assert exports the nine WL_* fields and calls
# workspaces-luks-emit.sh (feature=workspaces-luks / op=workspaces-luks-drift). Verdict is read from
# Sentry + the Better Stack heartbeat, NEVER by SSH-eyeballing (hr-no-ssh-fallback-in-runbooks).
set -uo pipefail

log()  { echo "[workspaces-cutover] $*"; }
step() { echo; echo "[workspaces-cutover] ===== $* ====="; }
die()  { echo "[workspaces-cutover] FATAL: $*" >&2; exit 1; }

# --- Configuration (overridable by the workflow; documented defaults) ---------
MOUNT="${WORKSPACES_MOUNT:-/mnt/data}"          # the live plaintext source AND the final LUKS mount
STAGING="${WORKSPACES_STAGING:-/mnt/data-luks}" # LUKS staging mount during the copy
MAPPER_NAME="${WORKSPACES_MAPPER_NAME:-workspaces}"
MAPPER="/dev/mapper/${MAPPER_NAME}"
CONTAINER="${WORKSPACES_CONTAINER:-soleur-web-platform}"
STATE_DIR="${WORKSPACES_STATE_DIR:-/var/lib/workspaces-luks}"
STATE_FILE="${STATE_DIR}/state"
# HEADER_BACKUP_BUCKET + the R2 S3 creds/endpoint are read host-side from prd_workspaces_luks
# (load_escrow_creds, below) — NOT passed via the workflow env / sudo argv (that would leak the
# creds into the host process list). The env override is kept only for the pre-merge stubbed test
# harness; production leaves it unset so the pinned Doppler read is authoritative (#6649).
HEADER_BACKUP_BUCKET="${WORKSPACES_HEADER_BUCKET:-}"  # MUST be distinct from the tfstate bucket (C4)
TFSTATE_BUCKET="${WORKSPACES_TFSTATE_BUCKET:-soleur-terraform-state}"  # the R2 backend bucket the header MUST NOT co-locate with (C4)
# SHA256-pinned aws-cli v2 — installed on-demand as root just before the freeze with $KEY in
# memory, so it is pinned exactly like CLOUDFLARED_SHA256. Digest computed from the versioned
# installer; bump AWSCLI_VERSION + AWSCLI_SHA256 together.
AWSCLI_VERSION="${WORKSPACES_AWSCLI_VERSION:-2.28.0}"
AWSCLI_SHA256="${WORKSPACES_AWSCLI_SHA256:-483e3c43b59255aef243bde90e9f09bb21cb9d1dd5e20f985212d708e510b97c}"
DEAD_MAN_MIN="${WORKSPACES_DEAD_MAN_MIN:-30}"
DRY_RUN="${DRY_RUN:-1}"
ROLLBACK="${ROLLBACK:-0}"
CONFIRM_WIPE="${CONFIRM_WIPE:-0}"

# Locate sibling scripts relative to THIS file. The workflow ships this script + its siblings
# (workspaces-luks-emit.sh, luks-monitor.{sh,service,timer}) as a tar bundle and runs THIS file as a
# file (#6649 content-carrier model), so the self-path is the on-host file path. The `:-$0` fallback
# keeps it defined under `set -u` even if the body ever arrives on stdin (`bash -s`), where
# BASH_SOURCE is empty — the pre-#6649 failure that darkened the emit channel + killed the run.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
EMIT="/usr/local/bin/workspaces-luks-emit.sh"
[ -f "$EMIT" ] || EMIT="${SELF_DIR}/workspaces-luks-emit.sh"
# shellcheck source=apps/web-platform/infra/workspaces-luks-emit.sh
[ -f "$EMIT" ] && . "$EMIT"

# The passphrase is read ONLY via the pinned scoped-config form (R9) — never doppler run/download.
read_key() { doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks 2>/dev/null || true; }

# The R2 escrow delivery (bucket name, S3 creds, endpoint) is read host-side via the SAME pinned
# scoped-config form as the passphrase (R9) — never argv, never doppler run/download (the CWE-522
# hole). `|| true` mirrors read_key; the fail-loud [ -n ] check is at the call site so a
# half-populated cred pair dies BEFORE aws, not as a confusing mid-freeze SigV4 error.
read_header_bucket()   { doppler secrets get WORKSPACES_HEADER_BUCKET --plain --config prd_workspaces_luks 2>/dev/null || true; }
read_header_key_id()   { doppler secrets get WORKSPACES_HEADER_R2_ACCESS_KEY_ID --plain --config prd_workspaces_luks 2>/dev/null || true; }
read_header_secret()   { doppler secrets get WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY --plain --config prd_workspaces_luks 2>/dev/null || true; }
read_header_endpoint() { doppler secrets get WORKSPACES_HEADER_R2_ENDPOINT --plain --config prd_workspaces_luks 2>/dev/null || true; }

# ensure_aws — web-1 carries lifecycle{ ignore_changes = [user_data] } and is unrebuildable, so
# cloud-init cannot deliver `aws` to the RUNNING host; this on-demand install IS the real delivery
# (the cloud-init addition covers FUTURE hosts only). SHA256-pinned (root + $KEY in memory).
# Idempotent: a present aws short-circuits.
# OPERATOR NOTE: this runs in BOTH arms (it precedes escrow_probe, which is outside the DRY_RUN gate),
# so a `dry_run=true` rehearsal is NOT host-side-effect-free the FIRST time — it may apt-get/curl/
# install aws-cli on web-1 (additive, no service restart; user-impact review). Subsequent runs no-op.
ensure_aws() {
  if command -v aws >/dev/null 2>&1; then return 0; fi
  log "aws CLI absent — installing pinned aws-cli v${AWSCLI_VERSION} (SHA256 verified)"
  command -v unzip >/dev/null 2>&1 || { apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq unzip >/dev/null 2>&1; } \
    || { emit_drift aws_unzip_missing; die "unzip unavailable and could not be installed — cannot unpack aws-cli"; }
  local tmp z; tmp="$(mktemp -d)"; z="${tmp}/awscliv2.zip"
  if ! curl -fsSL -o "$z" "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip"; then
    rm -rf "$tmp"; emit_drift aws_download_failed; die "aws-cli download failed — cannot escrow the header (C4)"
  fi
  echo "${AWSCLI_SHA256}  ${z}" | sha256sum -c - >/dev/null 2>&1 \
    || { rm -rf "$tmp"; emit_drift aws_cli_sha_mismatch; die "aws-cli SHA256 mismatch (expected ${AWSCLI_SHA256}) — refusing to run an unverified installer as root before the freeze (possible installer tampering)"; }
  ( cd "$tmp" && unzip -q "$z" && ./aws/install --update >/dev/null 2>&1 ) \
    || { rm -rf "$tmp"; emit_drift aws_install_failed; die "aws-cli install failed"; }
  rm -rf "$tmp"
  command -v aws >/dev/null 2>&1 || { emit_drift aws_still_absent; die "aws CLI still absent after install (C4)"; }
}

# load_escrow_creds — populate HEADER_BACKUP_BUCKET + export the R2 S3 env for aws, with per-field
# fail-loud. R2 rejects aws-cli>=2.23's default CRC32 checksums, so pin the checksum env to
# when_required (the known R2 breakage — a vendor-behavior fact, not derived).
load_escrow_creds() {
  HEADER_BACKUP_BUCKET="$(read_header_bucket)"
  local kid sec ep
  kid="$(read_header_key_id)"; sec="$(read_header_secret)"; ep="$(read_header_endpoint)"
  [ -n "$HEADER_BACKUP_BUCKET" ] || { emit_drift header_bucket_unreadable; die "WORKSPACES_HEADER_BUCKET unreadable from prd_workspaces_luks — refusing to proceed without an off-host header bucket DISTINCT from tfstate (C4)"; }
  [ -n "$kid" ] || { emit_drift header_key_id_unreadable; die "WORKSPACES_HEADER_R2_ACCESS_KEY_ID unreadable from prd_workspaces_luks (C4)"; }
  [ -n "$sec" ] || { emit_drift header_secret_unreadable; die "WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY unreadable from prd_workspaces_luks (C4)"; }
  [ -n "$ep" ] || { emit_drift header_endpoint_unreadable; die "WORKSPACES_HEADER_R2_ENDPOINT unreadable from prd_workspaces_luks (C4)"; }
  [ "$HEADER_BACKUP_BUCKET" != "$TFSTATE_BUCKET" ] || { emit_drift header_bucket_equals_tfstate; die "WORKSPACES_HEADER_BUCKET ($HEADER_BACKUP_BUCKET) equals the tfstate bucket — the header MUST live in a DISTINCT blast radius (C4)"; }
  export AWS_ACCESS_KEY_ID="$kid"
  export AWS_SECRET_ACCESS_KEY="$sec"
  export AWS_DEFAULT_REGION=auto
  export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
  export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
  HEADER_R2_ENDPOINT="$ep"
}

# escrow_probe — DRY_RUN-safe reachability+auth+writability probe. Runs in BOTH arms (OUTSIDE the
# `DRY_RUN != 1` gate) so a GREEN signal lands during the rehearsal, before any irreversible freeze.
# (1) probe-PUT (write→read-back→delete of a namespaced .probe/<run-id> key): a read-only head-bucket
#     would false-green an Object-Read-only token that then dies at the real PUT.
# (2) NEGATIVE probe: the SAME creds MUST be DENIED against soleur-terraform-state — a success proves
#     an over-scoped account-wide token (the name-compare below cannot catch over-scoping).
escrow_probe() {
  local run_id probe_key probe_body neg_err neg_rc
  run_id="${GITHUB_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
  probe_key=".probe/${run_id}"
  probe_body="$(mktemp)"; printf 'workspaces-luks-escrow-probe %s\n' "$run_id" > "$probe_body"
  if ! aws s3 cp "$probe_body" "s3://${HEADER_BACKUP_BUCKET}/${probe_key}" --endpoint-url "$HEADER_R2_ENDPOINT" >/dev/null 2>&1; then
    rm -f "$probe_body"; emit_drift escrow_probe_put_failed; die "escrow probe-PUT to $HEADER_BACKUP_BUCKET failed — creds/endpoint/writability not proven; aborting BEFORE the freeze (C4)"
  fi
  aws s3api head-object --bucket "$HEADER_BACKUP_BUCKET" --key "$probe_key" --endpoint-url "$HEADER_R2_ENDPOINT" >/dev/null 2>&1 \
    || { aws s3 rm "s3://${HEADER_BACKUP_BUCKET}/${probe_key}" --endpoint-url "$HEADER_R2_ENDPOINT" >/dev/null 2>&1 || true; rm -f "$probe_body"; emit_drift escrow_probe_readback_failed; die "escrow probe read-back failed — object not durable; aborting BEFORE the freeze (C4)"; }
  aws s3 rm "s3://${HEADER_BACKUP_BUCKET}/${probe_key}" --endpoint-url "$HEADER_R2_ENDPOINT" >/dev/null 2>&1 || true
  # NEGATIVE probe: the escrow creds MUST be DENIED against the tfstate bucket (the passphrase-bearing
  # state bucket). rc==0 (200) ⇒ over-scoped account-wide token ⇒ die. This is the SOLE runtime guard
  # against over-scope (the name-compare cannot catch it), so fail CLOSED: a non-zero exit is proof of
  # denial ONLY when it is an AUTH error (403/401/404) — a transport/network error is NOT proof and
  # must not be read as "safe" (security P2). A bucket-scoped R2 token gets 403 (or 404) here.
  neg_err="$(aws s3api head-bucket --bucket "$TFSTATE_BUCKET" --endpoint-url "$HEADER_R2_ENDPOINT" 2>&1)"; neg_rc=$?
  if [ "$neg_rc" -eq 0 ]; then
    rm -f "$probe_body"; emit_drift escrow_creds_overscoped; die "escrow creds are NOT bucket-scoped — they can reach $TFSTATE_BUCKET (the passphrase-bearing state bucket); refusing to proceed (C4/security)"
  elif ! grep -Eq '\b(403|401|404)\b|Forbidden|AccessDenied|Not Found|NoSuchBucket' <<<"$neg_err"; then
    # herestring, not `printf … | grep -q`: under `set -o pipefail` grep -q closes the pipe on the
    # first match and SIGPIPEs the producer → a false non-match (this branch's own SIGPIPE learning,
    # 2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md). The raw $neg_err tail is
    # credential-free here BY CONSTRUCTION: any auth error carrying a key-id shape is a 403/401/404 →
    # caught above and routed to the deny branch, so only non-auth (network/DNS/TLS) text reaches here.
    rm -f "$probe_body"; emit_drift escrow_negprobe_inconclusive; die "over-scope negative probe INCONCLUSIVE against $TFSTATE_BUCKET (non-auth error: $(tail -1 <<<"$neg_err")) — refusing to proceed on an unproven denial (C4/security)"
  fi
  rm -f "$probe_body"
  log "escrow probe OK — PUT/read-back/delete on $HEADER_BACKUP_BUCKET green; creds DENIED against $TFSTATE_BUCKET (bucket-scoped)"
}

# --- Persisted recovery state (survives a reboot; read by the EXIT trap) ------
persist_state() { mkdir -p "$STATE_DIR"; printf '%s=%s\n' "$1" "$2" >> "$STATE_FILE"; }
read_state()    { [ -f "$STATE_FILE" ] && (grep -E "^$1=" "$STATE_FILE" | tail -1 | cut -d= -f2-) || echo ""; }
FREEZE_HELD=0
FLIP_DONE=0
CANARY_OK=0

# Emit a discriminating drift event (any failed at-rest assert routes here).
emit_drift() {
  WL_REASON="$1"; export WL_REASON
  if command -v workspaces_luks_emit >/dev/null 2>&1; then WL_LEVEL=fatal workspaces_luks_emit;
  else echo "[workspaces-cutover] DRIFT reason=$1 (workspaces_luks_emit unavailable — Sentry channel not reached; workflow-run log is the only sink)" >&2; fi
}

# --- C1 byte-identity verify (itemized rsync) + its diagnostic emitter --------
# Two defects were fixed here vs the pre-#6604-followup inline form (run 29676585829/29676994044 —
# the first real cutover safe-aborted on "1 difference" that the operator could not identify):
#   (1) the verify rsync's stdout (the `%i %n` itemize lines) and stderr (rsync warnings/errors) are
#       captured SEPARATELY, so a benign stderr warning ("file has vanished") can no longer inflate
#       the diff count (the old `>"$vlog" 2>&1` folded them into one file);
#   (2) on a non-zero count OR a verify-rsync error the offending path(s)+code(s) are LOGGED — to the
#       run log AND Better Stack (via the already-allowlisted `luks-monitor` tag, op=
#       workspaces-luks-verify-diff) — BEFORE the temp files are removed and BEFORE die(), so the next
#       operator-approved real cutover self-reports exactly which path aborted it, no SSH.
# The gate is UNCHANGED: still 0 real content diffs, still fail-closed if the verify rsync errors, and
# NO itemize code is narrowed away (attribute-only .f..t/.d..t diffs still count).
VERIFY_DIFF_CAP="${WORKSPACES_VERIFY_DIFF_CAP:-40}"
LUKS_LOG_TAG="${WORKSPACES_LUKS_LOG_TAG:-luks-monitor}"   # real assignment; own-line `logger -t "$LUKS_LOG_TAG"` below (emitter-extractor convention, luks-monitor.sh shape)
# Strip CR/LF + non-printable so a crafted workspace filename cannot inject a spurious log/marker line.
_vscrub() { printf '%s' "${1:-}" | tr -d '\r\n' | tr -cd '[:print:]'; }

# Emit the itemized-diff diagnostic. MUST run BEFORE any rm of $vout/$verr and BEFORE die (defect 2
# is precisely "rm before log"). $1=count(int) $2=vout-file $3=verr-file $4=reason
emit_verify_diff() {
  local count="$1" vout="$2" reason="$4" k=0 line icode path summary row
  log "C1 verify FAILED ($reason): ${count} difference(s). Itemized (capped ${VERIFY_DIFF_CAP}):"
  # Human view -> run log.
  head -n "$VERIFY_DIFF_CAP" "$vout" 2>/dev/null | while IFS= read -r line; do log "  DIFF $(_vscrub "$line")"; done
  [ "$count" -gt "$VERIFY_DIFF_CAP" ] 2>/dev/null && log "  … +$((count - VERIFY_DIFF_CAP)) more"
  # Structured marker -> Better Stack (logger -t luks-monitor) AND run log (echo). Summary first.
  summary="SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF feature=workspaces-luks op=workspaces-luks-verify-diff count=${count} reason=$(_vscrub "$reason") host=$(hostname 2>/dev/null)"
  echo "$summary"; logger -t "$LUKS_LOG_TAG" -- "$summary" 2>/dev/null || true
  # Per-diff rows (one path each, path LAST so a spaced path is captured whole).
  while IFS= read -r line && [ "$k" -lt "$VERIFY_DIFF_CAP" ]; do
    icode="$(_vscrub "${line%% *}")"; path="$(_vscrub "${line#* }")"
    row="SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF feature=workspaces-luks op=workspaces-luks-verify-diff count=${count} idx=${k} icode=${icode} path=${path}"
    echo "$row"; logger -t "$LUKS_LOG_TAG" -- "$row" 2>/dev/null || true
    k=$((k + 1))
  done < "$vout"
  # Sentry page via the existing at-rest channel (op=workspaces-luks-drift), discriminating reason.
  emit_drift "workspaces_luks_${reason}"
}

# The C1 verify. Call DIRECTLY (never in $(…)/a pipe/a subshell) in the main body so die's `exit 1`
# reaches the EXIT trap -> rollback (a subshell would swallow it). $1=src $2=dst
verify_byte_identity() {
  local src="$1" dst="$2" vout verr rc diff_n err_tail
  vout="$(mktemp)"; verr="$(mktemp)"
  # --dry-run HARDCODED (one typo from `rsync --delete` wiping live data). Itemize -> stdout; rsync's
  # own warnings/errors -> stderr. Separate streams: stderr can no longer inflate the diff count.
  rsync -aHAXi --numeric-ids --checksum --delete --dry-run --out-format='%i %n' "$src"/ "$dst"/ >"$vout" 2>"$verr"
  rc=$?
  # Fail-closed PRESERVED: a verify rsync that ERRORS cannot certify DST==SRC. Capture its stderr tail
  # into a var BEFORE rm (die "$(tail "$verr")" after rm would print nothing).
  if [ "$rc" -ne 0 ]; then
    err_tail="$(tail -n 3 "$verr" 2>/dev/null | tr '\n' ' ')"
    # count=0: a verify-rsync ERROR has no diff count (vout is empty). The rc + stderr are surfaced in
    # the die message below; passing "0" avoids the marker mislabelling the rsync exit code as a diff
    # count (and avoids a nonsensical "+N more" when rc > VERIFY_DIFF_CAP).
    emit_verify_diff 0 "$vout" "$verr" verify_rsync_error       # log BEFORE rm + die
    rm -f "$vout" "$verr"
    die "the itemized verify rsync itself FAILED (rc=${rc}) to run to completion — cannot certify DST==SRC (C1); stderr: ${err_tail}"
  fi
  # Count ONLY itemize-shaped stdout lines: first char in <>ch.* , second in fdLDS (attribute-only
  # lines start '.', e.g. .f..t…/.d..t…), plus the `*deleting` form. Counts EVERY code (no narrowing);
  # blank lines and any stray stderr are excluded by construction.
  diff_n="$(grep -cE '^(\*deleting|[<>ch.*][fdLDS])' "$vout" || true)"
  if [ "$diff_n" -ne 0 ]; then
    emit_verify_diff "$diff_n" "$vout" "$verr" verify_byte_diff  # log BEFORE rm + die
    rm -f "$vout" "$verr"
    die "itemized rsync verify found ${diff_n} difference(s) — DST is not byte-identical to SRC (C1); see the SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF marker for the offending path(s)+code(s)"
  fi
  rm -f "$vout" "$verr"
}

# --- Freeze / resume writer quiesce (#6588) ----------------------------------
# QUIESCE_UNITS — every systemd unit that writes $MOUNT and MUST be stopped for the freeze.
#
# inngest-redis.service is the one this constant exists for. It persists its AOF to /mnt/data/redis
# (inngest-redis.conf `dir /mnt/data/redis`, `appendonly yes`) and is a systemd UNIT, not a
# container — so the pre-#6588 freeze (`systemctl stop webhook.service` + `docker stop $CONTAINER`)
# never touched it and Redis appended straight through the freeze, the pass-2 delta rsync AND the
# C1 verify. That is what safe-aborted the first two REAL freezes on 2026-07-19, both on exactly one
# difference: `icode=>fcst...... path=redis/appendonlydir/appendonly.aof.94.incr.aof` (checksum +
# size + mtime — a live-appending file). The C1 gate was RIGHT; the writer was not quiesced.
#
# inngest-server.service is deliberately ABSENT: its unit is ProtectSystem=strict with
# ReadWritePaths=/var/lib/inngest /var/lock, so it provably cannot write $MOUNT (and can never
# appear in `lsof +D`), while TimeoutStopSec=180 means stopping it could burn 3 minutes of a
# ~10-minute freeze for zero quiescence benefit. Its residual risk (a crash-loop into `failed`
# during the redis outage window) is covered by the post-freeze reconcile in resume_writers() at
# zero freeze cost. See ADR-119 Addendum 2026-07-19.
QUIESCE_UNITS="${WORKSPACES_QUIESCE_UNITS:-webhook.service inngest-redis.service}"
FREEZE_HOLDER_CAP="${WORKSPACES_FREEZE_HOLDER_CAP:-40}"

# ensure_lsof — G4 is fail-CLOSED, so `lsof` must exist. Mirrors ensure_aws (idempotent, installs
# on demand). `lsof` is provisioned by no repo artifact on the RUNNING host (web-1 carries
# lifecycle{ ignore_changes = [user_data] }), so the cloud-init addition covers FUTURE hosts only
# and this IS the real delivery.
# OPERATOR NOTE: like ensure_aws, this runs in BOTH arms, so a `dry_run=true` rehearsal is NOT
# host-side-effect-free the FIRST time — it may apt-get install lsof (additive, no service restart).
ensure_lsof() {
  if command -v lsof >/dev/null 2>&1; then return 0; fi
  log "lsof absent — installing (G4 is fail-closed; it must never be skipped)"
  { apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq lsof >/dev/null 2>&1; } || true
  command -v lsof >/dev/null 2>&1 || {
    emit_drift lsof_unavailable
    die "lsof unavailable and could not be installed — the G4 straggler assert cannot run. Refusing to freeze on a mount whose quiescence is unproven: a gate that silently evaporates when a binary is absent is exactly how an unquiesced writer reached two real freezes (#6588)."
  }
}

# emit_freeze_holders — log the processes still holding $MOUNT to the run log AND Better Stack
# BEFORE die(), so a G4 abort is diagnosable with no SSH. Mirrors emit_verify_diff (the #6604 fix
# for the same defect class on C1): evidence must outlive the abort that produced it.
emit_freeze_holders() {
  local holders="$1" n k line summary row
  n="$(printf '%s\n' "$holders" | grep -c . || true)"
  log "G4 straggler assert FAILED: ${n} line(s) still hold $MOUNT. Capped ${FREEZE_HOLDER_CAP}:"
  summary="SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER feature=workspaces-luks op=workspaces-luks-freeze-holder count=${n} mount=$(_vscrub "$MOUNT") host=$(hostname 2>/dev/null)"
  log "$summary"; logger -t "$LUKS_LOG_TAG" -- "$summary" 2>/dev/null || true
  k=0
  while IFS= read -r line && [ "$k" -lt "$FREEZE_HOLDER_CAP" ]; do
    [ -n "$line" ] || continue
    row="SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER feature=workspaces-luks op=workspaces-luks-freeze-holder count=${n} idx=${k} holder=$(_vscrub "$line")"
    log "$row"; logger -t "$LUKS_LOG_TAG" -- "$row" 2>/dev/null || true
    k=$((k + 1))
  done <<<"$holders"
  [ "$n" -gt "$FREEZE_HOLDER_CAP" ] 2>/dev/null && log "  … +$((n - FREEZE_HOLDER_CAP)) more"
  emit_drift freeze_straggler_holds_mount
}

# freeze_writers — quiesce every $MOUNT writer, assert no interrupted writes, then assert (G4) that
# nothing still holds the mount. Extracted above the sourced-detection guard so it is testable
# (workspaces-luks-freeze.test.sh); the pre-#6588 inline block sat below the guard and could only be
# checked by static grep, which cannot catch ordering or exit-status defects.
freeze_writers() {
  # Order: webhook FIRST (so a CI deploy cannot restart the container mid-rsync), then the
  # container, then the remaining units. resume_writers() reverses this.
  systemctl stop webhook.service
  docker stop -t 120 "$CONTAINER"   # C8: drain lets in-flight write() finish (a 10s SIGKILL truncates)
  local u
  for u in $QUIESCE_UNITS; do
    [ "$u" = "webhook.service" ] && continue
    systemctl stop "$u"
  done
  # luks-monitor.timer is armed by a PRIOR successful cutover and is RequiresMountsFor=/mnt/data, so
  # on a RE-dispatch it can fire mid-freeze and hold $MOUNT — which the now fail-closed G4 would
  # abort on. Best-effort: absent on a first cutover. Restored by resume_writers().
  systemctl stop luks-monitor.timer 2>/dev/null || true
  persist_state QUIESCED_UNITS "$QUIESCE_UNITS"

  # Interrupted-write asserts — abort rather than faithfully copy wreckage. The .git-specific checks
  # stay scoped to workspaces/*/; everything else is swept by G4 below (which covers the WHOLE mount,
  # not just workspaces/ — /mnt/data/redis is a SIBLING of workspaces/, so it was unguarded on every
  # axis before #6588).
  local ws
  for ws in "$MOUNT"/workspaces/*/; do
    [ -d "$ws" ] || continue
    [ -e "$ws/.git/index.lock" ] && die "index.lock present in $ws — a write was interrupted; aborting (C8)"
    ls "$ws"/.git/objects/pack/tmp_pack_* >/dev/null 2>&1 && die "tmp_pack_* present in $ws — interrupted pack; aborting"
    [ -e "$ws/.git/gc.pid" ] && die "gc.pid present in $ws — interrupted gc; aborting"
  done

  # G4 — no process is still touching the mount. THREE properties, each load-bearing:
  #  (a) fail-CLOSED on a missing lsof (ensure_lsof dies rather than skipping). The pre-#6588 form
  #      wrapped the whole assert in `command -v lsof && …`, so on a host without lsof the gate
  #      silently vanished — false assurance, and precisely the silent-failure anti-pattern
  #      (cq-silent-fallback-must-mirror-to-sentry).
  #  (b) NO pipe. `lsof +D "$MOUNT" | grep -q .` under `set -o pipefail` returns 141 when grep closes
  #      the pipe on an early match and the producer takes SIGPIPE — so `&& die` never fires. That is
  #      a SIZE-DEPENDENT fail-OPEN: the gate evaporates exactly when there are many stragglers.
  #      Same trap the escrow negative-probe already documents at the herestring above.
  #  (c) holders are EMITTED before die(), so the next abort self-reports (the #6604 defect class).
  ensure_lsof
  local holders
  holders="$(lsof +D "$MOUNT" 2>/dev/null || true)"
  if [ -n "$holders" ]; then
    emit_freeze_holders "$holders"
    die "lsof +D $MOUNT non-empty — a straggler still holds the mount (G4); see the SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER marker for the offending process(es)"
  fi
}

# resume_writers — restore everything freeze_writers() quiesced. Called on ALL THREE exit paths
# (success, rollback, and the dead-man's inline command carries the equivalent), so a run leaves the
# host exactly as it found it whether it succeeds, safe-aborts, or dies unattended.
#
# MUST run AFTER the mount: every quiesced unit is RequiresMountsFor=/mnt/data, so a start that
# races the remount leaves the unit `failed` — which silently OUTLIVES the run and is strictly worse
# than leaving it stopped. Hence the reset-failed before each start.
resume_writers() {
  local u rev=""
  for u in $QUIESCE_UNITS; do rev="$u${rev:+ }$rev"; done   # reverse: webhook comes back LAST
  for u in $rev; do
    systemctl reset-failed "$u" 2>/dev/null || true
    systemctl start "$u" 2>/dev/null || true
    systemctl is-active --quiet "$u" 2>/dev/null || {
      emit_drift quiesced_unit_not_active
      log "WARN: $u is not active after resume — the freeze left it down"
    }
  done
  # inngest-server reconcile — never STOPPED by the freeze (it cannot write $MOUNT), but the redis
  # outage window can crash-loop it into `failed`, which outlives the run. Zero freeze cost: this
  # runs after the mount is back. Only start it if it is not already active (no redundant restart).
  systemctl reset-failed inngest-server.service 2>/dev/null || true
  systemctl is-active --quiet inngest-server.service 2>/dev/null || {
    systemctl start inngest-server.service 2>/dev/null || true
    systemctl is-active --quiet inngest-server.service 2>/dev/null || emit_drift inngest_server_not_active
  }
  systemctl start luks-monitor.timer 2>/dev/null || true
}

# app_canary — the post-restart application probe.
# /health, NOT /api/health: middleware.ts exempts `/health` (the `pathname === "/health"` early
# return) and there is no /api/health route at all, so /api/health 307-redirects to /login. The
# pre-#6588 canary asserted == 200 without following redirects, so it would have aborted EVERY
# otherwise-successful cutover at the very last gate — after the mount was already repointed.
app_canary() {
  local health
  health="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 https://app.soleur.ai/health || echo 000)"
  [ "$health" = "200" ] || die "app /health=$health (expected 200) after restart"
}

# Host-local rollback: unmount the mapper, remount the RETAINED plaintext volume at $MOUNT, restart.
# Reconcilable, not a one-way door (C13): the LUKS volume RETAINS post-cutover writes.
# shellcheck disable=SC2317  # invoked indirectly via the EXIT trap / ROLLBACK mode
rollback() {
  step "ROLLBACK — remount the retained plaintext at $MOUNT + restart"
  [ "$DRY_RUN" = "1" ] && { log "(dry-run) would rollback"; return 0; }
  systemctl stop webhook.service 2>/dev/null || true
  docker stop -t 30 "$CONTAINER" 2>/dev/null || true
  umount "$MOUNT" 2>/dev/null || true
  cryptsetup close "$MAPPER_NAME" 2>/dev/null || true
  # Remount the retained plaintext volume (its by-label / by-id device — never the mapper).
  mount /dev/disk/by-label/workspaces_plain "$MOUNT" 2>/dev/null \
    || mount "$(read_state PLAINTEXT_DEV)" "$MOUNT" 2>/dev/null || true
  docker start "$CONTAINER" 2>/dev/null || true
  # AFTER the remount (RequiresMountsFor) — restores webhook + inngest-redis + reconciles
  # inngest-server, so a safe-abort does not silently leave the durable Inngest queue down.
  resume_writers
  emit_drift rollback_engaged
}

# shellcheck disable=SC2317  # invoked indirectly via the EXIT trap
cleanup() {
  local rc=$?
  trap - EXIT
  if [ "$rc" -eq 0 ]; then exit 0; fi
  log "ABORT (rc=$rc) — host-local auto-recovery"
  # ONE rollback: fire iff we hold the freeze or completed the flip AND the canary has
  # not yet passed (post-canary the LUKS mount is authoritative and retains writes — do
  # not tear it down). Single condition avoids the double stop/umount/remount flap.
  if [ "$CANARY_OK" != "1" ] && { [ "$FLIP_DONE" = "1" ] || [ "$FREEZE_HELD" = "1" ]; }; then
    rollback
  fi
  exit "$rc"
}

# Sourced-detection guard: when this file is `source`d (the workspaces-luks-verify.test.sh harness
# obtains verify_byte_identity/emit_verify_diff without running the cutover), return HERE — after all
# functions the test needs are defined, but BEFORE `trap cleanup EXIT` and the main body. An executed
# run (`bash …/workspaces-cutover.sh`, BASH_SOURCE[0]==$0) evaluates this as a no-op and proceeds.
if [ "${BASH_SOURCE[0]:-$0}" != "$0" ]; then return 0 2>/dev/null || true; fi

trap cleanup EXIT

# Arm a host-local dead-man timer: if the orchestrator does not clear it within DEAD_MAN_MIN,
# systemd-run auto-remounts plaintext + restarts (closes "frozen-and-SSH-unreachable", F3).
arm_dead_man() {
  [ "$DRY_RUN" = "1" ] && return 0
  # SELF-CONTAINED inline command — do NOT reference an external binary (an earlier draft
  # pointed at /usr/local/bin/workspaces-cutover-rollback, which this PR never installs, so
  # the transient unit would fail and no remount would happen — defeating the whole backstop).
  # Reads $STATE_FILE for the retained plaintext device and remounts it over $MOUNT, then restarts
  # the container AND every unit freeze_writers() quiesced (webhook + inngest-redis), reconciling
  # inngest-server and re-arming luks-monitor.timer. #6588: this is the THIRD restore site and the
  # only UNATTENDED one — omitting inngest-redis here leaves the durable Inngest queue down with no
  # operator signal, which is the failure nobody would see. Keep this command in lockstep with
  # resume_writers(); it must stay self-contained (no external binary).
  # Runs even if the SSH session (and this script) is long gone.
  local dev
  dev="$(read_state PLAINTEXT_DEV)"
  systemd-run --on-active="${DEAD_MAN_MIN}min" --unit=workspaces-luks-deadman \
    /bin/sh -c "systemctl stop webhook.service 2>/dev/null; systemctl stop inngest-redis.service 2>/dev/null; docker stop -t 30 ${CONTAINER} 2>/dev/null; umount ${MOUNT} 2>/dev/null; cryptsetup close ${MAPPER_NAME} 2>/dev/null; mount ${dev:-/dev/disk/by-label/workspaces_plain} ${MOUNT} && docker start ${CONTAINER} 2>/dev/null; systemctl reset-failed inngest-redis.service 2>/dev/null; systemctl start inngest-redis.service 2>/dev/null; systemctl reset-failed inngest-server.service 2>/dev/null; systemctl start inngest-server.service 2>/dev/null; systemctl start webhook.service 2>/dev/null; systemctl start luks-monitor.timer 2>/dev/null" \
    2>/dev/null || true
}
disarm_dead_man() {
  systemctl stop workspaces-luks-deadman.timer 2>/dev/null || true
  systemctl reset-failed workspaces-luks-deadman 2>/dev/null || true
}

# ============================================================================
# ROLLBACK mode — operator recovery entrypoint
# ============================================================================
if [ "$ROLLBACK" = "1" ]; then
  DRY_RUN=0 rollback
  exit 0
fi

# ============================================================================
# L3 pre-freeze gates (Hypotheses 1-2) — abort BEFORE any freeze
# ============================================================================
step "L3 gates — host reachability + mount preconditions (pre-freeze, zero downtime)"
mountpoint -q "$MOUNT" || die "L3: $MOUNT is not mounted — the data is not where the cutover assumes (Phase 0 STOP + Hetzner rescue crypttab/fstab repair, DP-9 F1)"
[ -b "$(findmnt -no SOURCE "$MOUNT" 2>/dev/null)" ] || log "WARN: $MOUNT source is not a block device"

# ============================================================================
# prepare_luks_target — select the FRESH device by volume ID, format-if-raw, open the mapper
# ============================================================================
step "prepare LUKS target: select fresh device by volume ID, blkid discriminator, open mapper"
KEY="$(read_key)"
if [ -z "$KEY" ]; then WL_DOPPLER_REACHABLE=false; export WL_DOPPLER_REACHABLE; emit_drift doppler_unreachable; die "empty WORKSPACES_LUKS_KEY — refusing to proceed unencrypted (NFR-026)"; fi
# The fresh LUKS volume is the ATTACHED block device that is NOT the current /mnt/data source. Select
# it by its Hetzner volume-ID by-id path (passed as WORKSPACES_LUKS_DEV), never a bare glob — the glob
# matches the LIVE plaintext volume too (the ambiguity Phase 1 pins).
FRESH_DEV="${WORKSPACES_LUKS_DEV:-}"
[ -n "$FRESH_DEV" ] && [ -e "$FRESH_DEV" ] || die "WORKSPACES_LUKS_DEV unset or absent — pass the fresh volume by-id device"
raw_type="$(blkid -s TYPE -o value "$FRESH_DEV" 2>/dev/null || true)"
if [ -z "$raw_type" ]; then
  log "fresh device is RAW (no signature) — luksFormat"
  [ "$DRY_RUN" = "1" ] || printf '%s' "$KEY" | cryptsetup luksFormat --type luks2 --key-file - "$FRESH_DEV"
elif [ "$raw_type" = "crypto_LUKS" ]; then
  log "fresh device already crypto_LUKS — no format (idempotent)"
else
  die "fresh device carries TYPE=$raw_type (expected raw or crypto_LUKS) — refusing to format a device with a filesystem signature (C7)"
fi
if [ "$DRY_RUN" != "1" ] && [ ! -e "$MAPPER" ]; then
  printf '%s' "$KEY" | cryptsetup luksOpen --key-file - "$FRESH_DEV" "$MAPPER_NAME"
fi
mkdir -p "$STAGING"
[ "$DRY_RUN" = "1" ] || { mountpoint -q "$STAGING" || mount "$MAPPER" "$STAGING"; }

# ============================================================================
# Escrow proof (BLOCKING, AFTER prepare — R7/C3) — against the REAL device via the host token path
# ============================================================================
step "escrow proof: luksOpen --test-passphrase against the REAL device (host token path)"

# Load the R2 escrow creds host-side (fail-loud) + ensure the S3 client, then run the DRY_RUN-safe
# reachability probe — in BOTH arms (OUTSIDE the DRY_RUN != 1 gate below), so the rehearsal proves
# the escrow path is usable BEFORE any irreversible freeze. This is what kills the false-green where
# a green dry-run hid an unusable escrow (the gap #6649 fixes).
ensure_aws
load_escrow_creds
escrow_probe

if [ "$DRY_RUN" != "1" ]; then
  if printf '%s' "$KEY" | cryptsetup luksOpen --test-passphrase --key-file - "$FRESH_DEV" >/dev/null 2>&1; then
    log "escrow OK — the host-token passphrase unlocks the real device"
  else
    WL_LUKS_OPEN_RESULT=fail; export WL_LUKS_OPEN_RESULT; emit_drift escrow_passphrase_mismatch
    die "escrow proof FAILED — the passphrase does not unlock the real device (F4 — unreadable-forever risk); aborting BEFORE the freeze"
  fi
  # C4 — the LUKS header is an independent terminal limb: back it up to a bucket DISTINCT from the
  # tfstate bucket, then assert the backup's UUID matches the live header. Distinctness is ENFORCED
  # (not just non-empty): co-locating the header with tfstate collapses the "different blast radius"
  # property — one bucket loss then takes both the sole decryption key AND the state. (load_escrow_creds
  # already enforced non-empty + distinctness above; these re-assert it at the write site.)
  [ -n "$HEADER_BACKUP_BUCKET" ] || { emit_drift header_bucket_unreadable; die "WORKSPACES_HEADER_BUCKET unset — refusing to proceed without an off-host header backup to a bucket DISTINCT from tfstate (C4)"; }
  [ "$HEADER_BACKUP_BUCKET" != "$TFSTATE_BUCKET" ] || { emit_drift header_bucket_equals_tfstate; die "WORKSPACES_HEADER_BUCKET ($HEADER_BACKUP_BUCKET) equals the tfstate bucket — the header MUST live in a DISTINCT blast radius (C4)"; }
  # Header temp file on the persistent STATE_DIR (mode 0700), NOT /tmp — a tmpfs /tmp makes the
  # `shred -u` below a no-op against the raw device (security F7).
  mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR" 2>/dev/null || true
  hdr="${STATE_DIR}/header-backup.img"
  # Guard the backup + UUID reads explicitly (set -uo pipefail has no -e): an unguarded
  # luksHeaderBackup/luksUUID failure would fall through and mis-report as a "UUID mismatch" with an
  # empty backup UUID, AND — firing pre-FREEZE_HELD — would page NOBODY on the Sentry channel (the
  # emit-less die was the only such gap in the escrow limb; observability review P2).
  cryptsetup luksHeaderBackup "$FRESH_DEV" --header-backup-file "$hdr" \
    || { emit_drift header_backup_failed; die "cryptsetup luksHeaderBackup FAILED for $FRESH_DEV — cannot produce the off-host header; aborting BEFORE the freeze (C4)"; }
  live_uuid="$(cryptsetup luksUUID "$FRESH_DEV")"
  bkp_uuid="$(cryptsetup luksUUID "$hdr" 2>/dev/null || cryptsetup luksDump "$hdr" | sed -n 's/^UUID:[[:space:]]*//p')"
  [ -n "$live_uuid" ] && [ "$live_uuid" = "$bkp_uuid" ] || { emit_drift header_backup_uuid_mismatch; die "header backup UUID mismatch (live=$live_uuid backup=$bkp_uuid) — C4"; }
  # Off-host copy to the DISTINCT bucket. BLOCKING + read-back: the upload failure is FATAL and the
  # object is proven present (head-object) BEFORE the local copy is shredded and BEFORE the freeze —
  # else the cutover could complete with NO off-host header anywhere, reopening the F4 unreadable-
  # forever window the moment the plaintext is wiped (Phase 5). The upload is the escrow, not a hint.
  hdr_key="workspaces-luks-header-${live_uuid}.img"
  aws s3 cp "$hdr" "s3://${HEADER_BACKUP_BUCKET}/${hdr_key}" --endpoint-url "$HEADER_R2_ENDPOINT" >/dev/null 2>&1 \
    || { emit_drift header_backup_upload_failed; die "off-host header backup upload to $HEADER_BACKUP_BUCKET FAILED — C4 escrow not satisfied; aborting BEFORE the freeze (creds are read host-side from prd_workspaces_luks — check WORKSPACES_HEADER_R2_ACCESS_KEY_ID / _SECRET_ACCESS_KEY / _ENDPOINT)"; }
  aws s3api head-object --bucket "$HEADER_BACKUP_BUCKET" --key "$hdr_key" --endpoint-url "$HEADER_R2_ENDPOINT" >/dev/null 2>&1 \
    || { emit_drift header_backup_unverified; die "off-host header backup object not readable back from $HEADER_BACKUP_BUCKET — refusing to shred the only local copy on an unproven escrow (C4)"; }
  log "header escrow OK — $hdr_key present in $HEADER_BACKUP_BUCKET (distinct from tfstate)"
  shred -u "$hdr" 2>/dev/null || rm -f "$hdr"
else
  log "(dry-run) escrow probe green; would luksHeaderBackup + upload to $HEADER_BACKUP_BUCKET via $HEADER_R2_ENDPOINT"
fi

# ============================================================================
# G2 manifest (writers live) — enumerate every workspace + ref, derive a count floor
# ============================================================================
step "G2 manifest — enumerate workspaces + all refs (incl refs/checkpoints/*), derive count floor"
manifest_of() {  # $1 = root dir
  local root="$1" ws
  for ws in "$root"/workspaces/*/; do
    [ -d "$ws" ] || continue
    echo "WS $(basename "$ws")"
    git -C "$ws" for-each-ref --format='REF %(refname) %(objectname)' 2>/dev/null || true
    git -C "$ws" for-each-ref --format='CHK %(refname) %(objectname)' 'refs/checkpoints/*' 2>/dev/null || true
    git -C "$ws" status --porcelain 2>/dev/null | sed 's/^/DIRTY /' || true
  done
}
G2="$(manifest_of "$MOUNT")"
G2_COUNT="$(printf '%s\n' "$G2" | grep -c '^WS ' || true)"
# refs/checkpoints/* is the highest-probability silent loss — enumerate it as its OWN named gate
# (C9), not folded into the workspace count. REF count is the full ref set.
G2_CHK="$(printf '%s\n' "$G2" | grep -c '^CHK ' || true)"
G2_REF="$(printf '%s\n' "$G2" | grep -c '^REF ' || true)"
log "G2: $G2_COUNT workspace(s), $G2_REF ref(s), $G2_CHK checkpoint-ref(s) enumerated"
# DP-9 F10: derive the floor from the OBSERVED count, never a hardcoded >0 (0 users ⇒ 0 is valid).

# ============================================================================
# Rollback rehearsal (C15 caveat) — prove the retained plaintext remounts read-only, no restart
# ============================================================================
step "rollback rehearsal — read-only remount of the retained plaintext at a distinct path"
if [ "$DRY_RUN" != "1" ]; then
  reh="/mnt/data-rehearse"; mkdir -p "$reh"
  plain_dev="$(findmnt -no SOURCE "$MOUNT")"
  persist_state PLAINTEXT_DEV "$plain_dev"
  # if/then/else, NOT `A && { B; C; } || D` — else a FAILED umount of a SUCCESSFUL mount would
  # take the `|| D` branch and log the misleading "remount failed" WARN (L3).
  if mount -o ro "$plain_dev" "$reh" 2>/dev/null; then
    log "rehearsal OK — plaintext remounts read-only"
    umount "$reh" 2>/dev/null || log "WARN: rehearsal cleanup umount of $reh failed (rehearsal itself succeeded)"
  else
    log "WARN: rehearsal remount failed (a single mounted device cannot be mounted twice on some fs — acceptable; the retained volume is a SEPARATE device post-repoint)"
  fi
fi

# ============================================================================
# Bulk rsync (writers live, no --delete) — no user impact
# ============================================================================
step "bulk rsync (writers live, no --delete) into the empty LUKS target"
[ "$DRY_RUN" = "1" ] || rsync -aHAX --numeric-ids "$MOUNT"/ "$STAGING"/

# ============================================================================
# FREEZE (≤20 min budget) — quiesce, drain, copy the delta, verify, repoint
# ============================================================================
step "FREEZE — quiesce $QUIESCE_UNITS + docker stop -t 120 (C8) + interrupted-write asserts (G4)"
FREEZE_HELD=1; persist_state FREEZE_HELD 1; arm_dead_man
if [ "$DRY_RUN" != "1" ]; then
  freeze_writers
else
  # Advisory holder probe (dry-run arm only, NEVER fatal). The rehearsal cannot reach the real G4
  # (it is inside the DRY_RUN gate), so without this a `dry_run=true` run tells the operator nothing
  # about whether the mount would actually be quiescible — which is how the fail-closed G4 could
  # first surface on a REAL freeze, burning an irreversible-freeze approval.
  ensure_lsof
  DRY_HOLDERS="$(lsof +D "$MOUNT" 2>/dev/null || true)"
  if [ -n "$DRY_HOLDERS" ]; then
    log "(dry-run) ADVISORY: $(printf '%s\n' "$DRY_HOLDERS" | grep -c . || true) process line(s) currently hold $MOUNT."
    log "(dry-run) These are NOT quiesced in this arm (no freeze runs). A REAL freeze stops $QUIESCE_UNITS first;"
    log "(dry-run) anything still listed AFTER that quiesce is what the fail-closed G4 would abort on."
    printf '%s\n' "$DRY_HOLDERS" | head -n "$FREEZE_HOLDER_CAP" | while IFS= read -r l; do log "  (dry-run) HOLDER $(_vscrub "$l")"; done
  else
    log "(dry-run) advisory holder probe: nothing currently holds $MOUNT"
  fi
fi

step "G3 manifest AFTER the freeze on SRC vs DST — same instant, opposite volumes (C9)"
if [ "$DRY_RUN" != "1" ]; then
  # C1: pass-2 delta with --checksum (the only backstop).
  rsync -aHAX --numeric-ids --delete --checksum "$MOUNT"/ "$STAGING"/ \
    || die "pass-2 delta rsync failed — DST is not a complete copy; aborting before the verify (C1)"
  # C1 — drop caches AFTER the last write (the pass-2 rsync above), IMMEDIATELY before the verify.
  # Dropping before pass-2 is useless — pass-2's --checksum reads all of SRC/DST back into the page
  # cache, so the verify would read RAM, never the dm-crypt round-trip. A drop that CANNOT run
  # (hardened kernel, no perm) must ABORT, not warn — the whole integrity claim rests on the
  # round-trip, so a silently-cached verify is a false-green (data-integrity P1).
  sync
  echo 3 > /proc/sys/vm/drop_caches || die "drop_caches failed — cannot trust the dm-crypt round-trip verify; aborting (C1)"
  # C1 — the ITEMIZED verify (the false-green fix): MUST be 0 real content diffs, fail-closed on a
  # verify-rsync error. verify_byte_identity captures the verify rsync's stdout/stderr SEPARATELY,
  # counts only itemize-shaped stdout lines (stderr can no longer inflate it), and LOGS the offending
  # path(s)+code(s) — run log + Better Stack (SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF) — BEFORE it dies, so
  # the next real cutover self-reports what aborted it. Call it DIRECTLY (never in $(…)/a subshell) so
  # die's exit 1 reaches the EXIT trap -> rollback.
  verify_byte_identity "$MOUNT" "$STAGING"
  # Byte assert with apparent-size (never df/du -sb — LUKS steals a header, geometry differs). Require
  # both sides non-empty + numeric, else a `du` failure on both (path typo, missing dir) yields ""=""
  # and passes vacuously.
  SRC_BYTES="$(du --apparent-size -sb "$MOUNT"/workspaces 2>/dev/null | cut -f1)"
  DST_BYTES="$(du --apparent-size -sb "$STAGING"/workspaces 2>/dev/null | cut -f1)"
  [[ "$SRC_BYTES" =~ ^[0-9]+$ && "$DST_BYTES" =~ ^[0-9]+$ ]] || die "du --apparent-size produced non-numeric output (src='$SRC_BYTES' dst='$DST_BYTES') — the byte match cannot run (C1)"
  [ "$SRC_BYTES" = "$DST_BYTES" ] || die "apparent-size mismatch (src=$SRC_BYTES dst=$DST_BYTES) — C1"
  # git fsck --full per workspace — a GATE, not decorative: a corrupt object that round-tripped onto
  # the LUKS device must ABORT (the plaintext original is wiped in Phase 5). Collect + die on any fail.
  fsck_fail=0
  for ws in "$STAGING"/workspaces/*/; do
    [ -d "$ws/.git" ] || continue
    git -C "$ws" fsck --full >/dev/null 2>&1 || { fsck_fail=$((fsck_fail + 1)); log "FSCK FAIL: $ws"; }
  done
  [ "$fsck_fail" -eq 0 ] || die "git fsck --full failed in $fsck_fail workspace(s) — object corruption on the LUKS copy (C1/AC26)"
  df "$STAGING" >/dev/null && df -i "$STAGING" >/dev/null || die "df/df -i preflight failed on $STAGING"
  # G3 — the data gate (AC24). Compare workspace, ref, AND checkpoint-ref counts, each derived from
  # the OBSERVED G2 (DP-9 F10, never a hardcoded >0). refs/checkpoints/* is its OWN named check.
  G3="$(manifest_of "$STAGING")"
  G3_DST_COUNT="$(printf '%s\n' "$G3" | grep -c '^WS ' || true)"
  G3_DST_REF="$(printf '%s\n' "$G3" | grep -c '^REF ' || true)"
  G3_DST_CHK="$(printf '%s\n' "$G3" | grep -c '^CHK ' || true)"
  [ "$G3_DST_COUNT" = "$G2_COUNT" ] || die "DST workspace count ($G3_DST_COUNT) != G2 ($G2_COUNT) — the data gate (G3), not the canary, is the partial-loss detector (AC24)"
  [ "$G3_DST_REF" = "$G2_REF" ] || die "DST ref count ($G3_DST_REF) != G2 ($G2_REF) — refs dropped in transit (AC24)"
  [ "$G3_DST_CHK" = "$G2_CHK" ] || die "DST refs/checkpoints/* count ($G3_DST_CHK) != G2 ($G2_CHK) — the highest-probability silent loss; aborting (C9/AC24)"
fi

step "repoint_luks_mount — mapper -> $MOUNT (backup fstab; findmnt assert)"
if [ "$DRY_RUN" != "1" ]; then
  cp /etc/fstab "/etc/fstab.pre-luks.$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo bak)" 2>/dev/null || cp /etc/fstab /etc/fstab.pre-luks.bak
  umount "$STAGING" 2>/dev/null || true
  # umount MUST succeed — a failed umount (a straggler re-acquired the mount) followed by the mapper
  # mount would STACK the mapper OVER the still-mounted plaintext. findmnt -no SOURCE returns the
  # TOPMOST source (=$MAPPER), so the assert below would PASS while the app writes to the mapper and
  # the plaintext is shadowed underneath (the #5274 stranding, silently). Fail loud instead.
  umount "$MOUNT" || die "umount $MOUNT failed — refusing to stack the mapper over live plaintext (#5274)"
  mountpoint -q "$MOUNT" && die "$MOUNT is STILL a mountpoint after umount — refusing to stack the mapper over it (#5274)"
  mount "$MAPPER" "$MOUNT"
  FLIP_DONE=1; persist_state FLIP_DONE 1
  [ "$(findmnt -no SOURCE "$MOUNT")" = "$MAPPER" ] || die "findmnt: $MOUNT is not $MAPPER after repoint (#5274 stranding)"
fi

# ============================================================================
# Host-level canary BEFORE docker start (C13) — the mapper link is the missing chain link
# ============================================================================
step "host canary BEFORE docker start (C13) — blkid + findmnt + cryptsetup status + mountpoint"
if [ "$DRY_RUN" != "1" ]; then
  WL_DEVICE_TYPE="$(blkid -s TYPE -o value "$FRESH_DEV")"; export WL_DEVICE_TYPE
  [ "$WL_DEVICE_TYPE" = "crypto_LUKS" ] || { emit_drift device_not_luks; die "blkid: $FRESH_DEV is not crypto_LUKS"; }
  [ "$(findmnt -no SOURCE "$MOUNT")" = "$MAPPER" ] || { emit_drift mount_not_mapper; die "findmnt: $MOUNT != $MAPPER"; }
  cryptsetup status "$MAPPER_NAME" >/dev/null 2>&1 || { emit_drift cryptsetup_status_missing; die "cryptsetup status: no mapper->device link"; }
  mountpoint -q "$MOUNT" || { emit_drift not_mounted; die "mountpoint -q $MOUNT failed"; }
  CANARY_OK=1; persist_state CANARY_OK "1:$(cryptsetup luksUUID "$FRESH_DEV")"  # DP-7: run-keyed + header UUID
  log "host canary PASSED — $MOUNT is the LUKS mapper"
fi

step "docker start + resume webhook + app canary (C13)"
if [ "$DRY_RUN" != "1" ]; then
  docker start "$CONTAINER"
  # Restore every unit freeze_writers() quiesced (webhook + inngest-redis) and reconcile
  # inngest-server — AFTER the mapper mount, which RequiresMountsFor=/mnt/data demands.
  resume_writers
  disarm_dead_man
  app_canary
  # Deliver the standing observability to the LIVE host via THIS channel (ADR-119 §(e)).
  install -D -m 0755 "${SELF_DIR}/luks-monitor.sh" /usr/local/bin/luks-monitor 2>/dev/null || true
  install -D -m 0755 "$EMIT" /usr/local/bin/workspaces-luks-emit.sh 2>/dev/null || true
  install -D -m 0644 "${SELF_DIR}/luks-monitor.service" /etc/systemd/system/luks-monitor.service 2>/dev/null || true
  install -D -m 0644 "${SELF_DIR}/luks-monitor.timer" /etc/systemd/system/luks-monitor.timer 2>/dev/null || true
  # #6649 — persist the prd_workspaces_luks boot token into the luks-monitor EnvironmentFile so the
  # DAILY timer probe (luks-monitor.service) can `doppler secrets get WORKSPACES_LUKS_KEY … --config
  # prd_workspaces_luks` unattended. cloud-init bakes ONLY SOLEUR_SENTRY_DSN here (no token), and the
  # cutover carries the token in $DOPPLER_TOKEN (injected via the 0600 stdin .env). Preserve the baked
  # DSN line; write 0600 root. Absent this, the daily probe would emit doppler_unreachable every day.
  if [ -n "${DOPPLER_TOKEN:-}" ]; then
    ENVF="/etc/default/luks-monitor"; touch "$ENVF"; chmod 600 "$ENVF"
    # Drop any prior DOPPLER_TOKEN line, keep the baked DSN + everything else, append the current token.
    # `umask 077` so the `.tmp` is BORN 0600 — a `chmod 600 "$ENVF"` AFTER the `mv` cannot protect the
    # window, because `mv` replaces the inode with the tmp's (0644-under-default-umask) perms, briefly
    # exposing the full-prd token world-readable (security review P3). The final chmod is belt-and-suspenders.
    ( umask 077; { grep -v '^DOPPLER_TOKEN=' "$ENVF" 2>/dev/null || true; printf 'DOPPLER_TOKEN=%s\n' "$DOPPLER_TOKEN"; } > "${ENVF}.tmp" ) \
      && mv "${ENVF}.tmp" "$ENVF" && chmod 600 "$ENVF"
  else
    log "WARN: DOPPLER_TOKEN not in env at unit-install time — the daily luks-monitor probe will lack a prd_workspaces_luks token"
  fi
  # Structural fail-closed gate: chattr +i the root-disk mountpoint is unreachable now (mapper is
  # mounted), so it is delivered on the next unmount path; arm the daily probe timer now.
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable --now luks-monitor.timer 2>/dev/null || true
  # Fail loud if the timer did not arm (a silently-missing unit would leave the daily probe dark; the
  # `install … || true` above swallows delivery errors deliberately, so assert the end state here).
  systemctl is-enabled luks-monitor.timer >/dev/null 2>&1 || { emit_drift luks_monitor_timer_enable_failed; die "luks-monitor.timer failed to enable — the daily at-rest probe would not run (C15/ADR-119 §(e))"; }
  # Reboot-once re-canary (C15): the realistic failure is the boot path (the structural gate + the
  # --restart resurrection). This script does NOT auto-reboot — a reboot drops the CF-Tunnel SSH
  # session mid-run. The run-keyed CANARY_OK is persisted to $STATE_FILE with the header UUID (above)
  # so a pre-reboot value cannot satisfy a fresh post-reboot check. The boot-path proof is an
  # OPERATOR step AFTER this run: reboot web-1 once, then dispatch workspaces-luks-verify.yml (the
  # read-only re-assert) — a fresh green there proves the boot path. See the runbook.
  log "cutover green. Operator: reboot web-1 once, then run workspaces-luks-verify.yml to prove the boot path (C15)."
fi

step "cutover body complete (DRY_RUN=$DRY_RUN). The WIPE/converge is a SEPARATE environment-gated dispatch (DP-4)."
# CONFIRM_WIPE path is authored in the Phase-5 soak/converge dispatch, not here (DP-4): the sweeper
# cannot hold the creds for an irreversible blkdiscard, so the wipe rides its own env-gated workflow
# that re-verifies the persisted run-keyed canary_ok header UUID against the live mapper (DP-7).
exit 0
