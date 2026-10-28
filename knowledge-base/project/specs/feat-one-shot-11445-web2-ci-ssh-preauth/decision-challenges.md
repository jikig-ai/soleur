# Decision Challenges — feat-one-shot-11445-web2-ci-ssh-preauth

Plan: `knowledge-base/project/plans/2026-10-28-infra-web2-ssh-preauth-after-rebirth-plan.md` (issue #11445).
No agent-spawning tool is available in this harness, so technical rows carry `pending - assumed:` rulings per the delegation rule.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Root cause / repair ordering — the issue asserts "auth rejection (CI key absent)"; the run log (40744937376) shows `Host key verification failed.` against the stale committed pin | technical | pending - assumed: **stale host-key pin is the primary defect** (evidence-resolved by the run log: client aborts during kex at `StrictHostKeyChecking`, auth never attempted; web-2's sshd-side `[preauth]` close matches). Pin re-capture is unconditionally first; both operator-authorized paths demoted to diagnostic-gated arms |
| Repair-path A-vs-B within the authorized envelope — admin-IP key install vs guarded re-replace | technical | pending - assumed: **admin-IP key install preferred over re-replace** when and only when Phase B proves the pubkey absent — non-destructive, idempotent, and a re-replace produces yet another host key (still needs Phase A). Re-replace reserved for host-level breakage (incomplete cloud-init beyond keys, sshd damage) |
| Conditional key-install instrument — raw admin `ssh` append vs `terraform_data.root_authorized_keys_web2` twin | technical | pending - assumed: **IaC twin** — mirrors `terraform_data.root_authorized_keys` (ci-ssh-key.tf), satisfies `hr-all-infrastructure-provisioning-servers`, is state-tracked and idempotent; cost is the EXT_RESIDENCE + `EXCLUSION_ALLOWLIST` + census bookkeeping (~4 files) |
| PR content shape — pin-only vs pin + unconditional twin | technical | pending - assumed: **pin-only if Phase B shows the pubkey present** (cloud-init `ssh_authorized_keys` parity is the likely state — the same template birthed prior web-2 hosts that passed this step); twin ships only on proven key absence (mechanism-minimality) |
| Operator-egress allowlist state at capture time | operator (irreversible/production-mutating authorization — none needed beyond the brief's authorization; flagged for visibility only) | pending - assumed: operator's current egress ∈ `var.admin_ips` (the admin-IP sshd path the brief asserts); if the keyscan fails on egress, `/soleur:admin-ip-refresh` precedes Phase A (its own ack) |
