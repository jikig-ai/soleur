# Decision challenges — cf-token-scope default-token profile (plan phase, 2026-10-28)

Headless subagent plan run (OpenCode, nesting depth 1): no advisor consult and no
AskUserQuestion were possible. Items marked `pending - assumed` carry the plan's
chosen default; the parent session / operator rules on them. Ruled rows are
transcribed from the CTO ruling on epic #11181
(<https://github.com/jikig-ai/soleur/issues/11181#issuecomment-6464031261>) — not
re-litigated here. Plan:
`knowledge-base/project/plans/2026-10-28-feat-cf-token-scope-default-token-profile-plan.md`.

| Item | Class | Ruling |
|---|---|---|
| R1. Widen vs mint vs per-run co-sign for the LB capability | technical | **Ruled by CTO agent, 2026-10-28:** Widen the existing `CF_API_TOKEN` once to zone LB Edit + account Monitors-and-Pools Edit — least-privilege in-family with held DNS-edit terminal primitive; a sixth alias mint carries root-var whole-apply hazard + Doppler write; ≥2 apply-bearing acts make JIT co-sign ceremony without blast-radius reduction. Dissent recorded: probe script hardcoded to `CF_API_TOKEN_RULESETS` until this extension lands (this plan is that remedy). |
| R2. Profile mechanism vs raw `--token-var` knob | technical | **Ruled by CTO agent, 2026-10-28** (implicit in the ruling's binding precondition: the retained-scope re-check must cover THIS token) **+ this plan:** named profiles only, preserving SKILL.md's posture against arbitrary token probing. Raw-knob surface cut; the §Usage refusal is re-worded to "profiles only, no raw token-var knob". |
| D1. Profile identifiers and flag naming | technical | pending - assumed: `--profile <rulesets\|default-token>`, default `rulesets`; new id `default-token` binds Doppler `CF_API_TOKEN`. Alternatives: `api-token` / `lb` / `primary`. Assumed-because: mirrors the ruling's own phrase "default-token profile" (operator-answer comment: "the `cf-token-scope` default-token probe-profile extension"), and the TF default-alias it stands for. |
| D2. Assert-mode flag name | technical | pending - assumed: `--expect-lb-scopes` (valid only with `default-token`); `--target-entrypoint` stays rulesets-only; either mismatch ⇒ usage error exit 2 before any secret read. Alternatives: overload `--target-entrypoint lb`, or `--assert-lb`. Assumed-because: the brief's "--target-entrypoint style post-widen run" describes the *shape*, and an explicit name avoids implying rulesets-phase semantics. |
| D3. Exit-code contract | technical | pending - assumed: **no new numeric codes.** Retained-class regressions = hard fail (exit 3) in every profile. Baseline target 403 = distinct reported state `not-yet-widened (403)` + stdout `NOTE:` summary, exit-neutral (0). Assert mode: target rows must be authorized or exit 3 (`FAIL: LB scope still absent`). Alternative: dedicated exit 4 for the neutral state — cut because it widens SKILL.md's published 0/2/3(+78) contract with no scripting consumer that needs it today. |
| D4. Expected-missing status set | technical | pending - assumed: **403 only** (`.errors[0].code` parsed for the row suffix, e.g. `err 10000`); 404/5xx/000/degraded-200/wrong-shape stay hard-fail in BOTH modes (a zone-LB 404 can mean an un-subscribed add-on — a real signal, never silenced; a false-green of neutrality is the failure class this guard exists to prevent). Brief's parenthetical "(403/10000 => not-yet-widened)" read as 403-with-code-10000 typical, 403 authoritative. |
| D5. ADR-130 amendment / C4 update as plan deliverables? | technical | pending - assumed: **no** — Phase 2.10 detection judged not to fire (no ownership/tenancy move, no new substrate; the widen decision itself already lives under ADR-130's criteria and is recorded on the epic; the probe-profile is tooling inside this skill, documented in its SKILL.md). Reject-condition risk: a reviewer may read the ruling as extending ADR-130's probe-set contract — if so, a one-paragraph ADR-130 amendment is cheap; escalate rather than assume silently. |
| D6. Brand-survival threshold | taste | pending - assumed: `aggregate pattern` (a falsely-green retained-scope check hides a whole-list REPLACE drop degrading cache/WAF/redirects for all traffic at once; not one user's data, not zero). Drives review-panel size (ADR-267); `single-user incident` would over-scope it (no per-user data surface); `none` is wrong for a credential-scoping canary. |
| D7. Plan Step 4.5 scoped advisor consult | process | pending - assumed: **not run** — harness constraint (subagent, nesting depth 1; spawning `resolveAdvisorTier()` impossible). Parent session to run the consult with the curated payload (Overview + Implementation Phases + Guard Contract, the riskiest section) and route findings by class per the plan-skill contract. |

## Not Yet Specified candidates

None — no product fog found; implementation unknowns are resolved in the plan.
