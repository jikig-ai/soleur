---
name: gdpr-gate
description: "This skill should be used when auditing diffs or plans for GDPR/CCPA/HIPAA compliance gaps."
---

# GDPR / CCPA / HIPAA pre-generation gate

`gdpr-gate` is an **advisory** code-level gate that fires inline during `/soleur:plan` Phase 2.7 and at `/soleur:work` Phase 2 exit. It scans plan prose, schema migrations, and diffs for regulated-data gaps under GDPR (Articles 5/6/9/17/20/25/30/32/33/35), with secondary coverage for CCPA / CPRA and HIPAA. It never blocks. Critical findings (Article 9 special-category data) prompt operator acknowledgment + GitHub issue creation; the gate never auto-writes to `compliance-posture.md`.

This is **not legal review**. Output is a heuristic, machine-generated checklist meant to compress regulator-shaped surprises out of the normal feature-design loop. Consult the `clo` agent and `legal-compliance-auditor` before merging anything load-bearing.

## When to invoke

- **Plan time** — automatic at `/soleur:plan` Phase 2.7 when the plan touches regulated-data surfaces (per `hr-gdpr-gate-on-regulated-data-surfaces` canonical regex).
- **Work time** — automatic at end of `/soleur:work` Phase 2, single pass after all per-task RED/GREEN/REFACTOR loops complete (token budget ≤4k per invocation).
- **Manual** — `/soleur:gdpr-gate "<scope>"` where `<scope>` is a file path, glob, or one-line description.
- **Hook (advisory only)** — `lefthook.yml` `gdpr-gate-advisory` prints a stderr breadcrumb when staged paths match the canonical regex. The hook always exits 0 — it never blocks the commit. Blocking enforcement lives in `/soleur:ship` Phase 5.5 (post-PR).

The gate is **read-only with respect to the canonical `/soleur:plan` template**. It audits the plan; it never injects its own checklist into the plan body. Architectural invariant per ADR-026.

## Disclaimer (always first)

Every gate output begins, as the first non-blank line, with the literal:

```
**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**
```

The disclaimer is hardcoded. A test in `plugins/soleur/test/gdpr-gate.test.ts` asserts the literal appears as the first non-blank line of every fixture output.

## Path globs (canonical)

The single source of truth for "what counts as a regulated-data path" is the regex below. `lefthook.yml` mirrors it verbatim; the skill's prompt template references it; `AGENTS.md` `hr-gdpr-gate-on-regulated-data-surfaces` cites it.

```
^(apps/web-platform/supabase/migrations/|apps/web-platform/lib/auth/|apps/web-platform/server/.*auth.*\.(ts|tsx|js)|apps/web-platform/app/api/.*\.(ts|tsx)$|.*\.sql$)
```

Each component matches at least one file in the current repo (verified at plan time, 2026-05-10). `forms/**` and `**/*.prisma` from earlier drafts are dropped — both matched zero paths in this repo and a glob that matches nothing is a workflow violation per `hr-when-a-plan-specifies-relative-paths-e-g`.

## 5 mandatory v1 checks (FR4)

Each check has a stable `check_id` for cross-referencing in `compliance-posture.md` and GitHub issue labels.

| `check_id` | Article | Trigger | Default severity |
|---|---|---|---|
| `GDPR-Art-6` | Art. 6 lawful basis | New schema column without `-- LAWFUL_BASIS: <basis>` annotation | `Important` |
| `GDPR-Art-5e` | Art. 5(1)(e) retention | New PII table without retention metadata | `Important` |
| `GDPR-Art-17` | Art. 17 erasure | New FK to `users` without `ON DELETE CASCADE` or anonymisation migration | `Important` |
| `GDPR-Chapter-V` | Art. 44–49 cross-border | New non-EEA vendor env var / SDK without `compliance-posture.md` Vendor DPA row | `Important` |
| `GDPR-Art-9` | Art. 9 special-category | New column matching the Art. 9 list in [fields.md](./references/fields.md) | **`Critical`** |

**Critical is reserved for Art. 9 column-name matches in v1.** Demoting the other four to `Important` keeps the noise floor low and preserves `compliance/critical` issue labels as a load-bearing signal. See [non-negotiables.md](./references/non-negotiables.md) for the regulatory rationale.

Reference layers:
- [fields.md](./references/fields.md) — PII field catalogue + Art. 9 special-category extension.
- [leakage-vectors.md](./references/leakage-vectors.md) — PII vector catalogue (verbatim from upstream).
- [non-negotiables.md](./references/non-negotiables.md) — GDPR-first regulatory framing.
- [legal-consent.md](./references/legal-consent.md) — ePrivacy + Art. 7/13/14/35.
- [layers/api-layer.md](./references/layers/api-layer.md) — 7 API-layer checks (AP-01..AP-07).
- [layers/data-in-transit.md](./references/layers/data-in-transit.md) — Transit checks + Chapter V cross-border.
- [layers/data-lifecycle.md](./references/layers/data-lifecycle.md) — Lifecycle checks; DL-04 covers Art. 20 portability.

## Output format

Each finding follows this schema:

```markdown
**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**

### `<check_id>` — <one-line title>

**Severity:** <Critical | Important | Suggestion>
**Article:** <regulation citation>
**Location:** <file path:line range, or "plan section <header>">
**Pattern matched:** <verbatim regex/keyword that fired>
**Why this matters:** <one short paragraph>
**What to do:** <concrete next action — annotate, add migration, file vendor DPA row, etc.>
```

Severity levels:
- `Critical` — reserved for Art. 9 (special-category) column-name matches in v1. Triggers the operator-acknowledgment escalation flow.
- `Important` — Art. 6 / Art. 5(1)(e) / Art. 17 / Chapter V findings. Logs to console; operator may file a `compliance/improvement` issue at their discretion.
- `Suggestion` — DPIA reminder, Art. 7 consent UX hint, ePrivacy banner alignment, etc. Read-only.

## Critical-finding escalation flow (FR5)

When a `Critical` finding fires, the gate emits this block at the end of the report:

```
─────────────────────────────────────────────────────────────────
CRITICAL FINDING — operator acknowledgment required
─────────────────────────────────────────────────────────────────

A `Critical` finding (`check_id: GDPR-Art-9`) requires an Active Items row in
`knowledge-base/legal/compliance-posture.md`. The gate does NOT auto-write the
row.

Run, in order:

  1. gh issue create \
       --title "<title summarising the finding>" \
       --label compliance/critical,domain/legal \
       --body "<finding text + link to PR>"

  2. Edit knowledge-base/legal/compliance-posture.md and append a row to the
     Active Compliance Items table. The canonical schema is:

       | Item                 | Issue     | Status | Deadline | Notes                              |
       | <one-line summary>   | #<issue>  | OPEN   | -        | <check_id>; <date>; <context>      |

     `<check_id>` is the gdpr-gate finding identifier (e.g., GDPR-Art-9). Date
     and remediation context belong in Notes — the table itself uses 5 fixed
     columns.

  3. git add knowledge-base/legal/compliance-posture.md
     git commit -m "compliance: register Art. 9 finding for #<issue>"

The gate exits after printing this block. It never modifies disk for you.
```

This flow is operator-driven by design — the gate is `read-only` against `compliance-posture.md`. Auto-writing would silently aggregate compliance gaps into a single repo file, defeating the human-accountability rationale (CLO assessment).

## Prompt template — what the gate sends to the model

The gate's reasoning step receives the following system prompt structure. The schema-only invariant is **DO NOT INCLUDE COLUMN VALUES** — the gate sends column NAMES only, never row values.

```
You are gdpr-gate, an advisory compliance auditor.

Your input is:
1. A diff or plan excerpt (no row values).
2. The list of regulated-data paths (per the canonical regex above).
3. The five v1 check definitions below.

DO NOT INCLUDE COLUMN VALUES in the response. Send column NAMES only —
schema-shape data, never live row payload. The user's PII is the subject of
the audit; sending values would be a Chapter V transfer of the very data we
are auditing.

For each check:
  - Identify pattern matches.
  - Emit a finding using the Output format above.
  - Reserve `Critical` for Art. 9 column-name matches.
```

The `DO NOT INCLUDE COLUMN VALUES` directive is a verbatim string assertion in `plugins/soleur/test/gdpr-gate.test.ts` — moving or paraphrasing it breaks the test by design.

## First-run on existing codebase

Existing migrations 001–040 in this repo do NOT use `-- LAWFUL_BASIS: <basis>` annotations. A backfill audit will fire `Important` (`GDPR-Art-6`) findings on every column that lacks one. **This is intentional** — backfill audits surface existing gaps, and the demotion of Art. 6 to `Important` keeps the noise from training operators to dismiss `Critical`. Operators may suppress backfill noise by scoping the gate to a specific diff (`/soleur:gdpr-gate "git diff main...HEAD"`) rather than a full repo scan.

## Future severity changes

Findings carry a stable severity per the FR4 table. If a future version introduces a new severity (e.g., `Blocking`), three consumer patterns must be grepped per `cq-union-widening-grep-three-patterns`:

- `const _exhaustive: never` rails (safe — the build fails until the new variant is handled).
- `\.severity === "` if-ladders (silent drop).
- `\?\.severity === "` optional-chained ladders (silent drop).

Add new severities in this file's table FIRST, then run the three greps before writing implementation.

## Boundary with sibling agents

- **`data-integrity-guardian`** — migration safety + judgment-based PII review. The gate is deterministic pattern-matching; the guardian is judgment-based.
- **`security-sentinel`** — OWASP / CWE security-of-processing flaws. Art. 32 overlaps; sentinel handles the "how", gate handles the "what".
- **`clo`** — reads `compliance-posture.md`; the gate produces the row contract the CLO consumes. The gate never writes; the operator does.
- **`legal-audit`** / **`legal-generate`** — document-layer skills (privacy policy, DPA, terms). The gate is code-layer.

Canonical disambiguation prose lives in `plugins/soleur/skills/review/SKILL.md` §boundaries.

## Sharp edges

- Hook layer is **advisory only** (`exit 0`). Operators expecting `lefthook` to block will be surprised — the blocking enforcement is at `/soleur:ship` Phase 5.5, post-PR.
- The lefthook breadcrumb does NOT fire when lefthook itself is bypassed: `git commit --no-verify`, GitHub web-UI edits, fork PRs whose authors don't have lefthook installed, or agent commits on machines without `lefthook install`. In those paths the only enforcement is `/soleur:ship` Phase 5.5's critical-finding-acknowledgment gate (post-PR). Plan Phase 2.7 + work Phase 2 exit gates run regardless of lefthook because they live inside the skill, not the hook layer.
- The `*auth*` regex match is intentionally broad — false-positives on `auth-error.ts` etc. are accepted because output is advisory and cheap.
- Lifted upstream files are pinned to commit `7b58d68461cb1fc033a063e34cc9de63d0b4144b`. Upstream drift is governed by the content-vendoring policy at `knowledge-base/engineering/policies/content-vendoring.md`, the weekly `scheduled-content-vendor-drift.yml` workflow, and the lefthook `vendor-pin-integrity` gate (silent-edit detection). NOTICE frontmatter (`upstream`, `pinned-commit`, `last-verified`, `lifted-files[]` with both `upstream-blob-sha` and `local-blob-sha`) is the canonical machine-readable form.
- **Runtime staleness banner** (FR6 / AC6a-d): the hook subshell-execs [notice-frontmatter.sh](./scripts/notice-frontmatter.sh) `days-stale` on every invocation. Days since `last-verified` >30d → STDOUT banner. Days >90d → additional `POSTURE_FAIL:` STDOUT line; the operator follows the chain in the policy doc to append a row to `compliance-posture.md`. NOTICE deletion / parser failure / future-dated `last-verified` all resolve to `days_stale=999` → banner fires. STDOUT (not stderr) is load-bearing — agent runtimes (Claude Code skill harness, MCP servers) frequently swallow stderr. Gate exits 0 in all paths; the staleness signal is advisory.
- The gate transmits column NAMES to the model (Anthropic). This is itself a Chapter V transfer; it falls under Anthropic's existing DPA recorded in `compliance-posture.md` Vendor DPAs. Row values are never sent — see "Prompt template" above.
- AGENTS.md rule ID `hr-gdpr-gate-on-regulated-data-surfaces` is **immutable** per `cq-rule-ids-are-immutable`. v2 splits retire the ID via the retired-rule-ids ledger rather than reusing.
