# Decision Challenges — feat-one-shot-9294-deploy-creds-tier-move

Technical/taste/operator rulings made or deferred during planning (#9294).
Agent consults were unavailable in this session (no subagent tooling); rows
marked `pending - assumed` carry the default the implementer should follow
unless the pipeline surfaces a ruling.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Narrow carrier shape (`soleur-deploy-channel` project + `deploy-channel` env + `DOPPLER_TOKEN_DEPLOY_CHANNEL` + loader narrow mode) | technical | Ruled by CTO agent, per the G1 epic ruling recorded in #9294's context (issuecomment-6914232441): non-Terraform consumers read a narrow Tier-B project; binding them to `infra-privileged` would hand them `HCLOUD_TOKEN` read/write to deliver a deploy-trigger credential — 2026-11 (carried, not re-litigated) |
| Two-PR sequence (carriers land before consumers name `deploy-channel`) | technical | pending - assumed: PR-A carriers + owner seed, then PR-B consumers. Default rationale: GitHub auto-creates a referenced-but-missing environment with NO branch protection; and the 15-min `scheduled-inngest-health` probe would page a false outage in the pre-seed window |
| `DOPPLER_TOKEN_DEPLOY_CHANNEL` seeded on both `deploy-channel` and `inngest-cutover` | technical | pending - assumed: both envs. Default rationale: gated cutover ops must keep `inngest-cutover` for the reviewer gate; routing them through the privileged loader would violate the narrow-carrier ruling |
| Sweeper partition via `FT_ONLY_SECRETS`/`FT_EXCLUDE_SECRETS` flags + new `sweep-deploy-channel` job | technical | pending - assumed: partition flags in `sweep-followthroughs.sh`. Default rationale: when the trio leaves the Tier-A sweep env, Guard 3 would comment/red every open trio tracker daily; the alternative (a dedicated workflow duplicating the engine) forks the lifecycle machinery |
| Retire `scripts/followthroughs/inngest-soak-6178.sh` in this slice | technical | pending - assumed: retire. Default rationale: #6178 is CLOSED; its `secrets=` retire directive executes on migration; leaving it would park a dead tier-a row past expiry |
| Disposition of tier-a rows whose files cannot lose the counted shape or the family name | technical | pending - assumed: per-file disposition (delete-row / forward-class / ADR `Allow:`-`Reclass:`-`Re-date:` line); a scanner class-rule refinement, if any file needs one, lands only with the same ADR-241 amendment |
| Loader narrow mode names no trio stem (whole-project download) | technical | pending - assumed: name-free export. Default rationale: `action.yml` is a composite action — a literal trio stem would pin a permanent `tier-a` row the ratchet can never retire |
| `key-rotate.yml`/`inngest-key-rotate.yml` `redeploy` jobs bind `deploy-channel` (no reviewer) | technical | pending - assumed: `deploy-channel`. Default rationale: upstream `key-rotate-approval` env already gates the dispatch; the deploy cred needs the main-only boundary, not a second human click |
| Brand-survival threshold `aggregate pattern` + CPO sign-off | operator (brand) | pending - operator decision: worst case is a cross-tenant supply-chain incident (deploy-host `ci-deploy.sh` replacement). Headless run: recorded here; sign-off collected at PR review gate |
| Owner-named seed (hash-equal copy, token mint, `gh secret set`) and tail (Tier-A deletions) | operator (irreversible production mutation) | operator-reserved — recorded in plan §Proposed Solution; agent does not execute |
| HMAC/CF-Access credential rotation tail | operator (irreversible production mutation) | operator-reserved per brief — explicitly out of scope; no `or`/`_NEXT` machinery planned |
| `cloudflare_zero_trust_access_service_token.deploy` stale-state reconciliation | operator (irreversible production mutation) | operator-reserved — #7103 B5; `removed{destroy=false}` block untouched |

## Specialist-consult coverage note

No domain-leader, CTO, SpecFlow, or advisor subagent was invoked: this session's
tool surface exposes no subagent spawn mechanism. All gates were applied
inline (domain review → engineering/infra + ops; GDPR gate → not a
regulated-data surface — the trio is infrastructure credentials, not personal
data; IaC routing gate → carrier via Terraform, operator steps recorded as
deferrals not implementation; observability/task-design/encryption/guard
gates → emitted in the plan). No independent review is claimed.
