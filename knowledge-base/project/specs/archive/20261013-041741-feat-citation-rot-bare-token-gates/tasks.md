---
title: "Tasks — mechanical gates for citation-rot + bare-token body-grep"
date: 2026-07-16
issue: 6517
pr: 6527
branch: feat-citation-rot-bare-token-gates
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-16-feat-citation-rot-bare-token-gates-plan.md
---

# Tasks

Derived from plan **v2** (v1 was reversed by a 7-agent review panel — read the plan's
`## Plan Review Findings` and `## Research Reconciliation` before starting).

**Shape:** PR A ships **rung 2** (session-injected rules) for both classes + ADR-116. PR B
(the Class A gate) is **HELD** behind a replay AC — v1's detector measured 50/300 commits
denied at 57% false hits, and would have denied `main`'s own HEAD.

**Not "always-loaded".** `AGENTS.rest.md` is **class-gated**, not always-loaded: only
`AGENTS.md` + `AGENTS.core.md` are always-loaded (`lint-agents-rule-budget.py`'s `B_ALWAYS`),
and `session-rules-loader.sh` injects `CLASSES="core rest"` on code/infra sessions but
`CLASSES="core docs-only"` on docs-only ones. The rung-2 argument is *narrower* than v1
claimed and still sufficient — `rest` is exactly the class that writes code comments and
test assertions. This claim was load-bearing for the ADR's "rung 2 was never tried"
argument, so it is stated at its real strength.

---

## Phase 1 — Setup

- [ ] **1.1** Confirm worktree + branch: `.worktrees/feat-citation-rot-bare-token-gates`,
      branch `feat-citation-rot-bare-token-gates`, draft PR #6527. Never read from the bare
      repo root.
- [ ] **1.2** Record the pre-change budget baseline:
      `python3 scripts/lint-agents-rule-budget.py` → expect `B_ALWAYS=22795`, exit 0.
      This is the number AC3 moves.

## Phase 2 — PR A: ADR + both rules (SHIP NOW)

### 2.1 ADR-116

- [ ] **2.1.1** Author `ADR-116-content-anchored-citations-in-code-comments.md` via
      `/soleur:architecture`. Ordinal is **provisional** — re-verify the next free ordinal
      against `origin/main` at ship (115 is max as of planning).
- [ ] **2.1.2** Decision items: (1) content-anchored citations repo-wide, generalizing
      ADR-076 item 3; (2) any enforcement ships born-blocking, never advisory-first;
      (3) enforcement is **not yet built** — held pending the replay AC.
- [ ] **2.1.3** Alternatives Considered: validate-resolvability (rejected — a coordinate
      carries no content assertion; the #6479 decoy passes it), advisory-first (rejected —
      #4270 open 56d/0 findings; 0 promotions ever), amend-ADR-076 (rejected — its subject
      is the drift extractor; its line-number rejection was for spurious diffs, not comment
      rot).
- [ ] **2.1.4** Include a `## C4 impact` section mirroring ADR-076's. Content: **none** —
      `hooks` container already modeled as a leaf; no external actor, system, or access
      relationship changes.
- [ ] **2.1.5** Consequences: convention stated + unenforced until the gate clears AC-B1;
      the ~360 existing citations are grandfathered permanently. State the figure **with the
      command that reproduces it** — a prose predicate does not pin a count (18 readings of
      the earlier stated predicate spanned 319–583 and none produced the `403` it claimed).

### 2.2 Rule — `cq-cite-content-anchor-not-line-number` (Class A convention)

- [ ] **2.2.1** Pointer in `AGENTS.md` Code Quality:
      `- [id: cq-cite-content-anchor-not-line-number] → rest`.
      **No bracket tag** — zero existing pointers carry one, and the tag cost 54 B of a
      ~205 B budget (Kieran P1/P2).
- [ ] **2.2.2** Body in `AGENTS.rest.md` (≤600 B; **as-shipped 558 B** — the 492 B figure
      was a v1 draft, superseded by the carve-out text). MUST carry the
      no-symbol carve-out: where no symbol exists (`.tf`, `.yml`, `.toml`) a line citation
      is permitted — there is no anchor to prefer. This is what makes the convention
      followable (CTO F2: infra is where citations concentrate).

### 2.3 Rule — `cq-assert-anchor-not-bare-token` (Class B — the 10× class)

- [ ] **2.3.1** Pointer in `AGENTS.md` Code Quality:
      `- [id: cq-assert-anchor-not-bare-token] → rest`. No bracket tag.
- [ ] **2.3.2** Body in `AGENTS.rest.md` (≤600 B; **as-shipped 595 B** — 443 B was a v1
      draft; 534 B predates the P2-1 carve-out clause + P2-2 sub-attribution. Only 5 B of
      headroom: re-measure, never retype, after any edit). Requires: anchor on
      `^\s*` or a call-form a comment cannot produce; mutation-test every new assertion.
      Cite #6479 (6×) and #6456 (4×).

### 2.4 Correct the propagated `10×` error (misinformation — do not skip)

The 10 recurrences are **all Class B**. Class A recurred **once** against ~360 citations
(~0.28%). The figure was propagated as justification into five artifacts.

- [ ] **2.4.1** `knowledge-base/project/specs/feat-citation-rot-bare-token-gates/spec.md` —
      correct the Problem Statement attribution; correct **TR6** (fail-closed → the hook
      fails open; TR6b = never *silently* self-disable).
- [ ] **2.4.2** `knowledge-base/project/brainstorms/2026-07-16-citation-rot-bare-token-gates-brainstorm.md`
      — correct the attribution in Why This Approach.
- [ ] **2.4.3** `knowledge-base/project/learnings/2026-07-16-advisory-first-precedent-is-a-claim-to-measure-and-a-coordinate-citation-carries-no-claim.md`
      — correct the attribution; add the v1-reversal as a Session Error.
- [ ] **2.4.4** **`gh issue edit 6517`** — the issue body's "Scope reshaped" section claims
      the recurrence for both classes. Correct it. Leaving it is publishing a wrong number.

### 2.5 Verify PR A

- [ ] **2.5.1** `python3 scripts/lint-agents-rule-budget.py` → exit 0, `B_ALWAYS < 23000`
      (expect ~22897 after two tagless pointers).
- [ ] **2.5.2** `python3 scripts/lint-rule-ids.py` → exit 0 (pointer↔body residency;
      `lint_union` couples them 1:1).
- [ ] **2.5.3** `python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"`
      → exit 0, **no ack required** (`GATED_PREFIX_RE = ^(hr|wg)-`; `cq-*` is ungated).
      Base MUST be the merge-base, not `origin/main` tip.
- [ ] **2.5.4** `bash scripts/test-all.sh` → green.
- [ ] **2.5.5** Re-verify the ADR ordinal against `origin/main`. **If renumbered, sweep the
      plan + this tasks.md + every AC naming the ordinal in the same edit** (#5990: a
      renumber left an AC asserting a nonexistent file).

### 2.6 #6529 follow-up

- [ ] **2.6.1** Comment on **#6529** recording that its promotion trigger is **not**
      mechanical, with the day-0 evidence (v1's `git log --since=<ship-date> … grep
      vacuous-assertion` returns the two learnings that motivated this plan, both dated the
      ship date; `--since` is commit date; `--name-only` re-fires on any later touch; and
      nothing runs it). The demonstrated mechanism is `/compound`, which caught the class
      twice in two days with no trigger. Do not let the next author re-derive the broken grep.

## Phase 3 — Ship PR A

- [ ] **3.1** `/soleur:review` (user-impact-reviewer fires — threshold is
      `single-user incident`).
- [ ] **3.2** `/soleur:compound` — the v1→v2 reversal is the session's largest learning.
- [ ] **3.3** `/soleur:ship`. PR body: `Ref #6517` (do **not** `Closes` — PR B is still
      outstanding on the same issue). Label `semver:patch` (docs/rules only).

---

## Phase 4 — PR B: the Class A gate (HELD — do not start until PR A merges)

**Gate on the gate.** Do not open PR B until **AC-B1** passes.

- [ ] **4.1** Implement the detector per the plan's PR B design of record:
  - [ ] **4.1.1** Surface: `lefthook.yml` `pre-commit` (the `gitleaks-staged` shape) —
        harness-independent + blocking. **Not** a PreToolUse hook, **not** a CI job.
        Accepted trade-off: `--no-verify` bypasses lefthook.
  - [ ] **4.1.2** Cited-extension allowlist
        `\.(ts|tsx|js|mjs|cjs|jsx|sh|bash|py|sql):[0-9]+(-[0-9]+)?` — kills
        `127.0.0.1:6379`, `4.5:1`, `.tf`/`.yml` targets.
  - [ ] **4.1.3** Strip `https?://` **before** comment-tail extraction (`http://` is the TS
        comment marker — Kieran P0; `postgres://u:p@127.0.0.1:54322/db` denied a line with
        no comment).
  - [ ] **4.1.4** Move tolerance: a `+` line whose identical text exists in the pre-image is
        not new — or drop the "move-scoped" claim. Required before G4/AC3 are true.
  - [ ] **4.1.5** Recovery (ADR-071's dropped half): named kill switch
        (`SOLEUR_CITE_LINE_EXT_RE=^$` → empty scope → allow), **named in the deny reason**,
        + a baseline of pre-existing violations. The agent — never the operator — owns
        recovery.
  - [ ] **4.1.6** Deny reason names the **waiver** (`cite-line:allow # issue:#N`), not just
        the alternative.
  - [ ] **4.1.7** Explicit fail when `jq` is absent — never a silent universal allow (TR6b).
  - [ ] **4.1.8** `exit 2` (internal error) → allow, stated explicitly (`set -uo pipefail`,
        not `-e`).
  - [ ] **4.1.9** Fixtures build comment markers by concatenation (`H='#'`) — v1's AC7 and
        its AC1 fixture family were mutually contradictory (Kieran P0).
- [ ] **4.2** **AC-B1 (blocking):** replay over the last 300 commits of `main`. Ship only if
      **≤3/300 denied** AND every denial is a true citation with an available content
      anchor. Record the measured numbers in the PR body. v1 scored 50/300 at 57% false.
- [ ] **4.3** Re-derive PR B's remaining ACs from scratch. **Do not carry v1's AC set
      forward.**

---

## Notes

- **Reuse, do not re-derive** (all verified sound): `brand-hex-commit-gate.sh`'s `git commit`
  trigger regex, its `-a`-aware `NAME_REF` block **including the quoted-arg strip**, and its
  awk hunk-walker. Do **not** copy its hook-name `emit` (orphan-gate trap) — the aggregator
  carves out only `te-*`, `gdpr-gate-*`, `context-reviewed-*`, and pencil ids, and exits 5.
- **Orphan-suite trap:** `scripts/*.test.sh` is **not** in `test-all.sh`'s auto-discovery
  glob (which covers `scripts/lib/*.test.sh`); siblings need an explicit `run_suite` line.
  `.claude/hooks/*.test.sh` **is** auto-discovered. Moot for PR A; live for PR B.
- **Waiver precedent is real** (a review claim to the contrary was rejected):
  `.gitleaks.toml` documents `# gitleaks:allow # issue:#NNN <reason>`, exercised in
  `canary-bundle-claim-check.test.sh` and `redaction-allowlist.test.ts`.
