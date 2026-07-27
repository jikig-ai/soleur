# Tasks — chore(6982): git-data pre-birth hardening + observability

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

> **IaC routing note.** Every service-state change referenced below (`systemctl` units, mounts,
> package installs) lives inside `cloud-init-git-data.yml`'s `runcmd:`/`bootcmd:` or inside
> `git-data-bootstrap.sh` — both rendered into `hcloud_server.git_data`'s `user_data` by
> `templatefile()` and applied by `terraform apply`. git-data has **no `remote-exec` provisioner and
> no human SSH path** by design, so an operator-run step here is not merely discouraged, it is
> impossible. Where a task quotes such a command it is describing template content, not an operator
> action. See the plan's `## Infrastructure (IaC)` section (plan Phase 2.8 output).

Derived from
[`knowledge-base/project/plans/2026-07-27-chore-git-data-pre-birth-hardening-plan.md`](../../plans/2026-07-27-chore-git-data-pre-birth-hardening-plan.md)
**after** the v1 → v2 plan-review revision (R1–R38). Read the plan's
`## Plan Review Revisions` table before starting — four P0 findings changed the design, and several
tasks below exist only because a v1 task was **wrong**, not merely incomplete.

**Scope fence:** this ships the hardening and the interlock release, **not the birth**. No task
creates `hcloud_server.git_data`.

**Standing guardrails for `/work`:**
- **Do not add a roadmap row** (CPO C7) — the roadmap explicitly carves internal tooling out of
  customer-facing rows.
- **AC25's mutation arms are non-negotiable** (CPO C2). If a mutation arm proves hard to build, that
  is a **blocker, not a trim**.
- Infra suites do **not** run under `scripts/test-all.sh`. A new `*.test.sh` without a matching
  `run: bash …` step in `.github/workflows/infra-validation.yml` gates **nothing**, and the orphan
  reporter is advisory and returns 0 — nothing will tell you.
- Every byte of `cloud-init-git-data.yml` **and** `git-data-bootstrap.sh` (via
  `base64encode(file(…))`) is an input to a ForceNew attribute. Free to edit now; a replace dispatch
  after birth.

---

## Phase 0 — Probes and preconditions (no product code)

- [ ] 0.1 **W0 probe (blocking).** Mint a throwaway `read` service token scoped **exactly as
      `doppler_service_token.git_data` is** (single config, `prd_git_data`). Run
      `doppler run --project soleur --config prd -- env` and **grep the output for
      `GIT_DATA_LUKS_KEY`**. Exit status is not the question — a CLI that silently resolves to an
      empty `prd` view exits 0 with the key absent, which is the dark boot. Record verbatim.
- [ ] 0.2 Prove the readiness gate currently **HOLDs** (the RED half):
      `source tests/scripts/lib/git-data-birth-readiness-gate.sh && git_data_birth_readiness_gate apps/web-platform/infra/cloud-init-git-data.yml; echo $?` → `1`.
- [ ] 0.3 Measure the baseline `user_data` render **with Terraform's own `base64gzip`**, not
      `gzip -9` (which overstates headroom on a hard gate). Record bytes + headroom.
- [ ] 0.4 Classify every `runcmd` item must-abort / must-tolerate — **including the items W4/W5/W6
      add**. Start from the nine-item table in the plan; item #1 (the sshd restart) is the real
      hazard.
- [ ] 0.5 Confirm `export HOME=/root` reaches the runcmd shell before any `doppler` invocation
      (`cloud-final.service` synthesises no `$HOME`; three prior dark boots came from this).
- [ ] 0.6 Record the verification that ADR-149 item 6 (firewall entailment) is **already
      discharged** on main — evidence, not assumption.
- [ ] 0.7 Pin `$BS_TABLE` explicitly and confirm the Mode-1 raw-SQL query form (the ACs cannot use
      `--grep`).

## Phase 1 — Terraform contract

- [ ] 1.1 Hoist `local.git_data_private_ip = "10.0.1.20"`; have `hcloud_server_network.git_data.ip`
      read it. Do **not** reference the computed attribute from the new secret.
- [ ] 1.2 Add `doppler_secret.git_data_ssh_host` — project `soleur`, config `prd`, name
      `GIT_DATA_SSH_HOST`, `value = local.git_data_private_ip`, `visibility = "masked"`.
      **No `depends_on`** (R9 — v1 applied the rationale ADR-149 Residual 2 explicitly corrected;
      this secret is the antidote, not the arming switch). **No
      `lifecycle{ignore_changes=[value]}`** (R38 — diverges from every sibling and would pin a stale
      IP).
- [ ] 1.3 Amend `variables.tf`'s `git_data_server_type` description: corrected D1 claim + the
      finding that `cpx22` is now the only sensible **orderable** option.
- [ ] 1.4 **Register the new address at all SIX sites, in this same commit** (R6): the birth
      `-target` list (18 → 19) and its prose; `_GIT_DATA_BIRTH_ALLOW`'s `def allow: [ … ]`; the
      gate's **separate presence loop**; the gate's two prose counts;
      `GIT_DATA_BIRTH_TARGET_BASES` plus the two "eighteen members" comments; the
      `rest_thirteen_except`/`rest_thirteen_with` fixture helpers. Add to
      `OPERATOR_APPLIED_EXCLUSIONS`. **The address joins the PRESENCE half, never the entailed
      loop** (entailed demands `creates == 1` → permanent wedge).

## Phase 2 — The emitter

- [ ] 2.1 `write_files:` **one** script `/usr/local/bin/git-data-emit` (R13) — Sentry store-API emit
      from the **baked** `${sentry_dsn}`, **no Doppler fallback**, applying the ADR-147 sanitiser
      chain **plus** the value-based redactor **internally on every path**.
- [ ] 2.2 Add `curl` to `packages:`; emitter degrades silently if absent (R23).
- [ ] 2.3 Add a `bootcmd:` beacon (R23) — `packages:`/`write_files` failures currently leave the ssh
      daemon up and emit nothing.
- [ ] 2.4 **Add `git_data_boot_fatal` to `apps/web-platform/infra/sentry/issue-alerts.tf`** (R1).
      Justify `event_frequency` in a comment — **do not copy `value = 1`**; on a fresh per-deploy
      group it means ">1" and a single event does not page.
- [ ] 2.5 Land `${sentry_dsn}` in **non-comment** template text (the sentinel).

## Phase 3 — Fail-closed boot

- [ ] 3.1 First runcmd item: `export HOME=/root`, `STAGE=runcmd_early`, `on_err` +
      `trap on_err EXIT` **with the `rc=$?; [ "$rc" -eq 0 ] && exit 0` guard** (R7), then emit
      `runcmd-entered` **and assert 2xx**, failing loudly otherwise (R8).
- [ ] 3.2 Add an `sshd -t` config validation before the sshd restart item (R16).
- [ ] 3.3 Arm `set -e` after 0.4's classification; explicit `|| true` + naming comment per
      must-tolerate item.
- [ ] 3.4 `STAGE=` progression, with `doppler_dl` immediately above the
      `sha256sum` → `tar xzf` → `chmod +x` block.
- [ ] 3.5 **Arm a heredoc-local `STAGE=` and trap inside `LUKSEOF`** (R2) — `luksOpen` runs in a
      child bash; without this a LUKS failure is indistinguishable from a Doppler scope failure.
- [ ] 3.6 Disarm before handing to the bootstrap; re-arm with a bootstrap-specific trap (same `rc`
      guard) capturing 20 redacted lines.

## Phase 4 — Boot-completion signal

- [ ] 4.1 **Teach the existing `log()` to emit** (R14). `git-data-bootstrap.sh` step 7 already
      asserts all four properties fail-loud; the only defect is that `log()` goes nowhere off-box.
      Route it through `git-data-emit` on FATAL paths, and add one success line emitting
      `stage:boot_complete` with the four booleans. **This is ~a tenth of the work v1 described.**
- [ ] 4.2 Include guest `df%` for **`/mnt/git-data`** (the live root) in the payload.
- [ ] 4.3 No repo paths, no workspace/user UUIDs in any payload.

## Phase 5 — Store maintenance

- [ ] 5.1 `git-data-bootstrap.sh`: add `receive.autogc false`, `gc.auto 0`, `gc.autoDetach false`,
      `pack.windowMemory`, `pack.packSizeLimit`, `pack.threads 1`, `pack.deltaCacheSize`,
      `core.bigFileThreshold` — **and add each to the existing fail-loud re-assert block**.
- [ ] 5.2 `git-data-gc.service`/`.timer` — weekly, `MemoryMax=` / `CPUQuota=` /
      `IOSchedulingClass=idle` / `Nice=19`, `OnFailure=` → `SOLEUR_GIT_DATA_GC` routed to the
      **Phase-2.4 Sentry rule**. Body over **`/mnt/git-data/repositories`**, **unreachable objects
      only**, under `flock`. Emits `df%` each run.
- [ ] 5.3 `mkfs.ext4 -q -O quota,project` on the LUKS volume. **Ship the flag; DEFER the `prjquota`
      mount option** (R31) — the flag is migration-forcing, the mount option is not and adds a new
      boot-failure mode on a host with no console.
- [ ] ~~5.4 store-monitor timer~~ — **CUT (R11)**: it polled the empty-by-construction LUKS volume.
- [ ] ~~5.5 recurrence poller~~ — **CUT (R12)**: no generic poller exists to extend.

## Phase 6 — Concurrency and workflow wiring

- [ ] 6.1 **Post-apply boot-signal poll in `git_data_host_create`, `if: always()`** (R20) — the real
      ADR-149 item-4 discharge. Fail the job if `stage:boot_complete` does not arrive, or arrives
      with any false assertion.
- [ ] 6.2 `01-hardening.conf`: add `MaxStartups`, `MaxSessions`; tighten `ClientAliveInterval`
      300 → 60. Keep the `01-` prefix (OpenSSH is first-match-wins; Hetzner ships
      `50-cloud-init.conf`). Declarative `write_files`, never `sed`.
- [ ] 6.3 `git-data-replication.ts`: module-level in-process semaphore bounding concurrent
      provision+replicate pairs. **Fail-soft on queue timeout** (git-data is an overlay; session end
      must never block). Emit a `reportSilentFallback`-class event when shedding.
      `server/concurrency.ts`'s `acquireSlot` is **not** reusable — it is DB-backed.

## Phase 7 — Records

- [ ] 7.1 Amend ADR-068's addendum (D1-corrected + D-SIZE) and ADR-149 (checklist item 8, the D-HB
      Alternatives amendment, the Residual 2 disposition, **and Residual 1 as partially discharged**
      by the boot-completion emit, R30).
- [ ] 7.2 Record **D-EMIT as an ADR-147 addendum** (R30) — that ADR is literally "boot-stage
      diagnostics live in baked host scripts".
- [ ] 7.3 Art. 30 register: wrap PA-1 (g)(13) and PA-2 (g)(17) in the **DRAFTED / NOT-YET-ACTIVE**
      pattern PA-2 already carries; amend PA-8 (c)(ii)/(d)/(f)/(g) for the additional emitting host.
- [ ] 7.4 `expenses.md`: add the missing **plaintext** volume row, bring both volume rows to `0.62`,
      strike the "no net-new" claim for the pre-cutover period, keep all git-data rows
      `approved-not-billing`, **and amend the third site of the D1 claim** (R27). Check whether
      §Downstream Consumers requires a `finance/cost-model.md` refresh (R38).
- [ ] 7.5 `model.c4`: two new edges (`gitDataStore -> betterstack`, `gitDataStore -> sentry`) with
      TARGET-state honesty markers, **and two description amendments — the `betterstack` ELEMENT
      description as well as the `betterstack -> founder` relationship** (R24). Run
      `c4-code-syntax.test.ts` + `c4-render.test.ts`. `views.c4` needs no change (both endpoints are
      already in the `containers` view — R25).
- [ ] 7.6 `git-data-birth.md`: **retain** the DO-NOT-DISPATCH banner, rewrite its release condition
      to name the W12 rehearsal evidence, add sizing + emitter-verified rows, add a post-birth
      verification section, note the ForceNew hazard on **both** files.
- [ ] ~~7.7 readiness-gate GREEN arm~~ — **CUT (R15)**: already exists.
- [ ] 7.8 File the deferred tracking issues: A10 quota assignment (**must name the missing T&C/AUP
      storage-limit clause as the blocker** — CPO C5); A11 Residual 3 (**bound to
      `GIT_DATA_STORE_ENABLED`**, plus the three public-doc LUKS paths per R33); the banner-clear
      follow-up (AC32); the multi-sentinel gate hardening (R26); the ADR-143 `cx22` phantom SKU +
      stale `cx23` row; the registry-volume ledger cell. **Separately** (CPO C6, do NOT scope in):
      the blog-post accuracy defect and the cloud-side backup-responsibility gap.
- [ ] 7.9 Create the follow-through probe with the **three real secret names** and **exit 2 for
      unborn** (R4, R21); post the #6548 and #6975 comments.

## Phase 8 — Rehearsal (W12), before PR-ready

- [ ] 8.1 Rung 1: render the real template, execute `runcmd` in the pinned Ubuntu 24.04 container
      harness, capture every payload. T5/T6/T15/T16/T17/T18 run here.
- [ ] 8.2 Rung 2: boot the rendered template once on a throwaway `cpx22` **outside** the
      `hcloud_server.git_data` address; observe the artifacts off-box; destroy.
- [ ] 8.3 Pin the evidence per AC31. If rung 2 is unreachable in-session, say so explicitly and move
      the requirement onto the banner-clear follow-up issue.

## Phase 9 — Verification

- [ ] 9.1 Walk all 34 acceptance criteria; record each result.
- [ ] 9.2 `bash apps/web-platform/infra/run-registered-suites.sh` green, and every new `*.test.sh`
      has a `run: bash …` step in `infra-validation.yml`.
- [ ] 9.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (**not** `npm run -w` — the
      repo root declares no `workspaces` field).
- [ ] 9.4 `python3 scripts/lint-encryption-posture.py`, and confirm **no `expires_on` changed**.
- [ ] 9.5 `terraform plan` on the per-merge path shows **zero** git-data creates.
