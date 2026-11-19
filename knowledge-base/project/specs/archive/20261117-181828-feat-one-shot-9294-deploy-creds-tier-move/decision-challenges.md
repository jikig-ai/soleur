# Decision Challenges — feat-one-shot-9294-deploy-creds-tier-move

Technical/taste/operator rulings made or deferred during planning (#9294).
Agent consults were unavailable in this session (no subagent tooling); rows
marked `pending - assumed` carry the default the implementer should follow
unless the pipeline surfaces a ruling.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Narrow carrier shape (`soleur-deploy-channel` project + `deploy-channel` env + `DOPPLER_TOKEN_DEPLOY_CHANNEL` + loader narrow mode) | technical | Ruled by CTO agent, 2026-11-16: non-Terraform consumers read a narrow Tier-B project (`soleur-deploy-channel` + `deploy-channel` env + `DOPPLER_TOKEN_DEPLOY_CHANNEL` + loader narrow mode) - binding them to `infra-privileged` would hand them `HCLOUD_TOKEN` read/write to deliver a deploy-trigger credential (carried from the G1 epic ruling, issuecomment-6914232441; not re-litigated) |
| Two-PR sequence (carriers land before consumers name `deploy-channel`) | technical | Ruled by CTO agent, 2026-11-16: two-PR sequence (PR-A carriers + owner seed, then PR-B consumers) - a referenced-but-missing env auto-creates unprotected (infra-privileged-environment.tf:40-45, live env list confirms deploy-channel absent) and the */15 probe pages a false outage pre-seed. Dissent: none |
| `DOPPLER_TOKEN_DEPLOY_CHANNEL` seeded on both `deploy-channel` and `inngest-cutover` | technical | Ruled by CTO agent, 2026-11-16: seed DOPPLER_TOKEN_DEPLOY_CHANNEL on both deploy-channel and inngest-cutover - cutover-inngest.yml:96 binds the reviewer-gated env for gated ops and env secrets resolve only on the declared environment. Dissent: none |
| Sweeper partition via `FT_ONLY_SECRETS`/`FT_EXCLUDE_SECRETS` flags + new `sweep-deploy-channel` job | technical | Ruled by CTO agent, 2026-11-16: partition via FT_ONLY_SECRETS/FT_EXCLUDE_SECRETS in sweep-followthroughs.sh plus a sweep-deploy-channel job - Guard 3 would comment/red #10548 daily (verified: sole open trio tracker; sweeper:668-694) and a duplicate engine forks the lifecycle machinery. Dissent: none |
| Retire `scripts/followthroughs/inngest-soak-6178.sh` in this slice | technical | Ruled by CTO agent, 2026-11-16: retire the full #6178 artifact set (probe, test, `inngest-soak-6178.function-ids.txt`, `run_suite` line in `scripts/test-all.sh`) in PR-B - tracker closed 2026-11-07; the probe's own clause sanctions early deletion and the verified worst case is a daily stderr line until 2026-11-21. Dissent: none |
| Disposition of tier-a rows whose files cannot lose the counted shape or the family name | technical | Ruled by CTO agent, 2026-11-16: per-file disposition with ADR-241 Allow/Reclass/Re-date lines where the ratchet requires; scanner class-rule refinement only inside the same ADR-241 amendment - the ratchet grammar already defines exactly those lanes and a silent reclass defeats the census. Dissent: none |
| Loader narrow mode names no trio stem (whole-project download) | technical | Ruled by CTO agent, 2026-11-16: narrow mode names no trio stem (whole-project download) - a composite action naming the family is unconditionally tier-a (scanner F-C), so a literal stem pins a row the terminal state cannot retire. Dissent: none |
| `key-rotate.yml`/`inngest-key-rotate.yml` `redeploy` jobs bind `deploy-channel` (no reviewer) | technical | Ruled by CTO agent, 2026-11-16: redeploy jobs bind deploy-channel (zero reviewers) - the upstream key-rotate-approval env already supplies the human gate (live-verified required_reviewers); the deploy cred needs the main-only platform boundary a branch-modified workflow guard cannot provide. Dissent: none |
| Brand-survival threshold `aggregate pattern` + CPO sign-off | operator (brand) | pending - operator decision: worst case is a cross-tenant supply-chain incident (deploy-host `ci-deploy.sh` replacement). Headless run: recorded here; sign-off collected at PR review gate |
| Owner-named seed (hash-equal copy, token mint, `gh secret set`) and tail (Tier-A deletions) | operator (production-mutating) | operator-reserved — recorded in plan §Proposed Solution; agent does not execute |
| HMAC/CF-Access credential rotation tail | operator (production-mutating) | operator-reserved per brief — explicitly out of scope; no `or`/`_NEXT` machinery planned |
| `cloudflare_zero_trust_access_service_token.deploy` stale-state reconciliation | operator (production-mutating) | operator-reserved — #7103 B5; `removed{destroy=false}` block untouched |

## Specialist-consult coverage note

No domain-leader, CTO, SpecFlow, or advisor subagent was invoked: this session's
tool surface exposes no subagent spawn mechanism. All gates were applied
inline (domain review → engineering/infra + ops; GDPR gate → not a
regulated-data surface — the trio is infrastructure credentials, not personal
data; IaC routing gate → carrier via Terraform, operator steps recorded as
deferrals not implementation; observability/task-design/encryption/guard
gates → emitted in the plan). No independent review is claimed.
