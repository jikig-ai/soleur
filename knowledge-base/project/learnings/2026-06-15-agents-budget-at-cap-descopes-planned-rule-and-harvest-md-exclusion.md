---
title: "AGENTS always-loaded budget at cap silently descopes a planned new rule; harvest scopes by *.md exclusion not per-file denylist"
date: 2026-06-15
category: workflow-patterns
tags: [agents-md, rule-budget, planning, one-shot, harvest-debt, yagni, grep-tooling]
symptoms:
  - "lint-agents-rule-budget.py [REJECT] B_ALWAYS=23053 > 23000"
  - "plan prescribed an AGENTS.docs.md cq-* rule + AGENTS.md pointer that could not land"
module: AGENTS.md, plugins/soleur/skills/plan, plugins/soleur/skills/harvest-debt
---

# Learning: AGENTS budget-at-cap descopes a planned rule; harvest scopes by `*.md` exclusion

## Problem

A two-item PR (PR #5349) added a YAGNI minimalism-ladder principle (ITEM ONE) and a new
`harvest-debt` skill (ITEM TWO). The plan for ITEM ONE prescribed BOTH a constitution body
AND an `AGENTS.docs.md` `cq-minimalism-ladder-generation-bias` rule with an `AGENTS.md`
index pointer. At /work time, adding the index pointer pushed the **always-loaded** payload
(`AGENTS.md` index + `AGENTS.core.md`) from 22994 to 23053 bytes — over the 23000-byte
critical cap — and `scripts/lint-agents-rule-budget.py` rejected the commit.

`scripts/lint-rule-ids.py` (`lint_union`) enforces pointer↔body 1:1, so the docs-sidecar
body and the always-loaded index pointer are **coupled**: you cannot keep the cheap
docs-class body without also paying the always-loaded pointer cost. Main had only **6 bytes**
of headroom (22994/23000), so any new rule pointer was unaffordable without demoting an
unrelated `wg-*`/core rule to `AGENTS.rest.md`.

## Solution

**Descope the AGENTS rule; ship ITEM ONE as the constitution body only.** The brief had made
the AGENTS pointer conditional ("if that matches the established pattern") — and the
established pattern is a budget at capacity. The constitution `## Code Style` section is the
canonical home that `/plan`, `/work`, and `/brainstorm` already read on demand. Forcing an
unrelated core-rule demotion in a YAGNI-ladder PR would be scope creep in a high-collision
file. Removed the now-dangling `cq-minimalism-ladder-generation-bias` reference from the
constitution body, reverted both AGENTS edits (so the sidecars are byte-identical to main),
and annotated the plan's AC2 as descoped.

## Key Insight

1. **Before a plan prescribes a NEW `AGENTS.md`/sidecar rule, check `B_ALWAYS` headroom** the
   same way the plan already checks the skill-description word budget. At-cap (≤ ~60 bytes
   slack) means a new rule pointer cannot land without an explicit, separately-justified
   demotion — so either (a) prescribe the demotion in the plan, or (b) place the principle in
   the constitution / owning artifact only. `B_ALWAYS = wc -c AGENTS.md + wc -c AGENTS.core.md`;
   critical cap is 23000.

2. **A new repo-wide grep tool scopes by file-CLASS, not a per-file denylist.** `harvest-debt`
   greps source for `SOLEUR-DEBT:` markers; the convention examples live in markdown (SKILL.md,
   plans, specs, the ledger README). Excluding `*.md` wholesale (markers are CODE-comment
   annotations, never prose) is simpler and self-maintaining versus the plan's narrower
   "exclude the one convention doc" denylist, which would silently self-report every other
   `.md` that quotes the marker. Pair with a concatenated marker literal in the test file
   (`"SOLEUR-DEB""T:"`, the digest-scrub push-protection idiom) so the test fixtures are not
   themselves harvested, and `cd "$(git rev-parse --show-toplevel)"` so repo-root-relative
   exclude pathspecs hold from any CWD.

3. **Anchor a `git grep -n` field-peel on the `:<digits>:` boundary**, not the first two
   colons — a colon WITHIN a path otherwise mis-peels file/lineno. The lineno is always
   numeric, so `match($0, /:[0-9]+:/)` is the robust split (caught by two orthogonal review
   agents).

## Session Errors

- **one-shot `#N` collision false-positive** — "ITEM #3"/"ITEM #2" matched real closed issues
  #3/#2; the gate would have aborted. **Recovery:** re-invoked with `#` scrubbed
  ("ITEM ONE"/"ITEM TWO"). **Prevention:** already covered by the `/soleur:go` "scrub closed
  `#N` contextual citations before invoking one-shot" sharp edge — when constructing one-shot
  args from a numbered report, never carry the `#`.
- **Constitution path drift** — brief/CC-MEMORY said `knowledge-base/overview/constitution.md`;
  real path is `knowledge-base/project/constitution.md`. **Recovery:** planning subagent
  re-derived via `find`. **Prevention:** deepen-plan premise-validation already treats
  plan-quoted paths as preconditions to verify; the stale pointer lives in machine-local CC
  memory (out of repo scope).
- **AGENTS budget at-cap rejected the planned rule** — see body. **Recovery:** descoped to
  constitution-only. **Prevention:** plan/deepen-plan should check `B_ALWAYS` headroom before
  prescribing a new AGENTS rule (routed to the plan skill this session).
- **`sync-readme-counts.sh` path drift** — plan said `plugins/soleur/skills/release-docs/scripts/`;
  actual is repo-root `scripts/`. **Recovery:** `find`. **Prevention:** covered by
  `hr-when-a-plan-specifies-relative-paths`.
- **shellcheck SC2181 + colon-path awk** — review-caught, fixed inline. One-offs.
- **git push non-fast-forward** — rebase rewrote the placeholder init-commit base.
  **Recovery:** `--force-with-lease`. **Prevention:** expected when rebasing a fresh
  draft-PR branch; one-off.

## Tags

category: workflow-patterns
module: AGENTS.md, plan, harvest-debt
