---
branch: feat-one-shot-10112-inngest-residuals
created: 2026-11-06
issue: 10112
---

# Verification Notes — feat-one-shot-10112-inngest-residuals

Durable verification artifact for issue #10112; `ship` folds this into the PR
body. All premises re-verified against `origin/main` (`4e0f90b`) on 2026-11-06.

## Phase 1 — premise re-verification

### Item 1 — image-baked cutover trio already retired (verify-only)

`git ls-tree -r origin/main --name-only | grep -E 'inngest-luks-cutover\.(sh|service|timer)$'`
returns zero hits. The image-baked executor trio
(`inngest-luks-cutover.sh`, `inngest-luks-cutover.service`,
`inngest-luks-cutover.timer`) does not exist on `origin/main` — retired by the
late-October host-replace prework (2026-10-24), which subsumes the issue's
"strip plaintext vocabulary + new image + pin bump" ask: there is nothing left
to strip. Item 1 is closed upstream.

Note on near-miss names: `scripts/followthroughs/inngest-luks-cutover-6894.sh`
still exists on main — it is a different artifact (a retired BetterStack probe
followthrough for #6894, RETIRED 2026-09-21 per its own header), not the
image-baked executor. Out of scope for item 1.

### Epic residual — `scripts/followthroughs/inngest-verify-clean-10390.sh`

`git ls-tree origin/main scripts/followthroughs/inngest-verify-clean-10390.sh`
returns nothing — already absent on `origin/main` (retired by the inngest@4
upgrade PR). The epic #10390 body still records this residual as "still owed";
it is discharged. Ship phase annotates the epic line.

### Item 2 — scope-lift provenance

Issue #10112 records the rehearsal-volume removal as filed under an operator
scope-exclusion: "first candidate to pull forward if the operator lifts the
exclusion". The resume brief for this change explicitly lists the unused
rehearsal volume in scope — that is the lift, recorded in
`decision-challenges.md` (operator-scope row, RESOLVED). Removal proceeds
under that authorization.

### Item-2/3/4 code premises (still true on main)

- `hcloud_volume.rehearsal_inngest` at
  `apps/web-platform/infra/inngest-provision-rehearsal/rehearsal.tf:241`;
  `hcloud_volume_attachment.rehearsal_inngest` at line 330.
- `scripts/encryption-posture-ledger.json` carries exactly one `stores[]`
  row keyed `"store": "hcloud_volume.rehearsal_inngest"` (line 258, through
  its exception block); the `rehearsal_inngest_luks` row at line 281 stays.
- `unpointed_raw_refused` arm present at
  `apps/web-platform/infra/cloud-init-inngest.yml:2690-2691` —
  `case '${inngest_doppler_config}' in rehearsal_*)` allowlist.
- Both resolver copies present: `write_files`
  `/usr/local/bin/inngest-luks-open.sh` (line 202) + the runcmd
  `STAGE=resolve`/unpointed arm.
- `inngest_doppler_config = "prd"` literal at
  `apps/web-platform/infra/inngest-host.tf:391` (the plan cited `main.tf`;
  the literal actually lives in `inngest-host.tf` — same line number).
- `inngest_luks_volume_id = hcloud_volume.inngest_redis_luks.id` at
  `inngest-host.tf:373`.
- `_D6_HEAD` pin at `inngest-redis-luks.test.sh:427`; UNP5/UNP5b arms at
  `inngest-redis-luks-loopback.test.sh:532-549`.
- `apply_target=inngest-host-replace` is a live dispatch option in
  `.github/workflows/apply-web-platform-infra.yml`.
- ADR-282 two-step lift (delete_protection + `prevent_destroy`) documented at
  `apps/web-platform/infra/inngest-redis-luks.tf:155-175`.

## Phase 5 — acceptance-criteria sweep

(Recorded below after execution — see "AC outcomes" at end of file.)

## AC outcomes

_To be filled in Phase 5 with literal command results for AC1–AC9._
