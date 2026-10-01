# Decision challenges — feat-one-shot-6931-web2-fresh-boot-luks

Decisions taken during headless planning that go against, narrow, or reinterpret the stated direction in
issue #6931, recorded per ADR-084 so they are auditable outside this session. `ship` renders these into the
PR body and files them as `action-required` issues.

**Mode: headless (one-shot planning subagent).** Nothing below was asked of the operator; the operator's
stated direction is the default and each entry names how to revert to it.

---

## DC-1 — User-Challenge: "ONE topology" is delivered as ONE MECHANISM with two Terraform addresses

**Classification:** User-Challenge (the issue's item 4 asked web-1 and web-2 to "share ONE topology (cattle parity)").

**Stated direction.** Decide whether web-1's post-de-pet serving volume is the additive singleton or a fresh-boot
`for_each` volume, so both hosts share one topology.

**What the plan does instead.** web-1 keeps the singleton `hcloud_volume.workspaces_luks`; web-2 keeps the keyed
`hcloud_volume.workspaces["web-2"]`, now raw and LUKS-at-boot through the SAME baked provisioner. The boot behaviour
is host-name-independent; the Terraform addresses differ. The single keyed resource (T2) is deferred behind the
web-1 de-pet.

**Why.** T2 needs a `state mv` of the sole-copy volume on a root where `moved` fails every `-target` plan (ADR-119
addendum, measured), and PR #9348 is already changing the same `for_each` and ledger row. The CTO consult ruled T1
with a T2-ready seam.

**To revert to the stated direction.** Ship T2 as its own single-use state-surgery workflow (the
`workspaces-plaintext-forget.yml` precedent) after PR #9348 lands; ADR-262 records the migration path.

---

## DC-2 — Taste: user_data token delivery instead of the CTO's preferred post-boot delivery

**Classification:** Taste (the CTO consult preferred delivery over the bastion; the plan deviates).

**What the plan does.** The existing boot token is passed as a `templatefile()` variable into `/etc/default/luks-monitor`.

**Why.** A rebirth changes the host SSH key and the committed pin file is re-captured by a follow-up PR, so a
post-boot delivery step cannot complete inside one dispatch. Containers are already default-drop firewalled with no
metadata-endpoint allowlist entry; the residual (root-equivalent host users) is recorded as R4.

**To revert.** Replace the user_data variable with a bastion-forward step in the birth job after the pin is
captured; accept a two-step birth.

---

## DC-3 — Narrowing: `web-host-create` will refuse `web-1` by name

**Classification:** Narrowing of an existing capability (merged with the birth path; the `image_tag` help text says it
is "required when birthing web-1").

**What the plan does.** Guard 2 adds a named refusal of `web-1` in `web-host-birth-gate.sh`, because the web-1 LUKS
attachment is hard-bound to web-1 and outside the birth fan-out (#6964); the refusal is the cheapest enforceable
invariant under the singleton topology.

**To revert.** Implement #6964's option 2 (a conditional `-target` of the attachment when the key is web-1) and give
the gate a key-conditional requirement arm instead of the refusal.

---

## DC-4 — Interpretation: the issue's stale ADR ordinals are corrected, not followed

The issue body cites "ADR-142 Decision 3" and its title cites "ADR-141 D3"; the binding text is ADR-143
Implementation Rulings R3. The plan cites R3 and sweeps the stale citations (including `model.c4` prose).

---

## DC-5 — Taste: the soak marker lives in a dedicated Doppler config, not shared `prd`

The issue wrote "Doppler `prd`". Doppler tokens are scoped per config, so a write token on `prd` can overwrite any prd
secret, and the git-data stamp precedent is only tolerable because its caller is an environment-gated dispatch while this
writer is a daily cron. The plan uses `prd_workspaces_luks_marker` (one `doppler_config`, one write token). To revert: write
to `prd` and gate the job behind a reviewer-protected environment (it then cannot run unattended).

## DC-6 — User-Challenge: three reviewers recommend splitting the work; the operator asked for one implementation

DHH, the CTO devex lens and the simplicity pass each recommended splitting (provisioner + raw-at-birth; verification +
marker; birth-gate hardening) and treating the live rebirth as an operation. The plan keeps the issue's single scope and adds a
"Delivery slicing" section with a peel-off commit order. To adopt the split, file PR-2 and PR-3 as follow-up issues now.

## DC-7 — User-Challenge: reviewers recommend deferring the marker writer and the escrow arm

DHH and the simplicity pass argue the marker has no consumer today (no caller sources it into `lb-weight-gate.sh`) and that
header escrow on an empty standby protects nothing yet. Issue item 3 explicitly asks for the marker, so it stays in scope.
Escrow stays in scope too, in a reduced form: non-fatal at boot, and a hard precondition of the marker, so the fence before
any user data is the marker rather than the boot path. To revert: drop the marker writer and its Terraform (item 3), and move
escrow into the flip orchestrator's preconditions.

## DC-8 — Taste: web-2 is converted by a rebirth, not an in-place reformat

DHH noted that the emptiness evidence needed for the rebirth would equally justify a one-time wipe-and-format dispatch, which
would avoid the state-removal-plus-API-delete bypass of `prevent_destroy`. The plan keeps the rebirth because the issue's
purpose is the disposability proof (a host rebuilt from IaC) and `hr-prod-host-config-change-immutable-redeploy` forbids
mutating the running host. To revert: a gated job that proves emptiness, runs `wipefs -a` on the device, and reboots into the
provisioner's `format` arm.
