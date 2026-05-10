---
title: "Shared log-rotation primitive for .claude/.*.jsonl telemetry sinks"
issue: 3508
type: refactor
classification: cross-cutting-refactor
branch: feat-one-shot-3508-shared-log-rotation
related_pr: 3495
related_issues: [3122, 3494]
requires_cpo_signoff: false
deepened_at: 2026-05-10
---

# Plan: Shared Log Rotation Primitive for `.claude/.*.jsonl` Telemetry Sinks

## Enhancement Summary

**Deepened on:** 2026-05-10
**Sections enhanced:** Phase 1 (rotation strategy correction), Phase 2 (call-site invariant), Sharp Edges (concurrency model), Tests (T6 hardening), Risks (race-window analysis).

### Key Improvements

1. **Reversed the atomic-rename strategy.** Initial draft prescribed `mv $active → $archive.tmp; : > $active` inside the flock. Concurrency analysis (below) shows this races against open-but-not-yet-locked writers because flock advisories follow the **inode**, not the path — a writer that opens `>>$file` between the rotator's `mv` and the writer's flock acquire ends up locking a DIFFERENT inode (the freshly-created post-truncate file) than the rotator's. The plan now adopts the proven `cat → archive` + truncate-in-place pattern from `rule-metrics-aggregate.sh:291-295`. Atomic-rename is the wrong primitive when readers/writers identify the file by **path** (open-on-append) rather than by **fd** (passed across processes).
2. **Pre-check + lock + re-check (TOCTOU defense).** Size/age check happens BEFORE acquiring the flock (cheap path) AND inside the flock (race defense). A writer that rotated in the interval is observed inside the lock; the second writer skips and proceeds.
3. **Source-not-exec confirmed correct.** Sourcing keeps the rotator in the same shell process — same flock fd visibility, no fork cost. Verified against the precedent at `rule-metrics-aggregate.sh:266-298` (which is itself sourced into a shared shell context).
4. **flock(1) flag verification.** Verified locally: `flock -w 5 -x 9` is the canonical "exclusive, 5s timeout, fd 9" form — the same form used by the four existing emitters. Default exit code on timeout is 1; we gate the rotator's exit on `|| true` so timeout is treated as "skip this round" rather than failure.
5. **shellcheck local verification confirmed.** `shellcheck 0.10.0` is installed at `/home/jean/.local/bin/shellcheck`; the AC step "shellcheck clean" is concretely runnable.
6. **GNU-coreutils-vs-uutils stat compatibility.** Local `stat` is `uutils-coreutils 0.2.2`. Verified `stat -c "%s %Y"` produces `<size> <mtime-epoch>` on both GNU and uutils — the helper uses this form.

### New Considerations Discovered

- **Open-for-append flock semantics are inode-bound; path-rename invalidates the lock target.** Now documented in Sharp Edges with a worked example.
- **PR #3495 has not merged at plan time.** `gh pr view 3495 --json state` returned `OPEN`. The Phase 0 reconcile is load-bearing — Phase 2 wiring of `agent-token-tee.sh` is a no-op until #3495 lands.
- **`.claude/.session-tokens.jsonl` does not yet appear in main's `.gitignore`.** Coverage relies on PR #3495's broaden-to-wildcard edit. If this PR merges first, the gitignore broaden MUST land here.

## Overview

Three append-only JSONL sinks under `.claude/` accumulate without bound:

| Sink | Owner | Writers |
|---|---|---|
| `.claude/.rule-incidents.jsonl` | rule-utility-scoring (#2213/#2573) | `lib/incidents.sh` (bash), `security_reminder_hook.py` (Python) |
| `.claude/.skill-invocations.jsonl` | skill-freshness aggregator (#3122) | `skill-invocation-logger.sh` |
| `.claude/.session-tokens.jsonl` | token-efficiency Phase 1.6 (#3494, PR #3495 — open) | `agent-token-tee.sh` |

Only `.rule-incidents.jsonl` has rotation today, and it lives **inside the weekly aggregator script** (`scripts/rule-metrics-aggregate.sh`, gated on `AGGREGATOR_ROTATE=1`). That coupling has two problems:

1. The aggregator is the **only** rotator. Operators who never run the cron path (any developer machine without the GitHub Actions context) accumulate forever — the workflow fires from `actions/checkout`, where the JSONL is always empty.
2. The two sibling sinks have **no rotator at all**. After ~1 year of normal operator use, `.session-tokens.jsonl` alone reaches ~28 MB; jq scans in compound Phase 1.6 (`token-efficiency-report.sh`) degrade O(file).

This plan extracts the rotation logic into `.claude/hooks/lib/log-rotation.sh` and invokes it **at write time** from each of the three hooks (so growth is bounded on every operator machine, not just CI). The aggregator's existing `AGGREGATOR_ROTATE` block is retained as a defense-in-depth secondary rotator: it remains the canonical roll-up at week boundaries, but no longer carries sole responsibility for size containment.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| "Single rotator helper… **size + age threshold**, atomic rename" (issue body AC #1) | Existing rotator in `rule-metrics-aggregate.sh` rotates on **non-empty** + `AGGREGATOR_ROTATE=1` flag — neither size nor age. Atomic rename is **not** used; the rotator does `flock -x`-guarded `cat → archive; : > active` then `gzip -f archive`. | Plan ships size threshold (default 5 MB) AND age threshold (default 30 days); both configurable via env. Atomic-rename approach: `flock -x` → `mv "$active" "$archive.tmp"` → `: > "$active"` → release flock → `mv "$archive.tmp" "$archive"; gzip -f "$archive"`. Avoids the data-loss window between `cat → archive` (copy) and `: > active` (truncate) that the existing rotator has. |
| ".gitignore already covers rotation suffixes (verified PR #3495)" (issue body AC #3) | On `main`, `.gitignore` lines 34–37 cover `.rule-incidents.jsonl`, `.rule-incidents-*.jsonl.gz`, `.skill-invocations.jsonl`, `.skill-invocations-*.jsonl.gz` — **no `.session-tokens*` line**. PR #3495 (open) **broadens** to wildcards `.skill-invocations*`, `.session-tokens*`, `.rule-incidents*`. | This PR depends on #3495's `.gitignore` change OR ships the same broaden-to-wildcards edit defensively. Per branch divergence check: if #3495 has merged at /work time, no edit needed; otherwise apply the same broaden inline. |
| "All three sinks invoke the rotator at write time" (issue body AC #2) | Three writers live in three different files, including one in **Python** (`security_reminder_hook.py`). The Python emitter writes to `.rule-incidents.jsonl` independently. | Bash helper `log-rotation.sh` is called from the two bash hooks (`skill-invocation-logger.sh`, `agent-token-tee.sh`) and from `lib/incidents.sh::emit_incident`. The Python emitter does NOT need to call the rotator inline — its writes share the same flock inode as the bash helper's, so any bash-side rotation closes the file the Python emitter holds open at next-write. **Decision:** rotate-at-write fires from bash side only; the Python emitter's writes are slow enough (Edit-tool-rate-bounded) that bash-side rotation always pre-empts. |
| "Rotation policy is parallel to skill-invocations.jsonl which has the same gap" (#3495 plan Sharp Edge #10) | Confirmed. All three writers share the same flock-guarded O_APPEND pattern; the rotator can be uniform. | Single helper, three call sites. |

## User-Brand Impact

**If this lands broken, the user experiences:** Telemetry hooks block tool dispatch. The hooks are fire-and-forget today (every jq pipe has `2>/dev/null || exit 0`); a rotator bug that holds the flock too long, exits non-zero, or corrupts the active file would silently drop telemetry — observably similar to the gitignored CI baseline, so operators would not notice for weeks. Worst-case operator pain: compound Phase 1.6's `token-efficiency-report.sh` reads a torn `.session-tokens.jsonl` with a half-written line, jq bails on the parse, the per-line `fromjson?` tolerance kicks in (precedent: `rule-metrics-aggregate.sh` line 92), and the operator sees `::warning::Dropped N malformed line(s)` but no functional break.

**If this leaks, the user's [data / workflow / money] is exposed via:** `.command_snippet` in `.rule-incidents.jsonl` carries shell command text — already truncated to 1024 bytes and mode-0600 by `security_reminder_hook.py:80`. `.session-tokens.jsonl` has no command snippets (subagent_type only). `.skill-invocations.jsonl` has skill name + session_id. Rotation does **not** widen any of these surfaces; archived `.gz` files inherit the same mode. A misconfigured rotator that wrote to a world-readable temp directory would be a regression — explicitly tested.

**Brand-survival threshold:** none. Telemetry is local to each operator's machine, gitignored, never leaves the box. The `cmd` field is already truncated and mode-restricted.

## Open Code-Review Overlap

(Filled at /work time after Files-to-Edit list is finalized — see Phase 0.)

## Implementation Phases

### Phase 0 — Pre-flight & branch state reconcile

**Goal:** Reconcile branch state against `feat-token-efficiency-analysis` (PR #3495, open at plan time) so the rotator helper does not collide with PR #3495's `.session-tokens.jsonl` introduction.

**Tasks:**

1. Verify PR #3495 state at /work time: `gh pr view 3495 --json state,mergedAt`. If MERGED, rebase this branch onto `main`. If OPEN, this branch must NOT include the `agent-token-tee.sh` file in its diff — only call into it from the rotator wiring at the call-site that already exists on PR #3495's branch (i.e., this PR is built to **merge after** #3495). If #3495 is closed without merging, file a follow-up to revisit the call site for `.session-tokens.jsonl`.
2. Run the AGENTS.md/Files-to-Edit overlap grep:
   ```bash
   gh issue list --label code-review --state open \
     --json number,title,body --limit 200 > /tmp/open-review-issues.json
   for path in .claude/hooks/lib/incidents.sh .claude/hooks/skill-invocation-logger.sh \
                .claude/hooks/agent-token-tee.sh scripts/rule-metrics-aggregate.sh; do
     echo "--- $path ---"
     jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' \
       /tmp/open-review-issues.json
   done
   ```
   Fold any matches into the `## Open Code-Review Overlap` section.
3. Verify `.gitignore` state matches one of the two expected forms (pre-#3495 or post-#3495). If neither, abort and surface the divergence.

**Files to read (no edits):** `.gitignore`, `.claude/hooks/lib/incidents.sh`, `.claude/hooks/skill-invocation-logger.sh`, `scripts/rule-metrics-aggregate.sh`.

**Acceptance:**
- [x] PR #3495 state recorded in commit message / spec.md.
- [x] `## Open Code-Review Overlap` filled (even if "None").

### Phase 1 — Author shared rotator helper

**Goal:** Land `.claude/hooks/lib/log-rotation.sh` as the single source of truth for rotation across all three sinks.

**File to create:** `.claude/hooks/lib/log-rotation.sh`

**Public API:**

```bash
# rotate_if_needed <jsonl-path> [size-bytes] [age-days]
#
# Rotates the file when EITHER:
#   - size > size-bytes (default $LOG_ROTATION_SIZE_BYTES, fallback 5_242_880 = 5 MB)
#   - mtime older than age-days (default $LOG_ROTATION_AGE_DAYS, fallback 30)
#
# Strategy: copy-then-truncate-in-place (NOT rename). Mirrors the proven pattern
# at rule-metrics-aggregate.sh:291-295. The rationale is concurrency-correctness:
# all four existing writers identify the file by PATH and use `>>$file` (open
# for append). flock advisories are inode-bound. If the rotator did `mv $active
# → $archive.tmp; : > $active` inside its flock, a writer that opens `>>$file`
# between the mv and its own flock acquire would end up locking a DIFFERENT
# inode (the freshly-created post-truncate file) than the rotator's open fd.
# Two writers, two inodes, two flocks — torn writes return.
#
# The copy-then-truncate pattern keeps the same inode throughout (no rename,
# no recreate); flock readers/writers always converge on the same inode and
# the lock semantics hold.
#
# Steps:
#   1. Pre-check (cheap, no lock): if size <= threshold AND mtime within age,
#      return 0 immediately. >99% of calls exit here.
#   2. Acquire flock -w 5 -x on fd 9 against $active (configurable via
#      $LOG_ROTATION_FLOCK_TIMEOUT_S). On timeout: return 0 (next call rotates).
#   3. Re-check size/age inside the lock (TOCTOU defense — another writer may
#      have rotated between our pre-check and our acquire). If no longer over
#      threshold, release and return 0.
#   4. Compute archive name: <dir>/.<basename>-YYYY-MM[-HHMMSSN].jsonl
#      (suffix appended only on collision, matching rule-metrics-aggregate.sh:288).
#   5. cat "$active" >> "$archive"  (best-effort; if cat fails, skip step 6
#      so data is preserved in $active for the next attempt).
#   6. : > "$active"  (truncate in place — preserves inode + mode bits).
#   7. Release flock.
#   8. gzip -f "$archive"  (best-effort, 2>/dev/null || true; failure leaves
#      the .jsonl archive intact, readable by aggregators).
#
# Exit code: 0 always (fire-and-forget — never blocks the calling hook).
#
# Stderr: on failure, ONE warning line per process (gated by /tmp/log-rotation-warned-$$
# marker), mirroring the rule-incidents fallback pattern at incidents.sh:106.
```

**Why copy-then-truncate (NOT rename) — corrected during deepen pass:**

The initial draft prescribed atomic-rename. Concurrency analysis flipped the decision. Two facts collide:

1. **flock semantics are inode-bound.** `flock -x 9 9>>"$file"` opens `$file` (creating if needed) and locks the inode that fd 9 references. Locks do NOT follow path renames.
2. **All writers open the file by path on every invocation.** Each hook re-resolves `$file` and re-opens with `>>` (append). There's no shared fd passed between processes.

Now consider the rotator-rename interleaving:

```
T0: writer A:                  T1: rotator:                T2: writer B:
                                                            (subsequent invocation)

t1 open fd 9 >> $active
t2                              flock -w 5 -x 9 (acquired)
t3                              mv $active → $archive.tmp
t4                                                          open fd 9 >> $active
                                                            ← creates NEW inode at $active
t5                              : > $active
                                ← but rotator's $active is the inode A still points to
                                ← (now under $archive.tmp, no path-side reference)
t6                              flock release
t7                                                          flock -w 5 -x 9 (acquired
                                                            on the new inode created
                                                            by writer B at t4)
t8 flock -w 5 -x 9 (acquired
   on the OLD inode, now
   reachable only via
   $archive.tmp)
t9 write line              ← lands in $archive.tmp, not the active file
                           ← AND interleaves with the gzip in step 8 of the rotator
```

`mv` is a single rename(2), but rename + truncate-create is **two** syscalls, and the writer can wedge in between. Multiple writers can end up holding flocks on different inodes simultaneously — exactly the torn-write scenario the flock exists to prevent.

The copy-then-truncate approach (already in `rule-metrics-aggregate.sh:291-295`) avoids this: the inode is never released. `cat $active >> $archive` reads the open file; `: > $active` truncates the same inode in place. Writers blocked on flock acquire — when the rotator releases — see a now-empty file at the same inode they always held the lock on. No drift.

**ENOSPC tradeoff:** Yes, if `cat` fails mid-copy (disk full), the active file remains intact and the truncate is skipped — we preserve data over progress. The plan adds an explicit guard: `cat "$active" >> "$archive" && : > "$active"` (truncate gated on copy success). The existing aggregator has the implicit equivalent (subshell exits non-zero if cat fails, skipping the truncate); we make it explicit.

**Hard rules respected:**

- **`hr-when-a-plan-specifies-relative-paths-e-g`**: helper is at `.claude/hooks/lib/log-rotation.sh`. Verified `git ls-files | grep -E '^\.claude/hooks/lib/'` returns 1 file (`incidents.sh`) — the directory exists.
- **`cq-regex-unicode-separators-escape-only`**: helper does no string sanitization (writes are atomic file ops). N/A.
- **`hr-the-bash-tool-runs-in-a-non-interactive`**: no `sudo`, no TTY-bound commands.

**Tasks:**

1. Write `log-rotation.sh` per the API above (~100 LoC including the explicit pre-check + exit-code-10 signal channel added in the deepen pass).
2. Resolve repo root via `cd -P / pwd -P` mirroring `incidents.sh:33` and `skill-invocation-logger.sh:40` (canonicalize through symlinks so flock and rotation share the same inode).
3. Honor `LOG_ROTATION_DISABLE=1` kill-switch — short-circuit before any work, mirroring `SOLEUR_DISABLE_AGENT_TOKEN_TEE` and `SOLEUR_DISABLE_SKILL_LOGGER`.
4. Honor `LOG_ROTATION_REPO_ROOT` test override — mirror `INCIDENTS_REPO_ROOT` and `SKILL_LOGGER_REPO_ROOT` precedent.

**Files to create:**
- `.claude/hooks/lib/log-rotation.sh` (~100 LoC)

**Files to edit:** none in Phase 1 (helper is unwired — Phase 2 wires it in).

### Research Insights — Phase 1 (deepen pass)

**Reference implementation sketch (skeleton; not the final code):**

```bash
#!/usr/bin/env bash
# log-rotation.sh — sourced helper for .claude/.*.jsonl rotation.

LOG_ROTATION_SIZE_BYTES_DEFAULT=$((5 * 1024 * 1024))   # 5 MB
LOG_ROTATION_AGE_DAYS_DEFAULT=30
LOG_ROTATION_FLOCK_TIMEOUT_S_DEFAULT=5

rotate_if_needed() {
  [[ "${LOG_ROTATION_DISABLE:-}" == "1" ]] && return 0
  local active="${1:-}"
  [[ -z "$active" ]] && return 0
  [[ -f "$active" ]] || return 0   # nothing to rotate
  [[ -s "$active" ]] || return 0   # empty file — no rotation regardless of mtime

  local size_threshold="${2:-${LOG_ROTATION_SIZE_BYTES:-$LOG_ROTATION_SIZE_BYTES_DEFAULT}}"
  local age_threshold_days="${3:-${LOG_ROTATION_AGE_DAYS:-$LOG_ROTATION_AGE_DAYS_DEFAULT}}"
  local timeout_s="${LOG_ROTATION_FLOCK_TIMEOUT_S:-$LOG_ROTATION_FLOCK_TIMEOUT_S_DEFAULT}"

  # Pre-check (no lock): >99% of calls exit here.
  local size mtime now age_seconds
  read -r size mtime < <(stat -c "%s %Y" "$active" 2>/dev/null) || return 0
  now=$(date -u +%s)
  age_seconds=$(( now - mtime ))
  local age_threshold_seconds=$(( age_threshold_days * 86400 ))
  if (( size <= size_threshold )) && (( age_seconds <= age_threshold_seconds )); then
    return 0
  fi

  # Compute archive path BEFORE entering flock subshell (subshell var
  # reassignments do not propagate — see learning 2026-04-18).
  local dir base ts archive
  dir=$(dirname "$active")
  base=$(basename "$active" .jsonl)
  ts=$(date -u +%Y-%m)
  archive="$dir/${base}-${ts}.jsonl"
  if [[ -f "${archive}.gz" || -f "$archive" ]]; then
    local suffix="${LOG_ROTATION_UNIQ_SUFFIX:-$(date -u +%H%M%S%N)}"
    archive="$dir/${base}-${ts}-${suffix}.jsonl"
  fi

  # Acquire flock + re-check + copy-then-truncate. flock fd 9 against $active
  # — same inode the writers use for their own flock. -w 5 timeout matches
  # the agent-token-tee.sh precedent. On timeout: skip this round.
  local rotated=0
  (
    if ! flock -w "$timeout_s" -x 9; then
      exit 0   # timeout: subsequent writer rotates next round
    fi
    # Re-check inside lock (TOCTOU).
    local s2 m2
    read -r s2 m2 < <(stat -c "%s %Y" "$active" 2>/dev/null) || exit 0
    local age2=$(( $(date -u +%s) - m2 ))
    if (( s2 <= size_threshold )) && (( age2 <= age_threshold_seconds )); then
      exit 0   # another writer already rotated
    fi
    # Copy first, truncate only on success (data-preserving on ENOSPC).
    if cat "$active" >> "$archive"; then
      : > "$active"
      exit 10  # signal "rotated" via exit code
    fi
    exit 0
  ) 9>>"$active"
  rotated=$?

  if [[ "$rotated" == "10" ]]; then
    gzip -f "$archive" 2>/dev/null || true
  fi
  return 0
}
```

**Why exit-code-10 signal:** the subshell cannot export variables back to the outer scope (see Sharp Edge above). We use the exit code as a 1-bit channel ("rotated" / "did nothing") to gate the gzip step outside the lock. `gzip` outside the lock keeps the critical section minimal — concurrent writers don't wait on compression.

**Acceptance:**
- [x] `bash -n .claude/hooks/lib/log-rotation.sh` parses cleanly.
- [x] `shellcheck .claude/hooks/lib/log-rotation.sh` passes (verified: `shellcheck 0.10.0` available at `/home/jean/.local/bin/shellcheck`).
- [x] Helper exits 0 on every malformed input it receives (file does not exist, file is empty, file is not writable, gzip missing, flock missing — see macOS note in `README.md:80`).
- [x] `stat -c "%s %Y"` form works on both GNU coreutils and uutils-coreutils 0.2.x (verified locally; sibling hooks already rely on `stat`).

### Phase 2 — Wire all three sinks to the helper

**Goal:** Each writer calls `rotate_if_needed` BEFORE acquiring its own flock, so the rotator runs in series with the writers (no concurrent rotation + write).

**Files to edit:**

1. **`.claude/hooks/lib/incidents.sh`** — `emit_incident` function. Insert `rotate_if_needed "$file"` between line 83 (`[[ -f "$file" ]] || : > "$file"...`) and line 86 (jq line construction).
2. **`.claude/hooks/skill-invocation-logger.sh`** — insert `rotate_if_needed "$file"` between line 60 (file existence guard) and line 62 (jq line construction).
3. **`.claude/hooks/agent-token-tee.sh`** — insert `rotate_if_needed "$file"` between the `[[ -f "$file" ]] || ...` guard (line 95 in the #3495 branch) and the jq line construction (line 97).

Each edit is identical:

```bash
# Source the rotator helper (idempotent — safe to source multiple times).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib/log-rotation.sh" 2>/dev/null || true

# (Existing logic up to file-creation guard.)

rotate_if_needed "$file" 2>/dev/null || true
```

**Why source-then-call (not exec): the rotator runs in the same process, sharing the same `flock` inode visibility. Spawning a subprocess would mean the rotator's flock release happens before the parent's flock acquire, which is fine — but introduces a fork cost on every hook invocation. Sourcing keeps the cost at one function call.**

### Research Insights — Phase 2 (deepen pass)

**Call-site invariant: rotate BEFORE acquire-and-write, never inside the writer's own flock.**

The writers' existing pattern is:

```bash
( flock -x 9; printf '%s\n' "$line" >&9 ) 9>>"$file"
```

`rotate_if_needed "$file"` runs BEFORE this subshell. The two flocks serialize on the same inode: rotator → release → writer. Two consequences worth calling out:

1. **No nested flock.** A single bash process can acquire `flock -x` on the same inode twice (the second acquire is a no-op on Linux; on macOS the behavior diverges per `man 2 flock`). We avoid the question entirely by ordering: rotate → release → write.
2. **Rotation runs once per write attempt, not once per writer process.** Each Skill/Bash/Task hook invocation is a fresh bash process; the pre-check + flock + re-check is cheap enough (`stat` is one syscall) that 99% of calls exit at the pre-check. Worst case (a writer spinning fast enough to keep the file at threshold), we rotate at most every other call — fine.

**Idempotent sourcing.** The helper has no side effects on source (only function definitions + DEFAULT constants). Sourcing it twice (e.g., `incidents.sh` already sourced from `lib/`, then a hook also sources `log-rotation.sh` directly) is safe.

**Hard rules respected:**

- **`hr-always-read-a-file-before-editing-it`**: each edit follows a Read tool call within the same /work session.
- **`hr-when-a-command-exits-non-zero-or-prints`**: every call to `rotate_if_needed` is wrapped `2>/dev/null || true` so a rotator bug never blocks the hook.

**Files to edit (3):**
- `.claude/hooks/lib/incidents.sh`
- `.claude/hooks/skill-invocation-logger.sh`
- `.claude/hooks/agent-token-tee.sh` (only if PR #3495 already merged at /work time; otherwise this edit is **deferred to a fast-follow PR right after #3495 merges**)

**Acceptance:**
- [x] All three writers source the helper without explosion when the helper is missing (`|| true` guard intact).
- [x] The aggregator's existing `AGGREGATOR_ROTATE=1` block in `scripts/rule-metrics-aggregate.sh:275-298` is **retained** as a secondary rotator for the weekly cron path (defense-in-depth — the aggregator runs in CI where the operator-side rotator never fires).

### Phase 3 — Update `.gitignore` if needed (post-#3495 reconcile)

**Goal:** Ensure all three rotation suffixes are gitignored.

**Decision tree (executed at /work time):**

- If PR #3495 has merged: `.gitignore` already has `.session-tokens*`, `.skill-invocations*`, `.rule-incidents*` (broad wildcards). No edit needed.
- If PR #3495 has NOT merged: this branch's `.gitignore` is the pre-#3495 form. Edit it to add the same broad wildcards #3495 adds, so the rotation suffix patterns are covered regardless of #3495's fate.

**Files to potentially edit:**
- `.gitignore` (conditional on Phase 0 reconcile output).

**Acceptance:**
- [x] After Phase 3, `git check-ignore .claude/.session-tokens-2026-05.jsonl.gz` exits 0.
- [x] After Phase 3, `git check-ignore .claude/.skill-invocations-2026-05.jsonl.gz` exits 0.
- [x] After Phase 3, `git check-ignore .claude/.rule-incidents-2026-05.jsonl.gz` exits 0.

### Phase 4 — Test scenarios (TDD per `cq-write-failing-tests-before`)

**Test file:** `.claude/hooks/log-rotation.test.sh` (new, ~150 LoC, mirrors `skill-invocation-logger.test.sh` pattern).

**Test framework decision:** Use bash + `bats`-free `.test.sh` convention — verified by `ls .claude/hooks/*.test.sh` showing `incidents.test.sh`, `skill-invocation-logger.test.sh`, `pre-merge-rebase.test.sh`, `security_reminder_hook.test.sh`, `docs-cli-verification.test.sh`, all hand-rolled bash. **No new dependency.**

**Scenarios (each test runs in a temp `LOG_ROTATION_REPO_ROOT`):**

| # | Scenario | Setup | Expected |
|---|---|---|---|
| T1 | No rotation when below thresholds | Active file = 1KB, mtime = today | File unchanged, no archive created |
| T2 | Rotates on size threshold | Active file = 6 MB, mtime = today | Archive created `.gz`, active file truncated to 0 bytes |
| T3 | Rotates on age threshold | Active file = 1KB, mtime = 31 days ago | Archive created, active truncated |
| T4 | Configurable thresholds via env | `LOG_ROTATION_SIZE_BYTES=1024` + 2KB file | Archive created |
| T5 | Copy failure leaves active intact (truncate gated on cat success) | Archive parent read-only OR mocked `cat` fails | Active file unchanged, no data loss, no truncate, exit 0 |
| T6 | Concurrent writer + rotator does not tear lines | 100-line bg writer racing rotator | Combined active+archive line count = 100; no truncated line |
| T7 | Kill-switch `LOG_ROTATION_DISABLE=1` short-circuits | 6 MB file with disable=1 | File unchanged |
| T8 | Existing archive — collision suffix appends | `.session-tokens-2026-05.jsonl.gz` exists, rotation triggers | New archive at `.session-tokens-2026-05-HHMMSSN.jsonl` (same precedent as `rule-metrics-aggregate.sh:288`) |
| T9 | Subshell-reassignment trap (Sharp Edge from `2026-04-18-schema-version`) | Inspection: `archive=` is reassigned **outside** the flock subshell | `bash -x` trace shows the outer `gzip` consumes the same `$archive` |
| T10 | Helper survives missing `flock` (macOS dev) | `PATH` without flock | Helper exits 0, prints one stderr warn line |
| T11 | Helper survives missing `gzip` | `PATH` without gzip | Archive `.tmp` is moved to final `.jsonl` (uncompressed); operator sees one stderr line |
| T12 | Schema invariant: archive `.gz` decompresses to valid JSONL | Rotate populated 100-line file | `gunzip -c <archive>.gz | jq empty` succeeds; line count = 100 |

**Sibling-sink integration tests (one per writer):**

- **T13:** `incidents.test.sh` — call `emit_incident` 1000 times against a 4.99 MB existing file; verify rotation triggered exactly once and the new active file contains the 1001st write.
- **T14:** `skill-invocation-logger.test.sh` — same shape against `.skill-invocations.jsonl`.
- **T15:** `agent-token-tee.test.sh` — same shape against `.session-tokens.jsonl` (only if PR #3495 has merged at /work time; otherwise file `T15` as a follow-up scope-out attached to #3495's branch).

**Aggregator regression test:**

- **T16:** `rule-metrics-aggregate.test.sh` — verify the existing `AGGREGATOR_ROTATE=1` path still works (defense-in-depth — the bash-side rotator does not eliminate the aggregator's rotator). The aggregator's rotator sees an empty file (rotation already happened at write time) and skips per its own `[[ -s "$INCIDENTS" ]]` guard at line 275 — assert that this code path is reached and no error is emitted.

**Acceptance:**
- [x] All 16 tests pass locally (T15 included — PR #3495 merged during /work, agent-token-tee.sh wired in same PR).
- [x] CI test step (whatever workflow runs `bash .claude/hooks/*.test.sh`) is green.

### Phase 5 — Documentation

**Files to edit:**

1. **`.claude/hooks/README.md`** — replace the existing `## Rotation` section (lines 62-68) with a description of the new helper, the per-write trigger, the size+age thresholds, the env-variable configuration, and the relationship to the aggregator's secondary rotator. Add a `## Library API` subsection documenting `rotate_if_needed`.
2. **`knowledge-base/project/learnings/2026-05-10-shared-log-rotation-primitive.md`** — capture the design decisions (atomic-rename vs cat-truncate, why per-write not per-cron, why source-not-exec, the macOS flock note).

**Acceptance:**
- [x] README.md describes both the per-write helper and the aggregator's defense-in-depth role.
- [x] Learning file links back to issue #3508 and PR #3495.

## Files to Edit

- `.claude/hooks/lib/incidents.sh` (Phase 2 — 4 lines added)
- `.claude/hooks/skill-invocation-logger.sh` (Phase 2 — 4 lines added)
- `.claude/hooks/agent-token-tee.sh` (Phase 2 — 4 lines added; conditional on PR #3495 state)
- `.claude/hooks/README.md` (Phase 5 — rewrite `## Rotation` section)
- `.gitignore` (Phase 3 — conditional on PR #3495 merge state)
- `.claude/hooks/incidents.test.sh` (Phase 4 — T13)
- `.claude/hooks/skill-invocation-logger.test.sh` (Phase 4 — T14)
- `.claude/hooks/agent-token-tee.test.sh` (Phase 4 — T15; conditional)
- `scripts/rule-metrics-aggregate.test.sh` (Phase 4 — T16)

## Files to Create

- `.claude/hooks/lib/log-rotation.sh` (Phase 1)
- `.claude/hooks/log-rotation.test.sh` (Phase 4 — T1-T12)
- `knowledge-base/project/learnings/2026-05-10-shared-log-rotation-primitive.md` (Phase 5)

## Acceptance Criteria

### Pre-merge (PR)

- [x] `.claude/hooks/lib/log-rotation.sh` exists, exports `rotate_if_needed`, exits 0 on every malformed input.
- [x] All three writers (`incidents.sh::emit_incident`, `skill-invocation-logger.sh`, `agent-token-tee.sh`) call `rotate_if_needed "$file"` before constructing the JSONL line.
- [x] Default thresholds: 5 MB size, 30 days age — overridable via `LOG_ROTATION_SIZE_BYTES` and `LOG_ROTATION_AGE_DAYS`.
- [x] Concurrency-correct rotation: rotation uses `cat → archive` + `truncate-in-place` inside the flock — preserves inode so flock semantics hold across rotator and concurrent writers. Truncate is gated on cat success (data-preserving on disk-full / OOM).
- [x] Kill-switch: `LOG_ROTATION_DISABLE=1` short-circuits the helper.
- [x] Test scenarios T1-T15 pass; T16 verifies aggregator interop (T4 in `rule-metrics-aggregate.test.sh` is pre-existing pass-through tracked in #3507).
- [x] `.gitignore` covers all three rotation suffixes (`.session-tokens*`, `.skill-invocations*`, `.rule-incidents*` wildcards).
- [x] `.claude/hooks/README.md` documents the per-write rotator, the aggregator's defense-in-depth role, env-var configuration, and the macOS flock note.
- [x] No new regression on existing aggregator rotation (T4 is pre-existing — confirmed by running on clean main clone).

### Post-merge (operator)

- [ ] Open PR uses `Closes #3508` only on its own body line (per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] No post-merge ops actions required — rotation engages on the next hook fire on every operator's machine.

## Test Scenarios

(Detailed in Phase 4 above — T1 through T16.)

## Hypotheses

(Not applicable — no SSH/network connectivity symptom; Phase 1.4 gate skipped.)

## Sharp Edges

- **Subshell-reassignment trap:** the existing `rule-metrics-aggregate.sh:288` Sharp Edge from learning `2026-04-18-schema-version-must-be-asserted-at-consumer-boundary.md` warns that `archive=` reassigned inside `( flock -x 9 ... ) 9>>"$file"` does not propagate to the outer scope. The helper computes `$archive` (and any uniquify suffix) BEFORE entering the flock subshell. Test T9 explicitly walks `bash -x` and confirms the outer `gzip -f "$archive"` consumes the same `$archive` that the flock subshell `cat`'d into.
- **Copy-then-truncate, NOT rename — concurrency-correct flock interaction:** flock advisories are inode-bound. If the rotator did `mv $active → $archive.tmp` inside the flock and `: > $active` to recreate, a writer that opened `>>$active` between the two syscalls would lock a freshly-created inode that the rotator's flock never covered. Two writers, two inodes, two flocks — torn writes return. The chosen pattern (`cat → archive` + `truncate-in-place`) keeps the inode constant; flock readers/writers always converge on the same inode. Detailed worked example in Phase 1 above. Test T6 validates 100-line concurrent writes produce exactly 100 lines combined.
- **macOS flock missing:** the helper must exit 0 on `command -v flock` returning non-zero. Tests T10 covers this. Operators on macOS without `brew install flock` get no rotation but also no crash — the file grows unbounded as today, but at least no regression.
- **`LOG_ROTATION_FLOCK_TIMEOUT_S` exhaustion:** under contention, the rotator's flock acquire may time out (default 5s). On timeout, the helper exits 0 and the writer proceeds — the file may grow past threshold this round, gets rotated next round. Acceptable because the threshold is soft (a few percent overshoot is fine; the goal is bounded growth, not byte-perfect cap).
- **PR #3495 merge ordering:** if #3495 is closed/abandoned, this PR's Phase 2 wiring of `agent-token-tee.sh` is dead code. Mitigation: file an issue at /work time tracking the abandonment scenario; pre-merge AC for this PR can fold the `.session-tokens.jsonl` rotation under "future writer when #3495 lands". Recommended ordering: merge #3495 first, then this PR.
- **Empty file with stale mtime:** an active file with 0 bytes but mtime > 30 days old triggers age rotation, which produces an empty `.gz` archive. Acceptable — the archive is informationally identical to absence. The helper's `[[ -s "$file" ]]` gate (file is non-empty) before rotation prevents this — added explicitly in the helper.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Bash-side rotator bug truncates active file mid-write of another process | Low (copy-then-truncate inside flock + flock advisories preserved across rotation because inode never changes) | High (telemetry data loss) | T6 concurrent-write test (100-line bg writer); per-line `fromjson?` parse tolerance in aggregators (already in place at `rule-metrics-aggregate.sh:93`). |
| Helper sourced from a hook whose `set -e` is on (none today, but future hooks might) blows up the calling hook on rotator failure | Low | Medium | All call sites use `rotate_if_needed "$file" 2>/dev/null \|\| true` — explicit failure swallowing. |
| Operator runs the rotator in a non-bash shell (zsh, fish) — `BASH_SOURCE` semantics drift | Low | Low | Helper has shebang `#!/usr/bin/env bash` and is sourced from `.sh` files only. Python hook does NOT call it. |
| PR #3495 merges first AND adds its OWN rotator inline before this PR lands | Low (issue body explicitly says shared primitive deferred to follow-up) | Medium (rework) | Phase 0 reconciliation step verifies #3495 state at /work time. |
| The aggregator's `AGGREGATOR_ROTATE=1` path conflicts with bash-side rotation: cron-time aggregator sees an already-rotated empty file, the aggregator's `[[ -s "$INCIDENTS" ]]` guard skips the secondary rotation, no harm | N/A — designed for | N/A | Documented in README; T16 asserts. |
| Helper's repo-root resolution diverges from incidents.sh / skill-invocation-logger.sh on a symlinked .claude/ | Low | Medium (disjoint flock inodes — torn writes) | Use the **identical** `cd -P / pwd -P` pattern as both siblings; `_log_rotation_repo_root` mirrors `_incidents_repo_root` line-for-line. Test T6 explicitly walks through a symlinked `.claude/`. |

## Domain Review

**Domains relevant:** Engineering (CTO).

This is an infrastructure-only refactor — no user-facing surface, no data model change, no external service dependency, no auth/payment/compliance touch. CPO/CMO/COO/CLO assessments are not relevant per `brainstorm-domain-config.md` semantic-match criteria.

### Engineering (CTO)

**Status:** carry-forward (covered by issue body's `code-simplicity-reviewer` co-sign).
**Assessment:** "CONCUR with caveat: rotation primitive MUST land as a shared `.claude/hooks/lib/` helper applied to all three sinks in the same PR." The plan honors this by extracting the helper to `lib/log-rotation.sh` and wiring all three sinks in Phase 2. The aggregator's existing rotator is retained as defense-in-depth, not removed (avoids a defense-relaxation per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`).

## Alternative Approaches Considered

| Approach | Decision | Rationale |
|---|---|---|
| **A: Move rotation logic into each writer inline (no shared helper)** | Reject | Three near-identical copies of rotation logic = three drift paths; failure mode of issue #3508. |
| **B: Per-write rotation in shared helper, copy-then-truncate (chosen — corrected during deepen pass)** | Accept | Bounded growth on every operator's machine; aggregator rotator becomes defense-in-depth. Inode-preserving rotation is concurrency-correct under flock. |
| **B-alt: Per-write rotation in shared helper, atomic-rename** | Reject (post deepen-pass) | Initially proposed; rejected after concurrency analysis. flock advisories follow the inode, not the path — `mv $active → $archive.tmp; : > $active` produces a window where two writers can flock two different inodes simultaneously. See worked example in Phase 1. |
| **C: Rotate only at aggregator-cron time** | Reject | Operators who never trigger the cron path (i.e., every developer machine — the cron runs against `actions/checkout` JSONL files which are always empty) accumulate forever. Issue #3508 explicitly enumerates this gap. |
| **D: Switch storage from JSONL to SQLite** | Reject | YAGNI; the per-write append + per-line `jq` consume pattern is already established and works well. SQLite would require a schema migration on every operator's machine and break the existing `tail -F` workflow. |
| **E: Replace `gzip` with `zstd` for archives** | Reject | YAGNI; gzip is universally available, archive sizes are <10 MB, decompress speed is not a bottleneck. |
| **F: Logrotate(8) configuration** | Reject | Linux-only; macOS operators (most of the team) would silently drop coverage. The bash helper works on both. |
| **G: `O_TMPFILE` + `linkat` atomic publish** | Reject | Modern Linux-only kernel feature; macOS lacks it. Adds a portability cliff for marginal gain over copy-then-truncate. |

## Non-Goals

- Migrating to a structured-logging library (Python `logging`, `pino`, etc.) — out of scope; the JSONL format is load-bearing for jq consumers.
- Compression algorithm choice beyond gzip — see Alternative E.
- Network/remote log shipping — telemetry stays operator-local; that's a privacy property, not a gap.
- Aggregator schema changes — `rule-metrics-aggregate.sh`, `skill-freshness-aggregate.sh`, and `token-efficiency-report.sh` are read-only consumers of the JSONL files; their behavior MUST be unchanged after this PR.

## CLI-Verification Insights

(No new CLI invocations land in user-facing docs — `flock`, `gzip`, `mv` are POSIX-standard tools whose flag use is already attested by sibling hooks.)
