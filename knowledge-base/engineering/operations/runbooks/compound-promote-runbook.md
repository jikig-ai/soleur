---
title: "Compound Promotion Loop — operator runbook"
type: runbook
issue: "#2720"
last_updated: 2026-05-26
---

# Compound Promotion Loop — operator runbook

## What it does

The Compound Promotion Loop is Layer 2 of the self-healing-workflow design.
A weekly Inngest cron function (Sunday 00:00 UTC) at
`apps/web-platform/server/inngest/functions/cron-compound-promote.ts`
reads `knowledge-base/project/learnings/`, runs a deterministic GDPR +
retired-rule pre-pass over the corpus, then calls the Anthropic API to cluster
learnings by problem/root-cause. When a cluster reaches >=5 source learnings
the loop opens up to **2 draft PRs per week**, each proposing a skill-instruction
edit or an `AGENTS.core.md` rule addition. The loop **never auto-merges** —
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
   diff edits `AGENTS.core.md` AND the new rule is genuinely cross-cutting
   (silent failure or blast radius, no single-file trigger). Reject anything
   that should be hook-enforced or scanner-enforced — those don't belong in
   the registry per `cq-agents-md-tier-gate`.
3. **Byte budget.** For `agents-core` PRs, verify the post-merge always-loaded
   payload stays under the thresholds defined in
   `scripts/lint-agents-rule-budget.py` (the authority: warn at
   `B_ALWAYS >= 20000`, reject above `23000`), which
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
(`knowledge-base/project/learnings/promotion-log.md`) preserves the proposal
record; the close acts as the rejection signal — the loop's per-week cap
counts open PRs only, so a closed proposal won't block next week's run.

## Reverting a promoted rule

If a merged promotion turns out to be a false positive, demote it via the
standard rule-retirement path: append the rule's ID to
`scripts/retired-rule-ids.txt` with format `<id> | <YYYY-MM-DD> | <PR> | <breadcrumb>`.
The next `rule-prune` cron tick removes the rule from `AGENTS.core.md` and
the linter rejects any future reintroduction of the retired ID.

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
  AGENTS.core.md AGENTS.docs.md AGENTS.rest.md 2>&1` for the current number
  and tier. As of 2026-07-20 it reports `B_ALWAYS=22900` in the WARN tier,
  roughly two dozen bytes of raw headroom below the reject ceiling. Expect essentially
  every `agents-core` proposal to be refused until a trim lands — that is the
  budget genuinely being exhausted, not a stale constant. Retire stale rules
  first to create headroom.
- **DPIA candidate.** Art. 35 DPIA assessment is deferred until 4 weeks of
  operation generate empirical data. Tracked in `compliance-posture.md`.

## Related artifacts

- Driver: `scripts/compound-promote.sh`
- Tests: `scripts/compound-promote.test.sh`
- Workflow: `.github/workflows/scheduled-compound-promote.yml`
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-021-stateless-self-modifying-cron.md`
- Audit log: `knowledge-base/project/learnings/promotion-log.md`
- Plan: `knowledge-base/project/plans/2026-05-11-feat-compound-promotion-loop-plan.md`
