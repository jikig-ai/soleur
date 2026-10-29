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
from GitHub PR state through Octokit (ADR-300), not from the log. The loop's
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
- **`skill-conflict-guard`**: an open PR changes the SAME target file as the skill-targeting cluster
  (matched exactly against the PR's changed `filename` or `previous_filename`; a PR that merely mentions
  `plugins/soleur/skills` in its title or body no longer matches, and Dependabot PRs are skipped to save requests: an accepted exclusion, since the path match never
  runs for a skipped PR and Dependabot edits manifests, not SKILL.md). No
  comment is posted anywhere. The conflicting PR number appears in the Better Stack warn line
  `skill-conflict-guard-refused` (fields `fn`, `hash`, `pr`, `target`) and in the run's stored step output (a public PR number):
  `scripts/betterstack-query.sh --grep skill-conflict-guard-refused`. `AGENTS.rules.md` clusters are
  unaffected. The App's own earlier open draft promote PR on the same SKILL.md also triggers it, by
  design (no two competing drafts on one file); the cluster re-proposes after that draft merges or
  closes. Both skill clusters in a run share one snapshot of the open PRs, so a PR opened after the scan
  and before the commit is not seen; the consequence is a merge conflict a reviewer resolves on the
  human-gated draft PR.
- **`skill-conflict-guard-unverifiable`**: the guard could not complete its check (a scan bound was hit with no match, or the scan was not asked about the target), so it refuses
  rather than report "no conflict". The bounds: 300 or more open PRs (`bound=prs`), a PR with
  1000 or more changed files (`bound=files`), or more than 150 file-list requests in one run
  (`bound=requests`; with more than about 150 open non-Dependabot PRs this one trips first, because
  each costs a request), or a scan that runs past its 120-second total deadline (`bound=time`, a slow
  GitHub; each request also has its own 20-second timeout). A scan asked about a target it did not cover reports `bound=targets` (an internal fault: report it). While such a PR or PR count exists, every skill cluster is unverifiable until it
  closes (fail closed by design; any contributor, including a fork, can cause it). `AGENTS.rules.md`
  clusters are unaffected. Signals: the warn line `skill-conflict-guard-unverifiable` (fields `fn`,
  `hash`, `bound`) in Better Stack, and a Sentry event (op `skill-conflict-guard-unverifiable`, tag
  `bound`). A failed GitHub request is different: it fails the scan step, Inngest retries, and no skill
  PR opens (the run errors; a PR already opened earlier in the same run stays, and clusters after the
  skill cluster are abandoned).
- **`edit-invalid` with Sentry `cause=too-long`**: a model-written line exceeded the per-line cap. The cap
  is 600 characters for `AGENTS.rules.md` (pinned by a test to `PER_RULE_CAP` in
  `scripts/lint-agents-rule-budget.py`, so the validator refuses exactly what the corpus lint would) and
  1000 for `SKILL.md` (no lint governs skill lines; revisit only if refusal rows show 1000 being hit;
  the whole diff is still bounded at 16,384 characters, so at most 16 full lines is the reachable maximum and
  more is refused `diff-size-exceeded`).
  The prompt states a soft target of 500 characters and the hard cap. There is no retry: a too-long line
  refuses the whole cluster.
- **`edit-derive-failed` or `diff-underivable-apply`**: a SERVER defect (a derived diff is additive by
  construction). Both go to Sentry; the follow-through probe exits 1.

## The `input` option and the patterns-path marker fields (ADR-300)

Recorded 2026-10-24. The manual-trigger event accepts an optional `data.input`:

- **`corpus`** (default, and the only behaviour of the scheduled cron): the learnings-directory
  path described above. The scheduled run ignores `data.input` entirely.
- **`patterns`**: the proposer reads the open pages under `knowledge-base/project/patterns/`
  (index plus the first 10 lines of each page's evidence learnings) instead of the whole
  learnings directory, and runs the PR-state ledger reader before the model call.
- Any other value on a **manual** trigger ends the run `status=error` before any Anthropic call (a
  typo is never silently treated as `corpus`). The Sentry op and tag is `invalid-run-option` and the
  `error_message` carries that prefix; the error row carries no patterns fields (key on the `invalid-run-option:` prefix of `error_message`; `error_class` is `InvalidRunOptionError` in source, but a minified server bundle does not guarantee class names). The handler writes the raw value to no sink (no Sentry, pino or Better Stack field, no marker, no `error_message`); the manual-trigger event that carried it persists in the Inngest event store under the retention recorded at PA-31 (f). A typo also posts a failed
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
2. **A `patterns` run without `allow_create` must not be triggered while any `self-healing/auto` PR is
   open** (it would stack drafts on the week-cap and on an unreviewed proposal). **A `patterns` run with
   `allow_create:true` may have at most ONE `self-healing/auto` PR open:** with one open the edit loop is
   skipped and only the create arm runs (if that one open PR is itself an unreviewed create draft, the arm refuses
   `create-open` and the run does nothing); with two open the run ends `week-cap-reached` before the arm.

### Marker fields (patterns path only)

Present on the `SOLEUR_COMPOUND_PROMOTE_OUTCOME` row only when `input_source` is `patterns`; the
scheduled row's field set is byte-identical to before. All are numbers or closed enums. Query
recipe and the full field list: `betterstack-log-query.md`. The early terminal rows `disabled`,
`deduped` and `week-cap-reached` on a manual patterns run carry ONLY `input_source:"patterns"` and
`create_requested` (none of the other fields below).

| Field | Meaning | How to read it |
|---|---|---|
| `input_source` | `patterns` (never emitted on the corpus arm) | On a manual patterns trigger, a row WITHOUT `input_source` means the option did not reach the handler (or the run was a deliberate manual corpus run, which the Inngest dashboard run-now sends). A row with only `input_source` and status `disabled`, `deduped` or `week-cap-reached` means the request did nothing: the capability is off, an open "[Scheduled] Compound Promotion" issue was created in the last 6 days (dedup), or open `self-healing/auto` PRs hold the week cap |
| `patterns_open` | open pattern pages loaded (after the runtime PII, path and schema drops) | `0` ends the run `empty-corpus` (no fallback to the corpus). Sentry op `patterns-empty`, emitted once per run, tag `cause`: `no-open-patterns` (pages exist but none is open) or `dir-unreadable` (the patterns directory is absent, unreadable or aliased: a symlink at or below the repository root on its path). Compare with the page count in the repo: fewer than expected means pages were dropped (Sentry op `pattern-page-dropped`, tag `cause` = `schema`, `size` (over 16 KiB), `pii` or `evidence`). Individual evidence files dropped inside a surviving page are reported to Sentry and the pino error mirror only (op `pattern-evidence-dropped`, tag `cause` = `archived`, `retired`, `pii` or `unreadable`, `extra.count`; `unreadable` also covers an aliased or missing learnings root and a first-10-lines excerpt over 16 KiB); the marker has no per-key drops. A page left under 5 surviving evidence entries is dropped |
| `ledger_read` | `ok` or `failed` | `failed` is a loud `status=error`, no Anthropic call. Read the Sentry message `ledger-read-failed` and its `cause` tag, one of seven: `http-5xx`, `rate-limit`, `page-cap`, `incomplete`, `unparseable`, `drift`, `transport`. The marker has no cause field: after Inngest retries (function `retries:1`, so deterministic causes are retried once and report twice) Better Stack shows `status=error`, `ledger_read=failed` and a static `error_message`. Key on `ledger_read=failed`: `error_class` is derived from `constructor.name`, which is `StepError` in the SDK's shape (an exhausted `step.run` reaches the handler as `StepError`, not `LedgerReadError`) but may be minified in a production bundle. `drift` fires only when a bot-authored (`soleur-ai[bot]`) hit exists and NO bot hit parses as a promote title (every bot PR was retitled): fix the title contract, do not retry blindly. Foreign-only hits (a fork or human PR on a `self-healing/auto-*` branch) read as an empty ledger and never fail; the `author:app/soleur-ai` qualifier keeps them out of the response today and the login check is the second layer. A `transport` failure can also be a 422: the query itself was rejected (for example the App slug changed). A zero-hit read is accepted as an empty ledger (the first patterns run is expected to read 0) |
| `ledger_suppressed` | clusters dropped because the same recomputed hash is already proposed (open, merged, or closed unmerged within 60 days); create-arm patterns removed before the model call are NOT counted (see Same-run collision) | Each also appears as `ledger-suppressed` in `refusals[]` and `refusal_detail[]` (`{cluster_hash, reason}`). `status=no-qualifying-clusters` with `ledger_suppressed > 0` means every cluster was suppressed. `clusters_proposed` stays pre-suppression. Slot starvation (accepted): the patterns arm slices the model's clusters to the week-cap `remaining` (at most 2; one less on an `allow_create` run, which holds a slot for the create arm) BEFORE suppression and does not tell the model which hashes are suppressed, so a repeatedly proposed rejected or merged cluster, or a same-evidence duplicate (`cluster-duplicate`), can occupy the slots and end a week `no-qualifying-clusters` with `ledger_suppressed >= 1`. A second cluster with the same source set in one run is refused `cluster-duplicate` |
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

## The gated new-skill create arm (`allow_create`, #10550)

Recorded 2026-10-26. **Status: dark-launched.** The arm is wired in `cron-compound-promote.ts` (control flow and
marker) and `compound-promote-create-arm.ts` (the two step bodies); no production create has been fired and none
is authorized by the PR that wired it. The authority is ADR-092's create-only amendment of 2026-10-26 (closed
six-path set, own verdict union) and the ADR-300 addendum of the same date.

- **Reachability.** The arm runs only on a manual trigger with `data.input:"patterns"` AND
  `data.allow_create:true`. `allow_create` is an EVENT field, not a runtime flag: absent, or anything but the boolean
  `true`, means off, and no flag exists to flip. The scheduled run, a manual `corpus` run and a non-boolean
  `allow_create` leave the arm absent and the run unchanged. The edit loop runs first; the arm then uses what is left
  of the week cap (it counts all open `self-healing/auto` PRs, not a calendar week). On an `allow_create` run the
  edit loop gets the free slots minus one, so one slot is held for the arm. With one free slot the edit loop is
  skipped and the run ends `no-qualifying-clusters` with the create fields.
- **Output.** At most ONE create per run: a DRAFT PR adding a markdown-only skill (`SKILL.md`, `PURPOSE.md`,
  Cursor stub) plus two README counts and one ledger row, body line `CREATE (new skill)`. Never auto-merged.
- **Preconditions for the first live fire (an operator-authorized production act, NOT performed by #10550):**
  at most one open `self-healing/auto` PR (none preferred, so the create draft is reviewed alone; with two open,
  every manual fire ends `week-cap-reached` before the arm); a runtime flag created through `soleur:flag-create` if the trigger-secret holder check in
  `phase0-measurements.md` ever finds a non-operator holder; the deploy verified (`deploy-arm.sh find --wait`
  and the served build sha equal to the merge sha); the compliance-posture dated note read.
- **Reading a refusal.** One refusal reason, `create-refused`, with a closed `class`; Sentry mirror op
  `create-refused` with a `class` tag. A refused create writes NO ledger row, so a pattern refused for budget or
  scan is retried once headroom frees.

| `class` | Meaning | How to read it |
|---|---|---|
| `week-cap` | No week-cap slot was left for the arm although the run started with at least one free slot | Not expected since the slot reservation: treat it as a defect (unless the run straddled the deploy of the reservation, or another `self-healing/auto` PR was opened after the run read the cap) and read `clusters_opened` and the open `self-healing/auto` PR count. Before that fix, the edit loop ran first and could take both slots, which refused the arm on a clean state (run `01M5YB28JD20JKKH4HG04CX2Z4`, 2026-10-27). A run that starts with two open `self-healing/auto` PRs never reaches the arm and ends `week-cap-reached` |
| `create-open` | another open PR already carries the `CREATE (new skill)` line, or the open-PR list could not be read | one open create at a time; a list failure refuses rather than guesses |
| `index-empty` | no open pattern page to read | defence in depth: the handler exits `empty-corpus` first, so this refusal is not expected in production; if it appears, check `patterns_open` |
| `input-size` | pattern index plus skill list exceeds the input ceiling | refused, never truncated; trim the index or raise the ceiling by amending the ADR |
| `model-invalid` | the model answer did not parse into the closed schema | one call, no retry; read the Sentry event |
| `shape` | a model string or a rendered file failed the shape allowlist, claim-word, PII or credential screen | the marker carries the field name, never the text |
| `slug` | slug collides with a skill dir, agent name or an open PR path | choose another pattern or wait for the open PR |
| `prefer-patch` | the nearest skill ranks in the top three by overlap and overlap is over the threshold | the marker carries rank and top-1 score (numbers); patch that skill instead |
| `budget` | description words exceed `cap - total`, or the cap or a description could not be parsed | the marker carries `cap` and `total` (numbers); free words by trimming a description in a human PR |
| `scan` | the scanner did not return an explicit LOW-RISK first line with exit 0 on BOTH files (HIGH-RISK, REVIEW, empty, non-zero, timeout, missing tool) | `detail` says which. Marker numbers: `create_file_index` (0 SKILL.md, 1 PURPOSE.md), `create_exit` (the script's exit code), `create_missing_tools` (how many). Sentry `extra`: `signal` (a `SIG*` name) and `missing_tool_names` (always members of the closed tool list). A missing tool means the runner image lacks a dependency |
| `readme-sync` | the README sync changed anything beyond digits in the two README files, or nothing at all | a script defect or a scan-time write; the draft is not opened. Marker numbers: `create_changed_count` (`unexpected-change`: paths other than the READMEs that differ; `no-change`: how many of the two READMEs changed), `create_exit` |
| `stub-drift` | the rendered Cursor stub differs from the renderer's own expectation | this is RENDERER SELF-CONSISTENCY only. Parity of the pure renderer with the real generator is the CI `cursor-name-map --check` (`sync-cursor-name-map.ts --check`), not a run-time check. If this fires the renderer was edited without its expectation |
| `persist` | a precondition of the commit failed, or the commit helper did | The create arm commits from the cron worker (Inngest), NOT from a GitHub Actions workflow; there is no workflow-run log to read. Read the Sentry event: op `create-refused` (tag `class`, `extra.detail`, and for a git failure `extra.cause`, see "Git failures" below), and for `failed-<stage>` / `not-committed-<status>` the helper's own Sentry mirror for that stage |

`create_detail` values by class (closed tokens; a `<field>:<rule>` token names the model field and the shape rule, never its text):

| `class` | `create_detail` values |
|---|---|
| `week-cap` | `no-slot` (defensive backstop since the slot reservation: the arm found no slot; no number rides it) |
| `create-open` | `open-create-pr`, `list-failed`, `list-incomplete`, `paths-unverifiable`, `paths-incomplete` |
| `index-empty` | `no-open-patterns` |
| `input-size` | `over-ceiling` (marker numbers `create_tokens`, `create_max`, `create_bytes`; the bound is bytes / 4) |
| `model-invalid` | `no-api-key`, `transport` (Sentry `extra.cause`: `http-429`, `TimeoutError`, ...), `max-tokens`, `empty`, `not-json`, `schema`, `unknown-pattern`, `internal` |
| `shape` | `<field>:<rule>` from the shape allowlist (rules include `instruction-risk` -- the phrase denylist, so `<field>:instruction-risk` is a MODEL STRING that hit it -- `claim-word`, `ref-format`, `markup`, `url`, `backtick`), `<field>:pii`, `<field>:credential`, `rendered-<file>:<pii or credential>`, `instruction-risk:skill` and `instruction-risk:purpose` (a model-derived LINE of the rendered SKILL.md / PURPOSE.md hit the denylist; the fixed template text is exempt), `empty:<file>` (a rendered file was empty), `template-unreadable` (Sentry `extra.cause`), `render`, `grok-block`, `fence:skill`, `fence:purpose`, `size:skill`, `size:purpose`, `frontmatter` (the rendered SKILL.md frontmatter did not parse), `frontmatter-keys`, `frontmatter-values`, `purpose-link`, `slot-left:purpose` |
| `slug` | `format`, `yaml-word`, `reserved`, `skill-exists`, `agent-exists`, `cursor-name-exists`, `cursor-dir-exists`, `open-pr-slug`, `open-pr-agent`, `open-pr-command`, and the unmeasurable-population tokens `agents-dir-unreadable`, `agents-below-floor`, `cursor-dir-unreadable`, `cursor-below-floor` |
| `prefer-patch` | `nearest-missing`, `nearest-not-top3`, `overlap`, `open-pr-nearest` |
| `budget` | `skills-dir-unreadable`, `skill-unreadable`, `frontmatter-missing`, `frontmatter-unparseable`, `frontmatter-not-a-map`, `description-not-a-string`, `population-below-floor`, `cap-unreadable`, `unreadable`, `words-out-of-range`, `over-headroom` |
| `scan` | `high-risk`, `review`, `non-zero`, `empty-output`, `timeout`, `unrecognised`, `spawn-error` (the interpreter could not be started; also mirrored as op `create-gate-spawn`), `script-not-regular` (the scanner is missing, a symlink or not a regular file under the repo root), `output-overflow` (more than 1 MiB of stdout), `missing-tool`, `input-too-small`, `input-unreadable`, `meta-base-invalid`, `no-input` |
| `readme-sync` | `readme-unreadable`, `git-failed`, `timeout`, `script-not-regular`, `spawn-error` (the interpreter could not be started), `output-overflow` (more than 1 MiB of stdout), `script-failed` (the script ran and exited non-zero: `create_exit`), `unexpected-change`, `no-change`, `non-digit-change` |
| `stub-drift` | `stub-differs` |
| `persist` | `branch-shape`, `branch-taken` (an open PR on our branch is not a create PR), `clone-missing` (the clone directory is gone; either step), `clone-not-clean`, `origin-failed`, `fetch-failed`, `reset-failed`, `blob-read-failed`, `origin-strip-failed`, `recheck-mismatch`, `page-missing` (the verdict's pattern is not in the run's pattern list; mirrored), `log-unreadable`, `base-moved`, `slug-appeared`, `tree-read-failed`, `branch-exists`, `branch-probe-failed`, `bytes-differ`, `deadline`, `internal`, `path-missing`, `path-not-regular`, `path-empty`, `path-too-large`, `path-nul`, `path-not-utf8`, `git-failed`, `changed-set-mismatch`, `failed-<stage>` and `not-committed-<status>` (the commit helper's own exit) |
| `create-open` (extra) | the `list-failed` and `paths-unverifiable` refusals also carry `extra.cause` in Sentry, a closed token (`http-<status>`, an errno name, an error class name or `unknown`), never a message |
| `cause` (extra) | Sentry `extra.cause` is set at exactly these sites, always a closed token and never a message. `create-open`: `list-failed` and `paths-unverifiable`. `budget`: `cap-unreadable`. `model-invalid`: `transport`. `shape`: `template-unreadable`. `persist`: `log-unreadable`, `internal`, `origin-failed`, and every git refusal (`clone-not-clean`, `fetch-failed`, `reset-failed`, `blob-read-failed`, `origin-strip-failed`, `tree-read-failed`, `branch-probe-failed`). Vocabulary: `http-<status>`; an errno name (`ENOENT`, `EACCES`, ...); an error class name (`TimeoutError`, `HttpError`, ...); `unknown`; `non-array` (`create-open/list-failed`: the listing answered with something that is not a list); for `origin-failed` `symlink-refused` and `set-url-failed`; for a git call `timeout`, `exit<N>`, `signal`, `spawn` (git never ran) and `bad-output` (git exited 0 but its answer was not the expected list of object ids) |

- **Kill switch.** There is no runtime flag. `allow_create` is read from each event, so the kill switch is to STOP
  FIRING manual triggers that carry it; nothing needs deploying. The existing opt-out in this runbook (`enabled:
  false` in `promotion-config.yml`) also stops it, because the run ends `disabled` before the arm.
- **Known limit (R4): the edit loop's token handling is untouched.** The create arm takes the installation token
  OFF `.git/config` before any of its scripts run. The token is on disk only for the network calls: the refresh fetch
  (before any script), and after the scripts the second fetch, the remote-branch probe and the commit helper. The
  EDIT loop still clones with the token in `.git/config` and runs no repo script, as before. A change there is a
  separate piece of work. If the final strip of the token from `.git/config` fails twice, the arm mirrors Sentry op
  `create-origin-strip-failed` (the token stays on the ephemeral workspace's disk until it is torn down).
- **Clone loss and token expiry.** The memoized clone path lives on the worker. If the container restarted between
  the two steps, or before a replay, the directory is gone: `persist/clone-missing` (either step), nothing written. `create-persist` looks up its own open PR first (that needs no clone), so a replay of an attempt that already opened the draft still ends `opened`.
  The installation token is minted once per run and lasts about an hour: a replay of `create-persist` more than
  roughly an hour later hands it an EXPIRED token, and the first fetch fails as `persist/fetch-failed` (or
  `origin-failed`) with `extra.cause` like `exit128`. Neither case writes anything; a new manual run starts from a
  fresh clone and a fresh token.
- **An unreviewed create draft holds capacity.** The create PR is a draft nobody merges automatically. While it is
  open it (a) permanently blocks any further create (`create-open`: one open create at a time) and (b) holds one of
  the two shared `self-healing/auto` week-cap slots. NO alert fires for an ignored draft today. The operator closes
  it (rejects the skill) or merges it after review; until then the arm is parked and one slot is held: a patterns run
  without `allow_create` can still use the other slot, while an `allow_create` run does nothing (the edit loop is
  skipped with one free slot and the arm refuses `create-open`).

### Create-arm marker fields

Every field below is absent from a scheduled row and from a manual `corpus` row (the field set of those rows is
byte-identical to before the arm existed). `create_requested` is the only one present when the arm did not run.
All are booleans, closed enums or numbers, except `create_detail`, a closed token (a field label plus a rule id,
or a fixed phrase) that never carries model text. Query recipe: `betterstack-log-query.md`.

| Field | Meaning | How to read it |
|---|---|---|
| `create_requested` | a manual `patterns` row: whether the event carried `allow_create === true` | Present on every manual `patterns` row, including the early `disabled`, `deduped` and `week-cap-reached` rows. NOT present on a manual run without `input:"patterns"` (a manual corpus row stays byte-identical to before the arm), so an `allow_create` sent WITHOUT `input:"patterns"` leaves no trace at all. `false` means the arm was off (a non-boolean `allow_create` such as `"true"` or `1` is ignored, never coerced). `true` with no `create_arm` means the run ended before the arm: read `status`. `week-cap-reached`, `empty-corpus`, `deduped` and `disabled` are early exits; `anthropic-truncated` means the edit clustering answer was truncated and the arm is skipped on that path (it never spends the call). The scope: a manual `patterns` row gains EXACTLY this one key when the arm did not run |
| `create_arm` | `ran`, emitted ONLY when the arm ran | Absent means off. With it, `kind` is `create` |
| `kind` | `create` | Emitted only together with `create_arm` |
| `create_outcome` | `no_action`, `refused` or `opened` | `no_action` = the model declined (`create_no_action_reason`) or no pattern was offerable (all owned: `all-owned` / `other`), or the model named an already-proposed pattern anyway (`ledger-suppressed` in `refusals[]`, `ledger_suppressed` counted, for a ledger hash only; whether that backstop fired is not readable from these fields alone, see "Reading a live-fire row"). `opened` = a draft PR exists (`create_pr`). `refused` = one `create-refused` entry in `refusals[]` plus `create_refusal_class` and `create_detail` |
| `create_no_action_reason` | `no-pattern-qualifies`, `all-owned` or `other` | `all-owned` also marks an offer the ledger emptied before the call (the model may also answer `all-owned` itself, so the field alone does not show whether a call was spent, but `create_offered` does: `create_offered > 0` on a `no_action` row means a model call was spent, `0` means the offer was emptied before the call; the create call's `output_tokens` on the `SOLEUR_CLAUDE_COST` row for this run then separates an instant decline (tens of tokens) from a deliberated answer; the cost row carries the same source and run id as the edit-loop calls and no create-specific token, so every `patterns` run has several rows under one run id (the clustering call, then any edit-loop calls, then the create call) and the create call is the LAST of them); `other` also marks a same-run-emptied offer (clusters the edit loop dropped as `ledger-suppressed` count as same-run, so they classify as `other`) and a suppressed (already proposed) pattern the model named anyway |
| `create_offered` | an integer count of candidate patterns (never text) | The patterns left after the same-run and ledger filters, i.e. the candidates the arm would send. Whenever a model call was made (a model `no_action`, a `suppressed` backstop hit, a post-call refusal, a `create`) it is the number the model was offered; for `model-invalid/transport` the call was attempted but may not have reached the model, so check the cost row. On a pre-call refusal (`create-open`, `input-size`, `no-api-key`, `persist/clone-missing` raised by the propose step, and the `budget` and `slug` refusals raised by the clone measurement) it is the candidate count and NO call was spent. `budget` and `slug` refusals also come from the post-call content gates, and `persist/clone-missing` is also returned by the persist step after a spent call, so for `budget` and `slug` read `create_detail`, and for `persist/clone-missing` only the cost row tells the two sides apart, rather than inferring from this field. On a pre-call `no_action` (`all-owned`, `other`) it is `0`. Absent on a `week-cap` or `index-empty` refusal, on `model-invalid/internal` (a step defect, mirrored to Sentry op `create-propose-internal`, where a call may already have been spent), and on a row whose memoized step output predates the field. Compare it with `patterns_open` to see how many patterns the filters held back. It says how many were offered, not why the model declined them |
| `create_refusal_class`, `create_detail` | the `class` table above and its closed token | The same pair is mirrored to Sentry (op `create-refused`, tag `class`, `extra.detail`) |
| `create_words`, `create_cap`, `create_total` | description words requested, the budget cap and the current model-visible total | Budget refusals only; `cap - total` is the headroom the description must fit |
| `create_top1`, `create_nearest_rank` | the best overlap score with an existing skill and the rank of the model's nearest skill | `prefer-patch` refusals only; compare with `OVERLAP_REFUSE_THRESHOLD` (Sentry `extra.threshold` on the same event) |
| `create_tokens`, `create_max`, `create_bytes` | the input-size bound (bytes / 4), its ceiling and the input bytes | `input-size` refusals only |
| `create_path_index` | index into the six-path set (0 SKILL.md, 1 PURPOSE.md, 2 Cursor stub, 3 README.md, 4 plugins/soleur/README.md, 5 promotion log) | `persist` collector refusals (`path-*`) and `persist/bytes-differ` |
| `create_file_index`, `create_exit`, `create_missing_tools`, `create_changed_count` | scan: refused file (0 or 1), the script's exit code, how many tools were missing; readme-sync: changed counts; `persist/base-moved`: how many base blobs moved; `create_exit` also: the exit status of a failed git call (`fetch-failed` and the other git failures) | `scan`, `readme-sync`, `base-moved` and git-failure refusals. The signal NAME, the missing tool NAMES and cause tokens are Sentry-only (`extra`). `min_words`, `max_words`, `headroom`, `threshold` and `pr` are Sentry-only numbers too |
| `create_pr` | the draft PR number | `opened` only |

Where the create outcome sits: the arm runs AFTER the edit loop, so `status` is the edit loop's status
(`completed`, or `no-qualifying-clusters` when the edit arm had nothing to open) and `clusters_opened` counts edit
PRs only. A create PR is never counted there. Since the slot reservation the edit loop cannot take the arm's slot,
so `create_refusal_class: "week-cap"` is a defect signal; a run that finds the cap saturated before the loop (two
open `self-healing/auto` PRs) ends `week-cap-reached` and never reaches the arm.

- **Where the cause is readable without SSH.** Better Stack: the marker row (recipe in `betterstack-log-query.md`).
  Sentry: one MESSAGE event per refusal, feature `cron-compound-promote`, op `create-refused`, tag `class`, with
  `extra.detail` and the same numbers. Infrastructure faults have their own ops: `create-gate-spawn` and
  `create-gate-git` (a gate script or git could not run), `create-propose-internal` and `create-persist-internal` (a
  defect inside a step, converted to a returned refusal), `create-own-pr-lookup-failed` (the replay lookup; the step
  continues), `create-clone-restore-failed` (the clone could not be returned to a clean main) and
  `create-origin-strip-failed` (the token could not be removed from `.git/config` after two tries).
- **A refused create writes no ledger row.** The promotion-log row exists only inside a committed PR, so a pattern
  refused for budget, scan or sync is retried on the next manual fire once the cause is gone.
- **Replay.** Step `create-propose` is memoized and never throws; step `create-persist` looks up its own open PR by
  the deterministic head branch (`self-healing/auto-<cluster hash>-<run date>`) and counts a hit as success ONLY when
  the PR body carries the `CREATE (new skill)` line, so a replay cannot open a second PR. A hit without the line is an
  EDIT PR (both arms use the same branch shape): `persist/branch-taken`.
- **Same-run collision.** The create arm does not offer the model a pattern whose cluster hash the edit loop recorded
  in the same run (opened or attempted), nor (since 2026-10-28) one the ledger already owns (an open or merged PR, or
  a closed one inside the 60-day window): no model call is spent on it. When every pattern is owned by the edit loop
  the arm ends `no_action` (`create_no_action_reason: other`); when the ledger empties the offer it ends `no_action`
  (`create_no_action_reason: all-owned`). Either way there is no call (`create_offered: 0`) and no `ledger_suppressed` increment.
  A model that names an unoffered owned pattern anyway is the backstop: a same-run hash is still `no_action` / `other`
  and is NOT recorded a second time (one `refusal_detail` entry per hash, the edit loop's own; no extra `ledger_suppressed`); a ledger hash
  is suppressed by the post-call gate (`ledger-suppressed`, counted once). An empty offer ends the step before the clone check and the
  open-create lookup, so a missing clone (`persist/clone-missing`) or an open create PR (`create-open`) is not surfaced on such a run.
- **Base moved.** Step B refreshes the clone to the current main, re-runs the admission checks on it, and, just
  before the commit (after a second fetch), compares the blob ids of `README.md`, `plugins/soleur/README.md`, the
  promotion log and the budget-cap file with the ones it used: `persist/base-moved` when ANY moved (an unrelated
  merge does not refuse). The same fetch lists the two new-slug directories (the skill dir and the Cursor stub dir):
  one that appeared on main while the gates ran is `persist/slug-appeared`. Accepted window: a README edit merged
  AFTER that second fetch and BEFORE `safeCommitAndPr`'s own fetch can still be reverted in the PR diff. The PR is a
  draft and the reviewer reads the diff; nothing merges automatically.
- **Orphan branch (`persist/branch-exists`).** The branch name is deterministic (`self-healing/auto-<cluster
  hash>-<run date>`). If an earlier attempt pushed it and the PR was never opened (or was closed), the new attempt
  finds the branch on the remote with no open PR and refuses `persist/branch-exists` instead of failing late as
  `failed-push`. If the earlier own-PR lookup could not be completed (a Sentry `create-own-pr-lookup-failed`), the arm looks once more
  before refusing, so a replay of an attempt that did open the draft still ends `opened`. The arm NEVER deletes a remote branch. Operator action: delete the orphan branch (GitHub UI, or
  `gh api -X DELETE repos/jikig-ai/soleur/git/refs/heads/<branch>`) and fire again, or wait for the next UTC day
  (the date is part of the name). The same-day wedge is a known limit. `persist/branch-probe-failed` is the probe
  itself failing (read `extra.cause`).
- **Git failures.** `fetch-failed`, `reset-failed`, `blob-read-failed`, `tree-read-failed`, `origin-strip-failed`,
  `branch-probe-failed` and `clone-not-clean` carry closed evidence: the marker field `create_exit` (git's exit
  status, absent when git was killed or never ran) and Sentry `extra.cause`, one of `timeout`, `exit<N>`, `signal`
  `spawn` or `bad-output`. `origin-failed` carries `extra.cause` of `symlink-refused` (a symlinked `.git` entry), `set-url-failed`
  (git refused the remote change) or an errno / class name. Sentry op `create-gate-git` is the per-call event: a
  SYNTHETIC error `git <sub> failed` with `extra` `{sub, exit, signal, killed, timedOut}`. Git's own stderr is never
  forwarded (a failed fetch against the tokenized origin echoes the remote URL there).
  `readme-sync/git-failed` and `persist/git-failed` (the clone snapshot before the sync, the snapshot after it, and the changed-set read
  of the collector) carry NO cause of their own: read the paired `create-gate-git` Sentry event of the same run (its `extra` has
  `sub`, `exit`, `signal`, `killed`, `timedOut`).
- **One deadline, pre-commit only.** Step B has one 150 s budget over the pre-commit phase (clone refresh, re-check,
  render, gates, second fetch and branch probe); every script and git call in it gets the smaller of its own timeout
  and what is left; an exhausted budget is `persist/deadline`, and the Sentry `extra.stage` names the stage that ran out: `fetch`, `reset`, `blobs`, `strip`, `write` (the checkpoint before the files are written), `scan`, `readme-sync`, `final-fetch`, `final-blobs`, `tree`, `probe` or `commit-guard` (the checkpoint before the commit helper). A git call that failed because the budget ran out is reported as `deadline`, not as the git refusal. It does NOT cover the own-PR lookup (it runs first,
  20 s), `safeCommitAndPr` (its own steps and timeouts) or the final cleanup.
- **A very busy repository refuses.** The one-open-create check reads at most 300 open PRs and the path scan makes
  at most 150 file requests: past either bound the arm refuses `create-open` (`list-incomplete` / `paths-incomplete`)
  rather than guess. Close or merge stale PRs.
  A fork PR never counts toward `create-open` (only a PR whose head branch is in THIS repository does; the repository
  name is compared case-insensitively). A flood of more than 300 open PRs, fork or not, makes the arm refuse
  `create-open/list-incomplete`: an accepted limit, the same bound the edit arm's open-PR read has.
- **Headroom is finite.** After one maximum-length skill merges the description budget headroom is 0, and every
  later create refuses `budget` / `over-headroom` until a human trims descriptions or raises the cap in
  `plugins/soleur/test/components.test.ts` (the cap is human-owned).

### Reading a live-fire row (model decline or gate refusal)

The marker already separates a model decline from a server-side refusal, so no extra
field is needed. Every gate except the ledger / same-run backstop returns `create_outcome: refused` with
`create_refusal_class` and `create_detail`. `no_action` with `no-pattern-qualifies` is therefore always the model's
own answer: no server path emits that reason (the pre-call filter yields only `all-owned` or `other`, with
`create_offered` at 0, and the backstop yields `other`). The backstop is the one `no_action` a server check produces
after a spent call (the model named a pattern it was not offered), so `other` on a row with `create_offered > 0` is
either the model's own `other` or that backstop, while `all-owned` on such a row is always the model's. Nothing on the
marker reliably separates the two `other` cases: the same-run branch adds neither `ledger_suppressed` nor a
`refusal_detail` entry, and the edit loop also increments both, so read a zero or absent value as unknown and a
non-zero one as a hint, never as proof. The arm makes one call and gets one verdict, so there is nothing to count. A row with `create_offered` absent (a memoized step that predates the field) cannot be
classified by offered count.

| Marker values | Meaning | Follow-up |
|---|---|---|
| `no_action`, `no-pattern-qualifies`, `create_offered > 0` | The model declined; no content gate ran. | None in code, however often it repeats: declining is the intended default and the bar stays. |
| `no_action`, `all-owned`, `create_offered > 0` | A call was spent and the model itself answered `all-owned`. | None in code. |
| `no_action`, `other`, `create_offered > 0` | A call was spent. The model answered `other` itself, or the backstop suppressed a create naming an unoffered owned pattern. The marker cannot tell which. | None in code. |
| `no_action`, `all-owned` or `other`, `create_offered = 0` | A pre-call path ended the arm (every candidate already claimed this run, or all owned); no call was spent. | None. |
| `refused`, `prefer-patch`, `nearest-not-top3` (`create_nearest_rank`) | A gate refused a model-proposed create. | One such live row opens a plan for supplying the server's per-pattern top-3 candidates in the prompt, as its own PR with its own operator-authorised live-fire. It is not a loosening of the gate. |
| `refused`, `prefer-patch`, `overlap` (`create_top1` at or above `OVERLAP_REFUSE_THRESHOLD`, also in the Sentry `extra.threshold`) or `open-pr-nearest` | The gate works as designed. | None. |
| `refused`, `shape`, `slug` or `budget` | Handled per class in this runbook. | None new. |
| `refused`, `model-invalid`, `max-tokens`, `empty`, `not-json`, `schema` or `unknown-pattern` | A call was spent and its output was unusable. | `max-tokens`: review the output token cap (reading only; a change is its own PR with its own operator-authorised live-fire). The others: the marker is the whole signal and the Sentry event adds nothing beyond it; no code follow-up is implied. |
| `refused`, `model-invalid`, `transport` | The call may not have reached the model (read the Sentry `extra.cause`). | Re-fire only on the operator's go-ahead. |
| `opened` | A draft PR exists (`create_pr` names it when present). | Record the PR and review it by hand. |
| any other `refused` row, for example `prefer-patch/nearest-missing`, `model-invalid/no-api-key`, `model-invalid/internal`, `persist`, `scan`, `readme-sync`, `stub-drift`, `input-size`, `week-cap`, `index-empty` or `create-open` | See the class and detail tables above. Some of these end before the call, so `refused` with `create_offered > 0` does not by itself mean a model-proposed create; `nearest-missing` (the model named a skill that is not in the list it was shown: missing, or model-invocation-disabled) is not the `nearest-not-top3` trigger. | None new from this section. |

What the marker cannot show: whether a decline was instant or deliberated. The only signal is `output_tokens` on the
`SOLEUR_CLAUDE_COST` row for the run (the create call is the last row under the run id). The 2026-10-28 records read
that row; a check of the 2026-10-29T08:03Z live-fire (Better Stack, by run id and then by marker over the following
hour) found none. The cause is not established. The related incident is #11049 (claude-cost-capture-dark, open as of
2026-10-29), but its alert counts cron cost rows with a non-null `cost_usd` across the whole fleet over 24 hours, so it
neither predicts nor explains one run's missing row. Check the run's own row before concluding it is absent. Fixing
the capture is separate work, not part of this arm.

### Review checklist for a create draft

The draft PR body carries this fixed checklist (server text, the same for every create). Reading a create draft:

1. Read every step, when-to-use and sharp-edge bullet as an instruction to an agent that holds shell access and secrets.
2. No step reads, prints or posts credentials or env files.
3. No step is destructive or irreversible.
4. No step moves money, sends mail or messages, or merges/approves without a human step.
5. No step treats fetched or issue content as instructions.
6. Will the description trigger on unrelated prompts? Narrow it or reject.
7. The skill is model-invocable by default: add `disable-model-invocation: true` if it should only run on request.
8. Scan `SKILL.md` and `PURPOSE.md` for names, domains or identifiers before merge.
9. Positioning: the skill makes Soleur sharper for the harness itself; no wording that promises an outcome in a
   user's workspace.
10. The skill does not restate or relax any hard rule.
11. Categorise the skill in `plugins/soleur/docs/_data/skills.js` (an unmapped skill shows as Uncategorized).
12. After a description edit, or a rebase onto a main that added another skill, rerun
    `bun plugins/soleur/scripts/sync-cursor-name-map.ts` and `bash scripts/sync-readme-counts.sh`.

Only `test` and `skill-security-scan PR gate` are real checks on the draft; the other required checks are posted by
the loop itself and prove nothing about the skill.

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
- Pattern wiki and ledger decision: `knowledge-base/engineering/architecture/decisions/ADR-300-pattern-wiki-and-pr-state-proposal-ledger.md`
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-021-stateless-self-modifying-cron.md`
- Audit log: `knowledge-base/project/learnings/promotion-log.md`
- Plan: `knowledge-base/project/plans/2026-05-11-feat-compound-promotion-loop-plan.md`
