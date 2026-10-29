---
title: Decision challenges — feat-one-shot-observability-vendor-prb-destroy
date: 2026-10-29
branch: feat-one-shot-observability-vendor-prb-destroy
---

# Decision challenges

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Pruned-monitor guard posture: shared `PRUNED_MONITOR_SLUGS` exemption set in the strict parity guards vs stripping the 43 emitters (SENTRY_MONITOR_SLUG consts + workflow `sentry-heartbeat` steps) | technical | Ruled by CTO agent, 2026-10-29: exemption set, keep all 43 emitters — spec NG4 non-goals emit-path edits verbatim and stripping is a prod-behavior change riding inside an IaC-destroy PR; `PRUNED ∩ declared = ∅` + `PRUNED ⊆ producers` keep the exemption honest. Correction: consumers are THREE sites, not three files — `sentry-monitor-iac-parity.test.ts` code→IaC (:239-249) and workflow→IaC (:158-167), and `function-registry-count.test.ts` guard (c) (:332-340); `sentry-cron-monitor-routing-parity.test.ts` does NOT consume the set (declared-universe only) — wiring it there is dead code. |
| `c4-count-parity.test.sh` `derive_github_slugs` semantic shift: raw `monitor-slug:` literal count → live-backed intersection (workflow slugs ∩ declared tf names) | technical | Ruled by CTO agent, 2026-10-29: intersection for C5/C6/C9 — a raw count (22) asserts numbers with no live referent post-destroy (14 live-backed). Mandatory amendment: split the derivation — keep a raw-literal `derive_github_emitter_slugs` consumed ONLY by the `c5 -ge c1` tail invariant (:203-212; C1=19 emitter files would falsely red a live-backed C5=14), while the intersection feeds C5/C6/C9; the comment must name the invariant split or a maintainer will "simplify" it back. |
| #10972 (route scheduled-orphan-sweeps monitor, due 2026-10-27) disposition after destroy | technical | Ruled by CTO agent, 2026-10-29: re-classed from `operator (scope)` to technical bookkeeping — the scope question was adjudicated by merged #6590 + PR-A; close #10972 as OBE post-merge AFTER the apply destroys the monitor, comment citing the destroy + surviving `notify-ops-email` cover AND naming the Resend-mail-key common-mode loss. Two added tails: (i) retire the followthrough probe per its own contract at `scripts/followthroughs/orphan-sweeps-relook-10972.sh:69-72` — delete probe + `orphan-sweeps-relook-10972.test.sh` + its `run_suite` line in `scripts/test-all.sh`, regenerate `suite-shard-legs.tsv`/`suite-durations.tsv` via `regenerate-shard-manifest.py --incremental --write`, drop the `follow-through` label; (ii) update the stale comment in `scheduled-terraform-drift.yml` ~L3311-3316 ("only monitoring path that does not use" the shared mail key, refs #10972). |
| `alert-reference.json` regeneration in PR-B | technical | Ruled by CTO agent, 2026-10-29: skip — the projection (`tests/scripts/lib/sentry-alert-projection.jq:232`) selects `sentry_alert` only, `monitor_ids` is untouched and binds the 22 kept detectors (`alert-reference.json` `cron-monitor-failure.detectorIds` verified = 22); the unknown-detector floor cannot trip on a destroy-only diff. If `plan_pr` reds on it anyway, take the `sentry-alert-reference-expected-<run-id>` artifact route, never hand-edit. |
