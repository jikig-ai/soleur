---
title: "Fixture-operand scanner P1b, P1a baseline burn-down, gdpr-gate staleness instrument, net-issue-flow FILED blind spot"
date: 2026-09-03
slug: fix-fixture-operand-and-flow-gates
branch: feat-one-shot-7708-7709-7710-7759-fixture-and-flow-gates
issue: 7708
closes: [7708, 7709, 7710, 7759]
type: fix
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
---

## Overview

Four test-gate and compliance-gate repairs, all filed as deferred scope by the fixture-operand-guard
work that merged 2026-08-31. They ship as four pull requests, one per issue, for
reasons the Implementation Phases section derives from measurement rather than from the issue count.

Two concern the fixture-operand scanner. One burns down the grandfathered site list the first rule
family landed with; the other adds a second rule family covering relative operands and the non-git
verb families, whose empty-operand behaviour differs per verb and must therefore be stated as
separate properties rather than one. They were expected to conflict over a shared baseline; measured,
they do not share one, and the real coupling runs the other way — which inverts their order.

The remaining two are independent gate repairs that share a property rather than a subsystem: in each,
the broken state and the healthy state produce the same output. A compliance gate emits only staleness
banners on a clean scan, so "scanned, found nothing" reads identically to "did not scan" — which is
how it was reported as refusing to run. A blocking net-issue-flow gate matches only filings that cite
the pull request, so a filing citing the originating issue is invisible and a net-positive change
passes silently.

*Note: no `spec.md` exists for this branch, so `lane:` defaults to `cross-domain` fail-closed rather
than being carried forward.*

## Enhancement Summary

**Deepened:** 2026-09-03. **Reviewers:** engineering and legal domain leads; DHH, code-simplicity,
architecture-strategist and spec-flow panels. The strict-convention reviewer did not return before
this pass closed — its lens was factual-claim verification and acceptance-criteria failure classes,
both of which the architecture and spec-flow passes independently covered, and every factual claim it
would have checked was verified by at least two other readers.

### What review and deepening changed

1. **Four pull requests, not two.** #7708 carried no site count, and measuring it (roughly 3,700
   candidate lines across 400 files, against P1a's 167 across 32) showed it hides a second burn-down.
   Splitting #7710 from #7759 followed separately: they share a property, not a file, a call graph or
   a reviewer.
2. **The order inverted.** The two scanner issues were expected to contend over a shared baseline.
   They do not share one; the coupling runs the other way, so burning P1a down first makes P1b's
   starting baseline smaller.
3. **A new CI gate was designed, then deleted.** `vendor-pin-verify.yml` already runs on the NOTICE
   path and already invokes the check being strengthened, so the enforcement follows from fixing that
   check rather than from new machinery.
4. **The conservation check became report-only** — closed issue numbers are cited routinely for
   unrelated reasons, and making an unmeasured heuristic the second blocking signal in a script whose
   every other failure path is fail-open risks wedging ordinary merges.
5. **A near-miss caught by review:** emitting conservation rows into the existing row stream would
   have silently made that report-only check blocking, because the consumer increments the blocking
   count once per row before reading any verdict. Every reporting and telemetry assertion would have
   passed over it.
6. **A near-miss caught by deepening:** isolating the new predicate in its own jq pass — the obvious
   way to get that isolation — would roughly double the runtime of a gate that has a timeout
   post-mortem. The isolation belongs in the consumer, not in a second pass.

### What measurement changed about the issues themselves

- #7709's live count is 167, not the 160 in its body; the difference is a detector widening, not new
  offending code.
- #7710's core claim is false: the gate does not refuse before scanning. It scans and exits 0. The
  real defect is that a clean scan emits only staleness banners, so success and failure are the same
  bytes.
- #7710's corpus is not stale. All eight lifted files are byte-identical to their pins; only the
  attestation is old.
- Three vendored files were never pinned in the canonical record, so the integrity guard covers five
  of eight — and the same wrong count is mirrored in `compliance-posture.md`.
- The mandated-filing exemption this plan initially claimed does not apply: the corpus contains one
  rule id, and it is not the deferral rule.
- 23 of the 32 burn-down holders cannot reach `assert_fixture_dir`, so the behaviour-changing remedies
  are the default rather than the fallback — the inverse of the plan's first draft.

## Research Insights

### Premise Validation (Phase 0.6)

All four issues are OPEN and none is closed by a merged pull request. Every artifact each one cites
was resolved against the working tree before planning began. Three premises did not survive contact.

**#7708 — holds.** `plugins/soleur/test/lib/fixture-scan.py` exists and carries the corpus walk
(`tracked_shell_files`, over `git ls-files` for `*.sh`), the heredoc skipping (`heredoc_lines`) and
the binding-form resolution (`_binding_of`) the issue describes. It has exactly two rule functions
today, `scan_cd` and `scan_operand`, so "a third `scan_*`" is accurate. The issue's claim that the
canonical `assert_fixture_dir` already rejects relative operands also holds — its `case` statement
carries an explicit `*)` arm printing `is RELATIVE; refusing`.

**#7709 — the live number is 167, and the title is the current one.** The baseline is not one row per
site; it is 32 rows of `<count>` and `<path>` separated by a tab, and the site total is their sum.
Measured live: `SITES=167` across `FILES=914` scanned. The issue title (167) is current; the issue
body (160) is stale. The baseline's own header records why: a deliberate `160 -> 167` regeneration on
2026-08-27 caused by widening the *detector* — comment skipping, guard-to-operand correlation, and
the addition of `merge`/`switch`/`restore` to the write-verb list — not by new offending code. The
body's "largest holders" list is stale in the same way: `ship-unpushed-commits-gate.test.sh` is 19,
not 23, and the list omits `context-reviewed-gate.test.sh` (12) and `pencil-collapse-guard.test.sh` (10).

**#7710 — the central factual claim is false, and the path is wrong.** The script is at
`plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh`, not `scripts/gdpr-gate.sh`. It does not
"refuse before scanning anything": measured, it prints the staleness banner, prints `POSTURE_FAIL`,
**then** evaluates its `CANONICAL_REGEX` against the supplied paths, then exits 0. Run against a
matching path it returns the regulated-path line normally. `SKILL.md` states the contract plainly —
"Gate exits 0 in all paths; the staleness signal is advisory" — and both test suites pin that exit
code. So "no diff is actually scanned" is not what is happening.

What *is* happening is described better by the issue's closing argument than by its opening one. On a
scan that matches nothing, the two staleness banners are the **only** output — there is no line
saying the scan ran. So "scanned, matched nothing" and "did not scan" are byte-identical, which is
exactly how this was read as a refusal. That indistinguishability is the real defect, and it is the
one the issue itself names as the reason to fix rather than to widen the window.

**#7710, second premise — "108 days stale" is true about the date and misleading about the rules.**
The live reading is now 116 days. But the lifted rule files were compared against upstream directly:
each pinned `upstream-blob-sha` was checked against the current content SHA at its upstream path in
`goSprinto/compliance-skills`. **Zero of eight have drifted.** The upstream repository HEAD has moved
past the pinned commit (`0594a9ef` against pinned `7b58d684`, pushed 2026-05-26) and the repository is
not archived, but every file this gate actually uses is byte-identical to its pin. The corpus is not
stale; only its attestation is. The gate is reporting a healthy corpus as degraded, which is the
mechanism that trains a reader to ignore it.

**#7710, third premise — the canonical record is incomplete, and this was not tracked anywhere.**
Raised by the compliance review and then verified independently. `content-vendoring.md` §2 states that
the NOTICE frontmatter is the canonical machine-readable form and that divergence from the body table
is a bug. Measured: the frontmatter pins **5** `lifted-files` entries, while the body table carries
**8** vendored rows. The three vendored files with no canonical pin are
`references/layers/auth-sessions.md`, `references/layers/frontend.md` and
`references/layers/testing-seeding.md`. (`references/legal-consent.md` and
`references/non-negotiables.md` also appear in the table but are Soleur-authored and correctly carry
no upstream pin, so the gap is exactly three.) The consequence is that
`vendor-pin-integrity.sh`, which reads the frontmatter, guards only five of the eight vendored files —
three vendored compliance rule files carry no local-edit integrity guard at all. This makes the
frontmatter reconciliation a **precondition** to any freshness attestation, because a bump made
against a five-entry record would attest to a completeness that does not exist.

**#7759 — holds, and the fix surface is narrower than feared.** The script is at
`plugins/soleur/skills/ship/scripts/net-issue-flow.sh`. Its FILED predicate is a bare-`#N` body match
against the PR number only, bounded by `createdAt >= PR_CREATED_AT`. `CLOSING_NUMS` — the set option 2
would consume — is already computed in the same script from the PR body. The apparent second consumer,
`.claude/hooks/ship-net-issue-flow-gate.sh`, is not a reimplementation: it shells out to the gate and
translates the exit code, and its own header says so. The fix therefore lands in exactly one file.

**ADR corpus check (proposed mechanism against rejected alternatives).**
`ADR-131-gate-moratorium-and-meta-work-budget.md` governs whether new gate work may proceed. It is
`status: proposed` and states in its own opening that it "decides nothing"; its Proposal 1 explicitly
permits that existing gates "may be fixed, tightened, merged, or deleted". The #7759 change is a fix
to an existing gate, so ADR-131 does not block it. The directly analogous prior change to this same
gate — the mandated-filing exemption — reached the same reading and produced no new ADR, which is the
precedent this plan follows.

### Property List (Phase 0.6b)

1. A relative or empty fixture-directory operand reaching a destructive verb in a tracked `*.sh` file
   is detected, with the detection stated per verb family rather than collapsed into one property.
2. The P1a grandfathered site list decreases only alongside the remediation that earned it, toward zero.
3. The gdpr-gate's output distinguishes "the gate scanned and matched nothing" from "the gate did not scan".
4. The gdpr-gate's staleness claim is true — it does not report a corpus as stale while that corpus is
   provably identical to its pin, and it does not attest over an incomplete record.
5. A net-issue-flow filing that cites the originating issue rather than the PR is not silently
   invisible to the blocking gate.

### Cut List (Phase 0.6b)

| Mechanism proposed | Property it would buy | Disposition |
|---|---|---|
| Widen `OPERAND_WRITE` / `scan_operand` to absorb the new verbs | 1 | **Cut.** Grepped the authority (`fixture-scan.py`): each rule function holds its own verb regex. Widening the P1a rule would move P1a's live counts while property 2 is mid-burn-down, and would collapse three measured behaviours into one claim the issue explicitly forbids. |
| A single baseline shared across both rules | 1, 2 | **Cut.** Shrink-only semantics are per-rule: one file's P1a count and its P1b count move independently, and a shared baseline could not express that. Two baseline *files* are genuinely required, and that separation is also what makes cross-perturbation impossible. |
| Copying the harness — the compare, regenerate and floor machinery — into the P1b suite | 1, 2 | **Cut, and this reverses an earlier draft.** That draft called a second copy "structurally forced" because `BASELINE` is a hardcoded `$SCRIPT_DIR`-relative literal. That describes today's harness, not a constraint: what must differ between the suites is the *fixture corpus*, since the verb families differ, and what must not be duplicated is the compare/regenerate/floor logic. Extract that into a shared helper both suites call, parameterised by rule and baseline path. Two rule families is the point at which that extraction is cheap and the second copy is not yet entrenched. |
| Re-vendor the rule corpus from upstream | 4 | **Cut on measurement.** 0 of 8 lifted files drifted. There is no content to refresh; the mechanism that buys property 4 is an attestation, not a re-lift. |
| Raise or replace the 30d/90d staleness thresholds | 4 | **Cut.** `content-vendoring.md` §7 makes the thresholds design parameters requiring an ADR to change, and the issue itself rejects widening the window as the fix. It would also buy nothing toward property 3. |
| Relevance-gate the staleness banner to matched paths | 3 | **Cut.** `2026-05-11-runtime-advisory-banners-must-gate-on-judgment-relevance.md` classifies a persistent-state staleness banner as *correctly* unconditional, contrasting it with the per-judgment operator-attested banner. Adopting per-judgment gating here would implement a mechanism that learning explicitly rejects. |
| Emit `Source: PR #<n>` at filing time, as the primary fix | 5 | **Cut as primary, retained as a complement.** Grepped the producers: `review.workflow.js` already emits `**Source:** PR #<n>`; `brainstorm/SKILL.md` files citing a parent *issue* at a point when no PR exists to cite. Option 1 alone therefore cannot buy property 5 — it leaves brainstorm-time and pre-existing filings invisible, and silently so. |
| Widen the FILED selector to also match `CLOSING_NUMS` | 5 | **Cut as primary.** Buys the property, but silently changes a blocking count and carries the cross-attribution risk the issue names — a sibling PR's filings counted against this one. |
| Mirror the fix into `.claude/hooks/ship-net-issue-flow-gate.sh` | 5 | **Cut on measurement.** The hook delegates via `bash "$GATE"` and re-implements no query logic; its own header says so. |

### Measured verb behaviour (the input to #7708's rule table)

Every row below was executed in a throwaway git repository rather than reasoned about. The first probe
was discarded and re-run because a trailing `| head` had captured the pipeline's exit status instead
of the verb's; these are the corrected readings.

| Verb form | Empty operand | Relative operand |
|---|---|---|
| `git -C "$X" <write>` | rc=0, resolves to the caller's working directory — **widens** | resolves against the caller's working directory — widens |
| `rm -rf "$X"` | rc=0, silent no-op | rc=0, **deletes under the caller's working directory** |
| `mv a "$X"` | rc=1, fails loudly | not applicable — a relative destination is a normal, legitimate form |
| `cp -r a "$X"` | rc=1, fails loudly | as above |
| `: > "$X/f"` | resolves to `/f` at the **filesystem root**; rc=1 unprivileged, would write with sufficient privilege | rc=0, writes under the caller's working directory |

Two refinements over the table in #7708. First, `cp -r a ""` fails loudly exactly as `mv a ""` does,
so grouping those two is correct. Second, the redirection family is a *third* behaviour the issue does
not name: an empty `$X` in `"$X/f"` anchors the write at the filesystem root rather than no-op'ing or
erroring, so its severity is a function of privilege rather than of the verb. The rule must therefore
state three behaviours, not two.

### Applicable institutional learnings

- `knowledge-base/project/learnings/2026-08-27-i-committed-the-defect-class-i-was-closing-eleven-times.md`
  — the direct lineage of this scanner. A shrink-only baseline catches growth only and is structurally
  blind to narrowing (cutting the verb list, reverting the corpus glob). A new guard needs a named
  member at its exact count, one fixture per member, never a sample or a total.
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
  — for every guard, name the cheapest green-preserving edit that breaks its stated property; if none
  can be constructed, the guard is not understood.
- `knowledge-base/project/learnings/2026-08-04-a-count-framed-ratchet-cannot-see-a-rename.md`
  — a count-only ratchet is blind to permutation. Bears directly on the burn-down: identities may
  change while the count falls. A deliberate retirement is an explicit acknowledged entry, never a
  silent exemption.
- `knowledge-base/engineering/operations/post-mortems/net-issue-flow-gate-timeout-silent-passthrough-postmortem.md`
  — this gate's own prior incident. `[[ "$RC" -eq 1 ]] || exit 0` mapped both a timeout and a missing
  binary to a silent pass. A fail-open branch is worthless unless it cannot fire silently and emits
  telemetry under a discriminating rule id, with a control proving a clean pass emits none.
- `knowledge-base/project/learnings/2026-07-20-an-advisory-gate-is-not-a-weak-gate-it-is-no-gate-and-a-ratio-needs-its-denominator-checked.md`
  — the original diagnosis of this same FILED query, cataloguing four independently-measured
  under-matching defects. #7759 is a fifth of that family.
- `knowledge-base/project/learnings/2026-05-11-runtime-advisory-banners-must-gate-on-judgment-relevance.md`
  — distinguishes per-judgment banners (must scope to relevance) from persistent-state banners
  (correctly unconditional). Determines what the #7710 fix must *not* do.
- `knowledge-base/project/learnings/2026-08-13-the-fixture-shape-decided-what-the-assertion-could-possibly-catch.md`
  — a guard's sensitivity is bounded above by fixture variety, invisibly. Bears on designing P1b
  fixtures whose topology actually makes the two rules' outputs diverge.
- `knowledge-base/project/learnings/workflow-patterns/2026-05-29-net-issue-flow-gate-at-filing-site-not-just-ship.md`
  — a discipline that must hold for an action is enforced where the action is taken.
- `knowledge-base/engineering/policies/content-vendoring.md` — §2 (frontmatter is canonical), §7 (the
  30d/90d runtime staleness contract), §8 (the POSTURE_FAIL chain).

### Conventions carried from the constitution

Shell files take `#!/usr/bin/env bash` with `set -euo pipefail`; snake_case functions and locals,
SCREAMING_SNAKE_CASE globals; `[[ ]]` tests. Operator-protection signals — warning banners, posture
failures, staleness alerts — emit to **stdout, not stderr**, because agent runtimes swallow stderr;
the gate already honours this and the new scan-completion line must too. New source files require a
corresponding test file before shipping, in a `test/` sibling directory using `<module>.test.sh`
naming. An assertion verifying a mutation pins the exact post-state value rather than accepting either
side of it.

### Existing scanner test structure (the template for P1b's guard contract)

`fixture-dir-operand-assert.test.sh` is organised in lettered sections that together form the model a
P1b suite should follow: section E carries canonical RED fixtures per binding form; E2 enumerates one
synthetic fixture per verb phrase; E3 proves the four laundering paths (a commented-out assertion, an
unrelated `case`, an unrelated `[[ ]] || true`, an unrelated `mkdir || return 1`) still trip, so a
guard must correlate with the operand rather than merely appear nearby; F carries must-PASS
false-positive fixtures; G exercises the canonical `assert_fixture_dir` against empty, relative,
bare-slash and absolute operands; C, C2 and D hold the byte-equality drift arm; H is a harness
self-check proving the failure counter still increments. An anti-vacuity floor (`MIN_ASSERTIONS`,
currently 62) guards the whole file.

## Open Code-Review Overlap

**None.** Queried the 63 open `code-review` issues against every planned edit surface — the scanner
module, the P1a test and baseline, the gdpr-gate script and NOTICE, `vendor-pin-integrity.sh` and
`net-issue-flow.sh` — and additionally against all 32 files named in the P1a baseline, since the
burn-down edits every one of them. No open scope-out names any of these paths.

## Research Reconciliation — Issue Claims vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| #7709: baseline holds "160 sites" (body) / "167" (title) | Measured live: **167** sites, 32 files, 914 files walked. The header records the deliberate `160 -> 167` detector-widening regeneration of 2026-08-27. | Plan targets 167. Report 167 as current in the PR body and say why the two numbers differ, so the next reader does not re-litigate it. |
| #7709: largest holder is `ship-unpushed-commits-gate.test.sh` at 23 | Live count is **19**. The list also omits `context-reviewed-gate.test.sh` (12) and `pencil-collapse-guard.test.sh` (10). | Sequence the burn-down from the live baseline, never from the issue body. |
| #7710: script lives at `scripts/gdpr-gate.sh` | It is at `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh`. | Use the real path throughout. |
| #7710: "refuses before scanning anything", so "no diff is scanned" | **False.** Measured: banners print, then the `CANONICAL_REGEX` scan runs, then `exit 0`. A matching path returns its regulated-path line normally. | Re-aim the fix at the defect that is actually present — the absence of a positive scan-completion signal, which is what made a healthy run look like a refusal. |
| #7710: the rule corpus is 108 days stale | The *attestation* is 116 days old; the *rules* are current. 0 of 8 lifted files differ from their pins. | Do not re-vendor. Re-verify by measurement and bump the attestation on that evidence. |
| #7710 (unstated): the NOTICE record is complete | The canonical frontmatter pins **5** of the **8** vendored files. `auth-sessions.md`, `frontend.md` and `testing-seeding.md` have no canonical pin, so the integrity guard covers five of eight. | Reconcile the frontmatter as a precondition to the attestation bump. |
| #7759: the fix may need to land in the hook as well | `.claude/hooks/ship-net-issue-flow-gate.sh` delegates via `bash "$GATE"` and re-implements no query logic. | Single-site fix in `net-issue-flow.sh`. |
| Brief: #7708 and #7709 conflict because they share the baseline | They do **not** share a baseline — the P1a test hardcodes its own path, so P1b structurally requires a second test file and a second baseline. The real coupling runs the other way: `assert_fixture_dir` satisfies both rules, so the burn-down shrinks **both** baselines. | Invert the order. Burn down P1a first, then measure P1b's initial baseline against the already-cleaned tree, so P1b starts smaller and is never regenerated downward by unrelated work. |

## User-Brand Impact

**If this lands broken, the user experiences:** a test-suite guard that reports a clean baseline while
destructive fixture operands remain in the corpus — meaning a future test run can delete or rewrite
files inside the user's own working repository rather than inside a throwaway fixture directory. The
concrete artifact is the user's checked-out worktree, mutated by a test they ran.

**If this leaks, the user's workflow is exposed via:** no new exposure vector. Nothing here reads,
writes, or transmits user data; the compliance-gate arm changes only how a local advisory tool
describes its own rule freshness, and the vendored content it attests to is public MIT-licensed text.

**Brand-survival threshold:** aggregate pattern.

The scanner arm is a guard over test fixtures — a defect degrades a safety net rather than exposing a
user. The gate arms change gate reporting, not product behaviour. No single-user incident is
reachable from this diff, so no per-PR sign-off is added; the section is present because every plan
carries one.

## Implementation Phases

The four issues ship as **four pull requests**, one each. The split follows review surface and blast
radius, not the issue count — it just happens to land on one-per-issue.

An earlier draft bundled #7710 and #7759 on the grounds that both are gates whose failing output
resembles their passing output. That is a true observation and a bad reason to share a pull request:
they have no file, no call graph and no reviewer in common, and bundling them would have asked one
reviewer to context-switch between vendored-content attestation semantics and issue-citation
heuristics inside a single diff. The shared property is worth stating in the overview; it is not an
engineering coupling, and it is not load-bearing for how the work lands.

The brief anticipated two, and the third is the consequence of a measurement the issues did not carry.
`hr-write-boundary-sentinel-sweep-all-write-sites` requires enumerating the write sites before sizing a
new guard, and #7708's body carries no site count at all. Measured: the P1b verb families produce
roughly **3,700 candidate lines across 400 files** before guard correlation, against P1a's 167 across
32. The redirection family alone contributes about 2,300. Binding-form resolution and guard correlation
will knock that down substantially — that is exactly how P1a reached 167 from a far larger raw surface
— but the residue is very unlikely to be small enough to burn down in the same change that introduces
the detector. Bundling #7708 with #7709 would therefore have hidden a second, larger burn-down inside a
pull request already carrying a 32-file sweep.

So #7708 ships the **detector plus a grandfathering shrink-only baseline**, and its burn-down is filed
as its own issue. That is precisely the pattern #7652 followed when it landed P1a and filed #7709, and
following it here keeps the ratchet working from day one instead of waiting on a burn-down.

The order is also inverted relative to the brief's sequencing note. The two issues do not share a
baseline — the P1a test hardcodes its own path, so P1b structurally requires a second test file and a
second baseline, and cannot perturb P1a's counts. The real coupling runs the other way:
`assert_fixture_dir` satisfies both rules, so burning down P1a first means P1b's initial baseline is
measured against an already-cleaned tree and starts smaller.

### PR 1 — burn down the P1a baseline (#7709)

**Phase 1.1 — Establish the measured starting point.**
Record `SITES` and `FILES` from `python3 plugins/soleur/test/lib/fixture-scan.py --rule operand --repo .`
before any edit, and confirm the baseline sum equals it. This is the number the burn-down is measured
against and it belongs in the PR body.

**Phase 1.2 — Burn down the P1a baseline (#7709).**
Work holder-by-holder in descending count so each commit is reviewable and the ratchet is exercised
repeatedly rather than once. Per site, apply exactly one of the three canonical remedies: an
`assert_fixture_dir "$X"` call after the binding; `|| return 1` or `|| exit` on a `$(mktemp -d)`-style
capture; or `${X:?}` at the binding. Choose by binding form — the scanner already reports it
(`positional`, `positional-at-use`, `command-substitution`, `read-process-substitution`), so the
remedy is a lookup rather than a judgement.

Regenerate with `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh --write-baseline` and
commit each shrink **in the same commit as the source edits that earned it**. A commit whose baseline
falls while no source file changed is the ratchet violation the issue names, and it must not appear
anywhere in this branch's history — not merely in its final state.

Any site that genuinely cannot take an assertion — for instance a test whose subject *is* relativity,
so a guard would defeat the test — gets an explicit acknowledged entry recording the file, the reason,
and the re-evaluation trigger. It never gets a silent count adjustment.

**Phase 1.2ᐧ0 — Availability decides the remedy far more often than binding form does.**
Measured across the 32 holders: **4** carry an inline copy of `assert_fixture_dir`, **5** source or
already reference it, and **23 cannot reach it at all**. So the guidance to prefer the additive remedy
"wherever the binding form allows" describes a minority of the work. For roughly seven sites in ten the
real question is availability, and the honest answer is that the two control-flow remedies — the ones
that change behaviour — are the default rather than the fallback. This is the single largest cost and
risk driver in the burn-down and it is worth knowing before the first commit rather than at the tenth.

Three of those 23 are not test files at all: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`,
`scripts/context-reviewed-gate-discoverability.sh` and
`apps/web-platform/scripts/lint-migration-fk-preconditions.sh`. Several more are infra and hook
scripts. Giving a customer-shipping plugin script a dependency on a test helper is the wrong direction,
so "just source the helper everywhere" is not available as a blanket answer.

Decide per file, in this order:

- Already has the helper, inline or sourced (9 files) — use `assert_fixture_dir`.
- A test file that can reasonably source the helper — source it rather than copying it. Every inline
  copy widens the byte-equality drift arm's surface, and there are already four.
- A plugin script under `plugins/soleur/` — a shared bash primitive belongs in the plugin payload per
  ADR-178. Read that ADR before adding a dependency, and prefer `${X:?}` if it does not fit.
- Anything else — `${X:?}` at the binding, or `|| return 1` / `|| exit` on a capture, with the
  behaviour-change controls below applied in full.

**Phase 1.2a — Treat the remedies as behaviour changes, because two of them are.**
Only `assert_fixture_dir "$X"` is purely additive. `${X:?}` and `|| return 1` / `|| exit` both change
**control flow**: if any site can legitimately reach the guarded line with `$X` transiently empty on a
non-error path — a teardown helper that no-ops when the fixture was never created is the obvious shape
— the remedy converts a benign no-op into a hard abort. Nine of the 32 holders are `.claude/hooks/*`
and gate-test scripts, which is to say scripts that decide the verdict on *other* pull requests. A
mistake there does not fail loudly in this change; it silently moves another gate's verdict boundary
and surfaces weeks later on an unrelated pull request.

Controls, all of them cheap relative to that failure:

- Batch by file, not by pattern. Run that file's own suite green before moving to the next, rather
  than one sweep with a single run at the end.
- Prefer `assert_fixture_dir` wherever the binding form allows it; reach for the control-flow remedies
  only where it does not, and say per site why.
- For each `.claude/hooks/*.test.sh` and gate-test holder, exercise the underlying gate end to end
  with both a synthetic pass and a synthetic failure after the edit, confirming the inserted assertion
  did not shift the gate's own verdict boundary.
- Sequence the two largest holders (19 and 18 sites) first and review them separately — they carry the
  most behaviour-change surface.
- Finish by asserting the scanner's own count, not merely that the suite is green. A sweep that
  accidentally stubbed `assert_fixture_dir` into a no-op would also read green.

If that exercise does reveal a shifted verdict boundary — which is the outcome it exists to produce,
not an unexpected one — the escalation is ordered: try the purely additive remedy first if a
control-flow one was used; if the site cannot take any of the three, it becomes an acknowledged entry
with the observed shift recorded as its reason. What must not happen is reaching for a different
remedy until the exercise goes quiet, since that selects for the remedy whose damage this particular
exercise cannot see.

### PR 2 — add the P1b detector (#7708)

**Phase 2.1 — Prototype and measure before committing to a shape.**
Write the rule function, run it over the corpus, and record its live site and file counts. That number
is not known today and it decides the rest of this pull request.

**The threshold is the repo's existing one, not a fresh judgement.** `net-issue-flow.sh` already states
the canonical fix-inline-versus-file rule in its own remedy text — the cost-of-filing auto-flip at
**100 lines and 4 files**. That is the same decision in the same repo, so it governs here: a residue
that fits inside it is burned down in this pull request, and anything larger ships as a grandfathering
baseline with the burn-down filed. Naming a number matters more than which number it is — "small
enough" is a phrase that accommodates whatever was measured, and it would reintroduce exactly the
bundling this three-way split exists to prevent. The planning-time estimate says the grandfathering
branch is far more likely, but the scanner's output decides it, not the estimate.

**Phase 2.2 — Add the rule.**
Add a third rule function to `fixture-scan.py` alongside `scan_cd` and `scan_operand`, register its
`--rule` value in `main()`, and give it its own verb tables. State the three measured behaviours as
three families rather than one property:

- a **widening** family — `git -C` with a relative operand, `rm -rf` with a relative operand, and a
  redirection target under a relative directory — all of which resolve against the caller's live
  working directory;
- a **root-anchored** family — a redirection target of the form `"$X/f"` where `$X` is empty, which
  resolves to the filesystem root and whose severity is a function of privilege;
- a **loud-failure** family — `mv` and `cp -r` into an empty destination, which fail with a non-zero
  status and announce themselves. These are detected and reported at lower severity precisely because
  they are self-announcing; recording that distinction is the point of splitting the rule.

Note what the `git -C` arm actually adds, because it is narrower than the issue's phrasing suggests.
P1a already flags any `git -C` write whose operand is bound without an assertion, and it cannot tell
at scan time whether that operand would be empty or relative — so the remedy for both is the same one
site. What P1b adds for `git -C` is the case P1a deliberately skips: `_binding_of` returns nothing when
the nearest binding is a **literal**, so a literal-bound *relative* operand is invisible to P1a. That
is the residue, and it is the only `git -C` case P1b should claim.

Add a sibling test file with its own hardcoded baseline path, modelled on the existing suite's lettered
sections, and seed its baseline from the post-burn-down tree.

**Do not widen `OPERAND_WRITE` or `scan_operand`.** That is the one edit that would couple the two
rules and move the P1a counts. An acceptance criterion pins it.

**Phase 2.3 — File the P1b burn-down.**
Unless Phase 2.1 measured a residue small enough to clear in place, file the burn-down as its own
issue, carrying the measured count, the per-family split, and the largest holders — the same shape
#7709 was given.

This pull request is therefore net-neutral against the net-issue-flow gate rather than exempt, and the
distinction matters. An earlier draft of this plan claimed the filing would be covered by the
mandated-filing exemption because it carries `Mandated-By: wg-when-deferring-a-capability-create-a`.
That is **false**, and it was checked: the exemption's corpus is derived by piping `AGENTS.rules.md`
through `scripts/lint-rule-bodies.py --emit-mandating-ids`, and that corpus currently contains exactly
one id — `wg-block-pr-ready-on-undeferred-operator-steps`. The deferral rule is not in it, so no
exemption applies to any filing in this batch.

The gate passes anyway, on arithmetic rather than on exemption, and each pull request's budget is
therefore fixed:

| Pull request | Closes | Files | Net |
|---|---|---|---|
| PR 1 | #7709 | none | −1 |
| PR 2 | #7708 | the P1b burn-down | 0 |
| PR 3 | #7710 | the §8-enforcement issue | 0 |
| PR 4 | #7759 | the blocking-promotion issue | 0 |

PR 2, PR 3 and PR 4 each sit exactly at the threshold, which blocks at net above zero. Neither has room for an
additional filing. Any further deferral discovered during implementation must therefore either be
folded in, or land with the documented override and a justification — it cannot simply be filed.

### PR 3 — the gdpr-gate freshness instrument (#7710)

These share a property rather than a subsystem: in both, the failing output is indistinguishable from
the passing output, which is why each was mis-read rather than fixed.

**Phase 3.1 — Reconcile the NOTICE canonical record (precondition).**
Add frontmatter `lifted-files` entries for `references/layers/auth-sessions.md`,
`references/layers/frontend.md` and `references/layers/testing-seeding.md`, each carrying the
`upstream-path`, the `upstream-blob-sha` already recorded in the body table, a `local-blob-sha`
computed with `git hash-object --no-filters`, and a `status`. This closes an integrity gap in which
three vendored files carried no guard, and it is what makes the completeness of any later attestation
true rather than assumed.

**Phase 3.2 — Strengthen the pin check that already runs.**
`vendor-pin-integrity.sh --verify-upstream` asserts that each pinned blob still resolves as an object,
which is a weaker statement than it appears: a blob resolves forever, so the check passes indefinitely
after upstream has replaced the file at that path. Strengthen it to compare each pinned
`upstream-blob-sha` against the *current* content SHA at its upstream path, reporting per-file `SAME`
or `DRIFTED` plus a total.

This is a fix to an existing gate rather than a new mechanism, and it is aimed at that gate's own
stated threat model: the workflow header describes it as closing "the NOTICE co-edit bypass", and a
check that cannot tell a current blob from a superseded one only half closes it.

**It has a twin, and the two must not diverge.** `cron-content-vendor-drift.ts` already performs this
same comparison weekly — it fetches each pinned path's current content SHA and compares it against the
NOTICE pin. The two exist on genuinely different surfaces: the cron runs on a schedule and can open a
pull request, while this check runs at pull-request time and can fail one, and neither can do the
other's job. But they are answering the identical question in two languages, and two implementations of
"is this blob still current" will eventually disagree. So the strengthened check must issue the **same
API call shape** the cron issues, and a comment in each must name the other as its twin. If a future
change makes one of them smarter, that comment is what tells the next reader the other needs the same
edit.

**Phase 3.3 — Bump the attestation, on a measurement CI already performs.**
The concern this phase originally answered is real: a locally-run tool plus a hand-edited date is
evidence-backed exactly once, and nothing in that arrangement stops the next change from citing the
tool without re-running it. `content-vendoring.md` §6 routes canonical bumps through the automated
pipeline for that reason, and #7255 means the anti-backdating binding is not currently operating.

The plan's first answer was to add a CI step enforcing that `last-verified` may not move without a
fresh comparison. That step is **cut** — not because the property is unwanted, but because the repo
already has the surface that provides it. `.github/workflows/vendor-pin-verify.yml` runs on
`pull_request`, carries a path filter that includes the NOTICE itself, holds a token, and already
invokes `vendor-pin-integrity.sh --verify-upstream`. So any change that edits `last-verified`
**already** triggers that workflow, and the Phase 3.2 strengthening therefore makes every future bump
CI-verified with no new job, no new step, and no new convention to remember.

That is the whole enforcement mechanism: fix the check that already guards this file, and the guarantee
follows. Building a second, bespoke gate beside it would have added machinery to obtain a property the
existing gate was one predicate away from providing.

So: land Phase 3.2, confirm the strengthened check passes on this change, then bump `last-verified`
with the per-file output recorded in the commit message.

If the comparison reports drift, the bump is not available. "Stop" is not a sufficient instruction
though, because it leaves the rest of a ready pull request with nowhere to go, so the branch is
defined: **PR 3 still ships Phases 3.1, 3.2, 3.4 and 3.5** — the frontmatter reconciliation, the
strengthened check, the posture row and the scan-completion line are all correct and useful whether or
not the corpus drifted, and the strengthened check is precisely what *detected* the drift. Only the
`last-verified` bump is withheld.

In that branch #7710 still closes, because the defect it names is the indistinguishable output, and
that is fixed. The re-vendor becomes its own issue carrying the measured drift, routed through
`content-vendoring.md` §6. The Phase 3.4 posture row then records the drift and the routing as its
resolution rather than the attestation, and the premise that both domain reviews signed off against —
that the corpus is current — is recorded as falsified rather than quietly dropped.

Note the arithmetic: that extra filing would take PR 3 to net-positive. Fold the re-vendor issue's
filing into the same body accounting, or carry the documented override with a justification.

The zero-drift result recorded above was measured during planning and must be re-measured at the moment
of the bump rather than assumed to have held.

Word nothing in this change as resolving #7255. That issue asks for a freshness signal the attesting
session does not control, and a CI-enforced comparison is a strong candidate to *become* that signal but
is not yet wired as one. Leave #7255 open, and note the candidacy there.

**Phase 3.4 — Record the posture gap, and fix the third copy of the count.**
The `POSTURE_FAIL` operator chain in `content-vendoring.md` §8 was never run across the 116-day window,
because nothing forces it — the gate is advisory and exits 0. Append a row to the
`## Active Compliance Items` table in `knowledge-base/legal/compliance-posture.md` recording the
window, that the chain did not run, why, and the resolution. Follow the row schema documented in that
section's own comment; note it states the gate never writes there directly, so this is an
acknowledged write, not an automated one. A late row is materially better than a silent gap for
anyone auditing this later.

**The same file carries the incomplete count, in a second place nobody has been looking.** Its
`## Vendored Code Provenance` table has a row reading `Lifted Files: 5 (gdpr-gate references/)` and
`Last Verified: 2026-05-10`. So the five-of-eight discrepancy is not confined to the NOTICE — it is
mirrored in the compliance document that an auditor would read first, and it is the artifact furthest
from the code. Correct that row to eight in the same change as the frontmatter reconciliation, and
move its `Last Verified` in lockstep with the NOTICE bump. Three artifacts carry this state — the
NOTICE frontmatter, the NOTICE body table, and this row — and only the body table is currently right.

That §8 has no mechanical enforcement is a real finding but a separate one; it is filed, not fixed here.

**Phase 3.5 — Make the gdpr-gate scan self-reporting.**
Emit a line, unconditionally and on stdout, stating that the path scan ran and how many paths it
examined and matched. This is the fix for the defect actually present: today a clean scan produces only
the staleness banners, so "scanned, matched nothing" and "did not scan" are the same bytes.

Leave the 30d and 90d thresholds untouched, keep the `exit 0` advisory contract, and do not
relevance-gate the staleness banners — they report persistent gate state and are correctly
unconditional. Extend the self-test to assert the new line in both the matched and unmatched cases.

**Two constraints on the line's wording and destination, both measured rather than assumed.**
`gdpr-gate.test.ts` carries three negative assertions, and an unconditional new line runs into two of
them: it asserts `stdout` does **not** match `/days stale/` on a fresh NOTICE, and that `stderr` does
not either. So the new line must not contain the substring `days stale` — a natural phrasing like
"scan complete; rules N days stale" would turn a passing suite red for a reason that has nothing to do
with the change. And it must go to **stdout**, which the constitution requires of operator-protection
signals anyway because agent runtimes swallow stderr, and which the third negative assertion
independently pins.

### PR 4 — the net-issue-flow FILED blind spot (#7759)

**Phase 4.1 — Add the conservation check, on a channel of its own.**
Keep the existing FILED predicate exactly as it is: it is narrow and high-precision, and the header
records four measured defects that argue against loosening it casually. Add a second set — issues
created after the PR that cite a number in `CLOSING_NUMS` but do not cite the PR — and:

- name them in the always-emitted block under their own label, with their issue numbers enumerated;
- emit telemetry under a rule id distinct from the existing ones, so "never fired" stays
  distinguishable from "fires every run";
- **report without blocking, in this first cycle.**

**The new set must not share the existing row stream, and this is the sharpest hazard in the batch.**
An earlier draft said "computed in the same jq pass", which reads as an efficiency win and is a trap.
The bash consumer is `FILED=$((FILED + 1))` executed once per row read, **before** any verdict is
examined — only the `exempt` verdict is later subtracted. So every row appearing in `GATE_ROWS`
increments `FILED`, and `NET = FILED - EXEMPT - CLOSING` is the blocking signal. Emitting conservation
findings into that stream would therefore raise `NET` by one per finding and block the pull request —
silently converting the report-only design into a blocking one, which is the precise opposite of the
decision taken above and defended at length.

So the conservation set is emitted on a structurally separate channel — a distinct output consumed by
its own loop that never touches `FILED`, `EXEMPT` or `NET`.

**Separate channel, but not a second jq pass**, and the distinction is load-bearing in the other
direction. The obvious way to isolate a predicate is to run it in its own `jq` invocation, and that
would be wrong here: the existing pass is documented as costing roughly a second over a ~2 MB payload,
the gate already runs in the several-second range, and it sits behind a hook timeout whose expiry this
gate has a post-mortem about — a silent pass at `rc=124`. Doubling the jq work to gain isolation would
buy a correctness property with an availability regression, in the one gate whose failure history is
precisely that.

Keep the single pass and emit a structured result instead — the two sets as sibling keys, or rows
tagged with which set they belong to — and route them to different loops on the bash side. The
arithmetic isolation, which is the actual hazard, lives in the consumer: the conservation rows must
never reach the loop that increments `FILED`. The residual shared-failure-domain risk is that a
malformed new predicate takes down the whole pass; that is bounded by adding the predicate as a
sibling filter over the same array rather than as a stage inside the FILED pipeline, and by the test
cases below.

Note the perf comment's actual claim before optimising against it: it warns off a *per-issue subprocess
loop*, measured at 1.7 seconds of fork overhead, not off a second invocation. One extra fork is not
what it prohibits — the runtime of a second full pass over the payload is the reason to avoid it.

An acceptance criterion pins the arithmetic directly: a pull request reproducing the measured #7702
shape must produce an identical `NET` before and after this phase lands. Reporting and telemetry
assertions alone cannot catch this — they would all pass while the count silently moved.

The non-blocking choice is deliberate and is a change from this plan's first draft. `CLOSING_NUMS` are
the issues the pull request closes, and post-PR issues cite those numbers constantly for entirely
ordinary reasons — "regression of #500", "see #500 for context". A heavily-cross-referenced foundational
issue would generate ambiguity flags on pull requests whose only distinguishing feature is that they
close it. Every failure path in this script today is fail-open except the single substantive `NET > 0`
signal; making a brand-new, structurally noisier heuristic the second blocking signal, with no measured
false-positive rate, risks wedging ordinary merges — and a gate that cries wolf is the exact failure
this batch is otherwise repairing.

Raise precision now rather than relying on the report alone: conjoin the machine-filed markers, so the
reported set is issues that carry a `Mandated-By:` line or the `deferred-scope-out` label. A person
writing "regression of #500" writes neither. That keeps the reported set close to genuine filings from
day one while the fire rate is being measured.

This still satisfies what the issue asks for. Its complaint is that the gate passes net-positive work
**silently**; naming the omission in the always-emitted block is what makes it self-reporting, which is
the property the issue names as option 3's advantage. Promotion to blocking is filed as its own issue
with a re-evaluation trigger — once enough pull requests have run the check for the telemetry to show a
real fire rate — rather than guessed at now.

Any new failure branch takes its own `_fail_open` rule id rather than reusing an existing one, so
"never fired" and "fails open every run" stay distinguishable. That distinction is the lesson of this
gate's own timeout post-mortem.

No producer is edited here. An earlier draft carried a "complementary" instruction to have filing
producers emit `Source: PR #<n>` where a pull request number is available — but the review producer
already emits it, the brainstorm producer has no pull request to cite, and no other producer was named
as a target. An instruction with no file behind it is prose, so it is cut rather than left to look like
scope.

Re-run `plugins/soleur/test/net-issue-flow.test.sh` — the script's own header requires it on any change
to the FILED query, and this adds a sibling query in the same pass.

## Files to Edit

**PR 1 (#7709)**

- `plugins/soleur/test/fixture-dir-operand-assert.baseline.txt` — regenerated, in the same commits as
  the source edits that earned each shrink.
- The 32 files named in that baseline. The five largest are
  `.claude/hooks/ship-unpushed-commits-gate.test.sh` (19),
  `plugins/soleur/test/worktree-manager-atomic-config.test.sh` (18),
  `plugins/soleur/test/resolve-git-root.test.sh` (12),
  `plugins/soleur/test/harvest-debt.test.sh` (12),
  `.claude/hooks/context-reviewed-gate.test.sh` (12).
  The authoritative list is the baseline file, not this plan — read it at implementation time rather
  than transcribing from here.

**PR 2 (#7708)**

- `plugins/soleur/test/lib/fixture-scan.py` — a third rule function, its acceptance in the
  rule-validation tuple in `main()`, and the module docstring, which currently states in prose that
  there are two rules. `OPERAND_WRITE` and `scan_operand` are not touched.
- `plugins/soleur/test/fixture-dir-operand-assert.test.sh` — only to move its compare, regenerate and
  floor logic into a shared helper both suites call. Its fixtures and its baseline path do not change.

**PR 3 (#7710)**

- `plugins/soleur/skills/gdpr-gate/NOTICE` — three missing frontmatter `lifted-files` entries, then
  the `last-verified` bump.
- `plugins/soleur/skills/gdpr-gate/scripts/vendor-pin-integrity.sh` — strengthen `--verify-upstream`
  from blob-resolvability to path-content currency.
- `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` — the scan-completion line.
- `plugins/soleur/test/gdpr-gate-self-test.test.sh` and `plugins/soleur/test/gdpr-gate.test.ts` —
  assertions for the new line in both matched and unmatched cases.
- `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts` — a comment only, naming
  the strengthened shell check as its twin so the two cannot drift apart unnoticed.
- `knowledge-base/legal/compliance-posture.md` — the retrospective row in `## Active Compliance Items`,
  **and** the `## Vendored Code Provenance` row, whose `Lifted Files` reads 5 and whose `Last Verified`
  reads 2026-05-10. Both move with the NOTICE.

**PR 4 (#7759)**

- `plugins/soleur/skills/ship/scripts/net-issue-flow.sh` — the conservation check, on its own output
  channel with its own consumption loop.
- `plugins/soleur/test/net-issue-flow.test.sh` — cases for the new set, the arithmetic-isolation case,
  and the assertion floor.

## Files to Create

- A P1b test file beside `fixture-dir-operand-assert.test.sh`, with its own baseline path.
- That test's shrink-only baseline file.
- A shared helper holding the baseline compare, regenerate and floor logic used by both suites.

No new CI workflow or step is created. `.github/workflows/vendor-pin-verify.yml` already runs on
`pull_request` with a path filter covering the NOTICE, already holds a token, and already invokes the
check being strengthened — so the enforcement follows from Phase 3.2 rather than from new machinery.

## Sequencing and Issue Closure

**Each pull request carries exactly one closing keyword set, and they are not interchangeable.** The
frontmatter's `closes:` list covers the whole branch, not any single pull request, and a bare
`Closes #N` auto-closes on merge from anywhere in a body. Lifting the four-issue frontmatter list into
the first pull request would therefore close #7708, #7710 and #7759 the moment PR 1 merged, months of
work before any of it shipped. So:

| Pull request | Body carries | And nothing else |
|---|---|---|
| PR 1 | `Closes #7709` | — |
| PR 2 | `Closes #7708` | — |
| PR 3 | `Closes #7710` | — |
| PR 4 | `Closes #7759` | — |

**Ordering.** PR 1 must merge before PR 2 begins, because Phase 2.1 measures the P1b residue against
the cleaned tree and a stacked branch would measure against a tree that review can still reshape. PR 3
and PR 4 depend on neither, and on nothing each other, so they may proceed in parallel with the
scanner work rather than waiting behind it.

**The net-issue-flow arithmetic depends on the closing line being present**, which is the second reason
the table above matters. PR 2 and PR 4 each file one issue and close one, landing at exactly the
blocking threshold. If the closing keyword is missing or malformed, or if the filed issue's body omits
a bare reference to its pull request, the count goes positive and the gate blocks — with the general
override as the only remaining route, which should not be reached by accident.

**#7708's closure is legitimate on detector-plus-baseline, and this was checked against the issue
rather than inferred from precedent.** Its body states the deliverable directly: a third rule function
"over the same machinery plus its own verb table **and its own shrink-only baseline**". A grandfathering
baseline is what the issue asks for, not a substitute for what it asks for. The burn-down it uncovers
is new scope the issue never claimed, which is why it is filed rather than absorbed.

## Guard Contract

Three guards ship here. Each matrix was derived from the property, not from finished code — that
ordering is the point, and it is why the matrices name mutations the current implementations do not yet
have anywhere to land.

### Guard 1 — the P1b detector and its shrink-only baseline

**Property.** Every call site in a tracked `*.sh` file where a fixture-directory variable reaches one of
the P1b verb families with a relative or empty operand, and where no guard correlated to *that variable*
intervenes between its binding and its use, is counted; and each file's count may only decrease.

**Assembly.** The chokepoint is the `--rule` dispatch in `main()` feeding the P1b rule function over the
corpus from `tracked_shell_files(repo, "*.sh")`. The assembly is structural, not a member list: it is
(corpus walk) × (verb-family regex) × (binding-form set in `_binding_of`) × (guard set in `_guard_res`).
There are therefore **four** places a member can be added or removed, and a matrix that exercises only
the verb regex would leave three unguarded.

**Mutation matrix.**

| # | Mutation | Must |
|---|---|---|
| 1 | Delete one verb family from the P1b verb regex | RED — a known holder's count falls with no source edit. Targets narrowing-blindness, which a shrink-only baseline is structurally unable to see on its own. |
| 2 | Add a second offending site to a file that already carries one correctly-asserted site | RED — that file exceeds its baseline. This is the "second member after a compliant first" row; a check that stops at the first member is itself the defect class. |
| 3 | Make the rule function return no rows at all | RED — the anti-vacuity floor must catch a scanner that reports zero and exits zero. This targets the guard's **own dispatch**. |
| 4 | **Move** an `assert_fixture_dir` call from before the use to after it, leaving the text present | RED — the site is unguarded during the window the property is about. A delete-only battery cannot distinguish this, because the guard text still appears in the file. |
| 5 | Narrow the corpus glob from `*.sh` to `*.test.sh` | RED against a `FILES` floor — files silently leave the walk. |
| 6 | Remove one binding form from `_binding_of` | RED — sites bound that way become invisible while every remaining assertion stays green. |

**Harness rows.**

- *Suite mutation that must RED:* neuter the failure counter so failures stop incrementing — the harness
  self-check must catch it. A matrix that only mutates the system under test cannot see a dead harness.
- *Must-PASS input that is not the canonical:* a site whose operand is absolute, bound from
  `$(mktemp -d)` and guarded with `|| return 1` — a different binding form and a different guard form
  from the canonical fixture, differing in ways the contract explicitly permits. RED rows alone cannot
  detect a guard that rejects everything; only a must-PASS row can.

### Guard 2 — the gdpr-gate scan-completion signal

**Property.** The gate's output always states whether the path scan executed and what it examined, so an
output carrying only staleness banners can never be read as a refusal to scan.

**Assembly.** The emit point after the `matched` loop in `gdpr-gate.sh`, and the assertion sets in
`gdpr-gate-self-test.test.sh` and `gdpr-gate.test.ts`. Both suites are members: an assertion added to
only one leaves the other free to drift.

**Mutation matrix.**

| # | Mutation | Must |
|---|---|---|
| 1 | Delete the scan-completion line | RED in both suites. |
| 2 | Fire the completion line only when at least one path matched | RED — this is a regression to exactly today's behaviour, and the property is about the zero-match case specifically. |
| 3 | Make the gate exit non-zero on `POSTURE_FAIL` | RED against the existing exit-0 assertions — proves the advisory contract is still pinned and was not quietly changed under cover of this fix. |
| 4 | Make the self-test's case runner execute zero cases | RED against the assertion floor. Targets the guard's own dispatch. |

**Harness rows.**

- *Suite mutation that must RED:* replace the assertion helper with a no-op; the floor must catch it.
- *Must-PASS input that is not the canonical:* a NOTICE dated 45 days ago — between the two thresholds.
  The 30-day banner fires, `POSTURE_FAIL` does not, the completion line is present, exit is 0.

### Guard 3 — the net-issue-flow conservation check

**Property.** Every issue created after the pull request that cites a number the pull request closes,
does not cite the pull request, and carries a machine-filing marker, is named in the always-emitted
block and counted in telemetry — never silently omitted.

**Assembly.** Two channels that must stay separate: the existing row stream feeding the
`FILED`/`EXEMPT`/`NET` consumption loop, and the new conservation channel with its own consumer.
Members are the FILED predicate, the conservation predicate, and `CLOSING_NUMS`. The chokepoint that
matters is not the jq program but the **bash loop**, because that is where a row becomes a count: it
increments `FILED` once per row before reading any verdict. The only external consumer is the
delegating hook, which translates the exit code and re-implements nothing.

**Mutation matrix.**

| # | Mutation | Must |
|---|---|---|
| 1 | Remove the conservation predicate | RED — the case reproducing PR #7702's measured shape (three issues citing the closed issue, none citing the PR) must stop being reported. |
| 2 | Add a second unattributed issue after a correctly-attributed first | Both reported — proves the check does not stop at the first member. |
| 3 | Report the set but drop the telemetry emit | RED — an unobservable report is the silent-omission shape this guard exists to end. |
| 4 | Make the jq pass return an empty array | The fail-open branch must emit its own distinctly-named row rather than reading as a clean pass. Targets the guard's own dispatch, and is the precise shape of this gate's prior timeout incident. |
| 5 | Drop the machine-filing marker conjunct | The false-positive control case (below) must start being reported, proving the precision conjunct is load-bearing rather than decorative. |
| 6 | Emit the conservation rows into the existing row stream instead of their own channel | RED — `NET` moves by one per finding and the gate blocks. This is the arithmetic-isolation row, and it is the one mutation every reporting and telemetry assertion in this suite would pass straight through, because each of them would still be true. |

**Harness rows.**

- *Suite mutation that must RED:* raise the assertion floor without adding cases.
- *Must-PASS input that is not the canonical:* an issue created after the pull request citing an
  unrelated number **not** in `CLOSING_NUMS`, and an issue citing a closed number but carrying no
  machine-filing marker. Neither is reported; the gate passes. These are the over-matching controls,
  and without them the matrix cannot detect a predicate that flags everything.

## Observability

```yaml
liveness_signal:
  what: the three suites run in CI on every pull request touching their subjects; the net-issue-flow
        gate additionally emits a telemetry row per invocation
  cadence: per pull request
  alert_target: CI failure on the pull request; rule-metrics aggregation for the gate's rows
  configured_in: the existing test battery and .claude/hooks/ship-net-issue-flow-gate.sh
error_reporting:
  destination: CI job output and the incident-marker telemetry rows already emitted by these gates
  fail_loud: true for the scanner suites (non-zero exit); the gdpr-gate stays advisory by its
             documented contract, and the conservation check reports without blocking in this cycle
failure_modes:
  - mode: the P1b detector silently narrows (verb family, corpus glob, or binding form removed)
    detection: the FILES and SITES floors in its own suite, plus mutation rows 1, 5 and 6
    alert_route: CI failure
  - mode: a burn-down commit shrinks the baseline with no matching source edit
    detection: per-commit inspection that the baseline diff is accompanied by source edits in the
               same commit; the ratchet alone cannot see this, which is why it is a review step
    alert_route: pull request review, and the acceptance criterion below
  - mode: an inserted assertion changes a gate test's verdict boundary
    detection: per-file suite run plus the synthetic pass and synthetic failure exercise on each
               hooks and gate-test holder
    alert_route: CI failure on that file's own suite
  - mode: last-verified advances without a fresh comparison
    detection: vendor-pin-verify.yml, which already fires on any NOTICE edit, running the
               strengthened path-content check from Phase 3.2
    alert_route: CI failure on the pull request carrying the date change
  - mode: conservation findings leak into the blocking FILED count
    detection: the arithmetic-isolation acceptance criterion and Guard 3 mutation row 6
    alert_route: CI failure in the net-issue-flow suite
  - mode: the conservation check fires constantly on ordinary pull requests
    detection: its dedicated telemetry rule id, aggregated across pull requests
    alert_route: the promotion-to-blocking issue's re-evaluation trigger reads this rate
logs:
  where: CI job output; incident-marker rows under the existing rule-metrics aggregation
  retention: as per the existing aggregation
discoverability_test:
  command: python3 plugins/soleur/test/lib/fixture-scan.py --rule operand --repo .
  expected_output: a trailer reading FILES=<n> and SITES=<total of any acknowledged baseline rows,
                   0 when there are none> once the burn-down completes; SITES=167 before it starts
```

## Acceptance Criteria

### PR 1 — #7709

1. `python3 plugins/soleur/test/lib/fixture-scan.py --rule operand --repo .` reports `SITES` equal to
   the total of the acknowledged rows remaining in the baseline — which is `0` when there are none,
   the expected and intended outcome.

   This wording is deliberate and replaces a flat `SITES=0`. The scanner has no exemption mechanism:
   an acknowledged site is still a counted site, and PR 1 does not touch `fixture-scan.py` to give it
   one. So a literal `SITES=0` would contradict the allowance for acknowledged entries two phases
   earlier, and the contradiction would only surface at verification, on the one site that genuinely
   cannot take an assertion. Any acknowledged row is a signal to re-examine the plan rather than a
   routine outcome — if more than a couple appear, the remedy set is wrong, not the sites.
2. `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh` passes, and every non-comment row
   remaining in its baseline corresponds one-to-one with an acknowledged entry recorded in the file's
   comment header.
3. Every commit in the branch whose diff touches the baseline also touches at least one `.sh` file in
   the same commit. Verified per commit by walking `git rev-list` and inspecting each commit's own diff
   — not with `git log -- <pathA> <pathB>`, which is a union filter and would pass on exactly the
   asymmetric commit this criterion exists to catch.
4. The full test battery is green, not only the suites for edited files.
5. For each holder under `.claude/hooks/` and each gate-test holder, a **before-and-after transcript**
   is recorded: that holder's own existing RED fixtures re-run, plus a synthetic pass and a synthetic
   failure, with the exit code and the failure text captured on both sides of the edit and compared.
   The pass condition is that the same case fails the same way, not merely that something failed —
   `${X:?}` and `|| return 1` change the exit status and the message, so a binary red-or-green check
   cannot see a remedy that altered *how* a gate fails. The fixture-construction path is exercised
   too, since a guard tripping during setup reads as broken infrastructure rather than a denial.
6. Any site not remediated carries an explicit acknowledged entry naming the file, the reason and the
   re-evaluation trigger. A count adjustment with no such entry does not appear.

### PR 2 — #7708

7. `fixture-scan.py` exposes a third `--rule` value, accepted by the rule-validation tuple in `main()`
   — the third editing site, distinct from the rule function itself. `git diff` shows no change to
   `OPERAND_WRITE` or to `scan_operand`.
8. Re-running the P1a suite reports `SITES=0` and its baseline is byte-identical to the state PR 1 left
   it in — the new rule perturbs nothing.
9. The P1b suite passes, with its own baseline file at its own path, and its measured site and file
   counts are recorded in the pull request body.
10. The rule reports the three verb families separately, and the suite asserts each family's behaviour
    independently rather than asserting a single combined property.
11. Every row of Guard 1's mutation matrix has been executed and observed to produce the stated result,
    with the observations recorded.
12. If the measured residue was not burned down in place, an issue exists carrying the count, the
    per-family split and the largest holders.
13. The module docstring no longer asserts that there are two rules. It currently says so in prose
    twice, and a header describing "the two rules" one function away from a third is the cheapest
    possible form of stale documentation.
14. The baseline compare, regenerate and floor logic is shared between the two suites rather than
    copied, with only the fixture corpora differing.

### PR 3 — #7710

15. The NOTICE frontmatter lists all eight vendored files. Verified by comparing the frontmatter entry
    count against the vendored rows of the body table and finding them equal.
16. `vendor-pin-integrity.sh --verify-upstream` reports a per-file `SAME` or `DRIFTED` verdict and a
    total for all eight, and covers eight files where it previously covered five.
17. The strengthened check is demonstrated to fail on a deliberately falsified pin, not merely to pass
    on the real one — a check that only ever passes proves nothing about what it would reject.
18. `last-verified` is bumped only if the comparison reports zero drift at implementation time, with
    the per-file output recorded in the commit message.
19. The strengthened check is confirmed to pass on the shape of an automated re-vendor pull request —
    one where the pins are being moved to current upstream in the same diff — so that hardening this
    gate does not silently start failing the pipeline that `content-vendoring.md` §6 makes canonical.
20. `knowledge-base/legal/compliance-posture.md` carries a row in `## Active Compliance Items` for the
    2026-05-10 to 2026-09-03 window recording that the §8 chain did not run, why, and how it was
    resolved, following that section's documented row schema.
20a. The same file's `## Vendored Code Provenance` row reads eight lifted files, not five, and its
    `Last Verified` matches the NOTICE. Verified by grepping that all three artifacts — NOTICE
    frontmatter, NOTICE body table, provenance row — agree on both the count and the date.
21. Running the gate against a path set that matches nothing produces a line stating the scan ran —
    so its output is no longer a subset of the output produced when it does not run.
22. The gate still exits 0 on every path, and the 30-day and 90-day thresholds are unchanged.

### PR 4 — #7759

23. `bash plugins/soleur/test/net-issue-flow.test.sh` passes with new cases covering: the measured
    PR #7702 shape; a second unattributed issue after an attributed first; an unrelated citation that
    must not be reported; and a citation without a machine-filing marker that must not be reported.
24. **`NET` is numerically unchanged by the presence of conservation findings.** Verified by running
    the gate against the #7702 fixture shape and comparing the reported `Filing:` and `Net:` values
    against the pre-change values on the identical fixture. This is the criterion that catches the
    conservation set leaking into the blocking count; every other criterion here would pass while it
    did.
25. The gate's exit code on a pull request whose only finding is unattributed issues is 0 in this
    cycle, and the report naming them appears in the always-emitted block.
26. An issue exists for promoting the conservation check to blocking, carrying a re-evaluation trigger
    stated in terms of measured fire rate.
27. No commit message and no pull request body in this batch describes any change as resolving #7255.
    Scoped to commit messages and pull request bodies only — the plan file itself contains that phrase
    inside the sentence prohibiting it, so a grep over tracked content would trip on its own rule.

## Domain Review

**Domains relevant:** Engineering, Legal.

### Engineering

**Status:** reviewed
**Assessment:** Verified the plan's factual claims against `main` independently and confirmed the
baseline (167 sites, 32 files), the top holders, the unconditional 999 from the cron staleness probe,
and that the existing upstream verification only asserts blob resolvability rather than path currency.

Three findings changed the plan. First, `hr-write-boundary-sentinel-sweep-all-write-sites` requires
enumerating write sites before sizing a new guard, and #7708 carried no count — measuring it produced
the three-way pull request split and the grandfathering approach for P1b. Second, two of the three
burn-down remedies change control flow rather than merely asserting, and nine of the 32 holders are
scripts that gate other pull requests, which produced the per-file batching and the synthetic
pass-and-failure exercise. Third, blocking on ambiguity in the conservation check was assessed as
likely to wedge ordinary merges, since closed issue numbers are cited routinely for unrelated reasons;
that produced the report-only first cycle, the machine-filing-marker precision conjunct, and the
separate promotion issue.

The review found no architectural decision requiring an ADR: all four items are gate and test-infra
repairs inside existing patterns, introducing no service, data model or cross-boundary integration.

### Legal

**Status:** reviewed
**Assessment:** Raised the blocking finding that the NOTICE frontmatter — canonical per
`content-vendoring.md` §2 — pins five of eight vendored files, so an attestation made against it would
claim a completeness that does not exist. Independently verified, and promoted to a precondition.

Confirmed that bumping `last-verified` on measured evidence is sound but is self-attestation rather
than independent corroboration while #7255 is open, and that the change must not be worded as
resolving it. Recommended writing the retrospective posture row for the window in which the §8 chain
never ran, on the grounds that a late row is better than a silent gap for a later auditor. Found no
Article 30 or DPIA implication, since nothing here touches a processing activity, purpose, legal basis
or data flow — only how a tool reports its own rule freshness. Found no new licensing obligation:
comparing content against pinned SHAs is read-only integrity checking, not a re-lift, and the existing
NOTICE and per-file attribution headers already satisfy the MIT terms.

That §8 has no mechanical enforcement — nothing makes the chain run when `POSTURE_FAIL` fires — was
noted as a real finding, and is filed rather than fixed here.

### Product/UX Gate

Not applicable. No file in the edit or create lists matches a UI surface; there is no user-facing
page, component or flow in this batch.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| A control-flow remedy converts a benign no-op into an abort inside a script that gates other pull requests, surfacing weeks later on unrelated work. | Prefer the purely additive remedy wherever the binding form allows; batch per file with its own suite green before moving on; exercise each hooks and gate-test holder with a synthetic pass and a synthetic failure. |
| A mass edit stubs the assertion helper into a no-op, and everything reads green. | Finish on `SITES=0` from the scanner itself rather than on suite greenness, and keep the byte-equality drift arm that pins every inline copy against the canonical body. |
| The baseline shrinks in a commit with no matching source edit — the ratchet cannot see this. | A per-commit acceptance criterion that walks `git rev-list` and inspects each commit's own diff, explicitly avoiding the `git log -- pathA pathB` union form. |
| P1b's measured residue turns out large enough that grandfathering it merely relocates the debt. | The residue is measured before the shape is chosen, and the burn-down is filed with its count and per-family split so the debt is sized rather than implied. |
| The conservation check is noisy enough to be ignored even as a report. | Precision conjunct on machine-filing markers from day one, dedicated telemetry so the rate is measured rather than argued, and promotion to blocking gated on that measurement. |
| The `last-verified` bump sets a precedent for date edits backed by a claim rather than a run. | The check that already guards the NOTICE on every pull request is strengthened to measure path-content currency, so the date cannot advance without CI having performed the comparison. No new gate is added. |
| The conservation check's rows reach the bash loop that increments `FILED` once per row, silently converting a report into a block. | A separate output channel with its own consumption loop, an isolated jq expression, a dedicated mutation row, and an acceptance criterion pinning `NET` numerically unchanged on the #7702 fixture. |
| Strengthening the upstream check starts failing the automated re-vendor pull requests that `content-vendoring.md` §6 makes canonical. | An acceptance criterion confirms the check passes on a re-vendor-shaped diff, where the pins move to current upstream in the same change. |
| Zero-drift no longer holds at implementation time. | The comparison is re-run at the moment of the bump; on drift the branch defined in Phase 3.3 ships the rest of the pull request and files the re-vendor separately. |
| The frontmatter's four-issue `closes:` list is lifted into the first pull request body, auto-closing three issues whose work has not shipped. | The Sequencing and Issue Closure section fixes one closing keyword per pull request and states that the frontmatter list describes the branch, not any single pull request. |
| An acknowledged, unremediated site makes a flat `SITES=0` criterion unsatisfiable, and the conflict surfaces only at verification. | The criterion is stated against the acknowledged-row total rather than against zero, and any acknowledged row is treated as a signal to re-examine the remedy set. |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Fold P1b into `scan_operand` by widening its verb list. | Moves P1a's live counts mid-burn-down and collapses three measured behaviours into one claim the issue explicitly forbids. |
| Ship #7708 and #7709 as one pull request. | The measured P1b surface makes #7708 a second grandfathering step; bundling would have hidden a larger burn-down inside a change already carrying a 32-file sweep, and would have made the two independently-revertible risk classes inseparable. |
| Re-vendor the gdpr-gate rule corpus. | Measured: nothing to re-vendor. Zero of eight lifted files differ from their pins. |
| Raise the 90-day staleness window. | `content-vendoring.md` §7 makes the thresholds ADR-gated, the issue rejects it, and it addresses neither the indistinguishable output nor the incomplete record. |
| Bump `last-verified` with the evidence in the commit body and no CI enforcement. | Evidence-backed once, unenforceable thereafter — the next change can cite the tool without running it. The enforcement ships with the edit instead. |
| Widen the FILED selector to match closed-issue citations. | Silently changes a blocking count and cross-attributes a sibling pull request's filings, which the issue itself names as the risk. |
| Block on ambiguity in this cycle. | Closed issue numbers are cited routinely for unrelated reasons; with no measured false-positive rate this risks wedging ordinary merges, and it would make a new heuristic the second blocking signal in a script whose every other failure path is fail-open. |
| Fix only the filing producers to emit `Source: PR #<n>`. | Cannot cover the brainstorm producer, which files against a parent issue when no pull request exists, and leaves pre-existing filings invisible — silently, which is the property under repair. |

## Gate Records

**Architecture Decision (ADR / C4):** no ADR. All four items are gate and test-infrastructure repairs
within existing patterns — no new service, data model, substrate, ownership boundary or trust boundary.
ADR-131, which governs gate work, is `status: proposed`, states that it decides nothing, and its
Proposal 1 permits existing gates to be fixed or tightened; the directly analogous prior change to
net-issue-flow produced no ADR either. No C4 impact: the change adds no external actor, no external
system or vendor, no container or data store, and no actor-to-surface access relationship — the
vendored-content relationship with the upstream repository already exists and is unchanged by
re-verifying against it.

**GDPR / compliance gate (Phase 2.7):** no regulated-data surface is touched — no migration, no auth
flow, no API route, no `.sql` file — and none of the four expansion triggers fires: no new processing
activity, no single-user-incident threshold, no new cron reading from the knowledge base, no new
artifact distribution surface. The batch modifies a compliance gate's own reporting, which is why the
Legal domain review above was run in full rather than skipped.

**Infrastructure as code (Phase 2.8):** no new infrastructure. No server, service, secret, vendor
account, DNS record, certificate or persistent runtime process.

**Encryption posture (Phase 2.11):** no persistent data store and no new cross-component connection.

**Soak follow-through (Phase 2.9.1):** no acceptance criterion is time-gated. The conservation check's
promotion to blocking is filed as a separate issue with a re-evaluation trigger, deliberately rather
than as a soak gating this batch's closure.
