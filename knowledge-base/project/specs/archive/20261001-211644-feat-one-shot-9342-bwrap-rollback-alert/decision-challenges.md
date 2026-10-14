# Decision challenges — feat-one-shot-9342-bwrap-rollback-alert

Taste-class plan-review findings (headless run; none changes the operator's stated scope). For `ship` Phase 6 to render.

1. **Generic alert-parity test instead of a bespoke guard (CTO, taste).** Six near-identical per-alert guards exist; every new alert costs a manual M17 bump. A generic test (every `logtail_exploration_alert` has a matching exploration, both `-target=` lines, `paused=false`, derived-not-hardcoded exploration count) would cover R6/R7 for all alerts. Plan keeps a trimmed bespoke guard for the alert-specific couplings (needle read from the emitter, no-`host_name`, runbook anchor). Candidate follow-up issue (re-evaluate when a 10th Logs alert is added).
2. **`recovery_period` 600 vs ~1800 (CTO, taste).** A deploy retry cycle can reopen the incident after the 10-minute auto-resolve. Plan keeps the sibling's 600 as a verbatim copy.
3. **R4 (no-`host_name` mutation row) (DHH said cut; CTO said keep as the best row).** Plan keeps it: it encodes a regression the live probe found (3 host_name values carry `ci-deploy` rows).
4. **Dead-man alert for "ci-deploy rows stopped shipping" (CTO, taste).** The `SANDBOX_PROBE_OK` pass-path marker is a cheap dead-man's switch; out of scope for #9342. Candidate follow-up.
