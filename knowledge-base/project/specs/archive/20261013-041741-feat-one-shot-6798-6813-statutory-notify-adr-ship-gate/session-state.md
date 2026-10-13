# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-07-22-fix-statutory-notify-path-adr-ordinals-and-ship-pir-gate-plan.md`
- Companion: `knowledge-base/project/specs/feat-one-shot-6798-6813-statutory-notify-adr-ship-gate/tasks.md`
- Draft PR: #6834
- Status: complete

### Collision Gate Disposition (Step 0a.5)
All six targets (#6798, #6799, #6800, #6801, #6802, #6813) confirmed OPEN. Every probe
surfaced merged PR #6782 identically — adjudicated a **cited-predecessor false positive**:

- `linked:issue` discriminator: PR #6782 `closingIssuesReferences == [6781]`; none of the six
  are closed by it.
- Body-probe scope discriminator: paths overlap (`notifications.ts`, ADR files), but each issue
  body states verbatim "Deferred from #6781 per `wg-when-deferring-a-capability-create-a`" with
  an explicit rationale for non-inclusion, and #6782's own body (line 71) enumerates all six as
  filed follow-ups. Genuinely new scope on both sides of the link.

### Errors
1. `Write` blocked once by the IaC-routing hook — matched the literal `doppler secrets set`
   inside a *negative* assertion in the plan's Infrastructure (IaC) section. Recovered by
   rewording to token-free phrasing rather than adding an `iac-routing-ack` opt-out. No content lost.
2. No `Task` tool available in the planning subagent, so domain leaders, the plan-review agent
   panel, and deepen-plan's research fan-out could not be spawned. Mitigated, not skipped:
   domain assessment done inline with a method note; `/soleur:plan-review` and the
   `soleur:legal:clo` review are written into `tasks.md` as **blocking** steps 0.9 and 1.4.
3. No aborts.

### Decisions
- **#6801 behavioral question DECIDED — close the cliff, do not accept it.** Re-anchor the scan
  window from `received_at` to `acknowledged_at`, same 60 days; no migration needed
  (`acknowledged_at` exists and is WORM per migration 102). Two issue premises were falsified and
  corrected: `infoSilentFallback` logs at `info` and **cannot** reach Better Stack (Vector keeps
  `level_int >= 40`), so the single emit **level-escalates** to `warn` when counters are non-zero;
  and `infoSilentFallback` **silently drops `tags`**, so #6781's `repin_suppressed` tag has never
  reached Sentry (census: exactly one affected site).
- **#6799 carries a consequence the issue misses.** Widening the T-7 equality to a band makes the
  `headsup` 23505 fire every day in steady state, destroying #6781's sole double-fire detector.
  The plan splits the counter (`suppressed` = daily-key only; `headsUpAlreadySent` = headsup-key)
  and names the residual ceiling (≤5-day detection delay via the daily arm). `breach-art33`'s
  dead T-7 arm is documented as intentional, not fixed.
- **#6802 makes the send-marker mean *delivered*.** Zero-delivery falls through to email,
  `notifyOfflineUser` returns a `NotifyOutcome`, and the cron **rolls the marker back** when
  nothing landed — restoring the pre-#6781 self-heal as a designed rollback. Non-410 pruning
  explicitly rejected in writing. New **ADR-134** (verified free against freshly-fetched
  `origin/main`; highest is ADR-132) plus an **ADR-037 amendment**; `pushService` added to the C4
  model, which had no Web Push external system at all.
- **#6800 takes zero renames.** Filename is authoritative; the disagreeing frontmatter ordinal is
  *removed* (`ADR-NNN` appears 11,784× repo-wide, so renumbering trades one ambiguity for a set of
  dangling refs). Enforcement lands in the existing, already-CI-wired `check-adr-ordinals.sh`.
  Applied migrations 122/135 are **not** edited — `run-migrations.sh` content-hashes them and
  `dev-migration-drift-probe` compares.
- **#6813's deliverable is the test, not the regex.** It extracts `OUTAGE_RE`/`PROD_RE` from
  `ship/SKILL.md` and runs the real `grep` (stronger than the sibling test's JS-port precedent,
  which drifts). The plan file is itself a fixture. Measured in a shell: the gate's `A && B && echo`
  chain **exits 1 on no-signal**, so a `set -euo pipefail` harness would invert the three assertions
  that matter — recorded as tasks.md 5.2.3.

### Components Invoked
- `Skill: soleur:plan` → `Skill: soleur:deepen-plan`
- `gh issue view` ×11, `gh pr view`, `gh issue list --label code-review` + `jq` (overlap check),
  `git fetch origin main`, `git log --grep` / `git show origin/main:` (attribution probes)
- deepen-plan gates run inline: 4.4 precedent-diff, 4.5 network-outage (triggered, adjudicated
  non-applicable), 4.55 downtime (N/A), 4.6 user-brand halt (PASS), 4.7 observability halt (PASS),
  4.8 PAT-shaped halt (PASS), 4.9 UI-wireframe (N/A)
- Verification passes: rule-ID liveness vs `AGENTS.md` + `retired-rule-ids.txt`, path-citation
  resolution, op-slug literal consistency, ADR-ordinal derivation from live `origin/main`,
  `set -e` semantics measurement
- **Not invoked (deferred to `/work`, both blocking):** `soleur:legal:clo`, `/soleur:gdpr-gate`,
  `/soleur:plan-review`
