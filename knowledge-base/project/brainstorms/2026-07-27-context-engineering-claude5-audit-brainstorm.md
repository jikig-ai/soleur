---
title: "Anthropic's Claude-5 context-engineering rules — what actually applies to Soleur"
date: 2026-07-27
status: decided
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-context-engineering-audit
pr: 7006
source: https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models
related: [6794, 2762, 3808, 3681, 2865]
---

# Claude-5 context-engineering rules — applicability audit

> **CORRECTION (2026-07-27, post-review): FR7 is WITHDRAWN, and FR2 was cut.**
>
> **FR7 — my finding was wrong.** I reported the six `-auto-approve` sites as a
> "literal inversion" of `hr-menu-option-ack-not-prod-write-auth`. They are not.
> Three review agents converged, and two measurements settle it:
> 1. `terraform apply -input=true` with no TTY does **not** hang — it exits
>    immediately with `Error: error asking for approval: EOF` (measured: rc=1,
>    0s). My "hangs forever" rationale — repeated in this document, the commit
>    messages and the issue — was false. The old form failed **closed**.
> 2. `.claude/hooks/prod-write-defer-gate.sh` is a registered PreToolUse hook
>    that **defers** any agent-run `terraform apply` (measured), so the agent
>    never runs it unattended regardless of the flag.
>
> Those commands are run by a human at a real terminal (`admin-ip-refresh`
> SKILL.md Step 7: *"for the operator to run. Do NOT execute them."*), where
> Terraform's native prompt **is** the per-command gate. "Do NOT pass
> `-auto-approve`" was correct guidance. All six sites are reverted to `main`.
>
> **FR2 (stamp byte figure) — cut.** It was the only reason the `CORPUS` loop
> existed, and that loop introduced two P1s of its own (a false over-strip
> warning, and a denominator that collapsed onto the numerator so a truncated
> corpus stamped as 100%). The denominator now derives from the `AGENTS.md`
> index — a fixed expected set — which is simpler and strictly more honest.
>
> What ships: FR1, FR6, FR8, FR9, FR11.


## What We're Building

Not a rules diet. **Soleur already ran the diet the article prescribes**, three months
before the article existed. The productive output of this audit is four small,
mostly-mechanical fixes to the *instruments* that govern context — each of which is
currently misreporting — plus an explicit decision to reject two of the article's
prescriptions on grounds specific to Soleur.

The headline: Soleur's progressive-disclosure mechanism **exists and is 8.7% effective**,
while its own telemetry renders it as ~50% effective. Nobody knew, because the number
that would have said so is computed with a doubled denominator.

## Measured Current State

All figures re-derived in worktree `feat-context-engineering-audit` at `655eb012c`.

| Quantity | Value | How measured |
|---|---|---|
| Live rules | **101** | `grep -c '^- \[id: ' AGENTS.md`; bodies 53 core + 6 docs + 42 rest |
| Retired rules | **58** | distinct ids in `scripts/retired-rule-ids.txt` |
| Rules ever created | **159** | 101 + 58 → **36% already retired** |
| `B_ALWAYS` (gated) | **22,900 B** | `python3 scripts/lint-agents-rule-budget.py` → `[WARN]`, ceiling 23,000 |
| Real fail-open footprint | **43,513 B (~10.9k tok)** | AGENTS.md 6,072 + core 16,901 + docs 3,266 + rest 17,274 |
| Ratio real : gated | **1.89×** | the budget gate measures 53% of what actually loads |
| Skill-description budget | **2,400 / 1,800 words** | **exceeded by 33.3% (−600 words)**, 95 skills |
| Rule↔skill duplication | **0 of 10 sampled** | no core rule restated in any SKILL.md |
| Rule↔rule contradictions | **4** | CTO audit, 2 verified verbatim below |
| Rule↔skill drifts | **4** | incl. one literal inversion, verified below |
| Dead rule citations in skills | **4** | skills cite ids absent from `AGENTS.md` |

### The finding that reframes everything

`.claude/hooks/session-rules-loader.sh` selects classes as:

```bash
CLASSES="core"
if   [[ "${LOADER_FAIL_CLOSED:-}" == "1" ]]; then CLASSES="core docs-only rest"
elif [[ -z "$CHANGES" ]];                    then CLASSES="core docs-only rest"   # empty changeset
elif (( HAS_CODE + HAS_INFRA + HAS_DOCS > 1 )); then CLASSES="core docs-only rest" # multi-class
elif (( HAS_DOCS == 1 ));                    then CLASSES="core docs-only"
elif (( HAS_CODE == 1 || HAS_INFRA == 1 ));  then CLASSES="core rest"
fi
```

Classifying the last **80 squashed PRs on main** through that exact regex block:

| Session class | Loads | Count | Share |
|---|---|---|---|
| multi-class | all 3 — 43.5 KB | 55 | 68% |
| unclassified (fail-closed) | all 3 — 43.5 KB | 1 | 1% |
| docs-only | core+docs — 26.2 KB | 16 | 20% |
| code/infra-only | core+rest — 40.2 KB | 8 | 10% |

**70% of real Soleur work loads the entire corpus.** Weighted mean saving is
`0.20 × 17,274 + 0.10 × 3,266 = 3,782 B` — **8.7%**, not ~50%. The cause is structural,
not a bug: Soleur's own workflow gates mandate a learning/spec `.md` alongside code in
nearly every PR, which makes almost every PR multi-class by construction. Progressive
disclosure is defeated by the rules corpus's own inflow rules.

Additionally, `CHANGES` is empty on a clean tree, so **every session-start on a fresh
worktree or clean `main` also loads all three** — this session did.

### Why nobody noticed: the instrument is misreporting

`session-rules-loader.sh:247`

```bash
TOTAL_RULES=$(grep -hE '^- .*\[id: ' "$REPO_ROOT"/AGENTS*.md | wc -l)
```

The glob `AGENTS*.md` matches the **index plus all three bodies**, counting every rule
twice (one pointer + one body). So the stamp reads `loaded: … (101 of 202 rules)` — which
looks like 50% utilisation at a glance, when it is 100%. This is precisely the number an
operator would consult to ask "is progressive disclosure working?", and it answers
reassuringly and wrongly. Confirmed against `knowledge-base/project/learnings/2026-07-22-rule-metrics-denominator-investigation.md`
(#6794), which already established `202 = 2 × 101` as a category error in the sibling
metric — the same double-count survives here.

### The one anti-pattern Soleur *does* have: conflicting messages

The article's first-named anti-pattern is contradiction across system prompt, skills and
request. Soleur has it, and `scripts/lint-rule-ids.py` cannot see it — it validates id
integrity only, never semantics. Two verified verbatim:

**Rule ↔ rule.** `wg-when-an-audit-identifies-pre-existing` says *"create GitHub issues to
track them before fixing. Don't just note them in conversation — file them."*
`wg-when-deferring-a-capability-create-a` says *"default to **documenting it in-place** …
File a GitHub issue ONLY when the `wg-defer-only-after-inline-triage` triple test passes …
converting every Non-Goal to an issue creates phantom backlog."* An agent that finds a
pre-existing issue during an audit *and* elects to defer it receives opposite
instructions. The overlap is partial, not total — which is worse, because it surfaces
only in the ambiguous case where guidance is most needed.

**Rule ↔ skill — a literal inversion.** `hr-menu-option-ack-not-prod-write-auth`
`[compliance-tier]` says: *"show the exact command, wait for explicit per-command
go-ahead, THEN run with `-auto-approve`/`--yes`/`--force`."* But
`plugins/soleur/skills/ship/SKILL.md:821` says *"Do NOT pass `-auto-approve`"* — **citing
that same rule id** — and `admin-ip-refresh/SKILL.md:42` says *"no `--yes`, no
`-auto-approve`, per AGENTS.md `hr-menu-option-ack-not-prod-write-auth`."*

This is not cosmetic. The rule's ack-then-`-auto-approve` design exists *because* the Bash
tool is non-interactive (`hr-the-bash-tool-runs-in-a-non-interactive`). Following the
skills instead of the rule makes the command block on a TTY prompt nothing can answer —
producing exactly the operator-blocking stall that Soleur's "never defer to the operator"
posture exists to prevent.

## Prescription-by-Prescription Verdict

| Article prescription | Soleur's primitive | Automation | Verdict |
|---|---|---|---|
| Replace rules with judgment | **discoverability litmus**, landed in `wg-every-session-error-must-produce-either`; 58 rules retired via allowlist | **full** | **Already done.** Independently invented 2026-04-23, precedent from 2026-02-25. No action. |
| Progressive disclosure | change-class loader + 3 sidecars | **partial — 8.7% effective** | **Real gap.** Mechanism present, rarely fires. See decisions. |
| Instructions in exactly one place | rules cite skills by `[id:]`; bodies not restated | **full** | 0 duplication in sample. No action. |
| No conflicting messages | `lint-rule-ids.py` — id integrity only | **none semantically** | **Real gap.** 4 rule↔rule, 4 rule↔skill (one a literal inversion), 4 dead citations. Nothing audits this. |
| Design tool interfaces, not examples | skill `description:` frontmatter | **partial — over budget** | **Real gap.** 2,296/1,800 words. |
| Auto-memory over manual files | `hr-never-write-to-claude-code-memory-claude` (hook-enforced) | **deliberately inverted** | **Reject.** See below. |
| Rich references over markdown specs | ATDD (`cq-write-failing-tests-before`), `.pen` wireframe gate, eval-harness | **substantially done** | Largely already satisfied. |

### The dividing line the article does not draw

The article's advice targets **judgment guidance** — "never write multi-paragraph
docstrings" — which a stronger model can now infer from context. Soleur's surviving 101
rules are overwhelmingly a different category: **environment facts the model cannot
infer at any capability level.** Warp intercepts terminal escape sequences.
`SENTRY_AUTH_TOKEN` 403s where `SENTRY_IAC_AUTH_TOKEN` works. `dev` and `prd` must
resolve to distinct Supabase refs. A smarter model does not thereby learn that your
Sentry token is misprovisioned.

This is the (a)/(b) split the operator asked for, and it explains why the corpus already
shrank 36% and then stopped: the discoverability litmus **already removed the
judgment-expressible rules.** What remains is mostly irreducible. Applying the article
again to this residue would delete environment facts and call it unhobbling.

### Direct counter-evidence to the thesis, as applied to Soleur

Soleur has been through model upgrades before. `knowledge-base/project/brainstorms/2026-04-16-model-upgrade-opus-4-7-brainstorm.md`
records the Opus 4.6→4.7 upgrade: **zero rules retired as obsolete, zero rules added for
model-specific failure modes.** Soleur has never once observed model-version-dependent
rule necessity. "The model is smarter now" has no track record here as a reason to delete
a guardrail, and no Soleur-specific A/B evidence exists either way.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Run a rules-deletion campaign | **No** | 36% already retired; residue is environment facts, not judgment guidance. #6794 independently forbids pruning on `rules_unused_over_8w` (fragmentation under-count). |
| Fix loader denominator (`:247`) | **Yes — first** | One-line glob fix. The instrument that measures every future decision here is wrong by 2×. Zero behaviour change. |
| Publish the real fail-open rate | **Yes** | 8.7% effective vs ~50% implied. Make the stamp report the loaded/total *bytes*, not just rule count. |
| Re-cut the class axis | **No — not yet** | Would be a large change premised on the same broken instrument. Fix the instrument, observe, then decide. Explicitly deferred. |
| Skill-description budget breach | **Yes — fix** | 33% over an existing enforced cap; the article's "tool interface" surface. |
| Resolve the 12 conflicts/drifts | **Yes** | The article's #1 anti-pattern, live. The `-auto-approve` inversion has an operator-blocking failure mode. |
| Hook-enforced rule prose | **Trim to one line, never delete** | Redundant *as enforcement* (the hook blocks), load-bearing *as explanation* — the deny message cites the id; without prose the agent is blocked without knowing why and routes around it. |
| Rule-vs-skill drift auditor | **Defer — file as capability gap** | No agent or skill audits rule↔skill semantics today; that absence is why all 12 are live. |
| `rule-prune.sh` compliance exemption | **Yes — fix** | `scripts/rule-prune.sh:167` gates only on `[hook-enforced]`/`[skill-enforced]`; it can propose retiring rules cited by the Art. 30 register. Latent compliance bug. |
| Dangling register citation | **Yes — fix** | `article-30-register.md:417` cites `hr-block-pr-ready-…`; real id is `wg-`. Already broken today. |
| Adopt auto-memory | **No** | CC memory is machine- and operator-local. Soleur's moat is portable cross-operator knowledge. Rejecting is correct, not a defect. |
| `claude doctor` | **Advisory only** | Would flag `AGENTS.md` size and skill descriptions. It cannot see hook-injected sidecars, so it would report the 6 KB index and miss 37 KB — reproducing the exact blind spot found here. |

### What must NOT be churned

- The **61 `**Why:** #NNNN` incident-derived rules** — each encodes a realised failure.
- The **`[compliance-tier]` rules**. CLO found live citations in `knowledge-base/legal/article-30-register.md`
  (`:62, :198, :214, :230, :304, :321, :324, :364, :453`), `compliance-posture.md`, a DPA,
  and — decisively — **`docs/legal/data-protection-disclosure.md:12`, a published
  user-facing document**, cites `cq-pg-security-definer-search-path-pin-pg-temp` by id.
  Deleting these silently voids a stated Art. 32 technical measure. **PROHIBITED.**
- The **loader's fail-closed default**. Failing open to all rules is the safe direction;
  the finding is that it is *common*, not that it is wrong.
- **`hr-*` demotion.** Only `wg-*` may move core→rest (CPO sign-off, PR #3496). PR #3681
  showed a demotion silently disabling a rule for its own trigger class.

## Open Questions

- Is 8.7% worth preserving the three-sidecar split at all? A single always-loaded corpus
  would be simpler and cost ~4 KB more in the 30% of sessions that currently benefit.
  Answerable only after the instrument is fixed.
- Should the inflow rules that force `.md` into every PR be relaxed so more sessions are
  genuinely single-class? This trades corpus governance against loader effectiveness —
  a real tension, not obviously resolvable in either direction.
- Do the 11 shipped plugin files referencing root-only `AGENTS.core.md` /
  `session-rules-loader.sh` / `scripts/lint-agents-rule-budget.py` degrade silently for
  downstream operators? `compound` step 8 and `grok-fidelity-gate.sh` both invoke them.
  Marketplace scope is `./plugins/soleur` (`.claude-plugin/marketplace.json:18`), so those
  paths do not exist in an installed tenant repo. Separate issue.

## User-Brand Impact

- **Artifact:** the `session-rules-loader` stamp and the AGENTS rules corpus — the
  governance instruments that decide which safety rules are in context for every session.
- **Vector:** an instrument that overstates coverage by 2× can license a future rules cut
  that silently removes a compliance control from context at the moment the risky action
  runs; the resulting failure is invisible until a user's data or production state is
  already affected.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Engineering, Product, Legal. (Marketing, Operations, Sales, Finance,
Support: not relevant — no user-facing surface, pricing, or vendor change.)

### Engineering
Progressive disclosure is implemented but near-inert: independently measured at 68%
multi-class over 80 PRs (orchestrator) and 72% over 200 commits (CTO), plus synthetic-tree
runs confirming clean-on-main → `101 of 202`, docs-only → `59`, code-only → `95`,
mixed → `101`. Realistic fail-open rate **75–85%** once clean-tree and question-only
sessions are counted. The loader's utilisation stamp is computed with a doubled
denominator and reads 50% when it means 100%. `B_ALWAYS` sits at 22,900 of a 23,000
REJECT ceiling — **100 bytes of headroom**, so the next core rule fails CI.

**Verdict on the 80% headline: it does not transfer. A defensible target is 15–25%**,
concentrated in generic-behaviour rules now enforced by the tools themselves
(`hr-always-read-a-file-before-editing-it` is enforced by the Edit tool;
`hr-the-bash-tool-runs-in-a-non-interactive` is model-known) and in trimming
hook-enforced prose. The distinction that decides it:
**Claude Code's system prompt described *the tool*; Soleur's rules describe *the world the
tool acts on*.** No model's judgment reconstructs "#5736's dedup INSERT was 63% of prod
WAL". The article's *diagnosis* transfers completely; its *prescription* mostly does not.

**Capability gap:** nothing audits rule↔skill semantic drift. `lint-rule-ids.py` validates
id integrity only — which is precisely why 4 contradictions, 4 drifts and 4 dead citations
are live and undetected. Belongs to engineering; filed as follow-up.

**Architecture decision required** if the classifier axis is ever re-cut (deferred here):
excluding `knowledge-base/**` from `DOCS_RE` would move most multi-class sessions into
`core+rest`, saving ~17 KB on ~70% of sessions — but a docs rule silently missing is
exactly PR #3681's failure mode, so it needs an ADR, not a patch.

### Product
Cost falls entirely on the founder, not on target users: `scaffoldWorkspaceDefaults()`
writes no `AGENTS*` files, so cloud users receive none of this corpus, and ~11k tokens
against a large window sits in the cache-stable prefix. With beta users at 0 and Phase 4
gating on founder recruitment, a harness-refactor week is direct opportunity cost.
Recommendation: take the mechanical instrument fixes; defer anything structural.

### Legal
Deleting register-cited rules is **PROHIBITED** — nine `article-30-register.md` citations
plus a published DPD statement depend on specific rule ids. Rewriting as judgment-prose
while retaining the id and the named mechanism is **PERMITTED-WITH-GUARDRAILS**. Moving
`[compliance-tier]` rules to progressive disclosure is **PROHIBITED** — a control absent
from context when the risky action fires is worse than no control. Two fixes are
warranted regardless of this brainstorm's outcome: the `rule-prune.sh` compliance
exemption and the dangling `:417` citation.

## Session Errors

1. **My routing brief asserted "202 rules" and "101 of 202 loaded ≈ 50%".** Both wrong;
   the corpus is 101 and the session loaded 100%. Root cause: I read the loader's stamp,
   which is itself miscomputed. Corrected before it reached the artifacts, but it had
   already been sent to two subagents and required in-flight correction. The error is
   the finding — the instrument misleads its readers, including this brainstorm.
2. **Learnings-researcher returned 3-month-stale recommendations** ("land PR #2762",
   "adopt the discoverability litmus") — both shipped in April. Verified independently
   against `scripts/retired-rule-ids.txt` before use. Agent reports on governance state
   need a landed-vs-proposed check.
3. **CPO reported 103 retired ids and "116 shipped files"**; actual 58 and 11. It counted
   file lines and broad rule-id mentions respectively. Both corrected by direct count.
4. **Roadmap drift, not fixed here:** `roadmap-reconcile.sh validate` reports
   `STALE_STATUS|phase 4|roadmap=56o/179c|milestone=72o/187c`. Left unmodified — an
   unrelated roadmap edit does not belong in this PR. Fix path is
   `/soleur:trigger-cron cron/roadmap-review.manual-trigger`.
