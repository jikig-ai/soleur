# Host fan-out — the running-host delivery contract for SSH `terraform_data` provisioners

Loaded by `plan/SKILL.md` Phase 2.8 (`## Infrastructure (IaC)` → `### Host fan-out`).
Required whenever a plan adds or edits a `terraform_data` SSH provisioner under
`apps/web-platform/infra/`; structurally encouraged for any multi-host fleet.

## Why the question exists

Running hosts' cloud-init is frozen (`ignore_changes = [user_data, ...]` on
`hcloud_server.web`), so an artifact added to `cloud-init.yml` or the image bake
reaches a running host only at its next `-replace`. A `terraform_data` SSH
provisioner targeted by the push-apply workflows is the hot-delivery path for the
host it dials — and ONLY that host. An artifact that web-1 gets via provisioner
and the sibling never gets leaves an entire class of sessions dark on that host;
the failure mode is silent because every check runs green on web-1.

## The classification

For each SSH-provisioned artifact, classify EVERY OTHER fleet host explicitly:

- **`twin`** — the sibling gets the artifact hot too: add a `<name>_web<N>`
  provisioner (`host = hcloud_server.web["web-<N>"].ipv4_address`,
  `host_key = local.web_<N>_ssh_host_key`, `%RAND%` in `script_path`,
  `timeout = "5m"`) and wire it into the push-apply `-target` list in
  `.github/workflows/apply-web-platform-infra.yml` (or the owning workflow).
  Web-2 twins carry NO credential material — the no-prd-credential boundary is
  enforced by the parity guard.
- **`role-only`** — the artifact is meaningless on the sibling (it probes the
  dialer's own host key; it plumbs a receiver that lives on one host). Name the
  reason in the plan.
- **`birth-covered`** — the artifact predates the sibling's last `-replace` and
  rode its birth cloud-init. The plan must name the introducing PR so a reviewer
  can check the date; an artifact introduced AFTER the sibling's birth may not
  claim this class.

## Mechanical enforcement

`apps/web-platform/infra/web-host-provisioner-parity.test.sh` sweeps
`server.tf` and enforces the same classification: `FLEET_SSH_HOSTS` is the
declared sibling roster, and every SSH-connected `terraform_data` must cover
each sibling via a `<name>_web<N>` twin, a symmetric base-twin, or an
`ONLY_JUSTIFIED["<name>@<host>"]` entry. Unclassified dialers red; stale
entries red; dialers on undeclared hosts red. The mutation suite
(`web-host-provisioner-parity-mutation.test.sh`, cases M4h/M4i) proves the
guard catches a phantom web-1-only dialer and an undeclared web-3 dialer.

The running-web-2 delivery census lives in `server.tf` at the
`egress_gateway_web2` comment — update it when adding a channel.

**Why:** #9534 — the web-1 egress-gateway provisioner would have shipped
web-1-only; the miss surfaced only when someone asked the question by hand.
