---
title: "Gate an operator-facing auto-close on a fresh measurement, not recorded evidence"
date: 2026-10-27
issue: "#9061, #10835, #10768 (PR #11296)"
category: workflow-patterns
---
# Gate an operator-facing auto-close on a fresh measurement, not recorded evidence

`apply-deploy-pipeline-fix.yml` closed `infra-drift` issues on (a) an infra-config `verified` verdict about host config files and (b) the issue's newest recorded plan — both captured BEFORE the apply. Fix: a `drift_plan` step re-runs the drift cron's own read-only `plan -detailed-exitcode` after the apply; the close `if:` requires `exit_code == '0'` (skipped step → empty output → fail-closed by construction).

## Session errors caught by review, not by the first draft

- **A token-presence assert is not a binding assert.** `exit_code=` + `$GITHUB_OUTPUT` present passed `echo "exit_code=0"` — the constant-laundering class. Pin the binding (`exit_code=$EXIT_CODE` + `EXIT_CODE=$?`) and mutation-test it.
- **`in:title` is a TOKEN search.** `infra: drift detected in web-platform/sentry` matched the `web-platform` close loop — a root never measured. Exact-title match mirrors the filer's own dedup.
- **Cross-verification beats self-disclosure:** two independent seats (pattern, code-quality) empirically reproduced the unbound-exit_code survival; data-integrity found the cross-stack arm by reading the filer's dedup, not the close path alone.
