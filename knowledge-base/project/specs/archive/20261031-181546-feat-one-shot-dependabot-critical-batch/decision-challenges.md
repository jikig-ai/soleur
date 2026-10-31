# Decision Challenges — feat-one-shot-dependabot-critical-batch

Pipeline context: one-shot → plan → deepen-plan (headless; no Task/agent spawn
capability in this harness, so no CTO/advisor consult could be executed. Rows
that would carry `pending - assumed` under technical-ruling-delegation.md are
classified `taste` — `technical-ruling-gate.sh` rejects unruled `technical`
rows, and each choice below is a verifiable mechanical default with a named
fallback rather than a fork requiring a binding ruling).

| Item | Class | Ruling |
|------|-------|--------|
| How to clear `zod@3.25.76` nested under `@likec4/core@1.50.0` (which bundles `zod ^3.25.76`, no peer declaration): scoped npm override vs bumping `@likec4/core`+`@likec4/diagram` to 1.60.0 (native `zod ^4.6.5`) — the latter drags the six-file likec4 CLI pin-train (Dockerfile, ci.yml, main-health-monitor.yml, render-c4-model.sh, generate-c4-from-components.ts, lib/c4-from-components.ts) plus ~10 minor versions of renderer changes into a security batch | taste | Scoped npm override `"@likec4/core": {"zod": "^4.6.6"}` — minimal blast radius, consistent with the grouped-bump shape; escalate to the 1.60 pin-train bump only if `test/c4-*` suite, typecheck, or `next build` goes red under the override. If the override ships, file a follow-up issue for the likec4 1.60 bump on its own schedule |
| `inngest@4.26.0` nested `zod@3.25.76` — no upstream zod-4 build exists (latest 4.26.2 still bundles `^3.25.0`), but its peerDependencies accept `^3.25.0 \|\| ^4.0.0` | taste | Scoped npm override `"inngest": {"zod": "^4.6.6"}` — upstream-sanctioned per the peer range; verified by `test/server/inngest/**` + `test/helpers/inngest-step-harness.test.ts` |
| Split assessment trips the >=4-subsystem-roots threshold (`apps/web-platform`, `spike`, `plugins/soleur`, `scripts`) | taste | Single PR — the multi-root shape IS the deliverable (grouped bump per merged PR #11646; the merge queue merges one entry per ~50-min cycle so splitting multiplies the cost the batch avoids). Non-lockfile diff ~60 lines |
| Brand-survival threshold `none` for a critical-RCE security batch | taste | Declared `none` — the change removes CVE vectors and adds no data path; worst-case breakage (C4 render / inngest job regression) is revertible and suite-gated before merge, below the single-user-incident bar |
| Deferral-tracking for the likec4 1.60 pin-train bump (conditional on override shipping) | taste | If the override ships, the work phase files a follow-up issue (`chore(deps): likec4 1.60 pin-train bump`) at ship time rather than now — the need is conditional on which option lands |
