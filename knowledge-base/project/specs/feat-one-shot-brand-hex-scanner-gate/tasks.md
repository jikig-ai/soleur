---
title: "Tasks — brand-palette enforcement + scanner-defect fixes"
plan: knowledge-base/project/plans/2026-05-29-feat-brand-palette-enforcement-anti-slop-scanner-plan.md
branch: feat-one-shot-brand-hex-scanner-gate
lane: cross-domain
closes: 4635
---

# Tasks

## 1. Setup / preconditions

- [ ] 1.1 Re-confirm preconditions: host grep is ugrep (`grep --version`); skill-desc budget at 1950/1950 (edit NO `description:`); current Tier-1 count = 15 in 4 prose sites + `tier1-scan.test.ts:290`.
- [ ] 1.2 Query open `code-review` issues against Files-to-Edit (Phase 1.7.5).

## 2. Brand rules (RED)

- [ ] 2.1 Add 3 rows to `slop-rules.md` Active-rules table: BRAND-RAW-HEX (brand/high), BRAND-WHITE-ON-GOLD (brand/high), BRAND-NONZERO-CORNER (brand/medium). Escape every literal `|` as `\|`.
- [ ] 2.2 Add prose: brand-high = blocking; BRAND-RAW-HEX project-agnostic; Soleur-user generalisation referencing their own brand-guide.md/token file (work item 7).
- [ ] 2.3 `tier1-scan.test.ts`: bump `toHaveLength(15)`→`18`; add positive+negative fixtures (synthetic, `withFile`) for the 3 rules; add compile round-trip / pipe-escape assertions.

## 3. Blocking exit code (GREEN)

- [ ] 3.1 Add `computeExitCode(findings, rules)` (pure, exported): exit 1 iff any finding's rule is `category==="brand" && severity==="high"`; else 0. Keep `Finding.category:"anti-slop"` (schema-safe).
- [ ] 3.2 Wire into `main()`; update header docblock "Exit codes".
- [ ] 3.3 Tests: brand-high→1; anti-slop-only→0; brand-medium-only→0.

## 4. Scope extension + single-source parity (work item 4)

- [ ] 4.1 `defaultPaths()` L245: add `apps/web-platform/server/.*\.(ts|tsx)$`; export `DEFAULT_PATH_RE_SOURCE`.
- [ ] 4.2 `review/SKILL.md` hook pattern: add same `server` alternation.
- [ ] 4.3 Route-group regression test: `DEFAULT_PATH_RE_SOURCE` matches `(public)/invite/[token]/{invite-actions,page}.tsx` (work item 2).
- [ ] 4.4 Parity test: `review/SKILL.md` hook literal == `DEFAULT_PATH_RE_SOURCE` (shared alternation body).

## 5. ugrep grep -z fix + guard (work item 1, closes #4635)

- [ ] 5.1 `review/SKILL.md` collector → `git diff --name-only -z … | tr '\0' '\n' | grep -E '<pattern>'`; `mapfile -t` (drop `-d ''`); never `grep -z`.
- [ ] 5.2 Add empty-result warn guard (diff has extension-matching files but `CHANGED_FILES` empty → warn, not silent-clean).

## 6. Doc sync

- [ ] 6.1 15→18 across `frontend-anti-slop/SKILL.md` L9/L47/L54 + `review/SKILL.md` L295.
- [ ] 6.2 `frontend-anti-slop/SKILL.md` scope table: add server `.ts/.tsx` row; add "Brand rules (blocking)" subsection.
- [ ] 6.3 `review/SKILL.md`: document brand-high = required-fix gate (not triage).

## 7. Verify

- [ ] 7.1 In-tree dry-run against `pending-invite-banner.tsx` + `notifications.ts`: expect ≥1 brand/high finding, `exit=1`. Use BRAND-NONZERO-CORNER signal to decide context-narrowing.
- [ ] 7.2 Full `bun test` green incl. `components.test.ts` budget canary.
- [ ] 7.3 PR body `Closes #4635`.
- [ ] 7.4 (ship) File app-side remediation tracking issue for `notifications.ts` greys + `pending-invite*` `#2563eb` (out-of-scope app code).
