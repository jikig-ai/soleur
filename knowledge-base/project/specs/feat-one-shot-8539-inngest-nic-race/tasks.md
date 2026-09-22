---
title: "Tasks: fix inngest private-NIC boot race (#8539)"
plan: knowledge-base/project/plans/2026-09-22-fix-inngest-private-nic-boot-race-plan.md
branch: feat-one-shot-8539-inngest-nic-race
lane: cross-domain
---

# Tasks: converge the inngest host's late-attached private NIC before the zot pull

## 1. Setup

- 1.1 Re-read the plan's Guard Contract and write both mutation matrices into the test files as
  failing cases BEFORE touching `cloud-init-inngest.yml`.
- 1.2 Re-enumerate the explicit inngest render maps: `git grep -l 'web_host_private_ips *=' -- apps`
  (expected: `inngest-host.tf`, `inngest-userdata-budget.sh`, `inngest-boot-emitter.test.sh`).
- 1.3 Record the baseline: `bash apps/web-platform/infra/inngest-userdata-budget.sh` (stored 14,964 B).
- 1.4 Check whether the Hetzner `ubuntu-24.04` image ships `hc-utils`. Use its manifest or docs;
  no host access. Note the answer in the PR body.

## 2. Core implementation

- 2.1 Template var: add `inngest_private_ip = local.inngest_private_ip` to the inngest templatefile
  map in `inngest-host.tf`. Add the literal `"10.0.1.40"` to the budget script's map and the
  boot-emitter test's map.
- 2.2 Replace the code-line `10.0.1.40` in the `net-health` diag (`cloud-init-inngest.yml:~1673`)
  with `${inngest_private_ip}`, keeping `%%{http_code}` intact.
- 2.3 Add the `write_files` entry `/etc/systemd/network/99-soleur-private-fallback.network`
  (root:root 0644) with exactly the plan's Phase 2 content. Put rationale in YAML comments above
  the entry, never inside `content:`.
- 2.4 Add the `write_files` entry `/usr/local/bin/soleur-inngest-nic-wait` (0755):
  - brace-free POSIX sh, no `%{`, no `# `-prefixed code lines;
  - an empty-argument guard;
  - probe resolution for `ip`/`grep`;
  - a 75×2 s POSIX-counter poll with `grep -qwF`;
  - three arms (`private_nic_ok` / `private_nic_timeout` / `private_nic_probe_fault`);
  - one detail string (`boot=` first, `.`-joined, ≤120 chars, charset `A-Za-z0-9=.:_-`) sent to
    both `inngest-boot-phone-home.sh` and `soleur-boot-emit`;
  - `by=<Network File basename>`, warning level when it is the fallback's.
- 2.5 runcmd: add `- networkctl reload || true` immediately after the first runcmd item (the
  token staging).
- 2.6 runcmd: add `- /usr/local/bin/soleur-inngest-nic-wait ${inngest_private_ip} || true` as the
  item immediately preceding the zot-login item.
- 2.7 `network.tf:9-13`: comment-only correction. The inline `network {}` block is in-place
  updatable at v1.63.0, and it is still a post-boot hot attach whenever public net is enabled.

## 3. Testing

- 3.1 Create `apps/web-platform/infra/inngest-nic-wait.test.sh`:
  - render via terraform `templatefile` + `local.inngest_rationale_strip`;
  - extract the helper and the `.network` file from the rendered write_files;
  - run Test Scenarios 1-11 (incl. 3b/3c) under a stub PATH;
  - run Guard 2's mutation rows plus the harness rows;
  - run `shellcheck -s sh` on the helper.
- 3.2 Extend `cloud-init-inngest-bootstrap.test.sh` with Guard 1's asserts. Order, presence and
  derived-set rows run on the render. Rows 5 and 10 run on the raw source. Add the write_files
  mode/owner asserts.
- 3.3 Extend `cloud-init-inngest-zot-pull-mutation.test.sh` with Guard 1's mutation rows and the
  three must-PASS inputs (incl. the :1141 / :1202 config writes).
- 3.4 Register the new suite in `.github/workflows/infra-validation.yml`, then run
  `bash scripts/lint-orphan-test-suites.sh`.
- 3.5 Re-run `inngest-userdata-budget.sh` (stored must stay < 32,768 B) and the size test.
- 3.6 Run AC1, AC7 and AC8 exactly as written in the plan (the `wc -l` forms).

## 4. Architecture record and docs

- 4.1 Add the ADR-115 amendment (2026-09-22, #8539), about 15-20 lines, linking the plan. Add the
  three §Alternatives rows and `8539` in `amended_by`. Keep the reboot grant registry-only.
- 4.2 In `model.c4`, edit the `inngest -> sentry` edge description to add the `private_nic_*`
  family. Run the C4 syntax/render tests and `bash plugins/soleur/test/c4-count-parity.test.sh`.
- 4.3 In `runbooks/inngest-server.md`, add a "Reading the private-NIC boot event" subsection. Its
  query must equal the plan's `discoverability_test.command`.

## 5. Ship notes

- 5.1 The PR body's first line: merging does not change production (the merge apply's `-target`
  excludes `hcloud_server.*`). Delivery is the post-merge `inngest-host-replace` plus the
  human-approved `op=resume`, owned by the orchestrator.
- 5.2 Issue references: `Closes #8539`; `Ref #6438`, `Ref #6500`, `Ref #6122`, `Ref #8562`. No
  closing keyword in any form next to 6500, 6122 or 6438.
- 5.3 Render `specs/feat-one-shot-8539-inngest-nic-race/decision-challenges.md` (taste findings
  T1-T4) into the PR body.
