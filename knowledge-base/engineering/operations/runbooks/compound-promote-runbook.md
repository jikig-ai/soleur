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

# 3. Confirm the next scheduled run will fire (Sunday 00:00 UTC) or trigger now
#    (soleur:trigger-cron; drop --dry-run to fire):
"${CLAUDE_PLUGIN_ROOT}/skills/trigger-cron/scripts/trigger.sh" \
  --event cron/compound-promote.manual-trigger --dry-run
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
(`knowledge-base/project/learnings/promotion-log.md`) rows ride the proposal's own
commit, so a `pending` row reaches main only when its proposal PR merges; the close acts as the rejection signal, and rejection state is read
from GitHub PR state through Octokit (ADR-299), not from the log. The loop's
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
  clusters are unaffected. This guard had never run in production before this change. The comment lands
  on an unrelated open PR and no PR is opened, so the ledger never sees the cluster and the same cluster
  can re-comment weekly while that PR stays open.
- **`edit-derive-failed` or `diff-underivable-apply`**: a SERVER defect (a derived diff is additive by
  construction). Both go to Sentry; the follow-through probe exits 1.

## The `input` option and the patterns-path marker fields (ADR-299)

Recorded 2026-10-24. The manual-trigger event accepts an optional `data.input`:

- **`corpus`** (default, and the only behaviour of the scheduled cron): the learnings-directory
  path described above. The scheduled run ignores `data.input` entirely.
- **`patterns`**: the proposer reads the open pages under `knowledge-base/project/patterns/`
  (index plus the first 10 lines of each page's evidence learnings) instead of the whole
  learnings directory, and runs the PR-state ledger reader before the model call.
- Any other value on a **manual** trigger ends the run `status=error` before any Anthropic call (a
  typo is never silently treated as `corpus`). The Sentry op and tag is `invalid-run-option` and the
  `error_message` carries that prefix; the marker `error_class` is `InvalidRunOptionError`, and the
  error row carries no patterns fields. The raw value is not logged. A typo also posts a failed
  check-in to the weekly Sentry monitor (pre-existing behaviour for any manual error).

```bash
# Patterns-path manual run (read the INTERIM OPERATING RULE below first).
# soleur:trigger-cron reads the secret read-only from Doppler. Drop --dry-run to fire.
"${CLAUDE_PLUGIN_ROOT}/skills/trigger-cron/scripts/trigger.sh" \
  --event cron/compound-promote.manual-trigger --data '{"input":"patterns"}' --dry-run
```

The Inngest dashboard run-now and the in-product agent tool pass no data, so they always run the
`corpus` arm.

### INTERIM OPERATING RULE

`dry_run` is deferred, so a real `input:"patterns"` run opens real draft PRs from an unproven
seed and consumes the week's `week-cap` slots. Until the flip tracker ships a dry run:

1. **As of 2026-10-25: do not trigger a manual `input:"patterns"` run until the 2026-10-25 scheduled
   run's marker is recorded.** That run is the clean baseline; the first post-fix run that can reach
   the gates. The rule lifts once that marker is recorded.
2. **Do not trigger one while any `self-healing/auto` PR is open** (it would stack drafts on the
   week-cap and on an unreviewed proposal).

### Marker fields (patterns path only)

Present on the `SOLEUR_COMPOUND_PROMOTE_OUTCOME` row only when `input_source` is `patterns`; the
scheduled row's field set is byte-identical to before. All are numbers or closed enums. Query
recipe and the full field list: `betterstack-log-query.md`. The early terminal rows `disabled`,
`deduped` and `week-cap-reached` on a manual patterns run carry ONLY `input_source:"patterns"` (none of
the other fields below).

| Field | Meaning | How to read it |
|---|---|---|
| `input_source` | `patterns` (never emitted on the corpus arm) | On a manual patterns trigger, a row WITHOUT `input_source` means the option did not reach the handler. A row with only `input_source` and status `disabled`, `deduped` or `week-cap-reached` means the request did nothing: the capability is off, an open "[Scheduled] Compound Promotion" issue was created in the last 6 days (dedup), or open `self-healing/auto` PRs hold the week cap |
| `patterns_open` | open pattern pages loaded (after the runtime PII, path and schema drops) | `0` ends the run `empty-corpus` (no fallback to the corpus). Sentry op `patterns-empty`, emitted once per run, tag `cause`: `no-open-patterns` (pages exist but none is open) or `dir-unreadable` (the patterns directory is absent or unreadable). Compare with the page count in the repo: fewer than expected means pages were dropped (Sentry op `pattern-page-dropped`, tag `cause` = `schema`, `pii` or `evidence`). Individual evidence files dropped inside a surviving page are Sentry-only (op `pattern-evidence-dropped`, tag `cause` = `archived`, `retired`, `pii` or `unreadable`, `extra.count`); the marker has no per-key drops. A page left under 5 surviving evidence entries is dropped |
| `ledger_read` | `ok` or `failed` | `failed` is a loud `status=error`, no Anthropic call. Read the Sentry message `ledger-read-failed` and its `cause` tag, one of seven: `http-5xx`, `rate-limit`, `page-cap`, `incomplete`, `unparseable`, `drift`, `transport`. The marker has no cause field: after Inngest retries (function `retries:1`, so deterministic causes are retried once and report twice) Better Stack shows `status=error`, `ledger_read=failed`, `error_class=LedgerReadError` and a static `error_message`. `drift` fires only when a bot-authored (`soleur-ai[bot]`) hit exists and NO bot hit parses as a promote title (every bot PR was retitled): fix the title contract, do not retry blindly. Foreign-only hits (a fork or human PR on a `self-healing/auto-*` branch) read as an empty ledger and never fail. A zero-hit read is accepted as an empty ledger (the first patterns run is expected to read 0) |
| `ledger_suppressed` | clusters dropped because the same recomputed hash is already proposed (open, merged, or closed unmerged within 60 days) | Each also appears as `ledger-suppressed` in `refusals[]` and `refusal_detail[]` (`{cluster_hash, reason}`). `status=no-qualifying-clusters` with `ledger_suppressed > 0` means every cluster was suppressed. `clusters_proposed` stays pre-suppression. Slot starvation (accepted): the patterns arm slices the model's clusters to the week-cap `remaining` (at most 2) BEFORE suppression and does not tell the model which hashes are suppressed, so a repeatedly proposed rejected or merged cluster can occupy the slots and end a week `no-qualifying-clusters` with `ledger_suppressed >= 1`. A second cluster with the same source set in one run is refused `cluster-duplicate` |
| `ledger_prs_scanned` | raw GitHub search hit count for `self-healing/auto-` PRs | The read takes up to 10 search pages of 100 and throws if the last page is full, so the usable ceiling is 999 hits. Past it every patterns run fails `page-cap`; plan state-split queries before then |
| `ledger_title_skipped` | bot-authored search items skipped because the title did not match the anchored promote-cluster title regex | Warn-level; does not fail by itself (if every bot PR was retitled, the read fails `drift`). A human-retitled bot PR stops suppressing its cluster, so a non-zero value explains a re-proposal. Restore the title (`self-healing(auto): promote cluster <64-hex> <YYYY-MM-DD>`) to restore suppression |

### Escape hatch: a permanently-suppressed merged cluster

A **merged** proposal suppresses its exact cluster hash permanently. The hash is sha256 over the
SORTED evidence paths the model cited; the slug is not part of it. So closing a page and reopening
it under a new slug does NOT lift a suppression. Only a different cited evidence set does: a human
adds or removes evidence on the page so the model's cluster differs. The model may cite any subset
of at least 5 from the open pages' union, so which hash comes back is not deterministic and
exact-hash suppression can be evaded by citing a different subset (accepted, tracked in #10977). An **open** proposal suppresses for as long as it is open (merge or close it);
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
- Pattern wiki and ledger decision: `knowledge-base/engineering/architecture/decisions/ADR-299-pattern-wiki-and-pr-state-proposal-ledger.md`
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-021-stateless-self-modifying-cron.md`
- Audit log: `knowledge-base/project/learnings/promotion-log.md`
- Plan: `knowledge-base/project/plans/2026-05-11-feat-compound-promotion-loop-plan.md`
