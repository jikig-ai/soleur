---
title: "Context-governance instrument fixes"
date: 2026-07-27
type: chore
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 7008
pr: 7006
branch: feat-context-engineering-audit
brainstorm: knowledge-base/project/brainstorms/2026-07-27-context-engineering-claude5-audit-brainstorm.md
spec: knowledge-base/project/specs/feat-context-engineering-audit/spec.md
plan_review: 6-agent panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, cto-devex) — v2 below
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan introduces NO infrastructure — no server, service,
     cron, secret, vendor, DNS record, or persistent runtime. The `doppler secrets set`
     string appears solely as a QUOTATION of existing text in
     plugins/soleur/skills/admin-ip-refresh/SKILL.md:42, cited to explain why that line's
     `-auto-approve` reference is a category error (that command has no such flag). No
     step here provisions or mutates infrastructure. -->

# Context-governance instrument fixes

## Overview

Repair the instruments that report which AGENTS rules reach context. **Zero rules added
or deleted.**

**v2 after a 6-agent review panel.** Four of the original ten FRs were cut or deferred on
evidence — including two where my own proposed fix was itself a no-op. What ships is
narrower and verified: FR1, FR2, FR6, FR7, FR8, FR9, FR11.

## Research Reconciliation — Spec vs. Codebase

Every row was re-derived from source. Five spec/plan claims were wrong.

| Claim | Reality (measured) | Response |
|---|---|---|
| FR7/FR8 "may breach B_ALWAYS (100 B headroom) — may need a `wg-*` demotion" | `lint-agents-rule-budget.py:78` — `ALWAYS_LOADED = ("AGENTS.md", "AGENTS.core.md")`. **`AGENTS.rest.md` is excluded.** Both FR8 targets are in `rest` (196 B, 364 B vs a 600 B cap). FR7 edits only skill/doc files. | **No demotion. B_ALWAYS untouched.** The operator's constraint is real but does not bind. |
| FR5 "`rule-prune.sh` lacks a `[compliance-tier]` exemption" | **Two placebos.** (a) `is_he` has no `continue`. (b) Decisive: `sanitized_prefix` is truncated to `RULE_PREFIX_LEN=50` (`scripts/lib/rule-metrics-constants.sh:13`) while `[compliance-tier]` sits at **char 214 of a 349-char line** — the substring test can *never* match, so `is_he` has always been 0 and `rule-prune.sh:193`'s `($hook_enforced …)` is a standing tautology. 4 of 5 compliance-tier rules are `hr-*`, already hard-skipped at `:154-157`. `rule-prune.sh:15`: *"Neither mode edits AGENTS.md — humans retire rule text in a separate PR."* | **DEFERRED.** Exposure is a bad *proposal*, not a deletion. Correct fix is a first-class enforcement-tag field in `rule-metrics.json` + `SCHEMA_VERSION` bump — real scope, orthogonal to this PR. Shipping the substring fix would be placebo #2. |
| FR9 "4 dead citations" | **3 are false positives.** `plan/SKILL.md:968` *narrates* PR #5349's descope. `deepen-plan/SKILL.md:775` is the **worked example of a fabricated id** — the line says "(fabricated, never existed)". `cq-pencil-collapse-auto-recover` is a **deliberate tier-gate carve-out** (`rule-metrics-aggregate.sh:302-309`: *"per `cq-agents-md-tier-gate` … tier-gated OUT of AGENTS.md … emitted by their hooks by design"*) **and** a live runtime key in `.rule-incidents.jsonl` — removing the exclusion trips the orphan gate. Only `ship/SKILL.md:770` is real. But the *class* is larger: 3 more confirmed shipped orphans. | Triage rewritten. The "add the rule or drop it" fork is **deleted** — both branches were wrong. |
| FR10 "add a citation-resolver lint" | The proposed scan yields **~45 unresolved tokens**, not 4: ~30 synthesized test fixtures (mandated by `cq-test-fixtures-synthesized-only`), truncated line-wrapped prose, and `rf-worktrees` matched inside `block-rm-rf-worktrees` (`\b` does not break on `-`). It also *excludes* `knowledge-base/legal/` and `docs/legal/` — the only citations with legal weight, and exactly where FR6's defect lives. | **DEFERRED with a design brief.** Needs a fixture carve-out, a `(?<![a-z0-9-])` boundary, an allowlist (one already exists in `rule-metrics-aggregate.sh`), and legal-dir scope. Unshippable as specified. |
| Plan claimed "9 spec FRs" | It implemented 8. **Spec FR4** (skill descriptions 2,400 → ≤1,800 words across 95 files) and **TR2** (class-share script) appeared in no phase, no AC, no Non-Goal. | Both now explicit Non-Goals with tracking issues. FR4 is the spec's largest reduction and deserves its own PR. |

Additional constraints found, not in the spec:
- **Stamp contract is ≤200 bytes** (`session-rules-loader.test.sh` Test 11) — and the HINT
  line already measures **206 bytes** in this worktree; Test 11 passes only because it runs
  in a short `mktemp -d`. Worst-case stamp is ~142 chars; the byte figure takes it to ~155.
  Headroom is **~40 B, not 140 B**.
- **Test 11 measures characters, not bytes** (`awk '{print length}'`), and the notes contain
  em-dashes (3 B each). The contract is under-measured by ~4 B.
- **`compound/SKILL.md:257` carries the identical doubled glob** (`grep -h '^- ' AGENTS*.md`
  → 202), in a shipped plugin file, reported to the operator on every `/compound`. → FR11.

## User-Brand Impact

Carried forward verbatim from the brainstorm.

- **If this lands broken, the user experiences:** a session that silently loads the wrong
  rule set, or a stamp that misreports coverage so the next decision rests on a false number.
- **If this leaks, the user's data is exposed via:** an instrument overstating rule coverage
  can license a future cut that removes a compliance control from context at the moment the
  risky action runs; invisible until data or production state is already affected.
- **Brand-survival threshold:** single-user incident.

CPO sign-off carried from the brainstorm's CPO+CLO+CTO triad. `user-impact-reviewer` runs at review.

## Implementation Phases

### Phase 0 — Capture baselines on `main` (required; ordering dependency)

Before any edit, on `main`:

```bash
for m in docs code both; do   # per-class $CONTEXT body hash, header lines excluded
  bash .claude/hooks/session-rules-loader.sh <<<"{\"cwd\":\"$PWD\"}" \
    | jq -r '.hookSpecificOutput.additionalContext' | tail -n +4 | sha256sum
done
grep -c '^- \[id: ' AGENTS.md                                    # expect 101
for f in core docs rest; do grep -c '\[id: ' AGENTS.$f.md; done  # expect 53 / 6 / 42
grep -cE '^(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]+[[:space:]]*\|' scripts/retired-rule-ids.txt  # expect 58
```

AC6 and AC12 compare against these. Captured after Phase 1 they prove nothing.

### Phase 1 — Fix the instrument (FR1, FR2, TR1)

1.1 **RED first.** Add to `session-rules-loader.test.sh` a test asserting the stamp's `M`
equals the body-sidecar count (101). Commit the test **alone**, confirm it fails (reports
202), then commit the fix. Add a **permanent** anti-regression assertion —
`grep -q 'AGENTS\*\.md' .claude/hooks/session-rules-loader.sh` must fail — which survives
the PR, unlike pasted output.

1.2 **FR1.** `.claude/hooks/session-rules-loader.sh` `TOTAL_RULES=` — glob the three body
sidecars instead of `AGENTS*.md`.
*Rationale corrected:* `RULE_COUNT` is scoped to the **selected** sidecars (53/59/101 by
path) while the denominator is corpus-wide. They share a counting **predicate**, not a
scope — correct for an "N of M" stamp. The bug is only that `M` counted the index too.
Architecture confirmed `TOTAL_RULES` is assigned once and consumed once (the stamp); the
manifest derives from `$CONTEXT`, and **no consumer of the `(N of M)` string exists**.

1.3 **FR2.** Append a compact byte figure to `STAMP`. Derive it with
`printf '%s' "$CONTEXT" | wc -c` — **not** `${#CONTEXT}`, which counts characters and would
disagree with the byte figures it invites comparison against. Assert the **worst-case
composed** stamp (both notes present), not the happy path.

### Phase 2 — Resolve the rule/skill conflicts (FR7, FR8)

2.1 **FR7 — no escape hatch; neither call site has a legitimate reason.** Verified:
`ship/SKILL.md:821,856` run `terraform apply -input=true` asserting "the Terraform yes
prompt is the load-bearing authorization" — under `hr-the-bash-tool-runs-in-a-non-interactive`
that prompt is **unanswerable**, so this is a hang, not a policy. `admin-ip-refresh/SKILL.md:42`
is a **category error**: the acked command there is a Doppler secret write, which has no
`-auto-approve` flag at all.

Correct form: chat ack → `terraform apply -target=… -input=false -auto-approve`.
**Phase 3.1b is deleted. `AGENTS.core.md` is not touched. B_ALWAYS is byte-identical.**

Sweep **all six** sites, not two: `ship/SKILL.md:821,856`, `admin-ip-refresh/SKILL.md:42`,
`admin-ip-refresh/references/admin-ip-refresh-procedure.md:107,148`, and
`knowledge-base/engineering/operations/runbooks/admin-ip-drift.md:104,162,223`.

2.2 **FR8.** Clause goes on **`wg-when-an-audit-identifies-pre-existing`**
(`AGENTS.rest.md:21`) — it is the unconditional one ("file them", no triage), it is the
side that is wrong in the overlap, and it has the larger headroom (404 B vs 236 B).
`wg-when-deferring-a-capability-create-a:38` already delegates correctly to
`wg-defer-only-after-inline-triage`. Clause (~180 B):

> If the finding is one you elect to defer rather than fix, `wg-defer-only-after-inline-triage`
> governs whether it becomes an issue — but it MUST land in a durable artifact (plan
> Non-Goals, register, code comment), never conversation only.

Zero B_ALWAYS cost (`rest` is excluded). Re-run the linter after — **`AGENTS.rest.md:22`
is exactly 600 bytes**, at the per-rule cap, so verify with the linter, never `awk length`
(chars ≠ bytes).

### Phase 3 — The `hr-`/`wg-` prefix class (FR6, widened)

Both are the same defect — a live rule cited under the wrong prefix:
- `knowledge-base/legal/article-30-register.md:417` — `hr-block-pr-ready-…` → `wg-block-pr-ready-on-undeferred-operator-steps`
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:817` — `hr-cla-signed-author-before-merge` → `wg-cla-signed-author-before-merge`

Verify each corrected id resolves in `AGENTS.md`.

### Phase 4 — Orphaned citations (FR9, corrected)

**Leave unchanged** (verified legitimate; changing them causes damage):
`plan/SKILL.md:968` (narration), `deepen-plan/SKILL.md:775` (the fabricated-id teaching
example), and all six `cq-pencil-collapse-auto-recover` sites (tier-gated by design +
runtime key).

**Fix — drop the dead citation, keep the sentence** (no survivor covers "keep gate regex +
docs + fixtures in sync"): `ship/SKILL.md:770`.

**Fix — 3 confirmed shipped orphans the spec never enumerated** (all `live=0`):
`.claude/hooks/durable-reminder-prefer-inngest.sh:6` (`hr-durable-reminders-use-inngest-primitive`,
which even claims "AGENTS.core.md"), `scripts/betterstack-query.sh:52`
(`hr-observability-probe-transient-is-not-no-access`), `scripts/rule-prune.sh:17`
(`hr-rule-retirement-guard`). For each: drop the citation and inline the rationale, per
`deepen-plan/SKILL.md:775`'s own prescription.

### Phase 5 — The sibling doubled glob (FR11, new)

`plugins/soleur/skills/compound/SKILL.md:257-258` — same `AGENTS*.md` glob, reports 202 to
the operator every `/compound` run, in a shipped plugin file. Two-token fix; without it
Phase 1 fixes one instrument and leaves its twin lying.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — the denominator test is committed **before** the fix, fails on `main` (202),
      passes after. The permanent `grep -q 'AGENTS\*\.md'`-must-fail assertion is in the suite.
- [ ] AC2 — a fail-open session stamps `(101 of 101 rules)`.
- [ ] AC3 — the **worst-case composed** stamp (fail-safe + over-strip notes + byte figure)
      is ≤200 **bytes**, measured with `wc -c`.
- [ ] AC6 — the three per-class `$CONTEXT` body hashes from Phase 0 match post-change,
      pairwise. (Scoped to the rules body, `tail -n +4`; the stamp *does* change — AC2/AC3
      require it.)
- [ ] AC7 — each of the six FR7 sites **positively** asserts ack-then-`-auto-approve` (or,
      for the Doppler write, drops the inapplicable flag reference). A negative grep is
      insufficient — it passes vacuously if the token is merely deleted.
- [ ] AC8 — the audit-vs-defer overlap resolves to one instruction; both rule ids still
      present; `python3 scripts/lint-rule-ids.py` exits 0.
- [ ] AC10 — both `hr-`/`wg-` prefix defects corrected; both ids resolve in `AGENTS.md`.
- [ ] AC11 — the 4 dead citations (1 + 3) are gone; the 3 verified-legitimate sites are
      **untouched** (`git diff --stat` shows no change to `plan/SKILL.md`,
      `deepen-plan/SKILL.md`, or any pencil site).
- [ ] AC12 — index 101, bodies 53/6/42, retired 58 — all identical to the Phase 0 baseline,
      using the pinned commands above. `lint-rule-ids.py` exits 0.
- [ ] AC13 — `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md 2>&1`
      exits 0 with `[WARN]`, and `B_ALWAYS` is **byte-identical to 22,900** (nothing in v2
      touches `AGENTS.md` or `AGENTS.core.md`). Use the linter — not `awk length` — for the
      per-rule cap; it measures bytes, awk measures chars.
- [ ] AC14 — `compound/SKILL.md` reports 101, not 202.

### Post-merge (operator)

None. Every step is executable in-session.

## Deferred — each gets a tracking issue in this PR

| Item | Why deferred | Re-evaluation |
|---|---|---|
| **FR3** `B_FAILOPEN` reporting — #7013 | FR2 already puts the live figure in the stamp *every session*, where decisions happen; FR3 is the same number, staler, behind a build step, and carries a real traceback risk (an uncaught `FileNotFoundError` on the two new files would wedge every commit). | When something needs to gate on it — the ADR's job. |
| **FR4** skill descriptions 2,400 → ≤1,800 words — #7011 | The spec's largest reduction, 95 files, unrelated to reporting instruments. | Its own PR. |
| **FR5** compliance-tier prune exemption — #7009 | The specified fix cannot reach its target (50-char prefix truncation). Correct fix is an aggregator schema change + `SCHEMA_VERSION` bump. Exposure is a *proposal* a human must action. | With the schema change. |
| **FR10** citation-resolver lint — #7010 | ~45 tokens, ~30 of them mandated test fixtures; needs a `(?<![a-z0-9-])` boundary, a fixture carve-out, an allowlist, and legal-dir scope. | Design brief above. **Not a silent drop** — the class recurred *because* the May learning did not compile. |
| **TR2** class-share script | Not load-bearing for any surviving AC. | With the ADR. |
| **Classifier-axis ADR** — #7012 | The question changes — see below. | Next cycle. |

**The ADR's question changes from "re-cut the axis?" to "keep or collapse the split?"**
Option (a) — excluding `knowledge-base/**` from `DOCS_RE` — is **unsafe and not a one-line
edit**: simulated against the loader's own branch logic, a KB-only changeset sets
`HAS_DOCS=HAS_CODE=HAS_INFRA=0`, no `elif` fires, and `CLASSES` falls through to its `core`
default — silently dropping `AGENTS.docs.md`, which holds `cq-rule-ids-are-immutable`,
`cq-agents-md-tier-gate`, `cq-agents-md-why-single-line`, `cq-skill-description-budget-headroom`
and `wg-ui-feature-requires-pen-wireframe` — precisely the rules that fire on knowledge-base
edits. That is PR #3681 reproduced exactly. The live alternative is **(c) collapse to a
single always-loaded corpus**: the split buys ~3,782 B weighted mean (~950 tokens, in a
cache-stable prefix) and charges a class-fit verification tax on every rule-authoring
decision forever, plus two production incidents (#3681, #3808).

## Files to Edit

`.claude/hooks/session-rules-loader.sh` · `.claude/hooks/session-rules-loader.test.sh` ·
`.claude/hooks/durable-reminder-prefer-inngest.sh` · `scripts/betterstack-query.sh` ·
`scripts/rule-prune.sh` (citation only) · `knowledge-base/legal/article-30-register.md` ·
`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` ·
`plugins/soleur/skills/ship/SKILL.md` · `plugins/soleur/skills/admin-ip-refresh/SKILL.md` ·
`plugins/soleur/skills/admin-ip-refresh/references/admin-ip-refresh-procedure.md` ·
`knowledge-base/engineering/operations/runbooks/admin-ip-drift.md` ·
`plugins/soleur/skills/compound/SKILL.md` · `AGENTS.rest.md`

**Not edited** (verified legitimate): `plugins/soleur/skills/plan/SKILL.md`,
`plugins/soleur/skills/deepen-plan/SKILL.md`, all `cq-pencil-collapse-auto-recover` sites,
`AGENTS.md`, `AGENTS.core.md`, `AGENTS.docs.md`.

## Files to Create

None.

## Observability

Trigger set does not strictly fire (`.claude/hooks/` and repo-root `scripts/` are outside
it). Recorded because the subject *is* an observability instrument.

```yaml
liveness_signal:  the session-start stamp, emitted every session. Cadence: per session.
error_reporting:  loader already fails closed (missing/symlinked sidecar → re-walk all
                  classes + FAIL_SAFE_NOTE). Unchanged.
failure_modes:
  - mode: denominator regresses to the doubled glob
    detection: the permanent `grep -q 'AGENTS\*\.md'`-must-fail assertion (AC1)
    alert_route: CI test failure
  - mode: stamp exceeds the 200-byte contract
    detection: Test 11, switched to `wc -c` (AC3)
    alert_route: CI test failure
  - mode: a rule silently stops loading for its trigger class
    detection: AC6 per-class body hashes vs the Phase 0 baseline
    alert_route: CI / manual diff
logs:             stdout of the SessionStart hook; no retention surface.
discoverability_test:
  command: bash .claude/hooks/session-rules-loader.test.sh    # no ssh
  expected_output: all PASS, including the denominator and anti-regression assertions
```

## Architecture Decision (ADR/C4)

**No ADR in this PR** — it repairs reporting. The one architectural decision (keep vs
collapse the sidecar split) is deferred above with its question restated.

**No C4 impact — checked, not asserted.** Read all three model files. (a) External actors
— `founder`, `emailSender`, `betaContact`, `contributor` — unchanged; (b) no new external
system or vendor edge; (c) the `hooks` (`model.c4:68`) and `skillloader` containers already
exist and neither description is falsified; (d) no tenancy, ownership, or trust-boundary
movement. The rules corpus is not modeled as a C4 element.

## Domain Review

**Domains relevant:** Engineering, Product, Legal — carried forward from the brainstorm triad.

- **Engineering** — progressive disclosure is 8.7% effective; the doubled denominator hid it.
  `B_ALWAYS` 22,900/23,000, untouched by v2.
- **Product** — cost falls on the founder, not target users. Recommendation was mechanical
  fixes now, structural later; v2 is exactly that, and narrower than v1.
- **Legal** — no rule deleted. FR6 widened to both prefix defects. FR5's exposure re-assessed
  **downward** on evidence: `rule-prune.sh` never edits `AGENTS.md`, and 4 of 5
  compliance-tier rules are already hard-skipped — a bad proposal, not a deletion.
- **GDPR gate (2.7)** — assessed, not invoked: no new processing activity, data flow, schema,
  or distribution surface. FR6 corrects a citation *string* in an existing register row.
- **IaC (2.8)** — reviewed; no infrastructure introduced (see the ack comment at the top of
  this file). **Encryption (2.11)** — skipped; no persistent store, no new connection.

## Non-Goals

- Adding or deleting any rule.
- FR3 (#7013), FR4 (#7011), FR5 (#7009), FR10 (#7010), TR2 — deferred above, each tracked.
- Re-cutting or collapsing the classifier axis — ADR tracked in #7012.
- The 11 shipped plugin files referencing root-only governance paths — largely refuted:
  `compound/SKILL.md:245-251` already carries a consumer-repo degrade table, and
  `grok-fidelity-gate.sh` is a Soleur-internal dev gate that never executes in a tenant repo.
  P2, tracked separately.
- Roadmap `STALE_STATUS|phase 4` — unrelated; `/soleur:trigger-cron cron/roadmap-review.manual-trigger`.
