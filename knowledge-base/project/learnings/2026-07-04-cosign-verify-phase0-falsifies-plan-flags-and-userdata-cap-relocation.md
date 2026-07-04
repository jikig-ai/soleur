---
title: "Phase-0 probe falsified the plan's cosign flag set (→ CTO/ADR-085); cloud-init 32KB cap forced trusted-root relocation"
date: 2026-07-04
tags: [supply-chain, cosign, one-shot, phase-0, cloud-init, architecture-fork, ADR-085]
issue: 6005
---

# Cosign private-GHCR verify (#6005) — two load-bearing lessons

## 1. A Phase-0 capability probe falsified the plan's prescribed flags → architecture fork → CTO

The plan (deepened + security-sentinel-reviewed) prescribed
`cosign verify --offline=true --new-bundle-format=false --trusted-root=<local> <digest>`.
A live Phase-0 probe against the REAL SHA-pinned cosign v3.1.1 container falsified it:

- `cosign verify` in v3.1.1 has **no** `--new-bundle-format` flag.
- `--offline` is **deprecated** (hidden from `--help`; removed in cosign v4) and, critically,
  still performs a **registry round-trip** for the OCI-attached `.sig` — it only suppresses
  the online tlog/rekor lookup. `docker pull` of the image does NOT pull the `.sig`.
- So the shipped bare-`--offline` verify (no pinned root) reaches the TUF CDN for its trust
  root → blocked by the #5046 container egress firewall → **never passes** (the #6005 bug).

This is exactly the `hr-verify-repo-capability-claim-before-assert` /
"plan-quoted numbers are preconditions to verify" discipline: **the plan is authoritative for
intent, never for a tool's exact flag/behavior.** The resolution (deprecated-`--offline`+
allowlist-widen vs. host-prefetch+`--network none` vs. `--network host`) was an
**engineering fork with material trade-offs**, so per the /work HARD GATE it routed to the
`soleur:engineering:cto` agent, NOT the operator. The CTO ruled **Design B′** (ADR-085): a
`--network host` ephemeral verifier so the `.sig` fetch rides the host's unrestricted egress —
keeping `ghcr.io` OUT of the sweep-enumerated container allowlist — with a pinned
`--trusted-root` + `--offline` (frozen inert by the pinned SHA; SOLEUR-DEBT tied to the next
SHA bump). Lesson: **do the load-bearing capability probe BEFORE writing the shell, and when
it contradicts the plan, route the fork to the CTO and record it in an ADR.**

## 2. The Hetzner 32,768-byte user_data cap forces baked-image delivery, not cloud-init write_files

The plan said deliver `trusted_root.json` (6.8 KB) via cloud-init `write_files`. But
`cloud-init.yml` renders to ~30.5 KB of user_data against a **hard 32,768-byte Hetzner cap**
(not gzipped) — a ~9 KB base64 embed (or even a ~1.3 KB inline `docker login` block) blows the
sub-cap budget (`cloud-init-user-data-size.test.ts` WEB_BUDGET=30,500). The established pattern
(#5921): **bake large host assets into the HOST base image** (`local.host_script_files` +
Dockerfile COPY + `.dockerignore` reinclude + `soleur-host-bootstrap.sh` install), extracted at
boot under a combined-hash verify. This is NOT circular trust: the trusted root is baked into
the **host** image, not the **app** image cosign verifies. The fresh-boot GHCR `docker login`
was likewise relocated from cloud-init into the baked bootstrap (zero user_data cost).

Corollary (staleness gate): sigstore's `trusted_root.json` has **no root-level expiry** — its
only `validFor.end` dates are retired 2022 keys (always past). So "parse expiry, fail within N
days" false-fails immediately; the correct deterministic signal is a **capture-age** gate
(fail once the committed root is older than a re-capture threshold).

## 3. Adding a no-default TF variable requires updating the terraform-test harness

A new `sensitive`, no-default `variable` (`hr-tf-variable-no-operator-mint-default`) makes
`terraform test` fail ("No value for required variable") — the `.tftest.hcl` top-level
`variables {}` block must get a dummy value for it, same as every other required var. Local
`terraform validate` passes (validate doesn't need var values); only `terraform test` (which CI
runs) catches it. Also add the resource to the auto-apply workflow's `-target` list
(`terraform-target-parity.test.ts`).
