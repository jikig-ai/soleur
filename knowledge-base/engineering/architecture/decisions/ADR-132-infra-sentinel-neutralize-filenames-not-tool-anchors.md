---
title: Infra sentinel — neutralize filenames, never anchor imperatives on tool adjacency
status: active
date: 2026-07-21
---

# ADR-132: Infra sentinel — neutralize filenames, never anchor imperatives on tool adjacency

## Context

`scripts/lint-infra-no-human-steps.py` is the enforcement teeth for
`hr-no-ssh-fallback-in-runbooks`. It flags a doc line when a HUMAN-ACTOR token and an
INFRA-IMPERATIVE token co-occur (or sit adjacent in the non-blank line sequence). Soleur
users are non-technical and act only through the web app / CI, so a prescribed human-run
infra step is an automation bug that must fail CI.

Issue #6771 reported a false positive: the imperative `-target … appl(y|ies|ied)` matched
the CI workflow FILENAME `apply-web-platform-infra.yml`, because the hyphen after `apply`
is a word boundary. Prose that *correctly* documents a CI-driven apply was therefore
flagged as prescribing a human step. That filename is cited across 20+ docs in the scan
dirs, so the pattern recurs; each occurrence gets carved out with a `lint-infra-ignore`
region, and every carve-out is a region where real violations also stop being detected.
That erosion is the issue's stated motivation.

The issue proposed three fixes, in its own preference order: (1) neutralize `*.yml` /
`*.yaml` filenames before matching; (2) anchor the `-target` imperative on
`terraform|tofu|opentofu` adjacency, matching every sibling imperative — it is the only
imperative with no tool anchor; (3) exclude possessive actors, which the issue itself
rated narrower and less clearly right.

The implementation plan inverted that order and made option 2 primary, on a measured
"~45 latent false positives removed" versus option 1's ~8. This ADR records why that
inversion was wrong and what governs the sentinel going forward.

## Considered Options

- **Option A: filename neutralization only.** Blank `*.yml`/`*.yaml` filenames to `_`
  before the actor/imperative scan, on the reasoning that a filename NAMES automation and
  can never instruct. Pros: closes the reported defect; removes 8 false positives;
  matches the issue author's ordering. Cons: leaves ~41 latent `-target … apply` false
  positives in the corpus, and carries a narrow false-negative of its own (an imperative
  living only inside a filename), mitigated by `STRONG_ACTOR_RE` — see Decision.
- **Option B: filename neutralization + tool anchor.** Additionally require a
  `terraform|tofu|opentofu` token adjacent to `-target`. Pros: removes 49 false positives
  total; makes the imperative set internally consistent, since every sibling is
  tool-anchored. Cons: **silences genuine human-run steps** — measured below.
- **Option C: filename neutralization + a narrower anchor** (tool adjacency OR an explicit
  apply-object such as "apply the host"). Pros: keeps some of B's reach while trying to
  preserve human-phrased applies. Cons: more regex surface and new fixtures, spent to
  rescue a hypothesis the measurement falsifies.

## Decision

**Option A.** Neutralize `*.yml`/`*.yaml` filenames before the scan. Do **not** anchor the
`-target … apply` imperative on tool adjacency, despite the apparent consistency win.

Measured at production scan scope (`SCAN_DIRS` only), all arms on one tree, `LC_ALL=C`
pinned on every `sort`/`comm`:

| arm | unique flagged lines | removes |
|---|---|---|
| baseline (`origin/main`) | 478 | — |
| A — filename neutralization | 470 | 8 |
| B — plus tool anchor | 429 | 41 more |

Both arms are strict subsets of the baseline (zero newly-flagged lines).

The plan assumed those 41 were latent false positives. Reading all 41 shows **12 are
unambiguously genuine human-run infra steps (~29%)**, rising to ~17 (~41%) on a generous
reading of the borderline cases — silenced because the natural phrasing omits the tool
name. Confirmed cases, each verified flagged **in context** (whole file, not an extracted
line):

<!-- lint-infra-ignore start: EVIDENCE CITATIONS. These quote the corpus lines that a tool
     anchor would silence — they are the measurement this ADR records, not steps anyone
     performs here. Removing this region makes the ADR flag under its own sentinel. -->
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md:50` —
  "This maintenance-window apply is a **FULL operator apply** (not the per-PR CI `-target`
  path)". This is a RUNBOOK, the exact artifact class `hr-no-ssh-fallback-in-runbooks`
  polices.
- `knowledge-base/project/plans/2026-04-30-fix-terraform-drift-deploy-pipeline-fix-3061-plan.md:323`
  — "Operator must read the plan output and type `yes` interactively".
- `knowledge-base/project/specs/feat-one-shot-fix-ci-ssh-auth-deploy-pipeline-fix/session-state.md:13`
  — `terraform_data.root_authorized_keys` "must be applied LOCALLY by the operator".
- `knowledge-base/project/specs/feat-one-shot-3485-tf-drift-fix/session-state.md:12` —
  two `-target`-scoped applies, "each requires its own per-command operator ack".
<!-- lint-infra-ignore end -->

**A correction worth recording, because it nearly became the ADR's evidence.** An earlier
draft cited `2026-07-07-fix-zot-doppler-registry-isolation-plan.md` as a fourth confirmed
case. It is not a member of the 41: that line sits inside a `lint-infra-ignore` region, so
it is flagged by **zero** arms. The error came from verifying it by extracting the single
line into a temp file — which strips it from its region and changes the verdict. A
line-level probe is not a valid measurement for a scanner whose unit of judgment is the
file. Verify in context, always.

The deciding asymmetry: **a false positive costs an author one carve-out; a false negative
costs a non-technical operator an un-automated infra step**, which is the entire reason the
sentinel exists. Resolve toward sensitivity. Worse, a carve-out is visible and auditable
while a silent miss is not — so option B would have *converted* auditable carve-outs into
invisible misses, which is strictly worse than the erosion it was meant to cure.

Option A alone closes #6771 as filed. This was verified by mutation: with the anchor
reverted, the regression test reproducing the reported defect stays green.

<!-- lint-infra-ignore start: EVIDENCE CITATIONS. The two quoted strings below are
     the corpus shapes this decision reasons ABOUT — a false negative the fix had to
     close, and a true positive the fix must preserve. Both are deliberately quoted
     verbatim so the boundary is checkable; neither is a step anyone performs here.
     Removing this region makes the ADR flag under its own sentinel, which is the
     guard behaving correctly. -->
**Option A is not free either, and the same asymmetry applies to it.** Neutralization
deletes a token, so any imperative that lives ONLY inside a `*.yml` filename is deleted
with it — "you ssh in and run the `cryptsetup-unlock-workspaces.yml` playbook by hand"
loses its only imperative and goes silent. That is the false-negative mirror of the defect
being fixed, and it lands on runbooks. Review caught it; the mitigation is
`STRONG_ACTOR_RE`: a line carrying an unambiguous human-agency signal (`by hand`,
`manually`, `yourself`, `your laptop`, `ssh into`, `<role> runs`) is scanned RAW, so a
filename can still supply its imperative. Bare `operator`/`you`/`founder` are excluded —
those weak mentions are what the #6771 false positive is made of, and including them would
re-open it. Measured cost at production scan scope: **zero** (identical flagged set to
neutralization-alone; its one corpus hit is under `/archive/`, already excluded).

**The `.yml`/`.yaml` boundary is a deliberate choice, not an oversight.** The neutralization
does not extend to `.sh`, `.service`, `.tf`, `.md`, or `.ts`, and the extensions are not
equivalent: a shell script is something a human *can* run, so "the operator runs
`reboot-hosts.sh`" is a true positive that must keep flagging. Only extensions that are
CI-by-construction (or pure citations) qualify. Two corpus lines currently exhibit the same
word-boundary defect via `.ts` and `.md` filenames; widening to citation extensions is
tracked separately rather than folded in here, because each candidate extension needs its
own true-positive/false-positive measurement.
<!-- lint-infra-ignore end -->

## Consequences

**Easier.** Prose documenting a CI-driven apply, or citing any `*.yml`/`*.yaml` workflow
name beside an actor word, no longer trips the gate — including `destroy-*.yml` and
`reboot-*.yml` style names that match a bare imperative. The carve-out that PR #6749 added
for this exact defect is removed, restoring detection in that region.

**Harder.** ~41 `-target … apply` false positives remain latent in the corpus. CI runs
`--changed`, so they bite only when a doc near one is edited. Their residual structure is
two clean classes — negation context ("no operator apply", "Operator steps | none") and
possessive/non-infra actors ("the operator's value") — tracked in issue #6806. Suppressing
those classes is the correct next step; weakening an imperative is not.

**Binding fixture rule.** Positive controls for this sentinel MUST include at least one
phrasing that contains **no tool token**. The tool anchor survived a 38-case suite and a
six-mutation battery precisely because every positive control contained the literal word
"terraform"; the suite could not see that the sentinel had lost its teeth for the phrasing
humans actually write. Test case F9 in `scripts/lint-infra-no-human-steps.test.sh` now
lifts a tool-token-free human step verbatim from the cutover runbook and is
mutation-verified to go RED if the anchor returns. Any future change to the imperative set
must keep it RED-able.

**Process consequence.** The plan inverted the issue author's stated preference order on
the strength of a single unvalidated number, and that number came from a scan whose
baseline was computed on a different tree than its comparison arm. Plan-quoted
measurements are preconditions to re-derive, not facts — and a count of "false positives"
is a *classification claim* that requires reading the population, not just differencing
two totals.

## Cost Impacts

None. No vendor, tier, or infrastructure change; the fix is a CI lint script edit. Runtime
cost is neutral — measured at 1.06× baseline on an in-process A/B benchmark (min-of-5,
interleaved arms), within the plan's 1.25× budget.

## NFR Impacts

None — no NFR in `knowledge-base/engineering/architecture/nfr-register.md` moves tier. The
decision preserves the existing detection sensitivity of a CI gate rather than changing a
system quality attribute.

## Principle Alignment

- **AP-007 (Exhaust automation before manual steps): Aligned** — this sentinel is the
  mechanical enforcement of AP-007, and the decision preserves its ability to detect a
  human step. Option B would have weakened AP-007 enforcement for the most common phrasing.
- **AP-002 (No SSH state mutation): Aligned** — the same sentinel covers SSH-actor
  imperatives; that half is untouched.
- **AP-011 (ADRs for architecture decisions): Aligned** — this record exists because the
  ruling is a durable detection-semantics decision a future author would otherwise
  re-litigate from the same "consistency" intuition.
