# Workflow-backed `soleur:review` (prototype)

`review.workflow.js` is a [dynamic workflow](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code)
re-implementation of the core engine of the `soleur:review` skill. It is a
**prototype for A/B comparison** against the prose-driven SKILL.md — not a
replacement. Both can coexist.

## What it does

```
Classify ──▶ Review ──▶ Verify ──▶ Synthesize
 (1 agent)   (2/4/8     (N skeptics  (dedup +
             dimension   refute each   provenance
             agents)     finding)      disposition)
```

1. **Classify** — one agent runs the same change-class predicates as
   `SKILL.md` §"Change Classification Gate" and returns a structured class
   (`code` / `non-code` / `lockfile-only` / `deletion-dominated`).
2. **Review** — the script (not the model) maps that class to its dimension
   list and fans out one agent per lens. Each lens reuses the **real Soleur
   reviewer agent** via `agentType`, so it inherits that agent's system prompt.
3. **Verify** — every finding is handed to an adversarial skeptic that defaults
   to `isReal=false` and must be argued *out* of refutation. Runs as a
   **no-barrier pipeline**: a dimension's findings start verifying the instant
   that dimension lands, while other dimensions are still reviewing.
4. **Synthesize** — confirmed findings are deduped by `file+title`, then given
   a deterministic `disposition` (`fix-inline` vs `scope-out-candidate`) from
   the SKILL's cost-of-filing rule encoded in code.

## How to run it

From a session where the diff under review is reachable (`origin/main...HEAD`):

```
Workflow({ scriptPath: "plugins/soleur/skills/review/workflows/review.workflow.js",
           args: "1234" })          // PR number, branch name, or "" for current branch
```

`args` may also be `{ target: "1234", deepReview: true }` to force the full
8-dimension pass. The literal phrases `deep review` / `full review` in a string
`target` trigger the same override, matching the SKILL.

Iterate by editing the file and re-invoking with the same `scriptPath`. To
resume an interrupted run, add `resumeFromRunId: "<runId>"` — unchanged
`agent()` calls return cached results instantly.

## What it inherits from Workflow that the SKILL can't express today

| Capability | SKILL.md (Task-spawn prose) | This workflow |
|---|---|---|
| Class → fan-out decision | Model interprets a bash decision tree each run | Deterministic JS lookup (`CLASS_DIMENSIONS`) |
| Per-finding verification | None — CONCUR fires only on scope-out *filings* | Every finding adversarially refuted before surfacing |
| Review→verify scheduling | Implicit barrier (waits for all reviewers) | No-barrier `pipeline()` — verify starts per-dimension |
| Disposition (fix vs file) | Prose cost-of-filing gate, model-applied | `disposition()` — code, auditable, identical every run |
| Resume after interruption | Restart from zero | Journaled — cached prefix replays instantly |
| Token ceiling | Hand-written "API budget" warnings | `budget.total` is an enforced hard cap (wire in if needed) |
| Structured output | Parse agent prose by hand | Schema-validated, agents retry on mismatch |

## Deliberately NOT ported (yet)

The prototype covers the **always-on dimension agents + verification +
disposition**. It does not yet implement the SKILL's:

- conditional agents (Rails reviewers, migration experts, `test-design-reviewer`,
  `semgrep-sast` bootstrap, `user-impact-reviewer`, `gdpr-gate`),
- anti-slop Tier-1 scanner hook,
- the full `deferred-scope-out` GitHub-issue filing flow + follow-through
  wiring + CONCUR self-check,
- pipeline-mode compact-marker output for `one-shot`/`work`.

Those are the next increment if the A/B justifies adopting the workflow form.
The disposition stage emits `scope-out-candidate` rather than auto-filing, so a
human (or a downstream CONCUR step) still owns the filing decision.
