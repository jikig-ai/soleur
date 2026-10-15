# Brainstorm: triage GitHub Code Quality findings and wire deterministic linters (#10331)

Date: 2026-10-15 · Issue: #10331 · Draft PR: #10342 · Branch: `feat-code-quality-linters-10331`
Lane: cross-domain · Baseline: `knowledge-base/engineering/audits/2026-10-14-github-code-quality-baseline.md`

## What We're Building

Four independently shippable slices that turn the 2026-10-14 CodeQL Code Quality baseline (169 findings, 22 rules) into deterministic signal:

1. **PR1 — triage the two `js/comparison-between-incompatible-types` findings** in `apps/web-platform/server/account-delete.ts` and `dsar-export.ts` (Art. 17 / Art. 15 code). Failing test first, then fix or dismiss with a stated reason.
2. **PR2 — shipped plugin scripts: replace silent handlers with logged ones**, surgical only. Shipped scripts with empty handlers: `playwright-mcp-redact-proxy.py`, `founder-check.py`, `resolve-debt.py`, `scan-ancestor-signal-helpers.py`. Behavior (fail-closed paths) must not change.
3. **PR3a — this repo's linters:** a baselined ruff step (CI + lefthook, shipped Python, excluding `knowledge-base/**` archive scratch) and a root eslint config covering the test dirs nothing lints today.
   **PR3b — plugin `work`/`review` detect-and-run:** detect the project's own eslint/ruff config, run it on changed files only, report the changed-line delta; "no linter configured" when absent. Depends on 3a's ratchet design.
4. **PR4 — ADR-276 S5 amendment** (keep or drop per-PR Code Quality), decided from a measured rule-by-rule overlap table after 3a lands; record the Code Quality billing in `knowledge-base/operations/expenses.md`.

## Why This Approach

- Operator chose the full scope including PR3b (2026-10-15), over the CPO's recommendation to defer the user-facing half. Recorded as an operator override: the CPO found no roadmap row or user report for PR3b; PR3b is therefore built on conviction, not demand evidence, and must stay small (detect-and-run, no bundled linters, no imposed rule sets).
- The CTO's detect-then-run design avoids imposing opinions on unknown customer stacks and reuses the existing `work/SKILL.md` baselined-lint drawdown pattern.
- Ruled by CTO agent: slice order PR1 → PR2 → PR3 → PR4; key the ratchet on `file:rule` plus a content anchor (not a bare total, not line numbers); pin ruff and eslint versions; keep Code Quality on until the overlap table exists.

## Key Decisions

| Decision | Choice | Source |
|---|---|---|
| User-facing PR3b | In scope (operator override of CPO) | Operator |
| PR order | 1 → 2 → 3a → 3b → 4 | CTO |
| Ratchet key | `file:rule` + content anchor; pinned tool versions | CTO |
| Code Quality on/off | Keep on now; decide in PR4 from overlap table | CTO |
| Redaction proxy | Logging only; fail-closed behavior unchanged; its test suite must pass | CPO + CLO |
| GDPR triage rule | Failing test first; `gdpr-gate` on any diff touching the two files; CLO assesses Art. 33 clock if a guard is defeatable | CLO |
| Productize Candidate | none (one-off setup) | — |

## User-Brand Impact

- **Artifact:** the shipped redaction proxy and plugin scripts, the DSAR export / account-erasure server code, and the work/review lint gates.
- **Vector:** a mechanical lint "fix" that flips a fail-closed handler to proceed (unredacted data reaches the agent), or a mistyped cross-tenant guard that lets another subject's rows into an export or reports an erasure complete.
- **Threshold:** single-user incident.

## Premise Corrections (verified)

- `apps/web-platform` already enables `@typescript-eslint/no-unused-vars` with a committed ratchet (`apps/web-platform/test/eslint-config.test.ts`, `BASELINE_FINDINGS = 192`). The JS gap is that eslint scans only `apps/web-platform`, not root `test/` or `plugins/soleur/test/`, and lefthook has no eslint entry.
- No Python linter exists anywhere (no ruff/pyproject/flake8; grep over `.github`, `lefthook.yml`, `scripts/`, `package.json`). 76 tracked `.py` files: 16 shipped, 9 plugin tests, 51 repo-only.
- `.claude/hooks/security_reminder_hook.py` does not ship to users (the issue groups it with shipped scripts). It fails open deliberately (advisory hook).
- `tsc --noEmit` in `apps/web-platform` exits 0, so TS2367 is not the source of the two findings; they are CodeQL-inferred. Candidate sites (low confidence): `dsar-export.ts:1857` (`fd !== null` in a `finally`, ~30%), `dsar-export.ts:148`, `account-delete.ts:236` (~10% each).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering
**Summary:** Four-PR slicing; repo CI/lefthook first, plugin detect-and-run second; ratchet keyed on `file:rule`; keep Code Quality on until a rule-overlap table exists (`py/file-not-closed`, `js/overwritten-property`, `js/regex/unmatchable-caret`, `js/superfluous-trailing-arguments` have no default ruff/eslint equivalent).

### Product
**Summary:** CPO read this as internal hygiene with no demand evidence for the user-facing half and advised deferring it; operator overrode. Treat the proxy as high brand risk: surgical changes only.

### Legal
**Summary:** No CLO sign-off needed unless triage finds a real defect; `gdpr-gate` runs on diffs touching the two server files. GitHub is already a recorded processor, so Code Quality AI suggestions need no register or DPD change while fixtures stay synthetic.

## Capability Gaps

- **No Python linter** — evidence: `git grep -n -i 'ruff\|flake8\|pylint\|pyflakes'` over `.github`, `lefthook.yml`, `scripts/`, both `package.json` returns nothing; no `pyproject.toml`/`ruff.toml`/`setup.cfg`/`.flake8`.
- **No eslint over root `test/` and `plugins/soleur/test/`** — evidence: only config is `apps/web-platform/eslint.config.mjs`; `package.json:14` runs `eslint .` from that dir.
- **No generic "run project linters" step in `work`/`review`** — evidence: `work/SKILL.md:1252-1256` is per-app guidance; `review/SKILL.md:348-364` is semgrep-only.

## Open Questions

- Exact locations of the two incomparable-type findings: Code Quality alerts are not in the code-scanning API; read them from the GitHub UI at plan time. Parked until then.
- Billing owner for Code Quality ($10/active committer/month + AI credits): operator to confirm; PR4 records it in `expenses.md`.
- PR3b scope boundary for unknown customer stacks (which linter configs to detect; behavior when none found) — plan-time design.
- Article 30 register row cites `knowledge-base/legal/data-processing-agreements/github.md`, which does not exist (tracked separately).
