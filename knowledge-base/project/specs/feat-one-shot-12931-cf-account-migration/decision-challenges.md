# Decision challenges — feat-one-shot-12931-cf-account-migration

Plan: `knowledge-base/project/plans/2026-11-18-infra-cloudflare-migrate-terraform-to-soleur-account-plan.md`. Issue #12931.

Technical forks were ruled by the CTO agent (`hr-technical-fork-is-not-an-operator-question`). Operator rows are the only items that need the operator. Each one has a recommended default, so the pipeline can proceed without a reply.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| F1: how stale old-id state entries leave state | technical | Ruled by CTO agent, 2026-11-18: a committed manifest plus an idempotent `terraform state rm` of every address whose `zone_id`/`account_id` is an old id. It runs in the first `cf-account-migrate` dispatch after a `state pull` backup. R2 buckets and the backend stay. Each phase then imports or creates. - Import blocks are ignored while the address is in state (measured), and destroys would hit the moved zone. |
| F2: how the ids flip | technical | Ruled by CTO agent, 2026-11-18: flip Doppler `CF_ZONE_ID`/`CF_ACCOUNT_ID`. Add `var.cf_r2_account_id` (no default) for every R2 surface. Add validations rejecting the old ids. Manage `prd` `CF_ZONE_ID` with a `doppler_secret`. - A plain flip would re-home the LUKS escrow and state buckets; parallel `*_soleur` vars invite mixed-account plans. |
| F3: which apply path runs the migration | technical | Ruled by CTO agent, 2026-11-18: a dedicated dispatch target `cf-account-migrate` with a `phase` input and a plan gate (new ids only, no deletes outside a pinned list, creates/imports within the phase set). The merge apply and the drift job refuse while the state-derived migration-complete predicate is false. - The push-triggered apply rides the dead tunnel and HALTs on the deploy-policy create. |
| F4: PR split | technical | Ruled by CTO agent, 2026-11-18: PR1 (this branch) holds the variable split, the dispatch target and gate, the state-rm manifest, F6/F7/F10, and the `redirects-dns` + `zone-rest` phases. It merges with `[skip-web-platform-apply]`. PR2 (tunnel, F5, F8) is part of THIS plan and pipeline, on a new branch from main after PR1 merges. - Redirects need no host change and are the fastest user-visible recovery. |
| F5 (re-ruled): ssh/registry A records | technical | Ruled by CTO agent, 2026-11-18: a pinned pre-delete step in the tunnel phase, before plan, for the 6 record ids. It refuses the old zone; asserts name, type=A, proxied=true and content in the 3-IP set per record; refuses all six if any check fails; is dry-run by default and idempotent. The CNAMEs are then plain creates with no gate exception. - Three A records per name cannot be imported into one address (the first ruling, import + replace, was withdrawn on that evidence). |
| F6: Load Balancing resources | technical | Ruled by CTO agent, 2026-11-18: `count = var.cf_load_balancing_enabled ? 1 : 0` (default false), no `moved{}`. `cf-lb-overlay.yml` refuses while the flag is false. - LB needs a paid add-on on the new account; the plain proxied A record serves today. |
| F7: Bot management on Free | technical | Ruled by CTO agent, 2026-11-18: keep the resource; `sbfm_*` fields become null unless `var.cf_zone_plan_pro`. The `zone-rest` phase plan settles `enable_js` on Free. - Super Bot Fight Mode is Pro-only. |
| F8: deploy Access service token | technical | Ruled by CTO agent, 2026-11-18: an API script with an operator-minted token holding only Access: Service Tokens:Edit. It writes the id/secret straight to Doppler (stdin, never printed) in every config holding the pair. The new UUID goes into `local.deploy_service_token_ids` in PR2. Only the migrate job may create exactly one `deploy_service_token` policy, with the committed UUID. - The token is unmanaged by design (ADR-241 D10); Playwright rejected. |
| F9: tunnel cutover sequence | technical | Ruled by CTO agent, 2026-11-18: F8 token and UUID commit first, then the tunnel-phase apply (tunnel, config, apps, policies, tokens, CNAMEs; `random_id.tunnel_secret` and `doppler_secret.registry_push_*` replaced), then the CI-SSH token sync, then `web-host-replace web-2`, then verification. The old tunnel stays until an owner-named cleanup. Tunnel name stays `soleur-web-platform`. - The token reaches the host only via user_data at create; the replace gate needs the tunnel already in state. |
| F10: DNSSEC and the seo_config import | technical | Ruled by CTO agent, 2026-11-18: count-gate DNSSEC off (default false) with a tracking issue. Delete the old-id `seo_config_settings` import block and `adopt_seo_config_entrypoint`. Import any new-zone config entrypoint by its new id through the manifest. - Enabling DNSSEC mid-cutover adds a whole-domain failure mode. |
| F11: token scopes | technical | Ruled by CTO agent, 2026-11-18: one token per Doppler key, no merges, with the permission groups in the plan's Phase 0 table. `CF_API_TOKEN_R2` is not re-minted. Repoint `scripts/check-cloudflare-token-drift.sh`. - Least privilege per provider alias; R2 stays on the old account. |
| Follow-up 1: PR2 timing | technical | Ruled by CTO agent, 2026-11-18: PR2 is not deferred. It is the second PR of this pipeline, opened from main after PR1 merges. - The operator directive names deploy hosts as in scope. |
| Follow-up 2: what rides the first dispatch | technical | Ruled by CTO agent, 2026-11-18: DNS-record, Pages project and Pages domain imports ride the first dispatch with the redirects (`phase=redirects-dns`). Only `zone_settings_override` and `bot_management` stay in `zone-rest`. The merge-apply and drift refusal holds until the tunnel phase completes. - Every forgotten address must be re-adopted before any full plan can run. |
| Rehearsal must not write state | technical | Ruled by plan author (mechanical consequence of F1 + `plan_only`), 2026-11-18: `plan_only` runs the state migrate as `--dry-run` and plans against a pulled local copy. - A rehearsal that forgets state is not a rehearsal. |
| Zone plan: buy Pro on the new zone? | operator (money) | Recommended default: stay on Free (COO D1). The old Pro cost $0; Pro on the new account is about $20-25/mo. All rule counts fit Free; only Super Bot Fight Mode is lost, and it was configured to `allow`. Revisit if bot traffic becomes a problem. |
| Load Balancing subscription | operator (money) | Recommended default: defer (COO D2, about $5/mo base). The LB is count-gated off; `app.soleur.ai` serves from the plain proxied A record. |
| Mint the new-account Cloudflare tokens (Phase 0 table) | operator (production-mutating) | Needs the operator's go. The mints run in the operator's signed-in dashboard session (Playwright, `cf-token-scope` flow), values straight to Doppler. |
| Doppler writes and the `CF_ZONE_ID`/`CF_ACCOUNT_ID` flip | operator (production-mutating) | Needs the operator's go, naming the command. Agent-run, values never printed. |
| `cf-account-migrate` dispatches (`redirects-dns`, `zone-rest`, `tunnel`) | operator (production-mutating) | Needs a go per phase, rehearsal (`plan_only=true`) first. |
| `web-host-replace web_host_key=web-2` | operator (production-mutating) | Needs a go. It is the immutable redeploy path for the new tunnel token; web-1 is not touched. |
| Revoke the temporary token, the old DNS-edit token and superseded tokens | operator (irreversible) | Needs a go. Recommended: revoke the old DNS-edit token as soon as its replacement is in Doppler, and the rest at cleanup. |
| Delete the old tunnel `fc4509ed…` in the old account | operator (irreversible) | Needs a go, after web-2's replace drops its connections. |
| App-level `X-Robots-Tag` fallback in Next.js (CMO P1) | operator (scope) | Recommended: file a follow-up issue rather than add to this P1. The edge noindex is restored in the first dispatch; an app-level fallback is defence in depth against a repeat. |
| Search Console check for `app.soleur.ai` token URLs indexed since 16:24 UTC (CMO P1) | operator (scope) | Recommended: run after the `redirects-dns` dispatch and request removal of any token URL; record in the PR thread. |

## Plan review (2026-11-18): DHH, Kieran, code-simplicity, CTO devex panel

Mechanical findings were applied to the plan. Each row below records what changed, or the class of the finding that was not applied as-is.

| Item | Class | Ruling |
|---|---|---|
| `cloudflare_record.app` in `redirects-dns` pulls the tunnel (Kieran P0) | technical | Applied: the `app` import moves to the `tunnel` phase. `redirects-dns` imports 26 records. - `content = hcloud_server.web["web-1"].ipv4_address` and the server renders the tunnel token. |
| Rehearsal `-state=<copy>` is ignored under the s3 backend (Kieran, DHH, simplicity) | technical | Applied: the rehearsal runs in a scratch root with a `backend "local"` override, and the job asserts the remote serial is unchanged. |
| Overwriting live token keys before the id flip (Kieran) | technical | Applied: tokens go to `<KEY>_NEXT` staging keys and swap with the ids in one sequence, with `<KEY>_PREV` kept for the revert path. |
| Import + update passes the gate (Kieran) | technical | Applied: Guard 1 requires every import to be a pure no-op import whose id equals the committed literal (mutation rows 9-11). |
| Null-id classification in state-forget (DHH) | technical | Applied: entries are classified on their one non-null id, both-null aborts, and the fixture covers every declared resource type. |
| Per-address `state rm` is not atomic (Kieran) | technical | Applied: one `state rm` call, serial asserted +1. |
| State-rm manifest (simplicity) | technical | Applied, modifying F1's mechanism but not its property: the candidate set is derived from state (non-R2 `cloudflare_*`), because the script already classifies each entry by its own id. A hand list drifts. |
| Write probes would mutate entrypoints (DHH, Kieran, simplicity) | technical | Applied: invalid-body probes only. No new probe script; profiles go on `cf-token-scope.sh`, run once per phase from the runbook. |
| In-progress predicate: cut (simplicity, DHH) vs widen (Kieran) | technical | Ruled in consolidation, 2026-11-18: keep and widen. Kieran showed concrete out-of-phase paths (`web_host_create` → `app` → tunnel; `ci_ssh_token_replace` → Access objects) that `deploy-policy-gate.sh` does not cover. The cut argument held only for the `apply` job. Applied: every plan-capable job except `cf_account_migrate` (and `web_host_replace web-2` after the tunnel phase) fails non-zero. The drift job is not gated. The completion definition is strengthened. |
| Id-preflight job step (simplicity, DHH) | technical | Applied: cut. The validations already fail old ids. |
| Branch configs do not inherit `prd` values (CTO devex item 1) | technical | Applied: a names-only inventory listing plus per-config writes in the Phase 2 step 2 sequence, for `CF_ZONE_ID`, `_PURGE`, `_DNS_EDIT` and the deploy pair. |
| Phase 0 split 0a/0b (CTO devex item 2) | technical | Applied. |
| Deploy-policy exception compares the local to itself (Kieran) | technical | Applied: the gate step also requires `GET …/access/service_tokens/<uuid>` to return 200. |
| TEMPORARY `ssl=full` rule still declared (Kieran) | technical | Applied: deleted in PR1 (it is in #12931's ask). |
| Expected counts hardcoded; operator compares by eye (Kieran, CTO devex item 8) | technical | Applied: the gate derives the counts and prints one `verdict=PASS creates= imports= destroys=0` line. |
| Allow-set written three times (DHH, simplicity) | technical | Applied: one jq list per phase generates the `-target` args. Uses `plan-gate-preamble.sh` and `gate-suite-harness.sh`. The prose set-identity test is cut. |
| Merge-section contradiction on the validations (all panels) | technical | Applied: corrected. Between merge and flip every plan fails closed, so the flip follows the merge in the same sitting. |
| No-rollback / fix-forward guidance (CTO devex item 4, Kieran) | technical | Applied: documented in Phase 2 step 2. The full revert is revert PR1 + restore `_PREV` + `state push` the backup. |
| Origin CA re-mint timing (CTO devex item 5) | technical | Applied: moved to Phase 3, before the release redeploy. |
| Token-drift script repoint timing (CTO devex item 7) | technical | Applied: PR1, as F11 ruled. |
| Cleanup retires the job behind `exit 1` (CTO devex item 6, simplicity) | technical | Applied: the cleanup PR deletes the job, input, option and gate. The mint script and the probe profiles are kept for the 8760h rotation. |
| Dormant PR2 scripts shipped in PR1 (all reviewers) | technical | Applied: moved to PR2. |
| Old-account objects left behind by the forget (DHH) | operator (irreversible) | Added to Phase 5 step 7: delete by name from the backup-derived list, one go each. The old LB monitor and pool may still bill, and the old `ci_ssh`/`registry_push` tokens stay valid until they expire. Recommended: delete right after Phase 3 verification. |
| Move ADR-329 and C4 edits to the cleanup PR (DHH) | taste | Declined; kept in PR1. PR1's LB gate falsifies the C4 `cloudflare` and `inngest -> api` descriptions, and the C4 mandate keeps the model true in the PR that changes it. The `infra-security.md` and 8209 literal edits did move to cleanup. |
| One standing delegation for the migration dispatches (CTO devex item 3) | operator (production-mutating) | Recommended: record one standing delegation on #12931 covering the `cf-account-migrate` rehearsal and apply lines and the `web-host-replace web-2` line, each envelope naming its exact `gh workflow run` command. Without it, each dispatch needs its own go. |

## Deepen-plan (2026-11-19)

| Item | Class | Ruling |
|---|---|---|
| Measured TF 1.10.5 behaviours: imports or `-replace` outside `-target` are dropped silently; multi-address `state rm` skips missing addresses with exit 0; a pure import is `["no-op"]` | technical | Applied: Guard 1 rows 9/9b/9c, the Guard 2 removed-count assertion, Sharp Edges. Evidence from terraform-architect local experiments (no network, no credentials). |
| Ruleset import prefix must be exactly `zone`/`account` | technical | Applied to Sharp Edges. v4 silently reads `zones/` as account. |
| Apply legs under the reviewer-gated `web-platform-infra-apply` environment (security) | technical | Applied. The rehearsal stays on `infra-privileged`. The environment approval doubles as the production-write authorization. |
| Token mint transcript leak via Playwright snapshot (security) | technical | Applied: no snapshot after Create; one evaluate step pipes the value into Doppler; fallback is an operator paste. |
| Secret-printing verification and long-lived `_PREV`/`_NEXT` (security) | technical | Applied: sha256 compare; `_NEXT` deleted at the swap; token `_PREV` deleted after `redirects-dns` verification; the temporary token is revoked after Phase 0a. |
| Deploy-policy exception checks (security) | technical | Applied: name, expiry, `non_identity`, single include, app id, read-only GET. |
| C4 completeness: 7 `model.c4` edits plus `model.likec4.json` regeneration; ADR-329 amends ADR-068 and ADR-321 (architecture-strategist) | technical | Applied. |
| Phase 0c early noindex: create the transform entrypoint in the new zone before PR1 merges, rendered from code, then imported (security) | operator (production-mutating) | Recommended: yes. It closes the `app.soleur.ai` `/shared` and `/invite` indexability window hours or days earlier. It is a new-zone write, so it needs the operator's go. |
| Expire share/invite tokens issued since 16:24 UTC 2026-11-18 (security) | operator (scope) | Recommended: decide after the Search Console check (CMO P1). Expire only if a token URL is found indexed. |
