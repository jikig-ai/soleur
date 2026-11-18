# Independent actual-manifest review — 2026-10-19

Verdict: **PASS for the scoped redirect-header diagnostic only**. Independent
security reviewer `actual_manifest_review` found no blocking findings. No network
request, marker consumption or receipt creation occurred. Fresh exact-action
approval remains required before execution. This is not full-branch review.

## Exact bindings

- Source and pushed PR #9051 head:
  `8f2700ede4259367ea4ae3ba011af9d82c5b559c`; tracked source clean.
- Actual manifest: `.soleur/redirect-diagnostic-8f2700ed-20261019/redirect-diagnostic-manifest.json`.
- Canonical manifest SHA-256:
  `9a23cd9c43a5d89590b6d7c1fb8cd329c515d84c3bac9ee2396669886397da4c`.
- Runner SHA-256:
  `9c242df4fffe92107f4947ffffdf058cb2028eda4bd4cd8a0ae8e8b3ae229dbb`.
- All 13 dependency hashes match the contract, executing files and committed
  source. Contract, input, pairing, operational and retained-manifest bindings
  match the actual manifest.
- CA: 185,311 bytes, SHA-256
  `8c97794a899a32666593979dc7adfaec8bda2b420eb092ff0d987e44ad0bf6ea`;
  strict projection preserves 121 certificate blocks. Explicit CA trust,
  hostname verification and required certificate verification apply.
- Platform: 864 bytes, SHA-256
  `168f762c218e167ba88ae7e48194126eb5ba5e99ef652063e3f14f9c4f0ee70f`.
  Exact OCI Config descriptor: size 2,646, digest
  `sha256:3f56e44ddc1a5655b8f288a2aa812db567b2f5f0b8bc18ef3da63b94a95608d5`.
- Private output fingerprint: device 64769, inode 9648079, UID 1000;
  directory/manifest modes 0700/0600. Descriptor-relative no-follow checks cover
  ancestors. Only the manifest exists; one-use marker and receipt are absent.

## Action and retention boundaries

Exactly two fixed HTTPS GETs: anonymous repository-scoped token, then the pinned
Config endpoint on registry-1.docker.io. Token JSON is read only in memory, at
most 16,384 bytes. Config response body is never read; require status 307 and one
bounded Location. No retry, redirect following, destination request or layer
fetch is permitted. Retain only the nine allowed routing/hash fields and fixed
receipt metadata; exclude raw Location, query values, bearer and exception text.

Pure import and manifest/source validation passed under `/usr/bin/python3.14`
(3.14.8). Python, Git and timeout executable bytes are outside manifest hash
bindings; runner source is bound. The approval command fixes interpreter and
timeout paths. DNS and other cooperative operations require the outer timeout.

## Exact command awaiting fresh approval

Run from `/data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-codex-web-live-paths`:

```bash
/usr/bin/timeout -k 5 90 /usr/bin/python3.14 -B /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-codex-web-live-paths/scripts/codex-qualification/redirect_diagnostic.py execute --manifest /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-codex-web-live-paths/.soleur/redirect-diagnostic-8f2700ed-20261019/redirect-diagnostic-manifest.json --manifest-sha256 9a23cd9c43a5d89590b6d7c1fb8cd329c515d84c3bac9ee2396669886397da4c --runner-sha256 9c242df4fffe92107f4947ffffdf058cb2028eda4bd4cd8a0ae8e8b3ae229dbb
```

The outer bound is 90 seconds with five seconds before forced termination;
internal limits remain 60 seconds overall and at most ten seconds per request.
If approved, execute once, then separately review resulting sanitized evidence.
No destination authority, publisher provenance, actual profile/recovery evidence,
runtime qualification or promotion readiness follows from this review.

PR remains draft, disarmed, default-off and customer-blocked. Build, Docker,
SQL, provider/browser/account operations, recovery, qualification, Web/CLO
matrices, promotion and ship gates stay held. Hosted auth remains BLOCKED;
alternate route remains PENDING.

This record and the session learning are left untracked until subsequent
evidence work so committing them does not change the manifest's exact source
HEAD before its approved attempt.

## Approved execution and separate evidence review — 2026-10-19

The operator approved the exact command above; it ran once and exited 1 with
the fixed incomplete message. Approval is consumed. The one-use marker remains.
The independent security reviewer separately verified the incomplete evidence:

- Receipt self-hash:
  `834c8ba7b1d6f306511d2d05034c67031ac4fc28c4986d61fc89e3a2af71c550`.
- Receipt file SHA-256:
  `a0c9b287d235f686250eee8c545b8024089a32f0e49fa66b3db3892e56e8597d`.
- Marker file SHA-256:
  `0dd4debcbd3ca2fbd08105c9def0be75ff2d5db076067f1125810efb254dc6a4`.
- Manifest/context/action/marker bindings match. Original private directory
  fingerprint and 0700/0600 modes match; no extra files exist.
- One attempted token GET, HTTP 200, `transport/header_shape`. Config GET was
  not attempted; no routing projection exists. All authority flags stay pending.
- Source inspection places refusal after parsing headers and before application
  token-body reading. No raw headers, token/body, Location, query values or
  exception text were retained. No destination or layer request occurred.

Verdict: **PASS for integrity of incomplete evidence; diagnostic goal incomplete**.
The precise failed header predicate cannot be inferred. The collector's last
checked monotonic clock precedes the transport exception, so its finish field
does not establish actual execution duration. No retry or follow-on is authorized.

The next source-only boundary is recorded in
`prebuild-acquisition-2026-10-16.md` under “Classified token-header refusal”.
