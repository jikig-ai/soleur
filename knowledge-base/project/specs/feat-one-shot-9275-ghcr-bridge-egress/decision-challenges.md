# Decision challenges for feat-one-shot-9275-ghcr-bridge-egress

Taste / User-Challenge records produced during planning (headless). `ship` renders these into the PR
body and files the `action-required` issue. Both are informational: the operator's direction was
interpreted narrowly, and the default (the operator's stated scope) is noted for each.

## DC-1: the `185.199.108.0/22` allowlist range is retained, not narrowed

- **Operator direction:** scope what bridge containers need from GitHub IPs, then narrow the allowlist
  only for what scoping proves unneeded.
- **Finding:** a static census of this repo shows nothing dials `*.githubusercontent.com`, but the range
  also fronts `raw.githubusercontent.com` and Pages, there is no runtime evidence, and
  `pkg-containers.githubusercontent.com` (the only GHCR-related host in it) is a blob CDN that cannot
  pull without a ghcr.io token that the carved frontends no longer serve.
- **Decision taken:** carve only the nine Packages frontends (`/meta` `.packages`) out of the allow
  list; keep the `/22`. Reversible by adding the range to a generator exclusion list.
- **Alternative if the operator wants the `/22` removed too:** one generator exclusion plus the evidence
  of a runtime census (the carved-drop samples in `egress_blocked` events are the channel).

## DC-2: the `ghcr_blocked=0` Better Stack alert is split out of this PR

- **Operator direction:** add a regression alert that fires if the deny stops holding; do not bundle
  other ADR-096 work.
- **Finding:** ADR-096 (2026-09-30 amendment) says the `ghcr_blocked=0` regression check "is tracked
  with #9275", but the issue body does not contain it and it concerns the hosts-file deny, a different
  layer from the bridge gap this PR closes.
- **Decision taken:** this PR's alert covers the bridge deny it adds (Sentry, no SSH). The hosts-file
  deny's regression alert is filed as its own issue (Deferral 2) and the ADR text points at it.

## DC-3: running web-2 is not patched in place

- **Operator direction:** narrow/deny GHCR from bridge containers; ship as its own PR.
- **Finding:** `terraform_data.cron_egress_firewall` is pinned to web-1 (SSH provisioner) and
  `deploy_pipeline_fix_web2` carries no cron-egress artifact, so a running web-2 keeps the old allow
  list, resolver and no probe until its next replace. Baked scripts reach only fresh hosts.
- **Decision taken:** do not add a new in-place delivery route for web-2 in this PR (it is a different
  mechanism with its own parity tests and gates). Recorded as a named residual in the plan and ADR-096
  amendment, with a tracking issue (Deferral 4).
- **Alternative if the operator wants web-2 covered now:** extend `deploy_pipeline_fix_web2` with the
  firewall artifacts, or dispatch `web-host-replace` for web-2 after the merge (an operator-authorized
  production action per `hr-menu-option-ack-not-prod-write-auth`).
