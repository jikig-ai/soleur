---
name: five-agent-panel-orthogonal-axis-converges-on-delete
description: When a plan-review panel covers two orthogonal axes (simplification = DHH + code-simplicity; correctness = Kieran + architecture-strategist + spec-flow), independent convergence on the same scope from BOTH axes is a textbook "prefer delete over fix" signal. PR-1 of TR9 (#3948) had 4-of-5 agents flag `cron_run_ledger` from 4 different lenses (over-engineering / native-Inngest-semantics-duplicate / production plpgsql cast bug / 24h operator-retry trap); deletion dissolved all four findings AND the architecturally-suggested fix (forward-compatibility schema column) was made moot. Two latent-bug subpatterns surfaced alongside.
metadata:
  type: best-practice
  category: plan-quality
  module: plan-review
date: 2026-05-18
related_issues: [3948, 3947, 3244, 3940, 3985]
related_pr: "#3985 (draft)"
related_plan: knowledge-base/project/plans/2026-05-18-feat-pr-1-migrate-scheduled-daily-triage-to-inngest-cron-tr9-plan.md
related_adr: ADR-033 (active; I3/I4 refined post-review)
---

# Learning: 5-agent panel orthogonal-axis convergence is "prefer delete over fix"

## Problem

PR-1 of TR9 (#3948) — migrate `scheduled-daily-triage` GitHub Actions workflow to an Inngest cron function on the self-hosted Hetzner runtime — was framed by the author as a "proof-of-pattern" PR that would bind ~11 subsequent agent-loop cron migrations. Brand-survival threshold was `single-user incident`; plan-review fired the full 5-agent panel (DHH + Kieran + Code-Simplicity + Architecture-Strategist + Spec-Flow-Analyzer) per `plugins/soleur/skills/plan-review/SKILL.md`.

Plan v1 prescribed an ambitious primitive stack to "future-proof" the next 10 migrations:

- `cron_run_ledger` Supabase table + `record_cron_run(text, int) returns boolean` SECURITY DEFINER plpgsql function — a jitter-guard preventing duplicate fires within 80% of the cron interval (19.2h for daily).
- `claude-code-bootstrap.sh` + `terraform_data.claude_code_install` provisioner + `cloud-init.yml` `runcmd` addendum + `templatefile()` var passthrough — three IaC surfaces to install `@anthropic-ai/claude-code` on Hetzner.
- `cron-daily-triage.prompt.md` co-located markdown file read at runtime via `readFileSync`.
- 11 follow-up child issues pre-filed against #3948 umbrella at PR-1 plan-time.
- Sentry monitor rename (resource id + slug) from `scheduled-daily-triage` to `cron-daily-triage`.
- 16 acceptance criteria + 10 risks + 7-step Phase 0.

The 5-agent panel converged on **deleting** ~50% of this scope, not refining it. The author had been thinking "proof-of-pattern justifies extra structure"; the panel correctly identified most of the structure as speculative gold-plating that 10 future PRs would inherit as cruft.

## Solution

**Read both panels as orthogonal axes**, then apply the rule from `plan-review/SKILL.md`:

> "When BOTH panels fire on the same scope, prefer delete over fix — a feature that simultaneously triggers 'too complex, remove' and 'has 4 specific bugs' is over-architected; cutting it dissolves the bugs."

PR-1's actual convergence matrix:

| Plan v1 primitive | Simplification axis | Correctness axis | Action |
|---|---|---|---|
| `cron_run_ledger` table + RPC + jitter-guard step | DHH P0-1 ("absurd over-engineering"); Code-Simplicity P0 ("Inngest already serializes cron fires natively") | Kieran P0-1 (plpgsql cast chain throws at runtime); Spec-Flow AC34 (24h operator-retry trap) | **DELETE.** All 4 findings dissolve. Architecture-strategist's proposed F1 fix (rewrite the SQL) AND F4/F8 (forward-compat schema column) become moot. |
| `bootstrap.sh` + `terraform_data` + cloud-init dual path | DHH P1-1 (add to `package.json` instead); Code-Simplicity P0 (inline `remote-exec` or package dep) | — | **SIMPLIFY to 1-line `package.json` dep.** ~90 LOC cut. |
| `.prompt.md` co-located file + `readFileSync` | DHH P1-2 (inline as template literal); Code-Simplicity P1 (eliminates filesystem dep) | Kieran P0-2 (esbuild does not bundle non-imported `.md`; `readFileSync` would THROW at first fire on Hetzner) | **INLINE as TS template literal.** Latent production bug dissolved. |
| Sentry monitor rename | DHH P1-3 (continuity > naming aesthetics) | Architecture F5 (destroy-create produces alert-gap window) | **KEEP existing slug.** Code-comment documents the function-name vs slug mismatch. |
| 11 pre-filed child issues | DHH P0-3 (speculative-stale); Code-Simplicity P1 (creates ~11 zombie tickets) | Spec-Flow AC32 (markdown checkboxes vs native sub-issues unspecified — but resolves via "umbrella checklist only" path) | **CUT.** Single checkbox list on #3948 body; defer per-child issues to migration-start time. |
| T5 unit-test mirror of sentinel sweep | DHH + Code-Simplicity ("redundancy without a failure mode T5 catches the sweep misses") | — | **CUT.** |

Convergence count: **4-of-5 agents independently flagged `cron_run_ledger`**. The remaining 1 (architecture-strategist) proposed a fix path; the orthogonal-axis rule says delete-over-fix when BOTH simplification and correctness panels fire — which they did. The architecture-strategist's correctness concerns (F4 worker-restart abandonment, F8 forward-compat schema) dissolve once the ledger is cut: Inngest's native `retries: 1` + `concurrency: [{scope: "fn", limit: 1}]` covers the worker-restart case; the schema column is YAGNI.

**Single-reviewer P0s applied as additive (not converging) fixes:**

- Kieran P0-3 (AbortSignal grandchild propagation): real correctness bug across cron-* class. Added `detached: true` + process-group SIGTERM→SIGKILL at +5s escalation.
- Architecture F2 (55-min × 80-turn = 0.69 below 0.75 peer-ratio floor): set precedent the next 10 migrations would clone. Raised to 60 min.
- Architecture F7 (`account`-scoped concurrency to prevent Hetzner OOM under future cron-* fan-out): cheap forward-compatibility primitive. Added.
- Spec-Flow AC37 (event trigger for operator manual-retry): operator UX gap. Added `[{cron:"..."},{event:"cron/...manual-trigger"}]` trigger array.
- Architecture F6 (`BARE_IMPORT_RE` for sentinel inverse-assertion): real shape escape (bare named import without immediate call). Added third regex.
- Kieran P1-2 (extract inverse-assertion sentinel to own file): cleaner ownership, two simple files vs. one mixed-invariant file.

**Plan v1 → v2 net:** ~700 → ~450 lines plan, ~290 LOC dropped from implementation (migration file, bootstrap script, cloud-init addendum, prompt file, T5 test, 11 phantom issues), 3 production bugs eliminated before merge.

## Key Insight

**Orthogonal axes converge for a reason.** A primitive that DHH flags as "absurd over-engineering" AND Kieran flags as "type-broken plpgsql" AND Code-Simplicity flags as "duplicates native substrate" AND Spec-Flow flags as "blocks operator manual retry for 24h" is not 4 separate problems with one feature — it is one over-architected feature whose unloved-ness shows up in every reviewer's lens. The simplification axis sees "too much complexity for the value"; the correctness axis sees "too much complexity to get right." They converge because they are reading the same underlying signal: this primitive is not load-bearing.

The architecture-strategist's role in the panel is specifically to surface concerns the simplification axis ignores (blast radius, peer ratios, schema forward-compatibility, alert-gap windows). When architecture-strategist proposes a FIX while the simplification + correctness axes propose DELETE, the deletion typically wins — because the architecture-strategist's fix is correct ONLY IF the primitive is load-bearing, and the convergence from the other two axes is precisely the evidence that it is NOT load-bearing.

**This is the textbook case for the rule.** The plan-review SKILL.md already encoded this from the 2026-05-11 #2720 plan v1→v2 cycle; PR-1 of TR9 is the second confirming instance. The rule does not need elaboration; it needs application — and the case demonstrates that applying it produces a strictly better PR-1 that also makes the next 10 mechanical migrations cheaper.

## Two latent-bug subpatterns surfaced alongside

### Subpattern A — plpgsql `RETURNING expr INTO var` type-mismatch is a high-signal latent bug class

Plan v1 declared `v_last_run_at timestamptz;` then wrote:

```sql
returning (last_run_at = v_now) into v_last_run_at;
return v_last_run_at is not null and v_last_run_at::text::boolean;
```

`(last_run_at = v_now)` is a boolean expression; assigning boolean into a `timestamptz`-typed variable raises a runtime type error AT FIRST CALL (`column ... is of type timestamp with time zone but expression is of type boolean`). The `::text::boolean` cast chain is unreachable. Postgres rejects the assignment before the cast can execute.

This bug class is **invisible to local manual plan review** — the author wrote it, the spec author wrote a Sharp Edge flagging "if the cast form is brittle, pivot at /work-time" without recognizing the bug, and DHH + Code-Simplicity (whose lens is over-engineering / native-substrate-duplication, not SQL semantics) did not catch it. Only Kieran's correctness-axis review caught it by mentally executing the plpgsql signature.

**Plan-time prevention:** when a plpgsql function uses `RETURNING expr INTO var`, type-check `expr` against `var`'s declared type as an explicit step. The Kieran-rails-reviewer agent does this automatically; the plan author often does not.

### Subpattern B — Architecture-strategist's peer-ratio catch validates the 5-agent panel (not 3-agent)

Plan v1 set `MAX_TURN_DURATION_MS = 55 * 60 * 1000` (55 min) with the rationale "preserves rollback headroom vs the old 60-min GitHub Actions timeout." Architecture-strategist's F2 finding: the `2026-03-20-claude-code-action-max-turns-budget.md` peer-ratio learning records 0.75 min/turn as the floor for daily-triage-class workflows; 55 min × 80 turns = 0.69 min/turn — below the floor. The agent at 73+ turns would be aborted, producing the partial-progress silent-failure shape this migration was meant to eliminate.

DHH, Kieran, Code-Simplicity, and Spec-Flow did NOT catch this — it requires (a) knowledge of the peer-ratio learning, (b) numerical reasoning, and (c) the framing that the primitive sets precedent for 10 future PRs. Architecture-strategist's brief explicitly covers blast-radius analysis across migrations; this is precisely the gap the 5-agent panel was designed to close vs the 3-agent baseline.

**Plan-review rule confirmation:** at brand-survival threshold `single-user incident`, the 5-agent panel is justified; the architecture-strategist's value-add is concrete and non-overlapping with the other four lenses. This case is the second confirming instance of the rule (first was 2026-05-11 #2720).

## Session Errors

1. **Plan v1 shipped 3 latent production bugs the author did not catch.** (a) plpgsql cast-chain runtime error in `record_cron_run` (Kieran P0-1); (b) `readFileSync(PROMPT_PATH)` would throw because esbuild does not bundle non-imported `.md` (Kieran P0-2); (c) AbortSignal SIGTERM does not propagate to grandchildren without `detached: true` + process-group kill (Kieran P0-3). — Recovery: all three fixed in v2 via 5-agent reconciliation. — **Prevention:** plan-time mental-execution against plpgsql RETURNING-INTO types; cite the build-pipeline (esbuild config) when prescribing `readFileSync` from `server/**`; explicitly name SIGTERM-propagation strategy when prescribing `child_process.spawn` with timeout. These three checks belong in plan-review brief generation (already encoded in Kieran's brief). The author's protection is the 5-agent panel firing on brand-survival plans.

2. **Plan v1 over-specified primitives by ~290 LOC.** Speculative-gold-plating framed as "proof-of-pattern" — the author conflated "primitives reused across 10 PRs" with "ALL primitives in PR-1 must be permanent." — Recovery: 4-of-5 orthogonal-axis convergence cut the unloved primitives. — **Prevention:** "proof-of-pattern" framing earns a tighter scrutiny pass, not a looser one. Every primitive in a proof-of-pattern PR-1 must answer "what failure mode does this prevent that the substrate doesn't already prevent natively?" Inngest dedupes crons → no jitter-guard; deploy pipeline runs `npm install` → no bootstrap.sh; esbuild bundles TS → inline prompts. Pattern: enumerate substrate-native capabilities before specifying new primitives. Captured in plan-review SKILL.md's existing prefer-delete-over-fix rule (no new rule needed).

## Sister learnings

- `2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md` — first instance of the orthogonal-axis delete rule (PR #2720 plan v1→v2; 4 P0 issues dissolved on matrix-split cut). This learning is the second confirming instance. Together they constitute "rule is well-supported by N=2 incidents" — no further generalization needed.
- `2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md` — similar pattern: plan-time vs review-time vs work-time cost asymmetry. Plan-time review beats work-time discovery on every axis.
- `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md` (today's other learning) — informed AC4 in plan v2 (single end-of-job heartbeat shape, NO two-step in_progress→ok).

## Related

- **PR-1 plan (v2):** `knowledge-base/project/plans/2026-05-18-feat-pr-1-migrate-scheduled-daily-triage-to-inngest-cron-tr9-plan.md`
- **Brainstorm:** `knowledge-base/project/brainstorms/2026-05-18-tr9-agent-loop-crons-inngest-migration-brainstorm.md`
- **ADR-033** (refined post-review at I3 + I4): `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`
- **Issue:** #3948 (umbrella)
- **Draft PR:** #3985
- **Plan-review skill** (rule source): `plugins/soleur/skills/plan-review/SKILL.md` "orthogonal-axis" paragraph + 2026-05-11 reference.
