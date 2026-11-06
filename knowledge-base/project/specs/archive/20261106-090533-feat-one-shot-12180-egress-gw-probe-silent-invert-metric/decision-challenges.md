# Decision challenges (plan phase, headless)

Rulings and findings persisted during planning of the egress-gateway probe-silence alert fix (Ref #12180). The
binding CTO ruling supplied with the task (invert the metric, `higher_than 0`, keep `treat_as_zero`, add a
reversible canary pair, poller as fallback only) is the default and is not re-asked.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Canary notification channel: `email = true` (the shape all 18 siblings use) versus `email = false` (untested against the provider; a refusal would fail the merge apply) | technical | Ruled by CTO agent, 2026-11-05: `email = true`, with `push`, `call`, `sms` and `critical_alert` false. A no-channel alert is unverified against the provider and a 422 would fail the merge apply, which costs more than one email. The soak probe reads the incidents API, not the inbox. |
| Canary SQL: derive from the production local with `replace()` versus a second duplicated heredoc | technical | Ruled by CTO agent, 2026-11-05: derive with `replace(local.egress_gw_probe_silent_sql, "'egress-gw-probe'", "'egress-gw-probe-canary-absent'")` so it cannot drift from the production shape. The guard pins the `replace(` line, asserts the swapped identifier is not any real emitter tag, and asserts canary and production SQL differ so a silent no-op replace is caught. |
| Metric expression and roster number | technical | Ruled by CTO agent, 2026-11-05: `greatest(toInt64(${length(var.web_hosts)}) - toInt64(count(DISTINCT JSONExtractString(raw, 'host_name'))), 0) AS value`, alert `higher_than 0`. One source of truth with the former threshold; no unsigned wrap. Counting distinct host names against the roster size (not set identity) is an accepted pre-existing residual, named in the alert comment. |
| Soak probe data source and tracker shape | technical | Ruled by CTO agent, 2026-11-05: read the Better Stack incidents API (not the mirror issues, whose `closed_at` lags the vendor `resolved_at`); one tracker issue; the probe is NOT YET / CANNOT ESTABLISH while the 4 h window is open or unverified, exits 5 "delete the canary" while the canary is still declared in main's `.tf`, and exits 0 only when verification held and the canary is gone. Planner refinement within the ruling: the convention's reserved codes are used (2 = NOT YET, 3 = CANNOT ESTABLISH, 5 = ACTION REQUIRED); exit 1 is never used. |
| Decision rule when the canary does not fire; state of the production alert meanwhile | technical | Ruled by CTO agent, 2026-11-05: no canary incident in the API 20 minutes after apply completion means the evaluator is blind for this query shape and the production alert is not trustworthy; build the feeder-fed poller and file its issue at once; leave the production alert armed (pausing removes the only detector); a green production alert is not evidence of health until the canary has fired. Named residual: with `treat_as_zero` kept, an evaluator error or timeout reads 0. |
| Hand-resolving incident 1047829421 or editing any Better Stack incident (a vendor write) | operator (production-mutating) | Not done and not planned. Only the per-merge Terraform apply writes to production. If the incident does not clear on its own, the fallback is the poller; a manual resolve would need the user's explicit per-command go-ahead. |
| Re-arming the paused `inngest_cutover_flip_silent` alert with the same inverted shape | operator (scope) | Not done in this PR: the brief limits the change to the egress alert, and the inverted shape is unproven until the canary has fired and the incident has stayed resolved. Awaiting the owner's decision after the soak result. |

## Notes

- The five technical rulings were obtained from one CTO consult with the evidence listed in the plan; no further
  technical fork arose. The placement of the canary local after the fail local (so the existing mutation anchors do
  not drift) and the exact-count bumps are mechanical consequences.
- Plan-review (DHH, Kieran, code-simplicity) findings applied as mechanical edits: the canary executor and 25-minute
  check were made explicit (the CTO rule F5 had no executor), the canary lifetime contradiction was resolved toward
  early deletion (the 4-hour soak concerns only the production incident), the guard matrix was trimmed from 17 to 13
  rows, probe incident matching became exact-name, and the empty-evaluator-window case was added as a disconfirming
  signal (AC12b), which is the same response F5 prescribes for a silent canary. Kept against reviewer cuts, with the
  reason: the soak probe (the brief's post-merge verification and the ship gate require it), the `infra-validation.yml`
  and flip-silent comment edits (named in the brief or false after the change), the rollback dry run (sharp-edge
  rule: a recipe first run during an incident), and the probe's tie to canary deletion (CTO ruling F4).
