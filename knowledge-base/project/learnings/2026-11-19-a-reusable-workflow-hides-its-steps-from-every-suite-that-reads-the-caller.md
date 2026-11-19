---
title: A reusable workflow hides its steps from every suite that reads the caller
date: 2026-11-19
category: integration-issues
module: ci-workflows, bastion-host-create, cloud-init, terraform
tags: [reusable-workflow, github-actions, test-suites, dpkg, cloud-init, terraform-target, tempfile-lint]
issue: 12866
pr: 12873
---

# Learning: a reusable workflow hides its steps from every suite that reads the caller

PR #12873 (ADR-327 step 2a, the dedicated bastion host) hit four mechanisms worth keeping. Each was
measured on this branch; the commit that measured it is named.

## 1. Moving a job body into a reusable workflow blinds every suite that reads `jobs.<id>.steps`

**Problem.** To fit the workflow byte gate, the `bastion_host_create` job body moved out of
`apply-web-platform-infra.yml` into `.github/workflows/bastion-host-create.yml`. The caller job
became `uses: ./.github/workflows/bastion-host-create.yml` with no `steps:` at all
(deaabc644f). `stock-preflight-coverage.test.ts` reads `jobs.<id>.steps` of the caller, found no
stock gate there, and went red on CI (`test-bun`, 62091eb206).

The dangerous version of this failure is the silent one. A suite that asserts "every step that does X
also does Y" passes on a job with zero steps. The red here happened only because this suite asserts
that the gate is present, not that it is absent.

**Solution.** The suite now resolves a local reusable caller to the called file's steps (18a7fc9f76).
Deleting the gate call in the reusable file turns the suite red (measured: 8 pass, 1 fail).

**What I checked for the other suites that parse the caller.** I checked three of them, not all.
- `terraform-target-parity.test.ts` strips `bastion_host_create` by name and pins its `-target`
  lines in a dedicated describe block.
- `web-host-escrow-preflight-census.test.ts` walks every file in `.github/workflows/`, so it sees the
  reusable body as a file of its own. It does not see the dispatch context, and the bastion is not
  `hcloud_server.web[...]`, so it is not in scope anyway.
- `stock-preflight-coverage.test.ts` is the one that missed it, now fixed.

**Key insight.** A suite that walks workflow files sees the moved body. A suite keyed on
`<caller file> + <job id> + steps` does not. Before you move a job body into a reusable workflow, run
`git grep -lE 'jobs|\.steps' -- plugins/soleur/test tests scripts | xargs grep -l '<caller>.yml'`.
For each hit, decide whether it reads by job id. If it does, it must follow `uses: ./.github/workflows/…`
into the called file, or it is now vacuous for that job.

## 2. Writing a dpkg conffile before `apt-get install` fails without a tty (rc=100)

**Problem.** The first cloud-init wrote the nftables baseline directly to `/etc/nftables.conf` in
`write_files`. Then it ran `apt-get install nftables`. Because the file already existed, dpkg found a
locally modified conffile and stopped at its interactive keep-or-replace prompt. Cloud-init has no
tty, so the install exited with 100. A docker reproduction showed rc=100 with the file written first
and rc=0 without it (56d41aed68).

**Solution.** Write the baseline to `/etc/soleur/bastion-nftables.conf`. Install it to
`/etc/nftables.conf` only after the package is installed. The lint now refuses a render that writes
`/etc/nftables.conf`. Two related traps showed up in the same pass:
- `cc_apt_configure` runs after `write_files` and regenerates `ubuntu.sources` unless
  `apt: {preserve_sources_list: true}` is set.
- A plain `apt-get update` exits 0 with no network. Use `--error-on=any`: under `docker --network none`
  it returns 100 where plain update returns 0.

**Key insight.** In cloud-init, `write_files` runs before `packages`/`runcmd`. Any path that a package
owns as a conffile must not be written until that package is installed.

## 3. Under `-target`, Terraform writes only the root outputs that depend on a targeted resource

**Problem.** The `bastion_private_ip` output came from a local value. The birth applies with `-target`
over `bastion-resources.txt`, and the output never reached state, so the downstream DNS and SSH config
chain had nothing to read (3eb127c22d).

**Solution.** The output now reads `hcloud_server_network.bastion.ip`, which is a targeted resource,
so the targeted apply writes it.

**Key insight.** If a later step reads a root output from a `-target` apply, the output must reference
an attribute of a targeted resource. A local or a variable alone is not enough.

## 4. The tempfile lint's high-water counts annotated sites, so stream through a dup'd fd instead

**Problem.** The same lesson as
`2026-11-08-a-sourced-gate-lib-cannot-own-a-trap-and-my-gate-list-skipped-the-ci-only-census-mode.md`
recurred twice on this branch. A `mktemp` in the sourced library `scripts/lib/bastion-boot-verify.sh`
pushed the class-b census (`lint-trap-tempfile-ownership.py --check-highwater`) over its high-water.
The first time, the pre-push ratchet lane caught it (107652ed0d). The second time, CI caught it on
737f366cd4 (fixed in 62091eb206). An `# lint-trap-ownership: ok` annotation clears the per-site rule
but still counts toward the census.

**Solution.** No tempfile. The reader's output is teed to a duplicated stdout fd, and the command
substitution exits with the reader's status. The sourced library owns no file and needs no trap.

**Key insight.** In a sourced library, the fix is to need no file, not to annotate one.

**Guardrail status.** Covered. `scripts/pre-push-ratchet-lane.sh` runs
`lint-trap-tempfile-ownership.py --check-highwater` as an unconditional fast member (5.6 s measured
today). This session did not measure why it did not stop the 737f366cd4 push. No cause is claimed.

## Session Errors

1. **737f366cd4 pushed with two CI reds** (`terraform fmt -check` on `bastion.tf`, and the class-b
   tempfile high-water). Recovery: 62091eb206. **Prevention:** both halves are already guarded
   locally. The lefthook pre-commit runs `terraform fmt {staged_files}`, and the pre-push lane runs
   the high-water (§4). This session did not measure why neither fired on that batch, so no new guard
   is proposed. If it recurs, record whether lefthook ran (`LEFTHOOK=0`, `--no-verify`, a missing
   `terraform` binary) before proposing one.
2. **62091eb206 red on `test-bun`** (stock-preflight coverage blind to the thin caller). Recovery:
   18a7fc9f76. **Prevention:** the plan sharp edge added with this learning (§1): grep the suites
   that read the caller before moving a job body into a reusable workflow.
3. **First cloud-init hit dpkg rc=100** (conffile written before install). Recovery: 56d41aed68.
   **Prevention:** §2 rule, now enforced by `bastion-lint.py`, which refuses a render that writes
   `/etc/nftables.conf`.
4. **`bastion_private_ip` never reached state under `-target`.** Recovery: 3eb127c22d.
   **Prevention:** §3 rule. Root outputs read after a targeted apply reference a targeted resource.
5. **Review seat `data-integrity-guardian` returned no report** (`Reviewed-Coverage: degraded 12/13`
   on 737f366cd4). Its scope was covered inline by the orchestrator. **Prevention:** none new. The
   degraded-coverage trailer is how this is already disclosed. One-off.
6. **In the compound session, a broad multi-file `grep` loop was refused by the `cc-plugin-privacy`
   hook.** Recovery: narrowed to three named files. **Prevention:** one-off. Read named files rather
   than a loop over a list that the hook flags.

## Tags

category: integration-issues
module: ci-workflows, cloud-init, terraform
