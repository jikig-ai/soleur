---
title: "Mechanical gates for two 'the check certifies the wrong thing' classes"
date: 2026-07-16
issue: 6517
pr: 6527
branch: feat-citation-rot-bare-token-gates
lane: cross-domain
brand_survival_threshold: single-user incident
tags: [ci-gate, citation-rot, vacuous-assertion, anchoring, born-blocking, agents-md-rule]
related_prs: [6456, 6479, 4265, 4646]
related_issues: [6517, 6462, 4270]
related_adrs: [ADR-071, ADR-076]
related_learnings:
  - 2026-07-16-a-gate-certifies-placement-not-correctness-and-a-documented-class-recurred-again.md
  - 2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md
  - 2026-07-02-enforce-gate-on-citation-resolvability-not-completeness-for-a-curated-register.md
  - 2026-05-12-brainstorm-write-mostly-artifact-diagnosis-and-lifecycle-prereq.md
  - 2026-07-06-measure-data-production-rate-before-scoping-a-visibility-surface.md
---

# Brainstorm: mechanical gates for citation-rot + bare-token body-grep

## What We're Building

Two **independent** interventions against two recurring "the check certifies the wrong
thing" classes. They share a motivation, not a mechanism, and ship as **two PRs**.

**Class A — a born-blocking ban on new `file:NNN` citations in code comments.**
A check over *added diff lines only* rejects newly-introduced `path:NNN` citations in
`.ts`/`.sh` comments and directs the author to a content-anchor (`<file> › <symbol>()`),
the convention ADR-076 item 3 already mandates for the domain-model register. Existing
citations are grandfathered; markdown is out of scope.

**Class B — the missing AGENTS.md rule (`cq-assert-anchor-not-bare-token`).**
A standing, always-loaded rule requiring that any body-grep / `indexOf` / `toContain`
over *file content* anchor on `^\s*` or a call-form — never a bare token that also
appears in a comment — plus mutation-testing every new assertion. The narrow ts-morph
gate is deferred behind a measurable trigger, not a calendar window.

## Why This Approach

The issue proposed (1) a citation *validator*, (2) a bare-token *static gate*, both
(3) advisory-first per the "frontend-anti-slop calibration precedent". Research
falsified all three premises.

**The cited calibration precedent does not exist as described.** `tier1-scan.ts` appears
in **zero** `.github/workflows/` files — it is a skill script invoked from prose in
`frontend-anti-slop/SKILL.md` and `review/SKILL.md`, not a CI gate. There is no advisory
stream to promote. Calibration issue **#4270** (opened 2026-05-21, stated window "2
weeks") is **still OPEN at 56 days**, with 4 comments — three on ship day, one triage bot
(2026-05-24) — and **zero findings logged organically**. Advisory→blocking promotion has
**never once happened** in this repo. What did ship blocking (brand rules, #4646, 8 days
later) was **born blocking** and skipped calibration entirely. Shipping advisory-first is
the highest-probability path to a third write-mostly artifact
(`2026-05-12-brainstorm-write-mostly-artifact-diagnosis`,
`2026-07-06-measure-data-production-rate-before-scoping-a-visibility-surface`).

**The Class A validator cannot detect the failure that motivated it.** `foo.ts:151`
carries no content assertion, so no gate can know what it *meant* to point at. The #6479
decoy was a 35-line shift *within* the file onto a line that still echoed `TRANSIENT` —
a resolvability check resolves it and passes. Measured 2026-07-16: 320 unique citations, 334
resolvable, **0 past-EOF** — the detector is weak on the tree it would guard. Banning
*new* line citations is cheaper (~10-line regex over `git diff -U0 | grep '^+'`), has
zero migration cost, needs no diff line-mapping, and enforces the rule the violated
file's own header already stated.

**Class B's naive surface is ~95% false-positive.** Naive regex hits ~619 sites (570
`toContain` + 49 `grep -q`), but most assert over *runtime values* — an HTTP body has no
comments, so the class cannot occur there. The genuine defect requires the haystack to
be file content read from disk AND the token to appear in a comment in that file: ~71
test files. Detecting that is ts-morph dataflow, not regex.

**The AGENTS.md rung was never tried.** Today's learning asserts *"This is `AGENTS.md`'s
standing rule — narrowing the scope is not the fix — anchor on syntax"*. Grep of
`AGENTS.md`, `AGENTS.core.md`, `AGENTS.rest.md`, `AGENTS.docs.md` returns **no such
rule**. The class is documented only in learnings. The learning's own diagnosis is that
"documentation that lives one `grep` away from the point of use is not where the author
is looking" — which is an argument *for* the always-loaded rule surface, not past it.
The repo's ladder is learning → AGENTS.md rule → hook/CI gate; #6517 proposes jumping to
rung 3 while asserting rung 2 failed. It was never occupied.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Class A = ban new `file:NNN`, not validate resolvability** | Validator can't detect the #6479 decoy (35-line intra-file shift, token still echoed); **0** of 334 resolvable citations are past-EOF. Ban is ~10 lines, 0 migration cost. |
| D2 | **Class A scope: code comments (`.ts`/`.sh`) only; markdown excluded** | 6,529 markdown citations vs 52 in code comments. Archived plans/learnings are historical records, not live claims — validating them is category error. |
| D3 | **Class A: grandfather existing citations** | Enforce on added diff lines only. Zero-noise on the standing tree. |
| D4 | **Both ship born-blocking; advisory framing dropped** | #4270 open at 56d/2wk window, 0 organic findings; 0 advisory→blocking promotions ever; #4646 born-blocking works. Overrides #6517's stated AC. |
| D5 | **Class B = add `cq-assert-anchor-not-bare-token` to AGENTS.md now; defer the ts-morph gate** | Rung 2 never tried. Rules load every session via `session-rules-loader.sh`; learnings do not. |
| D6 | **Class B gate promotion trigger = rule-metrics, not a calendar window** | `rule-audit.yml` + `rule-metrics-aggregate.yml` + `rule-metrics.json` already track per-rule fire counts and report unused rules. A window nobody closes (#4270) is replaced by a measured signal. |
| D7 | **Two PRs, not one** | Class A is diff-relative + lexical; Class B is a rule edit. Coupling lets B's calibration risk block A's clean win. |
| D8 | **Class A surface: PreToolUse hook on `git commit`, sibling to `brand-hex-commit-gate.sh`** | That hook already implements the diff mechanic (`-a`-aware diff base; awk hunk-header walker yielding newline→added-content). A diff IS available at PreToolUse — it computes it itself. Author-time beats CI: a CI warning arrives after the citation has rotted. |
| D9 | **Reuse `brand-hex-commit-gate.sh`'s diff machinery; no citation parser exists to reuse** | `dm_register_code_citations()` pairs file↔symbol with **no line numbers** — it is the philosophical precedent (anchor on symbols), not a code one. |
| D10 | **Frame Class B's rationale as keeping evidence-grade gates non-vacuous** | CLO: ADR-076 item 4's completeness disclaimer exists precisely so "no drift" can't be mis-cited as an attestation. Same shape one layer down. Engineering-hygiene argument, not compliance. |

**Productize Candidate:** `learning → AGENTS.md rule` promotion is currently manual and
was silently skipped for this class (a learning claimed a rule existed that did not).
`rule-audit.yml` exists but audits rules that *are* present; nothing detects a learning
that *asserts* a rule which is absent. Candidate: a check that greps learning bodies for
"AGENTS.md's standing rule"-shaped claims and verifies the cited rule resolves. Filed as
a follow-up, not scoped here.

## Open Questions

1. **Does Class A's ban need an escape hatch?** A `# cite-line:allow # issue:#NNNN
   <reason>` waiver mirrors `cq-test-fixtures-synthesized-only`'s gitleaks pattern.
   Recommend yes, for the rare case where a line number is genuinely the only anchor
   (e.g. citing a generated file with no symbols).
2. **Hook-only, or hook + CI backstop?** A PreToolUse hook is bypassable (`--no-verify`
   equivalents, agents that never call `git commit` through the harness). ADR-071 says a
   gate that cannot see what it guards produces false confidence. A CI sibling would
   close that, at the cost of a second implementation to keep in lockstep — the
   `tier1-scan.test.ts:654-678` parity-check pattern exists for exactly this.
3. **What is the promotion threshold for Class B's gate?** D6 says "rule-metrics", but the
   concrete trigger (e.g. "rule fires ≥N times in 30 days" vs "class recurs ≥1× after the
   rule ships") is unset. Plan-time decision.
4. **Hooks have no severity ladder.** They are binary allow/deny; `computeExitCode`'s
   rule-category keying is the repo's only promotion mechanism and is unavailable to
   hooks. D4 (born-blocking) sidesteps this, but if a future gate wants calibration on a
   hook surface there is no mechanism. Possible ADR.

## User-Brand Impact

- **Artifact:** the two proposed gates — the Class A born-blocking citation ban (PreToolUse
  hook) and the Class B `cq-assert-anchor-not-bare-token` AGENTS.md rule.
- **Vector:** a gate that reports green while the defect it certifies is present. A
  false-green in the verification chain lets a defective change reach a user believing it
  was verified; #6479 is the worked example — three live false-PASS routes to `exit 0` on
  a gate authorizing an **irreversible** GHCR PAT revoke, surviving eleven prior passes.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** `frontend-anti-slop/tier1-scan.ts` is the wrong template — it is a whole-file
lexical scanner with no diff concept, so Class A cannot fold into it. The right precedent
is `.claude/hooks/brand-hex-commit-gate.sh`, which already implements diff-at-PreToolUse.
No `file:NNN` parser exists to reuse. Class A is small (hours) and quiet (diff-scoped +
move-scoped); Class B is "currently unshippable as specified" — 586 bare-token sites is
noise, and the defect is bare-token-over-a-source-file-haystack, which is dataflow, not
regex. Ship as two artifacts. Capability gaps: none.

### Product (CPO)

**Summary:** The issue's load-bearing premise is refuted — `tier1-scan` is in zero
workflows, #4270's calibration window is 4× over at 56 days with zero organic findings,
and advisory→blocking promotion has never happened; born-blocking is the only mechanism
with a track record. Class A should ship the **ban**, not the validator (~360 citations,
334 resolvable, 0 past-EOF — the detector is weak, and the #6479 decoy passes it). Class B
should ship only if scoped to the ~71 readFileSync-plus-bare-token files; otherwise drop
rather than mint a third write-mostly artifact.

### Legal (CLO)

**Summary:** No legal or compliance implications — both gates are internal CI static
checks over Soleur's own source tree; no user data, PII, credentials, or customer-facing
surface. One adjacent note: ADR-076 item 4's completeness disclaimer is genuine precedent
for framing Class B as keeping evidence-grade gates non-vacuous, since false-greens in the
evidence chain (ADR-071 L1 gates, `gdpr-gate`, the domain-model register) turn a gate into
a claim it cannot support. No CLO action.

## Capability Gaps

None. Both interventions are buildable with existing hook conventions, the
`brand-hex-commit-gate.sh` diff machinery, and the AGENTS.md rule corpus. (CTO assessment,
verified against `.claude/hooks/README.md` and the 28 registered PreToolUse hooks.)

## Lane

`cross-domain` — set unconditionally by Phase 0.1 (`USER_BRAND_CRITICAL=true`, per #5175).
No operator override.

## Session Errors

1. **A subagent overstated an ADR's scope.** The learnings-researcher reported "ADR-076
   already decided: do not use line numbers **at all**." ADR-076 item 3's content-anchoring
   mandate is scoped to the **domain-model register's** facts/candidates, not a repo-wide
   ban on line numbers in code comments. — **Prevention:** an agent's ADR-scope claim is a
   claim to verify; read the ADR's Context + Decision, not just the Alternatives table.
   Applied here before the claim reached the doc.
2. **A merged learning asserted a rule that does not exist.** The 2026-07-16 learning
   states *"This is `AGENTS.md`'s standing rule"*; no such rule is in any AGENTS body. The
   assertion is itself an instance of the class it documents — a claim that reads as
   verified and is not. D5 fixes the underlying gap; the Productize Candidate above would
   detect the class.
3. **Roadmap drift left unsynced (deliberate).** `roadmap-reconcile.sh validate` reports
   `STALE_STATUS|phase 4|roadmap=43o/160c|milestone=55o/166c`. Not fixed here: the
   script's sanctioned path is the roadmap-review cron (which opens its own reviewed PR),
   and hand-editing would drag unrelated roadmap churn into a CI-gate branch. Surfaced to
   the operator instead.
