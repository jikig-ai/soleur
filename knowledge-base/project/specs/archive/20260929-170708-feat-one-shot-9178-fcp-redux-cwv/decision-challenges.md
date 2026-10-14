# Decision Challenges — feat-one-shot-9178-fcp-redux-cwv

Headless planning run (Task subagent, sequential-fallback). Items here are taste/operator-call findings `ship` Phase 6 renders into the PR body and files as `action-required` if warranted.

## 1. Client transaction sampling rate (0.1) is an unmeasured guess

The plan sets `tracesSampler` → `0.1` for real sessions (1.0 under the probe marker). No measurement of the session population exists in-repo — if daily authenticated pageloads are small, `1.0` for all sessions is affordable and gives complete field data; if large, `0.1` may still be quota-heavy. Operator call: pick the steady-state rate before merge, or confirm quota headroom (plan task 2.5).

## 2. Existing `.pen` reused rather than a new wireframe

The mechanical UI-surface gate (Files to Edit include `app/(dashboard)/dashboard/page.tsx` + `components/dashboard/*.tsx`) forces BLOCKING tier. The plan satisfies `wg-ui-feature-requires-pen-wireframe` by referencing the committed `dashboard-load-states.pen` (which already encodes the loading states this change exercises) instead of authoring a fresh `.pen`. If the operator would rather see the deferred-set semantics drawn explicitly, the work phase should extend that `.pen` (task 0.1).

## 3. `getUser` verdict caching recorded as verify-only

Issue text said "re-examine whether mw-auth can ride a shorter-cached verdict." ADR-253's 2026-09-26 amendment already rejected that cache by measurement, so the plan treats the bullet as settled (no middleware diff). If the operator wants it reopened, the gate is a fresh probe run showing `mw-auth` dominating the warm tail — not a judgment call the plan can make.

## 4. Deferred-fetch set is fixed at implementation time, not in the plan

Which keys gate behind post-FCP (nav-badge counts, releases, team-names are candidates) depends on the probe census + the `.pen` state list (FR4). The plan deliberately does not freeze the set — conservative default is ungated.
