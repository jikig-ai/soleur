#!/usr/bin/env bash
#
# git-data flag precheck — fail-closed read of GIT_DATA_STORE_ENABLED (#8189 D-3, blocker 1).
#
# Runs as its OWN step of .github/workflows/git-data-cutover.yml, before the SSH bridge and
# before the git-data root key is fetched. It is the only step bound to DOPPLER_TOKEN_PRD (as
# DOPPLER_TOKEN), so the `prd` read token never reaches a process that handles host bytes.
#
# WHY IT EXISTS. The deleted `read_flag` ran `doppler secrets get ... || echo ""` under a token
# scoped to prd_terraform: the scope error became "", and "" read as "flag unset". A read that
# cannot tell "absent" from "could not read" has to stop the run instead.
#
# MEASURED DOPPLER CLI SEMANTICS (v3.75.3, 2026-09-15):
#   doppler secrets get <absent> --plain --no-exit-on-missing-secret -p soleur -c <cfg>
#     -> exit 0, empty stdout
#   the same call WITHOUT --no-exit-on-missing-secret
#     -> exit 1 ("Could not find requested secret")
#   a nonexistent (or unauthorized) config, even WITH the flag
#     -> exit 1
# So with the flag, exit 0 + empty stdout means "absent", and every non-zero exit is a read
# failure (wrong scope, revoked token, network) — never "unset".
#
# SCOPE. A service token reads the config it is bound to. So after a successful flag read the
# SAME token must also read the reserved secrets Doppler injects into every config
# (DOPPLER_PROJECT, DOPPLER_CONFIG — docs.doppler.com/docs/secrets › reserved secrets) as exactly
# `soleur` / `prd`. Without that, a token bound to another config reads the flag as absent and the
# run proceeds as "unset" — the exact defect the deleted read_flag had.
#
# VERDICTS (the only output; the flag value, the reserved values and doppler's stderr are never
# printed — stderr goes to a temp file and is reduced to one fixed reason word):
#   DOPPLER_TOKEN empty      -> verdict=flag_token_absent                       exit 5 (no doppler call)
#   a read exits non-zero    -> verdict=flag_read_failed reason=<word> rc=<n>   exit 5
#        <word>: auth_invalid | forbidden | config_not_found | network | unknown
#   reserved values differ   -> verdict=flag_read_failed reason=scope_mismatch  exit 5
#   exactly `true`           -> verdict=flag_already_true                       exit 5
#   empty                    -> flag=unset                                       exit 0
#   any other value          -> flag=off                                         exit 0
# `true` is compared exactly (no case folding, no trimming): the app enables the store only on
# process.env.GIT_DATA_STORE_ENABLED === "true" (apps/web-platform/server/workspace-resolver.ts).
#
# MODE-AWARE READ (#8211 PR2). `FLAG_MODE` (default proof) changes what flag==true means:
#   proof    -> flag==true refuses verdict=flag_already_true (the store must not be live)
#   flip     -> flag==true is RESUME ARM B, not an error: prints flag=true resume=arm_b, exit 0
#               (a prior flip died after the write; the workflow routes to redeploy+assert)
#   rollback -> flag==true is the EXPECTED entry: prints flag=true; flag!=true exits 0 with
#               verdict-free flag=off + mode=rollback nothing_to_rollback marker
#   unfreeze -> flag value is IRRELEVANT to the sentinel decision: a died-mid-window flip
#               leaves flag==true + freeze held, and unfreeze is exactly that recovery —
#               so unfreeze never refuses on flag==true (reads like proof, prints the value).
#
# PIN_ONLY (review of #10352). snapshot_clear evaluates no wipe predicate but its ssh_config step needs $RUNNER_TEMP/git-data.pin, which only
#   this script writes. pin_only runs the same scope check and the same pin read/validate/write as every other mode, refuses nothing on the
#   flag's value, prints no wipe_variant line, and ends with `git_data_pin=present fp=...` like the others.
#
# WIPE MODES (#10138, design W3 / W7b; A1 2026-10-15). Three more FLAG_MODE values, all for git-data-cutover.yml::wipe.
#   The first stdout line of `wipe` and `wipe_check` is `wipe_variant=flip_chained|separated|none`, chosen ONLY from
#   the flag and the stamp (ADR-239 Amendment 2026-10-15): flip_chained = flag `true` OR a non-empty stamp;
#   separated = flag exactly `false`/unset AND no stamp; none = flag outside the closed set (true|false|unset).
#   wipe        -> flip_chained: three SEPARATE predicates, each with its own verdict word and exit 5, in order:
#                    1 wipe_precondition_flag_not_true   the flag is not exactly `true` (a stamp is present, so `off`/unset refuse)
#                    2 wipe_precondition_stamp_absent    GIT_DATA_LUKS_CUTOVER_AT (prd) is absent
#                      wipe_precondition_stamp_malformed it is non-empty but not ^YYYY-MM-DDTHH:MM:SSZ$ or not a real date
#                    3 wipe_precondition_soak_not_elapsed  now minus the stamp is below WIPE_SOAK_FLOOR_SECONDS
#                                                        (prints floor_days=<n> elapsed_s=<n>)
#                 separated: no predicate here (the run-record scan and the boot_complete predicates are a later step);
#                 none: refuses wipe_precondition_flag_unreadable (a flag value outside true|false|unset is not "off").
#                 an unreadable flag or stamp is a READ failure, not a predicate: flag_read_failed / wipe_stamp_read_failed
#                 reason=<word> rc=<n>. On a flip_chained pass it prints `flag=true mode=wipe` then
#                 `wipe_soak floor_days=7 stamp_epoch=<n> elapsed_s=<n>` and continues with the TOFU / deny-roots / pin work.
#   wipe_check  -> the same, REPORT ONLY: the first failing predicate prints `would_refuse=<word>` (or
#                 `would_refuse=none`) and the run continues and exits 0, so W4-W7 can be exercised before the flip
#                 and the soak. A READ failure still refuses (exit 5): a report must not hide a broken read.
#   wipe_reread -> the W7b read. WIPE_VARIANT (the variant W3 printed) is an EXPECTATION, compared and never a selector;
#                 absent or off-set it refuses `wipe_precondition_variant_changed expected=none`. Expecting flip_chained:
#                 the flag only (prints `flag=true mode=wipe_reread` or refuses wipe_precondition_flag_not_true; no stamp
#                 read). Expecting separated: re-reads flag and stamp, prints `wipe_variant=separated mode=wipe_reread`,
#                 refuses `wipe_precondition_variant_changed expected=separated got=<v>` or flag_unreadable. Never a pin
#                 write, TOFU or deny-roots probe.
# WIPE_SOAK_FLOOR_SECONDS is ONE unconditional constant (ADR-239, runbook "The wipe"): there is deliberately no
# `${VAR:-...}` form, so no environment value, input or variable can lower it. Relaxing it is a reviewed diff of that
# one line plus its pin test, the runbook number and an ADR-239 amendment with a CLO ruling.
#
# WRITE PATH (#8211 PR2 / #8573 seam). When FLAG_WRITE_VALUE is set to `true` or `false`, the
# step writes GIT_DATA_STORE_ENABLED through the dedicated write credential
# DOPPLER_TOKEN_GIT_DATA_FLAG (read/write on `prd`, environment-bound — never
# DOPPLER_TOKEN_WRITE, which is prd_terraform-scoped) and NOTHING ELSE in this file's flow
# runs (bar the STAMP CLEAR below, which only a rollback's false write runs): write mode returns after the read-back, before the pin/TOFU probes. Absence of the
# credential refuses verdict=flag_write_credential_absent (exit 5) BEFORE any remote call.
#   write form  : printf '%s' "$value" | doppler secrets set GIT_DATA_STORE_ENABLED …
#                 >/dev/null — stdin carries the value (never argv), stdout is discarded
#                 (doppler prints the whole config on set)
#   read-back   : the SAME write token re-reads the flag with --no-exit-on-missing-secret and
#                 must return exactly the written value, else verdict=flag_write_readback_failed
#   success     : flag_write=ok value=<written>
#
# STAMP CLEAR (#10297, design-rollback-rehearsal section 6). With FLAG_MODE=rollback and FLAG_WRITE_VALUE=false the write arm first
# clears GIT_DATA_LUKS_CUTOVER_AT, the wipe's 7-day soak anchor, with the SAME write credential (no new binding site):
#   read (--no-exit-on-missing-secret) -> delete (--yes, stdout discarded) -> read back -> then the flag write above.
#   absent already            -> cutover_at=absent (no delete call)        cleared and read back absent -> cutover_at=cleared
#   any step fails or the stamp is still present -> verdict=cutover_at_clear_failed step=<read|delete|readback> reason=<word>, exit 5.
#   <word>: the flag read's classifier (auth_invalid | forbidden | config_not_found | network | unknown), or still_present.
# It runs BEFORE the flag-off write on purpose: a failure then leaves the flag true and the fleet unchanged, so the rollback can be
# re-dispatched. After the write a failure would skip the redeploy of a fleet still running the store, and the re-dispatch would read
# flag!=true -> nothing_to_rollback and never redeploy. The FLIP's flag-on write, and every other mode, never touches the stamp.
# UNVERIFIED: the DELETE permission of DOPPLER_TOKEN_GIT_DATA_FLAG on prd. Until it is read from a real run, the fallback (named in
# the failure message) is R8, an owner-gated delete with a read-back, and a rollback of a STAMPED flip stops here until it is done.
# The stamp value is never printed (it is a date, but the posture is counts and words only).
#
# SANDBOX DENY-ROOTS (#9725). The agent sandbox's tenant denyRead must cover the
# worktree root BEFORE the flag flips — denying only WORKSPACES_ROOT when
# workspacePathForWorkspaceId resolves under WORKTREE_ROOT masks an empty
# directory while every sibling stays readable. This is a source-level probe on
# the checkout (no runtime, no creds): `workspace-resolver.ts` must export
# `workspaceTenantDenyRoots` AND `agent-runner-sandbox-config.ts` must call it.
# One line, like TOFU_ARM:
#   SANDBOX_DENY_ROOTS present   -> both markers found
#   SANDBOX_DENY_ROOTS absent    -> files readable, marker missing (old posture)
#   SANDBOX_DENY_ROOTS unknown   -> files unreadable/missing (never "absent")
# Blocking on FLAG_MODE=flip: anything but `present` refuses
# verdict=sandbox_deny_coverage_{absent,unknown}, because a flip without the
# coverage ships a sandbox that denies nothing real.
#
# WORKTREE ROOT OWNERSHIP (#8211 PR-E). With the flag on, every working tree lives at <WORKTREE_ROOT>/<id>, and the container runs as
# uid 1001 with no mount there, so the IMAGE must create the directory and give it to 1001 or every session fails EACCES at mkdir
# (the flag-on rehearsal, 2026-10-24). A source-level probe on the checkout, like SANDBOX_DENY_ROOTS: the Dockerfile's last stage must
# carry, in RUN instructions before its USER, `mkdir -p <dir>` and `chown [-R] 1001[:1001] <dir>`, where <dir> is the literal default
# workspace-resolver.ts declares (WORKTREE_ROOT_DEFAULT). Whole-line comments are stripped and continuations joined first, so a name
# in a comment is not a hit.
#   WORKTREE_ROOT_WRITABLE present  -> both found, in the final stage, before USER
#   WORKTREE_ROOT_WRITABLE absent   -> files readable, marker missing
#   WORKTREE_ROOT_WRITABLE unknown  -> Dockerfile or resolver unreadable, or the resolver's default unparseable (never "absent")
# Blocking on FLAG_MODE=flip, and on any `true` write: anything but `present` refuses verdict=worktree_root_writable_{absent,unknown}.
# This is the STATIC half. The property that matters is runtime (the directory is writable by uid 1001 inside the RUNNING container, and
# that container reaches git-data), which no GitHub runner can read: it is checked host-side by git-data-cutover.sh MODE=proof
# (probe=container-probe: verdict=worktree_root_not_writable | container_egress_blackhole), which the flip runs before the freeze.
#
# GIT-DATA HOST-KEY PIN (#7226, plan D3). The same step, with the same `prd` token, reads
# GIT_DATA_SSH_HOST_KEY (published by Terraform when git-data is born or replaced) with the same
# --no-exit-on-missing-secret semantics, validates its shape, and writes it to
# $RUNNER_TEMP/git-data.pin for the workflow's "Write git-data ssh_config" step. The raw value is
# never printed: only its SHA256 fingerprint, computed after validation.
#   the read exits non-zero  -> verdict=git_data_host_key_unavailable reason=<word> rc=<n> exit 5
#        <word>: the same classification as the flag read (auth_invalid | forbidden |
#        config_not_found | network | unknown), through the same read_secret / reason_of
#   exit 0 + empty           -> verdict=git_data_host_key_unavailable reason=absent       exit 5
#   not one ED25519 key line -> verdict=git_data_host_key_unavailable reason=invalid      exit 5
#   RUNNER_TEMP unusable     -> verdict=pin_write_failed                                  exit 5
#   valid                    -> git_data_pin=present fp=SHA256:<fingerprint>
# Before the pin read it prints one informational line about the app's unpinned fallback arm:
#   TOFU_ARM present|absent|unknown — whether the file GIT_AUTH_TS_PATH names (default: the
#   checkout's apps/web-platform/server/git-auth.ts) still carries the trust-on-first-use ssh
#   option itself (the accept-new value of the host-key-checking option, matched case-insensitively). The
#   probe keys on the BEHAVIOUR, not on a constant's name: renaming the constant must not flip it
#   to absent. The needle is built by concatenation so this file is not itself a hit for
#   tests/scripts/test-no-tofu-ssh.sh. `present` also raises a ::warning: that arm must be
#   deleted (#5914) before GIT_DATA_STORE_ENABLED is ever set.
set -euo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert
# suite pins every tracked copy byte-identical). Guards the one write below whose operand comes
# from the environment ($RUNNER_TEMP).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

refuse() { # <verdict-detail>
  echo "[git-data-flag-precheck] verdict=$1"
  echo "::error title=git-data-flag-precheck::verdict=$1"
  exit 5
}

# <stderr-file> -> one fixed word. Matched on doppler's own error text; the text is never printed.
reason_of() {
  if grep -qiF 'Invalid Auth token' "$1"; then echo auth_invalid
  elif grep -qiE 'does not have access|forbidden|\b403\b' "$1"; then echo forbidden
  elif grep -qiF 'Could not find requested config' "$1"; then echo config_not_found
  elif grep -qiE 'dial tcp|no such host|connection refused|i/o timeout|timeout|unable to connect|tls handshake|network is unreachable' "$1"; then echo network
  else echo unknown
  fi
}

FLAG_MODE="${FLAG_MODE:-proof}"
case "$FLAG_MODE" in
  proof|flip|rollback|unfreeze|wipe|wipe_check|wipe_reread|pin_only) : ;;
  *) echo "::error title=git-data-flag-precheck::verdict=flag_mode_invalid mode=${FLAG_MODE}"; exit 2 ;;
esac

# The wipe soak floor, seconds (7 days). Assigned unconditionally: an exported WIPE_SOAK_FLOOR_SECONDS is overwritten.
readonly WIPE_SOAK_FLOOR_SECONDS=604800

# --- SANDBOX_DENY_ROOTS detector (#9725) ---
# Markers are code-shaped, not name-mentions: the resolver must define the
# helper AND read the RAW WORKTREE_ROOT (the flag-collapsed form is the
# #9725 deviation — absent); the config must CALL it (a stale import or
# comment mention does not count as coverage). Shared by the write gate and
# the read-side informational arm; defined here because the write arm runs
# before the read probes.
detect_deny_roots() {
  local dir="${SANDBOX_SRC_DIR:-$(dirname "$0")/../server}"
  if [ -r "$dir/workspace-resolver.ts" ] && [ -f "$dir/workspace-resolver.ts" ] \
     && [ -r "$dir/agent-runner-sandbox-config.ts" ] && [ -f "$dir/agent-runner-sandbox-config.ts" ]; then
    # Function-scoped: the RAW env read must be inside the helper body — a
    # flag-collapsed body (calling getWorkspaceWorktreeRoot()) yields absent,
    # while a file-scoped grep would still hit that helper's own env read.
    if grep -qE 'export function workspaceTenantDenyRoots' "$dir/workspace-resolver.ts" \
       && grep -qF 'process.env.WORKTREE_ROOT' \
          < <(sed -n '/export function workspaceTenantDenyRoots/,/^}/p' "$dir/workspace-resolver.ts") \
       && grep -qE '=[[:space:]]*workspaceTenantDenyRoots\(' "$dir/agent-runner-sandbox-config.ts"; then
      echo present
    else
      echo absent
    fi
  else
    echo unknown
  fi
}

# --- WORKTREE_ROOT_WRITABLE detector (#8211 PR-E) ---
# The image must create + chown the resolver's default worktree root (header). Overrides, for the suite only:
# WORKTREE_DOCKERFILE and WORKTREE_RESOLVER (a mutant copy lives outside the tree, so the defaults would read `unknown`).
detect_worktree_root() {
  local df="${WORKTREE_DOCKERFILE:-$(dirname "$0")/../Dockerfile}"
  local rs="${WORKTREE_RESOLVER:-$(dirname "$0")/../server/workspace-resolver.ts}"
  local root
  if [ ! -r "$df" ] || [ ! -f "$df" ] || [ ! -r "$rs" ] || [ ! -f "$rs" ]; then
    echo unknown; return 0
  fi
  root="$(sed -nE 's#^[[:space:]]*const WORKTREE_ROOT_DEFAULT = "(/[A-Za-z0-9/_.-]+)";.*#\1#p' "$rs" | head -n 1)"
  if [ -z "$root" ]; then
    echo unknown; return 0
  fi
  # One logical line per instruction: whole-line comments dropped (Docker drops them inside a continued RUN too), continuations
  # joined. A stage is the span after a FROM; only the LAST stage ships, and the RUNs must precede that stage's USER.
  awk -v root="$root" '
    /^[[:space:]]*#/ { next }
    { line = $0
      if (sub(/\\[[:space:]]*$/, "", line)) { acc = acc line " "; next }
      ins(acc line); acc = "" }
    END { if (acc != "") ins(acc); print ((sm && sc) ? "present" : "absent") }
    function ins(l,   n, cmds, i, f, nf, j) {
      if (l ~ /^[[:space:]]*FROM[[:space:]]/) { sm = 0; sc = 0; user = 0; return }
      if (l ~ /^[[:space:]]*USER[[:space:]]/) { user = 1; return }
      if (l !~ /^[[:space:]]*RUN[[:space:]]/ || user) return
      n = split(l, cmds, /&&|;/)
      for (i = 1; i <= n; i++) {
        nf = split(cmds[i], f, /[[:space:]]+/)
        j = 1; while (j <= nf && f[j] == "") j++
        if (f[j] == "RUN") j++
        if (f[j] == "mkdir" && f[j+1] == "-p" && f[j+2] == root && (j + 3 > nf || f[j+3] == "")) sm = 1
        if (f[j] == "chown") {
          if (f[j+1] == "-R") { j++ }
          if (f[j+1] ~ /^1001(:1001)?$/ && f[j+2] == root && (j + 3 > nf || f[j+3] == "")) sc = 1
        }
      }
    }' "$df"
}

# ---- Write path (#8573): returns before the read probes --------------------------
if [ -n "${FLAG_WRITE_VALUE:-}" ]; then
  case "$FLAG_WRITE_VALUE" in
    true|false) : ;;
    *) echo "::error title=git-data-flag-precheck::verdict=flag_write_value_invalid value=${FLAG_WRITE_VALUE}"; exit 2 ;;
  esac
  # A `true` write (ANY mode — the read-side deny refuse fires only under
  # flip, and the write arm exits before it) must not land on a source tree
  # without the #9725 deny coverage. Refuse unless the markers prove present;
  # `unknown` (unreadable source) fails closed the same way.
  if [ "$FLAG_WRITE_VALUE" = true ]; then
    wr_deny="$(detect_deny_roots)"
    if [ "$wr_deny" != present ]; then
      echo "::error title=git-data-flag-precheck::verdict=sandbox_deny_coverage_${wr_deny} — the sandbox tenant denyRead does not verifiably cover WORKTREE_ROOT; land the #9725 deny-root fix before writing GIT_DATA_STORE_ENABLED=true"
      echo "[git-data-flag-precheck] verdict=sandbox_deny_coverage_${wr_deny}"
      exit 5
    fi
  fi
  # Same posture for the worktree root (#8211 PR-E): a `true` write onto an image that does not own it fails every session at mkdir.
  if [ "${FLAG_WRITE_VALUE}" = true ]; then
    wr_wt="$(detect_worktree_root)"
    if [ "$wr_wt" != present ]; then
      echo "::error title=git-data-flag-precheck::verdict=worktree_root_writable_${wr_wt} — the Dockerfile does not verifiably create and chown the worktree root to uid 1001; land the image fix before writing GIT_DATA_STORE_ENABLED=true"
      echo "[git-data-flag-precheck] verdict=worktree_root_writable_${wr_wt}"
      exit 5
    fi
  fi
  if [ -z "${DOPPLER_TOKEN_GIT_DATA_FLAG:-}" ]; then
    echo "::error title=git-data-flag-precheck::verdict=flag_write_credential_absent — DOPPLER_TOKEN_GIT_DATA_FLAG unset; the #8573 write seam is not provisioned. Never substitute DOPPLER_TOKEN_WRITE (prd_terraform-scoped)."
    echo "[git-data-flag-precheck] verdict=flag_write_credential_absent"
    exit 5
  fi
  ERRF="$(mktemp)" || refuse "flag_write_failed reason=unknown rc=95"
  trap 'rm -f "$ERRF"' EXIT
  # #10297: the rollback arm clears the wipe's soak anchor BEFORE it writes the flag off. See "STAMP CLEAR" in the header.
  if [ "$FLAG_MODE" = rollback ] && [ "$FLAG_WRITE_VALUE" = false ]; then
    clear_fail() { # <step> <reason>
      echo "::error title=git-data-flag-precheck::verdict=cutover_at_clear_failed step=$1 reason=$2 - GIT_DATA_LUKS_CUTOVER_AT (the wipe soak anchor) is not confirmed cleared, so GIT_DATA_STORE_ENABLED was NOT written and the fleet is unchanged. A transient read or network failure (reason=network) is re-dispatched as it is; otherwise the fallback is R8: an owner-gated delete of GIT_DATA_LUKS_CUTOVER_AT with a read-back (design-rollback-rehearsal section 6; runbook Verdict map row \"The rollback could not clear the wipe soak anchor\"), then re-dispatch mode=rollback. The DELETE permission of DOPPLER_TOKEN_GIT_DATA_FLAG on prd is unverified."
      echo "[git-data-flag-precheck] verdict=cutover_at_clear_failed step=$1 reason=$2"
      exit 5
    }
    # The stamp VALUE is never printed; every call below carries the write token and the values go to variables only.
    cur_rc=0
    cur="$(DOPPLER_TOKEN="$DOPPLER_TOKEN_GIT_DATA_FLAG" doppler secrets get GIT_DATA_LUKS_CUTOVER_AT --plain --no-exit-on-missing-secret -p soleur -c prd 2>"$ERRF")" || cur_rc=$?
    [ "$cur_rc" -eq 0 ] || clear_fail read "$(reason_of "$ERRF")"
    if [ -n "$cur" ]; then
      if ! DOPPLER_TOKEN="$DOPPLER_TOKEN_GIT_DATA_FLAG" doppler secrets delete GIT_DATA_LUKS_CUTOVER_AT -p soleur -c prd --yes >/dev/null 2>"$ERRF"; then
        clear_fail delete "$(reason_of "$ERRF")"
      fi
      cur_rc=0
      cur="$(DOPPLER_TOKEN="$DOPPLER_TOKEN_GIT_DATA_FLAG" doppler secrets get GIT_DATA_LUKS_CUTOVER_AT --plain --no-exit-on-missing-secret -p soleur -c prd 2>"$ERRF")" || cur_rc=$?
      [ "$cur_rc" -eq 0 ] || clear_fail readback "$(reason_of "$ERRF")"
      [ -z "$cur" ] || clear_fail readback still_present
      echo "cutover_at=cleared"
    else
      echo "cutover_at=absent"
    fi
  fi
  # stdin carries the value (never argv); stdout discarded (doppler echoes the config).
  if ! printf '%s' "$FLAG_WRITE_VALUE" | DOPPLER_TOKEN="$DOPPLER_TOKEN_GIT_DATA_FLAG" \
        doppler secrets set GIT_DATA_STORE_ENABLED -p soleur -c prd >/dev/null 2>"$ERRF"; then
    echo "::error title=git-data-flag-precheck::verdict=flag_write_failed reason=$(reason_of "$ERRF")"
    echo "[git-data-flag-precheck] verdict=flag_write_failed"
    exit 5
  fi
  # Fail-closed read-back with the same credential — the write is not proven until read.
  rb="$(DOPPLER_TOKEN="$DOPPLER_TOKEN_GIT_DATA_FLAG" doppler secrets get GIT_DATA_STORE_ENABLED --plain --no-exit-on-missing-secret -p soleur -c prd 2>"$ERRF")" || {
    echo "::error title=git-data-flag-precheck::verdict=flag_write_readback_failed reason=$(reason_of "$ERRF")"
    echo "[git-data-flag-precheck] verdict=flag_write_readback_failed"
    exit 5
  }
  if [ "$rb" != "$FLAG_WRITE_VALUE" ]; then
    echo "::error title=git-data-flag-precheck::verdict=flag_write_readback_failed reason=value_mismatch"
    echo "[git-data-flag-precheck] verdict=flag_write_readback_failed reason=value_mismatch"
    exit 5
  fi
  echo "flag_write=ok value=${FLAG_WRITE_VALUE}"
  exit 0
fi

if [ -z "${DOPPLER_TOKEN:-}" ]; then
  refuse flag_token_absent
fi

ERRF="$(mktemp)" || refuse "flag_read_failed reason=unknown rc=95"
trap 'rm -f "$ERRF"' EXIT

# read_secret <NAME> <failure-verdict> [extra-flag] -> sets VAL; on a non-zero exit refuses with
# "<failure-verdict> reason=<word> rc=<n>", so every read in this file classifies its failure the
# same way.
VAL=""
read_secret() {
  local rc=0
  : > "$ERRF"
  VAL="$(doppler secrets get "$1" --plain ${3:+"$3"} -p soleur -c prd 2>"$ERRF")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    refuse "$2 reason=$(reason_of "$ERRF") rc=${rc}"
  fi
}

read_secret GIT_DATA_STORE_ENABLED flag_read_failed --no-exit-on-missing-secret
flag="$VAL"
read_secret DOPPLER_PROJECT flag_read_failed
project="$VAL"
read_secret DOPPLER_CONFIG flag_read_failed
config="$VAL"
if [ "$project" != soleur ] || [ "$config" != prd ]; then
  refuse "flag_read_failed reason=scope_mismatch"
fi

# ---- Wipe modes (#10138): predicates before the generic mode-aware flag read ----------------------
# A1 (ADR-239 Amendment 2026-10-15): two variants, chosen ONLY from the two reads below (the flag and the stamp),
# never from an input, an environment value or a flag of this script's own.
#   flip_chained  the flag reads `true`, OR the stamp is non-empty (valid or malformed): the original gate.
#   separated     the flag is read successfully as exactly `false` or unset, AND the stamp is absent.
#   none          the flag is outside the closed set (true|false|unset) and the stamp is absent.
# A garbage stamp counts as PRESENT, so it can never reach `separated`. The run-record scan and the boot_complete
# predicates of `separated` live in a later workflow step (they need W4's server `created` and W5's row).
CLS_STAMP_STATE=""; CLS_STAMP_EPOCH=""
classify_stamp_state() { # sets CLS_STAMP_STATE=absent|valid|malformed and CLS_STAMP_EPOCH
  CLS_STAMP_EPOCH=""
  if [ -z "$1" ]; then
    CLS_STAMP_STATE=absent
  elif [[ $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
       && CLS_STAMP_EPOCH="$(date -u -d "$1" +%s 2>/dev/null)" && [[ $CLS_STAMP_EPOCH =~ ^[0-9]+$ ]]; then
    CLS_STAMP_STATE=valid
  else
    CLS_STAMP_EPOCH=""; CLS_STAMP_STATE=malformed
  fi
}
select_variant() { # <flag> <stamp-state> -> prints flip_chained|separated|none
  if [ "$1" = true ] || [ "$2" != absent ]; then echo flip_chained
  elif [ -z "$1" ] || [ "$1" = false ]; then echo separated
  else echo none
  fi
}
if [ "$FLAG_MODE" = wipe_reread ]; then
  # W7b: re-assert the variant W3 printed. WIPE_VARIANT is an EXPECTATION that is compared, never a selector;
  # an absent or off-set value refuses (fail closed).
  case "${WIPE_VARIANT:-}" in
    flip_chained)
      # Unchanged contract: the flag only. No stamp read, no pin write, no TOFU, no deny-roots probe.
      if [ "$flag" != true ]; then
        refuse wipe_precondition_flag_not_true
      fi
      echo "flag=true mode=wipe_reread"
      exit 0
      ;;
    separated)
      read_secret GIT_DATA_LUKS_CUTOVER_AT wipe_stamp_read_failed --no-exit-on-missing-secret
      classify_stamp_state "$VAL"
      got="$(select_variant "$flag" "$CLS_STAMP_STATE")"
      if [ "$got" = none ]; then
        refuse wipe_precondition_flag_unreadable
      fi
      if [ "$got" != separated ]; then
        refuse "wipe_precondition_variant_changed expected=separated got=${got}"
      fi
      echo "wipe_variant=separated mode=wipe_reread"
      exit 0
      ;;
    *)
      refuse "wipe_precondition_variant_changed expected=none"
      ;;
  esac
fi
if [ "$FLAG_MODE" = wipe ] || [ "$FLAG_MODE" = wipe_check ]; then
  # Both reads are UNCONDITIONAL: the variant is a function of the flag AND the stamp.
  read_secret GIT_DATA_LUKS_CUTOVER_AT wipe_stamp_read_failed --no-exit-on-missing-secret
  stamp="$VAL"
  classify_stamp_state "$stamp"
  stamp_epoch="$CLS_STAMP_EPOCH"
  wipe_variant="$(select_variant "$flag" "$CLS_STAMP_STATE")"
  echo "wipe_variant=${wipe_variant}"
  wipe_word=""; elapsed_s=""
  case "$wipe_variant" in
    none)
      wipe_word=wipe_precondition_flag_unreadable ;;
    flip_chained)
      # Three SEPARATE predicates, each with its own word (the original W3 gate, unchanged).
      if [ "$flag" != true ]; then
        wipe_word=wipe_precondition_flag_not_true
      fi
      if [ -z "$wipe_word" ]; then
        case "$CLS_STAMP_STATE" in
          absent)    wipe_word=wipe_precondition_stamp_absent ;;
          malformed) wipe_word=wipe_precondition_stamp_malformed ;;
        esac
      fi
      if [ "$CLS_STAMP_STATE" = valid ]; then
        elapsed_s=$(( $(date -u +%s) - stamp_epoch ))
        if [ -z "$wipe_word" ] && [ "$elapsed_s" -lt "$WIPE_SOAK_FLOOR_SECONDS" ]; then
          wipe_word=wipe_precondition_soak_not_elapsed
        fi
      fi
      ;;
    separated) : ;;  # no precheck predicate: the scan and the boot_complete predicates are a later step
  esac
  floor_days=$(( WIPE_SOAK_FLOOR_SECONDS / 86400 ))
  if [ "$FLAG_MODE" = wipe ]; then
    case "$wipe_word" in
      "") : ;;
      wipe_precondition_soak_not_elapsed) refuse "wipe_precondition_soak_not_elapsed floor_days=${floor_days} elapsed_s=${elapsed_s}" ;;
      *) refuse "$wipe_word" ;;
    esac
  fi
  if [ "$flag" = true ]; then echo "flag=true mode=${FLAG_MODE}"; fi
  if [ -n "$stamp_epoch" ]; then
    echo "wipe_soak floor_days=${floor_days} stamp_epoch=${stamp_epoch} elapsed_s=${elapsed_s}"
  fi
  if [ "$FLAG_MODE" = wipe_check ]; then
    echo "would_refuse=${wipe_word:-none}"
  fi
fi

# Mode-aware flag read (#8211 PR2): flag==true is a refusal only in proof; on flip it is
# resume arm B (a prior flip died after the write — the workflow re-runs redeploy+assert);
# on rollback it is the expected entry.
if [ "$flag" = true ]; then
  case "$FLAG_MODE" in
    proof) refuse flag_already_true ;;
    flip)
      echo "flag=true resume=arm_b"
      # fall through to the pin/TOFU probes — a resumed flip still needs the pin file
      ;;
    rollback|unfreeze)
      echo "flag=true mode=${FLAG_MODE}"
      ;;
    wipe|wipe_check) : ;;  # the wipe block above already printed the mode line
    pin_only) : ;;  # no predicate: the flag value is irrelevant, only the pin below is wanted
  esac
fi

# --- TOFU_ARM (informational) ---
GIT_AUTH_TS="${GIT_AUTH_TS_PATH:-$(dirname "$0")/../server/git-auth.ts}"
if [ ! -r "$GIT_AUTH_TS" ] || [ ! -f "$GIT_AUTH_TS" ]; then
  echo "TOFU_ARM unknown"
elif grep -qiF "StrictHostKeyChecking=accept-""new" "$GIT_AUTH_TS"; then
  echo "TOFU_ARM present"
  echo "::warning title=git-data-flag-precheck::TOFU_ARM present - the app still carries the unpinned git-data fallback (#5914); it must be deleted before GIT_DATA_STORE_ENABLED is ever set"
else
  echo "TOFU_ARM absent"
fi

# --- SANDBOX_DENY_ROOTS (#9725) ---
deny_state="$(detect_deny_roots)"
echo "SANDBOX_DENY_ROOTS $deny_state"
if [ "$FLAG_MODE" = flip ] && [ "$deny_state" != present ]; then
  refuse "sandbox_deny_coverage_${deny_state} — the sandbox tenant denyRead does not verifiably cover WORKTREE_ROOT; land the #9725 deny-root fix before flipping GIT_DATA_STORE_ENABLED"
fi

# --- WORKTREE_ROOT_WRITABLE (#8211 PR-E) ---
wt_state="$(detect_worktree_root)"
echo "WORKTREE_ROOT_WRITABLE $wt_state"
if [ "${FLAG_MODE}" = flip ] && [ "$wt_state" != present ]; then
  refuse "worktree_root_writable_${wt_state} — the Dockerfile does not verifiably create and chown the worktree root to uid 1001, so every session would fail EACCES at mkdir; land the image fix before flipping GIT_DATA_STORE_ENABLED"
fi

# --- git-data host-key pin ---
# twin: .github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh (ED25519 arm);
# apps/web-platform/server/git-data-replication.ts (resolveGitDataHostKeyPin);
# apps/web-platform/infra/modules/git-data-userdata/variables.tf (host_ssh_ed25519_public_key)
PIN_RE='^ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+/]{43}$'
read_secret GIT_DATA_SSH_HOST_KEY git_data_host_key_unavailable --no-exit-on-missing-secret
pin="$VAL"
if [ -z "$pin" ]; then
  refuse "git_data_host_key_unavailable reason=absent"
fi
# $PIN_RE unquoted: a quoted right-hand side is a literal string match, not a regex.
if ! [[ $pin =~ $PIN_RE ]]; then
  refuse "git_data_host_key_unavailable reason=invalid"
fi
PIN_OUT="${RUNNER_TEMP:-}/git-data.pin"
if [ -z "${RUNNER_TEMP:-}" ] || ! [[ $PIN_OUT =~ ^/[A-Za-z0-9/_.-]+$ ]]; then
  refuse pin_write_failed
fi
# The regex above already refuses a relative or dot-dot path; the canonical guard is the
# statement plugins/soleur/test/fixture-relative-assert.test.sh can SEE on the write's operand.
assert_fixture_dir "$PIN_OUT"
rm -f "$PIN_OUT" 2>/dev/null || true
if ! printf '%s\n' "$pin" > "$PIN_OUT"; then
  refuse pin_write_failed
fi
fp="$(ssh-keygen -lf "$PIN_OUT" 2>/dev/null | awk '{print $2}')" || fp=""
case "$fp" in
  SHA256:*) : ;;
  *) rm -f "$PIN_OUT"; refuse "git_data_host_key_unavailable reason=invalid" ;;
esac
chmod 0444 "$PIN_OUT" || refuse pin_write_failed
echo "git_data_pin=present fp=${fp}"

case "$FLAG_MODE:$flag" in
  *:true) : ;;  # the mode-aware branch above already printed flag=true
  rollback:*)
    # rollback on a flag that is not true: nothing to take off. Not a refusal — the desired
    # post-state (flag off) already holds; the workflow exits 0 on this marker.
    echo "flag=off mode=rollback verdict=nothing_to_rollback" ;;
  *:) echo "flag=unset" ;;   # flag empty
  *) echo "flag=off" ;;
esac
exit 0
