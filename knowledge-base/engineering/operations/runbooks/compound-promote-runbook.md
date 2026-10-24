---
title: "Compound Promotion Loop — operator runbook"
type: runbook
issue: "#2720"
last_updated: 2026-10-24
---

# Compound Promotion Loop — operator runbook

## What it does

The Compound Promotion Loop is Layer 2 of the self-healing-workflow design.
A weekly Inngest cron function (Sunday 00:00 UTC) at
`apps/web-platform/server/inngest/functions/cron-compound-promote.ts`
reads `knowledge-base/project/learnings/`, runs a deterministic GDPR +
retired-rule pre-pass over the corpus, then calls the Anthropic API to cluster
learnings by problem/root-cause. When a cluster reaches the quorum of **5**
distinct source learnings (`PROMOTION_QUORUM` in the handler, enforced by the
server, not only requested in the prompt: ADR-092 Amendment 2026-10-20)
the loop opens up to **2 draft PRs per week**, each proposing a skill-instruction
edit or an `AGENTS.rules.md` rule addition. The loop **never auto-merges** —
an operator confirms each proposal via normal PR review.

**Upstream weakness signal (#6037):** the weekly read-only weakness-miner
(`.github/workflows/weakness-miner.yml` → `scripts/weakness-miner.sh`, Sunday
06:00 UTC) clusters recently-added learnings into a ranked recurring-failure
digest at `knowledge-base/project/weakness-digest.md` (opened as its own bot-PR).
Triage that digest to decide which recurring patterns are worth a `/compound`
promotion — it is the detection half of the loop this runbook operates.

**Handler:** `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`
**Inngest function ID:** `cron-compound-promote`
**Sentry monitor:** `scheduled-compound-promote`

The capability is **default OFF**. Enabling sends summaries (path + first 10
lines per file) of your learnings corpus to Anthropic.

## Opt in

The cron reads `knowledge-base/project/promotion-config.yml` from
`actions/checkout` of main, so opt-in requires a committed flip. The file
is tracked (not gitignored); default content is `enabled: false`.

```bash
# 1. Flip enabled: true in the tracked config.
sed -i 's/^enabled: false/enabled: true/' \
   knowledge-base/project/promotion-config.yml

# 2. Commit and push the flip via PR. Operators reviewing the PR can veto.
git add knowledge-base/project/promotion-config.yml
git commit -m "chore: enable compound-promotion-loop"
# ... open a PR and merge after review ...

# 3. Confirm the next scheduled run will fire (Sunday 00:00 UTC) or trigger now:
curl -s -X POST https://soleur.ai/api/inngest \
  -H "content-type: application/json" \
  -d '{"name":"cron/compound-promote.manual-trigger","data":{}}'
```

> **Note.** `promotion-config.yml.example` is documentation only — it shows
> the schema and data-flow disclosure. The live file the cron reads is
> `promotion-config.yml` (tracked, default `enabled: false`). Editing the
> example does nothing.

## Opt out / kill switch

```bash
# Hard kill — the next cron tick exits no-op without contacting Anthropic.
sed -i 's/^enabled: true/enabled: false/' \
   knowledge-base/project/promotion-config.yml
git add knowledge-base/project/promotion-config.yml
git commit -m "chore: disable compound-promotion-loop"
# ... merge ASAP via PR (or revert the original opt-in commit) ...
```

The flip produces the `::compound-promote-status::disabled` sentinel and
exits 0. The kill is live as soon as the disable PR merges to main.

## Reviewing a `self-healing/auto` PR

Each draft PR is labeled `self-healing/auto` and carries a provenance trailer
in the commit message (Bot-Author, Source-Learnings, Threshold-Hit,
Cluster-Hash, Tier). Apply this 5-bullet acceptance heuristic before
clicking **Ready for review**:

1. **Hash integrity.** The workflow already re-derives `sha256(sorted(source_learnings))`
   and refuses to open the PR on mismatch (AC11). Spot-check by re-running
   the hash locally on the listed sources.
2. **Tier placement.** `tier: skill` → diff edits a single
   `plugins/soleur/skills/*/SKILL.md` (domain-scoped). `tier: agents-core` →
   diff edits `AGENTS.rules.md` AND the new rule is genuinely cross-cutting
   (silent failure or blast radius, no single-file trigger). Reject anything
   that should be hook-enforced or scanner-enforced — those don't belong in
   the registry per `cq-agents-md-tier-gate`.
3. **Byte budget.** For `agents-core` PRs, verify the post-merge always-loaded
   payload stays under the thresholds defined in
   `scripts/lint-agents-rule-budget.py` (the authority: warn at
   `B_ALWAYS >= 44000`, reject above `46000`), which
   `cq-agents-md-why-single-line` restates. Measure by running the linter
   rather than `wc -c` — the thresholds are defined over frontmatter-stripped
   bytes, and a raw `wc -c` overstates the payload by the frontmatter size.
   The driver script's prompt asks the LLM to propose against the lower warn
   floor, and a post-apply gate reverts anything above the hard ceiling, but
   caller-side verification is the second line of defense.
4. **Rule shape.** Each AGENTS-md rule body uses single-line `**Why:**`;
   evidence longer than one sentence belongs in the linked PR or learning
   file, not in the rule body.
5. **GDPR sanity.** The shell pre-pass excluded any learning matching the
   canonical PII regex. Scan the PR body for unexpected fragments anyway —
   the regex is heuristic (email, IPv4, IBAN) and may miss novel patterns.
   Reject if the body quotes anything that looks like PII.

If any of the five fail, **close the PR**. The append-only audit log
(`knowledge-base/project/learnings/promotion-log.md`) records accepted-or-pending
proposals only; the close acts as the rejection signal, and rejection state is read
from GitHub PR state through Octokit (ADR-297), not from the log. The loop's
per-week cap counts open PRs only, so a closed proposal won't block next week's run.
On the patterns path a closed-unmerged proposal also suppresses its exact cluster for
60 days from `closed_at` (see the `input` option section below).

## Reverting a promoted rule

If a merged promotion turns out to be a false positive, demote it via the
standard rule-retirement path: append the rule's ID to
`scripts/retired-rule-ids.txt` with format `<id> | <YYYY-MM-DD> | <PR> | <breadcrumb>`.
Removing the body from `AGENTS.rules.md` (and its pointer from `AGENTS.md`) is a
human edit in the same PR — `scripts/rule-prune.sh` never edits the corpus — and
the linter rejects any future reintroduction of the retired ID.

## How a proposal is drafted (#10552)

The weekly run is two model calls per cluster, not one. Phase 1 clusters the learnings and names a
`target_path` (and is told which targets are small enough to edit). Phase 2 shows the model the REAL
target file and asks for an anchor line plus the lines to insert after it. The SERVER validates the
answer, splices it into the HEAD text and derives the unified diff with git, so the model never writes
a hunk header. Everything after that (`checkDiffPaths`, the hard-rule and byte-budget gates, the shrink
floor, the draft PR) is unchanged.

**The quorum is checked first.** Before the target file is read and before phase 2 is called, the server
counts the cluster's DISTINCT source learnings that are keys of the collected corpus (duplicates and paths
the model invented do not count). Fewer than `PROMOTION_QUORUM` (5) and the cluster is refused
`quorum-not-met`: the target file is not read, the model is not called, no draft PR opens. Two things the
gate does not claim: it counts corpus paths, not relatedness (`Threshold-Hit: 5/5` is a floor, and the
human review of each draft PR is unchanged), and a refused cluster still occupies one of the week's
proposal slots. The rationale and the other consequences live in the ADR-092 Amendment of 2026-10-20.

Before this change three consecutive weekly runs each failed `git apply` in a different way and no PR
was ever opened; the refusal enum is in `betterstack-log-query.md` (seven `edit-*` reasons).

What a streak means when you read the weekly marker:

- **`edit-anchor-not-found` / `edit-anchor-ambiguous` / `edit-invalid`** every week: the model is not
  copying an anchor verbatim or is producing unusable lines. Model-side, not a server fault; the probe
  keeps the tracker open. Read the Sentry `cause` tag (op `draft-edit-refused`) before touching the prompt.
- **`quorum-not-met`** every week: the model keeps proposing clusters with fewer than 5 usable source
  learnings. Model-side, not a server fault (probe class N: never PASS, never FAIL). Read the Sentry event
  (op `draft-edit-refused`, tags `reason=quorum-not-met`, `cause=below-quorum`): `extra.source_count` is the
  distinct corpus-resolved count and `extra.proposed_count` is the model's raw list length, so
  `proposed_count` well above `source_count` means unknown or duplicate paths (a prompt or corpus-key
  problem), and both low means the model really proposed a thin cluster. The same two integers are on the
  mirrored error row in Better Stack (`scripts/betterstack-query.sh --grep draft-edit-refused` matches it
  and the `hash`-keyed warn line; only the error row, key `cluster_hash`, carries the counts; see
  `betterstack-log-query.md`). A recurring `cluster_hash` with `source_count` 0 is the hash of an EMPTY
  list (a constant), not one cluster recurring.
- **A red `lint-rule-ids` on an `AGENTS.rules.md` draft is expected, not a defect.** The cron edits one
  file; the corpus lint requires an `AGENTS.md` pointer line for every rule body. The draft PR body names
  the exact `- [id: <slug>]` line for the reviewer to add. Neither the follow-through probe nor the census
  counts this red check as a failure.
- **`edit-target-too-large`**: the target exceeds 120,000 bytes. It clears as the largest skills are
  shortened (#10551).
- **`skill-conflict-guard`** every week: any open PR that mentions `plugins/soleur/skills` blocks a
  skill-targeting cluster, and the guard posts the proposed diff as a comment on that PR. `AGENTS.rules.md`
  clusters are unaffected. This guard had never run in production before this change.
- **`edit-derive-failed` or `diff-underivable-apply`**: a SERVER defect (a derived diff is additive by
  construction). Both go to Sentry; the follow-through probe exits 1.

## The `input` option and the patterns-path marker fields (ADR-297)

Recorded 2026-10-24. The manual-trigger event accepts an optional `data.input`:

- **`corpus`** (default, and the only behaviour of the scheduled cron): the learnings-directory
  path described above. The scheduled run ignores `data.input` entirely.
- **`patterns`**: the proposer reads the open pages under `knowledge-base/project/patterns/`
  (index plus the first 10 lines of each page's evidence learnings) instead of the whole
  learnings directory, and runs the PR-state ledger reader before the model call.
- Any other value on a **manual** trigger ends the run `status=error` with an `invalid-run-option`
  `error_class`, before any Anthropic call (a typo is never silently treated as `corpus`). A
  Sentry message with op `invalid-run-option` accompanies it; the raw value is not logged.

```bash
# Patterns-path manual run (read the INTERIM OPERATING RULE below first):
curl -s -X POST https://soleur.ai/api/inngest \
  -H "content-type: application/json" \
  -d '{"name":"cron/compound-promote.manual-trigger","data":{"input":"patterns"}}'
```

Prefer `soleur:trigger-cron` (reads the secret read-only from Doppler, supports a dry run of the
request) over a hand-built request.

### INTERIM OPERATING RULE

`dry_run` is deferred, so a real `input:"patterns"` run opens real draft PRs from an unproven
seed and consumes the week's `week-cap` slots. Until the flip tracker ships a dry run:

1. **Do not trigger a manual `input:"patterns"` run before the 2026-10-25 scheduled run's marker is
   recorded.** That run is the clean baseline; the first post-fix run that can reach the gates.
2. **Do not trigger one while any `self-healing/auto` PR is open** (it would stack drafts on the
   week-cap and on an unreviewed proposal).

### Marker fields (patterns path only)

Present on the `SOLEUR_COMPOUND_PROMOTE_OUTCOME` row only when `input_source` is `patterns`; the
scheduled row's field set is byte-identical to before. All are numbers or closed enums. Query
recipe and the full field list: `betterstack-log-query.md`.

| Field | Meaning | How to read it |
|---|---|---|
| `input_source` | `corpus` or `patterns` | Confirms which arm ran. A manual run you meant as `patterns` that reads `corpus` means the option did not reach the handler |
| `patterns_open` | open pattern pages loaded (after the runtime PII, path and schema drops) | `0` ends the run `empty-corpus` (no fallback to the corpus, Sentry op `patterns-empty`): the seed is broken or every page is closed. Compare with the page count in the repo: fewer than expected means pages were dropped (Sentry op `pattern-page-dropped`, tag `cause`) |
| `ledger_read` | `ok` or `failed` | `failed` is a loud `status=error`, no Anthropic call. Read the Sentry message `ledger-read-failed` and its `cause` tag (`http-5xx`, `rate-limit`, `page-cap`, `incomplete`, `unparseable`, `drift`). `drift` means bot PRs were found but none matched the expected title or author: the title format or bot login changed, so fix the contract, do not retry blindly |
| `ledger_suppressed` | clusters dropped because the same recomputed hash is already proposed (open, merged, or closed unmerged within 60 days) | Each also appears as `ledger-suppressed` in `refusals[]` and `refusal_detail[]` (`{cluster_hash, reason}`). `status=no-qualifying-clusters` with `ledger_suppressed > 0` means every cluster was suppressed. `clusters_proposed` stays pre-suppression |
| `ledger_prs_scanned` | raw GitHub search hit count for `self-healing/auto-` PRs | A count near the 1,000-result search ceiling fails the read (`page-cap` / `incomplete`); plan state-split queries before then |
| `ledger_title_skipped` | bot-authored search items skipped because the title did not match the anchored promote-cluster title regex | Warn-level, never fails the read. A human-retitled bot PR stops suppressing its cluster, so a non-zero value explains a re-proposal. Restore the title (`self-healing(auto): promote cluster <64-hex> <YYYY-MM-DD>`) to restore suppression |

### Escape hatch: a permanently-suppressed merged cluster

A **merged** proposal suppresses its exact cluster hash permanently. On the patterns path a
page's evidence set is fixed, so a reverted merged edit does not re-cluster to a new hash and
stays suppressed. To let such a cluster be proposed again, a human either **changes the page's
evidence** (a different evidence set is a different hash) or **closes the page and reopens it
under a new slug**. An **open** proposal suppresses for as long as it is open (merge or close it);
a **closed unmerged** one stops suppressing at 60 days from `closed_at` (at exactly 60 days it
lapses).

## Sharp edges

- **`.claude/.rule-incidents.jsonl` is gitignored.** The cron CANNOT read it.
  Clustering input is always the committed `knowledge-base/project/learnings/`
  corpus. Local hook telemetry stays local until rolled up by the weekly
  aggregator into `knowledge-base/project/rule-metrics.json`.
- **`self-healing/auto` label is created idempotently.** First workflow run
  creates it; subsequent runs no-op. Manual creation is not required.
- **Plugin-scope edits are deferred to v2.** v1 only proposes changes to
  files inside this repo. Cross-repo plugin-scope promotion (`--scope=plugin`)
  is blocked on CLO sign-off + ToS/Privacy-Policy disclosure update.
- **Synthetic checks are posted by the workflow.** Operator-mark-ready
  satisfies the CI Required + CLA Required rulesets without waiting for real
  CI on bot-authored content.
- **GDPR shell pre-pass is heuristic.** The canonical regex covers email,
  IPv4, and IBAN. Novel PII patterns (phone numbers, employee IDs in unusual
  formats) may slip through. Use the LLM-driven `/soleur:gdpr-gate` for
  narrower targeted scans when needed; the human reviewer at PR time is the
  second line of defense.
- **Always-loaded payload is already tight.** Do not trust a figure quoted
  here — run `python3 scripts/lint-agents-rule-budget.py AGENTS.md
  AGENTS.rules.md 2>&1` for the current number
  and tier. Do not quote a figure here — run the command. The previously-frozen number in this
  spot (`B_ALWAYS=22900`, WARN tier, "expect essentially every agents-core proposal to be
  refused") went stale at ADR-151 and inverted the operating conclusion: the corpus
  collapse re-scoped `B_ALWAYS` to what every session actually loads and re-baselined the
  thresholds, so the tree now sits in the `[OK]` tier with kilobytes of headroom and
  in-budget proposals should be ACCEPTED, not refused. That is exactly the failure this
  runbook warns about two paragraphs above.

## Related artifacts

- Driver: `scripts/compound-promote.sh`
- Tests: `scripts/compound-promote.test.sh`
- Handler: `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` (the former
  `scheduled-compound-promote.yml` workflow no longer exists; the Inngest function replaced it)
- Pattern wiki and ledger decision: `knowledge-base/engineering/architecture/decisions/ADR-297-pattern-wiki-and-pr-state-proposal-ledger.md`
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-021-stateless-self-modifying-cron.md`
- Audit log: `knowledge-base/project/learnings/promotion-log.md`
- Plan: `knowledge-base/project/plans/2026-05-11-feat-compound-promotion-loop-plan.md`
