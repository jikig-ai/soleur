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
- **Manual repo-scan** — `/soleur:gdpr-gate --repo-scan` runs the gate against the whole working tree (operator-initiated only). Defenses, batching, and output contract documented in `## --repo-scan mode` below.
- **Hook (advisory only)** — `lefthook.yml` `gdpr-gate-advisory` prints a stderr breadcrumb when staged paths match the canonical regex. The hook always exits 0 — it never blocks the commit. Blocking enforcement lives in `/soleur:ship` Phase 5.5 (post-PR).

The gate is **read-only with respect to the canonical `/soleur:plan` template**. It audits the plan; it never injects its own checklist into the plan body. Architectural invariant per ADR-026.

## Disclaimer (always first)

Every gate output begins, as the first non-blank line, with the literal:

```
**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**
```

The disclaimer is hardcoded. A test in `plugins/soleur/test/gdpr-gate.test.ts` asserts the literal appears as the first non-blank line of every fixture output.

## --repo-scan mode

`/soleur:gdpr-gate --repo-scan` runs the gate against the whole working tree. Operator-initiated only — never auto-fires from `/soleur:plan`, `/soleur:work`, or lefthook. Token budget remains ≤4k per Haiku call (ADR-026 TR3) via 25-files-per-batch fan-out.

**Sole-arg sentinel.** When invoked with `$ARGUMENTS`, trim leading/trailing whitespace (including `\t` and `\n`). If the trimmed value equals **exactly** `--repo-scan` (no spaces, no quotes, no additional tokens), enter repo-scan mode. Any other value — including `--repo-scan apps/web-platform`, `repo scan`, or `"--repo-scan section of the repo"` — falls through to the v1 scope-string mode and is forwarded verbatim to the prompt.

**File source.** `git ls-files -c -o --exclude-standard` (cached + untracked, respecting `.gitignore`). Submodules excluded; symlinks not followed. Pre-filtered through the canonical regex (see `## Path globs (canonical)` below) so only regulated-data paths enter the candidate pool.

**Deny-list (D1).** Single source of truth: [scripts/path-denylist.txt](./scripts/path-denylist.txt). Line-oriented file with extended-regex patterns (one per line; `#` for comments). Bash `[[ =~ ]]` semantics. Any candidate path matching at least one deny-list pattern is excluded from the scan corpus and a `# blocked: <path>` line is emitted to stderr (audit trail).

**Allow-list bypass (D3).** `GDPR_GATE_REPO_SCAN_ALLOW_PATHS=path1:path2:...` — colon-separated literal paths (no globs accepted; bash strict equality after split). Default unset → all deny-list patterns enforced. Each entry must satisfy two clauses or the script exits 1: (1) the path must match at least one deny pattern (otherwise the bypass is meaningless), and (2) the path must exist in `git ls-files -c -o --exclude-standard` (otherwise the operator probably typo'd the path; see Sharp edges).

**CI refusal (D3).** If both `$CI` and `$GDPR_GATE_REPO_SCAN_ALLOW_PATHS` are set, the script exits 1 with `allow-list bypass refused in CI environment`. Operator-only by construction — runbooks that set the bypass var get caught at the script boundary, not by docs alone.

**Batching.** 25 files per Haiku call. The dispatching agent collects per-batch outputs, dedups by `(check_id, path, line)`, and summarises inline.

**Inline-only output (D4).** Findings emitted to stdout / conversation only. The repo-scan walker NEVER writes to `compliance-posture.md`, `__goldens__/`, `test/fixtures/`, or any disk path under `~/.claude/`. The v1 critical-finding flow (operator-acknowledged write to `compliance-posture.md` Active Items + GitHub `compliance/critical` label) still applies for Art. 9 column-name matches discovered during repo-scan.

**Schema-only invariant (D5).** The repo-scan prompt template inherits v1's `DO NOT INCLUDE COLUMN VALUES` directive verbatim. The directive is the load-bearing assertion in `plugins/soleur/test/gdpr-gate.test.ts`.

**Canonical-regex source-of-truth.** [scripts/repo-scan.sh](./scripts/repo-scan.sh) extracts the canonical regex from this file's `## Path globs (canonical)` heading via `awk` at runtime — it does NOT redefine the regex. Editors of SKILL.md must keep that heading and the first fenced regex line stable; if extraction fails the script exits 1 with `canonical regex not found in SKILL.md`. Asserted by AC-PARITY-1 and `gdpr-gate-repo-scan.test.ts`.

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

**Active layers (with `check_id` markers):**

- [layers/api-layer.md](./references/layers/api-layer.md) — 7 API-layer checks (AP-01..AP-07).
- [layers/data-in-transit.md](./references/layers/data-in-transit.md) — Transit checks T-01..T-06 + DT-EU-CB Chapter V cross-border.
- [layers/data-lifecycle.md](./references/layers/data-lifecycle.md) — Lifecycle checks DL-01..DL-06; DL-04 covers Art. 20 portability.
- [layers/auth-sessions.md](./references/layers/auth-sessions.md) — Auth & session checks A-01..A-07 + Art. 32(1)(b) confidentiality footer.
- [layers/frontend.md](./references/layers/frontend.md) — Frontend checks F-01..F-06 + ePrivacy/TTDSG strict-opt-in footer.
- [layers/testing-seeding.md](./references/layers/testing-seeding.md) — Test fixture + seed-data checks TS-01..TS-05 + Art. 32 pseudonymization footer.
- [legal-consent.md](./references/legal-consent.md) — Layer-shaped LC-01..LC-05 ePrivacy + GDPR Art. 7/13/14/35 (Soleur-authored — promoted from prose at v2; see NOTICE; v1 prose preserved at [legacy/legal-consent-v1-prose.md](./references/legacy/legal-consent-v1-prose.md) until v3).

**Reference catalogues (no `check_id` markers — consulted by other layers):**

- [fields.md](./references/fields.md) — PII field catalogue + Art. 9 special-category extension.
- [leakage-vectors.md](./references/leakage-vectors.md) — PII vector catalogue (verbatim from upstream).
- [non-negotiables.md](./references/non-negotiables.md) — GDPR-first regulatory framing.

The 5 mandatory v1 checks (FR4 above) fire on every gate invocation. `--repo-scan` (see `## --repo-scan mode` above) additionally fires every layer-id check across all 7 active layers.

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
- `--repo-scan` against full repo history will surface Art. 9 (`Critical`) findings on pre-v1 migrations 001–040 (legacy columns matching the special-category list). The default disposition is **tracked-not-amended** — `compliance-posture.md` Active Items records the row, no amendment migration is issued, because schema rewrites against historical PII tables carry their own data-integrity risk that typically exceeds the disclosure-cure benefit. The row reads `OPEN | tracked, not amended`. Default disposition only applies when the column is **dormant or read-only with disclosure cure available**. Amendment is required and the operator MUST consult `clo` before selecting a disposition when ANY of the following hold:
    1. **Active processing for an undisclosed special-category purpose** — production code currently writes or reads the column for a purpose not disclosed in the privacy notice. Fix is disclosure-side (privacy notice + DPIA + Art. 6/9 lawful-basis annotation) plus, if no Art. 9(2) lawful basis applies, halting processing.
    2. **Backfill with new special-category data** — schema is old but the *data* is new (placeholder/test rows replaced with real PII). This is operationally a new processing activity; Art. 35 DPIA may itself trigger.
    3. **Cross-border transfer post-Schrems II** — the column is replicated to a non-EEA processor (analytics, support, vendor) without Chapter V safeguards (DPA + SCCs + transfer impact assessment). Disclosure cure is insufficient — fix the Chapter V gap.
    4. **CCPA / CPRA "sensitive personal information" overlay** — California's SPI definition (Cal. Civ. Code §1798.140(ae)) overlaps but is not identical to Art. 9. A column that is Art. 9 in EU may also be SPI in California; the disposition must include a CCPA-side disclosure check, not just a GDPR-side one.
- `path-denylist.txt` patterns are bash `[[ =~ ]]` extended regex, **not shell globs**. Patterns that look like globs (e.g., `*.pem`) silently fail to match. `repo-scan.sh` sets `LC_ALL=POSIX` for locale-determinism, but contributors editing patterns should still verify on both Linux and macOS — character-class behaviour for non-ASCII bytes still differs between the two `bash` builds even with `POSIX` set.
