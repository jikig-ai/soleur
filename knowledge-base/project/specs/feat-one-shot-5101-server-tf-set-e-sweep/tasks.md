# Tasks — fix(infra): server.tf remote-exec `set -e` gating sweep (#5101)

Plan: `knowledge-base/project/plans/2026-06-10-fix-server-tf-remote-exec-set-e-sweep-plan.md`
Lane: cross-domain (fail-closed default — no spec.md `lane:` present)

## Phase 1 — Drift guard (RED)

- [ ] 1.1 Create `apps/web-platform/infra/server-tf-set-e.test.sh` per the plan's pseudo-shape (flag-based awk, comment-skipping, ≥ 13 block-count floor, `chmod +x`)
- [ ] 1.2 Run the guard against unedited server.tf — MUST fail with exactly 11 `FAIL block` lines and `blocks=13 ok=2` (plan-time live run confirmed this exact output; read every failure line)

## Phase 2 — server.tf sweep (GREEN)

- [ ] 2.1 Add `"set -e",` as the first inline element of the 11 audited blocks (pre-edit lines 97, 136, 175, 195, 252, 263, 444, 604, 615, 658, 686) — additive only, no other line changes, no new `|| true` guards (audit found zero needed)
- [ ] 2.2 `bash apps/web-platform/infra/server-tf-set-e.test.sh` → PASS (`blocks=13 ok=13`)
- [ ] 2.3 `grep -c '"set -e",' apps/web-platform/infra/server.tf` → 13
- [ ] 2.4 `bash scripts/followthroughs/server-tf-provisioner-set-e-sweep-5089.sh` → exit 0
- [ ] 2.5 `cd apps/web-platform/infra && terraform fmt -check && terraform init -backend=false && terraform validate` → exit 0
- [ ] 2.6 Diff hygiene: `git diff main -- apps/web-platform/infra/server.tf | grep -E '^-' | grep -v '^---'` is empty; added lines all match `^\+\s*"set -e",$`

## Phase 3 — CI wiring

- [ ] 3.1 Add named step to `.github/workflows/infra-validation.yml` `deploy-script-tests` job (after the cron-egress guard step): `Run server.tf remote-exec set -e drift-guard` → `bash apps/web-platform/infra/server-tf-set-e.test.sh`
- [ ] 3.2 `actionlint .github/workflows/infra-validation.yml` → exit 0

## Phase 4 — No-regression sweep

- [ ] 4.1 Sibling server.tf guards pass: `bwrap-userns-sysctl.test.sh`, `cron-egress-firewall.test.sh`, `infra-config-handler-bootstrap.test.sh`, `journald-config.test.sh`

## Ship

- [ ] 5.1 PR body: `Closes #5101`, `Ref #5046`, `Ref PR #5089`, `## Changelog`; label `semver:patch`
- [ ] 5.2 Post-merge (automated): `apply-web-platform-infra.yml` fires on merge; verify `gh run list --workflow=apply-web-platform-infra.yml --limit 1 --json conclusion,headSha` → success. On failure, triage per the plan's Hypotheses section (L3 handshake vs L7 newly-gated command)
