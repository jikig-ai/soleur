---
title: "refactor(ship): one BEHIND-sync executable, SKILL.md headroom, terminal monitor liveness, negation-aware PIR scan"
date: 2026-09-21
slug: refactor-ship-machinery-behind-sync-budget-monitor-pir
branch: feat-one-shot-ship-machinery-8419-8420-8334-8383
issue: 8383
closes: [8383, 8419, 8438, 8420, 7961, 8334]
type: refactor
lane: cross-domain
brand_survival_threshold: aggregate pattern
depends_on_pr: 8458
---

# refactor(ship): one BEHIND-sync executable, SKILL.md headroom, terminal monitor liveness, negation-aware PIR scan

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No `spec.md` exists for this branch; one-shot entered `plan` directly.)

> **Vocabulary note for whoever edits this file.** This plan is part of the corpus
> `scripts/ship-incident-pir-gate.sh` reads at ship time. Every token from its `OUTAGE_RE`
> is kept inside backticks or fenced blocks here (both are stripped before matching). Keep it
> that way in edits and in the PR body, or this PR's own ship run will ask for a PIR for an
> event that never happened. See Sharp Edges.

## Overview

Four defects in Soleur's ship / postmerge / hook machinery, fixed in one PR because they share
files and one of them is the byte source for another:

1. **#8383 — three copies of one state machine.** The Phase 7 BEHIND auto-sync arm is written
   out three times: inline in the `ship/SKILL.md` Phase 7 fence, again in the `merge-pr/SKILL.md`
   §5.2 mirror, and a third time in `plugins/soleur/scripts/sync-pr-behind.sh`, which has already
   drifted (it conflates a refused merge with a conflict, pipes `git merge` through `tail`, and
   writes its failure lines to stderr). This PR makes the script the only implementation and has
   both fences call it.
2. **#8419 (dup #8438) — no headroom.** `ship/SKILL.md` is 273970 B against a 274000 B ceiling
   (30 B left, measured today; the issue's 42 B figure is from `18887f8d5`), and
   `postmerge/SKILL.md` is 47998 B against 48000 B (2 B). Neither can absorb a
   route-to-definition bullet from `soleur:compound`. Moving the BEHIND arm out of the ship fence
   (item 1) frees about 5 KB; two step-gated extractions (ADR-229 shape) free the rest.
3. **#8420 (dup #7961) — the monitor hook lists dead monitors.** `monitor-supersede-guard.sh`
   treats only `<status>completed</status>` as terminal. Monitors also end by `<status>failed</status>`
   (their script exited non-zero) and by an `<event>[Monitor expired after …]` notice, which has
   no status tag at all. Those monitors stay listed forever, under a message that says the list is
   authoritative.
4. **#8334 — the PIR scan ignores negation.** `ship-incident-pir-gate.sh` matches `OUTAGE_RE`
   tokens that sit inside a denial (`not that the feature has stopped working`), so a sentence
   saying nothing broke reads as a report that something did.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / collision gate) | Reality (measured 2026-09-21 on `71e7585ea`) | Plan response |
|---|---|---|
| ship has 42 B headroom (#8419, #8438) | `wc -c` = 273970 → **30 B** | Use the live number; AC measures against the merge base at work time |
| postmerge has 2 B headroom | 47998 / 48000 → **2 B** | Holds |
| `sync-pr-behind.sh` "is correct on its own" (#8383) | It pipes `git merge … \| tail -8` and `git push \| tail -3` inside `if !` (correct only because `pipefail` is on); it runs `git merge --abort` after a merge that *refused to start* (nothing to abort, and it reports "merge conflict"); its failure lines go to **stderr**, which a Monitor does not stream; it does `git fetch --no-tags` where the fences do `git fetch origin main`. It is the least correct copy, not a correct one. | The consolidated script adopts the **fence's** semantics (the richer, fixture-pinned copy), not the script's |
| #8458 changes the script's target repo | Open, auto-merge armed; removes `REPO_ROOT=…; cd "$REPO_ROOT"` so the script works on `$PWD`. | **Hard prerequisite** for item 1: a fence that runs `${CLAUDE_PLUGIN_ROOT}/scripts/sync-pr-behind.sh` before #8458 would sync the plugin install's own checkout. Work phase gates on it (Phase 4, step 0) |
| #7961 is a duplicate of #8420 | Same predicate, same file, same remedy. #7961 quotes the older notice text `[Monitor timed out — re-arm if needed.]`; #8420 quotes the current `[Monitor expired after 30m …]`. | Close both; the terminal set covers **both** strings |
| #8438 is a duplicate of #8419 | #8438 is the `ship` half of #8419, same remedy (extract behind a step-gated directive), asks for ≥ 4 KB where #8419 asks ≥ 2 KB | Close both; AC uses the stricter 4 KB floor |
| #7801 (PIR false positive in a hypothetical paragraph) is open and nearby | **Already fixed** by merged PR #7806 (paragraph-scoped strip is on `main`, fixture `precedent-citation-inside-hypothetical-paragraph.md` exists); the issue was never closed | Out of scope. Not closed by this PR (not fixed by it); noted for the operator |
| #7800 (a cited `post-mortem` plus the adjective `live`) | Negation does not touch it: the trigger is a citation shape, not a denial | Out of scope; the negation strip does not cover it, stated in Non-Goals |

## Research Insights

**Premise Validation.** Checked: all eight cited issues (`gh issue view`): #8419, #8420, #8334,
#8383, #8438, #7961, #7800, #7801 are OPEN. #7801's fix already merged in #7806 (stale-open, out of
scope). #8458 is OPEN with auto-merge armed, touching only `sync-pr-behind.sh` and its test;
`origin/main` has not moved since this branch was cut (`git log HEAD..origin/main` empty).
Every cited path exists on `origin/main`. No cited mechanism appears in an ADR's rejected
alternatives: ADR-229 *prescribes* the step-gated extraction #8419 asks for.

**Property List** (Phase 0.6b):

- P1. One BEHIND sync implementation: a fix to the sync arm is made once and reaches the ship
  fence, the merge-pr fence and the standalone (Grok) path.
- P2. The sync arm's observable contract is unchanged: same `[ship.phase7.*]` lines on stdout,
  same `BEHIND detected` / `auto-sync … pushed` lines `pollInstructions()` keys on, same stop/continue
  decisions, same `fetch_failures` accounting.
- P3. `ship/SKILL.md` and `postmerge/SKILL.md` each sit ≥ 4096 B under their ceilings, and a
  compound route-to-definition bullet (~300 B) fits in each.
- P4. No behavioural text is moved behind a load directive that does not fire on the step that
  needs it (the ADR-229 trap).
- P5. Every monitor the supersede advisory lists is live: none has a terminal record in the
  transcript; and a genuinely live monitor is still listed.
- P6. The advisory does not claim more certainty than its source supports.
- P7. An `OUTAGE_RE` token inside a denial does not count toward `INCIDENT-SIGNAL`; an undenied
  token on the same line still does; each suppression is disclosed on stderr.

**Cut List** (mechanisms proposed in the asks, cut before research):

- "Optionally count fetch failures separately" (#8383) → P2 → **already on `main`**: the fence has
  `fetch_failures` since #8339 (`grep -n fetch_failures plugins/soleur/skills/ship/SKILL.md`). Kept
  as-is, moved nowhere.
- "Lower the ceiling after the trim" (#8438 path 2) → no property in the list (a lower ceiling
  *removes* the headroom P3 asks for) → cut. A ceiling change must also be its own
  `skill-body-budget.json`-only PR by the lint's contract.
- A new, separate negation lint / second pass for PIR (#8334 "pre-pass") → P7 → the existing
  single awk strip stage already has the per-line hook and the sentinel-to-stderr channel
  (`SENTINEL='__PIR_STRIP_SUPPRESSED__'`). The negation strip is a function inside that stage, not a
  new stage (a second stage is what #7801's review found incoherent).
- A `<plugin-root>` placeholder in the fence → P1 → Claude Code already substitutes the bare
  `${CLAUDE_PLUGIN_ROOT}` token in skill text (ADR-179, the canonical anchor for customer-facing
  plugin executables). Use that; no new paste token.

**Relevant files** (line anchors are content anchors, `cq-cite-content-anchor-not-line-number`):

- `plugins/soleur/skills/ship/SKILL.md` — Phase 7 fence between `<!-- phase-7-poll-block:start -->`
  and `:end`; the BEHIND arm starts at `# Auto-sync on BEHIND: GitHub auto-merge will not fire` and
  ends before `elif [[ "$s" == "OPEN BEHIND" && … -ge "$MAX_BEHIND_SYNCS"` (4665 B). Prose:
  `**Auto-sync on BEHIND.**` steps 1–4 (≈ 2.3 KB) and `**Settle-then-admin-merge escape hatch**`
  through the end of `**Expected side effect (RETIRED by #5806 / ADR-217)` (≈ 11.4 KB).
- `plugins/soleur/skills/merge-pr/SKILL.md` §5.2 — the derived mirror (9199 B block); its pushed
  line is `auto-sync N/MAX pushed` (differs from ship's `auto-sync N pushed — auto-merge will
  re-evaluate`; both match `auto-sync.*pushed`). Its tail paragraph points at ship's "Auto-sync on
  BEHIND" for the hatch.
- `plugins/soleur/scripts/sync-pr-behind.sh` (111 lines; #8458 deletes lines 23–24).
- `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (1056 lines) — extracts both fences,
  runs 20+ scenarios against each with **shell-function** `git`/`gh` mocks, a mirror-token parity
  list, and a real-git scenario 10.
- `plugins/soleur/test/sync-pr-behind.test.sh` — PATH-shimmed `gh`, real `file://` git; #8458
  wraps every case in `( cd "$X/work" && … )` + `assert_in_fixture`, floor 5 → 6.
- `plugins/soleur/lib/pr-merge-poll.ts` `behindSyncInstructions()`; `plugins/soleur/lib/harness.ts`
  poll patterns `BEHIND detected`, `auto-sync.*pushed`, `BEHIND resolved`;
  `plugins/soleur/test/pr-merge-poll.test.ts` asserts the script contains `BEHIND detected`.
- **Everything that executes or pins the script's bytes** (`git grep -l sync-pr-behind`, outside
  plans/specs): `pr-merge-poll.ts` + `pr-merge-poll.test.ts` (asserts `BEHIND detected` in the
  script), `harness.test.ts` (pollInstructions names the script), `workflow-fidelity.test.ts`
  (asserts the script contains `mergeStateStatus` — standalone mode keeps its state read),
  `review/SKILL.md` (recommends running the script standalone on a CONFLICTING-but-clean PR —
  standalone DIRTY handling is kept), `ship/SKILL.md`, `sync-pr-behind.test.sh`,
  `scripts/retired-rule-ids.txt` (prose only).
- `plugins/soleur/skills/postmerge/SKILL.md` Phase 3.6 (8658 B section, gated on "PR names a
  specific Sentry issue"). Phase 3.7 was considered and rejected — see Alternatives.
- `.claude/hooks/monitor-supersede-guard.sh` `task_is_complete()`; its suite
  `monitor-supersede-guard.test.sh` (30 cases, `MIN_CASES=30`, helper `complete_task`).
- `scripts/ship-incident-pir-gate.sh` (`OUTAGE_RE`, the strip awk, `SENTINEL`);
  `plugins/soleur/test/ship-incident-pir-gate.test.ts` (fixture verdict table);
  `scripts/ship-incident-pir-gate-mutation.test.sh` (mutation battery, pristine-copy restore).
- `.claude/hooks/ship-soak-followthrough-gate.sh` — the soak negation pre-pass #8334 mirrors, and
  the reason not to copy it verbatim (its safety comes from a `Ref #N` discriminator the PIR gate
  has no analogue for).
- `scripts/lint-skill-body-budget.py` + `plugins/soleur/test/skill-body-budget.json` (ceilings read
  from the merge base).

**Measured transcript shapes (for #8420).** Grepped the last 400 session transcripts under
`~/.claude/projects/-data-git-repositories-jikig-ai-soleur/`:

| terminal record for a Monitor task id | count | record |
|---|---|---|
| `<status>completed</status>` … `stream ended` | (most of 6088) | `type: queue-operation`, `content` string |
| `<status>failed</status>` … `Monitor "…" script failed (exit 1)` | 103 | same shape |
| `<event>[Monitor expired after 30m with no events delivered. …]</event>` (no `<status>`) | 850 | same shape; also mirrored in `type: attachment` records |
| `[Monitor timed out — re-arm if needed.]` (#7961, older harness) | 0 in the last 400 | quoted in #7961; kept as an alternative |

`<status>killed</status>` and `<status>stopped</status>` occur only on Background-command and
Agent tasks in this sample, never on a Monitor, so they stay out of the terminal set.

**Institutional learnings applied.**

- `2026-05-18-ship-phase-7-poll-loop-silent-on-behind-state.md` — why the BEHIND arm exists at all.
- #8339's plan (`plans/archive/20260919-220925-…-fix-ship-phase-7-poll-block-pipe-rc-plan.md`) —
  capture rc before `tail`; never `set -o pipefail` in a pasted block; errexit host shells kill a
  bare `x="$(cmd)"; rc=$?`; never `--abort` an operation this arm did not start.
- `2026-09-17-the-watcher-and-the-watched-shared-a-lifetime.md` — Monitors stream stdout only.
- #8458's body — a suite that runs a `$PWD`-operating script from the runner's CWD is one
  `git push` from the live repo; protection must be by assertion, not by side effect.
- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md` — the PIR battery must add rows
  for the new stage, not rely on the old rows staying green.
- The soak gate's own comments (`ship-soak-followthrough-gate.sh`, above its negation `awk`):
  "natural-language negation scope is not a character class"; `zero` self-negated there because it
  was also a signal token; an em dash inside a bracket class is not byte-safe under mawk.
- `ship-incident-pir-gate.sh` header: "THE BAR — a measured winner needs a corpus hit AND a
  fixture". Every negation cue this PR adds must clear it.

**CLAUDE.md / AGENTS conventions in force.** `cq-write-failing-tests-before` (RED first per item),
`cq-test-fixtures-synthesized-only`, `cq-cite-content-anchor-not-line-number`,
`hr-when-a-command-exits-non-zero-or-prints`, `wg-use-closes-n-in-pr-body-not-title-to`,
`hr-verify-repo-capability-claim-before-assert`.

**Skill description budget (Phase 1.8).** No `description:` frontmatter edit is planned; check skipped.

**External research.** Skipped: strong local context, no third-party API, no security surface.

**Community / functional-overlap discovery.** Skipped: internal refactor of repo-owned machinery;
no stack gap, and no registry skill replaces a repo's own ship fence.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 rows) matched none of the planned paths
(`sync-pr-behind.sh`, `ship/SKILL.md`, `merge-pr/SKILL.md`, `postmerge/SKILL.md`,
`monitor-supersede-guard`, `ship-incident-pir-gate`, `ship-phase-7-poll-fixtures`, `pr-merge-poll`).

## Proposed Solution

### A. `sync-pr-behind.sh` becomes the BEHIND arm (#8383)

One function, `sync_step`, owns one sync attempt, with the fence's semantics verbatim:

1. Refuse an operation it did not start: `MERGE_HEAD`, `rebase-merge`/`rebase-apply`,
   `CHERRY_PICK_HEAD`, `REVERT_HEAD` → `kind=merge_in_progress`, rc 9. Detached HEAD →
   `kind=detached_head`, rc 9. Both lines keep the fence's remediation sentences ("run git status,
   abort it, then re-arm the poll"; "check out the PR branch — run the poll from the PR worktree").
2. `GIT_TRACE=0 GIT_TRACE_CURL=0 GIT_CURL_VERBOSE=0 git fetch origin main`, rc captured with
   `|| rc=$?` before any display `tail`. Failure → `kind=fetch rc=<git's rc>`, **exit 5**.
3. `GIT_TRACE=0 git merge origin/main --no-edit`, rc captured the same way. rc 1 with `MERGE_HEAD` →
   print conflicted paths (`--diff-filter=U` **and** the merge output's `CONFLICT` lines), `git merge
   --abort` (its own failure reported), `kind=merge rc=1`, **exit 6**. Other rc with `MERGE_HEAD` →
   `kind=merge_in_progress rc=<git's rc>`, exit 9, untouched. Non-zero without `MERGE_HEAD` →
   `kind=merge_refused rc=<git's rc>`, worktree state printed, **exit 10** (new; the old script said
   "merge conflict" here and ran an `--abort` with nothing to abort).
4. `git push` (trace-off env), rc captured. Failure → `kind=push rc=<git's rc>`, **exit 7**, local
   merge commit retained.
5. Success → exit 0, no tagged line (the caller owns the `pushed` line and its counter).

**Tagged lines print git's own rc, not the script's exit code** — the existing fixture rows key on
`kind=merge rc=1`, `kind=merge_refused rc=2`, `kind=fetch rc=1`, `kind=push rc=1`.

Every tagged line goes to **stdout** as `[sync-pr-behind] kind=… rc=N — …` (one fixed tag, no
`--tag`/`--prefix` flags: nothing outside the two SKILL.md fences and the fixture reads the old
`[ship.phase7.sync_failed]` tag for these lines, and the fixture matches substrings, not prefixes).

**Strict mode is the script's, not the fence's.** The script runs under `set -euo pipefail`, which
the fence never did. Every display pipe carries `|| true` or is rewritten as a capture:
`git status --short | head -20` (SIGPIPE 141 on a long status), `printf … | grep '^CONFLICT '`
(rc 1 on no match, which would otherwise kill the script *before* `--abort` and leave the tree
conflicted).

Argv: `sync-pr-behind.sh <pr-number> [--max-attempts N]` (standalone, unchanged) and
`sync-pr-behind.sh <pr-number> --step` (one attempt, no `gh` calls). **Any unrecognised argument
exits 2 with usage** — the current parser silently ignores extra flags, which is what makes the
version-skew check in §B necessary. `--help` prints usage plus the exit-code table on stdout, rc 0;
it is the fence's capability probe and the Observability discoverability command.

The standalone loop keeps its `gh pr view` state read (`workflow-fidelity.test.ts` asserts the script
contains `mergeStateStatus`), its DIRTY → `git merge-tree --write-tree` classification (recommended by
`review/SKILL.md` for a CONFLICTING-but-clean PR), and its exit 8, and then calls `sync_step`. On the
DIRTY path that means two fetches (one to classify, one inside `sync_step`); accepted, the fence has
always done the same. Standalone lines keep the substrings `BEHIND detected`, `auto-sync … pushed`,
`BEHIND resolved`, `BEHIND unchanged` and `merge conflict` (the AwaitShell patterns).

| exit | meaning | fence action |
|---|---|---|
| 0 | synced and pushed | print `auto-sync N pushed …`, re-read state |
| 5 | fetch failed | `fetch_failures++`, print `— skipping this sync attempt`, continue |
| 6 | conflict, aborted | stop (the `[sync-pr-behind]` line says why) |
| 7 | push failed, merge retained | stop |
| 9 | an operation it did not start / detached HEAD | stop |
| 10 | merge refused to start | stop |
| 2 | usage / unknown argument | stop |
| anything else | the script itself failed | stop |

### B. Both fences shell out (#8383)

At loop entry, beside the existing worktree precondition:

```bash
# Bare ${CLAUDE_PLUGIN_ROOT}, never a `:-` default: ADR-179 records the default as the vector
# (it resolves to a path the customer controls). The --help probe refuses an older script that
# would silently ignore --step and run a full standalone sync.
SYNC_SH="${CLAUDE_PLUGIN_ROOT}/scripts/sync-pr-behind.sh"
if [[ "$sync_ok" -eq 1 ]] && ! { [[ -r "$SYNC_SH" ]] && bash "$SYNC_SH" --help 2>/dev/null | grep -q -- '--step'; }; then
  echo "[ship.phase7.precondition] sync-pr-behind.sh missing, unreadable or without --step at '$SYNC_SH' — BEHIND auto-sync disabled; the poll heartbeats, sync by hand"
  sync_ok=0
fi
```

The BEHIND arm becomes (≈ 18 lines instead of ≈ 60):

```bash
if [[ "$s" == "OPEN BEHIND" && "$sync_ok" -eq 1 && "$behind_syncs" -lt "$MAX_BEHIND_SYNCS" ]]; then
  behind_syncs=$((behind_syncs+1))
  echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] BEHIND detected — auto-sync attempt ${behind_syncs}/${MAX_BEHIND_SYNCS}"
  sync_rc=0; bash "$SYNC_SH" <number> --step || sync_rc=$?   # `|| rc=$?`: survives errexit (#8339)
  case "$sync_rc" in
    0) echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] auto-sync ${behind_syncs} pushed — auto-merge will re-evaluate"
       s=$(gh pr view <number> --json state,mergeStateStatus --jq '"\(.state) \(.mergeStateStatus)"' 2>&1) \
         || s="fetch-error: $s"
       echo "$s" | grep -qE "^(MERGED|CLOSED|fetch-error)" && break ;;
    5) fetch_failures=$((fetch_failures+1))
       echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.sync_failed] kind=fetch — skipping this sync attempt" ;;
    *) echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.sync_failed] sync-pr-behind.sh exited $sync_rc (see its line above). Stopping the poll."
       break ;;
  esac
elif …  # behind_exhausted arm unchanged
```

Three arms, not six: the stop cases differ only in the reason, and the script's own line carries it.
The DIRTY classification arm, the required-check scan, `behind_exhausted` and the timeout stay in the
fence — they are poll-loop logic, and #8383 names only the BEHIND arm. The merge-pr mirror gets the
same arm with its own `auto-sync N/MAX pushed` line. The fence header comment gains one line: the
BEHIND arm's implementation is `sync-pr-behind.sh`; edit it there.

`pr-merge-poll.ts` `behindSyncInstructions("claude")` is reworded to say the Monitor loop *calls*
`sync-pr-behind.sh --step` (its test gains a `--step` assertion).

### C. Headroom (#8419, #8438)

- **ship:** (i) the fence shrink above (≈ 3.5 KB); (ii) `**Auto-sync on BEHIND.**` steps 1–4 and the
  stdout paragraph become a three-sentence pointer to the script's header, where the same prose
  becomes the script's comment block (≈ 1.9 KB). Projected headroom ≈ 5.4 KB, above the 4096 B floor
  plus a 300 B probe bullet. **No hatch extraction** — see Alternatives. Contingency, only if the
  measured headroom after (i)+(ii) is below 4396 B: extract the settle-then-admin-merge procedure to
  `ship/references/settle-then-admin-merge.md`, **and** have both fences print a
  `[ship.phase7.hatch_check]` line naming that file and the one-line classifier when
  `behind_syncs == 2` (the sync-2 trigger otherwise lives only in prose the agent read an hour
  earlier), and repoint the `behind_exhausted` echo and ship's other citation of the hatch.
- **postmerge:** Phase 3.6's body moves to
  `plugins/soleur/skills/postmerge/references/sentry-error-count-delta.md`. Inline stays: the heading,
  the one-paragraph purpose, the **Run only when** trigger, the directive (*"When a Sentry issue is
  identified, read [sentry-error-count-delta.md](./references/sentry-error-count-delta.md) now and run
  it; otherwise skip silently"*), and the report vocabulary line (`AUTO-RESOLVED` / `STOPPED` /
  `STILL-FIRING` / `SKIPPED`, which Phase 7's report reads). The Graceful Degradation rows for this
  phase stay inline (they carry the skip semantics). The `resolved in Phase 3.6 above` comment moves
  with the second bash block, unchanged. `scripts/sentry-issue.sh`'s header pointer is updated.
  Projected headroom ≈ 7.5 KB.

The postmerge extraction satisfies ADR-229's condition: the reference loads only on the step that
needs it, and that step's trigger text stays in `SKILL.md`.

### D. Terminal monitor liveness (#8420, #7961)

`task_is_complete()` becomes `task_is_terminal()`: after the existing non-assistant filter, count
lines with `grep -cE`:

```text
<status>(completed|failed)</status>|<event>\[Monitor (expired after [0-9]+|timed out)
```

`killed`/`stopped` are left out: zero occurrences on a Monitor in 400 transcripts, and a TaskStop'd
monitor is already cleared by the ledger's stop filter. `timed out` is kept although it has zero
recent hits, because #7961 — which this PR closes — is evidence of exactly that string.

The advisory's closing parenthetical ("every task listed was still running when this was written")
is deleted and replaced with one line: "A `TaskStop` answering `No task found` means that row had
already ended."

### E. Negation-aware `OUTAGE_RE` (#8334)

A function `neg_strip(line)` inside the existing strip `awk`, applied at both print sites (the
`{print}` fall-through and the `ACTUALITY_RE` re-admit). For each `OUTAGE_RE` match on the lowercased
line it examines the text between the previous clause boundary (`. ; : ! ?` and a comma) and the
match start. A match is **denied** when either:

- **(a) a cue governs it directly:** `not`, `no`, `never`, `without`, or a word ending in `n't`,
  followed by at most two words before the match (`no outage`, `wasn't an outage`,
  `never went down`); or
- **(b) a clause-level denial phrase precedes it** anywhere in the same clause: `not that`,
  `rather than`, `instead of` (the #8334 specimen, `not that the feature has stopped working`, is
  four words from its cue and is caught only by this rule).

Word boundaries are spelled `(^|[^a-z])cue([^a-z]|$)` (mawk has no `\<`). A denied match is blanked
with spaces of equal length; every other match on the line survives. The two-word window is what keeps
`we had no alert when prod went down` and `users didn't notice the deploy was blocked` signalling —
both are fixtures that must stay red-flag. Dash boundaries, the curly `n’t`, and a `not only`
exclusion are **not** added up front; each is added only if the Phase 2 corpus run shows a hit it
fixes, and then with its own fixture (the gate's bar).

For each line with a denied match, the awk prints a sentinel line carrying the sanitized source line
(C0/DEL stripped by the existing `_pir_sanitize`). The shell turns each into
`ship-incident-pir-gate: PIR-OUTAGE-NEGATION-SUPPRESSED — "<line>"` on stderr after the guarded
assignment, then **removes the whole sentinel line** from the haystack with a `while read` filter —
not `${haystack//$SENTINEL/}`, which strips only the marker and would leave the payload (which still
contains the denied token) for the verdict grep to match; and not `grep -v`, which exits 1 on an empty
result (the reason the script's pipeline already ends in awk).

The verdict only moves when **every** `OUTAGE_RE` occurrence in the corpus is denied.

## Technical Considerations

- **Mocks must reach a child process.** The fixture mocks `git`/`gh` as shell functions in a
  subshell; the arm now runs `bash "$SYNC_SH"`, a child that inherits functions only via `export -f`.
  The harness wraps the mocks-file source in `set -a`/`set +a` (exports the `MOCK_*` knobs), runs
  `export -f git gh`, and exports `CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/soleur"`. PATH-shim
  executables (the `sync-pr-behind.test.sh` style) were considered and rejected for this suite: the
  fence itself also calls the mocked `git` (DIRTY arm, preconditions), so shims would mean rewriting
  every scenario's mock block, not adding three lines.
- **The mocks now run under the script's strict mode.** `set -euo pipefail` in the child turns mock
  shapes the fence tolerated into rc 1 — e.g. `"diff --name-only") [[ -e … ]] && echo` returns 1 when
  `MERGE_HEAD` is absent, and `"$1 $2"` in a `gh` mock breaks under `-u` on a one-argument call. Each
  such arm gets `|| true` / `${2:-}`. Phase 4 step 1 runs the `--step` unit cases against the
  fixture's exact `SYNC_MOCKS` text first, so a mock/strict-mode mismatch surfaces there, not as a
  misleading `exited 1` in a fence scenario.
- **Every git argv the script uses needs a mock arm.** The mock dispatches on `"$1 ${2:-}"`:
  `fetch origin`, `merge origin/main`, `merge --abort`, `push` (key `"push "`), `rev-parse -q` (must precede the
  `rev-parse *` glob), `rev-parse --git-dir`, `rev-parse --is-inside-work-tree`,
  `rev-parse --abbrev-ref`, `symbolic-ref -q`, `diff --name-only`, `status --short`. The script
  therefore uses the fence's argv — its current `git fetch --no-tags origin main` is dropped. A new
  static check in the fixture extracts every `git <sub>` call from the script and fails if any has no
  mock case, so a new call cannot silently hit the `*) return 0` default.
- **An unmocked child must not reach the live repo.** Mocked scenarios run with CWD
  `$MOCK_STATE/cwd` and `GIT_CEILING_DIRECTORIES="$MOCK_STATE"` (a ceiling must be a proper ancestor
  of the CWD to take effect). If an export is ever dropped, real `git rev-parse --is-inside-work-tree`
  finds no repo, the script exits 3, and the fence stops — a red row, never a push.
- **`--step` does not read state.** The fence already read `mergeStateStatus` this tick.
- **Scenario 10 (real git)** now also exercises the real script, with `CLAUDE_PLUGIN_ROOT` at the
  repo's plugin dir and CWD in the fixture worktree — the production shape #8458 fixed.
- **Version skew is refused, not misread.** The pre-change script ignores `--step` and would run a
  full standalone sync, exiting 0 on "no sync needed" — which the fence would print as `pushed`. The
  `--help | grep -- --step` probe at loop entry disables auto-sync for such a copy (fixture row).
- **Plugin installs.** Claude Code substitutes the bare `${CLAUDE_PLUGIN_ROOT}` in skill text, so the
  pasted fence carries the absolute plugin path (ADR-179). Where it is not substituted and not
  exported (a Grok/cloud shell), the precondition line fires once and the poll still heartbeats and
  still exits on MERGED/required-check/DIRTY. Grok's `GROK_PLUGIN_ROOT` ordering is ADR-179's
  amendment; this fence does not re-decide it.

## User-Brand Impact

**If this lands broken, the user experiences:** a `/ship` run whose Phase 7 poll prints the new
precondition line or `sync-pr-behind.sh exited N` and stops auto-syncing, so a BEHIND PR waits for a
human sync; or a supersede advisory that goes quiet when it should warn; or a PIR prompt that no
longer fires on a PR that fixed a real production event.

**If this leaks, the user's workflow is exposed via:** `sync-pr-behind.sh` running `git merge` and
`git push` in the wrong checkout, or a `:-` fallback path resolving to a script the customer's repo
controls. This PR adds no new write site — the push target is the caller's checked-out branch, as the
inline fence pushes today — it inherits #8458's `$PWD` fix, and it uses the bare
`${CLAUDE_PLUGIN_ROOT}` anchor ADR-179 requires.

**Brand-survival threshold:** aggregate pattern. Each failure mode is loud (a named stop line) or
bounded (one missed PIR prompt), and the one silent-direction risk — the negation strip swallowing a
real report — is measured against the whole plan corpus before merge (AC9).

## Observability

```yaml
liveness_signal:
  what: "sync-pr-behind.sh --help prints its exit-code table; in a live poll every sync attempt prints 'BEHIND detected — auto-sync attempt N/6' then either 'auto-sync N pushed' or a '[sync-pr-behind] kind=…' line plus the fence's stop/skip line, on the Monitor's stdout"
  cadence: "per poll tick that observes OPEN BEHIND (at most 6 per poll invocation)"
  alert_target: "the Monitor notification stream of the session running /ship or /merge-pr"
  configured_in: "plugins/soleur/scripts/sync-pr-behind.sh; ship/SKILL.md and merge-pr/SKILL.md Phase 7 fences"
error_reporting:
  destination: "Monitor stdout ([sync-pr-behind] kind=…, [ship.phase7.sync_failed], [ship.phase7.precondition]); stderr PIR-OUTAGE-NEGATION-SUPPRESSED from ship-incident-pir-gate.sh; the monitor-supersede advisory's additionalContext + systemMessage"
  fail_loud: true
failure_modes:
  - mode: "sync script missing, unreadable, or an older copy without --step"
    detection: "[ship.phase7.precondition] line at loop entry"
    alert_route: "Monitor notification"
  - mode: "sync script exits with a stop code or crashes"
    detection: "[ship.phase7.sync_failed] sync-pr-behind.sh exited N line, poll stops"
    alert_route: "Monitor notification"
  - mode: "negation strip suppresses a real report"
    detection: "PIR-OUTAGE-NEGATION-SUPPRESSED stderr note names each suppressed line in the ship transcript"
    alert_route: "ship Phase 5.5 transcript"
  - mode: "harness changes the monitor terminal record shape so ended monitors reappear"
    detection: "advisory's closing line: a TaskStop answering 'No task found' means the row had already ended"
    alert_route: "the advisory itself"
logs:
  where: "session transcript (Monitor stream, hook additionalContext); .claude/.rule-incidents.jsonl rows keyed rule_id=monitor-supersede"
  retention: "session transcript lifetime; incident ledger per its rotation"
discoverability_test:
  command: "bash plugins/soleur/scripts/sync-pr-behind.sh --help"
  expected_output: "exit codes"
```

## Guard Contract

### Guard 1 — one BEHIND sync implementation, pinned by the Phase 7 fixture

**Property.** Every BEHIND sync the repo can execute — the ship fence, the merge-pr fence, and the
standalone script loop — performs its merge/push through `sync_step` in `sync-pr-behind.sh`, and no
fence contains a `git merge` or `git push` of its own.

**Assembly.** The chokepoint is `sync_step()`. Its callers are (1) the ship Phase 7 fence's BEHIND
arm, (2) the merge-pr §5.2 fence's BEHIND arm, (3) the script's standalone loop. The fixture extracts
(1) and (2) with `extract_block` and runs every sync scenario against both (`run_scenario_both`), so
each scenario executes the script through each fence; (3) is covered by `sync-pr-behind.test.sh`. A
static assertion over each extracted block requires zero non-comment, non-`echo` lines matching
`(^|[;&|[:space:]])git (merge( |$)(origin|--abort|--no-edit)|push( |$))` — the DIRTY arm's
`git merge-tree` and its `echo "Resolve locally: git merge origin/main"` do not match — and exactly
one `bash "$SYNC_SH" 4387 --step` line (after the `<number>` substitution).

**Mutation matrix:**

| # | mutation (design-derived) | must go RED |
|---|---|---|
| M1 | second member: fix only merge-pr, leave ship's inline arm | static assertion on `:ship` (it quantifies over both blocks) |
| M2 | in `sync_step`, test the display pipe (`if ! git merge … \| tail -5`) instead of the captured rc (the #8339 bug) | scenario 6 on both fences (`pushed` forbidden, abort sentinel required) |
| M3 | fence maps exit 5 to the stop arm | scenario 8 (`behind_exhausted` with `fetch_failures=6/6` required) |
| M4 | `sync_step` writes its `kind=` line to stderr | a stdout-only assertion on the `[sync-pr-behind]` line in every sync scenario |
| M5 | `sync_step` returns 6 for a refused merge (the old conflation) | scenario 6b (`kind=merge_refused`, no abort sentinel) |
| M6 | drop the `--help \| grep -- --step` probe | new scenario 13: a stub script that ignores `--step` and exits 0 → `pushed` must never print, precondition line required |
| M7 | drop `\|\| true` from the `git status --short \| head -20` display | new scenario 6i: 25 status lines on a refused merge → `kind=merge_refused` still printed, exit 10 |

**Harness rows.**

- H1: drop `export -f git gh` from `run_scenario` → the sync scenarios must RED (the child finds no
  repo under the ceiling and exits 3 → stop line, no `pushed`).
- Must-PASS non-canonical: the mocked argv static check passes when the script gains a git call
  that *does* have a mock arm (so the check is not simply "no new git calls").

**Anchor.** The token list, the extracted blocks and the script all live in this diff. The anchor
outside any single edit is behavioural: the scenarios execute the real script through the real
fences, so hollowing either reds scenarios a token-list edit cannot satisfy.

### Guard 2 — the PIR negation strip

**Property.** An `OUTAGE_RE` occurrence is removed from the haystack if and only if a cue governs it
within two words or a denial phrase precedes it in the same clause; every other occurrence, including
one on the same line, reaches the verdict greps, and every removal is disclosed on stderr.

**Assembly.** The single strip `awk` in `ship-incident-pir-gate.sh`; `neg_strip()` is called at
**both** print sites (the `ACTUALITY_RE` re-admit and the `{print}` fall-through). Lines dropped by
`skip`/`DROP_RE` never reach it and need not. The sentinel lines are removed whole before the two
`grep -qiE` calls.

**Mutation matrix:** (new rows in `ship-incident-pir-gate-mutation.test.sh`)

| # | mutation | fixture that must flip |
|---|---|---|
| N1 | delete the `neg_strip` call at the fall-through | `negated-outage-only.md` signals (must not) |
| N2 | drop the clause boundaries (window runs to line start) | `negation-in-prior-clause-real-report.md` stops signalling (must signal) |
| N3 | line-scoped: blank the whole line when any match is denied | `negated-and-real-token-same-line.md` stops signalling |
| N4 | second member: examine only the first match on a line | `two-tokens-second-denied.md` (first undenied match inside a code span is stripped earlier; the only live token is the second, denied one) signals (must not) |
| N5 | widen rule (a) from two words to the whole clause | `no-alert-when-prod-went-down.md` stops signalling |
| N6 | delete rule (b) | `denial-specimen-8334.md` signals (must not) |
| N7 | remove only the marker, not the whole sentinel line | `negated-outage-only.md` signals (the payload re-injects the token) |
| N8 | call `neg_strip` only at the fall-through, not the re-admit | `actuality-line-only-token-denied.md` signals (must not) |

**Harness rows.** H1: the battery's green-baseline control still runs first and aborts on red. Must-PASS
non-canonical: `real-report-with-unrelated-negation.md` (a genuine past-tense report whose line also
carries a denial of a *different* subject) signals under the unmutated script. The
precondition-holds-property-fails row is `negation-in-prior-clause-real-report.md`: a cue *is* on the
line and the report must still signal.

**Anchor.** The corpus measurement (AC9) runs the gate over every plan under
`knowledge-base/project/plans/` (recursive) before and after, so a window that is too wide shows up as
flipped plans no fixture anticipated.

### Guard 3 — monitor liveness

**Property.** A monitor the advisory lists has no terminal record — `completed` or `failed` status,
or an `expired`/`timed out` event — keyed to its task id in a non-assistant transcript record, and a
monitor with no such record is still listed.

**Assembly.** `task_is_terminal()` is the only liveness predicate; the candidate loop calls it once
per arm after the ledger's stop filter.

**Mutation matrix:** (new cases in `monitor-supersede-guard.test.sh`)

| # | mutation | case that must go RED |
|---|---|---|
| T1 | drop the `expired after` alternative | 31: expired monitor is SILENT |
| T2 | drop `failed` | 32: failed monitor is SILENT |
| T3 | drop `timed out` | 33: legacy timed-out notice is SILENT |
| T4 | predicate always true (over-correction into silence) | case 2 (a live second monitor is REPORTED) and 34 |
| T5 | second member: one expired + one live on one target, loop stops after the first terminal arm | 34: exactly the live id is named, the expired id is absent |

**Harness rows.** H1: a new `expire_task` helper writes the measured shape (`type: queue-operation`,
`content` with `\n`-separated tags, no `<status>`); mutated to write `type: assistant`, case 31 must
RED (the fixture record is not a strawman — the existing case 7 already pins the assistant filter
itself). Must-PASS non-canonical, case 35: an expiry notice reading `after 20m with 3 events
delivered` → SILENT. `MIN_CASES` 30 → 35.

## Implementation Phases

Order is fixed by one dependency: Phase 4 needs #8458 on `main`. Phases 1–3 do not touch
`sync-pr-behind.sh` and run first. Mutation rows in Guards 1 and 3 are run once each during the work
(edit, run, restore) as RED proofs; Guard 2's rows are automated in the battery.

### Phase 1 — #8420 / #7961 monitor liveness

1. RED: cases 31–35 plus `expire_task`/`fail_task` helpers using the measured record shape;
   `MIN_CASES=35`. Run; 31–34 fail.
2. GREEN: `task_is_terminal()` with `grep -cE` and the §D alternation; replace the advisory's closing
   parenthetical; update the header comment's route-3 description to name the terminal set.

### Phase 2 — #8334 negation-aware PIR scan

1. Measure first: run the unmodified gate over every plan (recursive) and record the firing count and
   list.
2. RED: the Guard 2 fixtures plus the #8334 specimen (synthesized, with a `production` token
   elsewhere; `cq-test-fixtures-synthesized-only`) and their verdict rows in
   `ship-incident-pir-gate.test.ts`.
3. GREEN: `neg_strip()`, the sentinel, whole-line sentinel removal, the stderr note (§E).
4. Add N1–N8 to the mutation battery with content anchors.
5. Re-measure; read every plan that flipped yes → no via the suppressed lines the note names. Drop any
   cue that flips a plan cited by a file in `knowledge-base/engineering/operations/post-mortems/`, and
   any cue or phrase with zero corpus hits (with its fixture). Add a dash boundary / curly `n’t` only if
   the run shows a hit it fixes. Record before/after counts, the flipped list and per-cue hit counts in
   the script header, the way the soak gate records its 275 → 209.

### Phase 3 — #8419 postmerge headroom

1. Move Phase 3.6's body to `postmerge/references/sentry-error-count-delta.md` (§C); update
   `scripts/sentry-issue.sh`'s pointer.
2. `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`; record
   `wc -c` headroom.

### Phase 4 — #8383 + #8419 ship: one BEHIND executable

0. **Gate:** `git fetch origin main`, then `gh pr view 8458 --json state --jq .state` is `MERGED` and
   `git grep -c 'cd "$REPO_ROOT"' origin/main -- plugins/soleur/scripts/sync-pr-behind.sh` prints
   nothing. Then `git merge origin/main` (a merge, not a rebase: the branch already carries pushed
   plan commits). If #8458 is still open when Phases 1–3 finish, commit them and arm a Monitor on
   `gh pr view 8458 --json state`; if #8458 closes unmerged, stop and surface it — this phase must not
   re-implement its fix.
1. RED (script): extend `sync-pr-behind.test.sh` (on top of #8458's `( cd … )` wrappers and
   `assert_in_fixture`) with `--step` cases — success (exit 0, no tagged line), conflict (6,
   `kind=merge rc=1`, aborted), refused (10, nothing aborted, 25-line status), in-progress (9),
   detached (9), push rejected (7, merge commit retained), tagged lines on stdout, unknown argument
   (2), `--help` (0, prints `--step` and `exit codes`); raise its floor. Also run the `--step` cases
   once against the fixture's `SYNC_MOCKS` text.
2. GREEN (script): `sync_step`, strict argv, `--help`, `|| true` on display pipes, header comment
   carrying the moved Auto-sync prose; standalone loop calls `sync_step`.
3. RED (fixture): harness (`set -a`, `export -f`, `CLAUDE_PLUGIN_ROOT`, `$MOCK_STATE/cwd` + ceiling),
   mock strict-mode fixes, the static no-inline assertion, the git-argv-has-a-mock check, scenarios
   6i and 13; move the removed inline tokens (`sync_out="$(GIT_TRACE=0 git merge …`,
   `merge conflict, aborting sync`, `kind=merge_refused`, `kind=merge_in_progress`,
   `git push failed after merge`) from the mirror token list to a script-content check; add
   `--step` and `sync-pr-behind.sh exited` to the list; update must-match rows whose text now
   comes from the `[sync-pr-behind]` line.
4. GREEN (fences): replace the BEHIND arm in both fences (§B), add the `SYNC_SH` precondition, update
   the fence header comment.
5. Replace `**Auto-sync on BEHIND.**` steps 1–4 with the pointer; `pr-merge-poll.ts` wording +
   `--step` assertion.
6. Measure ship headroom; if below 4396 B, apply the §C contingency.

### Phase 5 — close-out

1. Touched-suite run: `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`,
   `bash plugins/soleur/test/sync-pr-behind.test.sh`,
   `bun test plugins/soleur/test/pr-merge-poll.test.ts plugins/soleur/test/harness.test.ts
   plugins/soleur/test/ship-incident-pir-gate.test.ts plugins/soleur/test/workflow-fidelity.test.ts
   plugins/soleur/test/components.test.ts`, `bash scripts/ship-incident-pir-gate-mutation.test.sh`,
   `bash .claude/hooks/monitor-supersede-guard.test.sh`, `bash plugins/soleur/test/concurrent-ship.test.sh`,
   `bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh`, and the budget lint against the
   merge base.
2. Route-to-definition proof (AC4): append a ~300 B probe bullet to each of ship and postmerge, run
   the lint, confirm OK, revert the probe.
3. PR body: `Closes #8383`, `Closes #8419`, `Closes #8438`, `Closes #8420`, `Closes #7961`,
   `Closes #8334` on separate lines in the body (not the title). Note #7801 as already fixed by #7806
   and still open. `OUTAGE_RE` vocabulary in backticks only.

## Files to Edit

- `plugins/soleur/scripts/sync-pr-behind.sh` — `sync_step`, `--step`, `--help`, strict argv (rc 2 on
  unknown), stdout tagging with git's rc, exit 10, fence argv, `|| true` display pipes, header prose
  (on top of #8458).
- `plugins/soleur/test/sync-pr-behind.test.sh` — `--step` cases, floor.
- `plugins/soleur/skills/ship/SKILL.md` — Phase 7 fence BEHIND arm, `SYNC_SH` precondition, fence
  header comment, `**Auto-sync on BEHIND.**` pointer; the protocol bullet near the top
  (`BEHIND stop-and-sync`) names `--step`.
- `plugins/soleur/skills/merge-pr/SKILL.md` — §5.2 mirror BEHIND arm + precondition.
- `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` — harness exports, CWD bounding, mock
  strict-mode fixes, static assertions, token list, scenarios 6i/13, row adjustments.
- `plugins/soleur/lib/pr-merge-poll.ts`, `plugins/soleur/test/pr-merge-poll.test.ts`.
- `plugins/soleur/skills/postmerge/SKILL.md` — Phase 3.6 reduced to trigger + directive + vocabulary.
- `scripts/sentry-issue.sh` — header pointer only.
- `.claude/hooks/monitor-supersede-guard.sh`, `.claude/hooks/monitor-supersede-guard.test.sh`.
- `scripts/ship-incident-pir-gate.sh`, `plugins/soleur/test/ship-incident-pir-gate.test.ts`,
  `scripts/ship-incident-pir-gate-mutation.test.sh`.

## Files to Create

- `plugins/soleur/skills/postmerge/references/sentry-error-count-delta.md`
- Fixtures under `plugins/soleur/test/fixtures/ship-incident-pir-gate/`: `negated-outage-only.md`,
  `negation-in-prior-clause-real-report.md`, `negated-and-real-token-same-line.md`,
  `two-tokens-second-denied.md`, `no-alert-when-prod-went-down.md`,
  `didnt-notice-deploy-was-blocked.md`, `actuality-line-only-token-denied.md`,
  `real-report-with-unrelated-negation.md`, `denial-specimen-8334.md`, plus one fixture per cue kept
  after the Phase 2 measurement.
- Contingency only (§C): `plugins/soleur/skills/ship/references/settle-then-admin-merge.md`.

Glob check: every edited path exists (`git ls-files`); the new files' parent directories exist
(`postmerge/references/`, the fixtures directory, `ship/references/`).

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Fence calls `sync-pr-behind.sh <n> --max-attempts 1` as #8383 sketched | The standalone mode re-reads state, re-classifies DIRTY, and exits 8 when GitHub has not yet recomputed `mergeStateStatus` after a push — the normal case seconds after a push — so a successful sync would read as "still BEHIND" |
| `"${CLAUDE_PLUGIN_ROOT:-plugins/soleur}"`, like `SS_LIB` | ADR-179: the `:-` default is the vector — it resolves to a path the customer controls. `SS_LIB` predates the ADR and gates only an advisory lock |
| Extract the settle-then-admin-merge hatch to `ship/references/` up front | Not needed for the 4 KB floor (≈ 5.4 KB from the consolidation), and its sync-2 trigger fires in no fence line, so the reference would be loaded only if the agent remembers prose it read an hour earlier (the ADR-229 trap). Kept as a contingency with a fence-printed trigger |
| `--tag` / `--prefix` flags to keep the lines byte-identical | Nothing outside the fences and the fixture reads those lines; the fixture matches substrings. Also removes a child-must-not-call-`date` hazard |
| PATH-shim mocks instead of `export -f` | The fence also calls the mocked `git`; shims mean rewriting every scenario's mock block |
| Consolidate the whole poll loop into a script | Larger paste-contract change, not asked for; the required-check scan and DIRTY classification are loop logic with their own rows |
| Extract postmerge Phase 3.7 instead of 3.6 | `ship/SKILL.md`'s merge→deploy protocol step 2 cites Phase 3.7's deploy-arm predicate for **every** merge — moving it behind the 3.7 trigger is the ADR-229 trap |
| Line-scoped negation drop (the issue's first sketch) | Silences a real report beside an unrelated denial |
| A 60-byte negation window | Catches `we had no alert when prod went down`; the two-word window plus clause-level phrases is narrower and still covers the specimen |
| Include `killed`/`stopped` in the monitor terminal set | Zero Monitor occurrences in 400 transcripts; TaskStop is already covered by the ledger |
| Raise the ceilings | Forbidden in the same diff by the lint, and concedes the ratchet's purpose (#8438) |

## Non-Goals

- #7800 (a citation of another `post-mortem` plus the adjective `live`): a citation shape, not a
  denial; untouched by the negation strip. Stays open.
- #7801: already fixed by #7806; stays open (not closed by this PR).
- Lowering any ceiling in `skill-body-budget.json` (a separate ceiling-only PR by the lint's contract).
- Reconciling Phase 7's "run every Monitor from a detached `origin/main` worktree" with the BEHIND
  arm's need for a checked-out PR branch. Pre-existing (the arm already refuses on a detached HEAD);
  the script's `detached_head` line now names it. The work phase searches for a tracking issue and
  files one if none exists (`wg-when-an-audit-identifies-pre-existing`).

## Acceptance Criteria

- **AC1** The fixture's static assertion passes: each extracted Phase 7 block has zero non-comment,
  non-`echo` lines matching the Guard 1 regex and exactly one `bash "$SYNC_SH" 4387 --step` line; the
  git-argv-has-a-mock check passes.
- **AC2** `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` passes with every existing
  scenario still run against both fences, plus scenarios 6i and 13.
- **AC3** `bash plugins/soleur/test/sync-pr-behind.test.sh` passes, including #8458's SUT-outside-repo
  case and the new `--step` cases; `bash plugins/soleur/scripts/sync-pr-behind.sh --help` exits 0 and
  prints `exit codes` and `--step`; `bash plugins/soleur/scripts/sync-pr-behind.sh 1 --bogus` exits 2.
- **AC4** Against the merge base: `wc -c < plugins/soleur/skills/ship/SKILL.md` ≤ 274000 − 4096 and
  `wc -c < plugins/soleur/skills/postmerge/SKILL.md` ≤ 48000 − 4096; the lint reports OK; a 300 B
  probe bullet appended to each still passes (then reverted).
- **AC5** `postmerge/SKILL.md` Phase 3.6 links `sentry-error-count-delta.md` from a sentence naming its
  trigger, and `git grep -n 'postmerge/SKILL.md' scripts/sentry-issue.sh` points at the new file.
- **AC6** `bash .claude/hooks/monitor-supersede-guard.test.sh` passes with ≥ 35 cases: expired, failed
  and legacy timed-out monitors each SILENT; one live + one expired on one target naming only the live
  id.
- **AC7** The advisory text no longer contains `every task listed was still running`.
- **AC8** `bun test plugins/soleur/test/ship-incident-pir-gate.test.ts` passes: `negated-outage-only`,
  `denial-specimen-8334`, `two-tokens-second-denied` and `actuality-line-only-token-denied` → no
  signal; `negation-in-prior-clause-real-report`, `negated-and-real-token-same-line`,
  `no-alert-when-prod-went-down`, `didnt-notice-deploy-was-blocked` and
  `real-report-with-unrelated-negation` → signal; one fixture per kept cue; all existing verdicts
  unchanged.
- **AC9** The corpus re-measurement is recorded in the gate's header: plans firing before/after, the
  flipped list, per-cue hit counts, and zero flips on plans cited from
  `knowledge-base/engineering/operations/post-mortems/`.
- **AC10** `bash scripts/ship-incident-pir-gate-mutation.test.sh` passes with N1–N8 each reported as
  flipping, none vacuous.
- **AC11** Running the gate on `negated-outage-only.md` prints `PIR-OUTAGE-NEGATION-SUPPRESSED` on
  stderr and exits 1.
- **AC12** `bun test plugins/soleur/test/pr-merge-poll.test.ts plugins/soleur/test/harness.test.ts
  plugins/soleur/test/workflow-fidelity.test.ts plugins/soleur/test/components.test.ts`,
  `bash plugins/soleur/test/concurrent-ship.test.sh` and
  `bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh` pass.
- **AC13** The PR body carries `Closes #8383`, `#8419`, `#8438`, `#8420`, `#7961`, `#8334`, one per line.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change to Soleur's own ship,
postmerge and hook machinery. Product/UX Gate: NONE (no UI-surface file in either Files list).

## Test Scenarios

| # | input | expected |
|---|---|---|
| S1 | fence, BEHIND, clean merge + push | `auto-sync 1 pushed`, re-read state, MERGED |
| S2 | fence, BEHIND, conflict | `[sync-pr-behind] kind=merge rc=1`, abort observed, stop line, no `pushed` |
| S3 | fence, BEHIND, fetch fails 6× | `fetch_failures=6/6` in `behind_exhausted` |
| S4 | fence, script missing | `[ship.phase7.precondition]` line, heartbeats, no sync |
| S5 | fence, older script that ignores `--step` | precondition line, never `pushed` (scenario 13) |
| S6 | fence under `set -e` host | S2 outcome, shell survives |
| S7 | refused merge with 25 status lines | `kind=merge_refused`, exit 10 (scenario 6i) |
| S8 | standalone, SUT outside repo (#8458) | caller's worktree moves, decoy does not |
| S9 | monitor: armed, expired, re-armed on same target | SILENT |
| S10 | monitor: one live, one expired, same target | lists only the live id |
| S11 | PIR: only token denied | exit 1, suppression note |
| S12 | PIR: `we had no alert when prod went down` | `INCIDENT-SIGNAL: yes` |

## Dependencies & Risks

- **#8458 must merge first** (Phase 4 step 0). Mitigation: Phases 1–3 are independent and land first;
  Phase 4 waits on a Monitor and never copies its fix.
- **Fixture harness change is the riskiest edit.** Mitigation: ceiling-bounded CWD, the argv-mock
  check, harness row H1, and running the `--step` cases against `SYNC_MOCKS` first.
- **Negation false negatives.** Mitigation: two-word window, occurrence scoping, corpus-wide
  measurement, per-cue hit bar, stderr disclosure of every suppression.
- **Shells where `${CLAUDE_PLUGIN_ROOT}` is neither substituted nor exported** lose auto-sync, loudly.
  Accepted over a `:-` fallback (ADR-179).

## Sharp Edges

- This plan and the PR body are PIR-gate corpus. Keep every `OUTAGE_RE` token in backticks or
  fences. Verify before marking ready: `bash scripts/ship-incident-pir-gate.sh --pr <N>` exits 1.
- Do not `git stash` in this worktree; commit WIP instead.
- `sync-pr-behind.sh` ships to customer hosts, including macOS's stock bash 3.2: no `mapfile`, no
  `${x,,}`, no associative arrays, no `timeout`/`sed -i`/`date -d`. The PIR gate's new awk must run
  under mawk and BSD awk (`match()`/`index()`/`substr()` only; no `gensub`, no `\y`, no `\<`).
- The fixture shadows `date`/`sleep` as functions in the parent subshell only; the script must not
  call either.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6.
- `ship/SKILL.md` edits make postmerge Phase 3.7 fire (`PIPELINE_GATE_CHANGE=1`) on this PR's own
  postmerge; expected, and the 3.6 extraction does not touch 3.7.

## Plan Review Revisions (2026-09-21)

Panel: DHH, Kieran, code-simplicity, CTO (devex), plus the Step 4.5 advisor consult. Applied:

- **Bare `${CLAUDE_PLUGIN_ROOT}`** instead of the `:-` default (Kieran P0, ADR-179).
- **Version-skew probe** (`--help | grep -- --step`) and strict argv rejecting unknown flags: the old
  script ignores `--step` and would report a no-op as `pushed` (advisor + Kieran; the plan's earlier
  "exits 2" claim was false, verified against the argv parser).
- **Static assertion regex** narrowed so the DIRTY arm's `git merge-tree` and its recovery `echo` do
  not match (Kieran P0).
- **Strict-mode hazards** in the script's display pipes and in the mocks (Kieran P1, advisor).
- **`kind=` lines carry git's rc** (Kieran P1).
- **Guard 2 rows N4/N8 rebuilt** so each mutation can flip a verdict; **whole-line sentinel removal**
  so the payload cannot re-inject the token (Kieran P1).
- **Negation window tightened** to two words + clause-level phrases; 60-byte cap, dash boundary,
  `not only` exclusion deferred to measurement (advisor, DHH, simplicity).
- **Cut:** the hatch extraction (now a contingency with a fence-printed trigger — DHH, simplicity,
  CTO P3), `--tag`/`--prefix`, the six-arm `case` (now three), `killed`/`stopped`, the live-`HEAD`
  sentinel, the relocated-root must-PASS row, harness row H2, PR-body mutation ceremony.
- **Ceiling as a proper ancestor** of the CWD; fetch before the #8458 gate grep; `grep -cE`;
  `MIN_CASES=35` (Kieran P2).
- **Kept against a cut recommendation:** `--help` (it is the version probe and the discoverability
  command); `timed out` (#7961's own evidence); `export -f` over PATH shims (fence also uses the mocks).
- **Not applied:** CTO P1's `find`-in-the-plugin-cache fallback chain (a `find` over a path the
  customer's machine controls reintroduces the ADR-179 vector); CTO P2's pasted `$PR_WT` (widens the
  paste contract; the `detached_head` line names the cause instead).
