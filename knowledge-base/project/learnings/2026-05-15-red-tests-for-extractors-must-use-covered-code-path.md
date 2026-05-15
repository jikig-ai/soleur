# Learning: RED tests for regex-based extractors must inject the indicator on a covered code path

## Problem

While implementing the `code-to-prd` skill (#2726), the test harness defined Layer 2 / Layer 3 RED tests (T10 / T11) by copying the fixture to a tampered variant and injecting a synthetic Stripe-shape token into `app/leak.tsx`:

```bash
cat >"${TAMPERED}/app/leak.tsx" <<'EOF'
/** Tracker page used by Layer-2 RED test. */
export default function Tracker() {
  const key = "sk_live_<<RED-test fixture token, alnum tail>>";
  return <pre>{key}</pre>;
}
EOF
```

Both RED tests passed cleanly (exit 0) even though the redaction layers were supposed to fire. The injected secret was never extracted into the rendered PRD, so Layers 2 and 3 had nothing to react to.

## Root Cause

The `code-to-prd` extractor reads only specific code paths via filtered regex:

- App Router routes: `^app/.*page\.(tsx|jsx|ts|js)$` and `^app/.*route\.(ts|js)$`
- State shapes: `\buse(State|Reducer)\b\s*[(<]` (any `*.tsx`/`*.jsx`/`*.ts`/`*.js`)
- fetch URLs: `fetch\(['"][^'"]+['"]` 
- Internal imports: `@/lib/api*` / `@/server/*`
- Env names: `process\.env\.[A-Z_][A-Z0-9_]*`
- Package deps: `package.json` `dependencies` keys

`app/leak.tsx` is none of these — not a `page.tsx`, not a `route.ts`, no `useState` call, no `fetch()`, no `process.env`. The walker tracked the file (Layer 1 didn't exclude it), but the extractor never lifted its content into the rendered output.

## Solution

Move the synthetic indicator to a code path the extractor explicitly reads. The State Shapes path is the cleanest target because (a) it accepts any `*.tsx`/`*.ts` file, and (b) its regex (`grep -nE '\buse(State|Reducer)\b\s*[(<]'`) prints the entire matched line — so a `useState("synthetic-secret")` initial value lands verbatim in the PRD:

```bash
# Replace app/page.tsx with one whose useState initial value carries the secret.
cat >"${TAMPERED}/app/page.tsx" <<EOF
/** Tampered landing page (Layer-2/3 RED test). */
import { useState } from "react";
export default function HomePage() {
  const [k, setK] = useState("${SYNTHETIC_LIVE}");
  return <pre>{k}</pre>;
}
EOF
```

After this change, T10 fired with `exit 1` from Layer 2, T11 fired with `exit 1` from Layer 3, and both verified the PRD path no longer existed.

## Key Insight

**A RED test that injects an indicator into a code path the SUT does not read passes vacuously — the same way a stubbed `fetch()` that returns a hardcoded value passes vacuously when the test means to verify the network call.** The injection site IS the test fixture. When the SUT is a regex-based extractor, the test must thread the indicator through the same regex pattern the SUT uses, not arbitrary file content within the fixture's directory.

This is the test-fixture analog of `2026-04-18-red-verification-must-distinguish-gated-from-ungated.md` (gating primitives) and `2026-04-22-red-test-must-simulate-suts-preconditions.md` (preconditions). For extractor-shaped SUTs, the precondition is "the indicator lives on a code path the extractor reads." Failing to satisfy the precondition makes the RED assertion vacuous.

## Cheapest Verification

After writing a RED test for an extractor, list every regex the SUT applies, then trace the injection site through each regex. If the injection site is invisible to all of them, the test is vacuous regardless of whether the assertion passes.

```bash
# For code-to-prd, the cheapest probe is to run the extractor against the
# tampered fixture and grep the rendered PRD for the synthetic indicator.
# If grep returns 0 lines, the indicator never entered the PRD, and Layer 2/3
# cannot fire on it.
bash code-to-prd.sh "${TAMPERED}" /tmp/test-prd.md
grep -F "${SYNTHETIC_LIVE}" /tmp/test-prd.md && echo COVERED || echo VACUOUS
```

A `VACUOUS` result means the RED test cannot distinguish "redaction worked" from "indicator never entered the surface."

## Tags

```yaml
category: test-failures
module: extractors-and-walkers
related:
  - knowledge-base/project/learnings/test-failures/2026-04-18-red-verification-must-distinguish-gated-from-ungated.md
  - knowledge-base/project/learnings/test-failures/2026-04-22-red-test-must-simulate-suts-preconditions.md
  - knowledge-base/project/learnings/2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md
  - knowledge-base/project/learnings/test-failures/2026-05-11-rerender-not-remount-for-in-component-state-machine-tests.md
issue: 2726
```

## Prevention

1. **At RED-test write time**, list the regex patterns the SUT applies (or the routes/paths the SUT enumerates) and trace the injection site through each. If the injection site isn't visible to any, the test is vacuous.
2. **At review time**, the reviewer should ask: "After this RED test sets up its fixture, does the SUT actually see the indicator?" If the reviewer cannot trace the indicator to a covered code path in <30 seconds, the test needs a coverage comment naming the regex/path.
3. **For new extractor-shaped skills**, the test harness header should list "Indicator coverage paths" — the regex patterns or directory globs that the test fixtures must thread their synthetic indicators through.

## Session Errors

The `code-to-prd` implementation session also surfaced these process errors. Each is documented with recovery + prevention so they feed back into the rules.

- **Wrong CWD at session start (bare repo)** — first Bash call ran in `/home/jean/git-repositories/jikig-ai/soleur` (bare repo root); `git status` returned exit 128 "this operation must be run in a work tree". **Recovery:** explicit `cd .worktrees/feat-code-to-prd-2726`. **Prevention:** when /work or /one-shot args reference a worktree path, the agent's first action must be `pwd` followed by `cd` into the worktree if not already there. Existing rule `hr-when-in-a-worktree-never-read-from-bare` covers the converse (don't read from bare); the new case is "don't run git from bare when the task targets a worktree." Already partially enforced by harness; no new rule needed.

- **`/dev/stdin` invocation of `redact-sentinel.sh` returns exit 0 instead of 1** — plan AC3 wording (`echo 'X' | bash redact-sentinel.sh /dev/stdin`) doesn't work because the sentinel re-reads `${FILE}` per pattern iteration; the FIFO drains on the first pattern (no match for JWT) and every subsequent pattern sees EOF on the same descriptor. The literal `/dev/stdin` looks like it should work, but doesn't, because the sentinel's loop body invokes `grep -oE -e "${pattern}" "${FILE}"` once per pattern — 14 separate reads of a single-use FIFO. **Recovery:** the test harness uses a temp file; tasks.md 6.6 was updated with the rationale. **Prevention:** when plan/spec wording invokes a multi-pass reader against `/dev/stdin`, mark it as known-broken at plan-review time and route to a temp-file workaround. Optionally, refactor `redact-sentinel.sh` to slurp content once into a variable before the pattern loop — this is a one-line change that would make `/dev/stdin` work as written.

- **Gitleaks subdir-scoped scan reported false leaks** — `gitleaks detect --source plugins/soleur/skills/code-to-prd --no-git` after committing the fixture `.env.example` showed "leaks found: 1" because `.gitleaks.toml`'s `[allowlist]` path patterns are relative to repo root (`plugins/soleur/skills/.*/test/fixture/\.env\.example$`); a subdir scan strips the `plugins/soleur/skills/code-to-prd/` prefix and the regex no longer matches. **Recovery:** ran `gitleaks detect --source . --no-git --config .gitleaks.toml` from repo root. **Prevention:** allowlist verification always runs from repo root with explicit `--config`. The pre-commit lefthook stage runs from repo root already, so the production gate is correct; only ad-hoc verification from a subdir is misleading. Document this in any future verification runbook.

- **Stopped pipeline after /soleur:review marker** — emitted the "Review Phase Complete" marker and waited for further user input despite the work skill's explicit Phase 4 directive: "Continue through the post-implementation pipeline automatically. Do NOT stop and wait." The agent rationalized the stop on the grounds that "the work is substantial" — but the work skill explicitly anticipates and rejects that exact rationalization: "the earlier learning 'Workflow Completion is Not Task Completion' applies." The user had to prompt "why did you stop the workflow?". **Recovery:** chained to /soleur:compound (this skill) and will continue to /soleur:ship next. **Prevention:** the work skill's pipeline is a single unit; after each chained skill returns its compact marker, the next step (compound, then ship) MUST be invoked in the same response. A skill marker is a progress signal, not a turn-ending deliverable. Tighten the work skill's Phase 4 prose to make this rejection of "the work is substantial" rationalization an explicit anti-pattern (proposed below in Constitution Promotion).
