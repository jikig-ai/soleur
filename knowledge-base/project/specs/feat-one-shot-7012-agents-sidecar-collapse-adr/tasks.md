---
title: Tasks — collapse the AGENTS change-class sidecars (ADR-150)
plan: knowledge-base/project/plans/2026-07-28-chore-collapse-agents-change-class-sidecars-plan.md
issue: 7012
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — ADR-150 sidecar collapse

> **Commit topology (read first).** Phases below are work ordering, **not commit
> boundaries**. Four `lefthook.yml` pre-commit jobs name the three sidecars in
> both glob and argv, so the tree is non-committable at every boundary inside
> Phases 1–4. **Phases 1, 2, 3, 4 and 6 are ONE atomic commit.** Phases 5, 7, 8, 9
> may be separate. Read the plan's Sharp Edges before starting.

## Phase 0 — Preconditions & baseline

- [ ] 0.1 `git fetch origin main`; re-derive the next free ADR ordinal (plan assumes **ADR-150**; highest on origin/main = ADR-149). If it moved, renumber and sweep this file + the plan.
- [ ] 0.2 Record the current budget verdict verbatim (stderr matters):
      `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md 2>&1`
- [ ] 0.3 `python3 scripts/lint-rule-bodies.py --write`; snapshot `.claude/rule-body-hashes.txt` (74 gated entries) to scratch.
- [ ] 0.4 **AC3 baseline (load-bearing).** Write a throwaway script reusing `lint-rule-bodies.py`'s body-parse + normalization with `GATED_PREFIX_RE` **disabled**; emit an ordered `(id → sha256)` snapshot over **all 101** bodies. The 74-entry manifest covers only `^(hr|wg)-` and proves nothing about the other 27.
- [ ] 0.5 Enumerate, in advance, every id whose body text is expected to change (expected: `cq-agents-md-why-single-line`, possibly `cq-agents-md-tier-gate`). Do not hardcode a count.
- [ ] 0.6 `bash scripts/test-all.sh`; record pre-existing reds.
- [ ] 0.7 Check for an in-flight compound-promote auto-PR: `gh pr list --search 'compound-promote in:title' --state open`. Resolve before merging.

## Phase 1 — Merged corpus (same commit as 2, 3, 4, 6)

- [ ] 1.1 Create `AGENTS.rules.md` by **section-wise union** (NOT `cat` — SE-2). Expected 7 sections: Hard Rules · Workflow Gates · Compliance Tier · Passive Domain Routing · Communication · Code Quality · Review & Feedback.
- [ ] 1.2 Carry the ADR-094 frontmatter (`last_reviewed`, `review_cadence`, `owner`) verbatim (SE-5).
- [ ] 1.3 H1: `# AGENTS Rules — the whole corpus, loaded every session`.
- [ ] 1.4 Verify lossless: exactly **101** `^- …[id: …]` lines. Expected ≈ 37,365 B raw / 37,292 B stripped.
- [ ] 1.5 `git rm` the three sidecars.
- [ ] 1.6 Do **NOT** assert corpus-order == index-order; the index has no `## Compliance Tier` section (SE-11).

## Phase 2 — Pointer index

- [ ] 2.1 Strip ` → core|docs-only|rest` from all 101 pointers. Expected ≈ 5,133 B.
- [ ] 2.2 Rewrite the preamble (it carries the brace form) to describe unconditional loading.

## Phase 3 — Lints

- [ ] 3.1 `scripts/lint-rule-ids.py`: drop the arrow arm from `POINTER_LINE_RE`; retarget file list; **DELETE** the two core-pinning checks (SE-4). Plan-time simulation: these are the ONLY two failures, covering 45 `hr-*` + 5 `[compliance-tier]`.
- [ ] 3.2 `scripts/lint-rule-bodies.py`: `SIDECARS = ("AGENTS.rules.md",)` **same commit as 1.5** (SE-1); delete the cross-sidecar collision detector. Land as its own commit inside the PR if the tree stays green.
- [ ] 3.3 `scripts/lint-agents-rule-budget.py`: `ALWAYS_LOADED`, missing-file guard, `_pick_always_loaded`, arg defaults, remediation string. **Hard prerequisite** — exits 2 until done.
- [ ] 3.4 Address SE-13: the two checks the arrow-drop makes unreachable — delete or record why they survive.
- [ ] 3.5 `scripts/lint-agents-enforcement-tags.py`, `scripts/_agents_md_sections.py`, `scripts/compound-promote.sh`, `scripts/kb-drift-walker.sh`.
- [ ] 3.6 `lefthook.yml` — all four glob+argv blocks.
- [ ] 3.7 `scripts/test-all.sh` — the two live-lint invocations.

## Phase 4 — Reduce the hook (do NOT delete it — SE-9)

- [ ] 4.1 Delete `DOCS_RE`/`CODE_RE`/`INFRA_RE`, the `HAS_*` loop, the `CLASSES` chain, the class loop, `LOADER_FAIL_CLOSED`, the `HINT` line.
- [ ] 4.2 KEEP: frontmatter strip, over-strip guard, symlink rejection, single-file fail-safe, stamp, `[session-context]`, SOC 2 manifest, **and the tmpfs-guard alarm block (job #9)**.
- [ ] 4.3 ⚠️ **Positional contract.** Removing HINT shifts `[session-context]` from lines 4-6 to 3-5. Update all four assertions (`sed -n '4p'/'5p'/'6p'`, the `sed -n '7p'`, the tmpfs `al4/al5/al6`, the `head -3` byte budget) **or** keep a one-line placeholder.
- [ ] 4.4 Pin the manifest's `change_class` to the constant `"all"` (do not drop the key — it is a CC6.1/CC7.2 evidence schema with an exact key-set assertion). Update `.claude/hooks/README.md`'s "three fields" prose.
- [ ] 4.5 Retarget Test 27 (`docs-only → numerator < denominator`) to a **truncated-corpus fixture** — do not delete it; it is the arm proving the stamp numerator is not vacuous.
- [ ] 4.6 Delete `tests/scripts/test_classifier_regex_parity.sh`, `tools/migration/classify-rules.sh`, `tools/migration/split-sidecars.sh`; unwire the parity suite from `test-all.sh`.
- [ ] 4.7 Retarget `session-rules-loader.test.sh`: drop the five `assert_class` cases. **`-headless.test.sh` needs NO edit** (its "classifier" is the `HEADLESS_MODE` boolean).

## Phase 5 — Teaching surfaces (separate commit OK)

- [ ] 5.1 DELETE class-fit prose: `plan/SKILL.md` (mirror marker + 2 bullets), `deepen-plan/SKILL.md` (twin), `compound/SKILL.md` (demotion rung), `plugins/soleur/AGENTS.md` (6-line paragraph), `.claude/hooks/README.md` (`## Change-class loader` — **retain** the manifest/SOC-2 and hook-design Sharp Edges subsections).
- [ ] 5.2 REWRITE: `plan/SKILL.md` B_ALWAYS bullet; `compound/SKILL.md` B_TOTAL model.
- [ ] 5.3 ⚠️ **Do not break the compound-sync anchors.** `plan/SKILL.md`, `compound/SKILL.md`, and `compound-promote-runbook.md` are threshold-mirror sites; if a rewrite drops the exact anchor phrasing the gate errors "extraction is vacuous".
- [ ] 5.4 `brainstorm/SKILL.md` — **no edit**; the count-discipline lesson stays true regardless of sidecars.
- [ ] 5.5 Pointer-only: `ship/SKILL.md`, `observability-coverage-reviewer.md`, `constitution.md`, `compound-promote-runbook.md`, `kb-tags.txt`.
- [ ] 5.6 User-visible block strings: `no-memory-write.sh` (+ its test), `background-poll-prefer-monitor.sh`, `iac-plan-write-guard.sh`.

## Phase 6 — Budget re-baseline (same commit as 1–4)

- [ ] 6.1 Measure real `B_ALWAYS` (expected ≈ **42,425 B**).
- [ ] 6.2 Set WARN/REJECT above it with a **stated margin**, described as a judgment call and a ratchet — not as a derived limit.
- [ ] 6.3 ⚠️ **Update all 13 threshold-mirror sites** in `lint-agents-compound-sync.sh`'s `SITES` table, including the three that name `AGENTS.docs.md` (repoint to `AGENTS.rules.md`).
- [ ] 6.4 `cq-agents-md-why-single-line` must carry the new literals and has only **6 bytes** of headroom vs `PER_RULE_CAP = 600` (SE-12).
- [ ] 6.5 `MAX_ALWAYS_LOADED_BYTES` is a **live production guard** — write its own rationale; "the measurement got honest" does not cover loosening it.

## Phase 7 — Citations & ownership (separate commit OK)

- [ ] 7.1 The four path-set **soundness arguments**: `bot-pr-with-synthetic-checks/action.yml`, `scripts/required-checks.txt`, `infra/github/ruleset-ci-required.tf`, `.github/workflows/ci.yml`.
- [ ] 7.2 `.github/CODEOWNERS` — three lines → one.
- [ ] 7.3 `.tf` citations. Note `infra/github/variables.tf` is a `description` **attribute**, not a comment — but still **no apply** (SE-6).
- [ ] 7.4 Leave `tests/scripts/fixtures/tfplan-real-ruleset-baseline.json` as a point-in-time capture; say so in the PR body.
- [ ] 7.5 Do NOT sweep `knowledge-base/project/{plans,specs,brainstorms,learnings}/**` or `**/archive/**`.

## Phase 8 — Deployed-cron rollout (Correction 4)

- [ ] 8.1 Harden the two `existsSync(...) ? readFile(...) : ""` fail-open sites in `cron-compound-promote.ts` — a missing corpus must fail loudly, not read as 0 bytes.
- [ ] 8.2 Retarget `TARGET_ALLOW_RE` so `AGENTS.core.md` is no longer a writable target (else the cron can resurrect it).
- [ ] 8.3 Same hardening for `scripts/compound-promote.sh`.
- [ ] 8.4 Verify the `web-platform-release.yml` redeploy actually ran post-merge (the path filter matches, but confirm — do not assume).

## Phase 9 — ADR + issue disposition

- [ ] 9.1 `/soleur:architecture create` **shape: rich** → `ADR-150-agents-rule-corpus-is-unconditionally-loaded.md`.
- [ ] 9.2 Record in Consequences: the honest byte framing (+2,344 B/session vs weighted mean; −1,255 B vs majority path; the −939 B/turn arrow saving is **orthogonal**, not a collapse win).
- [ ] 9.3 Amend ADR-092 (cross-sidecar decoy retired), ADR-094 (frontmatter host), ADR-140 (loader-class infeasibility voided), ADR-116; one-line fix to ADR-070; token swaps in ADR-139 and **`ADR-027-stateless-self-modifying-cron.md`** (a superseded second file shares that ordinal); ADR-086 is a **no-op**.
- [ ] 9.4 Record an explicit **AP-017 deviation note**: the ADR-092 gate is knowingly blind for one commit (SE-1); the compensating control is the all-101 body-hash proof (AC3).
- [ ] 9.5 Mark `specs/feat-agents-md-change-class-loader/` superseded (historical record — do not rewrite).
- [ ] 9.6 Close **#7013** (obsolete), **#6138** (target unreachable), **#3792** (superseded). Do NOT implement any.
- [ ] 9.7 `bash scripts/check-adr-ordinals.sh`.

## Phase 10 — Verification

- [ ] 10.1 Walk AC1–AC9; record each result.
- [ ] 10.2 AC3 is the load-bearing one: all 101 body hashes accounted for, **zero** WORM acks appended.
- [ ] 10.3 AC6 sweep clean (expected 65 files / 355 hits reduced to 0 outside the carve-out).
- [ ] 10.4 `bash scripts/test-all.sh` vs Phase-0 baseline.
- [ ] 10.5 PR body: `Closes #7012`, plus explicit disclosure that the ADR-092 gate is structurally blind across the migration (SE-1) and AC3 is the compensating proof.
