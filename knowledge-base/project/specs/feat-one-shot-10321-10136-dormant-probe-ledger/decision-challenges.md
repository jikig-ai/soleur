# Decision Challenges — feat-one-shot-10321-10136-dormant-probe-ledger

Session: one-shot planning subagent (2026-10-15). This harness cannot spawn Task
subagents, so technical forks were recorded `pending - assumed:` per the
technical-ruling-delegation rule — the main-context gate spawns
`soleur:engineering:cto` for any row the pipeline wants bound before work.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Standing vehicle for the credential-shape check (Better Stack alert vs scheduled workflow vs sweeper read-surface with open-ended closed set) | technical | pending - assumed: standing Better Stack alert (`logtail_exploration` + `logtail_exploration_alert` `registry_zot_log_credential_shape`), matching the 2026-10-14 CTO ruling (A2) that put the sibling clientIP invariant (#7530) on the same vehicle — ADR-218's pending amendment already records "why an alert and not a follow-through probe: a probe's tracker closes on PASS and drops out of the sweeper's 14-day lookback". The sweeper read-surface change was cut (re-opens the bounded-lookback hazard, touches shared machinery); the scheduled workflow was cut (weaker signal, duplicate credential plumbing). |
| Raw signing key remedy for `list-runs.ts` (hash bearer vs TLS) | technical | Resolved by evidence (no ruling needed): `inngest/inngest` v1.45.1 `pkg/authn/signing_key_strategy.go` `HandleSigningKey` accepts EITHER the raw key or `signkey-prod-<sha256>` (constant-time compare against both forms), and the SDK's own server-bound calls send the hashed form. Plan hashes the bearer client-side; TLS on the hop remains the CLO-gated residual (ruling due 2026-10-24). |
| Step-outputs wording in the ledger's Inngest row (reconcile vs mark not-asserted) | technical | pending - assumed: narrow `does_not_defend` to event payloads + mark step-output transport "not asserted on this link (#9139)" — the CTO code read attributes step execution to the Cloudflare serve-URL leg, so the link claim shrinks rather than being asserted. |
| Disposition of the audit-found dormant probes (`#3950`/`#6407`/`#6459`/`#8978` header notes; `#8706` delete-per-RETIREMENT) | technical | pending - assumed: dated header status notes for the four claiming post-close detection; delete `luks-monitor-host-timer-8706.{sh,test.sh}` per its own `RETIREMENT:` instruction + drop the `follow-through` label on #8706; no new alerts beyond the zot credential-shape one (the other probes' checks either had soak-scoped value or successors). |
| Alert coverage semantics: boot-scoped vs all-rows grading for the credential-shape alert | technical | pending - assumed: all matching rows fire (no newest-boot scoping) — the probe's boot-span existed to attribute delivery, which a standing regression detector does not need; any credential-shaped shipped row is an incident regardless of host generation. |
| Alert count vs Better Stack tier cap (15th managed Logs alert) | technical | pending - assumed: ship the resource and let the push-triggered apply measure the vendor cap; on refusal, surface on #10321 (paid-tier = operator money call; predicate-shrink vs sweeper-route = CTO re-ruling). |
| `INNGEST_SIGNING_KEY` rotation for the already-flown raw key | operator (production-mutating authorization) | pending - not decided: rotation is a Doppler/infra write and a legal-risk call for the 2026-10-24 CLO re-ruling; recorded as an explicit residual on #10136, NOT a plan task. |
| The measured nftables re-read the CLO conditioned acceptance on | operator (production-mutating authorization / infra read) | pending - not decided: proposed as verification evidence in the plan; execution is operator-gated (no SSH/terraform/dispatch rights in this pipeline). |

## Notes for ship-time rendering

- This PR does NOT close #10136 (`Ref` only): the issue's done-when is "each link has TLS with
  certificate verification on, or a ruled written decision that private-network plaintext is
  accepted with a dated owner" — TLS remediation is operator/infra-gated and the CLO re-ruling is
  2026-10-24; both postdate this PR.
- #10321 CAN close: header corrected, standing check lands as the alert, audit dispositions land.
