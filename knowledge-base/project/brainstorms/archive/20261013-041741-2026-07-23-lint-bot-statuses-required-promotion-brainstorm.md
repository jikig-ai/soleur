---
date: 2026-07-23
topic: Promote the credential-path guard from advisory to blocking
issue: 6882
branch: feat-lint-bot-statuses-required-promotion
pr: 6883
lane: cross-domain
brand_survival_threshold: single-user incident
status: complete
tags: [ci, required-checks, credential-leak, synthetic-checks, adr-032, adr-129]
---

# Brainstorm: promote the credential-path guard to a blocking required check (#6882)

## What We're Building

Extract `scripts/lint-credential-path-literals.py` out of the bundled `lint-bot-statuses`
CI job into its own always-run job, run it in **full-scan** mode, and promote **only that
job** to a blocking required status check — while adding an earned-green preflight
reproduction to the bot-PR composite action so bot PRs cannot merge under a fabricated pass.

`lint-bot-statuses` stays advisory and keeps its remaining six steps.

## Why This Approach

The issue framed a binary decision ("reproduce the scan in the action preflight, OR exclude
via a non-15368 `integration_id`") over a job it described as bundling four checks. Direct
verification changed the shape of the problem in four ways.

### 1. The issue's option B is not an exclusion — it is a deadlock

A GitHub Actions job's check-run is always posted under `integration_id` 15368. Requiring a
context under any other integration id means **no producer exists** for it on a bot PR, and
bot PRs do not trigger CI at all. The result is not "the guard is excluded from fabrication",
it is "every bot PR stalls pending forever" — the exact `#6049` failure the SSOT comment was
written to prevent. `CodeQL` is not a counterexample: it is pinned to 57789 because GHAS
posts it independently of Actions, and it is *deliberately omitted* from `required-checks.txt`
for that reason.

### 2. There is a third, twice-used option the issue does not mention — and it is the wrong one here

The repo has an established pattern for adding a content-scoped gate to `required-checks.txt`
and documenting the synthetic green as **FABRICATED-NOT-EARNED but sound by unreachability**:

| Precedent | Guarded surface | Why sound |
|---|---|---|
| `rule-body-lint` (#6103 / ADR-092) | `AGENTS.{core,docs,rest}.md` | not in `ALLOWED_PATHS` |
| `sentry-destroy-required` (#6589 / ADR-031 amendment) | `apps/web-platform/infra/sentry/**` | not in `ALLOWED_PATHS` |

Both carry a written tripwire: *"the residual goes LIVE the instant `<path>` is added to
`ALLOWED_PATHS`."*

That argument does **not** transfer to the credential-path guard. Its
`SCAN_DIRS = ("plugins", "knowledge-base")` over tracked `*.md` minus `**/archive/**`
**includes** `knowledge-base/project/weakness-digest.md`, which is one of exactly two paths
the bot composite action is allowed to write. The guarded surface is inside the bot's write
set, so the fabricated assertion would not be vacuously true.

### 3. …but the reachability is narrower than first assessed — and that makes it *worse*, not better

**Correction (recorded because it was asserted before verification):** the first pass of this
brainstorm described `weakness-digest.md` as "model-generated prose", and the CLO assessment
repeated that framing. It is false. `scripts/weakness-miner.sh` is a deterministic bash
clusterer with zero mutation surface; the digest body it emits is only
`basename "$p"` of learning file paths, plus tag labels and cluster counts. No learning prose
is copied. A credential path could only appear today via a learning *filename* — practically
negligible.

The sharper point is that this is **not a stable property**. The digest's content shape is
governed by an unpinned generator format that no test and no tripwire watches. A natural,
innocuous enhancement — emit each learning's frontmatter *title* instead of its bare filename,
so the digest is readable — makes the surface genuinely reachable overnight. And the existing
tripwire discipline would **not fire**, because it is keyed on `ALLOWED_PATHS` edits, not on
generator output format.

So the choice is between a soundness argument that depends on a bash script's `echo` format
staying frozen forever, and a ~3-line preflight that is correct regardless. That is the whole
case for earning the green.

### 4. The backlog drain unlocked full-scan mode, which the issue does not consider

Measured on this branch:

| Guard | Full-scan result | Promotable full-scan? |
|---|---|---|
| `lint-credential-path-literals.py` | `OK: no resolvable credential-file path literals in 7450 scanned file(s)` — exit 0 | **yes** |
| `lint-infra-no-human-steps.py` | `FAIL: 475 prescribed human-run infra step(s)` — exit 1 | no, changed-files only |

Because the grandfathered backlog was drained to zero (merged 2026-07-23), the credential
guard passes a full repository scan *today*. Per
`knowledge-base/project/learnings/2026-06-29-required-check-anchors-must-cover-verified-surface-not-inherited-paths.md`,
promoting a changed-files gate makes its diff anchors part of the security contract — a green
then asserts only "this diff is clean". Full-scan makes the green assert "the repository is
clean", removes the `--base` merge-base dependency (which is fragile on `merge_group`, where
`github.base_ref` is empty), and closes silent re-accumulation via renames or `archive/` moves.
This option is available only because of the drain, and only for this one guard.

### 5. Job-level promotion is the wrong granularity

The issue says the job bundles four checks. It runs **seven steps**, two of which are
deliberately non-blocking:

- `lint-trap-tempfile-ownership.py` (+ its `--check-highwater` ratchet) — ADR-129 states in
  terms that promotion "is a deliberate follow-up with merge-queue blast radius, not a side
  effect", and #6752 tracks three still-open sites.
- `lint-orphan-test-suites.sh` — carries a live carve-out (#6751: a suite that fails on `main`
  is excluded from the gate).
- `lint-infra-no-human-steps.py` — 475 full-scan violations; changed-files only.

Promoting the job promotes all of these, silently reversing ADR-129 and turning two open
issues into merge blockers. Splitting costs one additional public-ABI ruleset context
(ADR-032 Sharp Edge 1: a job rename silently un-requires the check until the paired Terraform
edit lands) — a real but bounded cost already paid nineteen times.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Extract `lint-credential-path-literals.py` into its own always-run ci.yml job; promote only that job | Avoids reversing ADR-129 and the #6751 carve-out; keeps a blocking security gate unconflated with self-declared advisory linters |
| D2 | Run the promoted guard in **full-scan** mode, not `--changed --base` | Backlog is zero, so it passes today; green then means "repo is clean", not "diff is clean"; removes merge-base fragility on `merge_group` |
| D3 | Earn the bot green via a Phase-4 preflight reproduction in `bot-pr-with-synthetic-checks` | The unreachability precedent depends on an unpinned generator format no tripwire watches; the linter accepts explicit positional paths, so the step is ~3 lines |
| D4 | Reject the issue's `integration_id` option | Actions always report as 15368; requiring another producer deadlocks every bot PR |
| D5 | Leave `lint-bot-statuses` advisory with its remaining six steps | Their promotion is separately tracked (ADR-129 / #6752 / #6751) and separately gated |
| D6 | Land the four-file fan-out in one PR; the ruleset applies on merge | The parity test enforces file-vs-file set equality, so partial staging goes red immediately |
| D7 | Write an ADR for the general rule; add a `compliance-posture.md` ledger entry | Per CLO: the advisory→blocking upgrade is Art. 32(1)(d) evidence; the ADR generalises the ALLOWED_PATHS ∩ SCAN_DIRS test |

## User-Brand Impact

- **Artifact:** the `credential-path-guard` CI check — the merge gate standing between a
  tracked doc and Claude Code's harness auto-attaching a live credential file into model context.
- **Vector:** a doc reintroduces a home-relative resolvable path to a real credential file; the
  harness resolves and reads it as a Read-tool result; a live token lands in session transcripts
  shared with a model provider outside any registered processing agreement.
- **Threshold:** `single-user incident`.

This is a realized-class vector, not a hypothetical: `preflight/SKILL.md` Check 10 previously
wrote the literal home-relative path to the operator's live Doppler CLI config, and a live
`dp.ct.*` token was read into transcripts. Non-technical Soleur users cannot read CI, so an
advisory gate offers them nothing — per
`knowledge-base/project/learnings/2026-07-20-an-advisory-gate-is-not-a-weak-gate-it-is-no-gate-and-a-ratio-needs-its-denominator-checked.md`,
an advisory gate is not a weak gate, it is no gate.

## Open Questions

1. **Job name.** `credential-path-guard` is proposed. Once chosen it is public ABI in three
   files (ADR-032); confirm at plan time and never rename without a paired Terraform edit.
2. **Full-scan runtime.** 7450 files scanned comfortably in the local run; confirm the added
   wall-clock on the hosted runner is acceptable before merging.
3. **Ordering.** The preflight reproduction must merge *no later than* the name entering
   `required-checks.txt`. If the name lands first, every bot PR in that window ships a
   fabricated green. Plan must pin these to one PR.
4. **`scripts/create-ci-required-ruleset.sh` / `update-ci-required-ruleset.sh`** both read the
   canonical JSON rather than hardcoding the set — verified, but re-confirm at implementation.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

Path (A) — reproduce in preflight — not the unreachability precedent, which would be its first
application to a reachable surface. Job-level promotion is the wrong granularity: split the
genuinely-blocking doc gate out and leave the self-declared advisory linters alone. All four
fan-out artifacts must co-land because the parity test enforces set equality file-vs-file; the
ruleset apply must not precede the job existing on `main`. Flagged that this warrants an ADR
citing the `ALLOWED_PATHS ∩ SCAN_DIRS` test as the general rule.

### Legal (CLO)

Not an Art. 33/34 personal-data breach — a Doppler token is infrastructure credential, not
personal data — but an **Art. 32(1)(b)** confidentiality failure over a credential that unlocks
systems processing personal data, plus secret-in-transcript disclosure outside any registered
processing agreement. The accountability hook is **Art. 32(1)(d)**: the duty to regularly test
and evaluate the effectiveness of a technical measure. A control that cannot block is not an
effective measure. No statutory clock fires on the residual alone. Verdict on the tripwire-comment
pattern here: **not defensible** — a comment is not a control. No Article 30 amendment needed;
an ADR plus a `compliance-posture.md` ledger entry are.

*(Note: the CLO assessment was given the "model-generated prose" framing for `weakness-digest.md`,
which was subsequently falsified — see the correction above. The verdict is unaffected: it turns
on the surface being in scan scope, which remains true.)*

### Product (CPO)

Worth doing now — zero backlog means the ratchet is cheap to close, not that it is closed; one
ignored red merge restores the vector. Real user-impact case (founders cannot read CI; the
failure mode is a credential in their session context), but size it as hours, not the epic the
issue implies. Recommended splitting the preflight change from the ruleset change so a preflight
bug and a merge-gate change are not in the same rollback.

## Session Errors

1. **Asserted "model-generated prose" before reading the generator.** I described
   `weakness-digest.md` as model-generated and threaded that into the CLO prompt, which
   repeated it. `scripts/weakness-miner.sh` is deterministic bash emitting only basenames,
   tags and counts. Caught by the repo-research pass and corrected above. The conclusion held
   for a different and better reason. *Rule applied late:* verify a generator's output shape
   by reading it before characterising its content in a prompt to another agent.
2. **Issue-body counts taken at face value initially.** The issue's "four bundled checks" is
   seven steps / six distinct linters. Confirmed by reading the job. Reinforces the existing
   guidance to re-derive inventory counts cited in an issue body.

## Prior Art Consulted

- `2026-07-20-an-advisory-gate-is-not-a-weak-gate-it-is-no-gate-and-a-ratio-needs-its-denominator-checked.md`
- `2026-07-16-advisory-first-precedent-is-a-claim-to-measure-and-a-coordinate-citation-carries-no-claim.md`
- `2026-06-29-required-check-anchors-must-cover-verified-surface-not-inherited-paths.md`
- `security-issues/2026-07-05-fabricated-green-content-gate-ceiling-and-verification-sentinel.md`
- `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md` (name-as-ABI)
- `2026-04-03-github-ruleset-put-replaces-entire-payload.md`
- ADR-032 (branch protection as IaC), ADR-092, ADR-129, ADR-031 amendment 2026-07-17
