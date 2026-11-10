# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9137-placement-aware-execution/knowledge-base/project/plans/2026-11-10-feat-inngest-placement-aware-execution-plan.md
- Status: complete

### Errors
- No `run_subagent` tool in the subagent's harness — agent spawns (CTO rulings ×2, CPO sign-off, condensed review panel) ran via the `claude` CLI instead; CPO and spec-flow analyzer approximated by plain `claude -p` prompts.
- First CTO ruling on T2 rested on a wrong premise (`SOLEUR_PROXY_BIND` literal `0.0.0.0` in container); re-spawned with corrected evidence — final ruling uses `SOLEUR_HOST_PRIVATE_IP`.
- First `git commit` attempt blocked by main-branch guard via `workdir`; succeeded with explicit `cd`.
- `plan-sharp-edges.md` (~150 KB) not read in full — highest-risk entries covered by guard-contract lint, panel review, and prior plan sharp edges.
- Plan review ran as one condensed panel spawn (not full named-panel fan-out); mechanical findings applied, taste rows persisted to `decision-challenges.md`.

### Decisions
- T1 — mechanism (CTO): Option C — app-layer fnId-aware forwarder in `app/api/inngest/route.ts`; `portable` executes where it lands, `host-affine`/`volume-bound`/unknown forward verbatim to the exec host; one app id, one serve URL, zero migration.
- T2 — exec identity (CTO, re-ruled): new `-e SOLEUR_HOST_PRIVATE_IP="$PROXY_BIND"` in `ci-deploy.sh` vs hardcoded `10.0.1.10` pin; unset/empty → HTTP 503 refuse, never local-execute.
- T3 — transport (CTO): pinned TLS reusing `PROXY_TLS_*` + `rejectUnauthorized: true`; receiver is a sibling listener on a dedicated port.
- T4 — scope (CTO): primary target only; fallback (a) second SDK worker stays deferred — trigger unmet.
- Premise finding: web-2 has served LB weight 1 since 2026-11-08 — placement exposure is LIVE today (~50% of pinned step calls land on web-2); plan frames fix as closing a live breach, optional operator-authorized `ga-pool-update mode=drain` interim row (T4a).

### Components Invoked
- soleur:plan (full phase run), soleur:deepen-plan (gate suite 4.4–4.13 all PASS/N/A)
- Agents via claude CLI: engineering/cto (×2), product CPO, condensed eng review panel
- Scripts: cloud-detect.sh, collision-precheck.sh 9137, lint-guard-contract.py
- Commits: 631fb7e571 (plan+tasks+decisions), fb6b92517a (review revisions + deepen record); draft PR #12554

## Operator Constraints

- constraint: 10382 operator-reserved - prod-mutating INNGEST_SIGNING_KEY rotation plus counsel - do not start without the operator.
- constraint: 8620 unblocked for the Inngest row - no hcloud encryption mechanism - record why-not when triaged.
- constraint: 9927 blocked on the 2026-11-24 inngest-host-replace window plus operator decisions.
- constraint: 12479 deferred p3.
