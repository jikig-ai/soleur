# Decision challenges — feat-8714-53biii-off-ghcr (plan review, headless)

Taste findings the plan did NOT apply. Each is recorded for the operator.

1. **DHH: cut the post-load ID ∈ {C, D} check and keep T only.** Not applied. The ID check costs
   one comparison and a C literal. It also proves by content address, independently of the
   published bytes, that docker loaded the upstream image. The CTO ruling asked for it.
2. **CTO: use pinned `crane pull --format=oci` instead of the curl builder.** Not applied. The
   curl builder is about 30 lines, can be tested offline with a stub curl, and needs no extra
   binary download inside `publish`/`rehearse`.
3. **Architecture: write a new ADR for "a GitHub release is the boot source of the sole pull
   path", not amendments.** Not applied. ADR-096 (the migration) and ADR-169 (what authorizes
   destroying the sole pull path) are amended instead.
4. **Simplicity: run one `rehearse` leg (the host's docker store) rather than two.** Not applied.
   The host store (docker.io 29.1.3 default) was not measured, and the second leg is one CI job.
5. **Architecture/DHH: turn on GitHub immutable releases, or keep a second copy of the asset in an
   independent store.** Not applied. Immutable releases is a repo-wide setting that would also
   affect the `v*`/`web-v*` release flow. Mitigations in place:
   - preflight P6 refuses any replace onto a missing or altered asset;
   - rule-audit detects a deleted asset;
   - recovery is to re-publish (reproducible) or revert PR 2b.

   Residual risk: an uncontrolled registry host loss while the asset is missing AND ghcr.io no
   longer serves v2.1.20.
6. **Spec-flow/Kieran: add a standing alert on `ghcr_blocked != 1`.** Not applied. Nothing on the
   host needs ghcr.io, so the deny is proof, not protection. It persists through the cloud hosts
   template.
