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
2. **Do not trigger one while any `self-healing/auto` PR is open** (it would stack drafts on the
   week-cap and on an unreviewed proposal).

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
| `ledger_suppressed` | clusters dropped because the same recomputed hash is already proposed (open, merged, or closed unmerged within 60 days) | Each also appears as `ledger-suppressed` in `refusals[]` and `refusal_detail[]` (`{cluster_hash, reason}`). `status=no-qualifying-clusters` with `ledger_suppressed > 0` means every cluster was suppressed. `clusters_proposed` stays pre-suppression. Slot starvation (accepted): the patterns arm slices the model's clusters to the week-cap `remaining` (at most 2) BEFORE suppression and does not tell the model which hashes are suppressed, so a repeatedly proposed rejected or merged cluster, or a same-evidence duplicate (`cluster-duplicate`), can occupy the slots and end a week `no-qualifying-clusters` with `ledger_suppressed >= 1`. A second cluster with the same source set in one run is refused `cluster-duplicate` |
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
  `data.allow_create:true` (default off). The scheduled run, a manual `corpus` run and a non-boolean
  `allow_create` leave it absent and the run unchanged. The edit loop runs first; the arm then uses what is left
  of the week cap (it counts all open `self-healing/auto` PRs, not a calendar week).
- **Output.** At most ONE create per run: a DRAFT PR adding a markdown-only skill (`SKILL.md`, `PURPOSE.md`,
  Cursor stub) plus two README counts and one ledger row, body line `CREATE (new skill)`. Never auto-merged.
- **Preconditions for the first live fire (an operator-authorized production act, NOT performed by #10550):**
  the evidence PRs #11230 and #11231 merged or closed (otherwise every manual fire ends `week-cap-reached` before
  the arm); a runtime flag created through `soleur:flag-create` if the trigger-secret holder check in
  `phase0-measurements.md` ever finds a non-operator holder; the deploy verified (`deploy-arm.sh find --wait`
  and the served build sha equal to the merge sha); the compliance-posture dated note read.
- **Reading a refusal.** One refusal reason, `create-refused`, with a closed `class`; Sentry mirror op
  `create-refused` with a `class` tag. A refused create writes NO ledger row, so a pattern refused for budget or
  scan is retried once headroom frees.

| `class` | Meaning | How to read it |
|---|---|---|
| `week-cap` | no week-cap slot left after the edit loop | expected while any `self-healing/auto` PR is open; close or merge the open drafts |
| `create-open` | another open PR already carries the `CREATE (new skill)` line, or the open-PR list could not be read | one open create at a time; a list failure refuses rather than guesses |
| `index-empty` | no open pattern page to read | check `patterns_open` |
| `input-size` | pattern index plus skill list exceeds the input ceiling | refused, never truncated; trim the index or raise the ceiling by amending the ADR |
| `model-invalid` | the model answer did not parse into the closed schema | one call, no retry; read the Sentry event |
| `shape` | a model string or a rendered file failed the shape allowlist, claim-word, PII or credential screen | the marker carries the field name, never the text |
| `slug` | slug collides with a skill dir, agent name or an open PR path | choose another pattern or wait for the open PR |
| `prefer-patch` | the nearest skill ranks in the top three by overlap and overlap is over the threshold | the marker carries rank and top-1 score (numbers); patch that skill instead |
| `budget` | description words exceed `cap - total`, or the cap or a description could not be parsed | the marker carries `cap` and `total` (numbers); free words by trimming a description in a human PR |
| `scan` | the scanner did not return an explicit LOW-RISK first line with exit 0 on BOTH files (HIGH-RISK, REVIEW, empty, non-zero, timeout, missing tool) | `detail` says which; a missing tool means the runner image lacks a dependency |
| `readme-sync` | the README sync changed anything beyond digits in the two README files | a script defect; the draft is not opened |
| `stub-drift` | the rendered Cursor stub differs from the generator's output | rerun the generator after a header change; the parity test should have caught it |
| `persist` | the commit or PR step failed for a genuine reason | read the workflow-run log |

`create_detail` values by class (closed tokens; a `<field>:<rule>` token names the model field and the shape rule, never its text):

| `class` | `create_detail` values |
|---|---|
| `week-cap` | `no-slot` (the edit loop used the last slot, or none was free) |
| `create-open` | `open-create-pr`, `list-failed`, `list-incomplete`, `paths-unverifiable`, `paths-incomplete` |
| `index-empty` | `no-open-patterns` |
| `input-size` | `over-ceiling` (numbers: `tokens`, `max`, `bytes`; the bound is bytes / 4) |
| `model-invalid` | `no-api-key`, `transport`, `max-tokens`, `empty`, `not-json`, `schema`, `unknown-pattern`, `no-strings`, `internal` |
| `shape` | `<field>:<rule>` from the shape allowlist, `<field>:pii`, `<field>:credential`, `rendered-<file>:<pii or credential>`, `template-unreadable`, `render`, `grok-block`, `fence:*`, `size:*`, `frontmatter*`, `purpose-link`, `slot-left:purpose` |
| `slug` | `format`, `reserved`, `skill-exists`, `agent-exists`, `cursor-name-exists`, `open-pr-slug` |
| `prefer-patch` | `no-skill-list`, `nearest-missing`, `nearest-not-top3`, `overlap`, `open-pr-nearest` |
| `budget` | `skills-dir-unreadable`, `frontmatter-*`, `description-not-a-string`, `population-below-floor`, `cap-unreadable`, `unreadable`, `words-out-of-range`, `over-headroom` |
| `scan` | `high-risk`, `review`, `non-zero`, `empty-output`, `timeout`, `unrecognised`, `missing-tool`, `input-too-small`, `input-unreadable`, `meta-base-invalid`, `no-input`, `count-mismatch` |
| `readme-sync` | `readme-unreadable`, `git-failed`, `timeout`, `script-failed`, `unexpected-change`, `no-change`, `non-digit-change` |
| `stub-drift` | `stub-differs` |
| `persist` | `branch-shape`, `clone-not-clean`, `internal`, `path-missing`, `path-not-regular`, `path-empty`, `path-too-large`, `path-nul`, `path-not-utf8`, `git-failed`, `changed-set-mismatch`, `path-count`, `unexpected-path`, `missing-path`, `duplicate-path`, `failed-<stage>` and `not-committed-<status>` (the commit helper's own exit) |

- **Kill switch.** Stop firing manual triggers with `allow_create`; the flag is read per event and is off by
  default, so no deploy is needed to switch the arm off. The existing opt-out in this runbook also stops it.

### Create-arm marker fields

Every field below is absent from a scheduled row and from a manual `corpus` row (the field set of those rows is
byte-identical to before the arm existed). `create_requested` is the only one present when the arm did not run.
All are booleans, closed enums or numbers, except `create_detail`, a closed token (a field label plus a rule id,
or a fixed phrase) that never carries model text. Query recipe: `betterstack-log-query.md`.

| Field | Meaning | How to read it |
|---|---|---|
| `create_requested` | a manual `patterns` row: whether the event carried `allow_create === true` | Present on EVERY manual patterns row, including the early `disabled`, `deduped` and `week-cap-reached` rows. `false` means the arm was off (a non-boolean `allow_create` such as `"true"` or `1` is ignored, never coerced). `true` with no `create_arm` means the run ended before the arm: read `status` |
| `create_arm` | `ran`, emitted ONLY when the arm ran | Absent means off. With it, `kind` is `create` |
| `kind` | `create` (the type also names `edit`, which is never emitted) | Emitted only together with `create_arm` |
| `create_outcome` | `no_action`, `refused` or `opened` | `no_action` = the model declined (`create_no_action_reason`) or the pattern is already proposed (`ledger-suppressed` in `refusals[]`, `ledger_suppressed` counted). `opened` = a draft PR exists (`create_pr`). `refused` = one `create-refused` entry in `refusals[]` plus `create_refusal_class` and `create_detail` |
| `create_no_action_reason` | `no-pattern-qualifies`, `all-owned` or `other` | `other` also marks a suppressed (already proposed) pattern |
| `create_refusal_class`, `create_detail` | the `class` table above and its closed token | The same pair is mirrored to Sentry (op `create-refused`, tag `class`, `extra.detail`) |
| `create_words`, `create_cap`, `create_total` | description words requested, the budget cap and the current model-visible total | Budget refusals only; `cap - total` is the headroom the description must fit |
| `create_top1`, `create_nearest_rank` | the best overlap score with an existing skill and the rank of the model's nearest skill | `prefer-patch` refusals only; compare with the refusal threshold in the PR body trailer |
| `create_pr` | the draft PR number | `opened` only |

Where the create outcome sits: the arm runs AFTER the edit loop, so `status` is the edit loop's status
(`completed`, or `no-qualifying-clusters` when the edit arm had nothing to open) and `clusters_opened` counts edit
PRs only. A create PR is never counted there. A run whose edit loop already used the last week-cap slot ends with
`create_refusal_class: "week-cap"`; a run that finds the cap saturated before the loop (today: #11230 and #11231 are
two open `self-healing/auto` PRs) ends `week-cap-reached` and never reaches the arm.

- **Where the cause is readable without SSH.** Better Stack: the marker row (recipe in `betterstack-log-query.md`).
  Sentry: one MESSAGE event per refusal, feature `cron-compound-promote`, op `create-refused`, tag `class`, with
  `extra.detail` and the same numbers. Infrastructure faults have their own ops: `create-gate-spawn` and
  `create-gate-git` (a gate script or git could not run), `create-propose-internal` and `create-persist-internal` (a
  defect inside a step, converted to a returned refusal), `create-own-pr-lookup-failed` (the replay lookup; the step
  continues) and `create-clone-restore-failed` (the clone could not be returned to a clean main).
- **A refused create writes no ledger row.** The promotion-log row exists only inside a committed PR, so a pattern
  refused for budget, scan or sync is retried on the next manual fire once the cause is gone.
- **Replay.** Step `create-propose` is memoized and never throws; step `create-persist` looks up its own open PR by
  the deterministic head branch (`self-healing/auto-<cluster hash>-<run date>`) and counts a hit as success, so a
  replay cannot open a second PR.

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
