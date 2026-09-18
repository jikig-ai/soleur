#!/usr/bin/env bash
# git-data boot-signal poll — the read path AND the step logic for the birth and replace
# interlocks (#8178). ADR-149 `## Amendment — 2026-09-17 (#8178)` is the canonical account
# of why; this header only says what each part is for.
#
# WHY THE STEP LOGIC LIVES HERE AND NOT IN THE WORKFLOW. Both git-data jobs run the same
# poll, verdict branching and invariant checks. Inline, they had already drifted inside the
# PR that added them (the replace copy lacked two arms), and nothing could test either copy.
# The workflow now calls git_data_boot_verify, so tests/scripts/test-git-data-boot-signal-poll.sh
# drives exactly what a job runs. The ::error:: text stays under scripts/, which is where
# scripts/lint-diagnosis-claims.sh (AP-021) looks.
#
# THE STDOUT/STDERR SPLIT IS STRUCTURAL. git_data_boot_read writes the reader's stdout and
# stderr to SEPARATE files, and the row match runs on the stdout file only, and only when
# the read answered. `--fail-with-body` puts an HTTP error's body on STDOUT, so that buffer
# is also never echoed on a failed read: it is measured by `wc -c`, classified by
# bs_read_classify's fixed greps, and dropped. The body can carry the query username.

_gdbsp_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/betterstack-absence.sh
. "$_gdbsp_dir/betterstack-absence.sh"
# shellcheck source=scripts/lib/betterstack-read-classify.sh
. "$_gdbsp_dir/betterstack-read-classify.sh"
# shellcheck source=scripts/lib/betterstack-sources.sh
. "$_gdbsp_dir/betterstack-sources.sh"

# Per-read wall-clock cap, seconds, around the WHOLE read: Doppler's own secret fetch and
# the reader's curl (--max-time 60 in betterstack-query.sh). Without it a slow read path can
# eat the job's timeout and the job is cancelled BEFORE it prints a verdict, which is the
# "could not tell" state this change exists to remove. `timeout` exits 124 (137 if it had to
# kill), classified `transport` by bs_read_classify.
#
# 45 < 60 DELIBERATELY, and the consequence is worth stating because it is not obvious: this
# cap ALWAYS binds before the reader's own curl budget, so a read that would have succeeded
# in 46-60 s is never observed as a success — it is cut and classified `transport`. That is
# the intended trade. A healthy read of this table measures ~1-3 s, so 45 s already means the
# read path is badly wrong, and one such read must not consume a third of the poll budget.
# The cost is bounded and fail-closed: `transport` renders as `unreadable`, never as a host
# verdict, so the worst outcome is a birth reported UNVERIFIED — never one wrongly verified.
# Raising this above 60 + Doppler's fetch would make the 46-60 s band reachable, but it also
# multiplies the job's worst-case poll wall clock by 20 — re-price `timeout-minutes` on BOTH
# git-data jobs and the `need` floor in tests/scripts/test-git-data-boot-signal-poll.sh (S19)
# in the same change, or the job starts being cancelled mid-poll again.
GIT_DATA_BOOT_READ_TIMEOUT_S="${GIT_DATA_BOOT_READ_TIMEOUT_S:-45}"

# git_data_boot_sql <anchor>
# The field-isolated read. A bare-substring --grep would match the shared source's
# inngest rows quoting issue bodies, so the discrimination is on PARSED FIELDS.
#
# `dt > fromUnixTimestamp(<anchor>)` bounds the read to THIS host generation (AP-027).
# `dt` is assigned by Better Stack at ingest (the emitter's POST body carries none), so the
# anchor is compared against Better Stack's clock, not the host's.
#
# LIMIT 1, newest first: the caller's invariant checks read exactly one row, so an older
# row can never lend a missing field to a newer one.
#
# The s3Cluster arm is REQUIRED: remote() alone is the ~40-minute hot window, and a
# once-per-boot marker falls out of it quickly.
git_data_boot_sql() {
  local anchor="$1"
  cat <<SQL
              SELECT dt,
                     JSONExtractString(raw,'stage')        AS stage,
                     JSONExtractString(raw,'host_name')    AS host,
                     JSONExtractString(raw,'luks_mounted') AS luks_mounted,
                     JSONExtractString(raw,'repo_root')    AS repo_root,
                     JSONExtractString(raw,'hooks_path')   AS hooks_path,
                     JSONExtractString(raw,'provision')    AS provision,
                     JSONExtractString(raw,'nft_metadata_drop') AS nft_metadata_drop
              FROM (SELECT dt, raw FROM remote(\$BS_TABLE)
                    UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
              WHERE dt > fromUnixTimestamp($anchor)
                AND JSONExtractString(raw,'stage') = 'boot_complete'
                AND JSONExtractString(raw,'host_name') = 'soleur-git-data'
              ORDER BY dt DESC LIMIT 1 FORMAT JSONEachRow
SQL
}

# git_data_boot_read <outfile> <errfile> <anchor_epoch>
# Runs one read. stdout -> outfile, stderr -> errfile, NEVER merged. Returns the
# reader's rc.
#
# THE TABLE IS PINNED HERE, from betterstack-sources.sh, for every caller. git-data ships
# to its own source (#7772); the reader's default is the shared one, which answers with zero
# rows from this host and would report a perfect boot as `silent`.
#
# `--only-secrets` injects only the three query credentials from prd_terraform, so a Doppler
# key named BS_TABLE cannot override the pin above. It is NOT a credential boundary: doppler
# builds the child environment from the parent's, so `env -u` strips the Doppler token and
# the R2 state-backend keys the job exports, which the reader has no use for.
# `--no-exit-on-missing-only-secrets` lets a MISSING query variable reach the reader, whose
# own check reports it as rc 3 (`credentials-absent`); without it doppler exits 1 first,
# which reads as a token fault.
git_data_boot_read() {
  local outfile="$1" errfile="$2" anchor="$3" reader
  # FAIL CLOSED ON A RELATIVE TARGET: both operands are redirect destinations, and a relative
  # path would write into the CALLER's working directory (a workflow's repo checkout).
  case "$outfile" in /*) : ;; *) printf 'git_data_boot_read: refusing a relative stdout target: %s\n' "$outfile" >&2; return 78 ;; esac
  case "$errfile" in /*) : ;; *) printf 'git_data_boot_read: refusing a relative stderr target: %s\n' "$errfile" >&2; return 78 ;; esac
  reader="$(bs_absence_query_script)"
  BS_TABLE="$BS_GIT_DATA_TABLE" BS_TABLE_S3="$BS_GIT_DATA_TABLE_S3" \
    timeout -k 5 "$GIT_DATA_BOOT_READ_TIMEOUT_S" \
    doppler run -p soleur -c prd_terraform \
      --only-secrets BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD \
      --no-exit-on-missing-only-secrets \
      -- env -u DOPPLER_TOKEN -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY \
      bash "$reader" "$(git_data_boot_sql "$anchor")" \
    >"$outfile" 2>"$errfile"
}

# git_data_boot_answered <rowsfile> <rc>
# 0 iff the read ANSWERED: rc=0 AND the body is shaped like an answer. ClickHouse returns
# HTTP 200 with a mid-stream exception and curl reports success, so a body carrying an
# error alongside its rows is a PARTIAL answer, and a partial answer is not an answer.
# bs_absence_response_is_answer decides on SHAPE (every non-blank line starts `{"dt":`).
git_data_boot_answered() {
  local rowsfile="$1" rc="$2" body
  [[ "$rc" -eq 0 ]] || return 1
  body="$(cat "$rowsfile" 2>/dev/null || true)"
  bs_absence_response_is_answer "$body"
}

# git_data_boot_poll_decide <found> <final_answered>   (yes/no, yes/no)
# The verdict, as a pure function so a suite can drive every arm. It rests on the FINAL
# read, and the caller also reports how many reads answered, so "the final read failed after
# 19 answered reads" is never reported as "every read failed".
#   received   — the host reported.
#   silent     — the final read answered and no row from this generation was present.
#   unreadable — the final read did not answer.
git_data_boot_poll_decide() {
  local found="$1" final_answered="$2"
  if [[ "$found" == "yes" ]]; then printf '%s\n' 'received'; return 0; fi
  if [[ "$final_answered" == "yes" ]]; then printf '%s\n' 'silent'; return 0; fi
  printf '%s\n' 'unreadable'
  return 0
}

# git_data_boot_poll <max_polls> <interval_s> <anchor_epoch>
# The loop. Prints one line per poll, a summary line and a terminal VERDICT= line. Returns 0
# on a verdict and 2 when it refuses to form one. Exports, for git_data_boot_verify:
#   GIT_DATA_BOOT_ROW       the matched row (one line), empty unless received
#   GIT_DATA_BOOT_VERDICT   received | silent | unreadable | refused-no-anchor
#   GIT_DATA_BOOT_CLASS     the last failed read's class, `none` if the final read answered
#   GIT_DATA_BOOT_ANSWERED  how many reads answered
#
# It never changes the caller's shell options: the rc of each read is captured with
# `|| rc=$?`, not with `set +e` / `set -e`, which would leave errexit armed in the caller.
git_data_boot_poll() {
  local max_polls="$1" interval_s="$2" anchor="$3"
  local i rc out err found="no" answered_n=0 final_answered="no" last_class="none" verdict
  local scratch body_len err1
  GIT_DATA_BOOT_ROW=""; GIT_DATA_BOOT_VERDICT=""; GIT_DATA_BOOT_CLASS=""; GIT_DATA_BOOT_ANSWERED=0

  # FAIL CLOSED ON A MISSING OR MALFORMED ANCHOR. The anchor is interpolated into SQL, so
  # anything but a 10-digit epoch is a wiring fault. Refusing names it; polling would turn it
  # into a SQL error on every read and report `unreadable`, pointing at the credentials.
  if ! [[ "$anchor" =~ ^[1-9][0-9]{9}$ ]]; then
    printf '::error::git-data boot poll: the run anchor is missing or malformed (got %q) — refusing to poll. An unanchored read can match a DESTROYED host generation and report this boot verified on the previous host'"'"'s row. This is a workflow wiring fault, not a host state.\n' "$anchor" >&2
    GIT_DATA_BOOT_VERDICT="refused-no-anchor"
    printf 'VERDICT=refused-no-anchor\n'
    return 2
  fi

  # ONE scratch directory per call, truncated per iteration. This file is SOURCED, so it
  # cannot own a trap (a `trap … EXIT` here would REPLACE the caller's). The leak is one
  # small directory per call, on an ephemeral runner in the workflow. (ADR-129)
  # lint-trap-ownership: ok sourced library — a trap here would REPLACE the caller's; leak is one dir per call on an ephemeral runner (see above, ADR-129)
  scratch="$(mktemp -d -t gdboot.XXXXXXXX)" || scratch=""
  if [[ -z "$scratch" || ! -d "$scratch" ]]; then
    printf '::error::git-data boot poll: could not create a scratch directory under TMPDIR=%s — refusing to poll. This is a runner fault, not a host state.\n' "${TMPDIR:-/tmp}" >&2
    return 2
  fi
  out="$scratch/rows"; err="$scratch/err"

  for (( i = 1; i <= max_polls; i++ )); do
    : > "$out"; : > "$err"
    rc=0
    git_data_boot_read "$out" "$err" "$anchor" || rc=$?

    if git_data_boot_answered "$out" "$rc"; then
      answered_n=$((answered_n + 1)); final_answered="yes"; last_class="none"
      if grep -q '"stage":"boot_complete"' "$out" 2>/dev/null; then
        found="yes"
        GIT_DATA_BOOT_ROW="$(head -1 "$out" 2>/dev/null || true)"
        printf 'poll %d/%d: answered, boot_complete row present (after the run anchor)\n' "$i" "$max_polls"
        break
      fi
      printf 'poll %d/%d: answered, no boot_complete row yet\n' "$i" "$max_polls"
    else
      final_answered="no"
      last_class="$(bs_read_classify "$rc" "$out")"
      # rc, the class, the body's LENGTH and a scrubbed first stderr line. Never the body:
      # this repository is public, and a ClickHouse auth failure body names the username.
      body_len="$(wc -c < "$out" 2>/dev/null | tr -d '[:space:]' || true)"
      err1="$(bs_read_scrub_err1 "$err")"
      printf 'poll %d/%d: read FAILED rc=%s class=%s body_bytes=%s stderr: %s\n' \
        "$i" "$max_polls" "$rc" "$last_class" "${body_len:-?}" "$err1"
    fi
    if (( i < max_polls )) && [[ "$interval_s" != "0" ]]; then sleep "$interval_s"; fi
  done

  verdict="$(git_data_boot_poll_decide "$found" "$final_answered")"
  GIT_DATA_BOOT_VERDICT="$verdict"; GIT_DATA_BOOT_CLASS="$last_class"; GIT_DATA_BOOT_ANSWERED="$answered_n"
  printf 'answered=%d/%d last_class=%s\n' "$answered_n" "$max_polls" "$last_class"
  printf 'VERDICT=%s\n' "$verdict"
  return 0
}

# git_data_boot_check_invariants <birth|replace> <row>
# Per-field assertions on the ONE matched row. A boot_complete carrying a FALSE assertion is
# worse than none: the bootstrap reached its final stage with an invariant unmet. Checked
# per NAMED FIELD; a bare `\bno\b` would match the word anywhere in the payload.
# nft_metadata_drop is REPORTED, never terminal: an unarmed egress drop is a hardening
# regression, not a dark host, and failing on it would route the operator to destroy a
# healthy host holding every connected user's repositories.
# Returns 1 when a required invariant fails, 0 otherwise.
git_data_boot_check_invariants() {
  local kind="$1" row="$2" f
  for f in luks_mounted repo_root hooks_path provision; do
    if grep -q "\"${f}\":\"no\"" <<<"$row"; then
      echo "::error::boot_complete arrived with ${f}=no — the host is up but an invariant is unmet. Treat this ${kind} as failed."
      return 1
    fi
    if ! grep -q "\"${f}\":\"yes\"" <<<"$row"; then
      echo "::error::boot_complete arrived WITHOUT a ${f} assertion. The emit contract and this reader have drifted; do not treat this ${kind} as verified."
      return 1
    fi
  done
  if grep -q '"nft_metadata_drop":"no"' <<<"$row"; then
    echo "::warning::git-data booted with nft_metadata_drop=no — the metadata-endpoint egress drop did NOT arm. The host is healthy and this ${kind} stands; the hardening control is absent. Check stage:gitdata_nftables_metadata_warn in Sentry for the cause. Re-arming needs a host replace (user_data is ForceNew), which destroys and recreates the host: schedule it, do not run it as a reflex."
  elif ! grep -q '"nft_metadata_drop":"yes"' <<<"$row"; then
    echo "::warning::boot_complete carried no nft_metadata_drop assertion — the emit contract and this reader have drifted. This ${kind} stands; the hardening control's state is UNKNOWN, which is not the same as absent."
  fi
  return 0
}

# _gdb_sentry_order — where a `silent` verdict sends the operator, in order. Every name here
# is a stage tag the host emits (cloud-init-git-data.yml); the query is Sentry, issue search
# host_name:soleur-git-data, since this run's apply.
_gdb_sentry_order() {
  printf '%s' "Read Sentry events for host_name:soleur-git-data timestamped AFTER this run's boot-trail anchor (printed by the 'Stamp boot-trail run anchor' step; events from an earlier host generation predate it), in this order: (1) a stage:betterstack_ingest warning means the host ran and its Better Stack upload failed; (2) a stage:boot_complete event means the host finished booting, either after the final read or with its upload lost — do not replace it; (3) a level:fatal event names the stage that failed; (4) stage:bootcmd_start with no stage:gitdata_runcmd_ok means it stopped in package or file setup, or its runcmd_ok emit was not delivered; (5) no event at all means it died before its network came up, or it has no Sentry DSN."
}

# git_data_boot_verify <birth|replace> <max_polls> <interval_s> <anchor> <apply_outcome>
# The whole step: precondition, poll, verdict, invariants, remediation. Returns 0 only when
# the boot signal was received with every required invariant positive.
#
# THE TWO KINDS DIFFER IN ONE WAY THAT MATTERS: re-dispatch. A birth after a green apply
# cannot be re-dispatched (the gate refuses a zero-create plan). A replace CAN, but every
# replace destroys and recreates the host holding every connected user's repositories, so it
# is never the way to get a second reading. Neither kind's remediation says "re-dispatch" for
# a read-path fault or a silent host.
git_data_boot_verify() {
  local kind="$1" max_polls="$2" interval_s="$3" anchor="$4" apply="${5:-}"
  local prc=0 answered read_note tail
  case "$kind" in
    birth|replace) : ;;
    *) echo "::error::git_data_boot_verify: unknown kind '${kind}' — this is a workflow wiring fault."; return 2 ;;
  esac
  [[ -n "$apply" ]] || apply="unknown"

  if [[ -z "${DOPPLER_TOKEN:-}" ]]; then
    if [[ "$kind" == "birth" ]]; then
      tail="on success do NOT re-dispatch (the gate refuses a zero-create plan) — verify with the runbook's 'After the birth' query; on failure re-dispatch is the normal remedy (the birth is additive)."
    else
      tail="do NOT re-dispatch the replace to get a reading (it destroys and recreates the host) — run the runbook's 'After the birth' query with this run's boot-trail anchor."
    fi
    echo "::error::DOPPLER_TOKEN is not present — the boot signal cannot be read, so this ${kind} CANNOT be verified. Refusing to report success. Fix the repo secret; then, apply outcome ${apply}: ${tail}"
    return 1
  fi

  git_data_boot_poll "$max_polls" "$interval_s" "$anchor" || prc=$?
  if (( prc != 0 )); then
    echo "::error::The boot poll refused to run (rc=${prc}) — see the line above. This says NOTHING about whether the ${kind} host booted; it is a wiring or runner fault. The ${kind} is UNVERIFIED (apply outcome ${apply})."
    return 1
  fi

  answered="${GIT_DATA_BOOT_ANSWERED:-0}"
  case "${GIT_DATA_BOOT_VERDICT:-}" in
    received) : ;;
    silent)
      if [[ "$kind" == "birth" ]]; then
        tail="The apply step's outcome was ${apply}: on success this is the green-apply/dark-host state this interlock exists to catch; on failure, if the server was created this is a partial birth whose host never came up, and if it was not there is no host to check. Do NOT treat this birth as complete; see the runbook's 'If it fails' section."
      elif [[ "$apply" == "success" ]]; then
        tail="The replace's apply succeeded, so the previous host was destroyed and this one has not reported to Better Stack. Do NOT re-dispatch the replace to get another reading: each replace destroys and recreates the host."
      else
        tail="The apply outcome was ${apply}, so whether the previous host was destroyed is NOT measured here: read the apply step's own error and the Hetzner project before any action."
      fi
      echo "::error::No stage:boot_complete from soleur-git-data within the poll budget, and the final read ANSWERED (answered=${answered}/${max_polls}), so this is a statement about the host or its upload path, not the read path. $(_gdb_sentry_order) ${tail}"
      return 1
      ;;
    unreadable)
      if (( answered > 0 )); then
        read_note="The FINAL read failed after ${answered}/${max_polls} earlier reads answered with no boot_complete row"
      else
        read_note="Every read failed (answered=0/${max_polls})"
      fi
      if [[ "$kind" == "birth" ]]; then
        tail="The birth is UNVERIFIED (apply outcome ${apply}): on success do NOT re-dispatch (the gate refuses a zero-create plan) — run the runbook's 'After the birth' query with this run's boot-trail anchor once the read works; on failure re-dispatch once it works."
      else
        tail="The replace is UNVERIFIED (apply outcome ${apply}). Do NOT re-dispatch the replace to get a reading: once the read works, run the runbook's 'After the birth' query (read-only) with this run's boot-trail anchor."
      fi
      echo "::error::${read_note}; last class=${GIT_DATA_BOOT_CLASS:-unknown}. The verdict on the final window is unmeasured, so this says NOTHING about whether the ${kind} host booted — fix the read path the class names, not the host. ${tail}"
      return 1
      ;;
    *)
      echo "::error::The boot poll ended with an unexpected verdict '${GIT_DATA_BOOT_VERDICT:-}' — failing closed; the ${kind} is UNVERIFIED (apply outcome ${apply})."
      return 1
      ;;
  esac

  printf '%s\n' "$GIT_DATA_BOOT_ROW"
  git_data_boot_check_invariants "$kind" "$GIT_DATA_BOOT_ROW" || return 1
  echo "boot signal received: git-data reported boot_complete with luks_mounted/repo_root/hooks_path/provision all positive (${kind}, apply outcome: ${apply})."
  return 0
}
