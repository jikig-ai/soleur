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
# CLEAN_STRAY — the stray-copy carve-out. Default 0 like ROLLBACK: it must never be the arm a
# dispatch falls into by omission. Unlike ROLLBACK it does NOT force DRY_RUN=0; see clean_stray().
CLEAN_STRAY="${CLEAN_STRAY:-0}"
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
# ReadWritePaths=/var/lib/inngest /var/lock, so it provably cannot WRITE $MOUNT, while
# TimeoutStopSec=180 means stopping it could burn 3 minutes of a ~10-minute freeze for zero
# quiescence benefit. (The write claim is NOT a hold claim — ProtectSystem=strict makes $MOUNT
# read-only in its namespace, not invisible, so a read-only open would still show in `lsof +D`.
# That axis is delegated to G4 on purpose, not argued away.) Its residual risk (a crash-loop into
# `failed` during the redis outage window) is covered by the post-freeze reconcile in
# resume_writers() at zero freeze cost. See ADR-119 Addendum 2026-07-19.
QUIESCE_UNITS="${WORKSPACES_QUIESCE_UNITS:-webhook.service inngest-redis.service}"
# QUIESCE_TIMERS — timer-driven $MOUNT touchers. Stopped as `<timer> <service>` PAIRS: stopping a
# .timer only prevents FUTURE triggers, it does not stop the instance the timer already launched.
#  - orphan-reaper: runs `rm -rf` over $MOUNT/workspaces/*.orphaned-* every 6h as root
#    (server.tf orphan-reaper.{service,timer}; orphan-reaper.sh WORKSPACE_ROOT=/mnt/data/workspaces)
#    and carries NO RequiresMountsFor, so nothing stops it firing mid-freeze. A reap between the
#    pass-2 delta rsync and the C1 verify makes `rsync --delete --dry-run` emit a `*deleting` line
#    — the IDENTICAL abort signature as the redis AOF, on a ~6h duty cycle against a ~20min freeze.
#  - luks-monitor: read-only, but RequiresMountsFor=/mnt/data means a mid-run instance holds the
#    mount and trips the now fail-closed G4 (and would block the umount). Armed only by a PRIOR
#    successful cutover, so absent on a first run — hence best-effort.
QUIESCE_TIMERS="${WORKSPACES_QUIESCE_TIMERS:-orphan-reaper luks-monitor}"
FREEZE_HOLDER_CAP="${WORKSPACES_FREEZE_HOLDER_CAP:-40}"

# _quiesce_list — QUIESCE_UNITS with webhook.service guaranteed PRESENT and FIRST.
# freeze_writers() and resume_writers() BOTH drive off this one list, so the stop set and the
# restore set cannot drift apart. Hardcoding the webhook stop while restoring only $QUIESCE_UNITS
# would mean an override that omits webhook.service stops it and never brings it back — an
# asymmetric stop/restore pair, which is the exact defect class this change exists to fix.
_quiesce_list() {
  local u out="webhook.service"
  for u in $QUIESCE_UNITS; do [ "$u" = "webhook.service" ] || out="$out $u"; done
  printf '%s' "$out"
}

# ensure_lsof — G4 is fail-CLOSED, so `lsof` must exist. Mirrors ensure_aws (idempotent, installs
# on demand). This is the SOLE delivery mechanism for `lsof`, on every host: web-1 carries
# lifecycle{ ignore_changes = [user_data] } so cloud-init cannot reach the running host, and the
# cloud-init package list was NOT extended for future hosts either — the web render sits ~78 B
# under its base64gzip budget (plugins/soleur/test/cloud-init-user-data-size.test.ts), and adding
# ` lsof` + a rationale comment consumed all but 2 bytes of that margin, which then failed on CI's
# zlib. A 2-byte margin is luck, not headroom. Do NOT re-add it without first re-measuring.
# OPERATOR NOTE: like ensure_aws, this runs in BOTH arms, so a `dry_run=true` rehearsal is NOT
# host-side-effect-free the FIRST time — it may apt-get install lsof (additive, no service restart).
# Called PRE-freeze beside ensure_aws (NOT inside freeze_writers): an apt-get inside the freeze
# window runs with the app down and the dead-man ticking, so a held dpkg lock (Ubuntu's daily
# unattended-upgrades) or a slow mirror would burn an irreversible-freeze approval. Bounded +
# lock-tolerant, mirroring cloud-init.yml's apt invocation. Idempotent, so the in-freeze call is a
# no-op backstop.
ensure_lsof() {
  if command -v lsof >/dev/null 2>&1; then return 0; fi
  log "lsof absent — installing (G4 is fail-closed; it must never be skipped)"
  local aerr; aerr="$(mktemp)"
  { timeout 240 apt-get update -qq >>"$aerr" 2>&1 \
    && timeout 300 apt-get install -y -qq -o DPkg::Lock::Timeout=300 lsof >>"$aerr" 2>&1; } || true
  if ! command -v lsof >/dev/null 2>&1; then
    # Carry apt's own tail into the die message — hr-no-ssh-fallback-in-runbooks means the operator
    # cannot shell in to ask "why"; a bare `lsof_unavailable` is undiagnosable.
    local atail; atail="$(_vscrub "$(tail -c 400 "$aerr" 2>/dev/null || true)")"; rm -f "$aerr"
    emit_drift lsof_install_failed
    die "lsof unavailable and could not be installed — the G4 straggler assert cannot run. Refusing to freeze on a mount whose quiescence is unproven: a gate that silently evaporates when a binary is absent is exactly how an unquiesced writer reached two real freezes (#6588). apt tail: ${atail}"
  fi
  rm -f "$aerr"
}

# emit_freeze_holders — log the processes still holding $MOUNT to the run log AND Better Stack
# BEFORE die(), so a G4 abort is diagnosable with no SSH. Mirrors emit_verify_diff (the #6604 fix
# for the same defect class on C1): evidence must outlive the abort that produced it.
emit_freeze_holders() {
  local holders="$1" n k line summary row
  # grep -c . <<< (herestring, not a pipe): the file documents at the escrow negative-probe that a
  # pipe under `set -o pipefail` can SIGPIPE the producer. `$holders` has already had lsof's
  # `COMMAND PID USER …` header row stripped by the caller, so this counts PROCESSES, not lines.
  n="$(grep -c . <<<"$holders" || true)"
  log "G4 straggler assert FAILED: ${n} process(es) still hold $MOUNT. Capped ${FREEZE_HOLDER_CAP}:"
  summary="SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER feature=workspaces-luks op=workspaces-luks-freeze-holder count=${n} mount=$(_vscrub "$MOUNT") host=$(hostname 2>/dev/null)"
  # Bare `echo` for the marker rows, matching emit_verify_diff — log() prefixes "[workspaces-cutover] ",
  # which would indent SOLEUR_ markers that the sibling emitter writes at column 0.
  echo "$summary"; logger -t "$LUKS_LOG_TAG" -- "$summary" 2>/dev/null || true
  k=0
  while IFS= read -r line && [ "$k" -lt "$FREEZE_HOLDER_CAP" ]; do
    [ -n "$line" ] || continue
    row="SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER feature=workspaces-luks op=workspaces-luks-freeze-holder count=${n} idx=${k} holder=$(_vscrub "$line")"
    echo "$row"; logger -t "$LUKS_LOG_TAG" -- "$row" 2>/dev/null || true
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
  # container drain, then the remaining units. resume_writers() reverses this exactly.
  local u first=1
  for u in $(_quiesce_list); do
    systemctl stop "$u" || { emit_drift quiesce_stop_failed; die "systemctl stop $u FAILED — refusing to freeze with a writer still running (the exact #6588 failure)"; }
    # C8: drain lets in-flight write() finish (a 10s SIGKILL truncates) — immediately after webhook.
    [ "$first" = "1" ] && { docker stop -t 120 "$CONTAINER"; first=0; }
  done
  # The canary container shares the same RW bind mount (-v /mnt/data/workspaces:/workspaces) and is
  # left running by an aborted deploy. Stopping webhook.service prevents NEW deploys, not a
  # pre-existing straggler; G4 would catch it, but that is an avoidable abort.
  docker stop -t 60 "${CONTAINER}-canary" >/dev/null 2>&1 || true
  # Timer-driven touchers, stopped as <timer> <service> PAIRS — see QUIESCE_TIMERS. Best-effort:
  # both are absent on a first cutover.
  for u in $QUIESCE_TIMERS; do
    systemctl stop "${u}.timer" "${u}.service" 2>/dev/null || true
  done
  # Record what was ACTUALLY stopped (the symmetric list), not the raw override — this is the
  # forensic record an unattended recovery reads.
  persist_state QUIESCED_UNITS "$(_quiesce_list)"

  # A SIGKILL at TimeoutStopSec leaves a TORN AOF tail, and `systemctl stop` still returns 0 — so
  # the process is gone (G4 clean) and C1 then certifies a byte-perfect copy of corrupt queue state.
  # Byte-identity is not integrity. Redis restarts with the default `aof-load-truncated yes`, i.e.
  # it silently discards the tail: every reminder armed in the last seconds vanishes with no error.
  # systemd sets Result=timeout on a TimeoutStopSec kill, so this is a real discriminator.
  local res
  for u in $(_quiesce_list); do
    res="$(systemctl show "$u" -p Result --value 2>/dev/null || echo unknown)"
    case "$res" in
      success|unknown) ;;
      *) emit_drift unclean_stop; die "$u did not stop cleanly (Result=${res}) — its on-disk state may be torn; refusing to certify a copy of possibly-corrupt data (C8)" ;;
    esac
  done

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
  # The redis-side equivalents. G4 answers a DIFFERENT question (is anyone holding the mount) than
  # these do (is there wreckage on disk we would faithfully copy), so delegating to G4 is not
  # sufficient — /mnt/data/redis is a SIBLING of workspaces/ and was unguarded on every axis before.
  if [ -d "$MOUNT/redis" ]; then
    ls "$MOUNT"/redis/appendonlydir/temp-rewriteaof-* >/dev/null 2>&1 \
      && die "temp-rewriteaof-* present in $MOUNT/redis/appendonlydir — an AOF rewrite child was killed rather than reaped; aborting (C8)"
    ls "$MOUNT"/redis/temp-*.rdb >/dev/null 2>&1 \
      && die "temp-*.rdb present in $MOUNT/redis — unexpected with \`save \"\"\`; something wrote outside the expected path; aborting (C8)"
    # Manifest consistency is the strongest available proxy for "the AOF is loadable" without
    # starting Redis: every file the manifest names must exist, or the copy is a faithful copy of an
    # unloadable dataset.
    local mf f
    mf="$MOUNT/redis/appendonlydir/appendonly.aof.manifest"
    if [ -f "$mf" ]; then
      while read -r f; do
        [ -n "$f" ] || continue
        [ -e "$MOUNT/redis/appendonlydir/$f" ] \
          || die "AOF manifest names '$f' but it is absent from $MOUNT/redis/appendonlydir — the queue state is unloadable; aborting rather than copying it (C8)"
      done < <(grep -oE 'file [^ ]+' "$mf" 2>/dev/null | awk '{print $2}' || true)
    fi
  fi

  assert_mount_quiesced freeze
}

# assert_mount_quiesced <phase> — G4. Call it at EVERY point where quiescence must hold, not once:
# it is a point-in-time sample, and the pass-2 delta rsync + C1 verify run ~10 minutes after the
# freeze. A writer that starts after a single sample is undetected by construction.
#
# FIVE properties, each load-bearing. The first four are the original G4 contract; the fifth is
# #6733's, and it is the one that broke five real cutovers.
#  (a) fail-CLOSED on a missing lsof (ensure_lsof dies rather than skipping). The pre-#6588 form
#      wrapped the whole assert in `command -v lsof && …`, so on a host without lsof the gate
#      silently vanished — the silent-failure anti-pattern (cq-silent-fallback-must-mirror-to-sentry).
#  (b) NO pipe. `lsof +D "$MOUNT" | grep -q .` under `set -o pipefail` returns 141 when grep closes
#      the pipe on an early match and the producer takes SIGPIPE — so `&& die` never fires. That is
#      a SIZE-DEPENDENT fail-OPEN: the gate evaporates exactly when there are many stragglers. Every
#      predicate below therefore reads a FILE (`awk … >"$pc"` + `[ -s ]`) or matches in-shell.
#  (c) a POSITIVE CONTROL. `lsof` exits 1 BOTH when it finds nothing and when it errors, and writes
#      diagnostics only to stderr — so `"$(lsof … 2>/dev/null || true)"` reads "the probe failed" as
#      "the mount is clean". A typo'd $MOUNT, an unstat-able subtree (docker overlay filesystems on
#      this host already warn), or any lsof error would pass the gate blind. So we hold our OWN fd
#      under $MOUNT and require the probe to SEE it: empty output then proves the scan reached the
#      mount, instead of merely assuming it. Mirrors verify_byte_identity, which captures stdout and
#      stderr separately and treats a probe error as fail-closed for the same reason.
#  (d) holders are EMITTED before die(), so the abort self-reports (the #6604 defect class).
#  (e) the probe does NOT PERTURB THE TREE IT CERTIFIES (#6733). See the block inside the function.

# _assert_mount_rw <phase> — the writability signal the old WRITE-probe smuggled in, restated as its
# own named assert (#6733).
#
# The removed probe was `exec 9>"$MOUNT/.luks-g4-probe.$$"`, and its failure arm doubled as an
# unnamed second assertion: a $MOUNT that had gone read-only (the kernel's `errors=remount-ro`
# default, after an I/O or ext4 error) could not be written, so the run aborted. The read-open that
# replaces it cannot fail that way. Dropping the signal silently would trade one defect for another,
# so it is asserted EXPLICITLY here — and it is now STRONGER than the side effect it replaces,
# because it names the condition instead of inferring it from a failed create.
#
# TOKEN comparison, never a substring. Measured on a live host 2026-07-20: `findmnt -no OPTIONS /`
# returns `rw,relatime,errors=remount-ro`. A substring test for "ro" matches inside the
# `errors=remount-ro` VALUE and would declare a perfectly writable mount read-only — an
# unconditional false abort. The options field is a comma-separated list, so it is split on `,` and
# each token compared WHOLE.
_assert_mount_rw() {
  local phase="$1" opts tok
  local -a toks
  opts="$(findmnt -no OPTIONS "$MOUNT" 2>/dev/null)"
  if [ -z "$opts" ]; then
    emit_drift g4_mount_opts_unreadable
    die "cannot read \$MOUNT's mount options via findmnt (phase=${phase}) — refusing to certify quiescence on a mount whose read/write state is unknown. The pre-#6733 write-probe proved writability as a side effect; this gate must not lose that signal silently"
  fi
  IFS=',' read -r -a toks <<<"$opts"
  for tok in "${toks[@]}"; do
    if [ "$tok" = ro ]; then
      emit_drift g4_mount_read_only
      die "\$MOUNT is mounted READ-ONLY (phase=${phase}; options='${opts}') — the kernel has almost certainly remounted it ro after an I/O or filesystem error. Refusing to freeze or verify against a mount that cannot accept rollback()'s remount: the retained plaintext is the ONLY copy until Phase 5, and a rollback that cannot write is not a rollback"
    fi
  done
}

assert_mount_quiesced() {
  local phase="${1:-freeze}" wsdir="$MOUNT/workspaces" lout lerr pc rc hdr holders

  ensure_lsof
  # Runs at BOTH phases, like the rest of G4 — a mount that went read-only between the freeze and
  # the pre-verify re-assert is exactly the drift this gate exists to catch.
  _assert_mount_rw "$phase"

  # --- THE PROBE IS A READ, NOT A WRITE (#6733) -------------------------------------------------
  # This gate used to hold its positive-control fd by CREATING an entry under the mount
  # (`exec 9>"$MOUNT/.luks-g4-probe.$$"`) and unlinking it. BOTH operations advance the mtime of
  # $MOUNT's ROOT DIRECTORY, and the `pre-verify` call site lands BETWEEN the pass-2 delta rsync and
  # the C1 itemized verify — so C1 correctly emitted `.d..t...... ./` on an otherwise byte-identical
  # tree and five real cutovers safe-aborted. C1 was RIGHT every time. The gate was perturbing the
  # very tree it was about to certify.
  #
  # The fix is at SOURCE: a READ-open of a directory that ALREADY EXISTS. Measured 2026-07-20:
  #   * `lsof +D` reports a read-only directory fd — `bash <pid> <user> 9r DIR … /mnt/data/workspaces`
  #     — so the positive control keeps its FULL strength; and
  #   * opening a directory for read does NOT advance its mtime (ns-precision, before == after).
  # There is consequently nothing to save, restore, fingerprint or prove-restored. An earlier
  # attempt bracketed the write with a touch -r save/restore; that repaired the symptom and left the
  # gate mutating its own subject. Removing the mutation is strictly smaller and strictly safer.
  #
  # WHY `workspaces/` AND NOT $MOUNT ITSELF: it is the directory every other gate on this path
  # already REQUIRES (the `du --apparent-size -sb "$MOUNT"/workspaces` byte assert, and the
  # `for ws in "$MOUNT"/workspaces/*/` loops in freeze_writers and the G3 manifest). Requiring it
  # here adds no new precondition — and its ABSENCE is the single most valuable thing this gate can
  # fail on, which is why the die below is worded the way it is.
  #
  # WHY REUSING A REAL PATH IS SAFE NOW: the old holder filter subtracted the probe BY PATH
  # (`grep -vF -- "$probe"`), so pointing the probe at a real path would have subtracted a GENUINE
  # straggler that happened to hold that same path — a fail-open in the exact gate meant to catch
  # stragglers. The filter below subtracts by PID instead, so only THIS process's own rows are
  # excluded and a straggler holding workspaces/ is still reported. The PID filter is what makes the
  # read-probe admissible; the two changes are one change and must not be separated.
  if ! exec 9<"$wsdir"; then
    emit_drift g4_workspaces_unopenable
    die "cannot open '$wsdir' for reading (phase=${phase}) — this is the WRONG-DEVICE / EMPTY-AUTO-CREATED-BIND-SOURCE state. Either \$MOUNT is not the volume carrying user data, or 'workspaces/' was auto-created empty beneath a bind mount. A cutover that proceeds from here copies an EMPTY tree, and every gate downstream compares empty against empty and reports GREEN: C1 finds no differences, the du byte match reads 0 == 0, and G3's counts agree at zero. That is a cutover declared successful with every user's data missing. Refusing to certify quiescence on a mount whose workspaces/ directory cannot even be opened"
  fi

  lout="$(mktemp)"; lerr="$(mktemp)"; pc="$(mktemp)"
  # `9<&-` closes fd 9 IN THE CHILD ONLY. Bash does not set O_CLOEXEC on `exec 9<`, so without this
  # redirection every child inherits the directory fd — and under the PID filter below an inheriting
  # child is indistinguishable from a foreign straggler, i.e. this gate would report ITSELF and
  # abort every cutover. Measured 2026-07-20: a child process in the same pipeline appears in
  # `lsof +D` output with its own inherited `9r DIR` row. (The lsof on this host happens to exempt
  # its own process from its output, but that is one implementation's behaviour, not a contract to
  # rest a production gate on — and it does not exempt any OTHER child.)
  lsof +D "$MOUNT" 9<&- >"$lout" 2>"$lerr"; rc=$?
  exec 9<&-

  # rc 0 = holders found, rc 1 = none found OR an error. Anything else is an outright probe failure.
  if [ "$rc" -gt 1 ]; then
    local etail; etail="$(_vscrub "$(tail -c 400 "$lerr" 2>/dev/null || true)")"
    rm -f "$lout" "$lerr" "$pc"; emit_drift g4_probe_failed
    die "the G4 lsof probe itself FAILED (rc=${rc}, phase=${phase}) — cannot certify quiescence; stderr: ${etail}"
  fi

  # HEADER-SHAPE ASSERT — lsof output-format drift must fail CLOSED.
  # Both predicates below read lsof's SECOND whitespace-separated field as the PID and drop row 1 as
  # the header. If a future lsof reordered its columns or dropped the header, the holder filter would
  # start reading a different column entirely: header text could be counted as a straggler, or — the
  # dangerous direction — real holders could stop matching and the gate would certify a busy mount as
  # quiesced. Asserting the shape converts that from a silent miscount into a named abort.
  # No pipe (`head -n1 … | grep -q` would SIGPIPE the producer to 141 under pipefail, property (b));
  # the first line is read directly from the file and matched in-shell.
  hdr=""; IFS= read -r hdr <"$lout" || true
  if [[ ! "$hdr" =~ ^COMMAND[[:space:]]+PID[[:space:]]+USER ]]; then
    rm -f "$lout" "$lerr" "$pc"; emit_drift g4_lsof_header_unrecognized
    die "lsof's output header is not the expected 'COMMAND PID USER …' shape (phase=${phase}; got: '$(_vscrub "$hdr")') — this gate parses the PID column by position, so an unrecognised format means every holder verdict below is unreliable. Refusing to certify quiescence from output this gate cannot parse"
  fi

  # POSITIVE CONTROL — our own fd MUST appear, matched on BOTH our PID and the probed path.
  # Requiring the PATH too is what makes an EMPTY holder list evidence: a row bearing our PID alone
  # could come from anywhere in the tree, whereas a row bearing our PID AND "$wsdir" proves the scan
  # actually descended to the subtree we opened. Without the path term, an lsof that scanned only
  # $MOUNT's top level would satisfy the control while never having looked where the data lives.
  # `awk … >"$pc"` then `[ -s ]`: a file test, never `| grep -q` (property (b)).
  awk -v p="$$" -v n="$wsdir" '$2 == p && index($0, n)' "$lout" >"$pc" 2>/dev/null
  if [ ! -s "$pc" ]; then
    local etail; etail="$(_vscrub "$(tail -c 400 "$lerr" 2>/dev/null || true)")"
    rm -f "$lout" "$lerr" "$pc"; emit_drift g4_probe_blind
    die "lsof did not report this script's own read fd on '$wsdir' (rc=${rc}, phase=${phase}) — the G4 straggler probe is BLIND, not clean; refusing to freeze on unproven quiescence. stderr: ${etail}"
  fi

  # HOLDERS — every row that is not the header and not one of OUR OWN.
  # `NR>1` drops the header structurally; the pre-#6733 form used `grep -v '^COMMAND '`, a heuristic
  # that would also have dropped a genuine holder whose COMMAND happened to start that way. Filtering
  # by PID (not by path) is what lets the probe reuse a real directory without subtracting a real
  # straggler — see the block above.
  holders="$(awk -v p="$$" 'NR>1 && $2 != p' "$lout" || true)"
  rm -f "$lout" "$lerr" "$pc"

  if [ -n "$holders" ]; then
    emit_freeze_holders "$holders"
    die "lsof +D $MOUNT non-empty (phase=${phase}) — a straggler still holds the mount (G4); see the SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER marker for the offending process(es)"
  fi
}

# resume_writers — restore everything freeze_writers() quiesced. Called on ALL THREE exit paths
# (success, rollback, and the dead-man's inline command carries the equivalent), so a run leaves the
# host exactly as it found it whether it succeeds, safe-aborts, or dies unattended.
#
# MUST run AFTER the mount is back, and the two quiesced units fail DIFFERENTLY if it is not:
#   - inngest-redis.service carries RequiresMountsFor=/mnt/data, so it fails SAFELY (systemd
#     refuses to start it) and merely lands in `failed`, which outlives the run.
#   - webhook.service carries NO RequiresMountsFor — only ReadWritePaths=/mnt/data — so it starts
#     SUCCESSFULLY onto the bare root-disk mountpoint directory. It is the CI deploy receiver, so a
#     deploy landing during the incident writes user data into the ROOT filesystem under /mnt/data,
#     shadowed the instant the volume is remounted. That is the dangerous one, and it is precisely
#     the trap inngest-redis.service's own RequiresMountsFor comment was added to prevent.
# rollback() swallows its remount failure (`|| true`), so this guard is what stops that swallowed
# failure from becoming a data-loss event.
resume_writers() {
  if ! mountpoint -q "$MOUNT" 2>/dev/null; then
    emit_drift resume_without_mount
    log "WARN: $MOUNT is NOT mounted — refusing to start writers onto the bare mountpoint directory."
    log "WARN: units stay stopped; the host needs an operator remount before the data plane returns."
    return 0
  fi
  local u rev=""
  for u in $(_quiesce_list); do rev="$u${rev:+ }$rev"; done  # reverse: webhook comes back LAST
  for u in $rev; do
    systemctl reset-failed "$u" 2>/dev/null || true
    systemctl start "$u" 2>/dev/null || true
    systemctl is-active --quiet "$u" 2>/dev/null || {
      # Carry the unit in the reason — two units in the set means an undiscriminated reason cannot
      # tell "the webhook is down" from "the durable queue is down".
      emit_drift "quiesced_unit_not_active_${u%%.service}"
      log "WARN: $u is not active after resume — the freeze left it down"
      logger -t "$LUKS_LOG_TAG" -- "SOLEUR_WORKSPACES_LUKS_RESUME_DEGRADED feature=workspaces-luks op=workspaces-luks-resume-degraded unit=$(_vscrub "$u") host=$(hostname 2>/dev/null)" 2>/dev/null || true
      echo "SOLEUR_WORKSPACES_LUKS_RESUME_DEGRADED feature=workspaces-luks op=workspaces-luks-resume-degraded unit=$(_vscrub "$u")"
    }
  done
  # inngest-server reconcile — never STOPPED by the freeze (it cannot write $MOUNT), but the redis
  # outage window can crash-loop it into `failed`, which outlives the run. Zero freeze cost: this
  # runs after the mount is back. Only start it if it is not already active (no redundant restart).
  systemctl reset-failed inngest-server.service 2>/dev/null || true
  systemctl is-active --quiet inngest-server.service 2>/dev/null || {
    systemctl start inngest-server.service 2>/dev/null || true
    systemctl is-active --quiet inngest-server.service 2>/dev/null || {
      # NEVER let emit_drift be a path's only channel: it returns 0 silently when the Sentry DSN
      # cannot be resolved, which is exactly the FIRST-cutover case (the DSN EnvironmentFile is
      # installed after the canary). Local evidence first, remote best-effort second.
      emit_drift inngest_server_not_active
      log "WARN: inngest-server.service is not active after reconcile"
      logger -t "$LUKS_LOG_TAG" -- "SOLEUR_WORKSPACES_LUKS_RESUME_DEGRADED feature=workspaces-luks op=workspaces-luks-resume-degraded unit=inngest-server.service host=$(hostname 2>/dev/null)" 2>/dev/null || true
      echo "SOLEUR_WORKSPACES_LUKS_RESUME_DEGRADED feature=workspaces-luks op=workspaces-luks-resume-degraded unit=inngest-server.service"
    }
  }
  # `restart`, not `start`: on a RE-dispatch the timer already exists, and a plain `start` on an
  # already-active unit is a no-op — so the host would keep running the STALE in-memory definition
  # even though `enable --now` runs later with a changed unit file.
  for u in $QUIESCE_TIMERS; do
    systemctl restart "${u}.timer" 2>/dev/null || true
  done
}

# app_canary — the post-restart application probe. TWO checks, because neither alone is sufficient.
#
# 1. /health (public) proves the Node process is listening. It is served by the CUSTOM SERVER at
#    server/index.ts (`parsedUrl.pathname === "/health"`), which intercepts BEFORE Next.js routing —
#    so the middleware.ts:113 CSP exemption never even runs for this path. (The pre-#6588 canary
#    used /api/health, which has no route and therefore falls through to middleware and 307s to
#    /login; asserting == 200 on it would have aborted EVERY otherwise-successful cutover at the
#    very last gate, after the mount was already repointed.)
#
# 2. /internal/readyz is the check that actually certifies THIS cutover. /health returns 200
#    UNCONDITIONALLY ("Always return 200 for load balancer probes" — server/index.ts) and never
#    touches $MOUNT; server/readiness.ts states the invariant explicitly ("/health stays untouched —
#    physically enforcing the 'no mount coupling on /health' invariant"). So /health is the one
#    endpoint in the codebase GUARANTEED not to reflect the volume we just repointed: if the mapper
#    mounts but $MOUNT/workspaces is absent, docker auto-creates an empty bind source, the container
#    comes up with an empty /workspaces, /health returns 200, and the cutover is declared green with
#    every user's source code missing. /internal/readyz asserts workspaces_writable AND
#    workspaces_populated. It is loopback-gated, hence the localhost probe.
app_canary() {
  local health ready
  health="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 https://app.soleur.ai/health || echo 000)"
  [ "$health" = "200" ] || die "app /health=$health (expected 200) after restart"
  ready="$(curl -sS --max-time 20 http://127.0.0.1:3000/internal/readyz 2>/dev/null || echo '')"
  case "$ready" in
    *'"ready":true'*) log "app canary PASSED — /health 200 and /internal/readyz ready=true (workspaces writable + populated)" ;;
    '') emit_drift readyz_unreachable
        die "/internal/readyz returned nothing after restart — cannot certify the repointed volume is actually serving user data. /health alone is a 200-always liveness probe and CANNOT fail on an empty or unmounted \$MOUNT (C13)" ;;
    *)  emit_drift readyz_not_ready
        die "/internal/readyz did not report ready=true after restart — the repointed \$MOUNT is not writable/populated, i.e. the container is serving an EMPTY /workspaces. Response: $(_vscrub "$ready") (C13)" ;;
  esac
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
  # $STAGING MUST be unmounted before the close. Without this, a mapper still mounted at $STAGING
  # makes `cryptsetup close` fail EBUSY — and the `2>/dev/null || true` swallowed it, so rollback
  # remounted the plaintext and reported SUCCESS while leaking the mapper open AND mounted,
  # holding a full divergent copy. That is the repoint-path hazard, on the recovery path where it
  # matters more. Report an EBUSY rather than swallowing it.
  umount "$STAGING" 2>/dev/null || true
  # Guard on existence: `cryptsetup close` on an ALREADY-INACTIVE mapper exits non-zero
  # ("Device workspaces is not active."), so an unguarded emit would fire WL_LEVEL=fatal on a
  # second ROLLBACK=1 dispatch — the most likely operator action after a partial recovery — for
  # a rollback that fully succeeded. A recovery-path signal that cries wolf gets ignored.
  if [ -e "$MAPPER" ]; then
    cryptsetup close "$MAPPER_NAME" || emit_drift rollback_mapper_close_failed
  fi
  # Remount the retained plaintext volume (its by-label / by-id device — never the mapper).
  mount /dev/disk/by-label/workspaces_plain "$MOUNT" 2>/dev/null \
    || mount "$(read_state PLAINTEXT_DEV)" "$MOUNT" 2>/dev/null || true
  docker start "$CONTAINER" 2>/dev/null || true
  # AFTER the remount — resume_writers() itself refuses to start anything if the remount above
  # failed (the `|| true` swallows it), so webhook cannot land on the bare mountpoint directory.
  mountpoint -q "$MOUNT" 2>/dev/null || emit_drift rollback_remount_failed
  resume_writers
  # Disarm HERE too, not only on the success path: an abort that reaches rollback has already
  # restored the host, so leaving the transient timer armed means it fires DEAD_MAN_MIN later and
  # takes a second, unannounced outage — one that now stops inngest-redis as well.
  disarm_dead_man
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

# NOTE: defined ABOVE the sourced-detection guard so rollback() (which disarms after a
# restore) and the freeze test harness can both reach them. Definitions only — arm_dead_man is
# not CALLED until the main body, so sourcing still has no side effect.
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
  # DERIVED from _quiesce_list/QUIESCE_TIMERS, not hardcoded: self-containment constrains the
  # RESULTING string (no external binary at fire time), NOT how the string is built. Hardcoding the
  # units left the one UNATTENDED restore path asymmetric under a QUIESCE_UNITS override — the exact
  # drift _quiesce_list() exists to prevent, on the path nobody is watching.
  local dev u stops="" starts="" tstarts=""
  dev="$(read_state PLAINTEXT_DEV)"
  for u in $(_quiesce_list); do
    stops="${stops}systemctl stop ${u} 2>/dev/null; "
    starts="systemctl reset-failed ${u} 2>/dev/null; systemctl start ${u} 2>/dev/null; ${starts}"  # reverse
  done
  for u in $QUIESCE_TIMERS; do
    stops="${stops}systemctl stop ${u}.timer ${u}.service 2>/dev/null; "
    tstarts="${tstarts}systemctl restart ${u}.timer 2>/dev/null; "
  done
  systemd-run --on-active="${DEAD_MAN_MIN}min" --unit=workspaces-luks-deadman \
    `# umount ${STAGING} BEFORE the close, in lockstep with rollback(): a mapper still mounted at` \
    `# $STAGING makes cryptsetup close fail EBUSY. This is the UNATTENDED restore path, so the` \
    `# swallowed failure leaves a complete DECRYPTED copy of every user's source live at $STAGING` \
    `# through the still-open mapper, indefinitely, with zero telemetry on any channel — the exact` \
    `# at-rest exposure #6588 exists to close, reached by a different door. The next run's stray` \
    `# guard does NOT surface it either (it is a mountpoint, so that guard is skipped). The close` \
    `# keeps its own error visible on the journal rather than 2>/dev/null.` \
    /bin/sh -c "${stops} docker stop -t 30 ${CONTAINER} 2>/dev/null; umount ${MOUNT} 2>/dev/null; umount ${STAGING} 2>/dev/null; cryptsetup close ${MAPPER_NAME} || logger -t ${LUKS_LOG_TAG} -- 'SOLEUR_WORKSPACES_LUKS_DEADMAN feature=workspaces-luks op=workspaces-luks-deadman result=fail reason=mapper_close_failed'; if mount ${dev:-/dev/disk/by-label/workspaces_plain} ${MOUNT}; then docker start ${CONTAINER} 2>/dev/null; ${starts} systemctl reset-failed inngest-server.service 2>/dev/null; systemctl start inngest-server.service 2>/dev/null; ${tstarts} fi" \
    2>/dev/null || true
}
disarm_dead_man() {
  systemctl stop workspaces-luks-deadman.timer 2>/dev/null || true
  systemctl reset-failed workspaces-luks-deadman 2>/dev/null || true
}

# ============================================================================
# Staging-target preparation (#6588) — lay a filesystem INSIDE the mapper, fail-close the
# mount, and ANCHOR every certified path to its intended device.
#
# The 2026-07-19 freeze (run 29695998561) exposed a real defect HERE: this script luksFormat'd
# the device and luksOpen'd the mapper but NEVER ran mkfs, so the mapper held no filesystem and
# `mount "$MAPPER" "$STAGING"` failed with `wrong fs type, bad option, bad superblock`. Under
# `set -uo pipefail` with NO `-e` that failure was SWALLOWED, and the `mkdir -p "$STAGING"`
# immediately above had already created /mnt/data-luks as a plain directory ON THE ROOT DISK.
# Every downstream step then targeted the root disk. The copy succeeded byte-for-byte onto the
# wrong block device; the rsync itemize vocabulary cannot express "correct copy, wrong target".
#
# CORRECTION (#6733, measured 2026-07-20 — run 29706401639). This block previously attributed
# that run's single `.d..t...... ./` C1 diff to the wrong-device copy. **That attribution was
# wrong.** Run 29706401639 was the first real cutover carrying the mkfs fix; the staging target
# was PROVABLY correct (`STAGING_TARGET result=ok`, mapper carries ext4, L1/L2/L5b green) and C1
# emitted the IDENTICAL `.d..t...... ./`. Same diff on the wrong device and on the right one, so
# the diff was never diagnostic of device identity.
#
# The actual cause was `assert_mount_quiesced` (G4): its positive-control probe CREATED and
# unlinked an entry inside $MOUNT, which advances the transfer ROOT's mtime, and it runs at
# `pre-verify` BETWEEN the pass-2 delta rsync and C1. C1 was correct on all five aborts — it
# reported a real perturbation of the source tree, inflicted by this script's own gate.
#
# FIXED BY REMOVING THE PERTURBATION AT SOURCE, not by compensating for it: the probe is now a
# READ-open of the already-required `$MOUNT/workspaces` directory (`exec 9<`), which `lsof +D`
# reports just as it reported the write fd, and which does not move any mtime at all. An
# intermediate attempt bracketed the write with a touch -r save/restore; it was replaced because a
# gate that mutates its subject and then repairs the evidence is still a gate that mutates its
# subject, and every repair path was one more way to fail. Pinned by
# workspaces-luks-verify-root-mtime.test.sh and workspaces-luks-g4-mutation.test.sh. C1 itself is
# byte-unchanged and was NOT narrowed — narrowing it would have silenced the one signal that
# catches a wrong-device copy, which is precisely what the paragraph above describes.
#
# The sibling git-data volume carries the IDENTICAL `mountpoint … || mount …` line
# (cloud-init-git-data.yml:159-170) — but under `set -euo pipefail`, where a failed mount is
# fatal. This script copied the line's SHAPE into a no-`-e` regime, converting a fail-closed
# line into a fail-open one, and dropped the `mkfs.ext4 /dev/mapper/git-data` that makes the
# mount succeed at all. git-data-luks.tf:73-78 documents the mechanism verbatim.
#
# THE SECOND INVARIANT (#6733): a gate that certifies a tree must not PERTURB that tree. G4 held
# the first invariant perfectly — it anchored, it fail-closed, it carried a positive control — and
# still broke every cutover, because certifying quiescence meant writing into the very directory
# whose byte-identity C1 was about to check. Any probe that mutates its subject is measuring
# itself. Both invariants are needed: the first stops a gate certifying the wrong thing, the
# second stops a gate from making the right thing look wrong.
#
# The second invariant has THREE enforcement sites in this file, because it has three channels:
#   1. assert_mount_quiesced's probe is a READ (`exec 9<`), never a create+unlink.
#   2. manifest_of passes --no-optional-locks, so `git status` cannot rewrite .git/index inside
#      $STAGING after verify_byte_identity has already certified it.
#   3. the L3 gates refuse to run when $TMPDIR resolves under $MOUNT, so this script's six mktemp
#      sites cannot perturb the tree either.
# Any future gate added on this path owes the same question: does this WRITE anywhere under $MOUNT
# or $STAGING between the last rsync and C1? If the answer is yes, it belongs somewhere else.
#
# THE INVARIANT: a gate that certifies a path must first anchor that path to its intended
# device. C1, the `du` assert, `git fsck` and the G3 manifest are all pure functions of the two
# STRINGS "$MOUNT" and "$STAGING" — not one anchors either to a block device, so nothing in that
# closure could ever distinguish "right bytes, wrong device".

# _same_dev — do two path-ish strings name the SAME block device?
#
# THIS HELPER CARRIES ITS OWN POSITIVE CONTROL. The naive form
#   [ "$(readlink -f "$1")" = "$(readlink -f "$2")" ]
# FAILS OPEN: if readlink errors or is absent, BOTH substitutions yield "" and "" = "" is TRUE,
# certifying a mount that was never verified. That is verbatim the failure this script already
# names at the G4 straggler assert ("reads 'the probe failed' as 'the mount is clean'"). The
# explicit rc checks plus `[ -b "$b" ]` make the canonicalizer prove it ran against a real
# block device before it may return 0.
_same_dev() {
  local a b
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  a="$(readlink -f -- "$1" 2>/dev/null)" || return 1
  b="$(readlink -f -- "$2" 2>/dev/null)" || return 1
  [ -n "$a" ] && [ -n "$b" ] && [ -b "$b" ] && [ "$a" = "$b" ]
}

# emit_staging_target — the target-preparation marker, on EVERY outcome including success.
# The swallowed mount emitted NOTHING, which is why the failure surfaced as an uninterpretable
# C1 itemize code instead of a named condition. A green run emitting result=ok proves the
# assert EXECUTED (hr-observability-as-plan-quality-gate). Bare `echo` at column 0 + `logger`,
# matching the emit_freeze_holders convention — log() would indent the marker, and the test
# harness routes `logger` to $MARKER_LOG.
emit_staging_target() {
  local result="${1:-fail}" reason="${2:-unspecified}" extra="${3:-}" row
  row="SOLEUR_WORKSPACES_LUKS_STAGING_TARGET feature=workspaces-luks op=workspaces-luks-staging-target result=$(_vscrub "$result") reason=$(_vscrub "$reason") staging=$(_vscrub "$STAGING") mapper=$(_vscrub "$MAPPER") host=$(hostname 2>/dev/null)"
  [ -n "$extra" ] && row="$row $(_vscrub "$extra")"
  echo "$row"; logger -t "$LUKS_LOG_TAG" -- "$row" 2>/dev/null || true
}

# Every die() in prepare_staging_target fires at prepare time — BEFORE the freeze (FREEZE_HELD=1
# is set ~110 lines later), so cleanup()'s rollback condition is NOT met and no rollback runs.
# That is correct: nothing has been unwound. But the message must SAY so, or an operator reaching
# for ROLLBACK=1 after a prepare-time abort umounts the LIVE plaintext volume and takes a
# gratuitous outage.
_PREPARE_ABORT_NOTE="No freeze was held and nothing was unwound: NO rollback is needed and ROLLBACK=1 must NOT be run (it would umount the LIVE plaintext volume at ${MOUNT} and cause a gratuitous outage). Residual state may be an open mapper, possibly mounted at ${STAGING}; both are idempotent on re-run."

prepare_staging_target() {
  local fs_type staging_src mapper_dev mount_src src_b avail_b reused_bytes _capacity_bad
  local _blkid_rc _usable_b _need_b
  local STAGING_FS_REUSED=0   # read by the marker on EVERY path — an assignment confined to the
                              # ext4 arm would abort the first-cutover path under `set -u` with
                              # `unbound variable` and emit NO marker at all.

  mkdir -p "$STAGING" || {
    emit_staging_target fail mkdir_failed
    emit_drift staging_mkdir_failed
    die "cannot create staging mountpoint $STAGING. ${_PREPARE_ABORT_NOTE}"
  }

  # --- Stray guard: DETECT and REFUSE, never delete. Runs in BOTH arms (read-only), so the
  # rehearsal reports the condition honestly. Canonical data lives at $MOUNT; post-repoint
  # $STAGING is unmounted. A non-mountpoint, non-empty $STAGING is therefore a stray root-disk
  # copy — exactly what the 2026-07-19 run left behind. Deletion is a separate, single-purpose
  # PR (it is user data: AP-009).
  if ! mountpoint -q "$STAGING" && [ -n "$(ls -A "$STAGING" 2>/dev/null)" ]; then
    # Carry MAGNITUDE. This die fires on EVERY dispatch — including every dry run — until the
    # stray is remediated, so it is the message the operator sees most, and it has to let them
    # tell "8 workspaces of duplicated user source" apart from "one leftover directory". Same
    # argument the reused_bytes field is built on: a flag with no number gets ignored.
    local stray_b stray_n
    stray_b="$(du -s --block-size=1 "$STAGING" 2>/dev/null | cut -f1)"
    # find -printf, not `ls | grep -c`: a workspace directory name containing a newline would
    # otherwise inflate the count (SC2010). One dot per entry, then count the bytes.
    stray_n="$(find "$STAGING" -mindepth 1 -maxdepth 1 -printf '.' 2>/dev/null | wc -c | tr -dc '0-9')"
    emit_staging_target fail stray_present "stray_bytes=$(_vscrub "${stray_b:-unknown}") stray_entries=$(_vscrub "${stray_n:-unknown}")"
    emit_drift staging_stray_present
    die "$STAGING is a non-mountpoint AND non-empty — a stray plaintext copy is present on the ROOT DISK (${stray_b:-unknown} B across ${stray_n:-unknown} top-level entries). This is a DUPLICATE; the canonical data is at $MOUNT. Refusing to prepare over it — remediate it before any cutover. ${_PREPARE_ABORT_NOTE}"
  fi

  # --- Refuse a re-run after an already-successful cutover. Re-dispatch is the most likely
  # operator action and had NO defined outcome: post-cutover $MOUNT *is* the mapper, so the
  # blkid probe would hit the ext4 reuse arm, $STAGING would not be a mountpoint, and the mapper
  # would be mounted a SECOND time at $STAGING while live at $MOUNT — making $MOUNT and $STAGING
  # the same filesystem and the bulk rsync a source-into-itself copy.
  # Safe in the dry-run arm: with no mapper present _same_dev fails closed and this does not fire.
  mount_src="$(findmnt -no SOURCE "$MOUNT" 2>/dev/null || true)"
  if _same_dev "$mount_src" "$MAPPER"; then
    emit_staging_target fail already_cutover "mount_src=$(_vscrub "$mount_src")"
    emit_drift staging_already_cutover
    die "$MOUNT is ALREADY sourced from $MAPPER — this cutover has already completed; refusing to re-stage onto the live volume. ${_PREPARE_ABORT_NOTE}"
  fi

  # --- DRY_RUN short-circuit, mirroring the rollback()/disarm_dead_man early-return idiom.
  # Everything ABOVE is a read-only assert and runs in both arms. Everything BELOW touches the
  # mapper — which the dry-run arm never opens (the luksOpen call site is gated on DRY_RUN != 1),
  # so asserting `[ -b "$MAPPER" ]` here would abort every rehearsal.
  if [ "$DRY_RUN" = "1" ]; then
    log "(dry-run) would assert mapper->device, mkfs-if-empty, mount $MAPPER at $STAGING, then assert the mount source IS the mapper"
    emit_staging_target dryrun ok
    return 0
  fi

  # --- Mapper preconditions: ANCHOR THE DEVICE BEFORE TRUSTING THE NAME.
  # The three-arm blkid guard at the call site is total over FILESYSTEM TYPES, not over mapper
  # existence or backing device. $MAPPER is only a NAME: luksOpen is skipped when that name
  # merely EXISTS ([ ! -e "$MAPPER" ]), so a stale mapper left open by a prior run and backed by
  # a DIFFERENT container satisfies the guard, and everything downstream — INCLUDING the positive
  # control below — would operate on the wrong container while reporting success. `cryptsetup
  # status` is the only thing that establishes mapper -> device, and it was previously consulted
  # only in the POST-repoint canary: after the freeze, after the copy, after the plaintext was
  # umounted. Anchor it here, pre-freeze, where an abort costs zero downtime.
  [ -b "$MAPPER" ] || {
    emit_staging_target fail mapper_absent
    emit_drift staging_mapper_absent
    die "$MAPPER is not a block device — luksOpen did not produce a mapper; refusing to prepare. ${_PREPARE_ABORT_NOTE}"
  }
  mapper_dev="$(cryptsetup status "$MAPPER_NAME" 2>/dev/null | sed -n 's/^ *device: *//p')"
  _same_dev "$mapper_dev" "$FRESH_DEV" || {
    emit_staging_target fail mapper_wrong_device "mapper_dev=$(_vscrub "${mapper_dev:-<unknown>}") expected=$(_vscrub "$FRESH_DEV")"
    emit_drift staging_mapper_wrong_device
    die "$MAPPER is backed by '${mapper_dev:-<unknown>}', not $FRESH_DEV — a stale mapper from a prior run; refusing to prepare. ${_PREPARE_ABORT_NOTE}"
  }

  # --- mkfs guard: mirror this script's OWN three-arm blkid idiom (the device-side C7 guard at
  # the call site), on the MAPPER. `-s TYPE -o value` (not bare `blkid`, which exits 0 on a
  # partition-table-only device and would SKIP the needed mkfs, reproducing this very bug).
  # `-p` forces a LOW-LEVEL superblock probe bypassing /run/blkid/blkid.tab: a cached entry can
  # report the PREVIOUS type for the same device name after a rollback-and-reformat cycle, and
  # one arm here mkfs's destructively while another refuses destructively — a stale read is
  # wrong in BOTH directions. (`-c /dev/null` is NOT equivalent: it suppresses the cache FILE
  # but still performs a normal lookup.)
  # A FAILED PROBE IS NOT PROOF OF AN EMPTY DEVICE. `|| true` collapsed every blkid failure
  # (rc 4 usage, rc 8 ambivalent, ENOENT, EACCES, EIO, or blkid simply absent from PATH — it
  # lives in /usr/sbin, which this script has been bitten by before) into fs_type="", which
  # takes the DESTRUCTIVE mkfs arm. Concrete loss: a prior run completed the hours-long bulk
  # rsync and died later; the mapper survives open with $STAGING unmounted; a re-dispatch whose
  # blkid fails then mkfs's over the complete good copy. mke2fs's own mounted-device refusal
  # does NOT save us — the mapper is not mounted. rc=2 ("nothing detected") is the ONLY empty
  # that means "no filesystem". This is the same asymmetry this file names at the G4 assert
  # ("reads 'the probe failed' as 'the mount is clean'"), surviving into the one arm that
  # destroys data.
  command -v blkid >/dev/null 2>&1 || {
    emit_staging_target fail blkid_absent
    emit_drift staging_blkid_absent
    die "blkid is not on PATH — cannot discriminate an empty mapper from a populated one; refusing to mkfs blind. ${_PREPARE_ABORT_NOTE}"
  }
  fs_type="$(blkid -p -s TYPE -o value "$MAPPER" 2>/dev/null)"; _blkid_rc=$?
  [ "$_blkid_rc" -eq 0 ] || [ "$_blkid_rc" -eq 2 ] || {
    emit_staging_target fail blkid_probe_failed "rc=${_blkid_rc}"
    emit_drift staging_blkid_probe_failed
    die "blkid -p failed (rc=${_blkid_rc}) on $MAPPER — a failed probe is NOT proof of an empty device; refusing to mkfs. ${_PREPARE_ABORT_NOTE}"
  }
  if [ -z "$fs_type" ]; then
    log "mapper carries NO filesystem — mkfs.ext4 (first cutover)"
    # lazy_*_init=0 finishes inode-table/journal init NOW rather than in a background kernel
    # thread that would compete with the bulk rsync. Paid pre-freeze, outside the freeze budget.
    # On a large volume that write is synchronous, silent and progress-free — say so, or the
    # operator reads a working run as a hang.
    log "mkfs may take several minutes on a large volume (lazy init disabled deliberately) — this is NOT a hang"
    mkfs.ext4 -q -E lazy_itable_init=0,lazy_journal_init=0 "$MAPPER" || {
      emit_staging_target fail mkfs_failed
      emit_drift staging_mkfs_failed
      die "mkfs.ext4 failed on $MAPPER. ${_PREPARE_ABORT_NOTE}"
    }
  elif [ "$fs_type" = "ext4" ]; then
    log "mapper already carries ext4 — no mkfs (idempotent re-run)"
    STAGING_FS_REUSED=1
  else
    # Load-bearing: this arm is what stops a re-run wiping an already-good copy.
    emit_staging_target fail unexpected_fs "fs=$(_vscrub "$fs_type")"
    emit_drift staging_unexpected_fs
    die "$MAPPER carries TYPE=$fs_type (expected empty or ext4) — refusing to mkfs over an unrecognised filesystem. ${_PREPARE_ABORT_NOTE}"
  fi

  # --- Fail-closed mount. Explicit if/then, never `A || B || C` — the unguarded one-liner this
  # replaces is the root enabler of the whole silent-target class
  # (hr-when-a-command-exits-non-zero-or-prints).
  if ! mountpoint -q "$STAGING"; then
    mount "$MAPPER" "$STAGING" || {
      emit_staging_target fail mount_failed
      emit_drift staging_mount_failed
      die "cannot mount $MAPPER at $STAGING. ${_PREPARE_ABORT_NOTE}"
    }
  fi

  # --- POSITIVE CONTROL: assert WHERE THE BYTES GO. Never infer it from a command that was
  # allowed to fail. This is the primary regression guard for the 2026-07-19 defect.
  staging_src="$(findmnt -no SOURCE "$STAGING" 2>/dev/null || true)"
  _same_dev "$staging_src" "$MAPPER" || {
    emit_staging_target fail source_not_mapper "source=$(_vscrub "${staging_src:-<none>}")"
    emit_drift staging_not_mapper
    die "$STAGING is not mounted from $MAPPER (source='${staging_src:-<none>}') — refusing to copy onto an unverified target. ${_PREPARE_ABORT_NOTE}"
  }

  # --- Capacity gate. THIS CHANGE IS WHAT FIRST MAKES ENOSPC REACHABLE: before the fix the
  # copy landed on the root disk (where it evidently fit); now it lands in the mapper, whose
  # usable capacity is the volume MINUS the LUKS2 header (~16-32 MiB data offset) MINUS ext4
  # metadata. A fresh volume sized equal to its plaintext source is therefore STRICTLY SMALLER
  # than that source. The delta rsync is INSIDE the freeze, where an ENOSPC burns an
  # irreversible-freeze approval exactly as the 2026-07-19 run did. Gate here, pre-freeze.
  # Measure the WHOLE MOUNT, in ALLOCATED BLOCKS. Both rsyncs copy "$MOUNT"/ — not
  # "$MOUNT"/workspaces — so gating on the workspaces subtree alone excluded $MOUNT/redis (the
  # AOF this file spends 20 lines quiescing) and anything else living beside it. And
  # --apparent-size sums file SIZES, not allocation: the payload is git repos, i.e. enormous
  # counts of sub-4K loose objects, where block rounding can push real usage well past apparent
  # size. Both errors point the same way — understating the source — so the gate passed and the
  # ENOSPC still landed in the delta rsync INSIDE the freeze, which is the exact outcome this
  # gate exists to prevent.
  src_b="$(du -s --block-size=1 "$MOUNT" 2>/dev/null | cut -f1)"
  avail_b="$(df --output=avail -B1 "$STAGING" 2>/dev/null | tail -1 | tr -dc '0-9')"
  # On the idempotent-resume path the staged copy ALREADY occupies the target, so df reports
  # avail ~= total - src and a bare `avail > src` aborts a COMPLETE, CORRECT staged copy — every
  # retry failing identically, with the only escape being to wipe the copy or reach past the
  # gate. Count the bytes already staged as available-to-us. Computed here (not below) because
  # the gate needs it; the marker reuses the same value.
  reused_bytes=0
  [ "$STAGING_FS_REUSED" = "1" ] && reused_bytes="$(du -s --block-size=1 "$STAGING" 2>/dev/null | cut -f1)"
  case "${reused_bytes:-}" in ''|*[!0-9]*) reused_bytes=0 ;; esac
  # Each operand checked SEPARATELY. A combined "$a|$b" pattern is unreadable and gets the
  # both-empty case wrong (the string is then "|", which an empty-string arm never matches) —
  # and a vacuous pass here is exactly the fail-open shape this whole change exists to remove.
  _capacity_bad=0
  case "$src_b" in ''|*[!0-9]*) _capacity_bad=1 ;; esac
  case "$avail_b" in ''|*[!0-9]*) _capacity_bad=1 ;; esac
  if [ "$_capacity_bad" = "1" ]; then
    emit_staging_target fail capacity_unreadable "src_b=$(_vscrub "${src_b:-<empty>}") avail_b=$(_vscrub "${avail_b:-<empty>}")"
    emit_drift staging_capacity_unreadable
    die "capacity probe produced non-numeric output (src='${src_b:-}' avail='${avail_b:-}') — cannot gate ENOSPC. ${_PREPARE_ABORT_NOTE}"
  fi
  # 5% margin, not a bare `-gt`: ext4 writes metadata DURING the copy, so one byte of slack is
  # not headroom. usable = what df reports free PLUS what an already-staged copy occupies.
  _usable_b=$((avail_b + reused_bytes))
  _need_b=$((src_b + src_b / 20))
  [ "$_usable_b" -gt "$_need_b" ] || {
    emit_staging_target fail insufficient_capacity "src_b=${src_b} avail_b=${avail_b} reused_bytes=${reused_bytes} usable_b=${_usable_b} need_b=${_need_b}"
    emit_drift staging_insufficient_capacity
    die "LUKS target has ${_usable_b} B usable (df avail ${avail_b} + ${reused_bytes} already staged) but the source is ${src_b} B and needs ${_need_b} B with margin — the copy cannot fit; aborting BEFORE the freeze. ${_PREPARE_ABORT_NOTE}"
  }

  # reused_bytes alongside reused=1: the most common retry is "mkfs succeeded, mount failed",
  # where the filesystem is EMPTY and reused=1 fires anyway. Without a byte count the flag cries
  # wolf on its most frequent trigger and gets ignored.
  emit_staging_target ok prepared "fs=$(_vscrub "${fs_type:-none}") reused=${STAGING_FS_REUSED} reused_bytes=$(_vscrub "${reused_bytes:-0}") source=$(_vscrub "$staging_src") avail_b=${avail_b} src_b=${src_b}"
  log "staging target ready: $MAPPER mounted at $STAGING (fs=${fs_type:-created}, reused=${STAGING_FS_REUSED}, avail=${avail_b}B, src=${src_b}B)"
}

# ============================================================================
# CLEAN_STRAY — the stray-copy carve-out (AP-009 DOCUMENTED DEVIATION)
#
# AP-009 ("Never delete user data", constitution.md) is an architecture principle this code
# DEVIATES from, deliberately, in exactly one narrow place. The carve-out is recorded in ADR-119
# "Addendum (2026-07-19): the stray-copy carve-out (CLEAN_STRAY, #6588)".
#
# The deviation is sound ONLY because provenance establishes the target is a duplicate: nothing
# ever wrote to $STAGING except the misdirected rsync of $MOUNT — no service, no mount, no
# container points at it. The canonical copy at $MOUNT is retained and never touched here.
#
# Deliberately NOT folded into prepare_staging_target: that function's contract is
# detect-and-refuse, and its suite pins "no rm" (T4c). Keeping the deletion in a separate
# entrypoint is what lets that invariant stay mechanically enforced for every other arm.
# ============================================================================

# emit_clean_stray — the receipt, on EVERY outcome including refusals and the idempotent no-op.
# Its OWN marker name: SOLEUR_WORKSPACES_LUKS_STAGING_TARGET's result=/reason= vocabulary is
# pinned by the T-series and the record_arm coverage matrix, and overloading it would make a
# user-data deletion indistinguishable from a staging-prep outcome on the operator's only no-SSH
# channel. Bare `echo` at column 0 + `logger`, matching emit_staging_target.
emit_clean_stray() {
  local result="${1:-fail}" reason="${2:-unspecified}" extra="${3:-}" row
  row="SOLEUR_WORKSPACES_LUKS_CLEAN_STRAY feature=workspaces-luks op=workspaces-luks-clean-stray result=$(_vscrub "$result") reason=$(_vscrub "$reason") deviation=AP-009 staging=$(_vscrub "$STAGING") host=$(hostname 2>/dev/null)"
  [ -n "$extra" ] && row="$row $(_vscrub "$extra")"
  echo "$row"; logger -t "$LUKS_LOG_TAG" -- "$row" 2>/dev/null || true
}

# assert_mode_exclusive — refuse ROLLBACK=1 together with CLEAN_STRAY=1. MUST be called BEFORE
# both mode blocks: the ROLLBACK block ends `exit 0`, so a CLEAN_STRAY block after it is
# UNREACHABLE whenever ROLLBACK=1. Without this, an operator who ticks both types the
# delete-user-data token, receives a ROLLBACK instead (umount $MOUNT, cryptsetup close, docker
# stop) on a host where no freeze was held — per _PREPARE_ABORT_NOTE, "a gratuitous outage" — the
# run exits 0, and the stray is still there while the operator believes a deletion succeeded.
# The operator most likely to tick both is exactly the one who just read "the cutover is wedged,
# try the recovery modes."
# shellcheck disable=SC2317  # invoked from the main body, below the sourced-detection guard
assert_mode_exclusive() {
  # Counted, not pairwise. A pairwise ROLLBACK-vs-CLEAN_STRAY test is correct today but silently
  # stops covering the invariant the moment a THIRD mode block lands (CONFIRM_WIPE is already
  # declared and its block is authored in the Phase-5 converge dispatch) — whichever block came
  # first would win by `exit 0`, which is the exact failure this function exists to prevent.
  # Each mode is counted by STRING equality against "1", never by arithmetic on the raw value:
  # these arrive from an operator-supplied .env, and $(( ... + CONFIRM_WIPE )) on a non-numeric
  # value is an evaluation hazard rather than a count.
  local n=0 m
  for m in "${ROLLBACK:-0}" "${CLEAN_STRAY:-0}" "${CONFIRM_WIPE:-0}"; do
    [ "$m" = "1" ] && n=$((n + 1))
  done
  if [ "$n" -gt 1 ]; then
    emit_clean_stray fail clean_stray_mode_conflict "rollback=$(_vscrub "${ROLLBACK:-0}") clean_stray=$(_vscrub "${CLEAN_STRAY:-0}") confirm_wipe=$(_vscrub "${CONFIRM_WIPE:-0}")"
    emit_drift clean_stray_mode_conflict
    die "$n operator modes were dispatched together (rollback=${ROLLBACK:-0} clean_stray=${CLEAN_STRAY:-0} confirm_wipe=${CONFIRM_WIPE:-0}). These are different verbs and the FIRST matching block would silently win via its early exit — performing e.g. a umount/close/restart on a host where no freeze is held while leaving the stray untouched, and reporting green. Re-dispatch with exactly ONE mode ticked."
  fi
}

# clean_stray — remove the stray plaintext copy at $STAGING. The single sanctioned deletion.
# shellcheck disable=SC2317  # invoked from the CLEAN_STRAY mode block, below the sourced guard
clean_stray() {
  local stray_b stray_n mount_src mount_dev staging_dev entry nested_mnt tool
  local missing_n missing_sample
  local -a victims=()
  local -a rel=()
  # The depth at which USER IDENTITY lives under $MOUNT, and therefore the depth the subset
  # check must reach to have any discriminating power. On web-1 the top level is infrastructure
  # (`workspaces/`, `plugins/`, `redis/`, `lost+found`) and per-user trees sit at
  # `workspaces/<id>/` — so a -maxdepth 1 comparison reduces to "does $MOUNT contain a directory
  # named workspaces?", which is TRUE in every reachable state INCLUDING one where the stray
  # holds a user's only surviving copy. Depth 2 is where the check starts asking a real question.
  # Deeper is not better here: per-file churn in a live workspace (build artifacts, .git objects)
  # would make a full-depth check refuse forever, re-creating the wedge this mode exists to clear.
  local SUBSET_DEPTH=2
  step "CLEAN_STRAY — remove the stray plaintext copy at $STAGING (AP-009 documented deviation)"

  # --- Requirement 2, script layer. REFUSE rather than force DRY_RUN=0 the way ROLLBACK does:
  # that silent coercion is precisely what makes ROLLBACK's ungated arm dangerous. dry_run
  # DEFAULTS TO TRUE, so "tick clean_stray, change nothing else" lands here — name the remedy.
  if [ "$DRY_RUN" = "1" ]; then
    emit_clean_stray fail clean_stray_dryrun_conflict
    emit_drift clean_stray_dryrun_conflict
    die "CLEAN_STRAY=1 was dispatched with DRY_RUN=1. This mode deletes user data and has no rehearsal — there is nothing it could safely simulate. Remedy: re-dispatch with dry_run UNTICKED (it defaults to TRUE, so an unchanged form lands here)."
  fi

  # --- Instrument availability, FIRST. Every guard below is a probe, and a probe whose binary is
  # absent returns a falsy rc that reads exactly like "the dangerous condition does not hold".
  # `mountpoint -q` on a missing binary exits 127 -> the `if` is false -> the catastrophic-mode
  # refusal silently does not fire. Refuse to run at all rather than run blind.
  for tool in mountpoint findmnt find stat du; do
    command -v "$tool" >/dev/null 2>&1 || {
      emit_clean_stray fail clean_stray_tool_missing "tool=$(_vscrub "$tool")"
      emit_drift clean_stray_tool_missing
      die "required probe '$tool' is not on PATH — every guard protecting this deletion depends on it. Refusing to delete user data with a blind instrument."
    }
  done

  # --- A SYMLINK $STAGING is refused with its OWN reason. `ls -A` follows a symlink while `find`
  # does not, so without this the run would enumerate nothing, delete nothing, and then die as
  # `clean_stray_incomplete` — blaming a partial removal for what is actually a path-type problem,
  # and doing so identically on every re-dispatch.
  if [ -L "$STAGING" ]; then
    emit_clean_stray fail clean_stray_staging_is_symlink
    emit_drift clean_stray_staging_is_symlink
    die "$STAGING is a SYMLINK, not a directory. Refusing — resolve it and re-dispatch."
  fi

  # --- A MOUNTPOINT $STAGING is the REAL LUKS volume, not a root-disk stray. This is the
  # catastrophic mode: deleting here destroys canonical, not a duplicate. (`mountpoint -q`
  # resolves symlinks, so a symlink-to-the-real-mountpoint is caught here too.)
  if mountpoint -q "$STAGING"; then
    emit_clean_stray fail clean_stray_staging_is_mountpoint
    emit_drift clean_stray_staging_is_mountpoint
    die "$STAGING is a MOUNTPOINT — that is the real LUKS volume, not a stray root-disk copy. Refusing to delete. Unmount it first if a cleanup is genuinely intended."
  fi

  # --- Idempotent re-dispatch is a SUCCESS. Re-dispatch is the most likely operator action
  # after an ambiguous run log, and this file already establishes the principle at rollback()'s
  # mapper guard: "a recovery-path signal that cries wolf gets ignored."
  # `ls` failure must NOT read as "empty" — that would report result=ok on an instrument failure.
  if ! ls -A "$STAGING" >/dev/null 2>&1; then
    emit_clean_stray fail clean_stray_staging_unreadable
    emit_drift clean_stray_staging_unreadable
    die "cannot read $STAGING — refusing to draw any conclusion about its contents."
  fi
  if [ -z "$(ls -A "$STAGING" 2>/dev/null)" ]; then
    emit_clean_stray ok already_clean
    log "$STAGING is already empty — nothing to remove. This is a SUCCESS (idempotent re-dispatch), not a silent skip."
    return 0
  fi

  # --- Canonical must be HEALTHY and DISTINCT before anything is deleted.
  mountpoint -q "$MOUNT" || {
    emit_clean_stray fail clean_stray_mount_unhealthy "mount=$(_vscrub "$MOUNT")"
    emit_drift clean_stray_mount_unhealthy
    die "$MOUNT is not mounted — the canonical copy is not where this deletion assumes it is. Refusing to delete the only other copy of the data."
  }
  mount_src="$(findmnt -no SOURCE "$MOUNT" 2>/dev/null || true)"
  [ -b "$mount_src" ] || {
    emit_clean_stray fail clean_stray_mount_unhealthy "mount_src=$(_vscrub "${mount_src:-none}")"
    emit_drift clean_stray_mount_unhealthy
    die "$MOUNT source is not a block device — refusing to treat an unverified mount as proof that the canonical copy exists."
  }

  # --- Same-FILESYSTEM refusal, via st_dev on the DIRECTORIES themselves.
  # `findmnt -no SOURCE "$STAGING"` cannot serve here: the mountpoint refusal above guarantees
  # $STAGING is NOT a mountpoint, and findmnt matches exact mount targets only — so it returns
  # empty in 100% of reachable states and any _same_dev() built on it is dead code that merely
  # LOOKS like a guard. `stat -c %d` asks the question actually being posed ("do these two paths
  # live on the same filesystem?"), and it answers it for plain directories.
  mount_dev="$(stat -c %d "$MOUNT" 2>/dev/null || true)"
  staging_dev="$(stat -c %d "$STAGING" 2>/dev/null || true)"
  if [ -z "$mount_dev" ] || [ -z "$staging_dev" ]; then
    emit_clean_stray fail clean_stray_stat_failed
    emit_drift clean_stray_stat_failed
    die "could not stat $MOUNT and/or $STAGING — an unreadable device id is NOT proof they are distinct filesystems. Refusing."
  fi
  if [ "$mount_dev" = "$staging_dev" ]; then
    emit_clean_stray fail clean_stray_same_device "dev=$(_vscrub "$staging_dev")"
    emit_drift clean_stray_same_device
    die "$MOUNT and $STAGING are on the SAME filesystem (st_dev=$staging_dev) — what looks like a stray IS canonical, and deleting it would free no root-disk space. Refusing."
  fi

  # --- No mount may live BENEATH $STAGING. Every guard above tests $STAGING itself; without this
  # a bind-mount at e.g. $STAGING/workspaces would be descended into by `rm -rf`, deleting the
  # canonical tree through it and failing only the final rmdir with EBUSY. awk (not `grep -q`)
  # because a pipeline whose consumer exits early takes SIGPIPE under `pipefail` and the
  # non-zero rc would read as "no nested mount".
  nested_mnt="$(findmnt -rno TARGET 2>/dev/null | awk -v s="$STAGING/" 'index($0, s) == 1 { print; exit }')"
  if [ -n "$nested_mnt" ]; then
    emit_clean_stray fail clean_stray_nested_mount "nested=$(_vscrub "$nested_mnt")"
    emit_drift clean_stray_nested_mount
    die "a filesystem is mounted BENEATH $STAGING (at $nested_mnt) — rm -rf would descend through it into live data. Refusing. Unmount it and re-dispatch."
  fi

  # --- Enumerate ONCE. The subset proof and the deletion MUST read the same snapshot: two
  # independent `find` runs let an entry created between them be deleted having never been
  # subset-checked, falsifying the exact premise the check exists to establish.
  # `-print0` / `read -d ''` throughout — this file already establishes (at the stray guard's own
  # magnitude probe) that a workspace directory name may contain a newline, and a line-based read
  # would split such a name into two pseudo-entries that can both spuriously match under $MOUNT.
  while IFS= read -r -d '' entry; do rel+=("$entry"); done < <(find "$STAGING" -mindepth 1 -maxdepth "$SUBSET_DEPTH" -printf '%P\0' 2>/dev/null)

  # An EMPTY enumeration here is INSTRUMENT FAILURE, not an empty directory — the already_clean
  # return above already proved $STAGING is non-empty. A `find` that is non-GNU (no -printf),
  # erroring, or killed must be indistinguishable from "premise FALSIFIED", never from "premise
  # confirmed". The heredoc-with-command-substitution form this replaces discarded find's exit
  # status entirely, so its failure silently passed the check and the deletion proceeded.
  if [ "${#rel[@]}" -eq 0 ]; then
    emit_clean_stray fail clean_stray_enumerate_failed
    emit_drift clean_stray_enumerate_failed
    die "could not enumerate $STAGING — find returned nothing for a directory already proven non-empty. The subset check could not run; refusing to delete on an unverified premise."
  fi

  # --- Subset check: every enumerated relative path in $STAGING must also exist under $MOUNT.
  # The marker carries a COUNT only. The offending NAMES go to the host log + the run log but not
  # to the marker's `extra`, because at $SUBSET_DEPTH those names include per-user workspace ids —
  # publishing them to the drift channel would be a wider audience than the data itself.
  missing_n=0
  missing_sample=""
  for entry in "${rel[@]}"; do
    [ -n "$entry" ] || continue
    [ -e "$MOUNT/$entry" ] && continue
    missing_n=$((missing_n + 1))
    [ "$missing_n" -le 5 ] && missing_sample="$missing_sample [$entry]"
  done
  if [ "$missing_n" -gt 0 ]; then
    emit_clean_stray fail clean_stray_not_subset "unique_count=$(_vscrub "$missing_n") depth=$(_vscrub "$SUBSET_DEPTH")"
    emit_drift clean_stray_not_subset
    die "$STAGING holds $missing_n path(s) (to depth $SUBSET_DEPTH) that $MOUNT does NOT have; first few:${missing_sample}. The duplicate premise this deletion rests on is FALSIFIED — something other than the misdirected rsync wrote here. Refusing. Inspect via the preflight probe before proceeding."
  fi

  # --- Victims are the DEPTH-1 entries of the same snapshot (those with no path separator).
  for entry in "${rel[@]}"; do
    case "$entry" in */*) continue ;; esac
    victims+=("$STAGING/$entry")
  done
  if [ "${#victims[@]}" -eq 0 ]; then
    emit_clean_stray fail clean_stray_enumerate_failed
    emit_drift clean_stray_enumerate_failed
    die "enumerated $STAGING but derived no top-level entries to remove — refusing rather than reporting a vacuous success."
  fi

  # --- The AP-009 banner + magnitude, BEFORE the first rm.
  stray_b="$(du -s --block-size=1 "$STAGING" 2>/dev/null | cut -f1)"
  stray_n="${#victims[@]}"
  log "AP-009 DEVIATION (documented carve-out, ADR-119 Addendum 2026-07-19): about to delete USER DATA — workspace source code — from the ROOT DISK at $STAGING: ${stray_b:-unknown} B across ${stray_n} top-level entries. This is sound only because provenance establishes the copy is a DUPLICATE; the canonical copy at $MOUNT is retained and is not touched."
  # result=START, not ok: `ok` is reserved for TERMINAL outcomes. Emitting ok here left a
  # success-keyed row in the permanent record for runs that went on to fail, and double-counted
  # every successful deletion for any consumer tallying result=ok on this marker.
  emit_clean_stray start deleting "stray_bytes=$(_vscrub "${stray_b:-unknown}") stray_entries=$(_vscrub "$stray_n")"

  # --- The deletion. DOTFILE-INCLUSIVE: `rm -rf "$STAGING"/*` misses .git/.cache, and a workspace
  # tree is full of them — a glob would leave the stray guard correctly still firing after a
  # "successful" run, with the remainder now a strict subset that behaves differently on retry.
  # Removed with a SHELL `rm` rather than `find -exec rm {} +`: -exec invokes the real /bin/rm
  # BINARY, which the test harness's rm() recorder cannot observe, which would make every "no rm
  # was issued" refusal assertion in the suite VACUOUS.
  # $STAGING ITSELF is left in place as an empty directory — the next run's `mkdir -p` and the
  # guard's own non-mountpoint predicate both expect it to exist.
  rm -rf -- "${victims[@]}" || {
    emit_clean_stray fail clean_stray_rm_failed
    emit_drift clean_stray_rm_failed
    die "the removal failed against $STAGING — the stray is partially or wholly intact."
  }

  # --- Post-deletion assertion. A partial removal must be NAMED: the guard would keep refusing
  # and the operator needs to know the cleanup is the reason, not a new stray. An `ls` failure
  # here must not read as "empty" — that would emit result=ok cleaned over an unverified state.
  if ! ls -A "$STAGING" >/dev/null 2>&1; then
    emit_clean_stray fail clean_stray_verify_unreadable
    emit_drift clean_stray_verify_unreadable
    die "cannot re-read $STAGING after the removal — refusing to certify the cleanup succeeded."
  fi
  if [ -n "$(ls -A "$STAGING" 2>/dev/null)" ]; then
    emit_clean_stray fail clean_stray_incomplete
    emit_drift clean_stray_incomplete
    die "$STAGING is STILL non-empty after the removal — the cleanup is incomplete and the stray guard will correctly keep refusing. Re-dispatch, or inspect via the preflight probe."
  fi
  emit_clean_stray ok cleaned "stray_bytes=$(_vscrub "${stray_b:-unknown}") stray_entries=$(_vscrub "${stray_n:-unknown}")"
  log "stray removed: $STAGING is now an empty non-mountpoint directory. The cutover is unwedged — a rehearsal should now run past prepare_staging_target."
}

# Sourced-detection guard: when this file is `source`d (the workspaces-luks-verify.test.sh harness
# obtains verify_byte_identity/emit_verify_diff without running the cutover), return HERE — after all
# functions the test needs are defined, but BEFORE `trap cleanup EXIT` and the main body. An executed
# run (`bash …/workspaces-cutover.sh`, BASH_SOURCE[0]==$0) evaluates this as a no-op and proceeds.
if [ "${BASH_SOURCE[0]:-$0}" != "$0" ]; then return 0 2>/dev/null || true; fi

trap cleanup EXIT


# Mode mutual exclusion — MUST precede BOTH mode blocks. ROLLBACK's block ends `exit 0`, so a
# CLEAN_STRAY block placed after it is unreachable whenever ROLLBACK=1 (see assert_mode_exclusive).
assert_mode_exclusive

# ============================================================================
# ROLLBACK mode — operator recovery entrypoint
# ============================================================================
if [ "$ROLLBACK" = "1" ]; then
  DRY_RUN=0 rollback
  exit 0
fi

# ============================================================================
# CLEAN_STRAY mode — the stray-copy carve-out (AP-009 documented deviation, ADR-119 addendum)
#
# Note the DELIBERATE divergence from ROLLBACK's shape one block above: ROLLBACK force-sets
# `DRY_RUN=0`, defeating rollback()'s own dry-run early-return. clean_stray() REFUSES a DRY_RUN=1
# dispatch instead. Forcing is what makes ROLLBACK reachable — and destructive — from the ungated
# dry_run=true arm; this mode must never inherit that.
# ============================================================================
if [ "$CLEAN_STRAY" = "1" ]; then
  clean_stray
  exit 0
fi

# ============================================================================
# L3 pre-freeze gates (Hypotheses 1-2) — abort BEFORE any freeze
# ============================================================================
step "L3 gates — host reachability + mount preconditions (pre-freeze, zero downtime)"
mountpoint -q "$MOUNT" || die "L3: $MOUNT is not mounted — the data is not where the cutover assumes (Phase 0 STOP + Hetzner rescue crypttab/fstab repair, DP-9 F1)"
# $TMPDIR MUST NOT resolve under $MOUNT (#6733). This script calls `mktemp` at six sites — the
# aws-cli unpack, the escrow probe body, C1's own stdout/stderr capture, ensure_lsof's apt log, and
# G4's three lsof capture files — and every one of them creates AND unlinks a file. If $TMPDIR
# pointed inside $MOUNT, each of those would advance a directory mtime inside the very tree C1
# certifies, re-creating the #6733 abort through a channel the G4 fix does not cover: G4's probe is
# now a pure read, but mktemp is not. Asserted here, ONCE, at the top rather than at six call sites,
# because the property belongs to the environment and not to any one caller.
# `mktemp -u` resolves the full template path WITHOUT creating anything — so this check cannot
# itself perturb the tree it is checking.
case "$(mktemp -u)" in
  "$MOUNT"/*)
    emit_drift tmpdir_under_mount
    die "L3: \$TMPDIR resolves under $MOUNT (mktemp would create '$(mktemp -u)') — every temp file this script creates would perturb a directory inside the tree C1 is about to certify byte-for-byte, and the cutover would safe-abort on a correct copy (#6733). Re-run with TMPDIR pointed outside $MOUNT (no freeze was held; NO rollback is needed and ROLLBACK=1 must NOT be run)"
    ;;
esac
# $MOUNT is the SOURCE OF EVERY BYTE and the path rollback() remounts. Anchoring it only as a
# `log WARN` was a live counterexample to the invariant this file now enforces three functions
# above (a gate that certifies a path must anchor it to a device) — fail-closed here too.
[ -b "$(findmnt -no SOURCE "$MOUNT" 2>/dev/null)" ] \
  || die "L3: $MOUNT source is not a block device — refusing to treat it as the copy source (no freeze was held; NO rollback is needed and ROLLBACK=1 must NOT be run)"

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
# -b, not -e: this must be a BLOCK DEVICE, matching the sibling asserts on $MOUNT's source and
# on $MAPPER. A regular file at this path would otherwise reach luksFormat.
[ -n "$FRESH_DEV" ] && [ -b "$FRESH_DEV" ] || die "WORKSPACES_LUKS_DEV unset, absent, or not a block device — pass the fresh volume by-id device"
# -p here for the same reason as the mapper arm below: this guard's empty arm runs luksFormat, a
# DESTRUCTIVE operation on an operator-supplied device. Reading the /run/blkid/blkid.tab cache
# after a rollback-and-reformat cycle is wrong in both directions. The mapper arm got this
# reasoning; the device arm — which is the more dangerous of the two — was left on the cache.
raw_type="$(blkid -p -s TYPE -o value "$FRESH_DEV" 2>/dev/null || true)"
if [ -z "$raw_type" ]; then
  log "fresh device is RAW (no signature) — luksFormat"
  [ "$DRY_RUN" = "1" ] || printf '%s' "$KEY" | cryptsetup luksFormat --type luks2 --key-file - "$FRESH_DEV" \
    || { emit_drift luksformat_failed; die "luksFormat failed on $FRESH_DEV — refusing to proceed (no freeze was held; NO rollback is needed and ROLLBACK=1 must NOT be run)"; }
elif [ "$raw_type" = "crypto_LUKS" ]; then
  log "fresh device already crypto_LUKS — no format (idempotent)"
else
  die "fresh device carries TYPE=$raw_type (expected raw or crypto_LUKS) — refusing to format a device with a filesystem signature (C7)"
fi
if [ "$DRY_RUN" != "1" ] && [ ! -e "$MAPPER" ]; then
  # Unguarded, a failed open leaves $MAPPER absent — prepare_staging_target would then take the
  # "no filesystem" arm and die as staging_mkfs_failed, a MISLEADING reason on the operator's
  # only no-SSH channel. Name the real failure here.
  printf '%s' "$KEY" | cryptsetup luksOpen --key-file - "$FRESH_DEV" "$MAPPER_NAME" \
    || { emit_drift luksopen_failed; die "luksOpen failed on $FRESH_DEV — refusing to proceed (no freeze was held; NO rollback is needed and ROLLBACK=1 must NOT be run)"; }
fi
prepare_staging_target

# ============================================================================
# Escrow proof (BLOCKING, AFTER prepare — R7/C3) — against the REAL device via the host token path
# ============================================================================
step "escrow proof: luksOpen --test-passphrase against the REAL device (host token path)"

# Load the R2 escrow creds host-side (fail-loud) + ensure the S3 client, then run the DRY_RUN-safe
# reachability probe — in BOTH arms (OUTSIDE the DRY_RUN != 1 gate below), so the rehearsal proves
# the escrow path is usable BEFORE any irreversible freeze. This is what kills the false-green where
# a green dry-run hid an unusable escrow (the gap #6649 fixes).
ensure_aws
# Hoisted here beside ensure_aws (#6588): apt-get inside the freeze window runs with the app down
# and the dead-man ticking, so a held dpkg lock or a slow mirror would burn an irreversible-freeze
# approval. Idempotent — the in-freeze call is a no-op backstop. Both arms, like ensure_aws.
ensure_lsof
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
# --no-optional-locks ON EVERY INVOCATION (#6733) — the SAME invariant as the G4 defect, one gate
# over: a gate that certifies a tree must not WRITE to that tree.
#
# `git status --porcelain` is not read-only. When a file's cached stat data is racily stale, git
# REFRESHES the index and writes it back — .git/index is rewritten, under $root. This function is
# called TWICE: G2 against $MOUNT (harmless, it runs while writers are still live and before any
# copy), and G3 against $STAGING at a call site that runs AFTER verify_byte_identity has already
# certified DST == SRC byte-for-byte. A rewritten .git/index there mutates the destination tree
# immediately after the proof that it matched, silently invalidating that proof. GIT_OPTIONAL_LOCKS=0
# / --no-optional-locks makes git skip the refresh-and-write entirely and report from the index as
# it stands, which is exactly what a manifest reader wants.
#
# Applied UNIFORMLY to all three invocations, not only to `status`. `for-each-ref` does not write
# the index, so two of these three are belt-and-braces — deliberately, so the property is one a
# static test can pin over the WHOLE function ("no bare `git -C` here") rather than a per-subcommand
# judgement call that the next editor has to re-derive and can get wrong in the silent direction.
manifest_of() {  # $1 = root dir
  local root="$1" ws
  for ws in "$root"/workspaces/*/; do
    [ -d "$ws" ] || continue
    echo "WS $(basename "$ws")"
    git --no-optional-locks -C "$ws" for-each-ref --format='REF %(refname) %(objectname)' 2>/dev/null || true
    git --no-optional-locks -C "$ws" for-each-ref --format='CHK %(refname) %(objectname)' 'refs/checkpoints/*' 2>/dev/null || true
    git --no-optional-locks -C "$ws" status --porcelain 2>/dev/null | sed 's/^/DIRTY /' || true
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
  # Herestrings, never `printf … | head`/`| grep`: `head` closes the pipe and SIGPIPEs the producer
  # under `set -o pipefail` — the same fail-open shape the real G4 removed. AC5's static guard is
  # scoped to freeze_writers(), so it cannot see this arm; the discipline has to be manual here.
  DRY_HOLDERS="$(lsof +D "$MOUNT" 2>/dev/null | grep -v '^COMMAND ' || true)"
  DRY_N="$(grep -c . <<<"$DRY_HOLDERS" || true)"
  if [ -n "$DRY_HOLDERS" ]; then
    log "(dry-run) ADVISORY: ${DRY_N} process(es) currently hold $MOUNT."
    log "(dry-run) These are NOT quiesced in this arm (no freeze runs). A REAL freeze stops $(_quiesce_list) plus the $QUIESCE_TIMERS timers first;"
    log "(dry-run) anything still listed AFTER that quiesce is what the fail-closed G4 would abort on."
    while IFS= read -r l; do [ -n "$l" ] && log "  (dry-run) HOLDER $(_vscrub "$l")"; done < <(head -n "$FREEZE_HOLDER_CAP" <<<"$DRY_HOLDERS")
    # Durable channel too — a rehearsal result that lives only in the run log is unanswerable an
    # hour later. The luks-monitor tag is already allowlisted in vector.toml, so this needs no
    # infra change.
    logger -t "$LUKS_LOG_TAG" -- "SOLEUR_WORKSPACES_LUKS_DRYRUN_HOLDER feature=workspaces-luks op=workspaces-luks-dryrun-holder count=${DRY_N} mount=$(_vscrub "$MOUNT") host=$(hostname 2>/dev/null)" 2>/dev/null || true
    echo "SOLEUR_WORKSPACES_LUKS_DRYRUN_HOLDER feature=workspaces-luks op=workspaces-luks-dryrun-holder count=${DRY_N} mount=$(_vscrub "$MOUNT")"
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
  # G4 RE-ASSERT. The freeze-time sample is ~10 minutes stale by now, and it is a point-in-time
  # sample: any writer that started AFTER it is undetected by construction. orphan-reaper is the
  # concrete instance — a 6-hourly root `rm -rf` over $MOUNT/workspaces/*.orphaned-* that, firing
  # between the delta rsync and the verify, makes `rsync --delete --dry-run` emit a `*deleting`
  # line, i.e. the IDENTICAL C1 abort signature as the redis AOF. Re-asserting converts that from a
  # mystery diff into a named holder, and is cheap against the freeze budget.
  assert_mount_quiesced pre-verify
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
  # Fail-closed: a swallowed failure here leaves $MAPPER mounted at $STAGING *and* then at $MOUNT
  # below. The post-repoint assert only checks $MOUNT, so it PASSES; rollback() then swallowed the
  # resulting EBUSY, remounted plaintext and reported success — leaving plaintext live at $MOUNT
  # and a still-open mapper holding a divergent full copy at $STAGING, with no telemetry at all.
  umount "$STAGING" || { emit_drift staging_umount_failed; die "cannot umount $STAGING before the repoint — refusing to mount $MAPPER at $MOUNT while it is still mounted at $STAGING (two live divergent copies); the freeze is held and cleanup() will roll back to the retained plaintext"; }
  # umount MUST succeed — a failed umount (a straggler re-acquired the mount) followed by the mapper
  # mount would STACK the mapper OVER the still-mounted plaintext. findmnt -no SOURCE returns the
  # TOPMOST source (=$MAPPER), so the assert below would PASS while the app writes to the mapper and
  # the plaintext is shadowed underneath (the #5274 stranding, silently). Fail loud instead.
  umount "$MOUNT" || die "umount $MOUNT failed — refusing to stack the mapper over live plaintext (#5274)"
  mountpoint -q "$MOUNT" && die "$MOUNT is STILL a mountpoint after umount — refusing to stack the mapper over it (#5274)"
  mount "$MAPPER" "$MOUNT" \
    || { emit_drift repoint_mount_failed; die "cannot mount $MAPPER at $MOUNT — the repoint did not happen; the freeze is held and cleanup() will roll back to the retained plaintext"; }
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
  # ANCHOR, do not merely probe. Asserting `cryptsetup status` exits 0 proves a mapper exists,
  # not that it is backed by the volume we formatted — the same relational-not-anchored shape
  # this change closes at prepare time, surviving at the one moment it is most expensive: after
  # the freeze, after the copy, after the plaintext has been unmounted. Mirrors the prepare-time
  # anchor. The two diverge if the mapper is closed and reopened against a different device
  # between prepare and repoint (concurrent operator action, or a stale dead-man firing mid-run).
  cryptsetup status "$MAPPER_NAME" >/dev/null 2>&1 || { emit_drift cryptsetup_status_missing; die "cryptsetup status: no mapper->device link"; }
  _canary_mapper_dev="$(cryptsetup status "$MAPPER_NAME" 2>/dev/null | sed -n 's/^ *device: *//p')"
  _same_dev "$_canary_mapper_dev" "$FRESH_DEV" \
    || { emit_drift canary_mapper_wrong_device; die "C13 canary: $MAPPER is backed by '${_canary_mapper_dev:-<unknown>}', not $FRESH_DEV — refusing to certify the repoint"; }
  mountpoint -q "$MOUNT" || { emit_drift not_mounted; die "mountpoint -q $MOUNT failed"; }
  CANARY_OK=1; persist_state CANARY_OK "1:$(cryptsetup luksUUID "$FRESH_DEV")"  # DP-7: run-keyed + header UUID
  log "host canary PASSED — $MOUNT is the LUKS mapper"
fi

step "docker start + resume webhook + app canary (C13)"
if [ "$DRY_RUN" != "1" ]; then
  docker start "$CONTAINER"
  # Restore every unit freeze_writers() quiesced (webhook + inngest-redis) and reconcile
  # inngest-server — AFTER the mapper mount (see resume_writers' mount guard).
  resume_writers
  # app_canary BEFORE disarm_dead_man. CANARY_OK=1 was set by the HOST canary above, so cleanup()
  # will no longer roll back; if the dead-man were disarmed first, an app-level failure here would
  # have ZERO automated recovery — on the one gate that actually proves user-facing health. Keeping
  # the dead-man armed across the canary preserves the unattended backstop for exactly that window.
  app_canary
  # The durable Inngest queue must be up before this run may call itself green. A dead queue behind
  # a green cutover is the "component reports SUCCESS but its downstream effect is absent"
  # anti-pattern — the user's scheduled work silently never fires. Fatal here is SAFE: CANARY_OK=1
  # is already set, so cleanup() will NOT roll back a correct mount over a service-start failure.
  systemctl is-active --quiet inngest-redis.service 2>/dev/null || {
    emit_drift green_run_degraded_queue
    die "inngest-redis.service is not active after a successful repoint — the durable Inngest queue is DOWN and armed reminders would silently never fire. Refusing to report a green cutover. The mount is correct and retained; restart the unit and re-run workspaces-luks-verify.yml."
  }
  disarm_dead_man
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
