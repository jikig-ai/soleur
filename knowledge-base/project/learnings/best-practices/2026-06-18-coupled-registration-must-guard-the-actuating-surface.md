# Learning: when a fact is registered across N coupled surfaces, the parity test must guard the surface that ACTUATES — not just the declarative ones

category: best-practices
module: apps/web-platform/infra (deploy_pipeline_fix), .github/workflows, #5505

## Problem

`deploy_pipeline_fix`'s trigger-file set is registered across FIVE surfaces: (1) server.tf `triggers_replace` hash, (2) ship `DEPLOY_PIPELINE_FIX_TRIGGERS` array, (3) ship `DPF_REGEX`, (4) the ship prose list, and (5) `apply-deploy-pipeline-fix.yml`'s `on.push.paths` — the filter that actually decides whether the auto-apply *fires*. #5492 added the 4 inngest cutover scripts to surfaces 1–4 and the `ship-deploy-pipeline-fix-gate.test.ts` `TRIGGER_FILES` fixture. The gate test went green. But surface 5 — the **actuating** one — was never updated, and the test never asserted parity against it.

Result: the inngest-only #5504 merge changed a file that was in the hash but NOT in the workflow `paths` filter → the auto-apply did not fire → a merged, CI-green fix did not reach prod until a manual `workflow_dispatch`. The "merged ≠ deployed" silent-stale class the deploy_pipeline_fix gate exists to prevent.

## Root cause of the miss

The drift guard (`ship-deploy-pipeline-fix-gate.test.ts`) asserted parity across the *declarative* surfaces (server.tf hash ↔ ship array ↔ regex ↔ TRIGGER_FILES) but NOT against the workflow `paths` filter. So adding scripts to the four guarded surfaces passed green while the one surface that controls execution silently drifted. **An unguarded surface in a coupled set is invisible drift waiting to happen.**

## Solution / durable rule

When a value must be registered across coupled surfaces, identify the **actuating** surface — the one whose content gates whether the action actually happens (here: the workflow `on.push.paths`; the hash only changes *what terraform sees*, not *whether the workflow runs*) — and (a) include it in the registration, (b) add a parity assertion guarding it. #5505 adds the 4 scripts to the paths filter and a test asserting `paths == TRIGGER_FILES ∪ {server.tf}` (set-equality, both directions). server.tf is the only legitimate extra in `paths` (it's the hash *definition*, not a hashed file).

Litmus when registering across surfaces: "If I change only one of these files, does every mechanism that should react actually react?" Trace the *trigger*, not just the *data*.

## Key Insight

A green parity test proves only the surfaces it compares. The surface most likely to be forgotten is the CI `paths:`/trigger filter, because it lives in a different file class (a workflow, not the resource/array/regex) and "feels" like plumbing rather than part of the registration. Enumerate the actuating surface explicitly and guard it.

## Session Errors

1. **#5492 registered the inngest scripts across 4 declarative surfaces but missed the actuating workflow `paths` filter, and the gate test didn't guard it.** **Recovery:** the gap surfaced when #5504's inngest-only merge didn't auto-deploy (manual `workflow_dispatch` needed); #5505 adds the paths + a parity test. **Prevention:** when a registration spans coupled surfaces, the parity test must include the surface that fires the action, not only the declarative ones.
2. **The new paths-extraction regex initially spanned the `workflow_dispatch` block** (latent phantom-path risk if a future `type: choice` input adds quoted `options`). **Recovery:** review (deployment-verification-agent, P3) → anchored the capture to the `apps/web-platform/infra/` prefix. **Prevention:** when slicing a YAML sub-block by string offset, anchor the item regex to the expected value shape, not just the list-item syntax.

## Tags
category: best-practices
module: deploy-pipeline-fix, ci-coupling, drift-guard, #5505
related: [[2026-06-17-webhook-combinedoutput-success-path-must-be-pure-json]], [[2026-06-17-synchronous-webhook-consumer-must-dump-response-body]]
