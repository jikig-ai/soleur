# Decision Challenges — feat-one-shot-6608-6197-inngest-host-prewiring

Headless one-shot run. These are surfaced here (not via AskUserQuestion) per the plan-skill
headless predicate; `/ship` renders them into the PR body and files an `action-required` issue.

## Challenge 1 — #6197 premise is stale: its code + OCI delivery are already complete (decisionClass: user-challenge)

**Operator's stated direction (task input):** "#6197 (P3): arm64 Vector shipper on the dedicated
host — add aarch64-unknown-linux-musl Vector build URL + pinned arm64 SHA + checksum override to
the inngest bootstrap (currently x86_64-hardcoded); provision BETTERSTACK_LOGS_TOKEN into the
soleur-inngest Doppler project … likely via OCI image rebake + OCI pin bump."

**Measured reality (2026-07-18):**
- PR **#6209** (merged 2026-07-07, `Ref #6197`) already: arch-parameterized the Vector install
  in `inngest-bootstrap.sh` (`arm64) vec_triple="aarch64-unknown-linux-musl"`), pinned
  `vector_sha256_arm64` in `vector.tf`, threaded it through `inngest-host.tf` + cloud-init
  `VECTOR_CLI_SHA256`, un-deferred Vector in `cloud-init-inngest.yml`, widened the boot isolation
  self-check to admit `BETTERSTACK_LOGS_TOKEN` (4→5), and created `inngest-betterstack-token.tf`
  provisioning `BETTERSTACK_LOGS_TOKEN` into the isolated `soleur-inngest/prd` project.
- PR **#6631** further hardened the Vector/doppler wiring; the OCI image was rebaked to
  **v1.1.23** by PR **#6651** (2026-07-18).
- Verified the published tag carries the change (per the "image-baked is a claim" learning):
  `git show vinngest-v1.1.23:…/inngest-bootstrap.sh | grep -c aarch64` = 1;
  `BETTERSTACK_LOGS_TOKEN` present in the tagged bootstrap (2×) and cloud-init isolation allowlist
  (6×); #6631 is an ancestor of the tag.
- PR #6209 was deliberately `Ref #6197` **not** `Closes` — #6197 stays open only as the tracker
  for the HELD Phase-2 host re-provision (dependency gate on epic #6178).

**Challenge:** There is **no code work remaining for #6197**. Re-implementing any of it would be
building on a stale premise (the #6497-class trap). This plan therefore does **not** touch the
Vector / BetterStack surface. The only outstanding #6197 item is the HELD Phase-2 cutover
re-provision, which is epic #6178's operator maintenance window — out of scope for this PR.

**Recommended disposition:** keep #6197 open as the Phase-2 tracker (its issue body says
"Re-evaluate before the Phase-2 cutover"); this PR records the reconciliation. Do not close #6197
here — its close condition (host re-provisioned + logs shipping) is not yet met.

## Challenge 2 — #6608 apply-path sequencing: fold into Phase-2 vs. immediate host-replace (decisionClass: taste)

Changing `web_host_private_ips` is baked into `user_data` (ForceNew) → force-replaces
`hcloud_server.inngest`. The resource is excluded from per-PR CI `-target`, so **merge is inert**.
Two delivery options for the corrected literal:

- **(A) Immediate:** dispatch `apply_target=inngest-host-replace` post-merge (scoped, AOF-preserving,
  menu-ack) to re-render nftables now.
- **(B) Latent (recommended):** let the corrected literal ride the **HELD Phase-2 cutover
  re-provision** — the same host replace that delivers #6197's already-merged wiring — so no
  separate maintenance window and no new operator step is introduced.

**Rationale for (B):** the host is DARK/inert (zero prod crons), deny-all-public; `10.0.1.11`
currently belongs to no host; `/api/inngest` is HMAC-fail-closed; the immutable-redeploy learning
(2026-07-07) warns a bare replace can leave the NIC down needing a soft reboot — cheaper to verify
inside the Phase-2 window the operator is already in. **Escape hatch:** if a read-only check shows
`10.0.1.11` has been reallocated to a live host before Phase-2, dispatch `inngest-host-replace`
immediately (documented in the runbook). Use `Ref #6608` (ops-remediation class), close at Phase-2.
