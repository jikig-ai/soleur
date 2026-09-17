#!/usr/bin/env bash
# git-data boot-signal poll — the read path for the birth and replace interlocks (#8178).
#
# WHY THIS IS A LIBRARY AND NOT A `run:` BLOCK. If the loop stays inline in the
# workflow, the per-poll line and the whole answered/found accounting sit outside any
# assembly, and the highest-value mutations — feeding the match buffer from stderr,
# suppressing stderr, unconditionalising the per-poll line — have no detector at all.
# That is the "check that cannot fail" class this change exists to end. Here they are
# drivable by tests/scripts/test-git-data-boot-signal-poll.sh, and `max_polls` /
# `interval_s` are parameters so the hermetic suite runs in seconds rather than the ten
# minutes twenty real sleeps would cost.
#
# WHY scripts/lib/ AND NOT tests/scripts/lib/. Two blocking CI hooks are path-scoped:
# scripts/lint-diagnosis-claims.sh (AP-021 — the diagnostic-honesty gate this whole
# change exists to satisfy) walks scripts/ and SKIPS any path matching /tests?/, and
# scripts/lint-workflow-errexit-capture.py (AP-022) scans only .github/workflows. Putting
# the ::error:: arms under tests/ would move them out of both detectors' reach, and
# ADR-149 records that this very poll has already shipped the errexit-capture defect once.
# The `rc=$?` capture stays in the workflow's run: block so AP-022 still sees it; this
# library takes rc as a parameter.
#
# THE STDOUT/STDERR SPLIT IS STRUCTURAL, NOT CONVENTIONAL. git_data_boot_read writes
# stdout and stderr to SEPARATE files, and the row match runs on the stdout file only,
# and only when the read answered. The match buffer therefore cannot receive the
# reader's own error echo — the failure the previous inline comment warned about, where
# betterstack-query.sh echoes the failing query back, that query contains the literal
# `boot_complete`, and a `2>&1` capture reports the boot signal as received on poll 1/20
# over a host that never booted. Because `--fail-with-body` puts an HTTP error's body on
# STDOUT, that buffer is also never echoed on a failed read: it is read only by `wc -c`
# and by bs_read_classify's fixed greps, then dropped.

_gdbsp_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$_gdbsp_dir/betterstack-absence.sh"
# shellcheck source=/dev/null
. "$_gdbsp_dir/betterstack-read-classify.sh"

# git_data_boot_sql <anchor>
# The field-isolated read. A bare-substring --grep would match the shared source's
# inngest rows quoting issue bodies, so the discrimination is on a PARSED FIELD.
#
# THE ANCHOR REPLACES `now() - INTERVAL 2 HOUR`. `host_name` pins the host, not the host
# GENERATION: a replace re-dispatched within the old window would match the DESTROYED
# host's boot_complete and report the new one verified. `dt` is DateTime64(6) and
# emitter-assigned, so the conversion and a skew allowance are both load-bearing.
#
# The s3Cluster arm is REQUIRED, not belt-and-braces: remote() alone is the ~40-minute
# hot window and a once-per-boot marker falls out of it immediately (measured: remote()
# alone rc=0/0 rows against a two-day-old marker; s3Cluster alone rc=0/4 rows).
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
              ORDER BY dt DESC LIMIT 5 FORMAT JSONEachRow
SQL
}

# git_data_boot_read <outfile> <errfile> <anchor_epoch>
# Runs one read. stdout -> outfile, stderr -> errfile, NEVER merged. Returns the
# reader's rc. The caller captures it with `rc=$?` as the first command after the call.
git_data_boot_read() {
  local outfile="$1" errfile="$2" anchor="$3" reader
  # FAIL CLOSED ON A RELATIVE TARGET. Both operands are redirect destinations, so a relative
  # path writes into the CALLER's working directory — inside a workflow that is the repo
  # checkout, which would scatter scratch files into a tree later steps read. The caller
  # always passes mktemp-rooted absolutes; this refuses anything else rather than trusting it.
  # The P1b relative-operand ratchet still counts this site (a static reading cannot prove a
  # positional absolute), and it is baselined with that itemisation rather than silently.
  case "$outfile" in /*) : ;; *) printf 'git_data_boot_read: refusing a relative stdout target: %s\n' "$outfile" >&2; return 78 ;; esac
  case "$errfile" in /*) : ;; *) printf 'git_data_boot_read: refusing a relative stderr target: %s\n' "$errfile" >&2; return 78 ;; esac
  reader="${BETTERSTACK_QUERY_SCRIPT:-scripts/betterstack-query.sh}"
  doppler run -p soleur -c prd_terraform -- bash "$reader" "$(git_data_boot_sql "$anchor")" \
    >"$outfile" 2>"$errfile"
}

# git_data_boot_answered <rowsfile> <rc>
# 0 iff the read ANSWERED: rc=0 AND the body is shaped like an answer.
#
# The second conjunct is not redundant. ClickHouse returns HTTP 200 with a mid-stream
# exception and curl reports success, so a body carrying an error alongside its rows is
# a PARTIAL answer — and a partial answer is not an answer. bs_absence_response_is_answer
# decides that on SHAPE (every non-blank line must start `{"dt":`), never on content:
# a content grep for `exception|Code: [0-9]+` would misread an ordinary application log
# line inside `raw` as a transport fault.
git_data_boot_answered() {
  local rowsfile="$1" rc="$2" body
  [[ "$rc" -eq 0 ]] || return 1
  body="$(cat "$rowsfile" 2>/dev/null || true)"
  bs_absence_response_is_answer "$body"
}

# git_data_boot_row_after_anchor <rowsfile> <anchor_epoch>
# 0 iff the file carries a boot_complete row whose `dt` is STRICTLY AFTER the anchor.
#
# WHY THIS RE-CHECKS WHAT THE SQL ALREADY FILTERS. The `WHERE dt > fromUnixTimestamp(…)`
# clause makes the server do this, so client-side it is defence in depth — and that is
# the point. The anchor is the only thing separating THIS host generation from the
# destroyed one, and delegating it entirely to a string-interpolated SQL predicate means
# a single unsubstituted variable silently widens the window to everything. The whole
# subject of #8178 is a check that could not fail; a guard whose correctness rests on an
# interpolation nobody asserts is the same shape. Cheap, and it makes the property
# testable hermetically instead of only against a live warehouse.
#
# Parsed with a fixed-offset cut rather than a JSON parser: the rows are JSONEachRow and
# `dt` is always the first key, and this must not acquire a `jq` dependency inside a
# workflow step that already has enough moving parts.
git_data_boot_row_after_anchor() {
  local rowsfile="$1" anchor="$2" line dt epoch
  while IFS= read -r line; do
    [[ "$line" == *'"stage":"boot_complete"'* ]] || continue
    dt="${line#*\"dt\":\"}"; dt="${dt%%\"*}"
    [[ -n "$dt" ]] || continue
    # `date` is the only conversion available without adding a dependency; a row whose
    # dt cannot be parsed is NOT counted as qualifying — fail closed, never open.
    epoch="$(date -u -d "${dt%.*} UTC" +%s 2>/dev/null || true)"
    [[ -n "$epoch" ]] || continue
    (( epoch > anchor )) && return 0
  done < "$rowsfile"
  return 1
}

# git_data_boot_poll_decide <found> <final_answered>   (yes/no, yes/no)
# The verdict, as a pure function so a suite can drive every arm.
#
# ANCHORED ON THE FINAL READ, DELIBERATELY. Each read queries the whole window, so
# demanding N clean reads would let a single late 5xx abort an otherwise-verified birth.
# The three outcomes are distinct FACTS with distinct remediations, which is the
# collapse #8178 is about one layer down:
#   received   — the host reported. Proceed.
#   silent     — we could read, and the host has not reported. A HOST fault; the
#                operator goes to the boot chain, not the credentials.
#   unreadable — we could not read at all. A READ-PATH fault; nothing about the host
#                was measured, and saying "the host never reported" here is the
#                misattribution this change removes.
git_data_boot_poll_decide() {
  local found="$1" final_answered="$2"
  if [[ "$found" == "yes" ]]; then printf '%s\n' 'received'; return 0; fi
  if [[ "$final_answered" == "yes" ]]; then printf '%s\n' 'silent'; return 0; fi
  printf '%s\n' 'unreadable'
  return 0
}

# git_data_boot_poll <max_polls> <interval_s> <anchor_epoch>
# The loop. Prints one line per poll plus a terminal VERDICT= line. Returns 0 on a
# verdict, non-zero when it refuses to form one.
git_data_boot_poll() {
  local max_polls="$1" interval_s="$2" anchor="$3"
  local i rc out err found="no" answered_n=0 final_answered="no" last_class="none" verdict
  # EXPORTED for the caller. The verdict is printed for humans AND exported for the
  # workflow, which must branch on `silent` vs `unreadable` to choose between two
  # different remediations — parsing its own log back for a VERDICT= line would be a
  # second, undetectable coupling.
  GIT_DATA_BOOT_ROW=""; GIT_DATA_BOOT_VERDICT=""; GIT_DATA_BOOT_CLASS=""

  # FAIL CLOSED ON AN ABSENT ANCHOR. Without it the predicate would fall back to a
  # wall-clock window, and a replace re-dispatched inside that window matches the
  # DESTROYED host's row — reporting the new host verified on the old one's evidence.
  # That is worse than no check, so it is refused rather than defaulted.
  if [[ -z "${anchor//[[:space:]]/}" ]]; then
    printf '::error::git-data boot poll: BOOT_TRAIL_SINCE is empty — refusing to poll. An unanchored query can match a DESTROYED host generation and report this boot verified on the previous host'"'"'s row. This is a workflow wiring fault, not a host state.\n' >&2
    printf 'VERDICT=refused-no-anchor\n'
    return 2
  fi

  # ONE scratch directory for the whole loop, two fixed names inside it, truncated per
  # iteration. The earlier shape made a fresh mktemp pair per poll and `rm -f`d them, which
  # is 60 create/unlink pairs over a 30-poll budget AND leaves two operands the P1b
  # relative-operand guard cannot prove safe (they are command-substitution results, so no
  # static reading shows them absolute). Truncation removes both the churn and the
  # unprovable operands rather than asserting around them.
  # SOURCED, so it cannot own a trap: this file is SOURCED into the caller's shell (the workflow
  # step and the suite both `source` it), so a `trap ... EXIT` here would REPLACE the
  # caller's own trap rather than add to one — silently disarming whatever cleanup the
  # caller registered. The leak is bounded by construction: exactly ONE directory per
  # git_data_boot_poll call, under TMPDIR, on an ephemeral Actions runner that is
  # destroyed with the job. Explicit `rm -rf "$scratch"` was the other candidate and is
  # rejected: it reintroduces a variable-rooted rm the P1b relative-operand guard cannot
  # prove safe, trading a bounded leak for an unprovable destructive operand. (ADR-129)
  local scratch
  # lint-trap-ownership: ok sourced library — a trap here would REPLACE the caller's; leak is one dir per call on an ephemeral runner (see above, ADR-129)
  scratch="$(mktemp -d -t gdboot.XXXXXXXX)"
  out="$scratch/rows"; err="$scratch/err"

  for (( i = 1; i <= max_polls; i++ )); do
    : > "$out"; : > "$err"
    # `rc=$?` MUST be the first command after the read: `$?` binds to the immediately
    # preceding command, and any convenience line between them silently takes its place.
    set +e
    git_data_boot_read "$out" "$err" "$anchor"
    rc=$?
    set -e

    if git_data_boot_answered "$out" "$rc"; then
      answered_n=$((answered_n + 1)); final_answered="yes"; last_class="none"
      # The match runs on the STDOUT file only, and only on an answered read — this is
      # the structural half of the match-buffer fix.
      if git_data_boot_row_after_anchor "$out" "$anchor"; then
        found="yes"
        # EXPORTED for the caller's per-field invariant assertions (luks_mounted,
        # repo_root, hooks_path, provision, nft_metadata_drop). A global rather than
        # stdout because stdout carries the human-readable poll transcript, and the
        # caller must not have to parse its own log back to find the row.
        GIT_DATA_BOOT_ROW="$(cat "$out" 2>/dev/null || true)"
        printf 'poll %d/%d: answered, boot_complete row present (dt after the run anchor)\n' "$i" "$max_polls"
        break
      fi
      # A boot_complete row that is NOT after the anchor belongs to a PREVIOUS host
      # generation, and saying so is the point — "no row yet" would read as a slow boot
      # when the truth is that the only row present is the destroyed host's.
      if grep -q '"stage":"boot_complete"' "$out" 2>/dev/null; then
        printf 'poll %d/%d: answered, boot_complete row present but NOT after the run anchor — previous host generation, not this boot\n' "$i" "$max_polls"
      else
        printf 'poll %d/%d: answered, no boot_complete row yet\n' "$i" "$max_polls"
      fi
    else
      final_answered="no"
      last_class="$(bs_read_classify "$rc" "$out")"
      # WHAT THE LOG GETS, AND WHAT IT NEVER GETS. rc, the classification, the body's
      # LENGTH and a scrubbed first stderr line — never the body. This repository is
      # PUBLIC and its Actions logs are world-readable, and a ClickHouse auth failure
      # body reads `Code: 516 … <username>: Authentication failed`, i.e. half of a
      # Basic-auth pair. The brief asked for "the response body/status"; the status,
      # the classification and the length deliver the property it wanted — the next
      # occurrence names its own cause from `gh run view` alone — without putting a
      # credential fragment in a public log.
      local body_len err1
      body_len="$(wc -c < "$out" 2>/dev/null | tr -d '[:space:]' || true)"
      err1="$(head -1 "$err" 2>/dev/null | tr -d '\r\n' \
        | sed -E "s/'[^']*'/'<redacted>'/g; s/[A-Za-z0-9.-]*betterstackdata\.com/<host>/g" \
        | cut -c1-200 || true)"
      printf 'poll %d/%d: read FAILED rc=%s class=%s body_bytes=%s stderr: %s\n' \
        "$i" "$max_polls" "$rc" "$last_class" "${body_len:-?}" "${err1:-<none>}"
    fi
    (( i < max_polls )) && [[ "$interval_s" != "0" ]] && sleep "$interval_s"
  done

  verdict="$(git_data_boot_poll_decide "$found" "$final_answered")"
  GIT_DATA_BOOT_VERDICT="$verdict"; GIT_DATA_BOOT_CLASS="$last_class"
  printf 'answered=%d/%d last_class=%s\n' "$answered_n" "$max_polls" "$last_class"
  printf 'VERDICT=%s\n' "$verdict"
  return 0
}
