---
title: "fix: git-data remote URL path the transport wrapper rejects (#8211)"
date: 2026-10-27
slug: git-data-remote-url-wrapper-path
branch: feat-one-shot-8211-git-data-remote-url-path
issue: 8211
type: fix
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix: git-data remote URL path the transport wrapper rejects (#8211)

Spec lacks valid lane: no `spec.md` exists for this branch, so `lane:` defaulted to cross-domain (fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-27
**Sections enhanced:** gate verification (4.6-4.13), negative-claim sweep, harness realism, parity assembly
**Research agents used:** `soleur:engineering:cto` x2 (rulings), learnings-researcher, plan-review panel (DHH, Kieran, code-simplicity); deepen pass ran the gates and a verify-the-claims sweep directly (the change is one constant plus tests, so the 40-agent fan-out would add cost without recall)

### Key Improvements
1. Corrected a plan-review-adopted claim that the ownership suite pins the `REPO_ROOT` defaults across wrapper, provision and remove. It pins only `MOUNT_ROOT` / `HOOKS_DIR` (wrapper header line about "both literals"), so R-PARITY extracts all three `REPO_ROOT` defaults itself.
2. Confirmed the production push shape needs `receive.advertisePushOptions`: the bootstrap sets it with `git config --system` (`git-data-bootstrap.sh`), so the vitest fixture must set it per repo or `--push-option` fails.
3. All mechanical gates pass: User-Brand Impact present with a valid threshold; no PAT-shaped tokens; no UI surface (no `.pen` needed); `lint-guard-contract.py` green (1 guard entry); exactly one unfenced `## Scope Check`; the Observability probe is an allowlisted `rg` that finishes instantly and prints the expected literal once the constant is flipped.

### New Considerations Discovered
- The git-data host's log redaction (`cloud-init-git-data.yml`, the sed rule on `/mnt/git-data/repositories/...`) already matches the NEW path form and not the old one, so host-side log lines carrying the new path are redacted to `REDACTED` automatically.
- `cron-egress-nftables.sh` quotes the old URL in a comment; editing it re-runs the web hosts' `cron_egress_firewall` provisioner (its `config_hash` hashes the file), so leave it (see Sharp Edges).
- The runbook's verdict-word census is the `RB` section of `git-data-cutover-access.test.sh` (not a suite named for a case); re-run the whole suite after the runbook edit.

## Overview

The web app builds the git-data remote as `ssh://git@${host}/repositories/${id}.git`. Git sends that path to the host unchanged and absolute, so the transport forced-command wrapper (`apps/web-platform/infra/git-data-transport-wrapper.sh`) runs `readlink -f '/repositories/<id>.git'`, gets nothing because `/repositories` does not exist at the host root, and refuses with `git-data transport: repo path does not resolve`. Both the session-start fetch and the session-end `git push --force git-data refs/heads/*:refs/soleur/worktrees/<id>/heads/*` failed on web-1 at 09:01Z on 2026-10-27, so nothing replicated, and rehearsal R3 failed. Provisioning still worked (it takes a bare workspace id through a different forced command), so the bare repo directory existed while no ref ever landed, and every existing check read that as success.

This plan flips the app-side path prefix to the wrapper's own root, adds tests that run the real wrapper with the exact command real git emits for `gitDataRemoteUrl(id)`, and tightens runbook steps R3 and R6 so a bare `<id>.git` never again counts as proof of replication. The owner lifted the merge-to-main ban for this one PR (flag `GIT_DATA_STORE_ENABLED` is on in prd, new sessions are paused). The PR body says `Ref #8211`, not `Closes`.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (measured 2026-10-27) | Plan response |
|---|---|---|
| Brief: the wrapper's `readlink -f` "gets empty because /repositories does not exist" | Confirmed by running the REAL wrapper with seams: old-form push is refused, `/mnt/git-data/repositories/<id>.git` push lands `refs/soleur/worktrees/<id>/heads/main`, fetch round-trips | Prototype recorded below; the same run becomes the permanent test |
| Code comment (`git-data-replication.ts` lines 42-51) and `git-data-bootstrap.sh` step 4b: a URL path of `/repositories/<id>.git` "resolves relative to /home/git" | Only true for the scp-style relative form (`git@host:repositories/<id>.git` emits `'repositories/<id>.git'`). An `ssh://host/repositories/...` URL emits the ABSOLUTE `'/repositories/<id>.git'` (stub-ssh capture); `ssh://host/~/...` emits `'~/...'`, which the wrapper never expands | Rewrite the code comment. The bootstrap comment cannot be edited (user_data), so it is listed as a parked follow-up |
| Brief: the cutover probe (`git-data-cutover-access.test.sh` about line 2947) "only uses full /mnt/git-data paths" | True, and it is the same absolute form the fix adopts: `git-data-container-probe.sh` line 133 defaults `GDCP_REPO_ROOT` to `/mnt/git-data/repositories` and dials `git-upload-pack '<root>/cutover-container-probe-absent.git'`. So the probe never diverged from the wrapper; it diverged from the APP | The probe case to add is a parity case (the probe's dialed command equals what git emits for the app's URL form), not a probe rewrite |
| Brief: "check provisionGitDataRepo/ensureGitDataRemote and the erasure remove path use the same form" | `provisionGitDataRepo` and `removeGitDataRepo` pass a bare workspace id as `SSH_ORIGINAL_COMMAND` to their own forced commands (`git-data-provision.sh`, `git-data-remove.sh`); they build no URL, and the scripts hardcode `/mnt/git-data/repositories`. Only `ensureGitDataRemote` (via `gitDataRemoteUrl`) and the fetch in `git-data-client.ts` (`const remoteUrl = gitDataRemoteUrl(workspaceId)`) use the URL | No edit to provision or remove. `ensureGitDataRemote` inherits the fix; the fetch inherits it; both are pinned by tests |
| Brief: `infra/git-data-bootstrap.sh` line 226 creates the symlink | Confirmed (`ln -sfn "$REPO_ROOT" "$GIT_HOME/repositories"`), and the bootstrap, wrapper and cloud-init are all embedded in the host's `user_data` render (`git-data.tf`, `module.git_data_userdata`) | Hard constraint: none of them is edited. After the fix the symlink is off the app's path |
| Paths "under apps/web-platform/ for server/ and infra/" | Confirmed: `apps/web-platform/server/git-data-replication.ts`, `apps/web-platform/infra/*` | Used throughout |

## Research Insights

### Premise Validation (Phase 0.6)

- #8211 is OPEN ("git-data cutover: rebuild the real modes ..."); the brief's ADR-239 reference exists (`knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md`). #11086 (agent-auth-failure) is out of scope and is neither fixed nor closed here.
- Cited symbols verified on this branch: `GIT_DATA_REPO_PATH_PREFIX` (`git-data-replication.ts:51`), `gitDataRemoteUrl` (`:333`, template `:336`), `ensureGitDataRemote` (`:589`), wrapper `readlink -f` (`git-data-transport-wrapper.sh:100-113`), bootstrap symlink (`git-data-bootstrap.sh:226`), probe default (`git-data-container-probe.sh:133`).
- ADR corpus grep (mechanism "URL form / symlink / relative path"): no ADR records the app URL form as a decision; ADR-068 only records the provisioning wrapper's absolute build of `/mnt/git-data/repositories/<workspace_id>.git`. The wrong claim lives in two code comments, not in a decision, so no ADR amendment is owed (see the architecture gate below).
- Collision pre-check: open PRs naming #8211 are #11285 (this branch's own draft), #10901 and #10905 (the erasure ledger work). #10905 edits the same runbook file (`git-data-luks-cutover-5274.md`); the R3/R6 hunks here are in a different region, so a rebase conflict is possible but small. Foreign `test-all.sh` processes belong to unrelated worktrees.

### Property List and Cut List (Phase 0.6b)

Properties the fix must buy:

1. A fetch and a push issued from the app for workspace `<id>` reach the same `$GIT_DIR` the provision call created and the pre-receive fence keys on.
2. The path the app emits is accepted by the wrapper under its current rules, without relying on the sshd working directory or the `/home/git/repositories` symlink.
3. Any future drift between the app's path and the wrapper's accepted root turns a test red BEFORE a rehearsal, not during one.
4. A rehearsal cannot read "the repo directory exists" as "replication worked".

Mechanisms the brief proposes, cut or kept:

| Mechanism | Property | What already covers it | Verdict |
|---|---|---|---|
| Change the app path constant | 1, 2 | nothing; this is the defect | keep |
| Test feeding git's emitted command into the wrapper test | 3 | the wrapper suite only feeds hand-written absolute paths | keep |
| Cutover-probe case in the URL form | 3 | `git-data-container-probe.sh` already dials the absolute form but nothing ties it to the app | keep, as a parity case |
| Push-lands-refs check | 1, 4 | `mode_probe` pushes by local path as the `git` user (bypasses the wrapper and ssh) | keep; this is the only test that crosses git -> ssh -> wrapper -> receive-pack |
| Runbook R3/R6 wording | 4 | none | keep, runbook text only |
| Edit the wrapper or cloud-init | 2 | n/a | cut: forces host replacement; the brief forbids it |
| New env override for the prefix | 2 | the host path is fixed in immutable cloud-init and the wrapper ignores client env | cut (CTO ruling) |

### Local research, institutional learnings

- `knowledge-base/project/learnings/2026-07-27-my-battery-was-green-because-it-only-tested-the-two-endpoints-not-the-wire.md`: each endpoint was tested, the connection between them never was. This defect is exactly that: wrapper tests used hand-written absolute paths, app tests pinned a string, and nothing ran git's real emission through the real wrapper.
- `knowledge-base/project/learnings/2026-03-20-ssh-forced-command-cloud-init-parity-gaps.md`: under a forced command `SSH_ORIGINAL_COMMAND` is the whole client request; mocked collaborators hid the real path.
- `knowledge-base/project/learnings/2026-09-21-the-fence-probe-read-the-config-the-bootstrap-writes-not-the-path-a-push-takes.md` (sharp edge): a guard must read what the PROCESS performing the behavior reads. The e2e test therefore runs the real wrapper under the real git client, not a grep of either.
- `knowledge-base/project/learnings/2026-07-24-guest-luks-store-must-gate-consumer-on-mount-and-guard-suite-must-pin-fail-loud-semantics.md`: mount-stub tests must assert the `exit 1` halt; the wrapper suite's `findmnt` UUID stub pattern is reused as is.
- Learnings search was partial (the first researcher hit a temp-volume quota error); the three hits above were read directly.

### Prototype (run 2026-10-27, real git, stub ssh, REAL wrapper with seams)

Emitted commands: `ssh://git@H/repositories/<id>.git` -> `git-receive-pack '/repositories/<id>.git'` (REFUSED); `ssh://git@H/mnt/git-data/repositories/<id>.git` -> `git-receive-pack '/mnt/git-data/repositories/<id>.git'` (push landed `refs/soleur/worktrees/wt1/heads/main`) and `git-upload-pack '/mnt/git-data/repositories/<id>.git'` (fetch landed `refs/remotes/git-data/main`, same sha); scp-style -> `'repositories/<id>.git'`; `ssh://H/~/...` -> `'~/repositories/<id>.git'`. The shim maps the literal `/mnt/git-data/repositories` onto a fixture root because CI has no `/mnt/git-data`; the parity pin (below) is what ties that literal to the wrapper's default.

## Problem Statement

`gitDataRemoteUrl` (the one builder behind the session-end push remote and the session-start fetch) emits a path the wrapper cannot resolve. Nothing detected it before the rehearsal because (a) the wrapper suite only tried paths under its own fixture root, (b) the app suites pinned the URL string without running git, (c) the container probe dials the absolute form with its own constant, and (d) the rehearsal's R3/R6 confirm lines accepted `<id>.git` existing, which provisioning alone produces.

## Proposed Solution

CTO ruling, 2026-10-27 (full text in `decision-challenges.md`): form A. `GIT_DATA_REPO_PATH_PREFIX = "/mnt/git-data/repositories"`, so `gitDataRemoteUrl(id)` returns `ssh://git@${host}/mnt/git-data/repositories/${id}.git`.

Why A: it passes the wrapper's `"$root_real"/*.git` check on its own, with no dependence on the sshd cwd or the bootstrap symlink; it keeps the `ssh://` scheme (every redaction, pinning and argv test already assumes it); it matches the form the container probe, `git-data-provision.sh` and `git-data-remove.sh` already use. B (scp-style relative) rests on two facts nobody has verified on prod. C (`~/`) cannot work (no tilde expansion in the wrapper).

Consequences handled: existing clones holding a stale `git-data` remote are re-pointed by `ensureGitDataRemote`'s `set-url` branch on every push (the fetch builds its URL from the workspace id and never reads the stored remote); no env override (the host path is fixed in cloud-init and a client cannot reach the wrapper's `GIT_DATA_REPO_ROOT`).

## Implementation Phases

Order follows `cq-write-failing-tests-before` and the contract-before-consumer rule: failing tests, then the one constant, then comments, then the suites that consume the contract, then docs.

### Phase 1 — RED tests (fail on the current constant)

1.1 `apps/web-platform/test/git-data-remote-url-wrapper.test.ts` (new): the app-side end-to-end. Mocks only what importing `server/git-data-replication.ts` needs (the same three `vi.mock` blocks as `git-data-replication.test.ts`: the git-auth module, a partial observability mock, the tenant client) and keeps `node:child_process` REAL. Hermetic fixture in a temp dir: `store/repositories/<id>.git` bare repo with HEAD -> `refs/heads/main` and `receive.advertisePushOptions=true` (production gets it from the bootstrap's system config; without it `--push-option` fails with "receiving end does not support push options"); `GIT_DATA_MOUNT_ROOT` is the real `stat -c %m` of the store dir and `GIT_DATA_STORE_DEVICE` the real `findmnt -n -o SOURCE --mountpoint <that mount>`; a `findmnt` UUID stub on PATH answers only the UUID query (tmpfs has no filesystem UUID) and a marker file holds that UUID; if `findmnt --mountpoint` prints nothing the test fails loud. An executable shim NAMED `ssh` (so git treats it as plain ssh and sends no `-G` capability probe; also ignore a leading `-G` defensively) is placed first on PATH and selected by `GIT_SSH_COMMAND`; it appends its LAST argv element (the remote command git emitted) to a log, rewrites the literal `/mnt/git-data/repositories` to the fixture root, and execs the REAL `infra/git-data-transport-wrapper.sh` under `env -i` with an explicit `PATH` and `HOME` plus the seam env (`GIT_DATA_REPO_ROOT`, `GIT_DATA_MOUNT_ROOT`, `GIT_DATA_HOOKS_DIR` empty dir, `GIT_DATA_STORE_DEVICE`, `GIT_DATA_STORE_VERIFIED`). Rows:
   - R-URL: `gitDataRemoteUrl(id)` equals `ssh://git@10.0.1.20/mnt/git-data/repositories/<id>.git` for a UUID id and for a `ws-uuid-123` id.
   - R-PUSH: run `ensureGitDataRemote(clone, id)`, then the production push shape by remote NAME: `git push --force git-data refs/heads/*:refs/soleur/worktrees/<wt>/heads/* refs/tags/*:refs/soleur/worktrees/<wt>/tags/* --push-option=lease-gen=1 --push-option=worktree-id=<wt>`. Exit 0; the log holds the `git-receive-pack '/mnt/git-data/repositories/<id>.git'` line (asserted by suffix/grep on the verb lines, not whole-file equality); the bare repo lists `refs/soleur/worktrees/<wt>/heads/main` and `.../tags/<tag>` with the pushed shas and nothing outside that namespace.
   - R-FETCH: real `git fetch <gitDataRemoteUrl(id)> +refs/soleur/worktrees/<wt>/heads/*:refs/remotes/git-data/*` exits 0, the log holds `git-upload-pack '/mnt/git-data/repositories/<id>.git'`, and the clone holds `refs/remotes/git-data/main` at the same sha.
   - R-STALE: a clone whose `git-data` remote holds the old `ssh://.../repositories/<id>.git` is re-pointed to the new URL by `ensureGitDataRemote` (`git remote get-url git-data`).
   - R-PARITY: the path prefix of `gitDataRemoteUrl` equals, byte for byte, the default parsed from each of `infra/git-data-transport-wrapper.sh`, `infra/git-data-provision.sh` and `infra/git-data-remove.sh` (`REPO_ROOT="${GIT_DATA_REPO_ROOT:-...}"` in all three), the composition of `OLD_ROOT` + `REPO_SUBDIR` in `infra/git-data-cutover.sh`, and the `/mnt/git-data` mount literal in `infra/cloud-init-git-data.yml` joined with `/repositories`. Each extraction asserts exactly one match (zero fails). (The ownership suite pins the `MOUNT_ROOT` / `HOOKS_DIR` defaults across the wrappers, not the `REPO_ROOT` default, so provision and remove are extracted here, not assumed. The container probe's default is covered by CPU1.)
   Expected on the old constant: R-URL, R-PUSH, R-FETCH, R-PARITY RED. The old-form refusal (the incident's exact message) is asserted once, in 1.3 (U3).
1.2 Update the pinned URL expectation in `apps/web-platform/test/git-data-replication.test.ts` (the `composes an ssh:// URL under the reconciled /repositories path` test; retitle) and `apps/web-platform/test/git-data-client.test.ts` (the `expect(argv).toContain(` line naming `ssh://git@10.0.1.20/repositories/`).
1.3 `apps/web-platform/infra/git-data-transport-wrapper.test.sh` (the owner's "wrapper test"): new section `U` before the mutation meta-check, using the suite's existing seams (`run_wrap`, `run_wrap_out`, `SEAMS`, `fixture_bare`). The prefix is NOT a typed literal: the section extracts the string assigned to `GIT_DATA_REPO_PATH_PREFIX` from `apps/web-platform/server/git-data-replication.ts` (exactly one match) so the test is tied to the app. A recording shim named `ssh` captures what real git emits for `ssh://git@10.0.1.20<prefix>/<id>.git` for fetch and push. Rows: U1 the emitted upload-pack command is accepted (dry-run; canonicalized exec names `<root>/<id>.git`); U2 the emitted receive-pack command is accepted; U3 the OLD emitted command `git-receive-pack '/repositories/<id>.git'` is refused with `repo path does not resolve` (reproduces the incident; precondition `/repositories` absent); U4 non-dry-run round trip through the real `git receive-pack` (empty hooks dir, `receive.advertisePushOptions` set) lands `refs/soleur/worktrees/<id>/heads/main` and no `refs/heads/*`. The old-form command is also added to the existing always-exit-0 stub loop in the mutation meta-check (one input, so the refusal assertion is shown able to fail). Raise the minimum-cardinality floor (currently 53 in the footer guard) by the new assertion count.
1.4 `apps/web-platform/infra/git-data-cutover-access.test.sh` (the owner's "cutover probe case"): one new row `CPU1` after CPX1 reusing the `inner-ssh` capture already in `$CP_LOGF`: the remote command the container probe dials equals, byte for byte, the command real git emits (recording shim) for `ssh://git@10.0.1.20<prefix>/cutover-container-probe-absent.git`, where `<prefix>` is extracted from `server/git-data-replication.ts` as in 1.3. This ties the probe's form to the app constant (CPX1 alone pins the probe to its own literal). Raise any floor in that suite.

### Phase 2 — the one-constant fix

2.1 `apps/web-platform/server/git-data-replication.ts`: `const GIT_DATA_REPO_PATH_PREFIX = "/mnt/git-data/repositories";` The template in `gitDataRemoteUrl` is unchanged (`${GIT_DATA_REPO_PATH_PREFIX}/${workspaceId}.git`). Exported `gitDataRemoteUrl` signature unchanged.
2.2 Rewrite the comment block above the constant (the one naming the `/home/git/repositories` symlink) and the `gitDataRemoteUrl` doc comment: the git client sends an ABSOLUTE path for `ssh://` URLs; the wrapper canonicalizes it with `readlink -f` and requires a direct `<root>/*.git` child of `/mnt/git-data/repositories`; the host's `/home/git/repositories` symlink serves only scp-style relative paths and is not on this path; cite the defect and #8211. No behavior change beyond the constant.

### Phase 3 — green and sweep

3.1 Run, in this order: the new vitest file, `git-data-replication.test.ts`, `git-data-client.test.ts`, `git-auth.test.ts`, `git-data-ssh-connect-bound.test.ts`; then `bash apps/web-platform/infra/git-data-transport-wrapper.test.sh`, `bash apps/web-platform/infra/git-data-cutover-access.test.sh`, `bash apps/web-platform/infra/git-data-ownership.test.sh`, and `bash plugins/soleur/test/c4-count-parity.test.sh` (unchanged: no C4 edit). `git-data-container-probe.sh` has no suite of its own (the cutover-access suite is its suite) and is never executed directly.
3.2 Residual sweep: `rg -n 'ssh://[^/ ]+/repositories/' apps/web-platform/server apps/web-platform/test/git-data-replication.test.ts apps/web-platform/test/git-data-client.test.ts apps/web-platform/test/git-data-remote-url-wrapper.test.ts` returns nothing (the regex needs the path to START at `/repositories`, so the new `/mnt/git-data/repositories` form does not match). The opaque argv samples in `git-auth.test.ts` and `git-data-ssh-connect-bound.test.ts` assert nothing about the path and are left alone.
3.3 Not edited, with the reason (verify with `git diff origin/main --stat` at the end): `git-data-transport-wrapper.sh`, `git-data-bootstrap.sh`, `cloud-init-git-data.yml`, `git-data.tf` (user_data / host replacement); `cron-egress-nftables.sh` carries the same stale `.../repositories/<id>.git` in a comment but editing it changes the `config_hash` of the web hosts' `cron_egress_firewall` provisioner (`server.tf`), which re-runs it on live web hosts; `AGENTS.rules.md`.

### Phase 4 — runbook R3 and R6

`knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`, run-sheet rows R3 and R6 (the table rows beginning `| R3 |` and `| R6 |`), per the CTO wording rule (decision-challenges row 2). Text only:
4.1 R3 "Checks": R3 passes only on positive refs evidence, a ref name under `refs/soleur/worktrees/<worktreeId>/` of `<syntheticId>.git` and its sha, attested by the owner and read by a route that is not SSH. `<id>.git` existing, a `store_not_empty` verdict and a `provisionGitDataRepo` success never count (provisioning succeeded in the failed 2026-10-27 rehearsal while every push was refused). Zero Sentry events `feature:worktree_lease op:git_data_replication_push` and `op:git-data-overlay` in the window is a required companion and alone yields "R3 INCONCLUSIVE", which blocks R6 and the deletion. State plainly that no documented no-SSH route to read those refs exists yet, so R3 cannot pass until one is supplied.
4.2 R6 "Checks" and failure column: the proof before the deletion reading `store_not_empty` is necessary and NOT sufficient; R6 requires the refs evidence of R3, and a `store_not_empty` with no refs evidence reads "provisioned, not replicated". The R9 evidence block is not edited.
4.3 Keep the runbook's own constraints: no SSH command, no secret value, query forms only from channels the runbook already uses. After the edit re-run the runbook word-census case (`case RB` in `git-data-cutover-access.test.sh`), since a verdict-shaped word would trip it.

### Phase 5 — hand-off artifacts (after merge-ready, not product code)

5.1 PR body: starts `Ref #8211` (never `Closes`), links `decision-challenges.md` rows, states that #11086 is untouched.
5.2 One comment on #8211 (no new issues) parking the three follow-ups from `decision-challenges.md` (positive no-SSH refs read for R3/R6; the container probe's wide `remote: git-data transport:` acceptance; the stale bootstrap step-4b comment to fold into the next deliberate host replace).
5.3 Commits via `git commit -F <file>`, author Jean Deruelle / jean.deruelle@jikigai.com, `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` as the final trailer block; explicit pathspecs only, never `git add -A`, never `git stash`.

## Files to Edit

- `apps/web-platform/server/git-data-replication.ts` (the `GIT_DATA_REPO_PATH_PREFIX` constant and the two comments naming the `/home/git` symlink and the `ssh://` URL)
- `apps/web-platform/test/git-data-replication.test.ts` (the URL-composition test: expectation and title)
- `apps/web-platform/test/git-data-client.test.ts` (the fetch-argv URL expectation)
- `apps/web-platform/infra/git-data-transport-wrapper.test.sh` (section U, one stub-loop input, floor)
- `apps/web-platform/infra/git-data-cutover-access.test.sh` (CPU1, floor)
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` (R3 and R6 row wording)

## Files to Create

- `apps/web-platform/test/git-data-remote-url-wrapper.test.ts`
- `knowledge-base/project/specs/feat-one-shot-8211-git-data-remote-url-path/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-8211-git-data-remote-url-path/decision-challenges.md` (written during planning)

## Open Code-Review Overlap

None. Queried open `code-review` issues (200 listed) for every path in Files to Edit plus `git-data-container-probe.sh`; no body names any of them.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Change the app-side URL path for BOTH fetch and push (gitDataRemoteUrl) to a form the wrapper accepts under its CURRENT rules" | Phase 2.1, 2.2 | mapped |
| 2 | "pick one and verify against the wrapper by actually running the wrapper logic with a stub" | Proposed Solution (CTO ruling A), Prototype, Phase 1.1 / 1.3 (real wrapper under real git) | mapped |
| 3 | "check provisionGitDataRepo/ensureGitDataRemote and the erasure remove path and the cutover probe use the same form" | Research Reconciliation row 4 (provision/remove take a bare id), Phase 1.1 R-STALE and R-PARITY, Phase 1.4 CPU1 | mapped |
| 4 | "Do NOT edit the wrapper or cloud-init user_data" | Phase 3.3 | mapped |
| 5 | "Add a test that feeds the exact SSH command git emits for gitDataRemoteUrl(id) into the wrapper test" | Phase 1.1 R-PUSH / R-FETCH, Phase 1.3 U1-U2 | mapped |
| 6 | "plus a cutover-probe case in that URL form" | Phase 1.4 CPU1 | mapped |
| 7 | "plus a check that a push in this form lands refs under refs/soleur/worktrees/<id>/" | Phase 1.1 R-PUSH, Phase 1.3 U4 | mapped |
| 8 | "Update runbook ... R3 and R6 confirm line to require refs under refs/soleur/worktrees/<id>/" | Phase 4 | mapped |
| 9 | "Do not edit AGENTS.rules.md" | Phase 3.3 | mapped |
| 10 | "do not fix or close it; park any follow-up as a comment on #8211 (no new issues)" | Phase 5.2; #11086 untouched | mapped |
| 11 | "PR body: \"Ref #8211\" (not Closes)" | Phase 5.1 | mapped |
| 12 | "commits via git commit -F ... trailer ... as the final block. Explicit pathspecs, never git add -A, never git stash" | Phase 5.3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Constant flip + comments | "Change the app-side URL path for BOTH fetch and push" | asked |
| New vitest e2e file | "feeds the exact SSH command git emits for gitDataRemoteUrl(id) into the wrapper test" | asked |
| Parity pin: app constant vs wrapper / provision / remove defaults, cutover.sh composition, cloud-init mount | "check ... the erasure remove path and the cutover probe use the same form" | asked (the ownership suite pins only the MOUNT_ROOT / HOOKS_DIR defaults, so provision and remove are extracted) |
| R-STALE (existing clones' remote re-pointed) | "check provisionGitDataRepo/ensureGitDataRemote" | asked |
| U3 old-form refusal row and the stub-loop input | "Wrapper tests ... only use full /mnt/git-data/... paths, so nothing caught it" | asked (the control is what makes the new rows able to fail) |
| Runbook R3 and R6 wording (rule folded into R3) | "(not just <id>.git existing)" | asked |
| #8211 comment parking follow-ups | "park any follow-up as a comment on #8211" | asked |

### Split Assessment

- Subsystems touched: 3 (`apps/web-platform/server`, `apps/web-platform/test`, `apps/web-platform/infra` tests) plus runbook docs
- Planned files: 6 edited, 1 created (plus specs) | Estimated changed lines: about 300 (mostly new test rows; trimmed after plan review)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (under every threshold; the runbook and tests are the proof of the one-line fix)

## User-Brand Impact

- **If this lands broken, the user experiences:** session-end work that is not durably replicated to the shared git-data store while the app reports no failure to them; their latest unpushed commits live only on the web host until the next successful session end (GitHub `origin` stays canonical and rehydration intact, ADR-068 section 1). Today the exposure is bounded because new agent sessions are paused.
- **If this leaks, the user's workflow data is exposed via:** no new vector. The URL carries only the already-validated workspace id (`WORKSPACE_ID_RE`), authorization (`authorizeGitDataAccess`) and the wrapper's canonicalize-under-root, freeze and mount checks are unchanged, and the wrapper still rejects dot paths, symlinks and nested paths (rows T4-T6).
- **Brand-survival threshold:** `aggregate pattern`
- **After this merges (review, user-impact seat):** the replication write path and the session-start `reset --hard` overlay can run against real repositories for the first time. Two latent behaviours become reachable, and neither is mitigated by this diff: the overlay resets a fresh clone to the store tip with no ancestry check against the just-cloned GitHub tip, so a replica older than GitHub sets a fresh clone back (nothing is lost, the commits stay on origin); and a stale clone force-pushes over a newer store tip because the fence orders by lease generation, not content. Both are parked on #8211. Real-user sessions must not resume (the new-session pause stays on) before REFS-CONFIRMED and the R6/R7 erasure proof; the runbook R3 row now says so.
- **Threshold decision (challengeable):** not `single-user incident` because the replica is an overlay with GitHub as the canonical copy and the flag is on with new sessions paused, so no single user's data is at stake before the next rehearsal; it would become `single-user incident` if sessions resume with the defect unfixed, which is the argument for merging promptly.

## Observability

```yaml
liveness_signal:
  what: Sentry events with feature worktree_lease and op git_data_replication_push (push or provision failure) and op git-data-overlay (fetch failure); healthy is none after the next session end
  cadence: per session end and per session start that grafts a clone
  alert_target: Sentry issue alert for the git-data replication push path and the git-data-host-key-pin-fault email for pin faults
  configured_in: apps/web-platform/server/git-data-replication.ts (reportSilentFallback in the replicateToGitData catch) and apps/web-platform/server/git-data-client.ts
error_reporting:
  destination: Sentry via reportSilentFallback (pin faults via reportGitDataPinFault), feature worktree_lease
  fail_loud: replicateToGitData re-throws after mirroring to Sentry; the wrapper's refusal text (remote: git-data transport: ...) arrives in the event detail
failure_modes:
  - mode: wrapper refuses the emitted path (this defect, or any future prefix drift)
    detection: the e2e vitest rows R-PUSH / R-FETCH and wrapper suite U1-U4 fail in CI before merge; in production a Sentry git_data_replication_push event carries the refusal text
    alert_route: CI red on the PR; Sentry issue alert in production
  - mode: push reports success but no ref lands (provision-only state)
    detection: no no-SSH positive read exists today; the runbook rule makes R3/R6 refuse to pass on directory existence, and the follow-up for a positive read is parked on #8211
    alert_route: rehearsal R3 reads INCONCLUSIVE and blocks R6 and deletion
  - mode: app prefix drifts from the host mount path
    detection: R-PARITY compares the app prefix to the wrapper, provision, remove, container probe, cutover.sh and cloud-init literals
    alert_route: CI red on the PR that changes either side
logs:
  where: Sentry for failures; the success line git-data replication push complete is info level and is not shipped to Better Stack
  retention: Sentry project retention; app log per the existing Vector pipeline
discoverability_test:
  command: rg -n "^const GIT_DATA_REPO_PATH_PREFIX" apps/web-platform/server/git-data-replication.ts
  expected_output: /mnt/git-data/repositories
```

## Guard Contract

### Guard 1 — remote-URL path parity and wrapper round trip

**Property.** The path prefix the app emits for a workspace remote is accepted by the real transport wrapper and equals the bare-repo root every host-side consumer uses, for both fetch and push.

**Assembly.** The prefix literal that must agree lives in six places this guard reads: the app constant (`git-data-replication.ts`), the wrapper, provision and remove defaults (`REPO_ROOT` in `git-data-transport-wrapper.sh`, `git-data-provision.sh`, `git-data-remove.sh`), the cutover composition (`git-data-cutover.sh` `OLD_ROOT` + `REPO_SUBDIR`), and the host mount literal in `cloud-init-git-data.yml` joined with `/repositories`. The container probe's default is held to the app constant by CPU1; the bootstrap's `REPO_ROOT` is not read (it cannot be edited, and the wrapper default it must match is read directly). The single chokepoint on the app side is `gitDataRemoteUrl`; both the named `git-data` remote (push, via `ensureGitDataRemote`) and the explicit fetch URL (`git-data-client.ts`, the `gitDataRemoteUrl(workspaceId)` call) flow through it, and R-PUSH / R-FETCH cover both directions. The harness shim is the second chokepoint: every dial passes through the recorded `GIT_SSH_COMMAND`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | revert `GIT_DATA_REPO_PATH_PREFIX` to `/repositories` | RED (R-URL, R-PUSH, R-FETCH, R-PARITY, U1-U4 via the extracted constant, CPU1) |
| 2 | change the prefix to `/mnt/git-data/repositories/` (trailing slash) or `/mnt/git-data/repos` | RED (R-PARITY exact equality; R-URL) |
| 3 | change ONLY `git-data-remove.sh`'s `REPO_ROOT` default or the `OLD_REPOS` composition in `git-data-cutover.sh` (app and wrapper intact), so the first member stays compliant | RED (R-PARITY checks every member, not the first) |
| 4 | make the shim log nothing, or point git at a different `GIT_SSH_COMMAND` so no dial is recorded | RED (the verb lines for upload-pack and receive-pack must be present; zero recorded fails) |

Harness rows: (a) the shim-records-nothing edit above reddens the SUITE, not the code under test; (b) must-PASS inputs that are not the canonical: a `ws-uuid-123` workspace id as well as a UUID, a tag ref alongside a head ref, and the push shape with `--push-option`. The anchor outside the commit is `cloud-init-git-data.yml`'s mount literal: editing it changes the host's `user_data`, which a terraform plan shows as a host replacement, so a change that moves both the app and the wrapper default together cannot pass unnoticed.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** two technical forks ruled by `soleur:engineering:cto` on 2026-10-27 (URL form A; runbook-only R3/R6 wording with no new probe). No Product/UX surface (no `components/`, `app/**/page.tsx` file), so the Product/UX gate is not triggered; no marketing, legal or finance implication (no new data processing, no copy). GDPR gate not triggered: no schema, auth, API route or migration touched, and no new processing activity; the Art. 17 erase path (`removeGitDataRepo`, bare id through its own forced command) is unchanged and is not routed through the URL.

## Architecture Decision (ADR/C4) gate

Skipped: no architectural decision is made or reversed. The fix restores conformance with the wrapper's existing contract; the wrong claim sat in two code comments, not in an ADR (ADR corpus grep, see Premise Validation). C4: read `model.c4` (`gitDataStore` element and the edges `claude -> gitDataStore`, `api -> gitDataStore`, `hetzner -> gitDataStore`, `github -> gitDataStore`, `gitDataStore -> sentry/betterstack/doppler`), `views.c4` (the infra view include) and `spec.c4`; the URL path form is not modeled in any of them, no external actor, system, store or access relationship changes, and `plugins/soleur/test/c4-count-parity.test.sh` passes at plan time (re-run at work time).

## Acceptance Criteria

### Functional Requirements

- [ ] `gitDataRemoteUrl(id)` returns `ssh://git@<host>/mnt/git-data/repositories/<id>.git` (`apps/web-platform/server/git-data-replication.ts`, constant at the `GIT_DATA_REPO_PATH_PREFIX` line).
- [ ] Real `git fetch` and real `git push --force` against that URL, through the REAL `git-data-transport-wrapper.sh` (seams), exit 0; the recorded commands are exactly `git-upload-pack '/mnt/git-data/repositories/<id>.git'` and `git-receive-pack '/mnt/git-data/repositories/<id>.git'` (vitest R-PUSH / R-FETCH, wrapper suite U1/U2). The vitest push is the production shape: by remote name `git-data`, both refspecs, `--push-option=lease-gen` and `--push-option=worktree-id`.
- [ ] After the push the bare repo holds `refs/soleur/worktrees/<wt>/heads/<branch>` and `.../tags/<tag>` with the pushed shas and no ref outside that namespace (R-PUSH, U4).
- [ ] The OLD form is refused with `repo path does not resolve: '/repositories/<id>.git'` in the wrapper suite (U3), and the always-exit-0 stub accepts it (the added stub-loop input).
- [ ] `ensureGitDataRemote` re-points a stale `git-data` remote to the new URL (R-STALE).
- [ ] The container-probe command equals git's emission for the URL form (CPU1, with the prefix extracted from the app constant), and the cutover.sh composition equals the prefix (R-PARITY).
- [ ] Runbook R3 and R6 require refs under `refs/soleur/worktrees/<id>/`, state that `<id>.git` existence, `store_not_empty` and provisioning success never count, and say plainly that no no-SSH refs read exists yet.
- [ ] PR body begins `Ref #8211` and contains no `Closes`/`Fixes` for it; #11086 is not mentioned as fixed.

### Non-Functional Requirements

- [ ] No SSH command, secret value or host address beyond the already-public private-net `10.0.1.20` appears in new test or runbook text.
- [ ] Every extraction in R-PARITY asserts exactly one match; zero is a failure.
- [ ] The e2e vitest file asserts hard preconditions (`git`, `bash`, `findmnt` present and `findmnt --mountpoint` answering for the store dir) and fails loud rather than skipping. The shim is named `ssh` so git sends no `-G` probe, and log assertions match the verb lines, not the whole file.

### Quality Gates

- [ ] `rg -n 'ssh://[^/ ]+/repositories/' apps/web-platform/server apps/web-platform/test/git-data-replication.test.ts apps/web-platform/test/git-data-client.test.ts apps/web-platform/test/git-data-remote-url-wrapper.test.ts` returns nothing.
- [ ] `git diff origin/main --name-only` is a subset of: the Files to Edit list, the Files to Create list, `knowledge-base/INDEX.md` if regenerated, this plan file (`knowledge-base/project/plans/2026-10-27-fix-git-data-remote-url-wrapper-path-plan.md`), and `knowledge-base/project/specs/feat-one-shot-8211-git-data-remote-url-path/{tasks.md,decision-challenges.md,session-state.md}` (pipeline-written files included on purpose).
- [ ] `git diff origin/main --stat -- apps/web-platform/infra/git-data-transport-wrapper.sh apps/web-platform/infra/git-data-bootstrap.sh apps/web-platform/infra/cloud-init-git-data.yml apps/web-platform/infra/git-data.tf apps/web-platform/infra/cron-egress-nftables.sh AGENTS.rules.md` prints nothing.
- [ ] The new vitest file is discovered by `npx vitest run test/git-data-remote-url-wrapper.test.ts` (reports its row count, not "no tests"), and the two infra suites still register by presence under `apps/web-platform/infra/` (`bash apps/web-platform/infra/run-registered-suites.sh --list` includes both).
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` passes; the runbook word-census case in `git-data-cutover-access.test.sh` passes after the runbook edit.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given the app builds the remote for workspace `W`, when real git pushes `refs/heads/*:refs/soleur/worktrees/T/heads/*` through the real wrapper, then the bare repo lists `refs/soleur/worktrees/T/heads/main` and no `refs/heads/main`.
- Given the old `ssh://.../repositories/W.git`, when git fetches through the same harness, then it exits non-zero with `repo path does not resolve`.

### Regression Tests

- Existing wrapper rows T1-T12 and C1a-C1f stay green (the section is additive).
- Traversal, symlink-at-repo-path and nested-path refusals (T4-T6) still refuse for the new prefix.

### Edge Cases

- Workspace id shapes: UUID, `ws-uuid-123`, dots and dashes (`WORKSPACE_ID_RE`); unsafe ids still throw before any URL is built.
- A tag ref in the same push as a head ref.
- A clone with no `git-data` remote yet (remote add) and one with a stale URL (set-url).

### Integration Verification (for `soleur:qa`)

- Post-merge, read-only and without SSH: `/health` `build_sha` on both web hosts equals the merge release; `deploy-arm.sh served <merge-sha>` prints `CONTAINS` (per the runbook's ordering note); Sentry search for `feature:worktree_lease op:git_data_replication_push` over the window after the deploy shows no `repo path does not resolve` event. Positive refs confirmation is the rehearsal's R3 owner attestation (decision-challenges row 4); no production-mutating step is taken by this PR.

## Rollback

Reverting the constant restores the defect (every push and fetch refused), so a revert is not a safe rollback. The safe fallbacks are existing ones: leave the flag off, or the cutover `mode=rollback` (R4), which is why this PR carries no flag change. If the new prefix itself proves wrong on the host, the signal is the same Sentry wrapper-refusal event; correct the constant forward. (Simulated at plan time: `git revert --no-commit` of this change touches only the files listed above; the only gates that react are the new tests, which is the point.)

## Dependencies & Risks

- Rebase risk on the runbook with #10905 (same file, different region).
- The e2e path-maps `/mnt/git-data/repositories` onto a fixture root, because CI has no such mount; that is why R-PARITY (literal equality with the wrapper's default and the cloud-init mount) is part of the same guard rather than a nicety.
- The vitest harness runs the real wrapper, which needs `findmnt`, `mountpoint`, `stat`, `readlink` (util-linux/coreutils); the existing wrapper suite already requires them, and the new test fails loud if absent.
- A wrapper rule change later (for example a different root) turns R-PARITY and the e2e red by design.
- Rehearsal readiness: R3 cannot pass on negative evidence; the owner decision in `decision-challenges.md` row 4 is the schedule risk. This PR does not decide it.

## Parked follow-ups (single comment on #8211)

Positive no-SSH refs read for R3/R6; container probe accepting any `remote: git-data transport:` answer; stale bootstrap step-4b comment (needs a host replace). No new issues.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one is filled.
- The Observability `discoverability_test.command` is a one-line `rg` on a committed source file, inside the 15 second cap, with a literal expected output.
- `cron-egress-nftables.sh` mentions the old URL in a comment. It is loaded on the WEB hosts through `server.tf`'s `cron_egress_firewall` provisioner, whose `config_hash` is a sha256 over the file, so even a comment edit re-runs that provisioner (and restarts `cron-egress-firewall.service`) on live web hosts. Do not "clean it up" in this PR; fold the comment fix into the next deliberate change to that file. (An earlier draft said it ships in another host's user_data; review measured that false.)
