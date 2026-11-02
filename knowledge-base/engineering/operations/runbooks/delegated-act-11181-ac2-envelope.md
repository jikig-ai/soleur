# Delegated act — ADR-068 AC 2 (owner-side relay activation), epic #11181

## Production Envelope - AC2

Delegation: https://github.com/jikig-ai/soleur/issues/11181#issuecomment-6417763814
Epic: #11181
Scope item: 1

Command:

```text
gh workflow run apply-web-platform-infra.yml -f host_proxy_tls_enabled=true
```

Blast radius: One `host_proxy_tls_enabled=true` apply through `apply-web-platform-infra.yml` (R2 backend serializer). Config-only: no code change, no host reboot, no LB pool mutation, no web-2 routing. web-2 remains structurally absent from `default_pool_ids` / weight 0. The Doppler secret writes (SOLEUR_PROXY_PEER_ALLOWLIST, SOLEUR_HOST_ROSTER) and git-data token scoping are operator-class prerequisites, not part of this delegated act (credential rotation overlaps the Excluded list).

Preconditions:
- Gate: no-inflight-run apply-web-platform-infra.yml
- Delegation verified valid (created 2026-10-26T13:55:06Z, expiry 2026-11-25).
- PR #11210 merged (per-host SOLEUR_PROXY_BIND injection) — confirmed 2026-10-26T15:56:37Z.
- Operator completed Doppler writes: SOLEUR_PROXY_PEER_ALLOWLIST="10.0.1.10,10.0.1.11" and SOLEUR_HOST_ROSTER="web-1=10.0.1.10,web-2=10.0.1.11" (operator-class, not delegated).
- Parallel cutover session confirmed topology unchanged: web-1=10.0.1.10, web-2=10.0.1.11.
- No in-flight `apply-web-platform-infra.yml` run (R2 serializer).
- Operator completed git-data token scoping to read-only `prd_git_data` config (operator-class, not delegated).

Verification:
- `gh run list --workflow apply-web-platform-infra.yml --limit 3` (confirm the apply completed green)
- `gh run view <run-id> --json conclusion` (expect `success`)
- Re-run `lb-weight-gate.sh` Condition A → expect exit 0 (AC 3, sequenced after this act lands)
- Evidence posted to epic #11181 as a comment.

Abort: Stop before the apply if an `apply-web-platform-infra.yml` run is in-flight. Stop if `delegation-verify.sh` returns non-zero for the command triple. Stop if the cutover-session topology confirmation is missing or differs.

Rollback: Re-run `apply-web-platform-infra.yml` with `host_proxy_tls_enabled=false`. Doppler writes are operator-class and rolled back by the operator.

Stop conditions: Halt if the delegation is edited, expired, or revoked mid-act. Halt if the cutover session reports a topology change. Halt if the apply workflow fails or if any required check turns red. Halt if any command is not byte-identical to the envelope line (verifier rejects mismatch).
