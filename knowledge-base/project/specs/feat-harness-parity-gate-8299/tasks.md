---
title: Tasks — cross-harness negative-space invocation gate
feature: feat-harness-parity-gate-8299
date: 2026-09-18
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-09-18-feat-harness-parity-census-plan.md
closes: 8299
---

# Tasks

> # ⛔ BLOCKED — do not execute these tasks
>
> These tasks derive from **plan v2**, which all three v2 reviewers refuted on
> 2026-09-18. Executing them would ship a gate that certifies 5 docs clean while
> they dispatch grok-only, and would reword ~174 correct sites.
>
> **Why v2 failed:** its predicate is a *blocklist* of harness-specific forms.
> AP-025 / ADR-202 — "a state predicate is complete by construction; a list of
> ways to reach it cannot be proven complete" — and the proof is that the token
> set omitted `formatSkillInvocation`'s grok branch (`` `/${name}` ``, harness.ts:129),
> a form defined eight lines from one it captured. 225 occurrences, 26 docs,
> 5 docs violating only via it.
>
> **What v3 must be** (design settled, not yet written):
> an **allowlist** predicate — every skill reference matches canonical
> `soleur:<known-name>`, checked against the 98-name index the population already
> enumerates. Complete by construction. Plus: a per-doc census vector rather than
> scalar pins (`inFence` is defeated by a compensating swap); anchor-scoped
> exemptions for adapter-teaching regions, or generate `go.md`'s Step 2.0 table
> from `routingInstructions()` so the ledger is genuinely empty; an allowlist of
> sanctioned marker-block names; fences scanned, not stripped (16 are dispatch
> payloads, including the mandatory resume prompt at `brainstorm/SKILL.md:604`);
> ADR-**227**, not 226.
>
> Full findings: the plan file's `## v2 review complete (3 of 3)` section (H1-H12)
> and `## v2 review — BLOCKING` (G1-G9).


Derived from **plan v2** (the plan of record). v1's design is retained in the plan file as the
review record only — do not implement it. The v1 census scored `ship/SKILL.md`, `gdpr-gate`,
`product-roadmap` and `incident` QUALIFIED while they still dispatched Claude-only, and its
trigger floor went inert the moment its own backfill ran.

**Baseline to reproduce before starting** (from inside this worktree):

- population **101** — `git ls-files 'plugins/soleur/skills/*/SKILL.md' 'plugins/soleur/commands/*.md' | wc -l`
- in violation **45 docs / 175 occurrences**; compliant **56**; in-fence **38**
- `/soleur:` **205** total → **57** commands (legitimate, ADR-224) + **135** skills (violations)

## Phase 1 — Prerequisites (no gate yet)

- [ ] 1.1 Write `plugins/soleur/grok/INSTRUCTIONS.md`, mirroring the tool-mapping table in
      `plugins/soleur/codex/INSTRUCTIONS.md`. Grok is the only harness with no shipped mapping doc,
      so "the adapter resolves the canonical token" is not yet true on all four. **Prerequisite for
      the whole approach** — do not start Phase 2 without it.
- [ ] 1.2 In `plugins/soleur/lib/harness.ts`: add `export const SUPPORTED_HARNESSES = ["claude","grok","codex","devin"] as const;`
      and derive `export type Harness = typeof SUPPORTED_HARNESSES[number] | "unknown";`.
      **`as const` is load-bearing** — without it the type degrades to `string` and nothing catches
      it, because nothing typechecks `plugins/`. Retain `| "unknown"` (`detectHarness` returns it at
      `:113`; there are `default:` arms at `:393` and `:463`).
- [ ] 1.3 Export the harness-specific token set from `harness.ts`, adjacent to
      `formatSkillInvocation` (`:120-140`) and `formatAgentSpawn` (`:212-245`) — the functions that
      *define* the forms. One source, so V3 holds.
- [ ] 1.4 Add a `never` exhaustiveness arm to `routingInstructions` and `pollInstructions`, so a
      fifth harness fails to compile until the adapter implements it. Today both fall through to
      `default:` and silently return Claude conventions.
- [ ] 1.5 Repoint **only** `plugins/soleur/test/workflow-fidelity.test.ts:373` at
      `SUPPORTED_HARNESSES`. **Do NOT touch `harness-model-map.test.ts:76`** — its
      `["claude","grok"]` is deliberate (`TIER_MAPS` has two keys) and widening it would pass
      vacuously via the unmapped `"inherit"` fallback.
- [ ] 1.6 Add a minimal tsconfig for `plugins/soleur` and confirm `npx tsc --noEmit` passes.
      This is a new capability — nothing typechecks `plugins/` today (`grep -c tsc scripts/test-all.sh` → 0).

## Phase 2 — Mutation matrix, then the gate (RED)

- [ ] 2.1 Write the v2 Guard Contract matrix (N1–N9, H1–H4) into
      `plugins/soleur/test/harness-parity.test.ts` as a header comment, **before** the assertions.
- [ ] 2.2 Implement the census: population from `git ls-files` over both globs, **injectable root**
      so the matrix is runnable; strip sanctioned marker blocks and fenced code; assert zero
      harness-specific skill-invocation tokens in the remainder.
- [ ] 2.3 Exempt `/soleur:{go,help,sync}` by construction — commands, not skills (ADR-224).
- [ ] 2.4 Failure output must name, per offending doc: **token, line, the harness it is specific
      to, and the canonical replacement.** A path list is a scoreboard, not a remediation.
- [ ] 2.5 Confirm RED with exactly **45 docs / 175 occurrences**. A green first run means the token
      set is wrong.

## Phase 3 — Ledger and fixtures

- [ ] 3.1 Create `plugins/soleur/test/harness-parity-exempt.tsv` (flat beside the test, matching
      the `fixture-*-assert.baseline.txt` precedent — **not** under `fixtures/`). State the column
      list explicitly: `path⇥disposition⇥date⇥issue⇥reason⇥evidence`, `#` comments, closed
      disposition enum. The `devin-dispositions.tsv` precedent has **no** date or issue column, so
      this is a documented divergence, not an inherited shape.
- [ ] 3.2 Add the real rows: `go.md`'s Step 2.0 adapter table and the per-harness
      `INSTRUCTIONS.md` files legitimately enumerate harness forms — that is their purpose.
- [ ] 3.3 Strict, fail-closed parsing: a missing, unreadable or malformed ledger, an unrecognised
      disposition, or a row naming a path outside the population is **RED**. Never a silently empty
      exemption set (constitution L139/L140).
- [ ] 3.4 Add the decoy fixtures N3/N6/H2/H3 need. Read the ledger inside its **own** `test()`, not
      shared setup, so a missing input REDs one case rather than throwing before the census runs.
- [ ] 3.5 Add the single exact-snapshot assertion:
      `expect(census).toEqual({ population: 101, violations: 0, exempt: <n>, inFence: 38 })`.

## Phase 4 — Canonicalise (GREEN)

- [ ] 4.1 Rewrite the 175 occurrences across 45 docs to bare `soleur:<name>`. These are
      **deletions** of a harness-specific prefix, not insertions of boilerplate.
- [ ] 4.2 Start with the top offenders: `commands/go.md` (25), `gdpr-gate` (17), `work` (11),
      `plan` (10), `brainstorm` (9), `linear-fetch` (9), `plan-review` (9), `one-shot` (8).
- [ ] 4.3 `commands/go.md` needs care — its Step 2.0 adapter table is ledger-exempt (H3) while its
      prose instructions are not. Do not blanket-rewrite the file.
- [ ] 4.4 Verify `plugins/soleur/skills/trigger-cron/SKILL.md` needs **no** change (already 0).
- [ ] 4.5 Confirm the snapshot goes green and `devin-cloud-mode.test.ts` still reports
      `marked.length == 67` with **`UNION` intact**.

## Phase 5 — Authoring surface, ADR, records

- [ ] 5.1 Add one line to `plugins/soleur/skills/skill-creator/SKILL.md` naming the obligation and
      the canonical form. v1 closed the `AGENTS.rules.md` and convergent-bullet routes without
      opening any other, leaving the RED test as the only teaching surface.
- [ ] 5.2 Author `ADR-226`. Re-derive the ordinal **ref-wide** first: two branches already claim
      ADR-225 (`feat-one-shot-adr142-…`, `feat-pluggable-web-agent-engines`), so 226 is contended.
      If it moves, sweep the plan, spec, tasks and every AC naming it in the same edit.
- [ ] 5.3 Record in the ADR: the negative-space inversion and why the presence census failed; the
      token set's single source; the `never` arm; and the honest limit — **the gate asserts
      form-consistency, not form-correctness**, since only grok (`ci.yml:1320`) and claude have
      live invocation verification.
- [ ] 5.4 File the agent-docs issue (68 docs, 8 with Claude-only spawn prose) — same defect class,
      separate population, NG1.
- [ ] 5.5 Update the brainstorm and the learning so their figures match the shipped gate.

## Phase 6 — Verification

- [ ] 6.1 Run V-AC1 through V-AC14 from the plan; record one evidence line each.
- [ ] 6.2 N1–N9 must RED **with the census sentinel on stdout**, not merely a non-zero exit —
      ADR-193's mutation oracle asserts the reason, not the exit code. N9 must fail at **compile**
      time via 1.6's tsconfig.
- [ ] 6.3 `git fetch origin main && SOLEUR_ALLOW_FULL_GATE=1 bash scripts/test-all.sh` green.
- [ ] 6.4 Note for `/work`: Phase 2 commits a deliberately-RED test and Phase 4 lands 45 doc
      edits, while `lefthook.yml:311` runs the full battery on any `.ts` and `:333` on any
      `plugins/soleur/**/*.md`. Sequence Phase 2's RED state and Phase 4's backfill so the gate is
      green at each commit boundary, or land the backfill as one commit.

## Out of scope — do not fold in

`#7453` (~105 `${CLAUDE_PLUGIN_ROOT:-…}` sites) · `#8306` (mirror completeness) ·
`#8307` (helper extraction) · `#8308` (`/soleur:go` session gates) · the new agent-docs issue.
Use `Ref #N`, never `Closes`.
