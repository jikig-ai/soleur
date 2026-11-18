---
title: Fresh current-source production image proposal
date: 2026-10-11
pr: 9051
status: candidate-prepared-startup-recovery-unqualified
---

## Reviewed source and fresh runner

Main through `e5ee9d577f2ea64580c17c314d0153bfe427d1de` is included at
`3c3ba13b29053071b690598325362b343299bc1a`. The old production image at
`a2ff13ca` predates the egress-forwarder payload, Vitest scratch ownership,
shim procfs changes and current host payload. Its build authorization and the
old 13-migration recovery rehearsal are consumed and remain unchanged.

A new task-owned runner is prepared at
`.soleur/production-image-proposal-20261011/prepare.py`, SHA-256
`f73a3ada3cf8dcd64610187e99c4bd30c663b98158b5e7c40b55ab6a5d5d9c03`.
Its read-only preview at the inspected merge passed with 4,970 tracked
app/plugin entries, 1,352 filtered plugin files and 63 host-script payload files.
The original Dockerfile digest is
`da6105549a2b1cb94fedab8257e4c4f0e325d9c15e1e08a9982febf8c6696ca0`;
the controlled Dockerfile digest is
`ec0475961448d6b24ea32cd6d8476359fcd66b05ce2d9e1b35597b7d5070723c`.
Preview did not export source, download, start containers, consume a marker or
run the application/database/provider.

Evidence is committed before seeking approval. The approval command must bind
the resulting clean, full HEAD and the runner digest above; documentation-only
commits do not qualify a different source set. Changed app/plugin inputs require
fresh inspection and approval. The reviewable command form is:

```text
python3 .soleur/production-image-proposal-20261011/prepare.py --source-sha <FINAL_CLEAN_40_CHARACTER_HEAD> --runner-sha256 f73a3ada3cf8dcd64610187e99c4bd30c663b98158b5e7c40b55ab6a5d5d9c03 --authorize-one-production-image-build
```

At proposal commit this command had not been authorized or executed. The final
literal SHA was shown with the approval request. Attempt `oct11-cd8473e1` has an exclusive
marker, source-bound image tag and exact owned resource names; pre-existing
resources, dirty tracked input or changed HEAD cause refusal.

## Exact proposed permission boundary

One local build from the complete current production Dockerfile and pinned
tracked app/plugin export, followed only by filesystem and default-UID probes.
The runner consumes its marker before source export, cache/network/container
mutations. Failure or interruption does not authorize a retry, repin or rebuild.

Explicit approval must cover public image/package/browser downloads, ordinary
npm install scripts and the engine-managed privileged BuildKit container.
Install stages have no enforced destination allowlist. Empty private Docker
configuration and sanitized environment exclude account/provider credentials.
The node base remains the Dockerfile's immutable node:22-slim digest; Claude Code
2.1.293, LikeC4 1.50.0, Vitest 4.1.11, requested GitHub CLI 2.96.0 with its existing
rolling fallback, and the pinned Chromium download remain attributable.
BuildKit and downloaded tool/image digests are captured, not inferred as pinned.

Two CPUs, 6 GiB total builder memory/swap, a 4 GiB Next heap, 75-minute work budget,
bounded stages/cleanup and at least 40 GiB free disk are enforced. Four
compiler/tripwire RUN lines and both probes use network none; telemetry is off.
Default Next build mode, normal install scripts and production stages remain.
Local image/cache assembly can write several GiB. Local compute and OpenAI
assistant usage are separate from Soleur subscription; Soleur disclaims runtime
cost warranty.

Admission checks immutable image/source identity, default server command,
default UID 1001, application/canary/shim/filter/forwarder hashes, every admitted
plugin file/symlink, all 63 baked host-script hashes, global tool versions and
browser payload presence. Metadata checks do not run these tools or qualify
browser, sandbox, firewall, deployment or observability behavior. The named
probes, dedicated builder and exact cache volume are removed; the local candidate
image and bounded logs/manifests remain. No global prune or image publication.

No server/database/recovery startup, SQL, provider/browser/account authentication,
customer content, shared writes, deployment, flag or cohort change is admitted.
PR stays draft, auto-merge disarmed, Codex default-off and customer traffic blocked.

## Separate full historical recovery follow-up

After a verified candidate exists, prepare a separate image/digest-bound,
one-use recovery runner and request fresh startup/SQL authorization. Reuse the
historical substrate in `.github/workflows/rls-authz-fuzz.yml`: Supabase CLI
2.84.2, genuine local auth/storage roles, tracking-table `content_sha` bootstrap
and canonical `run-migrations.sh --bootstrap=skip`. The inspected source has
187 complete forward SQL files; record exact filename/blob hashes and applied
rows, with zero omitted migrations. The old handbuilt 13-migration closure
cannot establish historical-schema parity.

Export into fresh task-owned scratch, use a unique copied Supabase project ID,
unused loopback ports and owned network/volumes, and prove ownership/binding
before fixture writes. The normal wrapper restricts published ports, not outbound
egress: the future proposal must separately prove the isolated network boundary.
Sanitize environment before the canonical migration runner: it prefers
`DATABASE_URL_POOLER` and invokes a Management-API schema-refresh helper.
Exclude pooler, hosted Supabase access, Doppler, provider and observability tokens;
verify the explicit local DSN before any SQL. A detached local Git snapshot avoids
the migration runner's fetch touching live worktree refs. The non-CI migration
145 and 149 tests target `supabase_db_web-platform`; do not run them against
the shared default project or treat their handmade schema as historical proof.

Seed only synthetic auth/member/workspace/conversation/message/engine state and
storage objects, preserve its ledger and content through first/replacement
production renderer health and graceful stop, then compare retained state,
protected checkpoints, auth/storage objects and workspace file hashes. Add
current-generation, stale retry/checkpoint, accepted old-attempt output,
owner/member/tenant, transfer-acknowledgment, erasure and concurrent-switch probes;
capture affected rows, lifecycle/checkpoint writes and WAL deltas.

A renderer/schema recovery pass still excludes real Codex-process recovery.
`server/codex-conversation-runtime.ts` has no approved live launcher or
qualification/egress composition, and this Dockerfile does not install a Codex
App Server payload. Safe fake-provider lifecycle tests remain separate from
permitted mode-specific Web/provider proof. Infrastructure, deployment and real
observability checks retain their own authorization and evidence boundaries.
Authenticated screenshots, eligible routine consumer, separate API-key/managed
Web matrices, attributable CLO disposition, and full review/promotion remain
acceptance work after recovery. Unknown project sharing, retention/inheritance
and configured regions are not inferred from build or local recovery results.

## Approved execution and terminal result — 2026-10-11

The user approved the exact one-use command bound to clean source
`2b826822c086d4348ada891e15fde2aa7b62eac3` and the runner digest above.
Execution completed successfully, including the complete controlled production
Dockerfile build, filesystem inventory, default UID 1001 probe and owned cleanup.
The marker is consumed; no repeat, repin or rebuild is authorized.

The retained local image ID is
`sha256:0914d1f1a6ec00fe79129531eac7d6e7aeb9507548e8f6207649d5915fa25420`,
size 2,477,592,039 bytes. All 1,352 admitted plugin files and 63 host-script
payloads matched their source hashes. Claude Code 2.1.293, LikeC4 1.50.0,
Vitest 4.1.11 and Chromium payload presence were admitted. BuildKit image ID was
`sha256:cec9f139f45e93c5c69c60f8b07cfad9f43f4ef6b6a6cd917527fea5ff2e3dea`.
The compiler/tripwire steps used network none; production compilation generated
93 pages. The two named probes, dedicated builder and its cache volume were
removed; no global prune or publication occurred.

Ignored terminal record: `.soleur/production-image-proposal-20261011/`
`candidate-2b826822c086-oct11-cd8473e1/build-record.json`, SHA-256
`13a928cd6854d9e13e747c0e2e48456b6c224bc0caa2b8647abbe12270422a96`.
Its explicit result is candidate prepared / startup-recovery parity unqualified.
No application/database startup, SQL, provider or browser authentication ran.

The frontend URL/key were build-only synthetic values; the key is not a genuine
Supabase JWT. This artifact cannot support authenticated production screenshots.
It contains no Codex executable or approved live launcher. Application fixes
prepared on 2026-10-12 are absent from this image. Do not use it to qualify
current application source or request a source-stale recovery retry.
