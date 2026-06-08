# Workflow-backed `soleur:review` (prototype)

`review.workflow.js` is a [dynamic workflow](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code)
re-implementation of the core engine of the `soleur:review` skill. It is a
**prototype for A/B comparison** against the prose-driven SKILL.md — not a
replacement. Both can coexist.

## What it does

```
Classify ──▶ Review ──▶ Verify ──▶ Synthesize ──▶ File
 (1 agent)   (always-on  (1–3        (dedup +       (CONCUR-gated
             + cond.     skeptics    provenance      scope-out,
             dimensions) refute      disposition)    dry-run by
                         each find.)                 default)
```

1. **Classify** — one agent runs the same change-class predicates as
   `SKILL.md` §"Change Classification Gate" and returns a structured class
   (`code` / `non-code` / `lockfile-only` / `deletion-dominated`) **plus a
   `triggers` object** (Rails, migration, tests, source, bash-only, GDPR,
   user-impact threshold).
2. **Review** — the script (not the model) maps the class to its **always-on**
   dimension list and the triggers to its **conditional** dimensions, then fans
   out one agent per lens. Each lens reuses the **real Soleur reviewer agent**
   via `agentType`, so it inherits that agent's system prompt.
3. **Verify** — every finding is handed to 1–3 adversarial skeptics (a
   perspective-diverse panel — correctness / scope / already-handled — when
   `deepReview`) that default to `isReal=false` and must be argued *out* of
   refutation; majority-real survives. **No-barrier pipeline**: a dimension's
   findings start verifying the instant that dimension lands. The fan-out is
   **budget-floored** — if `budget.remaining()` drops below the reserve, the
   remaining findings are surfaced `UNVERIFIED` (kept, not dropped) and the
   skipped set is logged. Never a silent cap.
4. **Synthesize** — confirmed findings are deduped by `file+title`, then given
   a deterministic `disposition` (`fix-inline` vs `scope-out-candidate`) from
   the SKILL's cost-of-filing rule encoded in code.
5. **File** — each `scope-out-candidate` is independently co-signed by a
   simplicity-biased **CONCUR gate** (defaults to DISSENT). DISSENT flips the
   finding back to `fix-inline`; CONCUR files a `deferred-scope-out` issue —
   but only when invoked with `{ file: true }`. Otherwise it's a **dry run**
   that emits the would-file issue body for inspection.

## How to run it

From a session where the diff under review is reachable (`origin/main...HEAD`):

```
Workflow({ scriptPath: "plugins/soleur/skills/review/workflows/review.workflow.js",
           args: "1234" })          // PR number, branch name, or "" for current branch
```

`args` may also be an object:

| field | effect |
|---|---|
| `target` | PR number / branch / `""` (current branch) |
| `deepReview` | force the full always-on 8-dimension pass **and** a 3-skeptic perspective-diverse verify panel. The literal phrases `deep review` / `full review` in a string `target` trigger the same override, matching the SKILL. |
| `file` | actually create the `deferred-scope-out` GitHub issues for CONCUR'd candidates. Default (omit) is a dry run that only emits the would-file bodies. |

e.g. `args: { target: "1234", deepReview: true, file: true }`.

Iterate by editing the file and re-invoking with the same `scriptPath`. To
resume an interrupted run, add `resumeFromRunId: "<runId>"` — unchanged
`agent()` calls return cached results instantly.

## What it inherits from Workflow that the SKILL can't express today

| Capability | SKILL.md (Task-spawn prose) | This workflow |
|---|---|---|
| Class → fan-out decision | Model interprets a bash decision tree each run | Deterministic JS lookup (`CLASS_DIMENSIONS` + `conditionalDimensions`) |
| Conditional agents | Prose "if PR contains X, spawn agent Y" | `triggers` flags → deterministic dimension list |
| Per-finding verification | None — CONCUR fires only on scope-out *filings* | Every finding adversarially refuted (1–3 skeptics) before surfacing |
| Review→verify scheduling | Implicit barrier (waits for all reviewers) | No-barrier `pipeline()` — verify starts per-dimension |
| Disposition (fix vs file) | Prose cost-of-filing gate, model-applied | `disposition()` — code, auditable, identical every run |
| Scope-out CONCUR gate | Manual self-check the agent CONCUR'd | Structured CONCUR/DISSENT verdict; DISSENT auto-flips to fix-inline |
| Resume after interruption | Restart from zero | Journaled — cached prefix replays instantly |
| Token ceiling | Hand-written "API budget" warnings | `budget` floor on the verify fan-out; UNVERIFIED-not-dropped + logged |
| Structured output | Parse agent prose by hand | Schema-validated, agents retry on mismatch |

## Ported so far

- always-on dimension agents (class-gated 2/4/8 fan-out)
- conditional dimensions (Rails ×2, migration ×2, test-design, semgrep-SAST,
  GDPR, user-impact) from deterministic `triggers`
- 1–3 skeptic adversarial verification, no-barrier pipeline
- provenance-driven deterministic disposition
- CONCUR-gated `deferred-scope-out` filing (dry-run by default; `{ file: true }`
  to create issues)
- `budget` floor on the verify fan-out with logged UNVERIFIED coverage

## Still NOT ported (next increments)

- **semgrep bootstrap + bash→shellcheck substitution.** The `semgrep` dimension
  tells the agent to run `ensure-semgrep.sh`, and `bashOnly` suppresses semgrep,
  but the shellcheck substitute dimension is not wired.
- **`gdpr-gate` is approximated** by routing to `data-integrity-guardian` with a
  GDPR lens rather than invoking the real deterministic `gdpr-gate` skill (its
  Art. 9 escalation + `compliance-posture.md` write are skill-side).
- **Follow-through auto-wiring** — filed scope-outs don't yet scaffold the
  `<!-- soleur:followthrough -->` directive + verification script.
- **Anti-slop Tier-1 scanner hook** (deterministic, runs inline in the SKILL).
- **Pipeline-mode compact-marker output** for `one-shot` / `work` callers.

## Validation

`review.workflow.js`'s control flow (conditional fan-out, pipeline verify,
majority survival, CONCUR flip, dry-run filing, budget floor) is exercised by a
stub harness with **no real agents / zero tokens** — see the PR description for
the matrix. The live A/B on PR #5006 covers the real-agent path.
