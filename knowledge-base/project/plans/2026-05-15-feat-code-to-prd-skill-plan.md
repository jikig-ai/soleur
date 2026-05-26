---
feature: code-to-prd
issue: 2726
parent_issue: 2718
branch: feat-code-to-prd-2726
worktree: .worktrees/feat-code-to-prd-2726
pr: 3783
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-05-15-code-to-prd-brainstorm.md
spec: knowledge-base/project/specs/feat-code-to-prd-2726/spec.md
date: 2026-05-15
type: feature
---

# Plan: code-to-prd skill (reverse-engineer Next.js codebase → PRD)

## Summary

Build a new Soleur skill `plugins/soleur/skills/code-to-prd/` that walks a target Next.js codebase, redacts secrets and PII via a 4-layer fail-closed stack, writes a PRD markdown document to `knowledge-base/product/prd/<project>-prd.md`, then spawns the `spec-flow-analyzer` agent on the written PRD to append a `## Gap Analysis` section. v1 ships Next.js-only (App Router + Pages Router). Rails/Django and exhaustive field inventory are explicitly deferred to v2.

Reuses `plugins/soleur/skills/incident/scripts/redact-sentinel.sh` verbatim (14 secret classes). Extends `plugins/soleur/skills/spec-templates/SKILL.md` with a fourth template (`prd.md`). Adapted from the MIT-licensed pattern at `alirezarezvani/claude-skills/product-team/code-to-prd`; MIT attribution required at SKILL.md footer + new `NOTICE` file at repo root.

## User-Brand Impact

**If this lands broken, the user experiences:** a polished-looking PRD that omits 4 routes or includes a customer API key in plaintext, posted into a buyer's data room during diligence.

**If this leaks, the user's data is exposed via:** the generated PRD markdown at `knowledge-base/product/prd/<project>-prd.md` — committed to git, shared via PR review, emailed to a buyer/contractor, or pasted into an AI agent's onboarding context.

**Brand-survival threshold:** `single-user incident`.

CPO sign-off was recorded at brainstorm Phase 0.5 (assessed user-brand-critical, both vectors confirmed). `user-impact-reviewer` agent will be invoked at PR review per `plugins/soleur/skills/review/SKILL.md` conditional-agent block. Sign-off lifecycle staging per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`.

## Research Insights

**Verified codebase facts (2026-05-15):**

- `plugins/soleur/skills/incident/scripts/redact-sentinel.sh` exists. Exit codes: 0 clean / 1 redaction needed / 2 invalid arg. Meta-redacts to `<8-prefix>***<8-suffix>`. 14 classes: JWT, email, UUID, stripe_key, stripe_whsec, stripe_acct, stripe_cust_pi_seti_sub_in, IPv4, env_var (DOPPLER/SENTRY/STRIPE/SUPABASE/OPENAI/ANTHROPIC/GITHUB/VERCEL/CLOUDFLARE), github_token, anthropic_key, openai_key, supabase_pat, pem_private_key. Test pattern at `plugins/soleur/skills/incident/test/redact-sentinel.test.sh`.
- `gitleaks` 8.24.2 installed at `/home/jean/.local/bin/gitleaks`. `.gitleaks.toml` (21367 bytes) at repo root.
- `tree-sitter` NOT installed. v1 does not require it (filesystem-driven route enumeration only).
- `NOTICE` / `THIRD_PARTY_LICENSES.md` do NOT exist at repo root — must be created.
- `plugins/soleur/skills/spec-templates/SKILL.md` has templates for `spec.md`, `tasks.md`, `component.md`. NO existing `prd.md` template.
- `plugins/soleur/agents/product/spec-flow-analyzer.md` is the canonical Agent location (Soleur-side); model: inherit. Spawn pattern in `plugins/soleur/skills/plan/SKILL.md:298`.
- `plugins/soleur/docs/_data/skills.js` `SKILL_CATEGORIES` map at line 12 — must register new skill.
- `plugins/soleur/skills/skill-creator/scripts/init_skill.py` scaffolds a new skill with template SKILL.md.
- `plugins/soleur/skills/skill-creator/scripts/package_skill.py` invokes `quick_validate.py` for frontmatter validation.
- `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh` is the mandatory security scan invocation (accepts stdin OR positional file; exit 0 advisory).
- **Description-budget headroom: 36 words** (current 1814 / 1850 cap at `plugins/soleur/test/components.test.ts:12`). New skill description MUST be ≤30 words to leave margin.

**Institutional learnings applied:**

- `2026-02-18-skill-cannot-invoke-skill.md` — skill cannot programmatically call `/soleur:gdpr-gate`; must redirect operator.
- `2026-03-15-skill-description-budget-prevents-context-compaction-loss.md` — description ≤30 words for this skill given current consumption.
- `2026-02-16-inline-only-output-for-security-agents.md` + `2026-05-15-fail-closed-redaction-enables-committed-default-output.md` — committed-default output requires 4-layer fail-closed redaction.
- `2026-02-13-agent-prompt-sharp-edges-only.md` — `spec-flow-analyzer` Task spawn prompt = sharp edges only, no generic PRD-writing advice.
- `2026-04-19-skill-description-budget-headroom.md` — measure budget at plan time; reserve a specific allocation.

## Research Reconciliation — Spec vs. Codebase

Per the plan skill's reconciliation requirement and folded from `spec-flow-analyzer`'s 9-gap report:

| Spec claim | Reality | Plan response |
|---|---|---|
| FR2 walker honors `.gitignore` via `git ls-files -c -o --exclude-standard` | Symlinks tracked by git pass through walker; `redact-sentinel.sh` reads via `grep` which follows the link. A tracked symlink pointing to a sibling worktree's `.env` bypasses path-exclusion. | Add **FR2.1**: resolve each candidate via `realpath --relative-base=<target>`; reject any path resolving outside `<target>`; skip symlinks entirely in v1. |
| FR1 detects Next.js via `package.json` + `next.config.{js,ts,mjs}` | Monorepos (workspaces, Turborepo, Nx) have multiple `package.json` files. Untracked target dir → `git ls-files` returns empty → walker writes empty PRD that passes redaction (a successful-looking no-op). | Add **FR1.1**: preflight aborts with explicit error if root `package.json` missing OR `git ls-files` returns 0 entries. Monorepo support deferred to v2; v1 scopes to the directory containing the first `package.json` walking up. |
| FR6 Layer 4 deletes PRD on gitleaks finding | If `rm -f` fails (read-only FS, permission denied), the leak persists silently. | Add **FR6.1**: after delete, assert `test ! -e <path>`; if file still exists, exit non-zero with loud operator message including the literal path. |
| FR10 Coverage Caveats "at minimum lists declined framework features" | "At minimum" is unambiguous as a floor but allows degenerate "None" output if extractor covered all input. Spec also silent on Art. 9 special-category gap surfaced by GDPR gate. | Add **FR10.1**: Coverage Caveats MUST enumerate, every run: (a) frameworks not scanned (Rails, Django, etc.), (b) extraction techniques used, (c) what was excluded by path filter (count + categories, not paths), (d) Art. 9 special-category disclaimer ("automated redaction does not detect Art. 9 text content; review banner-flagged sections before sharing"). Never permit "None." |
| FR6 Layer 4 absent-binary behavior: "emit warning" | Ambiguous: does this exit 0 (PRD remains, user sees warning) or abort (PRD deleted)? Layer 4 is the load-bearing independent verifier — operating without it breaks the fail-closed promise. | **FR6.2** (revised per Kieran): `gitleaks` is a **preflight precondition**. Skill aborts at Phase 0 if `gitleaks` is not on PATH, with installation instructions. Layer 4 is always present at runtime — never optional. |
| FR8 gap-analysis spawn failure: "MUST NOT proceed" | PRD already exists on disk at spawn time. "MUST NOT proceed" conflicts with the artifact's already-on-disk state. | Add **FR8.1**: gap-analysis spawn failure is **degraded success** — append `## Gap Analysis\n\nSKIPPED (spec-flow-analyzer unavailable at <ISO-8601 timestamp>)` to PRD; exit 0. The PRD is a draft; failing the closing pass should not delete an otherwise-clean output. |
| FR9 MIT attribution surfaces | `NOTICE` / `THIRD_PARTY_LICENSES.md` do NOT exist at repo root. Plugin is the unit of redistribution (Kieran review), not the repo. | Place NOTICE at **plugin root** (`plugins/soleur/NOTICE`), not repo root. Include full MIT text + upstream copyright line. Drift detection is **not** in v1 — `soleur:sync` has no MIT-audit logic and inventing one is YAGNI (DHH + Simplicity converge). v2 may add a dedicated `scripts/check-notice-drift.sh`. |
| FR7 PRD banner content | Banners are disclaimers, not founder instructions. Founders see `[REDACTED:stripe_key]` and don't know what to do. | Add **FR7.1**: PRD banner block includes an inline `### How to Read This PRD` subsection explaining (a) redaction-token format, (b) "redacted ≠ leaked — scanner found and removed," (c) one-line "if you see a token, source file contained a secret; rotate and move to `.env`." Content lives inline in the banner template — NOT a separate `references/how-to-read-this-prd.md` file (DHH + Simplicity converge). |
| TR8 test fixture token | Sentinel regex `sk_(test\|live)_[A-Za-z0-9]{16,}` does NOT match underscore — `sk_test_<<tail-with-underscores-that-fails-regex>>` terminates at `sk_test_FIXTURE` (7 chars, fails `{16,}`). Test would pass for the wrong reason. **Kieran P0 correctness bug.** | Rewrite **TR8** fixture to `sk_test_<<24+ alnum chars, no underscores>>` (alnum-only after prefix, 30 chars total, ≥16-char tail). Verify the sentinel actually matches at write time: `echo '...' \| bash redact-sentinel.sh /dev/stdin`. Add `.gitleaks.toml` allowlist entry for the fixture path citing `cq-test-fixtures-synthesized-only`. |
| Skill description (implicit in TR5) | Budget headroom is 36 words; spec did not reserve a specific allocation. | Add **TR5.1**: draft the SKILL.md `description:` field at P1 scaffold AS THE FIRST WRITE, ≤30 words. Run `wc -w` against the description before any other code. Add a tasks.md check-gate that the new total stays ≤1850. |

## Open Code-Review Overlap

None. Verified 2026-05-15 via `gh issue list --label code-review --state open --json number,title,body --limit 200` against all 5 planned write surfaces (`plugins/soleur/skills/code-to-prd`, `plugins/soleur/skills/spec-templates`, `plugins/soleur/skills/skill-creator`, `plugins/soleur/docs/_data/skills.js`, `plugins/soleur/skills/incident/scripts/redact-sentinel.sh`).

## Domain Review

**Domains relevant:** Product, Legal, Engineering (carry-forward from brainstorm).

### Product (CPO — carry-forward)

**Status:** reviewed
**Summary:** Founder-ICP-shaped for "inherited prototype / sell-side due diligence" archetype. Anchored on IP-safe-handoff outcome. v1 scope cut (Next.js-only, no exhaustive field inventory) preserves smallest blast radius. Sequencing prereq (#2725 incident-commander) verified merged 2026-05-14.

### Legal (CLO — carry-forward)

**Status:** reviewed
**Summary:** MIT attribution mandatory at SKILL.md footer + `NOTICE`/`THIRD_PARTY_LICENSES.md`. Secret posture must be REFUSE not FLAG. Dual banners (due-diligence + PII) mandatory, non-removable. Local-only operation = no DPA needed; obligation is disclosure-as-warning.

### Engineering (CTO — carry-forward)

**Status:** reviewed
**Summary:** Hybrid skill+agent orchestration mirrors `incident` pattern. Filesystem-first framework detection. Reuse `redact-sentinel.sh` verbatim. Walker = `git ls-files -c -o --exclude-standard`. Architectural pivot risk = grep-based field extraction silently misses 30% → mandatory `## Coverage Caveats` block.

### Product/UX Gate

**Tier:** none — skill scaffolding plan, no new user-facing UI files. Mechanical escalation check confirmed: no new `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files in this plan.

### GDPR Gate (Phase 2.7)

**Status:** reviewed (triggered by `brand-survival threshold = single-user incident` per `hr-gdpr-gate-on-regulated-data-surfaces` clause b — canonical regex did NOT match).

**Findings:**

- One `Suggestion` — `GDPR-Art-9` coverage gap. `redact-sentinel.sh`'s 14 classes cover secrets + 3 PII classes (email, IPv4, UUID), but NOT Art. 9 special-category text patterns (race, health, biometric, religion, etc.). Folded into FR10.1 (Coverage Caveats disclaimer) as v1 minimum; v2 may add an Art. 9 keyword-scan layer to the sentinel (flag-not-refuse).

No `Critical` findings. No `compliance-posture.md` Active Items row required.

## Implementation Phases

### Phase 0 — Preconditions and skill scaffold

- **Gitleaks precondition (FR6.2 revised):** abort with installation instructions if `which gitleaks` returns non-zero. Layer 4 is always present at runtime, never optional.
- Run `python3 plugins/soleur/skills/skill-creator/scripts/init_skill.py code-to-prd --path plugins/soleur/skills` to scaffold `SKILL.md` + `scripts/` + `references/`.
- Delete the stock example files the scaffolder creates that this skill won't use.
- Draft the `SKILL.md` `description:` field as THE FIRST WRITE — ≤30 words, single-line YAML format (not block scalar). Run `awk` extractor + `wc -w` to verify.

### Phase 1 — Walker + framework detection + extraction (single script)

- Single `scripts/code-to-prd.sh` does walker + framework detection + extraction + render (2-scripts collapsed to 1 per Simplicity review).
- Framework detection: `package.json` + `next.config.{js,ts,mjs}`. Refuse if not Next.js.
- Walker: `git -C <target> ls-files -c -o --exclude-standard`.
- Pre-scan path-exclusion filter: `.env*`, `secrets.*`, `*.pem`, `*.key`, `credentials.*`, `master.key`, `.git/**`.
- **Realpath resolution + symlink rejection** (FR2.1) — inherited-prototype threat model: previous contractor may have planted tracked symlinks.
- **Preflight aborts** (FR1.1): missing root `package.json` OR empty walker output.

### Phase 2 — Route + state + API extraction (Next.js only)

- App Router: enumerate `app/**/page.{tsx,jsx,ts,js}` and `app/**/route.{ts,js}`.
- Pages Router: enumerate `pages/**/*.{tsx,jsx,ts,js}` excluding `pages/_*.{tsx,jsx,ts,js}`.
- For each route: HTTP methods (route handlers), dynamic segments, one-line description from JSDoc/TSDoc on default export.
- State-shape summary via regex on `useState`/`useReducer`/server-component-props.
- API/external dependency inventory: `fetch()` literal URLs + `@/lib/api*`/`@/server/*` imports + `process.env.*` **names only** (FR5 — values never read) + `package.json` deps.
- Track every file whose extraction confidence falls below threshold — emit to `## Coverage Caveats`.

### Phase 3 — Redaction stack (3 layers, fail-closed)

Per plan-review Layer-2-is-redundant finding (DHH + Simplicity converge): Layer 2 (input sanitization) ran the same sentinel script on overlapping bytes as Layer 3. Cut. Stack is now 3-layer:

- **Layer 1** — path-exclusion filter (already in Phase 1).
- **Layer 2** — `redact-sentinel.sh` on rendered PRD pre-write. Exit code 1 (matches found) MUST abort write. No partial PRD on disk.
- **Layer 3** — `gitleaks detect --source <prd-file> --no-git --report-format json`. Any finding deletes the PRD AND verifies `test ! -e <path>` (FR6.1). Layer 3 is always-present (preflight ensures binary).

### Phase 4 — PRD writer (inline in `scripts/code-to-prd.sh`)

- Output path: `knowledge-base/product/prd/<project-name>-prd.md`. `<project-name>` derived from `package.json` `name` (kebab-case).
- Sections in order: Banners (including inline `### How to Read This PRD` subsection per FR7.1) → Overview → Routes → State Shapes → API & External Dependencies → Coverage Caveats (FR10.1) → Gap Analysis (populated Phase 5) → MIT Attribution.
- Dual banners (non-removable): due-diligence disclaimer + PII/confidentiality notice.

### Phase 5 — Gap-analysis closing pass

- After Phase 4 write + Layer 3 verifier passes, spawn `@agent-soleur:product:spec-flow-analyzer` via Task with the written PRD path. Prompt = sharp edges only per `2026-02-13-agent-prompt-sharp-edges-only.md`.
- Spawn failure is degraded success (FR8.1): append `## Gap Analysis\n\nSKIPPED (spec-flow-analyzer unavailable at <ISO-8601>)` to PRD. Exit 0. Layer 1+2+3 already cleared — gap-analysis is a closing analysis pass, not a safety boundary.

### Phase 6 — Test fixture + harness

- `plugins/soleur/skills/code-to-prd/test/fixture/`: minimal Next.js skeleton — 3 routes (`app/page.tsx`, `app/about/page.tsx`, `app/api/health/route.ts`) + `package.json` + `next.config.mjs` + `.env.example` (containing `STRIPE_SECRET_KEY=sk_test_<<24+ alnum chars, no underscores>>`). NO `app/actions.ts` — server-action extraction is not in v1 (Simplicity review #3). 5 fixture files total.
- Test harness `plugins/soleur/skills/code-to-prd/test/code-to-prd.test.sh` mirrors `incident/test/redact-sentinel.test.sh` shape.
- Test assertions:
  1. All 3 fixture routes captured in the PRD.
  2. HTTP method (`GET`) captured for `api/health/route.ts` (FR3 — per Kieran P1-9).
  3. Zero fixture-secret tokens appear in PRD output.
  4. **No env-var VALUE appears in PRD** (FR5 — only names; per Kieran P1-9): assert `grep -F "FIXTUREDONOTUSE" prd-output.md` returns 0 lines.
  5. `## Coverage Caveats` block is non-empty with all four required subsections (frameworks, techniques, exclusion counts, Art. 9 disclaimer).
  6. Both banners present and intact (verbatim string match).
  7. `### How to Read This PRD` subsection present in banner block.
  8. `## Gap Analysis` section present (either populated or `SKIPPED (...)`).
  9. MIT attribution footer present.
  10. Layer 2 sentinel halts the write when a fresh secret is injected post-render (RED test).
  11. Layer 3 deletes the file if Layer 2 is bypassed via env var `CODE_TO_PRD_SKIP_LAYER_2=1` (RED test).

### Phase 7 — Description budget verification (BEFORE registration)

Per Kieran P0-2 — measure → fit → register. Inverted from prior draft.

- Run `awk` extractor (using the canonical robust form from `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh:34`) to validate description value extraction works with single-line YAML.
- Verify total skill descriptions stay ≤1850 words via the same inline script used at plan-write time.
- Run `python3 plugins/soleur/skills/skill-creator/scripts/package_skill.py plugins/soleur/skills/code-to-prd` to validate frontmatter + structure.
- Run `bash plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh < plugins/soleur/skills/code-to-prd/SKILL.md` per `skill-creator` Step 5b.

### Phase 8 — Registration + attribution + spec-templates extension

- Append new entry to `plugins/soleur/docs/_data/skills.js` `SKILL_CATEGORIES` map (line 12) under `product-team` category.
- Create `plugins/soleur/NOTICE` (plugin root per Kieran P1 — plugin is the unit of redistribution, not the repo). Include: full MIT text, upstream copyright line.
- Extend `plugins/soleur/skills/spec-templates/SKILL.md` with `prd.md` template documenting the FR7 section order. Reuse `component.md`'s frontmatter pattern (`updated`, `primary_location`).

### Phase 9 — Fixture allowlist commit sequencing

Per Kieran P0-3 — pre-commit gitleaks hook reads allowlist from HEAD, not staged. Sequence:

- Commit 1: `.gitleaks.toml` allowlist entry for the fixture path.
- Commit 2: fixture `.env.example` containing the synthetic secret.

Two commits, in this order, NEVER bundled.

## Files to Create

- `plugins/soleur/skills/code-to-prd/SKILL.md`
- `plugins/soleur/skills/code-to-prd/scripts/code-to-prd.sh` (single script — walker + extractor + render + redaction orchestration)
- `plugins/soleur/skills/code-to-prd/references/banner-template.md` (includes inline `### How to Read This PRD` per FR7.1)
- `plugins/soleur/skills/code-to-prd/references/prd-template.md`
- `plugins/soleur/skills/code-to-prd/test/code-to-prd.test.sh`
- `plugins/soleur/skills/code-to-prd/test/fixture/package.json`
- `plugins/soleur/skills/code-to-prd/test/fixture/next.config.mjs`
- `plugins/soleur/skills/code-to-prd/test/fixture/app/page.tsx`
- `plugins/soleur/skills/code-to-prd/test/fixture/app/about/page.tsx`
- `plugins/soleur/skills/code-to-prd/test/fixture/app/api/health/route.ts`
- `plugins/soleur/skills/code-to-prd/test/fixture/.env.example` (contains `STRIPE_SECRET_KEY=sk_test_<<24+ alnum chars, no underscores>>` — alnum-only after prefix, verified to match sentinel regex)
- `plugins/soleur/NOTICE` (plugin root — NOT repo root)

## Files to Edit

- `plugins/soleur/docs/_data/skills.js` — append `code-to-prd: "product-team"` entry to `SKILL_CATEGORIES` map at line 12.
- `plugins/soleur/skills/spec-templates/SKILL.md` — append `prd.md` template after `component.md` template.
- `.gitleaks.toml` — append allowlist entry for `plugins/soleur/skills/code-to-prd/test/fixture/.env.example` citing `cq-test-fixtures-synthesized-only`.

## Acceptance Criteria

### Pre-merge (PR)

Reviewer-converged load-bearing set (12 ACs):

- [ ] AC1: Running `plugins/soleur/skills/code-to-prd/test/code-to-prd.test.sh` against the fixture passes all 11 test assertions.
- [ ] AC2: PRD output zero-secrets sweep — `bash plugins/soleur/skills/incident/scripts/redact-sentinel.sh <fixture-prd-path>` returns exit code 0.
- [ ] AC3: Sentinel regex actually matches the fixture token — `echo 'STRIPE_SECRET_KEY=sk_test_<<24+ alnum chars, no underscores>>' | bash plugins/soleur/skills/incident/scripts/redact-sentinel.sh /dev/stdin; echo "exit=$?"` returns `exit=1` (match found, redaction needed). Guards against Kieran P0-1 underscore-in-regex correctness bug.
- [ ] AC4: Layer 2 RED test — injecting a fresh `sk_live_<<24+ alnum Layer-2 RED-test fixture>>` (allowlisted) into the render pipeline aborts the write; no PRD on disk after the test.
- [ ] AC5: Layer 3 RED test — bypassing Layer 2 with env var `CODE_TO_PRD_SKIP_LAYER_2=1` and injecting the same secret produces a written PRD that is then deleted by Layer 3; `test ! -e <path>` passes.
- [ ] AC6: Gitleaks-absent preflight abort — running the skill with `PATH=$(echo $PATH | tr ':' '\n' | grep -v gitleaks | paste -sd:)` exits non-zero with installation instructions BEFORE any walker/extraction runs.
- [ ] AC7: Spec-flow-analyzer-failure degraded-success — running the skill with a deliberately broken Task spawn (env var `CODE_TO_PRD_FAKE_SFA_FAIL=1`) produces a PRD containing `## Gap Analysis\n\nSKIPPED (spec-flow-analyzer unavailable at` and exit code 0.
- [ ] AC8: Preflight abort — running the skill with `<target>` containing no `package.json` exits non-zero with the literal path in the error message.
- [ ] AC9: Symlink rejection — creating a symlink inside the fixture pointing to a sibling `.env` file does NOT cause the linked content to enter the PRD.
- [ ] AC10: Coverage Caveats non-empty — every PRD from any fixture variant contains a non-empty `## Coverage Caveats` block with all four required subsections (frameworks not scanned, extraction techniques, exclusion counts, Art. 9 disclaimer).
- [ ] AC11: Description-budget gate — extracting all SKILL.md descriptions via the canonical robust `awk` pattern (`gsub(/^description:[[:space:]]*"?|"?$/, "")` — verbatim from `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh:34`) returns total ≤1850 words. The new skill's own description is ≤30 words.
- [ ] AC12: `NOTICE` exists at PLUGIN root (`plugins/soleur/NOTICE`) with full MIT text + upstream copyright line. Verified via `grep -F "alirezarezvani/claude-skills" plugins/soleur/NOTICE` returning ≥1 line. SKILL.md footer also has attribution: `grep -F "Adapted from alirezarezvani/claude-skills (MIT)" plugins/soleur/skills/code-to-prd/SKILL.md` returns ≥1 line.

Boundary sentinel sweep (`hr-write-boundary-sentinel-sweep-all-write-sites`) is a **review-time concern**, not a CI gate. Reviewer enumerates write primitives in `scripts/code-to-prd.sh`: `rg '(^|[^<])>[> ]*"?\$' scripts/code-to-prd.sh` + `rg '\b(tee|cp|mv|install)\b' scripts/code-to-prd.sh` — every write site demonstrably routes through `redact-sentinel.sh` AND `gitleaks detect`.

### Post-merge (operator)

None. Skill is locally-invoked; no infrastructure provisioning or external service setup. Issue auto-closes via `Closes #2726` in the PR body.

## Risks

- **Description budget exhaustion:** 36 words headroom. If the skill description drafts at 35 words, sibling-skill trims may be needed. Mitigation: AC13 hard caps at 30 words.
- **gitleaks rule-set drift:** gitleaks 8.24.2 today; rules update over time. Layer 4 may surface new findings on a rule update against an unchanged PRD. Mitigation: this is desired behavior; pin gitleaks version in CI if drift becomes painful.
- **Founder confusion on redaction tokens:** mitigated by FR7.1 "How to Read This PRD" section.
- **Art. 9 special-category coverage gap:** flagged by GDPR gate as Suggestion. v1 documents in Coverage Caveats; v2 may add keyword-scan layer.
- **vendor pattern divergence:** vendor repo may evolve (new framework support, new schema). Mitigation: NOTICE pins `sha256`; `soleur:sync` triggers re-audit on drift (FR9.1).
- **Skill-cannot-invoke-skill:** if a future founder wants `gdpr-gate` to run on the generated PRD, the skill MUST redirect rather than invoke. Documented in SKILL.md post-run output.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`. (Carry-forward from AGENTS.md `hr-weigh-every-decision-against-target-user-impact`.)
- When implementing FR6 Layer 3, do NOT invoke `gitleaks detect --source <prd-file>` alone without `--no-git` — gitleaks defaults to scanning git history, which is not what Layer 3 wants. Verify with `gitleaks detect --help` before coding.
- When implementing FR2.1 symlink rejection, `realpath --relative-base=<target>` is GNU-coreutils-specific. macOS `realpath` differs. Soleur targets Linux primarily; v2 may add a Python `os.path.relpath` fallback.
- The `incident/scripts/redact-sentinel.sh` reuse contract is **verbatim invocation, no copy**. If a future v2 needs a different class set (Art. 9 keywords, monorepo paths, BYOK API keys), extend the sentinel upstream and benefit incident + code-to-prd simultaneously. Do not fork.
- Fixture allowlist sequencing (Kieran P0-3): pre-commit gitleaks hook reads allowlist from HEAD, not staged content. Sequence in tasks.md: commit `.gitleaks.toml` allowlist FIRST (commit 1), then commit fixture `.env.example` (commit 2). NEVER bundle.
- Fixture token format (Kieran P0-1): `sk_test_<<24+ alnum chars, no underscores>>` — alnum-only after prefix, no underscores. `redact-sentinel.sh`'s stripe_key class is `sk_(test\|live)_[A-Za-z0-9]{16,}`, and `_` is NOT in `[A-Za-z0-9]`. Verify at write time, not assume.
- Description-budget extraction (Kieran P1-4): use the canonical robust `awk` pattern from `skill-security-scan/scripts/run-scan.sh:34`: `awk '/^description:/ { gsub(/^description:[[:space:]]*"?|"?$/, ""); print; exit }'`. Brittle single-line-quote extractors break on block-scalar YAML — use the canonical form verbatim.
- The skill description budget headroom (36 words) is plugin-wide. If a parallel PR adds another skill, the headroom shrinks. Re-measure at /work-time start and abort with a clear error if headroom < 30 words.
- Phase ordering (Kieran P0-2): Phase 7 (description-budget verify) runs BEFORE Phase 8 (registration in `skills.js`). Inverting risks mutating a shared registry that then has to be reverted if budget fails.
- Layer 2 was cut from the redaction stack (DHH + Simplicity converge). v1 ships 3 layers, not 4. If a v2 contributor proposes restoring Layer 2, the burden is to show it catches something Layer 1+3 (and especially Layer 3's gitleaks pass) does not.

## Test Strategy

Test runner: `bash` (matches `incident/test/redact-sentinel.test.sh` precedent). No new framework dependency. Run via `bash plugins/soleur/skills/code-to-prd/test/code-to-prd.test.sh` from repo root.

CI integration: add a job invocation to the existing test workflow under `.github/workflows/`. Cross-reference with `plugins/soleur/skills/test-fix-loop/SKILL.md:28` for the test-runner detection pattern (`Gemfile/Rakefile` → bundle exec rake test; this plan adds bash → direct invocation).

Boundary-sentinel sweep verification (AC21): `rg` enumerates every PRD-write site in `scripts/render-prd.sh`; manual code review verifies each routes through `redact-sentinel.sh`.

## Sequencing and Bundle Context

- Tier-2 sibling of #2718 (claude-skills audit). #2725 incident-commander merged 2026-05-14 (verified). Other Tier-2 children: #2723 tech-debt-tracker, #2724 mcp-server-builder, #2727 karpathy-check.
- Cannibalization lens: parent #2718 explicitly REJECTED "wholesale 235-skill port." This plan ships ONE skill (Next.js only) — not a port-by-port lift. Cumulative cannibalization risk remains low.
- v2 deferrals (tracked separately): Rails framework support, Django framework support, exhaustive field inventory (AST-derived), page-relationship diagrams, Art. 9 keyword-scan layer in sentinel, monorepo support.
