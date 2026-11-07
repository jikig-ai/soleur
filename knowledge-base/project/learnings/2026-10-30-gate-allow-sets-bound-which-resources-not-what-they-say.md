---
title: "A plan gate's allow-set bounds WHICH resources — not WHAT THEY SAY"
date: 2026-10-30
tags: [plan-gates, terraform, review, cf-lb-overlay, 11181]
---

# Learning: grade `.change.after` identity, not just address+action — and put every new gate on the shared preamble floor

## Problem

PR #11652 shipped `tests/scripts/lib/cf-lb-overlay-gate.sh` — four per-arm plan graders that asserted `.address ∈ allow-set` + `actions ∈ positive-verb-list` and nothing else. The review panel (13 seats incl. a structural-enumeration seat) demonstrated, with live `jq` splices, that all of these passed rc=0:

- `cloudflare_record.lb_staging` create with `after.name = "app"` / `"*"` — a second proxied A record on `app.soleur.ai` (round-robin prod hijack), on the reviewer-free `infra-privileged` arm.
- `cloudflare_load_balancer.app` create with a wrong live hostname, `enabled=false`, or pool origins repointed at an attacker IP.
- `["forget"]` (`removed{destroy=false}`), `["import"]`, `["no-op"]+importing`, `["moved"]`, `actions:[]`, and missing `.change` entries — a positive `{create,delete,update,replace}` filter silently admits every verb Terraform adds later.
- The lib used `local plan` (not `plan_json`), so `test-plan-gate-preamble.sh`'s drift derivation never scanned it — a new lower-tier gate invisible to the coverage guard.
- A continuity-verdict `GO` on zero samples (`bad==0`, `total` unasserted) and a vacuous `head -3` liveness check.
- `jq`'s `//` treats `false` as empty: `(.after.enabled // true)` maps `enabled=false` → `true`. Use `if has("x") then .x else true end`.

## Solution (what actually fixed it, PR #11652 commits `65a969beb8` + `c515643f06`)

1. **Identity pins in every gate** — assert `.change.after` values that carry the property's *name*: record `{name:lb-staging,type:A,proxied:true}`, GA `{name:app.soleur.ai,enabled!=false,proxied!=false,origins ⊆ web-1 IP read off the plan's no-op server entry}`.
2. **Negative action filter** (vector-redeliver convention): only `["no-op"]`/`["read"]` are not-a-change; everything else must satisfy the allow-set.
3. **`plan_gate_assert_readable` + `plan_gate_assert_classifiable` + `local plan_json`** — the classifiable assert rejects `actions:[]`/scalar `.change`/missing keys; the parameter name is what the drift check greps for.
4. **Ordering/state asserts where ordering is the property** — the overlay gate requires the record `["no-op"]` (record→settle→overlay); the record gate tolerates converged no-op (idempotent re-dispatch) and names the next arm.
5. **Verdict floors** — a GO needs a minimum sample count, not just zero bad ticks; liveness via `[[ -s ]]`, never `head` on an existing file; `kill "${PID:-0}"` is a kill-0 footgun — guard with `[[ -n ]]`.
6. **Registration is part of the artifact** — the new gate suite was orphaned (no `run_suite` line → `lint-orphan-test-suites` red) and the workflow's destroy steps red the G2 census until `working-directory` used the `REHEARSAL_DIR` env name `g2IsSubRoot()` exempts. Both were verified CI-red before the fix commit.

## Key Insight

The LB hostname pin existed because the authors *knew* the class ("a config edit cannot silently perform the GA overlay") — and it still wasn't extended to the DNS record, the *more directly* prod-affecting primitive. Naming the class in a comment is not covering the class; an enumeration seat (map every write path to the sink) is what found all instances at once.

## References

- `tests/scripts/lib/plan-gate-preamble.sh` (the floor), `vector-redeliver-gate.sh` (negative filter + idempotency doctrine), `git-data-rung2-rehearsal.yml` (prod-read grep + honesty block).
- CTO ruling 2026-10-30: staging create arms keep `infra-privileged` — a pre-plan reviewer approval buys no independent authorization and stalls the shared apply serializer.
