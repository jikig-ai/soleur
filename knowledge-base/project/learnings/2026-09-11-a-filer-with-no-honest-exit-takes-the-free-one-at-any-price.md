---
title: A filer with no honest exit takes the free one at any price
date: 2026-09-11
category: workflow-patterns
tags:
  - filing-gate
  - net-issue-flow
  - scheduled-crons
  - measurement
  - guardrails
issue: 8076
related:
  - knowledge-base/engineering/architecture/decisions/ADR-216-machinery-ledger-and-filing-time-lever.md
  - knowledge-base/project/learnings/2026-09-08-my-live-verification-could-only-run-where-the-defect-was-invisible.md
  - knowledge-base/project/learnings/2026-09-04-four-of-my-checks-certified-something-narrower-than-their-names.md
  - knowledge-base/project/learnings/2026-09-10-every-escape-my-mutations-could-not-reach.md
  - knowledge-base/project/brainstorms/archive/20260912-022512-2026-09-11-filing-gate-run-report-exit-brainstorm.md
---

# Learning: a filer with no honest exit takes the free one at any price

## Problem

PR #8038 shipped a blocking filing gate with three exits and an ADR that said,
in words, that no filing exists which "must bypass the gate, cannot be labelled
machinery, and cannot name a user impact." Eleven hours later the first
scheduled agent to reach it — the daily community digest — was denied, read the
remediation, and filed with `--label meta/machinery`. The gate had worked
exactly as designed on the population it was designed for, and the operator's
question was whether the free exit is too cheap.

## Solution

The question was wrong, and answering it would have shipped the wrong fix.

A `Machinery: <path>` requirement on exit 1 would have produced
`Machinery: scripts/community-router.sh`. The digest cron had **no honest
exit**: its prompt says "creating the issue is REQUIRED: the platform only
persists your changes after it verifies the issue exists," and
`cron-cloud-task-heartbeat.ts` `TASK_INVENTORY` reads that issue's existence as
liveness. That is "mandated by construction" — the exact reasoning ADR-216 used
to exempt workflow-YAML filings — but these run in the cron substrate the gate
covers. Four crons are in that position (community-monitor, content-generator,
roadmap-review, competitive-analysis) — *corrected at plan time to nine; see
the addendum below*. The fifth inventory entry, legal-audit,
is *not*: its `scheduled-legal-audit` label covers up to five per-gap findings
per run, which is the audit exhaust the gate exists to gate.

So the fix is a **population** fix (a substrate-written, agent-unreadable
`run-report-label` directive the hook honours), plus **measurement** (report the
class-3 run-report floor and the exit-1 share beside the headline, so the
four-week check can tell relabel from reduce), plus **observability** (the cron
hook's deny never reached Better Stack; the whole denied-then-complied story was
inferred from the label set). Pricing exit 1 waits until the exit-1 share line
can say whether it needs pricing.

## Key Insight

**When a gate's first live contact produces a mislabel, ask "did this filer
have an honest exit?" before asking "is the free exit too cheap?"** A filer with
no honest exit takes whatever exit is available at whatever price; raising the
price only changes which dishonest artefact it produces. The tell is a filing
that is mandated by something the gate cannot see — a persistence handshake, a
liveness contract, a prompt that says REQUIRED.

Corollaries:

- **"There isn't one" is a claim to grep.** ADR-216's assertion was refutable in
  one command against `TASK_INVENTORY`. A closed-exit-set design should
  enumerate the mandated-by-construction filers *per covered class*, not just
  per uncovered class.
- **A flat headline cannot be diagnosed without an exit distribution.** The
  measurement counted filings regardless of label (so relabeling cannot hide),
  but reported no per-exit share (so relabeling cannot be *seen*). "Cannot hide"
  and "can be diagnosed" are different properties.
- **The wrong label accidentally gave the right lifecycle.** Run-reports had no
  lifecycle at all (43 open daily digests, last mass-closed by the operator);
  `meta/machinery` would have expired them at 90 days. When a mislabel produces
  a beneficial side effect, the side effect is a missing feature, not a reason
  to keep the mislabel — the drain would otherwise have tried to one-shot a
  community digest.

## Session Errors

1. **Counted `TASK_INVENTORY`'s five crons as five run-reporters.** Recovery:
   read each cron's prompt; legal-audit's label covers findings.
   **Prevention:** an inventory keyed on a *label* is not an inventory of
   *report-shaped filings* — read what each producer files under the label
   before deriving an exemption set from it.
2. **Asserted "mass-closed by hand" from `state_reason=completed` alone.**
   Recovery: `gh api .../issues/N/timeline` showed `closed_by: deruelle`, three
   closes in one second. **Prevention:** `state_reason` says what, never who;
   read the timeline before naming an actor.
3. **Two false denies from `guardrails:require-filing-justification` on honest
   exit-1 filings.** (a) A heredoc-then-`gh` one-liner containing "Soleur's"
   made `xargs -n1` abort on an unmatched single quote (`guardrails.sh:451`,
   stderr suppressed), so the `--label` token was never seen and the refusal
   said to add the flag already passed. (b) Re-run with `--body-file` alone,
   the unreadable-body deny (`guardrails.sh:616-628`) fired before `_fj_pass`
   was honoured — an exit-1 filing refused for a body it does not need.
   Recovery: write the body file in its own Bash call, then file.
   **Prevention:** tracked as FR7 of #8076 (quote-tolerant tokenizer fallback;
   honour exit 1 before the body-file check). Until then: never put prose with
   apostrophes in the same Bash call as `gh issue create`; write the body file
   first.
4. **Scratchpad directory absent on first heredoc write.** One-off; `mkdir -p`.
   **Prevention:** none needed beyond the mkdir.
5. **`cd /tmp` inside a tokenizer probe reset the shell CWD out of the
   worktree.** One-off. **Prevention:** run probes with absolute paths, no `cd`.
6. **Ended a turn on a first-person "I'll put the approaches to you" while an
   agent was still running.** Stop-hook caught it; the approaches went out in
   the same turn. **Prevention:** when waiting on a background agent, either
   act on what is already known or declare the wait explicitly.
7. **Discovered, not caused: the machinery-drain pool counts its own standing
   measurement issue** (`scheduled-machinery-drain.yml:62`, #8068 carries
   `meta/machinery`). Off by one on every run; the closing arm would drain its
   own ledger. **Prevention:** tracked as FR3 of #8076.

## Plan-time addendum (same day)

The brainstorm's answer survived planning; three of its premises did not.

**The population was wrong by four.** The brainstorm keyed the mandated
filers on `cron-cloud-task-heartbeat.ts` `TASK_INVENTORY` (five). The
contract that actually mandates a filing is `resolveOutputAwareOk` — the
"persist only if the scheduled issue exists" verify — and **nine** cron
functions call it, each passing `label: SENTRY_MONITOR_SLUG`. A heartbeat
inventory is a *liveness subset*; the filing population is whoever calls the
verify. Spec-flow found it by grepping the call sites; the brainstorm triad
and both research agents had all read the inventory and stopped. First fire
of a cron the brainstorm missed: architecture-diagram-sync, Sun 02:00Z — two
days after merge.

**A shape rule that looked airtight broke one member.** The advisor
consult proposed requiring a `[Scheduled] ` title on top of the label, to
close a file-and-vanish path. Kieran and architecture-strategist each read
every member's prompt: campaign-calendar's REQUIRED filings are `[Content]
Overdue: …` under `action-required,scheduled-campaign-calendar`. A rule over
a population is a claim about every member; check each member's actual
prompt before writing it.

**A side channel was designed before the existing channel was probed.**
The plan carried a hook-written `filing-denials.jsonl`, a pre-spawn
truncate, a `SpawnResult` field, an optional arg on the verify, and nine
one-line caller edits — to observe hook denials. One throwaway settings hook
under `claude --print --output-format json` showed a PreToolUse deny lands
in the result event's `permission_denials[]` with the full
`tool_input.command`. The substrate already parses that event. Everything
else was deleted.

### Session Errors (plan phase)

1. **Inherited population.** Recovery: spec-flow P0 → re-keyed on the
   `resolveOutputAwareOk` call sites with a grep-parity test; the residue in
   AC2/AC5/Guard 1 took three more reviewers to clear. **Prevention:** when a
   plan says "the set of X that must Y", grep the mechanism that *enforces* Y
   for its callers; a nearby list with the right-looking names is a
   hypothesis about the set, not the set.
2. **Shape rule not checked per member.** Recovery: title-half cut from the
   hook; the sweeper's title + author guards close the same path.
   **Prevention:** before adding a shape predicate over a population,
   `grep -n '"\[' <each member>.ts` — read every member's prescribed
   title/label strings, not the two you remember.
3. **Side channel before probe.** Recovery: 30-second probe; channel
   deleted. **Prevention:** before designing telemetry out of a spawned CLI,
   run it once with `--output-format json` and read the result event; a
   structured field usually already carries the signal.
4. **`issueCreated` placed where it cannot be computed.** Recovery: own
   grep found `resolveOutputAwareOk` in the cron functions, not the
   substrate. **Prevention:** before naming where a value is emitted, grep
   who computes it.
5. **Plan `Write` denied by `iac-plan-write-guard`** on "out-of-band" in a
   learnings citation. Recovery: rephrased to "via `--body-file`".
   **Prevention:** the guard's tokens (`operator (runs|installs|…)`,
   `operator-driven`, `out-of-band`, `manually install`) are matched
   anywhere in the plan; quote learnings by path, not by their trigger
   phrases.
6. **Leaf renamed without a sweep.** Recovery: reviewers caught
   `_cron-task-inventory` vs `_cron-run-reports`. **Prevention:** after any
   rename inside a plan, `grep -c '<old>' <plan>` must be 0 before review.
7. **Citation drift** (`main()` L701 vs L683; `SKILL.md:174` vs
   `group-by-area.sh:116-117`). Recovery: corrected from Kieran's read.
   **Prevention:** cite a line only after `sed -n` on it in the same turn.
8. **AC19 measured an open-count a concurrent filing could move.**
   Recovery: rewritten to the sweeper's own marker count (standing check).
   **Prevention:** `cq-ac-must-not-depend-on-concurrent-sessions`.
9. **Two `cd /tmp` probes reset the shell CWD; two turns ended on a
   first-person promise while agents ran.** One-offs. **Prevention:**
   absolute paths in probes; declare a wait explicitly.

## Review-time addendum (2026-09-12) — every check I wrote for the exit certified something narrower than its name

A 12-seat panel (the 8-agent code panel with a structural-enumeration seat in
place of agent-native, plus test-design, user-impact, observability and
simplicity) returned 45 findings on the implementation, all fixed inline and
none filed. Four were P1, and every one of the four lived in VERIFICATION,
not in the mechanism:

1. **The follow-through probe could never FAIL.** It read
   `.SOLEUR_CRON_FILING_DENY` at the top level of the decoded Better Stack
   `raw`; every live row nests the pino payload under `.message` (measured:
   38/40 cost-marker rows, 11/11 daily rows). AC18b was therefore vacuous
   and the probe would have closed #8076 through a real deny. The reading
   came from a runbook sentence — "`component` … as a **top-level key** of
   the decoded `raw`" — written from the plan, never from a row; a sibling
   probe (`anthropic-admin-key-6297.sh`) had carried the same reading since
   July and had reported `ZERO_PRODUCER_ROWS` on every sweep while its
   producer was alive. Both now decode `.message` first, and each has a
   fixture suite in the LIVE shape whose control and graded absence go
   through ONE decoder (a top-level reader reds on the control row).
2. **The probe's directive lacked `GH_TOKEN`.** The sweeper runs probes under
   `env -i` and forwards only names in `secrets=`; the header's "GH_TOKEN
   (sweeper default)" was a claim, not a read of `sweep-followthroughs.sh`.
   Exit 2 forever, rendered as the reassuring heading `NOT YET`.
3. **AC19's threshold was unreachable.** "≥ 25 closed, 43 eligible" was an
   open-count. Classifying the 43 through the guards the SAME plan defines
   gave 36 FAILED-bodied, 3 human-commented, 1 too young — at most 3 closes
   on first fire, and a deterministic false alarm. The property is the
   guard (no marker-closed digest is FAILED-bodied), not a count.
4. **The cron hook allowed a bare `$GH_TOKEN`** in a filing's title while
   `buildSpawnEnv` places the installation token in the sandbox env
   (pre-existing: `dangerousMetacharReason` denied `${…}` and `$(…)` only).
   The run-report exit lowered the bar to reach the create on every run,
   which is what made the security seat look at the create's argument
   surface at all.

Three P2 shapes worth naming because they recur:

- **The population is a claim.** The sweeper's human-comment guard
  (`user.type !== "Bot"`) read PAT-era `**Automated Triage**` comments —
  posted by a `User` login through the `claude` GitHub App — as human; 75 of
  117 live candidates were permanently unsweepable, visible only by
  classifying the real population, not a fixture. Automation is now
  Bot ∨ known actor ∨ (app-performed ∧ triage's own prefix).
- **A hand-mirrored predicate is a second pin on one truth.** Four seats
  independently found the deny marker's `FILING_SHAPE` regex diverging from
  the hook's `isApiIssue` (method-first, `-f title=` without a method). The
  fix was not a better regex: the marker now imports the hook's `filingShape`
  over the hook's tokenizer — one predicate, two consumers, no parity test
  needed because there is nothing to keep in parity.
- **A derivation that is a text regex over source is not an execution.**
  The parity test's call-site regex accepted only `[const x =][await ]f(`
  and missed `return f(`, `x = f(`, `step.run(() => f(`; the triage test
  substring-grepped a jq predicate that `and`→`or` left green; the probe
  had no fixtures. Each became an execution: comment-and-string-stripped
  extraction proven on a fixture directory, the extracted jq run on a
  fixture, the probe run on live-shaped rows.

Also fixed: a `created:`-keyed sweeper re-closed a human-reopened report
every day (the marker's age now distinguishes "retry" from "reopened"); the
`scheduled-*` triage exclusion over-reached onto legal-audit findings and
campaign-calendar action items (keyed on the eight sweepable labels from the
leaf); 80 unpaced mutations on day one (1 s pace); cap checked after the
comments GET (hoisted); `<<<` here-strings matched the heredoc regex;
`permission_denials` absent ≡ `[]` (now `capture_status: field-absent`);
runbook fields that did not exist on the marker (`runId`/`runStartedAt` →
`run_id` ↔ Sentry `inngest.run_id`); the ADR heading over a four-item list.

**Key insight, review-time.** On a PR whose subject is a guard, the highest
defect density was in the artifacts that VERIFY the guard — the probe, the
ACs, the runbook, the tests — and each defect was the same shape: a
sentence written from what the author intended, standing in for a
measurement of what the system does. The cheapest instruments found the
most: one live `betterstack-query.sh | jq` run (row shape), one `gh search`
classified through the guards (population), one grep of
`sweep-followthroughs.sh` (secrets). Panels find these too, at ~1.8M tokens;
the measurement costs seconds and belongs BEFORE the sentence is written.

### Session Errors (review phase)

1. **Design-validity lenses ran concurrently with the panel** rather than as
   the serial pre-phase the review skill prescribes. Deliberate: the design
   was operator-decided at plan time (D1, "directive + minimal lifecycle"),
   so a design pass could not have deleted a mechanism; dedup preserved.
   **Prevention:** state the deviation and its reason in the classification
   announcement, as done.
2. **The shared-context prompt file was blocked by the full-command-line
   process-grep guard** on a literal flag string inside prose (twice — the
   second time inside THIS learning's first draft). **Prevention:** describe
   a forbidden invocation by its flag's NAME, never its spelling, in any text
   that passes through a heredoc.
3. **`git rev-parse HEAD origin/<branch>` printed `fatal: Needed a single
   revision` twice after a push.** Instrument noise (the remote-tracking ref
   updates on fetch). **Prevention:** `git fetch` before reading
   `origin/<branch>`; never read a push verdict off a following command.
4. **shellcheck SC1111/SC1007** on unicode primes in row names and
   `VAR= func`. One-off, fixed. **Prevention:** ASCII row names; `VAR=''`.
5. **`gitleaks dir <files>` reported 7 hits from the CWD's gitignored
   `.env`**, not from the named files. **Prevention:** scan with
   `gitleaks protect --staged` and `gitleaks git --log-opts=<range>`; `dir`
   mode walks the directory regardless of the paths given.
6. **The jq exclusion's first draft rebound `.`** inside
   `select($n | index(.))` and excluded every issue. Caught by executing the
   predicate on a six-issue fixture before committing — the same defect
   class the test-design seat had just flagged in the substring-grep test.
   **Prevention:** in jq, bind the outer value (`. as $l`) before piping to
   another value; execute every predicate on a fixture with members on BOTH
   sides.
7. **`lint-shell-trace-credential-refusal` flagged the rewritten probe**
   (binds credentials, no xtrace refusal). Fixed with the lint's own block.
   **Prevention:** run the repo lints on the fix batch, not only at session
   start — three of the lints fire only on NEW code.
8. **The fixture harness's `run_probe` was written as `$(...)`**, so `OUT`
   never reached the parent shell and all 15 rows reported unbound. One-off.
   **Prevention:** a runner that sets a verdict variable must not be called
   in a command substitution; set `RC`/`OUT` as globals.
9. **Inherited-sentence class:** the runbook's row-shape prose was written
   from the plan and misled two probes (#1 above). **Prevention:** a
   sentence about a live artifact's SHAPE is a measurement, not a
   description — run the query, paste the `jq` line that shows the shape,
   and give every consumer a fixture in that shape.
10. **Stale scheduled-wakeup prompts** (plan-phase text) fired twice
    mid-review. Recognised as stale, not acted on. **Prevention:** a
    self-authored wakeup should carry the phase it belongs to, so a later
    phase can discard it on read.

## Tags

category: workflow-patterns
module: guardrails / issue-flow / cron-substrate
