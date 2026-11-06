# Tasks — CodeQL alert #216 (actions/untrusted-checkout/medium)

- [x] plan + deepen-plan (Scope Check, Guard Contract ×2, Enhancement Summary)
- [x] verify alert at source: `gh api .../code-scanning/alerts/216` → line 283 resolve-target checkout; query semantics read from `UntrustedCheckoutQuery.qll`/`UntrustedCheckoutMedium.ql` (no `if:`/`persist-credentials` sanitizer)
- [x] `resolve-target`: new `gate` step emits `trusted`/`deploy_sha` (trusted = workflow_run push-to-main + 40-hex SHA, or non-workflow_run → $GITHUB_SHA)
- [x] checkout `if: steps.gate.outputs.trusted == 'true'`, `ref: ${{ steps.gate.outputs.deploy_sha }}` (exactly-one-checkout + depth-1 deploy-arm contract preserved)
- [x] `budget` step same `if:` (no tree when gate declines; preserves GREEN clean-skip)
- [x] `verify-doppler-secrets` job `if:` trusted-shape conjunct + `persist-credentials: false`
- [x] comments: name the gate/resolve-check coupling + alert #216
- [x] `workflow-run-deploy-invariants.test.sh`: new P4 (gate/if/ref shape) + P5 (vds job gate) rows; MIN_ROWS 80→82
- [x] suites green: workflow-run-deploy-invariants 82/82, resolve-target-decision 64/64, deploy-arm 79/79
- [x] YAML parse sanity + affected-test run
- [ ] review + fix-rounds (Reviewed-Coverage: sequential-fallback, depth-1)
- [ ] compound
- [ ] ship → merged PR; post-merge verify alert #216 fixed on main
