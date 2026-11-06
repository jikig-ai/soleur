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
late-October host-replace prework (2026-10-26), which subsumes the issue's
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

All commands run literally against the worktree on 2026-11-06, on the committed
tree (HEAD `a7f6102` + this file's commit).

### AC1 — rehearsal volume resources gone — PASS

```text
$ git grep -nE 'hcloud_(volume|volume_attachment)"[[:space:]]+"rehearsal_inngest"' -- apps/web-platform/infra/inngest-provision-rehearsal/
(no output; rc=1 — zero hits)
$ grep -c 'resource "hcloud_volume"' apps/web-platform/infra/inngest-provision-rehearsal/rehearsal.tf
1
```

Only `rehearsal_inngest_luks` + `rehearsal_inngest_luks` attachment remain.

### AC2 — ledger row deleted; lint green — PASS

```text
$ grep -cE 'hcloud_volume\.rehearsal_inngest\b' scripts/encryption-posture-ledger.json
0
$ python3 scripts/lint-encryption-posture.py
::warning::encryption-posture: dedicated inngest host -> web-platform app sdk_url poll ... in_transit exception expires in 6 day(s) (2026-11-12); tracking #10538 ...
::warning::encryption-posture: Cloudflare edge -> web hosts origin for app.soleur.ai ... in_transit exception expires in 6 day(s) (2026-11-12); tracking #10479 ...
encryption-posture: 19 stores, 12 connections, 0 unledgered, 0 failing checks -> PASS
```

(The two `::warning::` lines are pre-existing expiry notices for unrelated
in_transit exceptions; exit 0.) Store count 19 → the `*.tf` census dropped in
step with the row, so the positive-work floor stays consistent.

### AC3 — plan-shape suite with trimmed fixtures — PASS

```text
$ bash tests/scripts/test-inngest-provision-plan-shape.sh
=== inngest-provision-plan-shape: 28 passed, 0 failed (28 cases, 4 mutants) ===
```

Both import-refusal cases retargeted at `hcloud_volume.rehearsal_inngest_luks`
refuse with "the plan IMPORTS hcloud_volume.rehearsal_inngest_luks".

### AC4 — rehearsal sentinel + terraform validate — PASS

```text
$ bash apps/web-platform/infra/inngest-provision-rehearsal.test.sh
=== inngest-provision-rehearsal: 91 passed, 0 failed (91 assertions) ===
$ terraform -chdir=apps/web-platform/infra/inngest-provision-rehearsal init -backend=false -lockfile=readonly
$ terraform -chdir=apps/web-platform/infra/inngest-provision-rehearsal validate
Success! The configuration is valid.
```

### AC5 — blank-`prd` DR procedure written — PASS

`inngest-luks-cutover-6894.md` §"2026-11-06 — blank `prd` volume bring-up: the
disaster-recovery procedure (#10112)" replaces the "needs a written procedure
when it is ever needed" placeholder (the §6 bullet now points at it). It names,
verified by grep: `INNGEST_LUKS_ACTIVE_VOLUME_ID` deletion in
`soleur-inngest`/`prd` (pointer refuses at `STAGE=resolve`/`reopen_pointer`
before the format arm), the reviewed `rehearsal_*` → `rehearsal_*|prd` allowlist
window with `_D6_HEAD`/UNP5 pin updates in the same diff,
`apply_target=inngest-host-replace`, the
`luks_format` → `luks_open_fresh` → `mkfs` → `mount_luks` verification rows, the
revert PR, the optional pointer re-write — and states plainly "verified
statically, not drilled" and the deliberate NOT (no standing flag, var, or
apply target). CTO ruling carried verbatim.

### AC6 — resolver-duplication disposition recorded — PASS

`inngest-luks-cutover-6894.md` §"2026-11-06 — the two-copy resolver decision is
deliberate (#10112)" + ADR-142 §"Addendum — 2026-11-06 (#10112)" item (b) name
both copies (`/usr/local/bin/inngest-luks-open.sh` write_files + runcmd
`STAGE=resolve`), the deliberate asymmetries (reopen never formats —
`reopen_not_luks`; pre-network `logger` vs `$INNGEST_LUKS_DETAIL` tee;
stage's `*[!0-9]*` non-numeric arm vs reopen's `reopen_pointer` fold), and the
drift bound (loopback suite executes both verbatim; `inngest-redis-luks.test.sh`
literal pins; ADR-142 D5 pinned-duplication precedent). Ruling = accept; the
share path (task 4.3) is NOT executed per the CTO ruling, and both texts record
the caveat that a future "share" flip must re-run the `cloud-init-inngest.yml`
overlap check.

### AC7 — rehearsal runbook corrected — PASS

```text
$ grep -n 'two scratch volumes' knowledge-base/engineering/operations/runbooks/inngest-provision-rehearsal.md
(no output; rc=1 — absent)
```

Phase-A description now reads "one scratch volume (the LUKS store — the unused
plaintext scratch volume was removed in #10112)"; the stranded-state edge is a
new failure-table row plus §"Stranded pre-#10112 volume in state" with the
`terraform state rm hcloud_volume.rehearsal_inngest
hcloud_volume_attachment.rehearsal_inngest` remediation and the teardown-only
dispatch alternative.

### AC8 — verify-clean-10390 absence verified (PR-body material) — VERIFIED

`git ls-tree origin/main scripts/followthroughs/inngest-verify-clean-10390.sh`
returns nothing — absent on `origin/main` (retired by the inngest@4 upgrade
PR). Ship phase folds this into the PR body and annotates the epic #10390
residual line (epic stays open).

### AC9 — cutover trio absent verified (PR-body material) — VERIFIED

`git ls-tree -r origin/main --name-only | grep -E 'inngest-luks-cutover\.(sh|service|timer)$'`
returns zero hits — item 1 closed upstream by the 2026-10-26 host-replace
prework. Ship phase folds this into the PR body with `Closes #10112`.

### Gate re-run note

`bash scripts/test-all.sh --affected` was NOT run: `bash scripts/test-all.sh
--capacity` reports `CAPACITY_CONTENDED reason=sibling_runs measured_runs=1`
(two pids in `.worktrees/feat-one-shot-bun-pair-ratchet-accept-cleanup`).
The named gates above all pass; the affected-derivation sweep is left for the
parent per the advisory-lock rule.

`markdownlint` (repo-pinned, `scripts/markdown-lint.sh`): all three edited/added
markdown files clean — `inngest-provision-rehearsal.md`,
`inngest-luks-cutover-6894.md`, `ADR-142-...md`, `verification-notes.md`.
