---
title: "git-data: six hash-bound hardening items, batched — erasure can report success having erased nothing, plus the sshd-unit, authorized_keys2, hooksPath and AcceptEnv surface"
date: 2026-09-10
slug: fix-git-data-hash-bound-hardening-batch
branch: feat-one-shot-8043-git-data-hash-bound-hardening
issue: 8043
closes: 8043
type: fix
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  The ack is truthful, not an escape hatch. Phase 2.8 ran and `## Infrastructure (IaC)` is written.
  Every `systemctl` verb discussed here is CONTENT OF A CLOUD-INIT TEMPLATE that Terraform renders
  into `hcloud_server.git_data.user_data`. Nothing is provisioned outside Terraform, and the apply
  path is deliberately *no apply at all*: the host does not exist yet.
-->

## Enhancement Summary

**Deepened on:** 2026-09-11
**Sections enhanced:** Observability (P1-3), Guard 2 + FR11b (P1-2), Guard 4 assembly + Files to
Edit, F7 ordering, F10/FR7 roster, FR11 construct, FR17, Phase 0 hash provenance
**Research agents used:** verify-the-negative sweep (14 claims, sonnet), learnings-researcher,
test-design-reviewer (Guard Contract), plus inline measurement (ruleset required-context read;
node prototype of the emitter-derived stage set; `betterstack-query.sh --help` reproduction; Check 10 `credentials_required` branch read;
baseline hash re-derivation)

### Key Improvements

1. **P1-3 resolved — the discoverability probe was doubly dead.** `--help` exits 3 (no handler; the
   cred check runs first) *and* the `credentials_required: "none — …"` line would have made Check
   10 `SKIP-DECLARED` without executing anything. Probe is now the Guard 5 suite with FR13's row
   label as `expected_output`; the field is removed because presence is the waiver.
2. **P1-2 resolved — Guard 2 rows 4/5 are now drivable RED.** The op-contract test proved only
   `WARNING_STAGES ⊆ tf`. Three set-equality assertions (tf ⇔ literal; emitter-derived warning set ⇔
   literal ∪ named fatal-routed exceptions; each exception on the fatal rule) are specified with the
   measured expected values, three extra mutation rows added (5b–5d).
3. **Guard 4 now has a home, and its tier is stated honestly.** The first draft named a property
   with no file and routed it to "CI, pre-merge"; measured, the only CI job in reach
   (`deploy-script-tests`) is not a ruleset context. The guard now has a **birth-time arm** inside
   `git_data_rung2_rehearsal_gate` (blocks the birth; HOLDs on a shallow clone, so the birth job's
   checkout gains `fetch-depth: 0`) and an **advisory PR-range arm** in `infra-validation.yml`,
   with the rebase-merged multi-commit residual filed to #8010.
4. **Test-design pass (6.8/10 before, findings folded):** Guard 2 row 2 gained a positive control
   (contrary drop-in + failing `restart ssh` + torn-down `/run/sshd`); `sshd -T` rc 255 joins the
   could-not-measure class; "missing directive" fixtures set contrary values, not deleted lines;
   Guard 3 gained a stated traversal/writability model with runtime rows in S1's container; Guard
   5's refusal is pinned at **exit 64 + stderr naming `BS_TABLE`** (the script's usage-error
   convention; 2 and 3 already mean other things) via a stderr-capturing runner; Guard 1's stub
   must exact-match the mount root.

### New Considerations Discovered

- `gc_timer` is emitted at `level:warning` but **pages** via the fatal rule's stage-only `eq` —
  pre-existing; pinned as a literal exception and filed in FR17 as a policy decision, not changed.
- `issue-alerts.tf` carries a `removed`+`import` pair for the warning rule, not a `moved` block
  (FR11 corrected). `git-data-transport-wrapper.sh` has **three** AcceptEnv-claim comment sites,
  not two — F10 is five sites across three files (F10/FR7/Files-to-Edit corrected).
- `decision-challenges.md` UC-1 mis-numbered the betterstack item as FR12/Guard 4 (the evidence-
  deletion items); corrected to FR13/Guard 5, and its "nothing depends on it" claim now names the
  discoverability probe as the one dependency.

## Overview

Six hardening defects on the git-data host, fixed as one change because each edits a file inside the
13-file `RUNG2_TEMPLATE_SHA256` binding. Any single edit voids the committed rung-2 boot evidence, so
moving them together costs one fresh rehearsal instead of six.

**This plan was rewritten twice against measurement.** A CTO consult rejected four of the six fixes
as first designed; a six-agent review panel then found that the corrected plan **could not merge**,
that two of its fixes still did not close the holes they named, and that its central observability
claim was false. Every such correction is folded in below and carries the measurement that produced
it. The three that change the shape of the work:

1. **The PR could not merge as sequenced.** `infra-validation.yml`'s rung-2 freshness check arms
   itself once the evidence file exists, and fails when the hash moves — which is the whole point of
   this PR. Resolved by **deleting** the void attestation rather than editing it (§ The merge
   interlock).
2. **F7 closed neither hole.** `authorized_keys` ships `owner: git:git`, so the constrained
   principal owns and can rewrite the map in place; root-owning only `/home/git` left that
   untouched.
3. **The new sshd assertion would have gone dark.** The stage it was to emit on routes to no Sentry
   rule today — including the very row that carried the F11 measurement.

## Problem Statement

Five items (F6–F10) were filed on #8043 during #8009. A sixth (F11) was measured on 2026-09-10 while
re-verifying the rung-2 evidence. All six are properties of a running host, or of files that host
owns — things a static assertion over Terraform source structurally cannot see.

| id | Defect | Severity today | Hash-bound via |
|---|---|---|---|
| F6 | `modules/git-data-userdata/variables.tf` frames all eight render vars as "identity-shaped". For the three SSH pubkeys that is wrong: together they **are** the host's SSH authorization map — a capability divergence. | Comment accuracy | module `.tf` |
| F7 | The `git` account **owns and can rewrite** its own authorization map; `01-hardening.conf` pins no `AuthorizedKeysFile`, so `authorized_keys2` is also honoured. | Defense in depth | template + payload |
| F8 | `git-data-remove.sh` (Article 17 erasure) can exit 0 having erased nothing; `git-data-provision.sh` can write a real user repo onto the root disk. | **Serious** | payloads |
| F9 | `core.hooksPath` points at a directory writable by the `git` account whose pushes the hook fences. | Defense in depth | payload |
| F10 | **Five** wrapper comment sites (remove ×1, provision ×1, transport-wrapper ×3 — the issue said four; the third transport-wrapper site, on the dry-run hook, was found at deepen-plan) claim sshd passes no client env (`AcceptEnv` empty). Ubuntu ships `AcceptEnv LANG LC_*`. | Comment accuracy | payloads |
| F11 | The template's only ssh unit action names `sshd`; the image is `ubuntu-24.04` where the unit is `ssh`. It fails on every boot, fail-open, and `boot_complete` still reports all four booleans `yes`. | Dead code + unmeasured drop-in | template |

### F8 in detail — the one with weight

`git-data-remove.sh` derives `REPO_ROOT="${GIT_DATA_REPO_ROOT:-/mnt/git-data/repositories}"` and
guards it with `readlink -f`. **`readlink -f` succeeds on a path that does not exist.** So on a host
whose volume failed to mount, both guards pass, `mkdir -p "$REPO_ROOT"` writes into the unmounted
mountpoint on the root disk, the repo is not found, and the script prints `not present (no-op)` and
exits 0 — an Article 17 erasure success over a store nobody looked at.

**What prevents it today is an accident, not an assertion.** The forced command runs as `git`,
cloud-init creates `/mnt/git-data` as root, and the bootstrap chowns only the *symlink* — so
`mkdir -p` takes EACCES and `set -euo pipefail` aborts. Chown that mountpoint to `git` for any
unrelated reason and erasure begins silently succeeding over nothing. That sentence is the most
quotable line against us in this file and it is deliberately not softened; FR16 records the
accident-to-assertion transition **with its date** so it is never discoverable without its
remediation attached.

**The provision path is the more severe half.** On an unmounted host `git-data-provision.sh` runs
`git init --bare` and writes a **real user repository onto the root disk**; a later successful mount
silently hides it. That is data loss, not a false report.

**Measured, and it reshapes the fix:** deleting `mkdir -p "$REPO_ROOT"` **already** fails closed, on
its own. The next statement is `exec 9>"$lock_file"`, and a failed redirection on a special builtin
exits the shell under `set -e` (`rc=1`, verified in isolation). So the mount assertion is a *message
upgrade* — it turns a raw bash error into a named reject — and the `mkdir` deletion is the
load-bearing control. Phase 2 must not present them the other way round.

`git-data-transport-wrapper.sh` shares the root derivation but already rejects a non-existent repo,
so on an unmounted host it fails closed on every push. **It gets no mount assertion**: the plan's own
justification for touching it was "consistency", which is not a property.

> **Superseded at review (#8052, pattern-recognition + structural seats).** "Rejects a non-existent
> repo" covers the *absent* root, not the *off-store* root the review pass added to provision/remove
> (`stat -c %m` containment): a wrapper whose root resolved onto the root disk beside a healthy mount
> exec'd `git-receive-pack` there (measured, `rc=0`). The property is "the forced command that writes
> user source acts only on the store", which is not consistency. The wrapper now carries the same
> mount + containment guard, the `.cutover-freeze` refusal, and pins `core.hooksPath` on the command
> line; `git-data-transport-wrapper.test.sh` T8–T11 pin it.

### F11 in detail — measured, not inferred

From git-data's own Better Stack source (2734275 / `t520508_soleur_git_data_prd_logs`), filtered to
the rung-2 rehearsal host:

```json
{"stage":"sshd_config_warn","level":"warning",
 "message":"git-data sshd restart failed (config valid)",
 "host_name":"soleur-git-data-rehearsal-33888071954",
 "detail":"Failed to restart sshd.service: Unit sshd.service not found."}
```

Three rows total: `gitdata_runcmd_ok`, this one, `boot_complete`. Zero `level:fatal`.

**The mechanism**, measured against a live `ubuntu:24.04` with archive `openssh-server`:

```
ssh.socket   Accept=no   Before=sockets.target ssh.service   RequiredBy=ssh.service   (no Conflicts=)
ssh.service  Type=notify  ExecStartPre=/usr/sbin/sshd -t  RuntimeDirectory=sshd  Alias=sshd.service
enabled: sockets.target.wants/ssh.socket PRESENT | multi-user.target.wants/ssh.service ABSENT
```

`Alias=sshd.service` is instantiated only when `ssh.service` is *enabled*. Socket activation means it
never is — hence `Unit sshd.service not found.` on every boot.

**Three corrections to the framing this plan first carried:**

1. **`Accept=no` — there is no per-connection `sshd -i`.** One long-lived `sshd -D` inherits the
   listening fds. The "a per-connection re-read makes the drop-in effective anyway" reasoning in the
   issue comment is false.
2. **The unit action is redundant for the config load** — but for a different reason: `write_files`
   precedes `runcmd`, `ssh.service` has not started, so the daemon reads `01-hardening.conf` at its
   first start regardless. The honest justification for keeping an action is the **observation
   window**: start the daemon deterministically where the boot is instrumented, instead of lazily at
   first connection where nothing watches.
3. **The rename is safe on a console-less host for a specific, measurable reason that must be
   recorded:** `ssh.socket` carries **no `Conflicts=ssh.service`**, so the listener stays bound and a
   failed `ssh.service` start does **not** close port 22. Against that, `Type=notify` +
   `ExecStartPre` means the call now blocks on a systemd job — bounded by `DefaultTimeoutStartSec`
   (90 s), where the old call returned instantly at rc=5. That is a new up-to-90 s stall above the
   LUKS stage, and the fresh rehearsal must read the boot wall-clock delta.

**Scope limit.** The three forced-command lines are read per connection and are **unaffected**; the
capability separation holds. What was unproven is whether the drop-in is loaded at all — **nothing
measures it**. That gap, not the dead unit name, is worth the bytes.

## The merge interlock — why this PR deletes the evidence file

**As first sequenced, this PR could not merge.** Measured:

- `.github/workflows/infra-validation.yml`, step *"Rung-2 evidence freshness (active only once
  evidence exists)"*, skips only while the evidence file is **absent** — "dormant by design" — and
  otherwise runs `git_data_rung2_rehearsal_gate` against the live template and `exit 1`s on a
  mismatch. The file exists on `main`, so the step is **armed**, and this PR moves the hash by
  design.
- The escape of "just rehearse first" is closed: `git-data-rung2-rehearsal.yml` runs under
  `environment: web-platform-infra-apply`, and that environment's deployment branch policy is
  `custom_branch_policies: true` with **exactly one allowed branch — `main`**
  (`gh api repos/jikig-ai/soleur/environments/…/deployment-branch-policies` → `total_count: 1`,
  `main`). So a rehearsal cannot run from this branch, and the branch cannot merge while the
  evidence is stale. That is a deadlock, not a sequencing preference.

**Resolution: this PR DELETES `apps/web-platform/infra/git-data-rung2-boot-evidence.env`.**

Deleting is categorically different from the thing the brief forbids. Editing `RUNG2_TEMPLATE_SHA256`
to the moved digest would make a void attestation *look freshly re-rehearsed* — the precise failure
the gate exists to prevent, and one it cannot catch, because its only provenance check is a **regex
that `RUNG2_EVIDENCE_URL` looks like an Actions run URL**; it never fetches the run. Deleting asserts
nothing. It states the truth: the boot that was proven is not the boot that would happen.

It is also fail-closed in both directions:

- `git_data_rung2_rehearsal_gate` HOLDs on an absent file (`if [[ ! -f "$evidence" ]]` → HOLD), so
  the **birth stays interlocked** — harder than before, not softer.
- The CI freshness step returns to its dormant-by-design arm, so the PR is mergeable.

The sequel then re-creates the file from a real rehearsal dispatched from `main`, in its own
human-approved PR, exactly as intended.

## Research Insights

### Premise Validation (Phase 0.6)

All issue premises hold. **One premise supplied by the brief did not reproduce**, and several
supporting claims from consults and the learnings corpus were falsified on checking — all reconciled
below.

| Cited | Result |
|---|---|
| `#8043` open; F11 filed as a comment carrying the measurement | Confirmed |
| the template names the wrong ssh unit; four templates, all `ubuntu-24.04` | Confirmed (`git-data.tf`, `rung2-rehearsal/rehearsal.tf`, and the three siblings) |
| `readlink -f` succeeds on an absent path, so the reject never fires | Confirmed by reading the guard |
| the `git` account owns the authorization map | Confirmed: `owner: git:git`, `permissions: '0600'`, plus a recursive chown of `.ssh` to `git:git` in the bootstrap |
| `01-hardening.conf` pins none of `AuthorizedKeysFile`/`AcceptEnv`/`PermitUserEnvironment` | Confirmed — nine directives, none of the three |
| `core.hooksPath` target is git-owned | Confirmed |
| "identity-shaped" appears once, and the corrected wording already exists in the gate | Confirmed |
| `betterstack-query.sh` ignores `--table` in raw-SQL mode | Confirmed — Mode 1 matches on `$1` and `exit $?` before the flag loop |
| `#8010`, `#7025` open; `#8009`/PR `#8035` closed/merged | Confirmed |
| **brief:** the inngest-bootstrap pin drift-guard is red on `main` | **DID NOT REPRODUCE** — 163/163 `OK` on a worktree byte-identical to `main`. Recorded as unreproduced, not contradicted (its pin-vs-tag arm needs network + `fetch-tags`). **Load-bearing:** the web-host deferral must not rest on this claim, and the follow-up must not repeat it. |

### Research Reconciliation — claims falsified on checking

| Claim | Reality | Response |
|---|---|---|
| ADR-149: the git-data boot has "zero observability" | **Superseded.** The emitter ships (#6982) and the token is baked (#7460/ADR-198); the F11 row came out of git-data's own source. | Emit through the existing emitter; build no new channel. |
| "No `mountpoint -q` precedent in the siblings" | **False.** `git-data-bootstrap.sh` uses it at six sites, inside the same hash-bound set. | Copy that precedent. |
| `git-data-runcmd-rehearsal.test.sh` "does not exist" | **False** — 241,826 B, and it contains case S1, which runs the real sshd stage in a real Ubuntu container. Its `systemctl` stub is `printf '#!/bin/sh\nexit 0\n'`, which is exactly why the unit-name defect survived it. | S1 is where the F11 RED goes; the stub becomes programmable. |
| The 32 KB `user_data` cap constrains this change | Measured headroom **19,020 B** (stored 13,748 / cap 32,768), and comments are render-stripped. | Quality gate, not a design constraint. |
| A per-connection `sshd -i` makes the drop-in effective anyway | **False** — `ssh.socket` is `Accept=no`. | F11 rejustified around the observation window. |
| `mountpoint -q "$REPO_ROOT"` asserts the store is mounted | **False and dangerous.** `/mnt/git-data/repositories` is a *subdirectory*; `mountpoint -q` on it returns rc=1 on a correctly mounted host, so the first design would have **failed every erasure closed** — Art. 17 non-compliance in the opposite direction. | Assert the mount **root**, via a decided seam (below). |
| Root-owning `/home/git` closes F7 | **False.** `authorized_keys` is `git:git 0600` — `git` rewrites it **in place**; no directory swap needed. The home is the *second* hole, not the only one. | Root-own all three (below). |
| Pinning `AcceptEnv` empty enforces the corrected comment | **False, and boot-fatal-capable.** The keyword **accumulates**; `AcceptEnv` bare → `sshd -T` rc=255, `AcceptEnv ""` → rc=255. A 255 lands on the `sshd -t REJECTED` arm → `exit 1` → runcmd aborts **before LUKS** → dark host, and a `level:fatal` that fails the rung-2 gate closed. | Pin **cut**. F10 ships as the comment correction only. |
| A new `STAGE=` is a safe way to add a stage | **False.** The top-armed trap reports the last-assigned `STAGE`, and `git_data_boot_fatal` routes on ten literal values, so a new assignment makes any later death in that item report a stage in no rule. | Emit a literal stage string; leave `STAGE=sshd_config` intact. |
| The erasure "outcome token" adds accountability | **Premise false twice.** Three distinct outcomes already exist on stderr (`reject`, `not present (no-op)`, `erased bare repo for`); and the token is **unreadable by construction** — `sshWithPrivateKeyAuth` resolves to **stdout only**, `removeGitDataRepo` is `Promise<void>` and discards it (on failure the rejection carries `stderr`/`code` — review correction, see §User-Brand Impact). | Token **cut**. Art. 5(2) is delivered by FR4's non-zero exit plus the existing Sentry mirror. |
| `ExecMainStartTimestampMonotonic` proves the daemon started | Duplicates the existing `_sshd_r_rc` branch, and on a once-per-instance `runcmd` on a never-booted host both branches are acceptable — it distinguishes two non-defects, and nothing acts on the answer. | **Cut.** |
| The new row routes to operator email | **False, twice.** `sshd_config_warn` matches **nothing** in `sentry/` or `test/` — the F11 discovery row pages nobody. And `git_data_boot_warning` carries `fallthrough_type = "NoOne"` against a project with no ownership rule, so it lands in the issue stream and pages no one. | Reuse and **route** `sshd_config_warn`; state the `NoOne` reality in Observability. |
| The plan's Files-to-Edit closes the erasure loop | **False.** `account-delete.ts` catches, mirrors to Sentry, and **continues** — the user is still told the account was deleted. | Stated honestly; the boundary is FR17's cutover-deadlined follow-up. |

### The hash binding, enumerated

`git_data_rung2_user_data_sha256()` hashes the cloud-init template, the render module's own three
`.tf` files, and the nine `file()`-bound payloads — **13 files**: `cloud-init-git-data.yml`;
`git-data-{bootstrap,pre-receive-placeholder,provision,transport-wrapper,remove,gc}.sh`;
`git-data-gc{,-failure}.service`; `git-data-gc.timer`; and
`modules/git-data-userdata/{main,variables,outputs}.tf`.

The hash is over **source**, not the render. That is why F6 and F10 — pure comment fixes — void the
evidence at all, and why they cost **zero** rendered bytes (`local.git_data_rationale_strip` removes
comment lines at render time, ADR-152).

**Worth naming rather than accepting as physics:** hashing source instead of render is *why* a
comment that never reaches the host voids a paid attestation, and therefore why this batch has to be
six items wide. Not this PR's job to change — recorded as a finding in the FR14 ADR amendment.

Everything the fixes touch **outside** those 13 — the birth gate and its fixtures, the Sentry alert
Terraform, the op-contract test, the suites, the runbooks — is free.

### Property List (Phase 0.6b)

1. An Article 17 erasure cannot report success unless it acted on the mounted store.
2. A repo cannot be provisioned into a directory that is not the mounted store.
3. The `git` account cannot rewrite its own SSH authorization map — by editing it **or** by
   replacing the directory holding it — and sshd reads exactly one authorization file.
4. The push-fence hook directory is not writable by the account whose pushes it fences, and remains
   traversable by it.
5. The sshd hardening drop-in is measurably in effect on the booted host.
6. Every emitted stage reaches a routing rule.
7. Comments bound into the evidence hash state true things.
8. A Better Stack query cannot silently read a source the caller did not ask for.
9. A voided attestation cannot be made to look freshly re-rehearsed.

### Cut List (Phase 0.6b)

| Mechanism | Property | Why cut |
|---|---|---|
| Erasure outcome token (FR5, first draft) | 1 | Premise false: three outcomes already distinguishable on stderr, and the token is unreadable by construction (`sshWithPrivateKeyAuth` resolves to stdout only; `removeGitDataRepo` returns `void`). Designing its shape "for the sibling web-host defect" was speculative generality for a deferred issue. |
| `ExecMainStartTimestampMonotonic` capture | 5 | Duplicates the existing rc branch; distinguishes two acceptable states on a first boot; no consequent. |
| Mount assertion in `git-data-transport-wrapper.sh` | — | Maps to no property; the plan's own justification was "consistency". |
| `AcceptEnv` pin | 7 | Unrepresentable — accumulating keyword, both clearing syntaxes exit 255 into the boot-abort arm. |
| `PermitUserEnvironment no` pin | 7 | Measured as already the default; a no-op costing hash-bound bytes. |
| Minting a new stage name | 6 | `sshd_config_warn` already exists in the same block — reuse it, and route it, which also repairs a pre-existing dark path. |
| Widening `boot_complete`'s four booleans | 5 | Couples this PR to #8010's contract and an AC30-parity assertion for a property a stage carries. |
| `level:fatal` for the new row | 5 | Fails the rung-2 gate closed on a first-outing instrument. |
| Device-identity assertion in the erasure path | 1 | Phase-ambiguous: the cutover re-points the mapper, so `/mnt/git-data`'s device differs pre/post. Belongs at boot, where it already is. |
| `AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u` | 3 | Measured to work, but moves a literal five birth-gate arms key on, and is redundant once `.ssh` is root-owned. Follow-up. |
| Fixing the ssh unit in the sibling templates | 5/6 | Measured cost; see the fleet decision. |
| **Editing** the evidence file to match the moved hash | 9 | Forbidden. **Deleting** it is the correct move — see § The merge interlock. |

### Value-Proposition Measurement (Phase 0.6c)

The saving is **five rehearsal host-lifecycles plus five human-approved evidence PRs** — measured as
a count of avoided rehearsals; the currency figure is not derivable at plan time and is not the
deciding quantity. The larger saving is timing: `user_data` is ForceNew and git-data is excluded from
the reboot primitive (ADR-115), so the same edits after the birth cost a destructive
`git-data-host-replace` of the host holding every user's source code.

## Proposed Solution

### The fleet decision for F11 — git-data only

| Template | Host | `ignore_changes` on `user_data` | Consequence of editing |
|---|---|---|---|
| `cloud-init-git-data.yml` | `hcloud_server.git_data` | **No** (`[ssh_keys]` only) | Unborn → **free now**, destructive replace after the birth. **Fix here.** |
| `cloud-init.yml` | `hcloud_server.web` | **Yes** | Inert for the running host; reaches only a future fresh create. |
| `cloud-init-inngest.yml` | `hcloud_server.inngest` | **No**, deliberately | ForceNew → destructive **replace of a live host**. |
| `cloud-init-registry.yml` | `hcloud_server.registry` | **No**, deliberately | Same. A replace is *already pending* on that host per its own `lifecycle` comment, so this plan neither creates nor deepens the divergence. |

A **fifth** `ubuntu-24.04` host exists and is correctly out of scope: `hcloud_server.grok_dogfood`
(`grok-dogfood.tf`) renders `cloud-init-grok-dogfood.yml`, which carries **no ssh unit action**. It is
named here so a future reader re-deriving "all four templates" does not re-derive it wrong.

**Follow-up severity is load-bearing.** On all three siblings the drop-in loads at the daemon's first
start regardless, so the class is *noisy, not unhardened* — **with one exception that must not be
filed as noise**: inngest's next `runcmd` item is
`/usr/local/bin/inngest-boot-phone-home.sh sshd-restarted`, a **positive attestation for an action
that fails on every boot**. That is a false-attestation instrument on a live host, not noise.

### F11 — the fix, in the order it must run

**(a) Name the unit the image ships** (`ssh`), and rewrite the adjacent comment to the
observation-window justification, recording that `ssh.socket` has no `Conflicts=` so port 22 stays
bound, and that the call now blocks on a `Type=notify` job bounded at 90 s.

**(b) Assert the effective config — BEFORE the unit action, not after.** `ssh.service` declares
`RuntimeDirectory=sshd`, so **systemd owns `/run/sshd`** and tears it down when the unit stops or a
start fails (`RuntimeDirectoryPreserve` defaults to `no`). Ordering `sshd -T` after the action means
that on the fail-open branch `/run/sshd` may be gone, `sshd -T` exits 255 `Missing privilege
separation directory`, and edge case 19 classifies it could-not-measure — **silent in exactly the
failure it exists to catch.** Run it immediately after the existing `sshd -t`, where the stage's own
`/run/sshd` setup guarantees the directory.

Compare only the two directives whose absence is dangerous — `PasswordAuthentication no` and
`PermitRootLogin prohibit-password` — rather than walking all nine. That satisfies the property and
avoids three self-inflicted normalization traps, all measured:
`permitrootlogin prohibit-password` is normalized to `without-password`; `AcceptEnv LANG LC_*` prints
as **two** lowercase lines; keywords are lowercased. A general roster walk must handle all three; a
two-directive `grep -qx` against the lowercased dump does not.

**(c) Emit on the stage that already exists, and route it.** Do **not** assign a new `STAGE=`. The
block already emits literal stage `sshd_config_warn` (twice), while `STAGE=sshd_config` stays intact —
that is not a precedent to copy, it is the same stage. And `sshd_config_warn` matches **nothing** in
`apps/web-platform/infra/sentry/` or `apps/web-platform/test/`: the row that carried the F11
measurement reaches no rule today. Adding that one token to `git_data_boot_warning`'s `in` list and
to `WARNING_STAGES` both carries the new assertion **and repairs a pre-existing dark path** — the
highest-value line in the batch, and free.

**Write the stage as the bare literal `sshd_config_warn`, and cite the right precedent.** The first
draft pointed at the `gitdata_nftables_metadata` / `_warn` pair as the literal-string precedent; that
pair does the **opposite** — it emits `"$${STAGE}_warn"`, *derived* from `$STAGE`. The genuine
literal precedent is the sshd stage's own two existing warn emits, twenty lines from where the new
code goes. The distinction matters because an implementer following "emit a literal" who copies the
nftables shape writes a derivation, which happens to render the same string under `STAGE=sshd_config`
today and silently diverges the day anyone renames the stage.

Because the drop-in assertion and the existing restart-failure row now **share** `sshd_config_warn`,
routing cannot tell them apart — and does not need to; **the message and `detail` do**. The
assertion row carries its own message (`git-data sshd hardening directive absent from effective
config`) and names the directive in `detail`, so the two are discriminable in Better Stack and in
the captured evidence rows while riding one routed stage.

### F7 — close both holes, and put the fix where the gate allows it

Two holes, both measured:

1. **The file.** `authorized_keys` is `owner: git:git` `0600` inside a `git:git 0700` `.ssh` — `git`
   owns the map and rewrites it in place.
2. **The home.** `/home/git` is created by the template's `users:` block with useradd semantics
   (`HOME_MODE 0750`, owned by `git`), so even a root-owned file is bypassable by replacing `.ssh`.

**Fix all three objects, with modes chosen so the account can still work:**

| Object | Target | Why |
|---|---|---|
| `/home/git` | `root:git 0750` | sshd `chdir()`s here for the forced command and `git` resolves `$HOME` config here. `root:root 0750` would repeat exactly the `$HOOKS_DIR` traversal trap F9 exists to avoid. |
| `/home/git/.ssh` | `root:git 0750` | Not writable by `git`, so `authorized_keys2` cannot be created — which is what actually closes the fall-through. |
| `authorized_keys` | `root:root 0644` | ~~sshd reads it as root before dropping privileges~~ **Corrected at review 2026-09-11:** sshd opens the map under the TARGET USER's uid (measured in the pinned image — `root:root 0600` is "Permission denied" and every push is refused; `root:root 0644` authenticates), which is exactly why the mode is 0644 and not 0600. StrictModes permits `st_uid == 0` — that half stands. |

**Where the fix may live is constrained by a gate, not by taste.** `git_data_authorization_map_gate`
HOLDs if the template references the literal `/home/git/.ssh/authorized_keys` **outside** its
`write_files` `- path:` declaration, because `runcmd` runs after `write_files` and would decide the
real map. So: the `owner:`/`permissions:` change goes on the `write_files` entry, and the
ownership work for `/home/git` and `.ssh` goes in **`git-data-bootstrap.sh`** (a payload file the
gate does not scan), replacing the recursive chown that currently reverts cloud-init's declaration.

**Two non-hash-bound files must move with it, or the birth is held by our own fix.**
`tests/scripts/lib/git-data-birth-readiness-gate.sh` HOLDs unless the entry declares exactly
`owner: git:git`, and its stated rationale — *"an authorization map owned by anyone else is either
unreadable by sshd or writable by a second principal"* — is **measured false**. Flip the arm, correct
the rationale, and update the fixture in `tests/scripts/test-git-data-birth-readiness-gate.sh`.

`AuthorizedKeysFile .ssh/authorized_keys` is still pinned, with its role stated honestly: with `.ssh`
root-owned nothing can create `authorized_keys2`, so the pin is defense in depth against a future
ownership regression, not the control that closes the hole.

**Ordering in the bootstrap is the whole fix, not a detail** (learning
`2026-03-20-cloud-init-chown-ordering-recursive-before-specific.md`: a recursive chown placed after
a targeted one silently reverts it, and cloud-init exits 0). The current
`chown -R "$GIT_USER:$GIT_USER" "$GIT_HOME/.ssh"` runs in `runcmd`, i.e. **after** `write_files`,
so it is the *last writer* and today reverts whatever `owner:` the template declares. The fix
**deletes** that recursive chown rather than re-ordering it — there is no correct position for a
`-R` over `.ssh` once the map is root-owned — and replaces it with three targeted, non-recursive
calls in this order: `chown root:git /home/git && chmod 0750 /home/git`, then the same for
`/home/git/.ssh`, then `chown root:root /home/git/.ssh/authorized_keys && chmod 0644`. The
post-condition assert reads back all three with `stat -c '%U:%G %a'` and compares literals, so the
test proves the *absence* of the reverted state, not merely the presence of a chown line (Guard 3
row 4 is the mutation that restores the `-R`).

### F8 — delete the create, assert the mount root, decide the seam

- **Delete `mkdir -p "$REPO_ROOT"` from `git-data-remove.sh`** — an erasure path must never create the
  store — **and from `git-data-provision.sh` too**, rather than reordering it: `git-data-bootstrap.sh`
  already creates `$REPO_ROOT` at boot, downstream of its own `mountpoint` FATAL, so provision's
  `mkdir` is dead on a healthy host and is precisely the hazard on an unhealthy one.
- **Assert the mount root** in both, as a named reject above the `readlink` guards.
- **The test seam must be decided before the RED phase, and the first draft's instruction was
  self-contradictory.** It said both "derive `GIT_DATA_ROOT` the way `git-data-bootstrap.sh` does"
  (a hardcoded `/mnt/git-data`) and "derive from the same variable" as the seam
  (`GIT_DATA_REPO_ROOT`, caller-supplied). Both cannot hold. All three wrapper suites invoke
  `env -i PATH="$PATH" GIT_DATA_REPO_ROOT="$root"` with `$root` an ordinary temp dir, so
  `mountpoint -q "$(dirname "$REPO_ROOT")"` reds **every existing case**, and acceptance test 2 —
  the mounted-store row the plan requires be written first — becomes unbuildable. Creating a real
  mount needs `CAP_SYS_ADMIN`; PATH-stubbing `mountpoint` contradicts the cited fail-safe learning
  and edge case 18.
  **Decision: introduce a second, independently-defaulted seam `GIT_DATA_MOUNT_ROOT`**
  (`${GIT_DATA_MOUNT_ROOT:-/mnt/git-data}`), asserted directly. Production derives it from the
  default; the suites set it to a directory they can make satisfy the assertion. `mountpoint` is
  still resolved absolutely and fails closed when absent. This also removes the unstated
  one-level-of-nesting assumption in `dirname`.

### F9 — the directory AND the file, root-owned but traversable

`$REPO_ROOT` stays `git`-owned; `$HOOKS_DIR` becomes **`root:git 0750`** — not writable by `git`,
still traversable, because `git` runs `receive-pack` which execs the hook. Split the
`mkdir`/`chown`/`chmod` triple that today applies one owner and one mode to both paths.

**The directory alone does not close the property, and the first design stopped there.** The
bootstrap installs the fence with
`install -o "$GIT_USER" -g "$GIT_USER" -m 0755 "$PLACEHOLDER_STAGED" "$PRE_RECEIVE"` — so
`pre-receive` itself is **owned by `git` at 0755**. Truncating an existing file needs write
permission on the *file*, not on its directory, so after a root-owned `$HOOKS_DIR` the `git` account
could still overwrite the very fence it is fenced by. That is the
guard-narrower-than-its-claim class this plan cites a learning for, reproduced inside the fix.

**So: `install -o root -g root -m 0755`**, and the post-condition assert covers the **file's**
ownership as well as the directory's and the configured `core.hooksPath`.

### F6 and F10 — the comment fixes

- **F6** — mirror the capability-divergence wording already in
  `tests/scripts/lib/git-data-birth-readiness-gate.sh` into the hash-bound `variables.tf`.
- **F10** — correct all **five** comment sites (`git-data-remove.sh` ×1, `git-data-provision.sh` ×1, `git-data-transport-wrapper.sh` ×3: the header, the `GIT_DATA_REPO_ROOT` override note, and the dry-run hook — `grep -nE 'AcceptEnv|client env'` over the three scripts is the roster, and it returns five sites, not the issue's four). The premise is false; **the conclusion is still true**, and
  that is what to write: `AcceptEnv LANG LC_*` cannot match `GIT_DATA_REPO_ROOT` or
  `GIT_DATA_TRANSPORT_EXEC_DRYRUN`, so the test seams stay unreachable from a client. These four
  comments are the stated basis for a **security boundary**, not stale notes — the F6–F11 table's
  "comment accuracy" severity under-rates them, deliberately corrected here.

### The `--table` trap

`betterstack-query.sh` Mode 1 matches on `$1` and `exit $?` before the flag loop, so `--table`
alongside raw SQL is discarded and the query reads the default source — against a git-data host that
yields a plausible **empty** result and the conclusion "the boot was dark", which is the wrong
conclusion this batch nearly reached. **P8 says "cannot *silently* read a different source", so the
minimum sufficient fix is to fail loudly**: exit **64** naming `BS_TABLE` when a `--table*` flag survives
into Mode 1 — 64 because it is the script's own usage-error code (`unknown flag → exit 64`, non-numeric
`--limit → 64`), and **not** 2, which the script reserves for the identifier refusal, nor 3, which
means creds-not-injected; a probe that reads the number must not confuse three reasons. The pre-scan that makes the flag work in both modes is the nicer fix and is retained as
the preferred option, but it is not what the property requires. See UC-1 in
`decision-challenges.md`: a reviewer argues this item does not belong in this PR at all.

## Technical Approach

### Implementation Phases

**Phase 0 — preconditions, no edits.** Record the baseline hash (must equal
`3a2392fb5b0d4fae9d4abeaf5ca10ee682430e473dd9eac1ca3d340ef4ce1725`; **record the command whose
output produced it**, rather than carrying it as a bare literal — re-derived at deepen-plan on
this branch, byte-identical to `main`, with the gate's own function:

```bash
source tests/scripts/lib/git-data-birth-readiness-gate.sh
git_data_rung2_user_data_sha256 apps/web-platform/infra/cloud-init-git-data.yml
# → 3a2392fb5b0d4fae9d4abeaf5ca10ee682430e473dd9eac1ca3d340ef4ce1725
```

The function takes the **template path** as `$1` and derives the module dir from it; called bare it
ABORTs "template missing or not supplied" — that is fail-closed, not a broken helper) and the byte
budget. Run the four
git-data suites, the birth-gate suite and the op-contract test green so every later red is
attributable. In S1's Ubuntu container capture `systemctl cat ssh` and `sshd -T` on the real image,
closing the vendor-drop-in residual and pinning the normalization traps against real output.

**Phase 1 — guards first (RED).** The first RED to write is the one that would have caught F11: make
S1's `systemctl` stub return rc=5 `Unit sshd.service not found.` for `sshd` and rc=0 for `ssh`. Then
the mount-root rows against the decided `GIT_DATA_MOUNT_ROOT` seam, then the ownership rows.

**Phase 2 — contracts before consumers (GREEN).** `AuthorizedKeysFile` pin → `write_files` ownership
→ bootstrap chown/chmod split for `/home/git`, `.ssh`, `$REPO_ROOT`, `$HOOKS_DIR` → birth-gate arm +
fixture (must land in the **same commit** as the `owner:` change) → `mkdir` deletions + mount-root
assertions → sshd stage: unit rename, `sshd -T` **before** the action, emit on `sshd_config_warn` →
alert routing + `WARNING_STAGES` → comment corrections.

**Phase 3 — the trap, the docs, the deletion.** `betterstack-query.sh`; the ADR amendment; the
runbook updates; the Article 30 entry; and the **deletion of
`apps/web-platform/infra/git-data-rung2-boot-evidence.env`**.

**Phase 4 — re-measure and hand off.** Re-run the byte budget, re-derive the hash, record it in the
PR body, and confirm the CI freshness step is dormant again.

## Architecture Decision (ADR/C4)

**Amend ADR-149.** Additions: the ssh-unit fleet decision with its `ignore_changes`-vs-ForceNew
table; the socket-activation model (`Accept=no`, no `Conflicts=`, `Type=notify`) that makes the
rename safe on a console-less host; the **evidence-deletion precedent** — that a voided attestation
is deleted, never rewritten, and that the gate's provenance check is a URL *shape* regex which cannot
detect a hand-edited hash; and the finding that the hash binds **source rather than render**, which
is why comment-only edits void it.

The capability-vs-identity correction is **not** added: that wording already exists verbatim in
`tests/scripts/lib/git-data-birth-readiness-gate.sh`, and F6's whole job is to mirror it into the
hash-bound copy. Recording it a third time in the ADR is duplication, not a decision.

No new ordinal is claimed, which removes the collision hazard. If review prefers a standalone ADR for
the fleet decision, the ordinal must be re-derived across **all** `origin/*` refs and re-verified
immediately before merge.

**C4: no change.** Enumerated against all three of `{model,views,spec}.c4`: no external human actor,
external system, container or data store is added; the change emits through the **existing**
`gitDataStore -> betterstack` and `gitDataStore -> sentry` edges; no modelled access relationship
moves — F7/F9 tighten ownership *within* the existing `git` account's boundary. Derived cardinalities
are untouched and `plugins/soleur/test/c4-count-parity.test.sh` is **green on this branch** (10/10,
2026-09-10) as mechanical backing.

## User-Brand Impact

**Tense note, deliberate.** `hcloud_server.git_data` has never existed and holds zero bytes, so every
clause says **will**. Present-tense claims here would repeat the exact claim-class the company
publicly retracted in the #6588 data-protection-disclosure retraction, one document over.

- **If this lands broken, the user will experience** a host that never births, or — worse and
  quieter — one that boots green while `git push` is refused. Two live paths, each pinned by a guard
  row: `root:root 0750` on `/home/git`, `.ssh` or `$HOOKS_DIR` makes them untraversable by the
  account that serves every push; a mount assertion on the wrong path refuses every erasure. A
  boot-brick on a host with no console and no SSH fallback is not recoverable in place.
- **If this does not land, the user will experience** an Article 17 erasure that reports success
  having erased nothing, and a provision that writes their repository onto the root disk where a
  later mount silently hides it — **data loss**, not a false report. Both become reachable at the
  `GIT_DATA_STORE_ENABLED` cutover, and after the birth cost a destructive host replace to fix.
- **If this leaks, the user's source code will be exposed via** the SSH authorization map, which the
  template declared `git:git`, so the constrained principal **would own and could rewrite in place**.
- **If erasure silently no-ops,** the user's repository remains after a deletion reported success. At
  the cutover this falls inside three **already-published** statements — DPD §10.3(b), T&C §14.1b,
  and the in-product Delete Account dialog — with no amendment needed. Deliberately **not** claiming
  these were "accepted money against": the roadmap records beta users 1 and pricing gates 0 of 5, and
  no paying user was confirmed at plan time. An Article 30 register is read by regulators, and
  overstating exposure there is as bad as understating it.
- **The app-layer boundary is NOT closed here, and the plan must not imply otherwise.** After FR4 the
  host stops lying and the **application keeps lying**: `account-delete.ts` catches, calls
  `reportSilentFallback`, and continues the cascade, so the user is still told the account was
  deleted. *(Corrected at review, #8052 observability seat: `sshWithPrivateKeyAuth` resolves to stdout
  only on SUCCESS; on failure the `execFile` rejection carries `stderr`, `code` and the remote refusal
  line, and `reportSilentFallback` ships that Error to Sentry — so refused IS distinguishable from a
  reachability blip in Sentry/Better Stack. What is not closed is the user-facing outcome, which the
  cascade never consults; and no issue-alert rule matches the op, so the event is issue-stream only.)*
  FR17 filed it as #8094, deadlined to the cutover.
- **If the attestation is forged in its own commit,** the birth releases on unrehearsed bytes: Guard 4
  catches only the same-commit shape, and any later evidence-only commit re-blesses a voided file
  through both arms. The run-resolution residual is #8010; it reaches users only through a born host.
- **Brand-survival threshold:** `single-user incident`

## Observability

```yaml
liveness_signal:
  what: "git-data boot-stage rows on Better Stack source 2734275 (t520508_soleur_git_data_prd_logs) via /usr/local/bin/git-data-emit; stage:boot_complete is what the birth job polls"
  cadence: "per-boot (runcmd is once-per-instance)"
  alert_target: "sentry_alert.git_data_boot_warning. STATED HONESTLY: it carries fallthrough_type NoOne against a project with no ownership rule, so it lands in the Sentry issue stream to be read — it does NOT page and does NOT email. Raising that is out of scope; misdescribing it is not."
  configured_in: "apps/web-platform/infra/cloud-init-git-data.yml (emitter + stages); apps/web-platform/infra/sentry/issue-alerts.tf (routing, whose in-list this PR extends)"

error_reporting:
  destination: "Sentry via a baked DSN with no Doppler fallback, plus Better Stack 2734275 as the queryable second copy"
  fail_loud: "a stage row at level:warning or level:fatal; the sshd_config_warn row now also names any hardening directive absent from the sshd -T dump"

failure_modes:
  - mode: "the hardening drop-in is shadowed and not in the effective config"
    detection: "sshd -T is run BEFORE the unit action (systemd owns /run/sshd via RuntimeDirectory= and tears it down on a failed start, so a post-action probe goes silent in exactly this failure) and compared against PasswordAuthentication no + PermitRootLogin prohibit-password, normalized for the without-password rewrite"
    alert_route: "the existing sshd_config_warn stage — which this PR adds to git_data_boot_warning's in-list and to WARNING_STAGES, because today it matches nothing in sentry/ or test/ and reaches no rule at all"
  - mode: "the boot names an ssh unit the image does not ship"
    detection: "the same sshd_config_warn row, with a distinct unit-not-found detail discriminating it from a genuine failure of the action"
    alert_route: "same, once routed by this PR"
  - mode: "an Article 17 erasure is invoked while the store is not mounted"
    detection: "git-data-remove.sh refuses with a named reject and a non-zero exit instead of printing 'not present (no-op)' and exiting 0. The three outcomes are already distinguishable on stderr today; what changes is that the unmounted case stops landing in the second bucket"
    alert_route: "execFileAsync rejects -> account-delete.ts catches -> reportSilentFallback to Sentry (op git-data-bare-repo-erasure). STATED HONESTLY: a Sentry event, NOT a user-visible failure — the delete flow continues and still reports success. Closing that boundary is FR17's cutover-deadlined follow-up, NOT this PR"
  - mode: "a provision is invoked while the store is not mounted"
    detection: "the mkdir is deleted, so the subsequent `exec 9>` redirection fails closed under set -e; the mount-root reject upgrades the raw bash error into a named one"
    alert_route: "same non-zero remote exit, with the same app-layer caveat"
  - mode: "a voided attestation is made to look freshly re-rehearsed"
    detection: "a guard row reds when git-data-rung2-boot-evidence.env is modified in the same commit range as any of the 13 bound files — the gate itself cannot catch this, because its only provenance check is a regex that RUNG2_EVIDENCE_URL looks like an Actions run URL; it never fetches the run"
    alert_route: "two arms, stated honestly: (1) the birth-time arm inside git_data_rung2_rehearsal_gate HOLDs the birth, the rehearsal and the CI freshness step — that is the gate; (2) the PR-range arm in infra-validation.yml deploy-script-tests is ADVISORY (not a ruleset context — measured at deepen-plan), a visible-red signal pre-merge, not a merge block. Multi-commit rebase-merged bypass of arm 1 is #8010's scope"

logs:
  where: "Better Stack 2734275 (hot + s3Cluster archive) via scripts/betterstack-query.sh with BS_TABLE=t520508_soleur_git_data_prd_logs; Sentry issues for the fatal/warning stages"
  retention: "90d"

discoverability_test:
  command: "bash tests/scripts/test-betterstack-query-archive.sh"
  expected_output: "ok   mode 1: a --table flag is never silently discarded"
```

**Why the probe is the suite and not `--help` (Kieran P1-3, folded in at deepen-plan).** The first
draft's probe was `bash scripts/betterstack-query.sh --help`, expecting a usage block. Measured on
this branch: it exits **3** and prints the *creds-not-injected* hint, because the script has **no
`--help` handler at all** (its flag loop is `--since|--until|--grep|--limit|--raw-only|--no-archive|
--table|--table-s3|*→exit 64`) and the credential check at the top of the script runs before any
argument is read. So the probe asserted a feature no FR delivers, and was false on `main` and would
have stayed false after FR13. Two further facts constrain the replacement:

- **Any credential-free invocation of the script exits 3 before parsing.** There is no argument
  that reaches Mode 1 or Mode 2 without `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` set, so the
  CLI contract cannot be probed by calling the script directly from a probe whose first token must
  be an allowlisted verb (`env`/`VAR=x` prefixes are not verbs; `probe-verb-gate.sh` rejects them).
- **The dropped `credentials_required: "none — …"` line was itself a defect.** Preflight Check 10
  treats *any* non-empty, non-placeholder value as a declaration and emits `SKIP-DECLARED` without
  running the command (`plugins/soleur/skills/preflight/SKILL.md`, the `if [[ -n "$CREDS_REQ" ]]`
  branch; the placeholder regex is anchored `^…none…$`, so `none — <prose>` is not a placeholder).
  The field would have waived the very execution it was written to invite. It is removed, not
  reworded: presence is the waiver.

The suite is the honest probe: it fakes the three credentials and shims `curl` at the egress
boundary (`capture_sql`), runs in ~0.2 s with no network, and inside Check 10's bwrap sandbox it
needs only the read-only repo bind plus tmpfs `/tmp` (`mktemp -d -t`), both of which the sandbox
provides. Its verdict line names the Guard 5 property; the row label above is the **canonical
literal** — Guard 5's new Mode-1 case must print exactly `ok   mode 1: a --table flag is never
silently discarded` (two spaces after `ok`, matching the suite's `ok()` helper format), so the
`expected_output` substring match is against that row. **This block now makes no claim about
`main`:** on `main` the suite passes 30/0 and simply has no such row, because the row is FR13's
deliverable; Check 10 executes the probe on the branch at ship time (its PASS row reads "invariant
proven by live execution inside the sandbox"), and an `expected_output` that `main` also satisfies
— e.g. the suite's terminal `0 failed` — would prove nothing about the property this PR adds. The
old probe was different in kind: it asserted a usage block that exists on neither `main` nor the
branch. Reading real git-data rows still needs the team token and remains the job of
`scripts/followthroughs/git-data-rung2-evidence-capture.sh`, declared nowhere here because this
block no longer claims to read them. Check 10's `expected_output` tokenizer splits on `,`, the
word `or`, quotes, brackets and `/` — the row label contains none of these, deliberately; do not
"improve" it with a slash or a quoted flag.

## Encryption Posture

No new persistent store and no new cross-component connection. Every row is an existing ledger entry
restated unchanged for continuity, with this PR's delta named.

```yaml
at_rest:
  - store: hcloud_volume.git_data
    mechanism: plaintext-exception
    evidence: "scripts/encryption-posture-ledger.json, store hcloud_volume.git_data; apps/web-platform/infra/git-data.tf, the hcloud_volume git_data block (format = ext4, no LUKS apparatus)"
    defends_against: "nothing at the volume layer; the pre-cutover rollback backstop pending the DL-2 wipe"
    does_not_defend: "a seized or snapshot-imaged disk exposes any git data resident on this volume"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable:the host has never been born, so no attachment state exists to probe; tracked #6897"
    delta_this_pr: "none — volume, format and attachment untouched"
  - store: hcloud_volume.git_data_luks
    mechanism: luks
    evidence: "scripts/encryption-posture-ledger.json, store hcloud_volume.git_data_luks; the cryptsetup luksFormat/luksOpen calls in cloud-init-git-data.yml, cited by content anchor per cq-cite-content-anchor-not-line-number"
    defends_against: "a seized/RMA'd or snapshot-imaged block volume: unreadable without the Doppler-held passphrase"
    does_not_defend: "a leaked credential, an app-layer read on the unlocked host, or exfiltration via a compromised git-data process"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable:no per-volume host posture probe yet; tracked #6897"
    delta_this_pr: "none directly, but the LUKS stage sits DOWNSTREAM of the sshd stage in the same runcmd chain — which is why the AcceptEnv pin was cut: a 255 there aborts runcmd before LUKS. A regression test asserts the LUKS rows still appear in the fresh rehearsal evidence"
  - store: git_data.baked_credentials_on_host
    mechanism: plaintext-exception
    evidence: "scripts/encryption-posture-ledger.json, store git_data.baked_credentials_on_host; the /etc/default/git-data-betterstack and /etc/default/git-data-doppler write_files at 0600 root:root"
    defends_against: "a file-read-only primitive held by the non-root git account for the two 0600 files; and since #7772 metadata-endpoint reads by any non-root UID"
    does_not_defend: "code execution as root, which reads user_data from the metadata endpoint; and the 0755 sentry_dsn copy the git account can read"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable:the host has never been born"
    delta_this_pr: "narrows it — F7 removes the shortest persistence path for code execution as git (appending to its own authorized_keys), and F9 removes the hook-rewrite path, without adding any baked credential"
in_transit:
  - connection: "connected user's git client -> git-data host"
    enforced_at: "cloud-init-git-data.yml, the /home/git/.ssh/authorized_keys write_files block: three command=... ,no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty forced-command lines"
    tls: "n/a — SSH transport; OpenSSH as shipped by ubuntu-24.04, hardened by /etc/ssh/sshd_config.d/01-hardening.conf"
    cert_verification: "on — host-key verification is the client-side control; the host key is published via doppler_secret.git_data_ssh_host"
    does_not_defend: "an attacker who already holds one of the three private keys; the forced-command separation bounds what each key can do, not who holds it"
    disclosed_as: not-publicly-claimed
    delta_this_pr: "strengthens it — the authorization map becomes root-owned in a root-owned .ssh inside a root-owned home, and the drop-in becomes measurably in effect"
exception:
  justification: "hcloud_volume.git_data is the plaintext rollback backstop for the LUKS cutover, pending the DL-2 wipe. Restated unchanged; this PR neither creates nor extends it"
  tracking_issue: "#6897"
  reevaluate_when: "the git_data_luks cutover is confirmed and the DL-2 wipe runs"
  expires_on: "2026-10-22"
```

## Guard Contract

Anti-vacuity mechanics follow **AP-023**: every floor reports via `printf >&2` + `exit 1` (never
through the suite's own `fail` helper), and the case counter increments at the **call site**, never
inside `$( )`.

### Guard 1 — the erasure and provision paths cannot act on an unmounted store

**Property.** Neither `git-data-remove.sh` nor `git-data-provision.sh` may act, or report success,
unless `GIT_DATA_MOUNT_ROOT` is a mount point; and neither may create the store.

**Assembly.** The chokepoint is the root derivation in the two scripts that mutate repository state.
The roster is the subset of the `templatefile()` map in `modules/git-data-userdata/main.tf` that
derives `REPO_ROOT` **and** performs a create or destroy — stated as an explicit membership rule with
an absolute floor of **2**, because deriving it by grepping the scripts under test would take the
expected set from the artifact under test. `git-data-transport-wrapper.sh` derives `REPO_ROOT` but is
deliberately **out** of this guard: it mutates nothing and already rejects a non-existent repo.
*(Superseded at review — see the note under FR5's "gets no mount assertion" above: it execs
`git-receive-pack`, which writes objects and refs, and it is now IN the guard.)*

**Three fixture constraints the rows depend on (test-design review at deepen-plan):** *(superseded at
implementation: the suites use a REAL mount — `stat -c %m` of the fixture root — and `/proc` for the
off-store rows, not a `mountpoint` stub; `git-data-remove.test.sh` says "NOT A STUB". The exact-match
concern below is what the real instrument gives for free.)* the
`mountpoint` stub prepended to the suites' `env -i PATH=` must **exact-match** its argument
against the fixture's mount root — a prefix match lets row 2 (refusal pointed at `$REPO_ROOT`)
survive, because `$REPO_ROOT` starts with the mount root; row 3 must assert `$REPO_ROOT` is still
**absent** after the run, not the rc alone, since a refusal that fires *after* a re-added `mkdir`
would return the right code having already created the store; and the "mountpoint absent from
PATH" edge needs the curated-symlink PATH named in Test Scenario 13.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the refusal from `git-data-remove.sh` and invoke it against a non-mount holding no repo | RED |
| 2 | Point the refusal at `$REPO_ROOT` instead of the mount root — the shape that looks right and fails **every** erasure closed on a healthy host | RED |
| 3 | Re-add `mkdir -p "$REPO_ROOT"` to `git-data-remove.sh` | RED — *placed ABOVE the path guards (T7/T8/T10 red). At its original position, below the `-d` guard, the mutant is EQUIVALENT (the guard refuses first, the mkdir never runs); measured 29/29 at review.* |
| 4 | Re-add it to `git-data-provision.sh` | RED |
| 5 | Neuter the guard's own dispatch — the per-suite assertion floors in `git-data-remove.test.sh` / `git-data-provision.test.sh` are the dispatch (there is no cross-script roster to neuter: Guard 1 lives in the two per-script suites, and the floor of 2 is "both suites carry the mount rows", asserted by a grep in QG2, not a runtime roster) — delete the floor, zero-case run reports success | RED |
| 6 | Fix `git-data-remove.sh` but leave `git-data-provision.sh` unguarded — the second member must still be checked | RED |
| 7 | MUST-PASS, non-canonical: a mounted store reached through a **symlinked** `$REPO_ROOT` whose target is on the mount | PASS |
| 8 | MUST-PASS, non-canonical: the refusal implemented via a differently-named helper with equivalent semantics and reject text | PASS |
| 9 | Harness row — delete the suite's assertion-count floor so a zero-case run reports success | RED |
| 10 | Harness row — make the fixture's "unmounted" setup silently satisfy the assertion, so every case tests the mounted path | RED |

### Guard 2 — the hardening drop-in is measurably in effect, and the stage cannot go dark

**Property.** The sshd stage asserts the two security-critical directives against the **effective**
`sshd -T` config **before** any unit action; it never reassigns `STAGE`; and every stage value it
emits appears in both the alert routing and the op-contract list.

**Assembly.** Chokepoint: the sshd stage block in `cloud-init-git-data.yml`, bounded by `STAGE=`
above and the `set -e` arming line below. Three producers that must agree: the directive list in the
`01-hardening.conf` `write_files` block, `sentry/issue-alerts.tf`, and `WARNING_STAGES` in
`sentry-git-data-warning-stages-op-contract.test.ts`. Suite: `git-data-runcmd-rehearsal.test.sh`
case S1, whose `systemctl` stub becomes programmable.

**The op-contract cross-file check is one-directional today, so rows 4 and 5 cannot go RED as the
suite stands (Kieran P1-2, folded in at deepen-plan).** Measured against
`sentry-git-data-warning-stages-op-contract.test.ts`: its routing assertion is
`for (stage of WARNING_STAGES) expect(scoped).toContain(stage)` — that proves
`WARNING_STAGES ⊆ tf`, and nothing proves `tf ⊆ WARNING_STAGES` or that the **emitter's** warning
vocabulary is inside either. The file's own header says so ("NOT COVERED: population growth …
adding a THIRD warning stage to the emitter without routing it would not fail here"). So an
implementer who emits `sshd_config_warn` and forgets both the `in` list and `WARNING_STAGES` ships
5/5 green — the exact dark path FR11 exists to close. Row 5 as first written was therefore a row
the guard could not honour.

*Derivation, measured on this branch* (a 25-line node prototype over the real files; the numbers
are what the assertion must reproduce, not a design guess):

```
emitted warning stages (template, comment-stripped, backslash-continuations joined):
  [ betterstack_ingest, gc_timer, gitdata_nftables_metadata_warn, sshd_config_warn ]
git_data_boot_warning `in` list (split on ","):
  [ betterstack_ingest, gitdata_nftables_metadata_warn ]
git_data_boot_fatal `eq` values:
  [ gitdata_runcmd_early, sshd_config, volume_mount, gitdata_doppler_dl, doppler_run,
    luks_open, bootstrap, gc, gc_timer, gitdata_nftables_metadata ]
```

Three things fall out. (1) `sshd_config_warn` is emitted and routed by **nothing** — the F11 claim,
now reproduced by the derivation the test will run rather than by a hand grep. (2) **`gc_timer` is
emitted at `level:warning` (`git-data-emit "SOLEUR_GIT_DATA_GC timer failed to arm" "$STAGE"
warning`, under `STAGE=gc_timer`) and is routed by the FATAL rule's `eq`** — the fatal rule filters
on `stage` only, never on `level`, so a timer-arm failure *pages* today. That is a pre-existing
paging-policy fact this PR must **not** silently change (the test header names moving a stage
across the severity boundary as the change ADR-198 forbids making quietly); it is recorded, named in
the test as a literal, and filed in FR17 for a deliberate decision. (3) The template's emit shapes
are exactly three — a bare literal (`sshd_config_warn warning`), `"$STAGE" warning`, and
`"$${STAGE}_warn" warning` — the last two resolved by the **nearest preceding whole-line `STAGE=`**,
which is the construct the suite already uses for its ordering assertion, so no new extraction idea
is introduced.

**Set-equality assertions to add to the suite** (both directions, over derived sets, never over
`toContain`):

```ts
// (a) tf ⊇ and ⊆ WARNING_STAGES — the one-directional `toContain` becomes set equality.
const inList = scoped.match(/key\s*=\s*"stage",\s*match\s*=\s*"in",\s*value\s*=\s*"([^"]+)"/)![1]
  .split(",").sort();
expect(inList).toEqual([...WARNING_STAGES].sort());

// (b) the EMITTER's warning vocabulary == WARNING_STAGES ∪ the named fatal-routed exceptions.
// Join backslash continuations first: one warning emit's stage+level sit on the continued line.
const joined = cloudInitCode.replace(/\\\n\s*/g, " ");
const emits = [...joined.matchAll(/git-data-emit\s+"[^"]*"\s+("?[^"\s]+"?)\s+warning\b/g)];
// resolve: bare literal → itself; "$STAGE" → nearest preceding STAGE=; "$${STAGE}_warn" → that + "_warn"
// plus the emitter-internal mirror construct `"level":"warning","tags":{"stage":"<x>"`.
const WARNING_EMITS_ROUTED_BY_FATAL_RULE = ["gc_timer"] as const; // pages; see FR17
expect(emittedWarningStages.sort())
  .toEqual([...WARNING_STAGES, ...WARNING_EMITS_ROUTED_BY_FATAL_RULE].sort());
// (c) each named exception really is on the fatal rule — the literal cannot become a dumping ground.
for (const s of WARNING_EMITS_ROUTED_BY_FATAL_RULE)
  expect(scopeResource(tf, "git_data_boot_fatal")).toMatch(new RegExp(`value\\s*=\\s*"${s}"`));
```

Scope discipline: (b) extracts **warning-level emits only** — a regex anchored on the emit call
shape with a literal `warning` level — and never derives the fatal set, so it stays inside the
header's own boundary ("deliberately NOT a general extraction engine" for the nine-fatal
reconciliation). The nearest-preceding-`STAGE=` resolution must run against `cloudInitCode` (the
comment-stripped corpus), for the reason the file already records: a prose line quotes the emit
literal ~400 lines above the real one. **Floor:** (b) must also assert
`emits.length >= 3` — with the regex mis-anchored the derived set is empty and (b) would compare
`[]` against a non-empty list and red anyway, but the floor turns that into a named failure rather
than a confusing diff. After this PR the expected value of (b) is
`[betterstack_ingest, gc_timer, gitdata_nftables_metadata_warn, sshd_config_warn]` and
`WARNING_STAGES` is `[betterstack_ingest, gitdata_nftables_metadata_warn, sshd_config_warn]`.
Rows 4 and 5 are now drivable: emitting a stage absent from the tf list reds (b)/(a); adding it to
the tf list but not `WARNING_STAGES` reds (a); adding it to neither reds (b). The header's "NOT
COVERED: population growth" paragraph is rewritten to say what is now covered and what the
`gc_timer` exception means.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore the bare call naming the `sshd` unit, stub returning rc=5 for `sshd` and rc=0 for `ssh` | RED |
| 2 | Move `sshd -T` to **after** the unit action, then fail the action so `/run/sshd` is torn down — the probe must not be allowed to go silent in the failure it exists to catch | RED |
| 3 | Assign a new `STAGE=` instead of emitting a literal stage string | RED |
| 4 | Emit a stage value absent from `issue-alerts.tf` — reds assertion (b) (emitter set ≠ routed set), and (a) if the value was added to `WARNING_STAGES` alone | RED |
| 5 | Emit a stage value absent from `WARNING_STAGES` — the population growth the test's header said it did not cover; **drivable only via the set-equality assertions (a)+(b) above**, which is why they are part of this guard's deliverable and not optional hygiene | RED |
| 5b | Add `sshd_config_warn` to the tf `in` list but not to `WARNING_STAGES` — the one-directional `toContain` passes this; (a) reds it | RED |
| 5c | Add a stage to `WARNING_EMITS_ROUTED_BY_FATAL_RULE` that the fatal rule does not carry — (c) reds it, so the exception literal cannot absorb an unrouted stage | RED |
| 5d | Move `gc_timer`'s warning emit into `WARNING_STAGES` (routing it to the non-paging rule) without touching the tf — (a) reds it: a paging-policy change cannot ride in as a "fix" | RED |
| 6 | Drop `PermitRootLogin` from the comparison after `PasswordAuthentication` is verified present — a check that stops at the first member is the defect itself | RED |
| 7 | Empty the two-directive list the stage iterates, so the comparison runs over zero directives and passes — the S1 harness's literal expected set (floor 2, per F11(b)) reds it | RED |
| 7b | Positive control for row 2 and row 10 together: contrary drop-in (`PermitRootLogin yes`), programmable stub that returns non-zero for `restart ssh` **and** removes `/run/sshd`; the captured `sshd_config_warn` row's `detail` must name the directive. On a healthy fixture the assertion emits nothing, so "already ran" has no observable without this row | RED |
| 8 | Emit at `level:fatal` — the rung-2 gate contract forbids it | RED |
| 9 | MUST-PASS, non-canonical: a dump rendering `permitrootlogin without-password` and two lowercase `acceptenv` lines — the normalization must accept it | PASS |
| 10 | Harness row — restore the unconditional `exit 0` `systemctl` stub, so no row can distinguish unit names or activation state | RED |

### Guard 3 — the git account cannot rewrite its own authorization map or the hook it is fenced by

**Property.** `git` can neither edit `authorized_keys`, nor replace the directory holding it, nor
write `$HOOKS_DIR`; `$HOOKS_DIR` and `/home/git` remain **traversable** by `git`; `$REPO_ROOT` stays
git-writable; and sshd consults exactly one authorization file.

**Assembly.** Four producers that must agree: the `write_files` `owner:`/`permissions:` on
`authorized_keys`; the ownership of `/home/git` and `/home/git/.ssh`, set in `git-data-bootstrap.sh`
because the authorization-map gate forbids the template naming that literal outside `write_files`;
the bootstrap's chown/chmod calls, which run **after** `write_files` and are the last writer; and the
`AuthorizedKeysFile` pin. A guard reading only `write_files` would miss the last writer.

**Static model vs runtime rows — decided, because rows 5/6/11 are undecidable by text grep.**
`root:root 0750` (row 5, RED) and `root:git 0750` (canonical, PASS) differ only in group, so the
static arm needs a stated model, applied to the **last writer** (the bootstrap's chown/chmod
lines, never the `write_files` declaration alone): the `git` principal is in group `git` and no
other; a path is *traversable by git* iff (owner=git ∧ owner-x) ∨ (group=git ∧ group-x) ∨ other-x,
and *writable by git* iff the same with `w`. The static rows (Guard 3 rows 1–7, 9–12) evaluate that
model over the literals the bootstrap sets. The **runtime** rows — Test Scenarios 8–10 ("git
appends → denied", "mv ~/.ssh → denied", "traverses, writes `$REPO_ROOT`") — need a root context
and a `git` principal, which no suite outside the docker arm has; they run in S1's Ubuntu
container (`useradd git`, `su git -c '…'`), where the bootstrap's ownership lines are applied to
a real `/home/git`, and they are the rows that prove the model rather than restate it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore `owner: git:git` on the `authorized_keys` entry — the constrained principal appending its own key is the shortest persistence path and must be caught **without** any directory swap | RED |
| 2 | Restore `/home/git` to `git`-owned `0750` — the directory-replacement variant | RED |
| 3 | Root-own the file and the home but leave `.ssh` `git`-owned, so `authorized_keys2` can still be created | RED |
| 4 | Fix all three but restore the bootstrap's blanket recursive chown of `/home/git/.ssh` — the later writer must still be caught | RED |
| 5 | Set `/home/git` to `root:root 0750` — not writable, but **not traversable**, so sshd cannot chdir for the forced command | RED |
| 6 | Set `$HOOKS_DIR` to `root:root 0750` — same trap, the directory F9 is about | RED |
| 7 | Set `$HOOKS_DIR` back to git-writable | RED |
| 8 | Over-tighten: make `$REPO_ROOT` root-owned, which breaks provisioning | RED |
| 9 | Remove the `AuthorizedKeysFile` pin | RED |
| 10 | Neuter the guard's own dispatch — check zero paths, exit 0 | RED |
| 11 | MUST-PASS, non-canonical: `$HOOKS_DIR` as `root:root 0755` rather than `root:git 0750` — both are not-writable-but-traversable | PASS |
| 12 | Harness row — delete the suite's assertion floor so a zero-case run reports success | RED |

### Guard 4 — a voided attestation cannot be made to look fresh

**Property.** `git-data-rung2-boot-evidence.env` is never modified in the same change as any of the
13 hash-bound files; it may only be **deleted** there, or created by a rehearsal PR that touches none
of them.

**Assembly.** The chokepoint is the commit range, not a file: the guard quantifies over the 13-file
set derived from the `templatefile()` map plus the module's own `.tf` files, and the evidence path.
**Where it lives (unnamed in the first draft; pinned at deepen-plan — and the obvious home is
advisory, measured).** The only CI step in the neighbourhood, *"Rung-2 evidence freshness"*, sits
in `infra-validation.yml`'s `deploy-script-tests` job, which is **not** a required check: the
"CI Required" ruleset's contexts are `test`, `dependency-review`, `e2e`, `skill-security-scan PR
gate`, `CodeQL` and the guard jobs in `ci.yml` (`gh api repos/jikig-ai/soleur/rules/branches/main`
at deepen-plan lists no `infra-*` or `deploy-script-*` context), and the file's own comments at the
`deploy-script-tests` batteries say "a RED row in THIS job does not block a merge". So a range
check placed there is a visible-red signal, not a merge gate, and the first draft's
`alert_route: "CI, pre-merge"` over-claimed. The guard therefore has **two arms with one
derivation**, in `tests/scripts/lib/git-data-birth-readiness-gate.sh` beside
`git_data_rung2_user_data_sha256()` so the 13-file roster is the same walk and cannot drift from
the hash:

1. **Birth-time arm — the one that blocks.** Inside `git_data_rung2_rehearsal_gate` itself, which
   already runs at the three places that matter (`apply-web-platform-infra.yml`
   `git-data-host-create`, `git-data-rung2-rehearsal.yml`, and the CI freshness step): find the
   commit that last touched the evidence file (`git log -1 --format=%H -- <evidence>`), take
   `git diff-tree --no-commit-id --name-only -r <sha>`, and HOLD if it intersects the 13. HOLD also
   when the checkout is shallow (`git rev-parse --is-shallow-repository` = `true`): provenance
   cannot be read from a depth-1 clone, and the birth job's checkout **is** depth-1 today (its
   `actions/checkout` step carries no `fetch-depth`) — so this PR adds `fetch-depth: 0` to that one
   checkout, and the gate's shallow-HOLD is what makes forgetting it fail closed rather than
   fail open. This arm is what makes the property hold at the interlock the whole plan is about.
2. **PR-range arm — early warning.** The same function over `git diff --name-only
   --diff-filter=AM <range>` (a **deletion**, `--diff-filter=D`, is the permitted shape) from a new
   step immediately before *"Rung-2 evidence freshness"*, with the range shape the workflow's
   `detect-changes` job already uses — `origin/${BASE_REF}...HEAD` on `pull_request`,
   `$BEFORE_SHA HEAD` on push — and **HOLD on an unresolvable base** (that job's comment: "Running
   too much costs CI minutes; running nothing costs the guarantee"). Labeled advisory in its own
   step comment, in the words the file already uses.

**Residual, stated so nobody reads Guard 4 as a proof.** The birth-time arm inspects *one*
commit. A PR that edits a bound file in commit A and the hash in commit B and lands by **rebase
merge** (all three merge methods are enabled on this repo — `gh api repos/jikig-ai/soleur` →
`allow_rebase_merge: true`) presents an evidence commit that touches only the evidence, and
passes arm 1; only the advisory arm 2 sees it, pre-merge. Closing that requires resolving the
run the URL names and binding its head SHA — which is **#8010's** scope, not this PR's. Guard 4
is the structural mitigation for the single-commit shape (squash, the one-shot pipeline's
default), and the plan says so rather than letting "CI, pre-merge" imply a gate that is not
there.

Unit suite: `tests/scripts/test-git-data-birth-readiness-gate.sh` gains the rows below against a
throwaway repository built under `mktemp -d` from the suite's existing `_r2_write_module` fixture
writer, two commits deep, sourcing `plugins/soleur/test/lib/git-fixture-env.sh` first (the #7849
chokepoint: the precedent in `tests/scripts/test-weakness-miner.sh` shows why — an inherited hook
`GIT_DIR` would otherwise send the fixture commits into the developer's real repository; learning
`2026-03-24-git-ceiling-directories-test-isolation.md`). The suite is already registered in
`scripts/test-all.sh` (`run_suite "tests/scripts/git-data-birth-readiness-gate"`), so the new rows
run in the required `test` context without a registration edit; nothing auto-discovers
`tests/scripts/`, so a *new* file there would run in zero runners (#7718) — which is why the rows
go into the existing suite.
This exists because the gate itself **cannot** catch the failure — its only provenance check is a
regex that `RUNG2_EVIDENCE_URL` *looks like* an Actions run URL; it never fetches the run, so editing
the hash and leaving the URL releases the birth on a rehearsal that never ran the shipped template.
This is the highest-consequence property in the batch and previously had no mechanism at all.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Modify `RUNG2_TEMPLATE_SHA256` to the moved digest in the same change as a template edit | RED |
| 2 | Modify any other key in the evidence file alongside a payload-script edit | RED |
| 3 | Neuter the guard's own dispatch — derive an empty bound-file set and exit 0 | RED |
| 4 | Bind only the template and not the nine payloads, so an edit to `git-data-remove.sh` plus an evidence edit passes | RED |
| 5 | MUST-PASS: this PR's own shape — the 13 files change and the evidence file is **deleted** | PASS |
| 6 | MUST-PASS: a rehearsal PR that creates the evidence file and touches none of the 13 | PASS |
| 7 | Harness row — inside every fixture assert `c1 != c2` and `git diff --name-only c1 c2` is non-empty before calling the gate; mutate the fixture's `git commit` to fail silently (a runner with no identity does exactly this) so every HOLD row reads as PASS — the harness must red, not the SUT | RED |
| 8 | Base `0000000000000000000000000000000000000000` (branch-create sentinel) or a shallow clone → named HOLD, distinct from "empty diff" | RED if it passes |
| 9 | MUST-PASS: arm 1 on a repo whose last evidence-touching commit touches only the evidence | PASS |
| 10 | Arm 1 on a squash-shaped commit touching evidence + `git-data-remove.sh` → HOLD | RED if it passes |

### Guard 5 — `--table` cannot be silently discarded

**Property.** A `--table`/`--table-s3` flag is either honoured or refused loudly, in every invocation
mode; no mode discards it.

**Assembly.** `scripts/betterstack-query.sh`'s argument handling has **two** dispatch paths — the
Mode-1 raw-SQL early `exit` and the Mode-2 flag loop — and the flag is honoured in only one. The
roster of modes is derived from the script's own dispatch branches. Suite:
`tests/scripts/test-betterstack-query-archive.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore the pre-fix behaviour: Mode 1 discards the flag and proceeds | RED |
| 2 | Neuter the guard's own dispatch — the mode count is a **literal 2 with a floor** (never derived from the script's own `case`/`if` branches, which would take the expected set from the artifact under test, the shape Guard 1's Assembly forbids); drop the floor, assert over zero modes and exit 0 | RED |
| 3 | Handle `--table` in Mode 1 but not `--table-s3` | RED |
| 4 | Break Mode 2's existing order-independence — the second mode must still be checked | RED |
| 5 | MUST-PASS: `BS_TABLE` set in the environment with no flag, in raw-SQL mode | PASS |
| 6 | Harness row — the Mode-1 rows must run through a direct `bash "$TARGET"` runner that captures **stderr and rc**; mutate that runner to discard stderr and return 0, so the refusal text and rc=64 are unobservable and the row would pass on a script that exits 3 (creds) or 2 (identifier) instead | RED |

## Acceptance Criteria

### Functional Requirements

- **FR1 (F6)** — `git grep -c 'identity-shaped' modules/git-data-userdata/variables.tf` is 0, and the
  block names the three pubkeys as a capability divergence.
- **FR2 (F7 objects)** — the `authorized_keys` `write_files` entry declares `owner: root:root`;
  `git-data-bootstrap.sh` sets `/home/git` and `/home/git/.ssh` to `root:git 0750` and no longer
  chowns them to `git`; `01-hardening.conf` carries `AuthorizedKeysFile .ssh/authorized_keys`.
- **FR3 (F7 gate, atomic)** — in the **same commit** as FR2, the birth gate's ownership arm accepts
  the new owner, its measured-false rationale is corrected, and the fixture in
  `tests/scripts/test-git-data-birth-readiness-gate.sh` is updated. The gate does not HOLD on the
  post-fix template.
- **FR4 (F8)** — `mkdir -p "$REPO_ROOT"` appears in neither `git-data-remove.sh` nor
  `git-data-provision.sh`; both refuse with a named message and non-zero exit when
  `GIT_DATA_MOUNT_ROOT` is not a mount point, before the `readlink` guards;
  `git-data-transport-wrapper.sh` is **not** given a mount assertion.
- **FR5 (F8 seam)** — `GIT_DATA_MOUNT_ROOT` exists with an independent default, `mountpoint` is
  resolved absolutely and fails closed when absent, and all three wrapper suites pass.
- **FR6 (F9)** — `$REPO_ROOT` stays `git`-owned; `$HOOKS_DIR` is `root:git 0750`; the
  `mkdir`/`chown`/`chmod` triple is split; the post-condition assert covers ownership.
- **FR7 (F10)** — all **five** comment sites state what sshd does while preserving the still-true conclusion; `grep -cE 'AcceptEnv (is )?empty|passes (NO|no) client env' apps/web-platform/infra/git-data-{remove,provision,transport-wrapper}.sh` totals 0 after the edit and the corrected wording names `AcceptEnv LANG LC_*` at each site.
  **No `AcceptEnv` pin and no `PermitUserEnvironment` pin is added** — greppable against the drop-in.
- **FR8 (F11 unit + order)** — the stage names the `ssh` unit, and `sshd -T` runs **before** the unit
  action.
- **FR9 (F11 assertion)** — the row names any of `PasswordAuthentication no` /
  `PermitRootLogin prohibit-password` absent from the effective dump, normalized for
  `without-password`.
- **FR10 (F11 emission)** — the row is emitted on the existing literal stage `sshd_config_warn` at
  `level:warning`, `STAGE=sshd_config` is unchanged, and unit-not-found is discriminated in the
  detail.
- **FR11 (F11 routing)** — `sshd_config_warn` is added to `git_data_boot_warning`'s `in` list and to
  `WARNING_STAGES`. Verify the sentry plan shows a **one-value diff**, not a condition-group rewrite:
  `issue-alerts.tf` still carries the **`removed { from = sentry_issue_alert.git_data_boot_warning }` +
  `import { to = sentry_alert.git_data_boot_warning }` pair** that adopted the live rule (there is
  no `moved` block anywhere in the file — the first draft named the wrong construct; corrected at
  deepen-plan against the file), and its own comment records that an earlier edit here would have
  rewritten the live condition-group type.
- **FR11b (op-contract set equality)** — `sentry-git-data-warning-stages-op-contract.test.ts`
  asserts (a) the tf `in` list **set-equals** `WARNING_STAGES`, (b) the emitter-derived
  warning-level stage set set-equals `WARNING_STAGES ∪ WARNING_EMITS_ROUTED_BY_FATAL_RULE`, and (c)
  every member of that exception literal appears as a `value = "<stage>"` on `git_data_boot_fatal`
  (§ Guard 2). The exception literal is exactly `["gc_timer"]` at merge; the header's "NOT COVERED:
  population growth" paragraph is rewritten. Greppable: `grep -c 'toContain(stage)'` on the routing
  `it` is 0 and `grep -c WARNING_EMITS_ROUTED_BY_FATAL_RULE` is ≥ 3.
- **FR12 (evidence deletion)** — `apps/web-platform/infra/git-data-rung2-boot-evidence.env` is
  **deleted**, its content never edited; the CI freshness step is dormant again; the birth gate HOLDs
  on absence.
- **FR13 (`--table`)** — a `--table*` flag surviving into Mode 1 is honoured or refused with
  **exit 64** and a stderr line naming `BS_TABLE`; the runbook records the behaviour. The suite row that proves it
  prints the canonical literal `ok   mode 1: a --table flag is never silently discarded` — this is
  the `discoverability_test.expected_output`, so
  `grep -c 'mode 1: a --table flag is never silently discarded' tests/scripts/test-betterstack-query-archive.sh`
  is ≥ 1 and the suite exits 0. **No `--help` handler is added**: the first draft's probe assumed
  one, none exists, and adding one is scope the property does not need (§ Observability).
- **FR14 (ADR)** — ADR-149 amended per § Architecture Decision, including the source-vs-render
  hashing finding and the evidence-deletion precedent.
- **FR15 (runbooks)** — `git-data-birth.md`'s F8 trap note becomes an assertion note. **The
  DO-NOT-DISPATCH banner is not touched** — #7025's own PR.
- **FR16 (Art. 30)** — the erasure assertion is recorded under the Art. 30(1)(g) limb of the activity
  that actually covers workspace/repository content, naming DPD §10.3(b), T&C §14.1b and the Delete
  Account dialog, **with the accident-to-assertion date**. The consult's "PA-2 §(g)(22)" citation
  does **not** survive checking — `## Processing Activity 2` is *Conversation Data* — and the
  register runs PA-1…PA-35 with no activity plainly owning repository content. Identify the right
  one; if none exists, **that absence is the finding** and the remedy is a new PA (next free
  re-derived at write time, not trusted from this plan).
- **FR17 (deferrals, severities load-bearing)** —

  | Follow-up | Severity + framing |
  |---|---|
  | `cloud-init.yml`, `-registry` sibling templates | Low. **Noisy, not unhardened.** Must not repeat the unreproduced red-drift-guard claim. |
  | `cloud-init-inngest.yml` | **Higher** — its next runcmd emits `inngest-boot-phone-home.sh sshd-restarted`, a positive attestation for an action failing every boot. A false-attestation instrument on a live host, not noise. |
  | `AuthorizedKeysFile` → `/etc/ssh/authorized_keys.d/%u` | Low, filed as **"structural hardening; the hole is already closed"** — not as an open vulnerability. |
  | Post-cutover mapper identity | **Gates the cutover.** Both volumes coexist (#6897, expiring 2026-10-22), so post-cutover a boot could mount the **plaintext** volume at `/mnt/git-data` and erasure would act on the wrong store. Filed at review as **#8101** (with the cutover `hooks/` rsync gap). |
  | App-layer erasure boundary (`account-delete.ts` reports success on refusal) | **P1/P2, deadlined to the cutover.** |
  | Web-host `removeWorkspaceDir` Phase 3 | **P1/P2, NOT P3** — the only item here on the host **serving production now**, against a dialog promising "permanently deleted". File naming the reaper-liveness gap (`orphan-reaper.sh` always `exit 0`s) and the undisclosed ~30 h window. "Bounded" must not be used unqualified. |
  | `git_data_host_replace` has no `environment:` gate while `git_data_host_create` does | Low, noted. |
  | `gc_timer` warning-level emit **pages** via the fatal rule's stage-only `eq` | Low, **policy decision, not a bug report**. Measured at deepen-plan: the fatal rule filters on `stage` and never on `level`, so `git-data-emit … "$STAGE" warning` under `STAGE=gc_timer` lands on the paging rule. Whether a gc-timer arm failure on a fresh host should page is ADR-198's severity-boundary call; this PR pins the current answer as the `WARNING_EMITS_ROUTED_BY_FATAL_RULE` literal so it cannot move silently, and does not decide it. |

- **FR18 (issue hygiene)** — #8043's body is updated to name F11, and states that closing it does not
  mean the erasure guarantee is live: the sequel (rehearsal → evidence PR → #7025 → birth) remains.
- **FR19 (priority coherence)** — resolve the inversion: #8043 is `p1` at `single-user incident` but
  sits in **Post-MVP / Later**, while #7025 — the sequel step that realizes this PR's value — is
  `priority/p3-low`. Add a roadmap row for the git-data cutover naming its legal-activation
  dependency.

### Non-Functional Requirements

- **NFR1** — `RUNG2_TEMPLATE_SHA256` **moves**; the new hash is recorded in the PR body.
- **NFR2** — the evidence file's **content is never edited**. It is deleted (FR12), and Guard 4
  enforces that no change modifies it alongside any of the 13 bound files — at the birth for the
  single-commit shape, and pre-merge (advisory) for the PR range; the rebase-merged multi-commit
  residual is #8010's (§ Guard 4).
- **NFR3** — no rehearsal and no birth is dispatched by this PR.
- **NFR4** — rendered `user_data` stays under 32,768 B with the budget script exiting 0 (baseline
  13,748 B); the delta is reported in the PR body.
- **NFR5** — `cloud-init.yml`, `cloud-init-inngest.yml`, `cloud-init-registry.yml` and
  `cloud-init-grok-dogfood.yml` are untouched.
- **NFR6** — no gate HOLDs on the post-fix template for any reason this PR introduces; the only thing
  holding the birth is the absent evidence, which is correct.
- **NFR7** — the boot introduces no new abort path. The `sshd -t` `exit 1` arm remains the block's
  only one and stays above the new probe; `set -e` still arms at the block's tail; the new calls sit
  above it and carry explicit tolerate arms. The one new bounded wait — up to 90 s on the
  `Type=notify` unit job — is recorded and read from the fresh rehearsal's boot wall-clock delta.

### Quality Gates

- **QG1** — every Guard Contract mutation row is demonstrated in the stated direction; RED rows
  before the fix, PASS rows after.
- **QG2** — the four git-data suites, `tests/scripts/test-git-data-birth-readiness-gate.sh`,
  `git-data-emit.test.sh`, `sentry-git-data-warning-stages-op-contract.test.ts` and
  `tests/scripts/test-betterstack-query-archive.sh` pass.
- **QG3** — `git-data-render-strip-parity.test.sh` and `git-data-template-strip.test.sh` pass.
- **QG4** — `plugins/soleur/test/c4-count-parity.test.sh` stays green (10/10).
- **QG5** — any regex handed to `awk` as a **dynamic string** uses a bracket expression (`[(]`),
  never a backslash escape: this workstation ships `mawk`, CI ships `gawk`.
- **QG6** — the touched suites pass with a **temp root private to this run** (`TMPDIR` per-run), so
  no gate's outcome depends on a sibling worktree
  (`cq-ac-must-not-depend-on-concurrent-sessions`). A shared-`/var/tmp` rc=4 is reported as
  skipped-for-contention and re-run isolated; it never stands as this gate's evidence.
- **QG7** — `infra-validation.yml`'s rung-2 freshness step reports its dormant-by-design message.

## Test Scenarios

1. `git-data-remove.sh` against a non-mount holding no repo → named reject, non-zero; before the fix,
   `not present (no-op)` and exit 0.
2. `git-data-remove.sh` against a **correctly mounted** store → still erases. **Write this first** —
   it is the row that catches a mount assertion pointed at the wrong path.
3. `git-data-provision.sh` against an unmounted root → refuses; before the fix it writes a real bare
   repo onto the root disk.
4. S1 with the stub returning `Unit sshd.service not found.` for `sshd` and rc=0 for `ssh`.
5. `sshd -T` missing a security-critical directive → the row names it.
6. A dump rendering `permitrootlogin without-password` → the comparison passes.
7. The unit action fails and `/run/sshd` is torn down → the assertion has **already run** and still
   reports.
8. `git` appends to `~/.ssh/authorized_keys` → denied.
9. `git` attempts `mv ~/.ssh ~/.ssh.old && mkdir ~/.ssh` → denied.
10. `git` traverses `/home/git`, `/home/git/.ssh` and `$HOOKS_DIR`; writes none of them; writes
    `$REPO_ROOT`.
11. `betterstack-query.sh 'SELECT 1' --table <t>` names that table in the captured SQL, or exits
    **64** with stderr naming `BS_TABLE`. **Pin the rc and the text, not "non-zero":** `capture_sql`
    discards stderr, and the script exits 3 on missing creds and 2 on the identifier check, so an
    unpinned "non-zero" row passes for the wrong reason. Use the direct `bash "$TARGET"` runner shape
    the suite already has for its identifier rows, capturing stderr. Same row for `--table-s3` (Guard 5
    row 3 cannot red without it).
12. **Regression:** the three forced-command lines keep their exact option set (M27 passes); the
    birth gate does not HOLD; `boot_complete` still carries exactly its four booleans; the LUKS stage
    still emits — proving the sshd stage did not abort runcmd before reaching it.
13. **Edge:** `$REPO_ROOT` a symlink onto the mount; `mountpoint` absent from PATH → fails **closed**
    (the fixture needs a **curated PATH of symlinks** — `bash readlink dirname flock rm` — because
    util-linux lives in `/usr/bin` on both the workstation and the runner, so "absent from PATH"
    cannot be produced by trimming); `sshd -T` rc 126/127 **and 255** → could-not-measure, not
    "directives absent" — 255 is what a torn-down `/run/sshd` returns (`Missing privilege separation
    directory`), and classifying only 126/127 would let the post-action ordering of Guard 2 row 2
    emit a row with the wrong cause and stay green; **a "missing directive" fixture sets a
    contrary value** (`PermitRootLogin yes`, `PasswordAuthentication yes`) rather than deleting the
    line, because the 24.04 default `PermitRootLogin prohibit-password` renders identically to the
    hardened value and a deleted line produces a green dump; an empty `01-hardening.conf` → the row
    names **both** directives (that is the assertion, not a floor — the two-directive list is a
    literal with floor 2 in the S1 harness, matching F11(b)'s decision not to walk all nine).
14. **Integration:** re-derive the hash → differs from the deleted evidence's; the rung-2 gate HOLDs
    on absence; the CI freshness step is dormant.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Six separate PRs | Up to six paid rehearsals where one discharges all six. |
| Land F6/F10 separately as "free" | The hash is over **source**, so a comment edit voids the evidence exactly as a code edit does. |
| Edit the evidence to match the moved hash | Makes a void attestation look freshly re-rehearsed — undetectable by the gate, whose provenance check is a URL-shape regex. |
| Keep the evidence file and fix CI to tolerate a stale hash | Weakens the one gate standing between a moved template and a birth. Deleting asserts nothing and keeps both gates fail-closed. |
| Rehearse first, then merge | Impossible: the rehearsal environment allows deployment from `main` only, and the branch cannot merge while the evidence is stale. |
| `mountpoint -q "$REPO_ROOT"` | rc=1 on a correctly mounted host — would fail every erasure closed. |
| `owner: root:root` alone, or `chown root:root /home/git` alone | Each closes one of the two holes. Both, or neither is closed. |
| `root:root 0750` on `/home/git` or `$HOOKS_DIR` | Not writable, but not traversable — breaks the forced command and every push. |
| Pinning `AcceptEnv` empty | Accumulating keyword; both clearing syntaxes exit 255 and abort runcmd before LUKS. |
| A new `STAGE=` for the assertion | De-pages the runcmd item's fatal trap. |
| Minting a new warning stage name | `sshd_config_warn` already exists and is unrouted; reusing it repairs a dark path for free. |
| The erasure outcome token | Three outcomes already distinguishable; the token is unreadable by construction. |
| `ExecMainStartTimestampMonotonic` | Duplicates the existing rc branch and distinguishes two acceptable states. |
| Device identity in the erasure path | Phase-ambiguous across the cutover; belongs at boot, where it already is. |

## Risk Analysis & Mitigation

| Risk | Blast radius | Mitigation |
|---|---|---|
| The mount assertion targets the wrong path → every erasure refuses | Art. 17 non-compliance, inverted | Guard 1 rows 2 and 7; test 2 written **first** |
| An ownership change breaks traversal → every push fails | all connected users | Guard 3 rows 5, 6, 11; test 10 |
| `git` can still append to its own authorized_keys | persistence for code execution as `git` | Guard 3 row 1 — the row the first design lacked |
| `sshd -T` placed after the action goes silent on the failure it exists to catch | false green | Guard 2 row 2; FR8 fixes the order |
| The new row is emitted but routed nowhere | write-only observability | Guard 2 rows 4, 5; FR11 also repairs the pre-existing dark path |
| A voided attestation is edited to look fresh | a birth against an unrehearsed template | Guard 4 — the gate structurally cannot catch this |
| The 90 s `Type=notify` wait stalls the boot above LUKS | delayed boot | NFR7; read the wall-clock delta from the fresh rehearsal |
| A seventh item arrives mid-flight | another voided rehearsal | The batch closes at six; a seventh goes to the follow-up set unless measured before the rehearsal dispatch |

## Dependencies & Prerequisites

The sequel is out of scope and runs in this order — **and step 1 needs more than a token**, which the
first draft did not hand off:

1. A fresh rung-2 rehearsal, dispatched **from `main`** (the environment allows no other branch),
   confirm token `REHEARSE-GIT-DATA`, `dry_run=false`. The workflow runs `permissions: contents: read`
   and **cannot commit** — it uploads the evidence as an **artifact**. The evidence PR therefore
   consists of: download the artifact from run *N*, add
   `apps/web-platform/infra/git-data-rung2-boot-evidence.env`, and set `RUNG2_EVIDENCE_URL` to
   `https://github.com/jikig-ai/soleur/actions/runs/N`. The full artifact is not just the hash — it
   is four `QUERY:` blocks carrying the rehearsal host-name literal, plus `RUNG2_SENTRY_CROSSCHECK`,
   `RUNG2_EVIDENCE_URL` and `RUNG2_VAR_DIVERGENCE`.
2. **#7025** — clear the DO-NOT-DISPATCH banner, as its own PR touching nothing else.
3. Only then the birth dispatch.

**#8010** remains the reason a green rung-2 gate does not mean a rehearsal passed. **#6897** — the
plaintext-volume exception, unchanged. **Art. 32 re-instatement:** the #6588 retraction withdrew four
git-data Art. 32 measures as statements about today; the cutover checklist must re-instate them, or
it ships a host whose published Art. 32 description is still retracted.

## Open Code-Review Overlap

`None.` `gh issue list --label code-review --state open --limit 200` was queried and every planned
path checked against the issue bodies with `jq --arg`.

## Domain Review

**Domains relevant:** engineering, legal, product

### Engineering

**Status:** reviewed. The CTO consult and a five-agent panel measured against a live `ubuntu:24.04`
container and this worktree. Between them they rejected four of the six original fixes, then found
the corrected plan unmergeable, F7 still insufficient, the `sshd -T` ordering wrong, and the new
stage's routing absent. All folded in above with their measurements.

### Legal

**Status:** reviewed. Three **already-published** statements cover the bare-repo store at the
cutover with no amendment needed (DPD §10.3(b), T&C §14.1b, the Delete Account dialog, bridged by the
privacy policy's "Workspace data" definition). **None is false today** — the host is unborn and
"workspace data" resolves to the serving host's `/workspaces/<id>/` — so **no correction is owed**.
One qualifier the consult's framing missed and this plan records: the safety today comes from an
**empty store**, not from `GIT_DATA_STORE_ENABLED` — `removeGitDataRepo` is deliberately gated on
`GIT_REMOVE_SSH_PRIVATE_KEY`, not the flag, so the app already attempts the call and swallows the
result. No breach-notification obligation arises: a failure to erase is Art. 5(1)(e)/17
non-compliance, not an Art. 4(12) breach, and no processing has occurred. The alpha-tester annex
(`status: draft-requires-counsel-review`) and the DPA template (`not_yet_executed: true`, zero
register rows) are **unexecuted** and are not exposures.

*Draft material requiring professional review; not legal advice.*

### Product

**Status:** reviewed — **signed off with three blocking conditions**, all now discharged in the plan:
the false `alert_route` claim is restated truthfully and the boundary filed (FR17); the legal
reasoning is qualified; and the deferral severities are corrected, including re-filing the web-host
sibling off P3. Advisory items also folded in: the priority inversion (FR19), QG6, the tense
corrections, and dropping the unverified "accepted money against" claim.

### Product/UX Gate

Not applicable — no path in `## Files to Edit` matches a UI surface.

## GDPR / Compliance Gate

Fires: F8 is an Article 17 erasure path. `/soleur:gdpr-gate` runs inline against this plan and the
FR/AC set before implementation. The legal consult covers the register and disclosure questions;
findings are carried in FR16 and FR17.

## Infrastructure (IaC)

**Terraform changes.** `modules/git-data-userdata/variables.tf` — comment only.
`sentry/issue-alerts.tf` — one value added to an existing rule's `in` list. No resource, provider,
variable or output added, removed or retyped; no new `TF_VAR_*`, no new secret.

**Apply path.** **None for the git-data host** — it does not exist, so there is nothing for a config
change to reach; the template becomes live only at the gated birth. The Sentry change applies on
merge via `apply-sentry-infra.yml` as an in-place update to an alert rule's value list. One coupling
to note rather than assume: `git_data_boot_warning` carries `frequency_minutes = 31` and git-data-emit
sends one shared message per stage, so all boot rows share an issue group — a third value on the `in`
list can consume a dedupe window an existing warning would otherwise have used. `runcmd` is
once-per-instance, so practical exposure is one boot.

**Distinctness / drift safeguards.** `hcloud_server.git_data` carries `ignore_changes = [ssh_keys]`
and deliberately **not** `[user_data]`, so `user_data` stays ForceNew — which is what makes the
pre-birth window the only cheap one. NFR5 keeps the four sibling templates untouched.

**Vendor-tier reality check.** No vendor resource is created; the new routing is a value on an
existing rule.

## Files to Edit

| Path | Items | Hash-bound |
|---|---|---|
| `apps/web-platform/infra/cloud-init-git-data.yml` | F7 (`owner:`, `AuthorizedKeysFile`), F11 | yes |
| `apps/web-platform/infra/git-data-remove.sh` | F8, F10 | yes |
| `apps/web-platform/infra/git-data-provision.sh` | F8, F10 | yes |
| `apps/web-platform/infra/git-data-transport-wrapper.sh` | F10 (×3) only — **no** mount assertion | yes |
| `apps/web-platform/infra/git-data-bootstrap.sh` | F7 (home/.ssh ownership), F9 | yes |
| `apps/web-platform/infra/modules/git-data-userdata/variables.tf` | F6 | yes |
| `apps/web-platform/infra/sentry/issue-alerts.tf` | FR11 | no |
| `apps/web-platform/test/sentry-git-data-warning-stages-op-contract.test.ts` | FR11 | no |
| `tests/scripts/lib/git-data-birth-readiness-gate.sh` | FR3; Guard 4 (both arms, sharing the hash function's 13-file walk; arm 1 inside `git_data_rung2_rehearsal_gate`) | no |
| `tests/scripts/test-git-data-birth-readiness-gate.sh` | FR3 fixture; Guard 4 rows (throwaway repo via `git-fixture-env.sh`) | no |
| `.github/workflows/infra-validation.yml` | Guard 4 PR-range arm, placed before *Rung-2 evidence freshness*, labeled advisory; QG7 unchanged | no |
| `.github/workflows/apply-web-platform-infra.yml` | one line: `fetch-depth: 0` on the `git-data-host-create` job's checkout, so Guard 4's birth-time arm can read provenance (the arm HOLDs on a shallow clone, so omitting this fails closed) | no |
| `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` | Guards 2, 3 | no |
| `apps/web-platform/infra/git-data-{remove,provision,transport-wrapper}.test.sh` | Guards 1, 3 | no |
| `scripts/betterstack-query.sh`, `tests/scripts/test-betterstack-query-archive.sh` | FR13, Guard 5 | no |
| `knowledge-base/engineering/architecture/decisions/ADR-149-*.md` | FR14 | no |
| `knowledge-base/engineering/operations/runbooks/{git-data-birth,betterstack-log-query}.md` | FR15, FR13 | no |
| `knowledge-base/legal/article-30-register.md` | FR16 | no |

## Files to Delete

| Path | Why |
|---|---|
| `apps/web-platform/infra/git-data-rung2-boot-evidence.env` | Void by construction once the template moves. Deleting is the only honest state and the only mergeable one — see § The merge interlock. The sequel re-creates it from a real rehearsal. |

## Files Explicitly NOT Edited

| Path | Why |
|---|---|
| `cloud-init.yml`, `-inngest`, `-registry`, `-grok-dogfood` | Inert or ForceNew on live hosts; grok-dogfood has no ssh action (NFR5). |
| `apps/web-platform/server/{account-delete,git-data-replication,git-auth}.ts` | The app-layer erasure boundary is real and **deliberately** out of scope — FR17 files it, deadlined to the cutover. Named here so the omission is a decision, not silence. |
| `apps/web-platform/server/workspace.ts` | The live sibling defect; its own P1/P2 issue (FR17). |
| the DO-NOT-DISPATCH banner in `git-data-birth.md` | #7025's own PR. |
| the alpha-tester annex, the DPA template | Both unexecuted; not exposures. |

## References & Research

`#8043`, `#8009`/PR `#8035`, `#8010`, `#7025`, `#6897`, `#7772`/ADR-198, `#6588` (the retraction
precedent), ADR-115, ADR-149, ADR-152, ADR-068;
`knowledge-base/project/plans/2026-07-27-chore-git-data-pre-birth-hardening-plan.md` (R16);
`docs/legal/data-protection-disclosure.md` §10.3(b), `docs/legal/terms-and-conditions.md` §14.1b,
`apps/web-platform/components/settings/delete-account-dialog.tsx`;
learnings `2026-03-19-openssh-first-match-wins-drop-in-precedence.md`,
`2026-07-30-four-ways-a-green-guard-asserted-nothing-rung2-route.md`,
`2026-07-29-every-guard-i-fixed-this-session-was-narrower-than-the-claim-it-carried.md`,
`2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument.md`,
`2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`.

### Measurements taken at plan time

- `git-data-userdata-budget.sh` → `stored=13748 B / cap=32768 B (headroom 19020 B)`.
- `plugins/soleur/test/c4-count-parity.test.sh` → 10/10.
- `cloud-init-inngest-bootstrap.test.sh` → 163/163 `OK`; the brief's "red on main" did not reproduce.
- Live `ubuntu:24.04` + `openssh-server`: `ssh.socket` `Accept=no`, no `Conflicts=`; `ssh.service`
  `Type=notify`, `RuntimeDirectory=sshd`, `Alias=sshd.service` with the multi-user symlink absent;
  `mountpoint -q /mnt/git-data/repositories` → rc=1 on a mounted store; `AcceptEnv` bare and
  `AcceptEnv ""` → `sshd -T` rc=255; `AcceptEnv FOO` accumulates; `permitrootlogin without-password`
  in the dump; `authorizedkeysfile .ssh/authorized_keys .ssh/authorized_keys2`;
  `permituserenvironment no` already default; `/etc/login.defs` `HOME_MODE 0750`.
- `exec 9>` on a path under an absent directory → rc=1 under `set -e` (the `mkdir` deletion is the
  load-bearing control).
- `grep -rn sshd_config_warn apps/web-platform/infra/sentry/ apps/web-platform/test/` → **no matches**.
- `tests/scripts/lib/git-data-birth-readiness-gate.sh` → HOLDs unless `owner: git:git`; HOLDs on an
  absent evidence file; HOLDs on a template reference to the authorized_keys literal outside
  `write_files`.
- `gh api repos/jikig-ai/soleur/environments/web-platform-infra-apply/deployment-branch-policies` →
  `total_count: 1`, `main`.
- `article-30-register.md` → PA-1…PA-35; `## Processing Activity 2` is *Conversation Data*.
