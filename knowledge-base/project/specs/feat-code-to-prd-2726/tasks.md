# Tasks: code-to-prd skill (#2726)

Plan: `knowledge-base/project/plans/2026-05-15-feat-code-to-prd-skill-plan.md`
Brand-survival threshold: `single-user incident` — CPO sign-off required before `/work`.

## Phase 0 — Preflight + scaffold

- [ ] 0.1 Verify `gitleaks` binary on PATH; abort with installation instructions if missing (FR6.2 revised — Layer 3 always-present at runtime).
- [ ] 0.2 Re-measure description-budget headroom: total SKILL.md description words must stay ≤1850. If parallel PR ate the headroom, abort with clear error.
- [ ] 0.3 Run `python3 plugins/soleur/skills/skill-creator/scripts/init_skill.py code-to-prd --path plugins/soleur/skills` to scaffold.
- [ ] 0.4 Delete stock example files the scaffolder creates that this skill won't use (assets/ likely unnecessary).
- [ ] 0.5 Draft SKILL.md `description:` field — ≤30 words, single-line YAML format only. Verify via canonical robust `awk` extractor (`gsub(/^description:[[:space:]]*"?|"?$/, "")`).

## Phase 1 — Walker, framework detection, extraction

- [ ] 1.1 Create `scripts/code-to-prd.sh` (single script per Simplicity review).
- [ ] 1.2 Framework detection: presence of `package.json` AND one of `next.config.{js,ts,mjs}`. Refuse if not Next.js with a clear v2-roadmap pointer.
- [ ] 1.3 Walker: `git -C <target> ls-files -c -o --exclude-standard`.
- [ ] 1.4 Pre-scan path-exclusion filter: `.env*`, `secrets.*`, `*.pem`, `*.key`, `credentials.*`, `master.key`, `.git/**`.
- [ ] 1.5 Realpath resolution + symlink rejection: resolve each candidate with `realpath --relative-base=<target>`; reject any path resolving outside `<target>`; skip symlinks (FR2.1).
- [ ] 1.6 Preflight aborts: missing root `package.json` OR empty walker output (FR1.1).

## Phase 2 — Extraction (Next.js)

- [ ] 2.1 App Router route enumeration: `app/**/page.{tsx,jsx,ts,js}` + `app/**/route.{ts,js}`.
- [ ] 2.2 Pages Router enumeration: `pages/**/*.{tsx,jsx,ts,js}` excluding `pages/_*.{tsx,jsx,ts,js}`.
- [ ] 2.3 For route handlers (`route.ts`), capture HTTP methods (exported `GET`/`POST`/`PUT`/`DELETE`/etc.).
- [ ] 2.4 For each route, capture dynamic segments + one-line JSDoc/TSDoc description (default-export only).
- [ ] 2.5 State-shape summary: regex pass for `useState`/`useReducer`/server-component props.
- [ ] 2.6 API/external dependency inventory: `fetch()` literal URLs + `@/lib/api*` / `@/server/*` imports + `process.env.*` NAMES ONLY (never read values — FR5).
- [ ] 2.7 Cross-reference `package.json` dependencies; flag third-party SDK packages.
- [ ] 2.8 Track files with low extraction confidence — emit to `## Coverage Caveats`.

## Phase 3 — Redaction (3 layers)

- [ ] 3.1 Layer 1 (path exclusion) — already in Phase 1.
- [ ] 3.2 Layer 2 — invoke `plugins/soleur/skills/incident/scripts/redact-sentinel.sh` on rendered PRD pre-write. Exit code 1 MUST abort write.
- [ ] 3.3 Layer 3 — invoke `gitleaks detect --source <prd-file> --no-git --report-format json`. Any finding: delete the PRD AND verify `test ! -e <path>`; if delete fails, exit non-zero with loud operator message.

## Phase 4 — PRD writer (inline in `scripts/code-to-prd.sh`)

- [ ] 4.1 Compute output path: `knowledge-base/product/prd/<project-name>-prd.md` where `<project-name>` = `package.json` `name` sanitized to kebab-case.
- [ ] 4.2 Ensure `knowledge-base/product/prd/` directory exists.
- [ ] 4.3 Render PRD sections in order: Banners (with inline `### How to Read This PRD` per FR7.1) → Overview → Routes → State Shapes → API & External Dependencies → Coverage Caveats → Gap Analysis (populated Phase 5) → MIT Attribution footer.
- [ ] 4.4 Render banner template from `references/banner-template.md` — dual mandatory disclaimers (due-diligence + PII/confidentiality) + inline How-to-Read subsection (redaction-token format, "redacted ≠ leaked" framing, rotation instruction).
- [ ] 4.5 Render Coverage Caveats with FOUR mandatory subsections: (a) frameworks not scanned (Rails, Django, etc.), (b) extraction techniques used (regex-only, no AST), (c) what was excluded by path filter (count + categories, not paths), (d) Art. 9 special-category disclaimer.
- [ ] 4.6 Apply Layer 2 (sentinel) → Layer 3 (gitleaks) gating between render and final disk write.

## Phase 5 — Gap-analysis closing pass

- [ ] 5.1 After Phase 4 write + Layer 3 verifier passes, spawn `@agent-soleur:product:spec-flow-analyzer` via Task with the written PRD path.
- [ ] 5.2 Spawn prompt = sharp-edges-only per `2026-02-13-agent-prompt-sharp-edges-only.md`. Cap at 200-250 words.
- [ ] 5.3 Spawn failure: append `## Gap Analysis\n\nSKIPPED (spec-flow-analyzer unavailable at <ISO-8601>)` to PRD. Exit 0 (FR8.1 degraded-success).
- [ ] 5.4 Spawn success: append agent output as `## Gap Analysis` section.

## Phase 6 — Test fixture + harness

- [ ] 6.1 Create fixture `package.json` (declares `name: "code-to-prd-fixture"`, minimal deps).
- [ ] 6.2 Create fixture `next.config.mjs` (export default `{}`).
- [ ] 6.3 Create fixture routes: `app/page.tsx`, `app/about/page.tsx`, `app/api/health/route.ts` (with `GET` export).
- [ ] 6.4 Create fixture `.env.example` with `STRIPE_SECRET_KEY=sk_test_<<24+ alnum chars, no underscores>>` (alnum-only after prefix per Kieran P0-1).
- [ ] 6.5 NO `app/actions.ts` — v1 doesn't extract server actions (Simplicity review #3).
- [ ] 6.6 Verify sentinel matches the fixture token: `echo 'STRIPE_SECRET_KEY=sk_test_<<24+ alnum chars, no underscores>>' | bash plugins/soleur/skills/incident/scripts/redact-sentinel.sh /dev/stdin; echo "exit=$?"` → `exit=1`. Failing this aborts implementation immediately.
- [ ] 6.7 Create test harness `plugins/soleur/skills/code-to-prd/test/code-to-prd.test.sh` mirroring `incident/test/redact-sentinel.test.sh` shape (set -uo pipefail, PASS/FAIL counter, trap cleanup).
- [ ] 6.8 Implement 11 test assertions per plan Phase 6.

## Phase 7 — Description-budget gate + skill validation (BEFORE registration)

- [ ] 7.1 Re-run description-budget script; total ≤1850 confirmed.
- [ ] 7.2 Run `python3 plugins/soleur/skills/skill-creator/scripts/package_skill.py plugins/soleur/skills/code-to-prd`.
- [ ] 7.3 Run `bash plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh < plugins/soleur/skills/code-to-prd/SKILL.md` (Step 5b cooperative-fast-path).

## Phase 8 — Registration + attribution + spec-templates extension

- [ ] 8.1 Append `code-to-prd: "product-team"` to `plugins/soleur/docs/_data/skills.js` `SKILL_CATEGORIES` map (line 12).
- [ ] 8.2 Create `plugins/soleur/NOTICE` (plugin root) with full MIT text + upstream copyright line.
- [ ] 8.3 Append `Adapted from alirezarezvani/claude-skills (MIT) — see plugins/soleur/NOTICE` footer to `plugins/soleur/skills/code-to-prd/SKILL.md`.
- [ ] 8.4 Extend `plugins/soleur/skills/spec-templates/SKILL.md` with `prd.md` template documenting FR7 section order.

## Phase 9 — Fixture allowlist commit sequencing

Per Kieran P0-3 — pre-commit gitleaks hook reads allowlist from HEAD, not staged. STRICTLY TWO COMMITS in this order:

- [ ] 9.1 Commit 1: `.gitleaks.toml` allowlist entry for `plugins/soleur/skills/code-to-prd/test/fixture/.env.example` citing `cq-test-fixtures-synthesized-only`. Push. Confirm landed.
- [ ] 9.2 Commit 2: fixture `.env.example` with the synthetic secret. Push.

Never bundle these two commits. Verify locally before pushing each.

## Phase 10 — Acceptance verification

Run every AC1–AC12 from plan. Each must pass before marking PR ready.

## Open Questions (track during /work)

- Does the existing `incident` skill's `redact-sentinel.sh` exit-code 0/1/2 contract suffice for code-to-prd's gating? Verify behavior on each layer transition.
- Does `package.json` `name` ever contain characters that defeat kebab-case sanitization? (e.g., scoped packages `@org/pkg`.) Document the sanitization rule in SKILL.md.
- Coverage Caveats: should "extraction confidence threshold" be operator-tunable? v1 = hardcoded; defer.
