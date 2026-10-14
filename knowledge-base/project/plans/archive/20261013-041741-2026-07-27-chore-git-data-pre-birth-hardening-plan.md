---
date: 2026-07-27
issue: 6982
type: chore
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
branch: feat-one-shot-6982-git-data-pre-birth-hardening
closes: 6982
---

# chore(6982): git-data pre-birth hardening + observability

> **SCOPE FENCE.** This PR ships the **hardening and the interlock release**, not the **birth**.
> No step in this plan creates `hcloud_server.git_data`, and no acceptance criterion requires a
> live git-data host. The birth remains a separate, operator-authorised `workflow_dispatch`
> (`apply_target=git-data-host-create`, `confirm=BIRTH-GIT-DATA`) governed by
> `knowledge-base/engineering/operations/runbooks/git-data-birth.md`. Dispatching a host birth is
> a production write and is out of scope for this plan (`hr-menu-option-ack-not-prod-write-auth`).

## Deepen-Plan Pass (v2 → v3)

**Deepened:** 2026-07-27 · **Halt gates evaluated:** 4.5 · 4.55 · 4.6 · 4.7 · 4.8 · 4.9 · 4.10

| Gate | Verdict |
|---|---|
| 4.5 Network-outage deep-dive | **PASS** — triggered on `SSH`/`firewall`/`timeout`; `## Hypotheses` answers all four L3→L7 layers with named artifacts and honest N/A opt-outs. |
| 4.55 Downtime & Cutover | **PASS (new section added)** — the trigger words are present but the subject host **does not exist**, so no serving surface can go offline. Recorded explicitly rather than left implicit; see `## Downtime & Cutover`. |
| 4.6 User-Brand Impact | **PASS** — section present, concrete artifact + vector, threshold `single-user incident`, no placeholders. |
| 4.7 Observability | **PASS** — all 5 fields present with non-placeholder values and children; `discoverability_test.command` contains **zero** `ssh ` occurrences. |
| 4.8 PAT-shaped variable | **PASS — one match adjudicated as a false positive**, and it surfaced a real design constraint (D1 below). |
| 4.9 UI-wireframe artifact | **SKIP** — no path in Files-to-Edit/Create matches any UI-surface term or glob. No `.pen` required. |
| 4.10 Encryption Posture | **PASS** — `at_rest` (3 stores), `in_transit` (3 connections) and `exception` all present; every required sub-field populated; `does_not_defend` non-empty everywhere; the one `plaintext-exception` carries `tracking_issue` **and** `expires_on`. |

### D1 — Gate 4.8 adjudication, and the constraint it exposed

The sweep matched exactly one line: `var.betterstack_logs_token`, via the broad
`var\.[a-z_]*_(pat|token)` arm. **False positive** — `hr-github-app-auth-not-pat` governs *"infra-time
GitHub writes"*, and this is a **Better Stack Logs ingest** token with no GitHub surface. No GitHub
auth of any kind appears in this plan. Recorded rather than silently dismissed, because the gate is
fail-closed by design and the next reader deserves the adjudication.

**But chasing it exposed a genuine drift my own v2 fixes introduced** — exactly the post-edit
self-audit class this phase exists to catch. R3 cut Better Stack from the boot path and R12
re-routed the gc fault event to Sentry; taken together those imply *"no Better Stack on git-data at
all"*, which would have made `var.betterstack_logs_token` dead. Before deleting it I checked whether
the follow-through probe could then run on Sentry — **and it cannot**:

- `.github/workflows/scheduled-followthrough-sweeper.yml` passes `SENTRY_AUTH_TOKEN` (sourced from
  `SENTRY_IAC_AUTH_TOKEN`), and `scripts/sentry-issue.sh`'s own header records that this token
  **403s** on `event:read`. The script needs `SENTRY_ISSUE_RO_TOKEN`, which the sweeper does **not**
  pass.
- The sweeper **does** pass `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}`, and those work.

**So the channel split is refined, not collapsed** — and the refinement is forced by a real
constraint rather than taste:

| Signal | Channel | Why |
|---|---|---|
| Early boot stages (`runcmd_early` … `doppler_dl`) and **all fatals** | **Sentry only** | Baked DSN, no Doppler dependency — works precisely when Doppler is the broken stage. R3's objection stands in full, and this is the interlock's sentinel. |
| **Boot-completion** (`stage:boot_complete`) and **gc faults** | **Sentry *and* Better Stack** | Both are **post-Doppler by construction** — the bootstrap only reaches its final stage after `doppler run` has succeeded, and the gc timer runs long after boot. So the ingest token *is* readable here, and R3's pre-Doppler objection does not apply. |
| The follow-through probe's read path | **Better Stack** | The only channel the sweeper can authenticate (above). This is what makes AC20's *"the sweeper can actually execute it"* satisfiable at all. |

**Consequences, all folded in below:** `var.betterstack_logs_token` stays (the 4.8 match is
legitimate); `doppler_secret.git_data_betterstack_logs_token` in `prd_git_data` **returns**, gated on
W0's probe result; and the birth `-target` set therefore goes **18 → 20**, not 18 → 19. That count
correction propagates to all six registration sites (R6) and to AC8.

### D2 — Residual: git-data has one paging vendor, not two

`model.c4` records the Sentry/Better Stack duplication as deliberate — *"a SECOND-SOURCE vendor that
pages independently precisely so a Sentry outage is survivable… Do not 'consolidate' the two — the
redundancy is the design."* On git-data, **only Sentry pages**: the Better Stack copy is queryable
(and is what the follow-through probe reads) but nothing alerts on it, because R12 established there
is no generic disk/gc recurrence poller to extend and this plan does not build one.

The second paging source for this host is the `git_data_prd` heartbeat — **deferred to #6548** by
D-HB. So between this PR and #6548, a Sentry outage concurrent with a git-data boot failure is
unobserved. Stated as an accepted residual rather than hidden: the window is bounded by #6548, the
host is unborn for all of it, and the alternative (arming a beat that goes green on a host whose
LUKS never mounted) is worse than the gap.

### D3 — Precedent-diff gate (Phase 4.4): no novel patterns

Checked the four pattern-bound behaviours this plan introduces against in-repo precedent:

| Pattern | Precedent | Divergence |
|---|---|---|
| Boot-fatal emitter + `trap on_err` + `STAGE=` | `cloud-init.yml`'s `_emit`/`on_err`; `cloud-init-inngest.yml`'s phone-home | **One** deliberate divergence: git-data's emitter is a `/usr/local/bin/` **binary**, not an inline shell function, so the LUKS heredoc's child bash can call it (R2). Recorded in Phase 3.5. |
| Per-host scoped-config ingest token | `doppler_secret.registry_betterstack_logs_token` (`zot-registry.tf`) | None — same shape. |
| Bounded maintenance unit | `soleur-host-bootstrap.sh` / `inngest-bootstrap.sh` `CPUQuota=`/`MemoryMax=` units | None — this is the in-house idiom for bounding a background job on a small host. |
| Scheduled work | Phase 4.4's Inngest-vs-GH-Actions check | **N/A** — the gc timer is a host-resident systemd timer on a host with no app context and no Inngest connectivity (deny-all, private-net only). ADR-033's Inngest preference does not reach it. |

No novel pattern is introduced, so no "pattern is novel — scrutinise" flag is needed.

### D4 — Verify-the-negative pass (Phase 4.45)

Negative security claims in the plan body were re-grepped against the implementation:

- *"the LUKS passphrase is **never** in `user_data`"* — **confirmed**. `git-data.tf`'s templatefile
  vars pass `doppler_token` (a scoped read token), never `GIT_DATA_LUKS_KEY`; the passphrase is
  fetched at boot via `doppler run`.
- *"git-data has **no** `remote-exec` provisioner and no human SSH path"* — **confirmed**.
  `git-data.tf` carries no `provisioner` block; all three `authorized_keys` entries are
  `command=`-forced with `no-pty`; the login shell is `git-shell`.
- *"`grep -rn "MaxStartups\|MaxSessions"` returns **zero hits anywhere in the tree**"* — **confirmed**
  at plan time; this is a claim `/work` should re-run rather than trust, since a sibling PR could
  land the first occurrence.
- *"`pii_scrub_string` does **not** scrub a bare UUID"* — **confirmed** by the CLO panel against
  `vector.toml`'s transform bodies. This is the claim AC22 exists to defend against.

### D5 — Post-edit self-audit (Phase 4.45)

Swept the plan for references to symbols the v2 edits dropped. One hit, now fixed: the Observability
`logs:` field and Phase 5.2's `alert_route` still described a Better-Stack-only steady-state path
after R12 re-routed gc faults to Sentry — resolved by D1's explicit split. No references remain to
`git-data-store-monitor.*`, `git-data-phone-home`, or `git-data-redact` outside the "cut in v2"
annotations that deliberately name them.

## Downtime & Cutover

**Gate 4.55 fired on keyword match and is discharged by the subject, not by an argument: there is no
serving surface to take offline.** `soleur-git-data` **has never existed** — an authenticated
`terraform state list` returns zero git-data members.

- **Infra reboot/replace class:** not triggered. This PR changes `hcloud_server.git_data`'s
  `user_data` (ForceNew) and `variables.tf`'s `server_type` **description** — on a resource that is
  absent from state, so Terraform plans nothing. No running host is power-cycled, replaced, or
  resized. AC7 asserts mechanically that the per-merge plan shows **zero** creates for any git-data
  address, which is the same property from the other direction.
- **Database lock class:** not triggered — no migration, no DDL, no backfill.
- **Deploy/router class:** not triggered — no container swap, no tunnel or router change, no
  connector restart. git-data carries no `cloudflared` (ADR-096).

**The one adjacent surface, and why it is also zero-downtime:** W6's client-side limiter edits
`git-data-replication.ts`, which ships in the web container. It is fail-soft by construction — on
queue timeout it sheds rather than blocking, because git-data is an overlay and session end must
never wait on it. Its deploy is the ordinary container roll, unchanged by this PR.

**Zero-downtime posture for the birth itself** (out of scope here, recorded for the dispatch): a
birth is **additive-only** — the gate demands zero destroys, zero volume destroys, zero firewall
rules and zero reboot-forcing updates on any live host, and refuses otherwise. The blue-green
question does not arise because there is no old host to cut over from.

## Plan Review Revisions (v1 → v2)

Panel: Fable advisor consult (ADR-083 Step 4.5) · kieran-rails-reviewer · architecture-strategist ·
spec-flow-analyzer · code-simplicity-reviewer · CPO (sign-off, threshold `single-user incident`).
Every row was verified against the worktree by the reviewer that raised it.

<!-- lint-infra-ignore start -->
| R | Finding | Sev | Disposition |
|---|---|---|---|
| R1 | **The Sentry fatal channel matches NO alert rule.** `apps/web-platform/infra/sentry/issue-alerts.tf` holds 28 narrowly tag-filtered `sentry_issue_alert` resources, no catch-all, zero `git.data` hits — and the file was in neither Files list. The repo already documents this class in its `web_terminal_boot_fatal` comment: the web host's whole runcmd stage set *"matches NO alert rule, so those events are write-only today."* Four of six declared `alert_route`s were false. | **P0** | **Fixed.** `issue-alerts.tf` added to *Files to Edit*; a `git_data_boot_fatal` rule is a Phase-2 deliverable with AC33. The `event_frequency` threshold is flagged load-bearing: `value = 1` works for the web host only because its group is always already hot, and git-data's first-ever boot fatal is by definition the first event in its group. |
| R2 | **`STAGE=luks_open` has no producer.** `luksOpen` runs inside `doppler run … -- bash -s <<'LUKSEOF'` — a **child bash**. The parent's `STAGE` and `on_err` do not cross the exec boundary, and no phase armed anything inside the heredoc. A failed `luksOpen` and a W0 scope failure would both surface as `STAGE=doppler_run`, collapsing the plan's single most important discriminator into another mode. | **P0** | **Fixed.** Phase 3.5 arms a heredoc-local `STAGE=`/trap. Only possible because the emitter is a `write_files` binary under `/usr/local/bin/` (unlike the web host's non-exported inline `_emit`) — a child process can call it. |
| R3 | **The Better Stack channel is dark for the stages it was specified to cover.** The token cannot be baked (metadata-API retrievable) and the Doppler CLI does not exist until `STAGE=doppler_dl`, so a `doppler-cli-install-FAILED` marker to Better Stack was unreachable *by construction* — the exact "dark by construction" trap ADR-149 item 2 names and W0 exists to avoid. Neither W0 branch resolved it. | **P0** | **Fixed by cutting, not patching.** Boot fatal + boot-completion → **Sentry only** (baked DSN, works when Doppler is the broken stage). Better Stack keeps **steady-state only**. This removes the Better Stack credential from W0's critical path. **Corrected against what shipped:** the resolution's last clause claimed the secret was deleted *entirely* — it was not, and could not be, because R3 itself keeps Better Stack for STEADY STATE (the gc emits) and that needs the token. `doppler_secret.git_data_betterstack_logs_token` ships in `git-data-luks.tf`, is one of the twenty `-target`s, and is one of the fifteen members of the birth gate's presence loop. What was cut is the BOOT-time Better Stack marker, not the secret. |
| R4 | **The follow-through probe names a credential that does not exist.** `BETTERSTACK_LOGS_QUERY_TOKEN` appears nowhere; `scripts/betterstack-query.sh` needs `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` (already wired in the sweeper), and `BETTERSTACK_LOGS_TOKEN` is **ingest-only (write)** per that script's own header. `sweep-followthroughs.sh` on an unknown `secrets=` name fails and `return 0`s — issue left open, no comment. Fully silent. | **P0** | **Fixed.** Directive corrected to the three real names. Worse than the name: AC20's proven-RED arm was being satisfied by a *credential* failure rather than "host unborn", so the probe could never flip to pass. AC20 now asserts the **sweeper can execute it**, not merely that the script exits non-zero locally. |
| R5 | **AC4 forbade the escape the design requires.** `grep -c '%{' … returns 0`, but the prescribed `curl -w 'http=%%{http_code};…'` probe **contains** `%{` as a substring. The plan's own *Template escaping* paragraph stated both halves without noticing they contradict. Any correct implementation failed AC4. | **P0** | **Fixed.** AC4 is now `grep -cP '(?<!%)%\{'`, matching a bare Terraform directive but not the doubled `curl` form. |
| R6 | **The birth gate has a FOURTH registration site.** `git-data-host-birth-gate.sh` carries `_GIT_DATA_BIRTH_ALLOW` (18-member *permission* set) **and** a separate hardcoded 13-member presence loop (*completeness* set) that `terraform-target-parity.test.ts` never extracts. A three-of-four edit is green — the new address would be *permitted* but not *required*, so a birth whose Doppler write is absent passes the gate, reinstating ADR-149 Residual 2's harm behind a PASS. The plan's own mitigation ("the parity test catches a partial edit") is what made this dangerous. | **P0** | **Fixed.** The plan now names **six** sites (adding the presence loop, two gate prose counts, and the fixture helpers `rest_thirteen_except`/`rest_thirteen_with`), states explicitly that the new address joins the **presence** half (the entailed loop would reproduce ADR-149's *"Too strict → a permanent wedge"*), and AC8 requires a parity assertion that extracts the presence loop. |
| R7 | **`trap on_err EXIT` fires on exit 0.** No `rc=$?` guard was specified, and Phase 3.4 re-armed a bootstrap trap that survives to the successful end. As written, **every healthy boot emits `level=fatal`** — inverting AC25's whole point. | **P0** | **Fixed.** Phases 3.1/3.4/3.5 specify the `rc=$?; [ "$rc" -eq 0 ] && exit 0` guard, and T17 asserts a healthy boot emits **zero** fatals. |
| R8 | **T6 certified the dark boot as passing.** *"with the emitter's DSN empty → the abort still happens"* asserts exactly the state the interlock exists to prevent. No AC asserted the emitter is present, executable and **delivering** before `set -e` is armed. If the emitter binary is missing when the trap fires, `on_err` gets rc 127/126 and (per the web-host precedent's trailing `\|\| true`) proceeds silently to `exit 1`. | **P0** | **Fixed.** T6 replaced by its inverse, and a **delivery assertion** lands at `STAGE=runcmd_early` (AC34): emit `runcmd-entered`, check the curl returned 2xx, fail loudly if not. |
| R9 | **`depends_on = [hcloud_server.git_data]` applied the rationale ADR-149 explicitly corrected.** That residual says of exactly this reasoning: *"`depends_on` guarantees the key **co-lands with** the server, and co-landing is precisely the harmful state."* Correct for the remove key (the arming switch); inverted for `GIT_DATA_SSH_HOST`, which is the **antidote**, not the poison — and is not even a secret, just the static literal. | **P1** | **Fixed — dropped.** The secret now lands dependency-free in Terraform's first wave, which *also* removes the only edge that could ever drag `hcloud_server.git_data` into an upstream `-target` closure, strengthening AC16's no-wedge property. |
| R10 | **`discoverability_test` does not execute.** `betterstack-query.sh` exits 3 without a `doppler run -p soleur -c prd_terraform --` wrapper; `--grep` compiles to `raw LIKE '%…%'` — the bare-substring form the plan's own `failure_modes` **forbids**; and the default window is 1 h, so a once-per-boot marker is invisible to a probe running at `earliest=merge+1d`. Item 4 was a prose comment naming a `host_id` the plan never defines. | **P1** | **Fixed.** Commands wrapped, `--since` pinned, field isolation switched to Mode 1 raw SQL with the `$BS_TABLE` / `$BS_TABLE_S3` archive arm (Mode 1 does **not** auto-add it, so a boot event older than the ~40-minute hot window is otherwise invisible). Sentry item rewritten around `scripts/sentry-issue.sh`, a GET-only no-SSH reader that exists. |
| R11 | **The disk monitor watched the wrong filesystem.** W5.3 polled `/mnt/git-data-luks` every 15 min — but `git-data-provision.sh` and the transport wrapper both default `REPO_ROOT=/mnt/git-data/repositories`, and the plan's own GDPR §B says the LUKS store is *empty* pre-cutover. 96 events/day about a filesystem that cannot change, while the one that fills goes unwatched. | **P1** | **Fixed by cutting.** Disk state rides the **boot-completion emit and the gc run** — zero new mechanism, correct mountpoint. `git-data-store-monitor.{sh,service,timer,test.sh}` and the recurrence poller are cut. Dissolves R12. |
| R12 | **Phase 5.5 was not a grep addition.** `scheduled-zot-restart-loop.yml` delegates entirely to `scripts/zot-restart-loop-alarm.sh`, a zot-specific alarm with boot_id scoping, restart-count plateaus and a NIC discriminator. There is no generic disk-recurrence poller to extend. | **P1** | **Moot** — cut with R11. The `SOLEUR_GIT_DATA_GC` fault event's `alert_route` is corrected to the R1 Sentry rule rather than a poller that does not exist. |
| R13 | **Three emitter scripts weakened the PII control.** AC24 ("any log excerpt passes through the redactor first") was a *convention* two other scripts had to remember. Both in-repo precedents (`cloud-init.yml`'s `_emit`, `cloud-init-registry.yml`'s `post()`) are **one** thing that redacts inline on every path. | **P1** | **Fixed.** Consolidated to a single `git-data-emit` that redacts internally on every path — making AC24 **structural** rather than conventional, from less code. One script, one suite, one CI registration. AC23's two-arm redactor assertion survives inside it. |
| R14 | **Phase 4.1 was ~90 % already implemented.** `git-data-bootstrap.sh` step 7 already asserts, fail-loud, all four things the plan proposed as new work (`mountpoint -q` ×2, `[[ -x $PRE_RECEIVE ]]`, the `core.hooksPath` equality). The only defect is that `log()` goes nowhere off-box. | **P1** | **Fixed.** Phase 4.1 rewritten as *"teach one existing function to emit"* plus one success line — roughly a tenth of the described work. The "augment-then-fail-closed" discussion dissolves with it. |
| R15 | **Phase 7.7 was already done.** `tests/scripts/test-git-data-birth-readiness-gate.sh` already carries the `RELEASED` arm plus interpolation-beside-comment and beside-escape arms; AC2's arms likewise already exist. | **P2** | **Fixed.** Phase 7.7 deleted; AC2 deleted as ceremony (it asserts existing green). |
| R16 | **`systemctl restart sshd` is the real `set -e` hazard — and W6 makes it worse.** It is runcmd item #1, and this PR adds `MaxStartups`/`MaxSessions` to the sshd drop-in in the same change that arms `set -e` over the restart. A malformed directive → failed restart → aborted runcmd → LUKS never opens. Phase 0.4 also said "every **existing** runcmd item" while W4/W5/W6 add new ones. | **P1** | **Fixed.** Phase 3.2 adds `sshd -t` before the restart; Phase 0.4's scope widened to items this PR *adds*; the nine-item classification table inlined so it cannot be skipped. |
| R17 | **AC22's UUID assertion was a substring proxy with no RED arm**, and its fixture pointed at the empty LUKS volume so it would pass vacuously. The sanitiser chain ends `tail -c 180`, so a truncated-but-still-identifying UUID prefix survives a literal grep. | **P1** | **Fixed.** AC22 asserts a UUID **shape** regex, fixtures at `/mnt/git-data/repositories/<uuid>.git` (matching `git-data-provision.sh`), and carries a mutation arm. |
| R18 | **AC9 was wrong on its premise.** `heartbeat-reprovision-parity.test.ts` reads `apply-web-platform-infra.yml` at three call sites — a file this PR **does** edit. And "passes unchanged" is not something `bun test` reports. | **P1** | **Fixed.** Replaced with the mechanical form: `git diff origin/main -- plugins/soleur/lib/heartbeat-manifest.ts` is empty. |
| R19 | **No AC caught the zero-of-three registration case.** AC8 asserted the three lists agree *with each other*; adding the resource and touching none of them is fully silent (the parity census does not cover general resources, and an untargeted resource is never planned). The plan named this class in *Research Insights* and then did not guard it. | **P1** | **Fixed.** AC8 gains an arm asserting every `doppler_secret.*`/`betteruptime_*` address declared in `git-data.tf` appears in either the birth target set or `OPERATOR_APPLIED_EXCLUSIONS`. |
| R20 | **No reader for the boot-completion emit.** The birth job's only post-apply step is a text summary, and its own comment says *"A green apply is NOT a green boot — and for THIS host there is currently no boot signal at all."* The plan shipped ADR-145 R2–R5's **producer half only**; R2–R5 is a *poll inside the birth job* with `if: always()`. | **P1** | **Fixed.** A post-apply poll with `if: always()` is added to the `git_data_host_create` job (Phase 6.3) — the honest item-4 discharge. Credentials and query tooling already exist, so it costs one step. |
| R21 | **The follow-through's exit code contradicts the repo's own contract.** The precedent documents `0=PASS / 1=FAIL / 2=TRANSIENT`. "Unborn" is textbook TRANSIENT; using 1 would post a **daily FAIL comment** from `merge+1d` until the birth, byte-identical in kind to a genuine post-birth failure — and `REOPEN_MAX` caps only the closed path. | **P1** | **Fixed.** Unborn → **exit 2**; AC20 updated. |
| R22 | **Partial birth re-opens exactly what W8 closes.** `git_remove_ssh_private_key` is already one of the 18; `git_data_ssh_host` is the new 19th. A partial birth landing the server + remove key but not the ssh-host secret puts `removeGitDataRepo` back on the throw path — un-completable by hand. The plan analysed partial birth and never connected it to W8's guarantee. | **P1** | **Fixed.** AC35 pins the ordering; the risk row names the coupling. |
| R23 | **No pre-`runcmd` beacon, and `curl` is not in `packages:`.** `packages:` is `[git, util-linux, cryptsetup]`, yet the whole emitter chain depends on curl. A death in `packages:`/`write_files` leaves sshd up (so the reachability probe goes green) and emits nothing. | **P1** | **Fixed.** `curl` added to `packages:`; a `bootcmd:` beacon added (the web host has one for this exact reason); the emitter degrades silently if curl is absent. |
| R24 | **`model.c4`'s `betterstack` ELEMENT description asserts a fact D-HB falsifies** (*"…is now armed via the ADR-117 measure-then-arm gate"*), and the plan targeted a different string (the `betterstack -> founder` **relationship** description). | **P2** | **Fixed.** Phase 7.4 names both strings. |
| R25 | **`views.c4` citation was wrong** — the `containers` view includes `gitDataStore`, `betterstack` **and** `sentry`, so both edges render there; the plan justified the Sentry edge via the `context` view, which does **not** include `gitDataStore`. Right conclusion, wrong evidence — and the plan claimed "verified rather than assumed", which makes the citation the deliverable. | **P2** | **Fixed.** |
| R26 | **A12's argument against splitting is dissolvable.** The interlock is a one-bit latch by construction; a second sentinel (the boot-completion marker) and a third (`doppler_secret.git_data_ssh_host` in `*.tf`) is ~5 lines of bash and makes the hold survive a split. Independently, sequencing the emitter PR **last** preserves the hold across a split with no gate change at all. | **P2** | **Adopted in part.** Still atomic (CPO endorsed), but the verdict is rewritten: atomicity is chosen for review coherence and the shared forcing function, **not** because a split forfeits the interlock — it does not, if sequenced. The multi-sentinel gate hardening is filed as a follow-up, since it strengthens the latch for every future PR. |
| R27 | **AC14's grep self-matched the plan file** (four unqualified occurrences), and Phase 7.3 never assigned the third site of the D1 claim (`expenses.md`). | **P1** | **Fixed** — `--exclude-dir` added; Phase 7.3 names the D1-claim amendment alongside the row edits. |
| R28 | **AC16's command cannot return what it claims** — case-sensitive, and it would match only the `name = "GIT_DATA_SSH_HOST"` line, never the `value =` line the AC is trying to pin. | **P1** | **Fixed** — the AC greps the resource block, not the token. |
| R29 | **D-SIZE argument 1 is overstated.** *"One vCPU serialises the gc timer against `git-receive-pack`"* is undercut by W4's own `IOSchedulingClass=idle` + `Nice=19` + `CPUQuota=`, which are exactly a serialisation mitigation. | **P2** | **Fixed** — restated as *bounded, not eliminated* (`Nice` does not preempt; `CPUQuota` caps gc's share without bounding receive-pack latency). Argument 2 (destructive replace) carries the decision alone. |
| R30 | **D-EMIT had no ADR home**, and ADR-149 **Residual 1** got no disposition. | **P2** | **Fixed** — D-EMIT recorded as an **ADR-147 addendum** (that ADR is literally *"boot-stage diagnostics live in baked host scripts"*). Residual 1 recorded as **partially discharged** by the boot-completion emit — the first guest-side evidence for this host. |
| R31 | **The `prjquota` mount option is not in the mkfs flag's irreversibility class.** The flag is migration-forcing (adding it later needs a replace **plus** an rsync of every user's objects); the mount option is not, does nothing until projects are assigned (deferred, and legally blocked), and adds **a new way for the mount to fail at boot** on a host with no SSH and no console. | **P2** | **Adopted.** Ship `mkfs.ext4 -O quota,project`; **defer** `prjquota`. |
| R32 | **`git-data-bootstrap.sh` is ALSO ForceNew** — it enters `user_data` via `base64encode(file(…))`. The plan's ForceNew discussion named only the YAML, so the warning banner would have gone on the wrong file. | **P2** | **Fixed** — stated, and the banner goes on both. |
| R33 | **CPO C1 (blocking): the public LUKS claim.** The identical present-tense claim W10 fixes internally is **published** at `docs/legal/privacy-policy.md`, its mirror `plugins/soleur/docs/pages/legal/privacy-policy.md`, and `docs/legal/data-protection-disclosure.md` — and GDPR §F said flatly *"no public-document amendment is required"*, defended only for the emitter addition. | **P1** | **Fixed, narrowly.** The public sentence is predicated on **stored** data, so it goes false at the **cutover**, not at the birth — one step later than the internal register, which is a claim about the *volume*. §F corrected to *"not required at birth; **required before the cutover flag flips**"*, and the three paths join the existing A11 cutover-bound tracking issue. No public-doc edit in this PR. |
| R34 | **CPO C1(iii): the plan contradicted itself on which volume holds data at birth.** *Encryption Posture* called plaintext `hcloud_volume.git_data` "the Phase-2 store"; the *Research Reconciliation* table recorded #6976 finding it **vestigial** with reclaim targeting `/mnt/git-data-luks`. Both cannot be true, and the answer determines whether W10 is needed and when the public claim triggers. | **P1** | **Fixed** — resolved against the code in the *Precision note* (`REPO_ROOT=/mnt/git-data/repositories`, the plaintext volume, per `git-data-bootstrap.sh` and `git-data-provision.sh`); the #6976 reading is corrected to "vestigial **after** the cutover, live before it", and W5's reclaim retargeted accordingly. |
| R35 | **CPO C3: User-Brand Impact understates itself.** `ensure-workspace-repo.ts` states the invariant git-data ⊇ the GitHub clone, and GitHub is *"strictly BEHIND the user's latest committed tip on git-data."* git-data holds the **sole copy** of the delta between a user's last GitHub push and their latest worktree state — not a lost replica, lost work with no other copy. | **P1** | **Fixed**, plus the merge-time (zero — host unborn, 0 beta users) vs birth-time (all-users) separation CPO asked for. |
| R36 | **W0's probe asserted the wrong thing.** Exit status is not the question — a CLI that silently resolves to an empty `prd` view exits 0 with `GIT_DATA_LUKS_KEY` **absent**, which is the dark boot. | **P2** | **Fixed** — the probe greps the resulting environment for the key name, under a token scoped exactly as `doppler_service_token.git_data` is. |
| R37 | Ceremony ACs: several restate phase instructions or assert that untouched tests still pass. | **P2** | **Adopted in part.** Cut AC2, AC17, AC19, AC21. **Kept** AC14/15/27/28/29 — at this threshold the prose-drift and record-keeping criteria are the deliverable's only mechanical trace, and R27 showed AC14 catching a real missed site. Kept the load-bearing halves of AC11/AC12. |
| R38 | Minor, all fixed: measure AC3 with Terraform's `base64gzip` default level, not `gzip -9` (overstates headroom on a hard gate); `lifecycle{ignore_changes=[value]}` on the new secret diverges from every sibling and would pin a stale IP — dropped; `$BS_TABLE` pinned explicitly; `expenses.md` §Downstream Consumers requires a `finance/cost-model.md` refresh on a category subtotal shift; `terraform-target-parity.test.ts` prose says "eighteen" in two places and must move to nineteen; the `arm_one` step is gated `if: steps.ssh_token_gate.outputs.ssh_apply_skip != 'true'`, so the ADR-149 amendment says "every merge **on the normal path**". | **P2** | **Fixed.** |
<!-- lint-infra-ignore end -->

**CPO sign-off: APPROVED WITH CONDITIONS.** C1 (R33/R34) and C2 (AC25 non-negotiable — if a mutation
arm is hard to build that is a blocker, not a trim) are blocking; C3–C7 are folded in above and into
*Alternatives*/*Files*. **C7 is a standing guardrail for `/work`: do not add a roadmap row** — the
roadmap explicitly carves internal tooling out of customer-facing rows.

> No `spec.md` exists for this branch, so no `lane:` could be carried forward — defaulted to
> `cross-domain` (TR2 fail-closed). The default is also the correct value: Engineering, Legal and
> Operations all returned findings.

## Overview

`soleur-git-data` is declared in IaC and **has never existed**. Its birth route merged on
2026-07-27 (`git-data-host-create`, ADR-149, commit `ddbb70703`) and is held by a mechanical
birth-readiness interlock — `tests/scripts/lib/git-data-birth-readiness-gate.sh` refuses to plan
while `apps/web-platform/infra/cloud-init-git-data.yml` contains no non-comment `${sentry_dsn}`
terraform interpolation.

The interlock exists because of one measured property:

> **A green `terraform apply` and a dark host are indistinguishable for git-data.**

This plan discharges that interlock and, in the same merge, lands the changes whose correction cost
rises sharply the moment the host exists.

**The forcing function, stated precisely** (this replaces a weaker claim in the plan's first draft).
It is **not** true that a `server_type` change is uncorrectable after birth. The
`git-data-host-replace` job plans `-replace='hcloud_server.git_data'`, and its own stock-preflight
error text says so: *"changing the type is a cost/HA decision (#6463)… `var.git_data_server_type`
has no dispatch input and no Doppler key — it is edited in `variables.tf` and MERGED to main."*
What is true, and is the actual forcing function:

- `hcloud_server.git_data` deliberately carries **no** `lifecycle.ignore_changes = [user_data]`, and
  `user_data` is **ForceNew**. So **every** cloud-init edit — the emitter, the `set -e` trap, the
  sshd stanza, the `mkfs` flags — costs a full `git-data-host-replace` after birth.
- That replace is a **destroy-then-create of the host holding every connected user's source code**,
  with both volumes and the LUKS passphrase preserved *by omission* and ADR-115 Residual 1 standing
  (the guest's convergence is unprovable, and git-data is barred from the reboot primitive).
- Pre-birth the same edits cost **zero**: there is no host and no data.

So the discipline is not "impossible later" but "**free now, and a destructive dispatch later**" —
and, critically, the moment the sentinel threads, the route is live and the only remaining hold is a
prose banner, which ADR-149's own Alternatives table rejects as *"held until the first person who
reads the runbook and not the plan."*

**Authoritative scope source.** ADR-149 carries an explicit *"Interlock release checklist —
#6982 inherits this"* (7 items). That checklist, not the issue body, is the contract. It contains
two items the issue body does not mention (item 5, `GIT_DATA_SSH_HOST`; item 6, the firewall
entailment correction), and its own text warns *"#6982 could have satisfied every listed item and
still shipped this."* Two further items were surfaced by the domain panel and are folded in below
(W10, the Art. 30 present-tense encryption claim; and the Phase-0 Doppler scope probe).

### The workstreams

| # | Workstream | Source | Cost of getting it wrong post-birth |
|---|---|---|---|
| W0 | **Probe: `doppler run` config scope mismatch** (see below — unlisted P0) | CTO panel | Dark boot, today, on the first dispatch |
| W1 | Off-host emitter: baked `${sentry_dsn}` fatal channel + baked Better Stack stage markers + a **boot-completion** emit | Issue item 1 · ADR-149 §1, §2, §4 | Replace dispatch |
| W2 | ~~Create + arm the heartbeat~~ → **DEFERRED**, superseded by W1's boot-completion emit | Issue item 2 · #6548 | — (see D-HB) |
| W3 | `set -e` + `trap on_err EXIT` + `STAGE=` over the Doppler download runcmd | Issue item 3 | Replace dispatch |
| W4 | git gc/pack tuning + a bounded maintenance timer | Issue item 4 | Replace dispatch |
| W5 | Reclaim (unreachable objects only) + store-fullness observability + `prjquota` option preservation | Issue item 5 | `mkfs` flags: replace **+ data migration** |
| W6 | sshd `MaxStartups`/`MaxSessions` + tightened `ClientAlive*` + a client-side concurrency limiter | Issue item 6 | sshd half: replace dispatch |
| W7 | `server_type` sizing decision — reconcile ADR-068 D1 against the 2026-07-27 brainstorm | Issue item 7 | Replace dispatch (store + CAS fence offline) |
| W8 | Produce `GIT_DATA_SSH_HOST` (`doppler_secret.git_data_ssh_host`) | ADR-149 §5 / Residual 2 | 100 % false Art. 5(2) alarms from day one |
| W9 | Add sizing/emitter rows to the pre-dispatch table. **Clearing the banner is MOVED OUT** — see W12 | ADR-149 §7 | — |
| W10 | Art. 30 register: neutralise the present-tense LUKS claim; record the second emitting host | CLO panel | A **false** Art. 32 measure on the register at birth |
| W11 | Expense-ledger correction: birth creates **two** 10 GB volumes, ledger books one, at a stale rate | COO panel | `wg-record-recurring-vendor-expense-before-ready` blocks PR-ready |
| W12 | **Rehearsal boot** — render the real template, boot it once on a throwaway server, and pin the observed emitter artifacts as evidence | Fable advisor consult | The one moment a destroy-and-create is free |

### W12 — the rehearsal boot, and why the banner-clear moves out of this PR

The scoped strong-model consult (ADR-083, plan Step 4.5) named the flaw that survives every other
safeguard here: **every gate in this plan is static, while the failure class it defends against —
"green apply, dark host" — is only observable at runtime.** Two consequences, both adopted.

**(a) Mutation arms are necessary and not sufficient.** AC25's arms prove the code *can go red when
neutered*; they never prove an event *actually arrives* when the code is intact. W0's token-scope
mismatch is exactly the defect class that passes every static check and every mutation arm and then
dies silently on first boot. The host has never existed, so **this is the one moment when a
destroy-and-create is free** — and a single rehearsal boot simultaneously (i) executes W0 for real
rather than by probe, (ii) validates the Phase-3 must-abort/must-tolerate classification against an
actual boot (the named precedent — assertions placed above the heredocs that create their targets —
is precisely the ordering class a static enumeration is worst at catching), and (iii) converts the
release condition from *"the variable is referenced"* to *"the signal was received."*

**(b) "W9 is the last commit" was not a mitigation.** A PR merges atomically, so a banner cleared in
the final commit clears at the same instant as all the untested code it is supposed to be downstream
of. **The banner-clear therefore moves to its own follow-up PR whose stated precondition is the W12
evidence.** The first draft's "last commit" framing is withdrawn.

**Rehearsal ladder — use the cheapest rung that answers the question, and pin which rung was used.**

1. **Container harness** (already prescribed for T5/T6): `docker run` the pinned Ubuntu 24.04 image,
   execute the rendered `runcmd`, capture the emitted payloads. Answers: the `set -e` classification,
   the trap's coverage, the emitter helpers' behaviour, the redactor, `sha256sum` abort ordering.
   Does **not** answer: `doppler run` scope against real Doppler, `luksOpen` against a real volume,
   the private NIC, or whether an event actually lands in Sentry/Better Stack.
2. **Throwaway host boot** — a `cpx22` outside the `hcloud_server.git_data` address, booted from the
   **rendered real template** with stub volume ids and a scratch Doppler branch config, then
   destroyed. Answers everything in (1) plus the live `doppler run` scope, real egress, and — the
   point — **whether the Sentry fatal event and the Better Stack stage markers and the
   boot-completion emit actually arrive off-box.**

**Required evidence, pinned in the PR body:** the three observed artifacts (a Sentry event from the
fatal channel, ≥1 Better Stack stage marker, and one `SOLEUR_GIT_DATA_BOOT_COMPLETE` row carrying
its four assertion booleans), each with the query that retrieved it. Rung (2) is the target; if only
rung (1) is reachable in-session, that must be stated explicitly as the residual, and the banner-clear
PR must then carry rung (2) as *its* precondition rather than inheriting a pass.

**Residual, stated rather than hidden.** Between this PR's merge and the banner-clear PR, the
interlock is mechanically **released** (the sentinel threads) while only the prose banner holds the
route — the "hold by convention" state ADR-149's Alternatives table rejects. That is a real
regression in hold-strength, and it is accepted deliberately because the alternative is worse:
clearing the banner over an emitter no one has ever seen emit. The mitigation is that W12 is a
deliverable of **this** PR, not the follow-up, so the window is short and the evidence exists before
anyone could act on the cleared gate.

### W0 — the unlisted P0, and why it is Phase 0

`cloud-init-git-data.yml` runs **both** boot-critical blocks as
`doppler run --project soleur --config prd -- …`, but `doppler_service_token.git_data`
(`git-data-luks.tf`) is scoped to `doppler_config.git_data_prd` = `soleur` / **`prd_git_data`**.

Every sibling agrees with its own token: `cloud-init-inngest.yml` uses
`--project soleur-inngest --config prd` against a token in that project's `prd`;
`cloud-init-registry.yml` likewise. **git-data is the only host whose flags name a config its token
is not scoped to.** This has never executed — the host has never booted. `git-data-luks.test.sh`'s
A6 mutation arm asserts only that the string `doppler run` survives; nothing asserts the scope
agrees.

If the CLI errors on the mismatch rather than deferring to the token's own scope, `GIT_DATA_LUKS_KEY`
never reaches the heredoc, `cryptsetup luksOpen` never runs, and — because the heredoc's
`set -euo pipefail` is line 1 of a script `doppler run` failed to exec — **nothing reports it**.
That is the dark boot the interlock exists to prevent, sitting inside the file the interlock
inspects.

**It is Phase 0 because it gates a design decision, not just a fix:** the answer determines whether
the emitter's Better Stack credential can live in `prd_git_data` at all, or whether the `doppler run`
invocation must be corrected first. Probe shape: mint a throwaway `read` service token against a
throwaway branch config and run `doppler run --project soleur --config prd -- env` with it (the
ADR-130 probe pattern ADR-149 already used for `POST /v3/configs`). Cost: minutes.

### Precision note — "LUKS mounted" and "the store is plaintext" are BOTH true

The advisor consult flagged an apparent contradiction between W1's boot-completion emit (which
asserts *LUKS-mounted*) and W10 (which records that the live store is *plaintext*). **They are not
in contradiction, and the distinction is load-bearing enough that getting it wrong would produce
either an emit that permanently reds every birth or — far worse — one written to pass vacuously,
installing exactly the green-light-over-a-dark-host the interlock exists to prevent.** Verified
against the template and the bootstrap:

- `cloud-init-git-data.yml` **does** `cryptsetup luksOpen` the LUKS volume and `mkfs`/mount it at
  `/mnt/git-data-luks` on every boot. So *"the LUKS volume is open and mounted"* is a true, testable
  boot post-condition, and asserting it is correct.
- `git-data-bootstrap.sh` sets `REPO_ROOT="$GIT_DATA_ROOT/repositories"` where
  `GIT_DATA_ROOT=/mnt/git-data` — the **plaintext** volume. It only *asserts* that the LUKS root is
  open and mounted; it does **not** create a repo root there. So the **bare git data lives on the
  plaintext volume**, and the LUKS volume is a mounted-but-empty cutover target gated by
  `GIT_DATA_STORE_ENABLED`.

**Which volume holds data at birth — resolved (R34, CPO C1(iii)).** v1 contradicted itself: the
*Encryption Posture* section called the plaintext volume "the Phase-2 store" while the *Research
Reconciliation* table cited #6976 finding it **vestigial**, with reclaim targeting the LUKS mount.
Resolved against the code, not the issue: `git-data-bootstrap.sh` sets
`REPO_ROOT="$GIT_DATA_ROOT/repositories"` with `GIT_DATA_ROOT=/mnt/git-data`, and
`git-data-provision.sh` and `git-data-transport-wrapper.sh` both default
`REPO_ROOT="${GIT_DATA_REPO_ROOT:-/mnt/git-data/repositories}"`. **The plaintext volume is the live
store at birth.** #6976's "vestigial" reading is corrected to *vestigial **after** the cutover, live
before it* — and this is why W5's reclaim and the disk observability target `/mnt/git-data`, not the
LUKS mount (R11), and why W10 is needed at all.

**Therefore:** W1's four assertions are `luks_mounted` (the LUKS *device* is open and mounted),
`repo_root` (the repo root exists on `/mnt/git-data` with the expected owner/mode), `hooks_path`,
and `provision`. The emit must **not** claim the repositories are encrypted at rest — that is
precisely the false claim W10 exists to remove from the Art. 30 register, and duplicating it into
telemetry would be the same defect in a second artifact. **No decision about moving the repos onto
the LUKS volume is taken by this plan** — that is the `GIT_DATA_STORE_ENABLED` cutover (#5274
Phase 3 / #6897), and the advisor's "decide LUKS-at-birth scope now" is answered as: *it is already
decided, upstream of this plan, and this plan neither advances nor contradicts it.* An AC pins the
emit's wording so a future reader cannot re-conflate the two (AC30).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #6982 / task framing) | Reality (measured on this worktree) | Plan response |
|---|---|---|
| "No log shipper — 0 occurrences of vector/betterstack/journald; the inngest cloud-init has 31/11/5, the web host's 14/2/7" | **Confirmed** for git-data. But the *comparison hosts are the wrong precedent.* `vector.toml` has **zero `type = "file"` sources**, and `[sources.system_journald]` filters `PRIORITY ∈ {0,1,2}` while cloud-init runcmd output is PRIORITY 6 — so **neither web nor inngest ships `/var/log/cloud-init-output.log`**. What gets boot failures off-box on those hosts is an **explicit per-stage emitter**. The architecturally-matched host (the registry: deny-all, no docker, no OCI bake) uses **curl emitters**, not a Vector agent. | Adopt the **registry/inngest emitter pattern**. A Vector agent on git-data is explicitly rejected (A1) — which also discharges the COO panel's Vector-collector quota concern by construction: git-data ships **no `host_metrics`**, the source of the 2026-06-10 quota breach. |
| "Heartbeat absent, not merely paused" | **Confirmed and sharpened three ways.** (a) `betteruptime_heartbeat.git_data_prd` is **never-created**, not never-unpaused — it sits in `OPERATOR_APPLIED_EXCLUSIONS` *and* `GIT_DATA_BIRTH_REFUSED`. (b) The `arm_one` call for it lives in the **per-merge `apply` job**, not a birth-only step — so creating it makes git-data reachability a **merge-blocking dependency for the whole repo**. (c) Its feeder proves **reachability, not boot correctness**: `web-git-data-probe.sh` names its own limit (*"a bounded TCP connect-and-close to :22 proves the port is OPEN, not that git transport SERVES"*), and sshd is up before `runcmd` runs — so a host whose Doppler download 404'd, whose LUKS never mounted and whose bootstrap died **beats green**. | **W2 deferred.** Arming it would install a green light over the exact failure the interlock was built to catch. ADR-149 item 4 is instead satisfied **host-side** by W1's boot-completion emit. `Closes #6548` is **withdrawn**; #6548 gets the `arm_one` merge-wedge finding recorded against it. Full reasoning in D-HB. |
| "No `set -e` on the Doppler runcmd item" | **Confirmed.** `sha256sum -c -` → `tar xzf` → `chmod +x /usr/local/bin/doppler` with no `set -e` and no armed `trap`. The file's only `set -euo pipefail` is line 1 of the `LUKSEOF` heredoc `doppler run` executes — so on a missing or wrong-arch binary it runs **zero** times. `git-data.tf`'s tripwire comment says it verbatim: *"NOTHING ABORTS."* | W3 ports the web host's top-armed `on_err`/`STAGE`/`_emit` shape. **Blast-radius caveat carried into the plan:** a `set -e` scope change un-gates previously-tolerated non-zero exits, so Phase 3 enumerates **every** existing runcmd item and classifies it must-abort / must-tolerate before arming. |
| "`git-data-transport-wrapper.sh` denies `git gc`, so there is no manual route either" | **Confirmed, and stronger.** The wrapper allows exactly two verbs; all three `authorized_keys` entries are `command=` + `no-pty`; the `git` user's shell is `git-shell`. There is **no** maintenance escape hatch over SSH by design. | W4 does not add one (A7). Maintenance runs host-local as root via a systemd timer installed at cloud-init — the only context that can reach the repos. |
| "No quota / reclaim on a 10 GB store" | **Confirmed, with four refinements.** (a) 10 GB is the **Hetzner floor**, not a capacity estimate. (b) Both volumes are **ext4** — XFS project quotas unavailable, uid/gid quotas useless (every repo is owned by the single `git` uid); only **ext4 project quotas** work, and only with `-O quota,project` at `mkfs` time. (c) `git_data_luks_volume_size >= git_data_volume_size` binds any resize. (d) Per #6976, `hcloud_volume.git_data` is vestigial — reclaim targets `/mnt/git-data-luks`. | W5 enables the `mkfs` flag now, ships **unreachable-object** reclaim, and ships store-fullness observability. Per-workspace quota *assignment* is deferred (A10) — and per the CLO panel it is **also blocked on a contractual basis that does not exist yet** (see *GDPR / Compliance Gate* §E). |
| "No `MaxStartups`/`MaxSessions`" | **Confirmed repo-wide** — `grep -rn "MaxStartups\|MaxSessions"` returns **zero hits anywhere in the tree**. Defaults apply: `MaxStartups 10:30:100`, `MaxSessions 10`. Additional finding: `ClientAliveInterval 300` + `ClientAliveCountMax 2` lets a wedged transport connection hold a slot for **~10 minutes** — the larger risk on a 2-vCPU box. | W6 adds both to the existing `01-hardening.conf` drop-in (**first-match-wins**; Hetzner ships `50-cloud-init.conf`, so the `01-` prefix is load-bearing) and tightens `ClientAliveInterval` to 60. |
| "ADR-068 D1 asserts 'neither CPU- nor RAM-bound' … the brainstorm rejects `cpx12` BECAUSE gc/repack is spiky on one vCPU" | **Confirmed, and the claim has three sites:** ADR-068 addendum D1, `variables.tf`'s `git_data_server_type` description, and `knowledge-base/operations/expenses.md`. The brainstorm's contradicting sentence is one site. Neither cites telemetry; neither can, pre-birth. | W7 resolves it **by construction, not by assertion** (D-SIZE). Amends all three sites. |
| "Sizing is … post-birth uncorrectable" | **FALSE as stated.** `git-data-host-replace` exists and plans `-replace='hcloud_server.git_data'` with both volumes and the passphrase preserved by omission; its stock-preflight error text describes the var-flip-and-merge remediation explicitly. | Corrected in *Overview* and in D-SIZE. The directional conclusion (decide before birth) survives on the **replace-is-destructive** argument, which is the one that actually holds. Shipping the stronger-but-false claim would let a reviewer who checks it discount everything around it. |
| ADR-149 §6 — "Correct the `hcloud_firewall_attachment.git_data` entailment rule **if it has not already been corrected**" | **ALREADY CORRECTED on main.** `git-data-host-birth-gate.sh` splits the attachment out of the entailed-creates loop and asserts the **outcome** (`server_ids` ends at length 1) rather than a verb, with the provider-source rationale inline. | Checklist item 6 is **discharged, no code change** — recorded as verified evidence rather than assumed. |
| Collision gate: are #6974 / #6989 prior implementations of this scope? | **No.** #6974 is the `cax11 → cpx22` repin + arch derivation; #6989 is the birth route + interlock. Neither ships an emitter, gc tuning, quota, sshd limits, or `GIT_DATA_SSH_HOST`. | Proceed. |
| *(not in the issue)* Art. 30 register asserts, present tense, that the git-data volume **is** LUKS-encrypted at rest | **Confirmed** — `knowledge-base/legal/article-30-register.md` PA-1 limb (g)(13) and PA-2 limb (g)(17). Today that is harmlessly premature: no reader can be misled about a store that does not exist. **The birth is the event that converts a premature claim into a false one**, because the live store is the plaintext `hcloud_volume.git_data`. | **W10**, must-fix in this PR. Apply the wrapper PA-2 already uses for its own *"DRAFTED / NOT-YET-ACTIVE"* row. |
| *(not in the issue)* Better Stack object count | Live: **7 heartbeats + 3 monitors = 10 objects**; the vendor page reads *"10 monitors & heartbeats"* as a **single shared pool of ten**. Unconfirmed against a live 429 (no usage endpoint exists) — **REVIEW, not fact**. | Reinforces the W2 deferral: this plan creates **no new Better Stack object**. If a future PR does, it must first reclaim the slot held by `app.soleur.ai/health` — a live monitor that is **not Terraform-declared** and duplicates `uptime-alerts.tf`'s `app` monitor. Recorded, not acted on here. |

## Hypotheses

`plan` Phase 1.4 fired on the keyword set (`SSH`, `firewall`, `unreachable`, `timeout`). **There is
no outage to diagnose** — the subject host has never existed, which is itself the L3 artifact. The
L3→L7 layers are addressed as *design preconditions*, each with a named artifact per the checklist's
opt-out rule, and in order.

1. **L3 — firewall allow-list.** Not drift: `hcloud_firewall.git_data` is a **zero-rule deny-all**
   firewall by design, and the birth gate refuses any plan that gives it inbound rules
   (`FIREWALL CONTENT` arm). Public IPv4/IPv6 exist for **egress only** (apt + GitHub during
   cloud-init; there is no NAT gateway in this account). **No operator egress IP is in any path** —
   nothing in this plan reaches git-data over SSH from a laptop or a CI runner.
   *Artifact:* the gate's `firewall_rules == 0` arm; `git-data.tf`'s `public_net` comment.
   **[verified — design, not drift]**
2. **L3 — DNS / routing.** git-data has **no DNS name**. Transport is private-net only, to the
   static `10.0.1.20` pinned in `network.tf`. *Artifact:* `network.tf` `ip = "10.0.1.20"` (a
   literal, not a computed attribute — which is also what makes W8 tractable).
   **[verified — static, no resolver in path]**
3. **L7 — TLS / proxy.** Not applicable: no HTTPS surface, no Cloudflare tunnel on git-data
   (ADR-096 excludes cloudflared from zot/git-data/inngest). **[N/A — artifact: ADR-096]**
4. **L7 — application layer.** The one live signal is `web-git-data-probe.sh` on the web hosts,
   emitting `SUPPRESS ping: 10.0.1.20:22 UNREACHABLE` every 60 s. **That is the expected and
   correct output** — the endpoint does not exist. *Artifact:* the script's fail-soft branch;
   `heartbeat-manifest.ts`'s `git_data_prd` row. **This absence is the signal.**

**Ordering discipline honoured.** Every layer is answered before any service-layer claim, and no
phase proposes an sshd or fail2ban change as a *remedy* for a connectivity symptom — W6's sshd
change is capacity hardening for a host that does not yet accept a single connection.

## User-Brand Impact

<!-- lint-infra-ignore start -->
**If this lands broken, the user experiences:** a `git push` at session end that hangs or fails
against a git-data host whose LUKS volume never mounted — and, because nothing in the boot path
fails closed today, an operator who sees a green `terraform apply` and no alert. Concretely: the
user's worktree replication silently stops working while `ensure-workspace-repo.ts` treats git-data
as a fail-soft overlay, so the failure is invisible until the user needs the replicated copy and it
is not there. A second reachable end-state: OOM during a receive-triggered `gc`/`repack` on a
2 vCPU / 4 GB no-swap box, killed silently because `gc.autoDetach` is default-on, presenting to the
pushing client as a stalled push with no error. A third, newly identified: **every account deletion
files a false "Art. 17 erasure failed" event** from the moment the host exists (W8).
<!-- lint-infra-ignore end -->

**If this leaks, the user's source code is exposed via:** the store holds **every connected user's
repository objects and refs**. (a) The zero-rule deny-all firewall plus its attachment are the
*entire* public-exposure defense on a host with a public IPv4/IPv6; a birth that lands the server
without the attachment leaves the store naked on the open internet. (b) The at-rest posture: the
live target store is **plaintext ext4** with a declared-but-not-live LUKS cutover target gated by
`GIT_DATA_STORE_ENABLED`, carried as a ledgered exception tracking #6897. A boot where `luksOpen`
silently failed leaves at-rest encryption absent while every artifact claims it present — the state
today's zero-emit boot path cannot distinguish from success.

**Third vector, introduced by this plan and mitigated in it.** The emitter ships boot-stage detail
off-box, and the CLO panel found the sharp edge: on this host the **repo identifier *is* the user
identifier** (`workspace_id === user_id` per the mig-053 N2 invariant; repos are named
`<workspace_id>.git`), and `vector.toml`'s `pii_scrub_string` **does not scrub a bare UUID in free
text** — it scrubs `userid=<token>` pairs, emails, bearer tokens and DSNs. So any emitted line
naming a repo path would ship **raw `auth.users.id` values** to Better Stack, breaking PA-8's
Recital 26 pseudonymity claim and the "no processor-side erasure call required" conclusion that
rests on it. **This is the single most important cross-item finding in the plan**, because it is
created by items 1 and 5 *together* and by neither alone: the emitter is the channel, and the
reclaim/disk unit is the thing that would naturally log which repo it pruned. The mitigations are
binding ACs, not notes (AC22–AC24).

**Correction to the framing above (R35, CPO C3) — this is lost work, not a lost replica.** The
paragraph reads as redundancy loss ("the user needs the replicated copy and it is not there"). That
understates it, in the direction that matters. `ensure-workspace-repo.ts` states the invariant:
git-data ⊇ the GitHub clone, and GitHub is *"strictly BEHIND the user's latest committed tip on
git-data."* **git-data therefore holds the sole copy of the delta between a user's last GitHub push
and their latest worktree state.** Losing it is not losing a replica; it is losing user work with no
other copy anywhere.

**Merge-time vs birth-time impact are different by orders of magnitude, and must not be conflated.**
At **merge**: the host is unborn, `GIT_DATA_STORE_ENABLED` is off, and there are **0 beta users** —
user impact is exactly **zero**. At **birth**: all-users, simultaneously. A reviewer reading this
section cold will otherwise price merge-time risk far too high, and the honest statement is that this
PR's risk is entirely *option-value* risk on a decision that becomes expensive later.

**Brand-survival threshold:** `single-user incident` — **the ceiling of the vocabulary**, not a scope
estimate (CPO C4). The repo uses exactly two values, `none` and `single-user incident`; there is
nothing to escalate to. If anything the label *under*-describes the blast radius: one store, one
firewall, one at-rest posture, holding every connected user's repository objects, so a leak is
simultaneous and all-users. Two rules fire at this tier and must not be read as optional: a
scope-out justified by *"next-most-likely entry not covered"* is an anti-pattern, and deepen-plan's
domain triad is mandatory.

**Consequence:** `requires_cpo_signoff: true`. CPO sign-off is required at plan time before `/work`
begins. `user-impact-reviewer` is invoked at review time per the review skill's conditional-agent
block.

## Architecture Decision (ADR/C4)

Three architectural decisions, all **in-scope tasks of this PR** per
`wg-architecture-decision-is-a-plan-deliverable`.

### ADR

**Primary: amend `ADR-068` (2026-07-27 addendum, §Decisions).** No new ordinal — the addendum
itself argues git-data's type decision belongs in ADR-068 (*"git-data is this ADR's element"*) and
establishes the addendum-not-new-ordinal convention. Records **D-SIZE** and a `D1-corrected` row.

**Secondary: amend `ADR-149`.** Add checklist **item 9 as merged** (sizing confirmation — the release
checklist has none today, and neither does the runbook's pre-dispatch table, whose step-7 stock
preflight checks *orderability*, never *adequacy*). Amend the Alternatives table with **D-HB**'s
evidence: the original *"Target the heartbeat too — Rejected"* verdict **stands**, but for a
partly different and stronger reason. Amend Residual 2's disposition to record W8's dissolution of
the feasibility trap.

**No new ADR ordinal is claimed.** If review concludes one is warranted, the next free on
`origin/main` is **ADR-150** — *provisional*; `/ship`'s ADR-Ordinal Collision Gate re-verifies before
merge, and any renumber must sweep this plan, `tasks.md`, and every AC naming the ordinal in the
same edit.

---

**D-SIZE — keep `cpx22`; make D1's claim true by construction instead of asserting it.**

Both sides of the contradiction are unmeasured, and **each is right about a different regime**. The
resolution removes the regime that makes the weaker claim false:

- ADR-068 D1's *"neither CPU- nor RAM-bound"* is true of the **steady state**. A bare-repo push
  target populated lazily and turn-driven is I/O-shaped, not compute-shaped.
- The brainstorm's *"`git gc`/`repack` are spiky on a single vCPU"* is true of the **burst**, and
  the burst is not hypothetical: `receive.autogc` is **default-ON**, so *every push* can trigger
  `gc --auto` → `repack` server-side, `pack.windowMemory` is **unlimited** on a 4 GB box with **no
  swap**, and `gc.autoDetach` is **default-on**, hiding the resulting OOM from the pushing client.

D1 as written is therefore false — not because the store is inherently CPU-bound, but because the
**default git configuration** makes it burst-bound. W4 removes that regime: `receive.autogc=false`
and `gc.auto=0` move maintenance off the push path entirely, `pack.windowMemory`/`pack.threads`
bound the peak, and a systemd-bounded timer (`MemoryMax=`, `CPUQuota=`, `IOSchedulingClass=idle`)
caps what maintenance may consume. **After W4, "neither CPU- nor RAM-bound" is an enforced
invariant rather than an unbacked assertion.** The tuning work *is* the correction — which is why
W4 and W7 are one decision, not two.

**The type stays `cpx22`** (2 vCPU / 4 GB / 80 GB, €19.49/mo net → ~$21.05). Not downsized to
`cpx12` (1c/2g, €11.49 → ~$12.41, **−$8.64/mo / −$103.68/yr**), for three reasons that survive the
tuning:

1. **Serialisation — bounded, not eliminated.** One vCPU serialises the gc timer against concurrent
   `git-receive-pack`. State this honestly (R29): W4's own `IOSchedulingClass=idle` + `Nice=19` +
   `CPUQuota=` *are* a serialisation mitigation, so this argument is weaker than v1 implied. What
   remains true is that `Nice` does not preempt and `CPUQuota` caps gc's *share* without bounding
   receive-pack *latency*. **Argument 2 carries the decision on its own**; this one is supporting.
2. **The correction is destructive, not a resize.** A post-birth type change routes through
   `git-data-host-replace` — a destroy-then-create of the host, with the store and the writer-side
   CAS fence offline and passphrase preservation resting on omission. $104/yr does not buy that
   exposure on a host that has never been measured. (This is the corrected version of the
   "uncorrectable" claim; see *Research Reconciliation*.)
3. **No measurement is possible pre-birth, and the decision cannot wait for one.** The honest
   statement the ADR must make is *"unmeasured, sized for the burst, with the burst now explicitly
   bounded"* — not *"measured and unbound"*.

**Not upsized to `ccx13`** (2 dedicated c / 8 GB, €42.99 → +$25.38/mo / **+$304.56/yr**, and it
would consume 2 of 8 dedicated vCPUs): over-provisions against no measurement, the direction
ADR-143 D1 criticised. **`cx23`/`cx33`/`cax11` are not candidates** — all three were out of stock in
all three EU DCs at the live 2026-07-27 probe; a host cannot be born on them.

**Companion decision — no swap file.** The obvious OOM backstop is **rejected**: an unencrypted
root-disk swapfile can hold plaintext git object data paged out from under the LUKS posture the
whole `git_data_luks` apparatus exists to establish. Encrypted swap (random-key dm-crypt) would work
but adds a second crypt device to a host already barred from the reboot primitive. Bound memory
instead. Recorded in *Encryption Posture*.

**Two catalogue corrections found while pricing this** (filed as a separate issue, not fixed here):
ADR-143's probe table lists **`cx22` at ~€4.59 "out of stock"** — `cx22` is **not in the Hetzner
catalogue at all**, the same phantom-SKU class as the `cx32` that destroyed the registry host
(#6288); and the same table records `cx23` as "in stock", which the 2026-07-27 probe falsifies.

---

**D-HB — the heartbeat stays out of the birth route. ADR-149's verdict stands, on better evidence,
and item 4 is satisfied host-side instead.**

The plan's first draft proposed folding `betteruptime_heartbeat.git_data_prd` into the birth
`-target` set and arming it in the birth job, calling that ADR-149 checklist item 4's post-apply
signal. **That is withdrawn.** Three findings, any one of which is disqualifying:

1. **It would wedge every merge to `main`.** The `arm_one` call for `git_data_prd` already exists —
   in the **per-merge `apply` job**, not a birth-only step. It no-ops today only because the address
   is absent from tfstate. The moment the heartbeat exists, *every merge* unpauses it, polls 230 s,
   and on no-beat rolls back to paused and returns non-zero → the apply job fails. That converts the
   health of an unborn, un-cutover, flag-off host into a merge-blocking dependency for the whole
   repository. Unnamed in ADR-149 and in the first draft.
2. **It would prove the wrong thing.** `web-git-data-probe.sh` names its own limit: *"a bounded TCP
   connect-and-close to :22 proves the port is OPEN, not that git transport SERVES."* sshd is up
   before `runcmd` executes — so a host whose Doppler download 404'd, whose LUKS volume never
   mounted, and whose bootstrap died **answers on :22 and beats green**. Wiring that in as "the
   replacement for ADR-145's R2–R5 boot poll" installs a green light over the exact failure the
   interlock was built to catch. ADR-149 already says this correctly (*"a floor to build on rather
   than the signal itself"*); the first draft walked it back.
3. **It would consume a Better Stack object at a possible 10/10 cap** (see *Research
   Reconciliation*), risking a half-succeeding birth apply.

**What ADR-149's Alternatives row gets amended with, rather than overridden:** its stated reason —
*"a monitor this route cannot arm is the #6537 fed-but-paused shape"* — is now **partly stale on the
feeding half**. The feeder shipped; `web-git-data-probe.service` runs `doppler run` *per tick* and
resolves the URL by indirection through `GIT_DATA_HEARTBEAT_URL_KEY`, so the URL secret would
propagate within one 60 s tick of an apply with **no `ci-deploy` redeploy required**; and
`heartbeat-manifest.ts` already carries the row as `feeder: {kind: "timer"}` with no
`arming_pending`. The **conclusion is unchanged** and the reasons above are stronger than the one
recorded. That correction is the ADR edit.

**ADR-149 checklist item 4 is therefore satisfied by W1's boot-completion emit**, host-side: a
final `git-data-bootstrap.sh` stage that asserts and reports the LUKS mount, the bare-repo root, the
`core.hooksPath` setting, and the provision wrapper's presence — the `soleur-fresh-boot-ready`
analogue. That is a real R2–R5 replacement; a web-side TCP probe is not. It also gives ADR-149
**Residual 3** (empty-store Art. 17 silent success) the birth-completion marker it needs — the same
signal — so the tracking issue for Residual 3 can name a concrete design rather than an open
question.

**#6548 is not closed by this PR.** It gets a comment recording the `arm_one` merge-wedge finding,
the reachability-vs-serviceability finding, and the object-cap finding — the three things its
implementer must resolve first, plus the #6975 cross-host masking dependency.

---

**D-EMIT — git-data gets curl emitters, not a Vector agent.** Full reasoning in A1.

### C4 views

**All three model files were read in full** (`model.c4` 558 lines, `views.c4` 62, `spec.c4` 54) —
not grepped for the feature's own noun. Enumeration of external human actors, external systems,
containers/data stores, and access relationships:

| Class | Element | Already modelled? | Action |
|---|---|---|---|
| External system | `betterstack` (uptime/heartbeat + Logs source 2457081) | Yes | **Description edit** — its git-data paragraph says the beat *"is absent from live Better Stack … #6548/#6982 own arming it"*. After this PR, #6548 alone owns it, and the reasons have changed. |
| External system | `sentry` (`de.sentry.io` DSN ingest) | Yes | **New edge** (below) |
| Container / data store | `platform.infra.gitDataStore` | Yes | **Description edit** — it asserts *"interlocked until #6982 ships an off-host emitter (ADR-149)"*. False on merge. The *"NOT YET PROVISIONED"* clause stays true. |
| Container | `platform.infra.hetzner` (the probe's home) | Yes, with edge `hetzner -> gitDataStore` | No change — the consumer probe is untouched. |
| External system | `doppler` | Yes | **No change.** W8's secret lands in the existing `soleur/prd` config the model covers; W1 bakes the DSN via `templatefile`, adding no new Doppler edge from git-data. (If W0's probe forces a new `prd_git_data` secret for the Better Stack token, that is still inside the existing `doppler -> gitDataStore`-class relationship — re-check at /work.) |
| **Access relationship** | git-data → Better Stack (boot stage markers, disk/gc events) | **NO — absent** | **New edge** `gitDataStore -> betterstack` |
| **Access relationship** | git-data → Sentry (boot-fatal emit) | **NO — absent** | **New edge** `gitDataStore -> sentry` |
| External human actor | — | n/a | **None, and this is checked rather than assumed.** git-data has no DNS name, no interactive shell (`git-shell` + three `command=`/`no-pty` forced commands), and no operator SSH path; the operator reaches its telemetry only through `betterstack`/`sentry`, both of which already carry `-> founder` paging edges. Verified against `model.c4`'s full actor list (`founder`, `emailSender`, `betaContact`, `contributor`). |

**Concrete `.c4` edits** (in-scope tasks, edited directly on the filesystem and committed in this
feature's lifecycle — the `c4-edit` flag gates only the in-browser webapp editor, never this path):

1. `model.c4` — add `gitDataStore -> betterstack` with `technology "curl → Better Stack Logs (HTTPS)"`.
2. `model.c4` — add `gitDataStore -> sentry` with `technology "curl → Sentry store API (HTTPS)"`.
3. `model.c4` — amend the `gitDataStore` and `betterstack` descriptions per the table.
4. **`views.c4` — NO change required, verified rather than assumed:** the `containers` view already
   includes both `platform.infra.gitDataStore` and `betterstack`, and the `context` view already
   includes `betterstack` and `sentry`. LikeC4 renders an edge whose *both* endpoints are included,
   so the new edges render without a `view … include` line. `gitDataStore` is correctly absent from
   `context` — it is an L2 container.
5. Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` (a `view include`
   referencing an undefined element fails there, never at `tsc`).

### Sequencing

Both new edges describe behaviour **wired at merge but only observable after the birth** — exactly
like the existing `hetzner -> gitDataStore` edge, whose description already says *"the probe RUNS
today, but its target host has never been provisioned"*. The new edge descriptions must carry the
same honesty marker (TARGET state, unobserved until the birth dispatch). No edge is deferred.

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

<!-- lint-infra-ignore start -->
`plan` Phase 2.8 fired and this section is its required output. **Nothing is routed to an operator
SSH session or a vendor dashboard.** Every service-state change named anywhere in this plan
(`systemctl` invocations, mounts, package installs) lives inside `cloud-init-git-data.yml`'s
`runcmd:`/`bootcmd:` or inside `git-data-bootstrap.sh`, both of which are rendered into
`hcloud_server.git_data`'s `user_data` by `templatefile()` in `git-data.tf` — i.e. they are applied
by `terraform apply`, never by a human at a shell. git-data has **no `remote-exec` provisioner and
no human SSH path** by design, so an operator-run step is not merely discouraged here, it is
impossible. Where this plan's prose quotes such a command, it is quoting template content under
review, not prescribing an operator action.
<!-- lint-infra-ignore end -->

### Terraform changes

| File | Change |
|---|---|
| `apps/web-platform/infra/git-data.tf` | Add `templatefile` vars to `user_data`: `sentry_dsn = var.sentry_dsn`, `betterstack_ingest_url = local.betterstack_logs_ingest_url`, `host_name = "soleur-git-data"` — plus the Better Stack **credential**, whose delivery shape is decided by W0's probe (see below). Add `resource "doppler_secret" "git_data_ssh_host"` (W8). |
| `apps/web-platform/infra/network.tf` | Hoist `local.git_data_private_ip = "10.0.1.20"` and have `hcloud_server_network.git_data.ip` read it — the #6415 `local.registry_private_ip` pattern. Today the literal is duplicated across `network.tf`, `server.tf`'s probe envwrite, and `git-data-replication.ts`'s non-prod default. |
| `apps/web-platform/infra/variables.tf` | Amend the `git_data_server_type` description: carry the corrected D1 claim **and** the COO finding that `cpx22` is now the only sensible *orderable* option, which is stronger than "a purchase of orderability". No default change. |
| `apps/web-platform/infra/cloud-init-git-data.yml` | W1, W3, W5 (`mkfs` flags, monitor units), W6 (sshd). |

**Required providers / pins:** none added. `var.sentry_dsn` (`sensitive`, default `""`) and
`var.betterstack_logs_token` (`sensitive`, no default) already exist;
`local.betterstack_logs_ingest_url` already exists in `zot-registry.tf`.

**Sensitive variable sourcing:** all from Doppler `soleur/prd_terraform` via
`--name-transformer tf-var`. **No new no-default variable is introduced**, so
`hr-tf-variable-no-operator-mint-default`'s sequencing hazard does not fire and no merge can be
wedged by a missing `TF_VAR_*`.

**The Better Stack credential — decided by W0, not assumed.** Two shapes, and the probe picks:
(a) if `doppler run --config prd` works under the `prd_git_data`-scoped token, add
`doppler_secret.git_data_betterstack_logs_token` to `doppler_config.git_data_prd` (the
`registry_betterstack_logs_token` precedent) and read it at runtime — **a new address, so it needs
the three-way registration**; (b) if it does not, correct the `doppler run` invocation first, then
(a). **Do not bake `BETTERSTACK_LOGS_TOKEN` into `user_data`** — `user_data` is retrievable from the
Hetzner metadata API, which is the same rationale that keeps the LUKS key out. The **Sentry DSN is
different and is baked**: it is semi-public (already in the client bundle, and `variables.tf` says
so), and baking it is what makes the fatal channel independent of the Doppler stage that may itself
be broken.

**W8 — the `GIT_DATA_SSH_HOST` feasibility trap is not structural.** ADR-149 cut
`doppler_secret.git_data_ssh_host` from #6977 because *"it would make `terraform-target-parity.test.ts`
red on landing, and the natural remedy drags `hcloud_server.git_data` into the per-merge plan and
wedges every merge to `main`."* That mechanism is real **only** under the remedy "give the new secret
a per-PR `-target` line" — and that is not the remedy its five sibling secrets use. All of
`doppler_secret.git_{transport,provision,remove}_ssh_private_key`,
`git_data_heartbeat_url_prd` and `git_data_luks_key` sit in `OPERATOR_APPLIED_EXCLUSIONS` with **no**
per-PR target. The clean shape:

1. `local.git_data_private_ip = "10.0.1.20"` — a **static literal**, not a computed attribute, so
   the secret needs no reference to any hcloud resource.
2. `value = local.git_data_private_ip`, plus `depends_on = [hcloud_server.git_data]` for the same
   arming-switch ordering reason `git_remove_ssh_private_key` carries it — do not publish a runtime
   key ahead of the host it addresses. The `depends_on` edge is only dangerous **in combination
   with** a per-PR target, and there is no reason to add one.
3. Register in **all three** of: the birth `-target` list (**18 → 20** per D1 — the Better Stack
   ingest secret returns alongside the SSH-host secret); the allow-set in
   `tests/scripts/lib/git-data-host-birth-gate.sh` — shell var `_GIT_DATA_BIRTH_ALLOW`, whose body
   is the **unparameterised** `def allow: [ … ]` because git-data is a singleton (unlike
   `web-host-birth-gate.sh`'s `def allow($k):` for the `hcloud_server.web` for_each map); the parity
   test pins the unparameterised form via `/def allow:\s*\[([^\]]+)\]/`, so do not "harmonise" the
   two; and `GIT_DATA_BIRTH_TARGET_BASES`.
4. Add to `OPERATOR_APPLIED_EXCLUSIONS` — which satisfies the parity test's *"every `-target` is an
   OPERATOR_APPLIED_EXCLUSION"* assertion. That is a **requirement** of the birth set, not an
   obstacle.

No per-PR target, no upstream closure into `hcloud_server.git_data`, no wedge.

### Apply path

**(a) Cloud-init-only, for everything host-resident.** git-data has **no `remote-exec` provisioner**
— the CI runner cannot SSH it, and `runcmd` is once-per-instance. Every host-side change in
W1/W3/W4/W5/W6 reaches a host **only at birth** (or at a subsequent replace). There is no idempotent
in-place bootstrap path for this host, unlike the web host's `soleur-host-bootstrap.sh`.

**(b) Merge-apply, for the Terraform-only pieces.** `doppler_secret.git_data_ssh_host` (and the
Better Stack secret, if W0 routes it that way) are `OPERATOR_APPLIED_EXCLUSIONS`, so a merge to
`main` applies **nothing** for this PR. Expected downtime: **zero**. Blast radius on merge: **zero
live resources changed.**

**(c) The birth dispatch — explicitly NOT part of this plan.**

**Auto-apply hazard check.** This plan adds no `for_each` resource and creates no reference from a
targeted resource to a `-target`-excluded sibling. An AC asserts the per-merge plan shows **no
create** of any git-data address. **Partial-birth surface:** every address added to the 18-target
set widens the partial-birth failure surface by one (if the server lands and a later address does
not, the retry plans zero server creates and the gate correctly refuses, and the host cannot be
completed by hand). Additions are held to the minimum — **one** (W8), or two if W0 forces the
Better Stack secret — and all three registration sites are edited in the **same commit**; the parity
test asserts exact length equality, so a two-of-three edit fails loudly, which is the good case.

### Distinctness / drift safeguards

- **dev ≠ prd:** git-data exists in prd only; no dev host, no dev/prd collapse risk.
- **`lifecycle.ignore_changes`:** `betteruptime_heartbeat.git_data_prd` is untouched (W2 deferred).
  `hcloud_server.git_data` deliberately keeps **no** `ignore_changes = [user_data]` — load-bearing
  here: **every byte of `cloud-init-git-data.yml`, comments included, is an input to a ForceNew
  attribute.** Pre-birth that is free; post-birth a comment edit costs a replace. The plan adds a
  warning banner at the template head and a note in the runbook, and records this as a residual
  rather than "fixing" it — the alternative (`ignore_changes = [user_data]`) forfeits the clean
  replace-to-reprovision path the resource comment says is deliberate.
- **State storage:** `var.sentry_dsn` is `sensitive` but lands in `terraform.tfstate` (R2 backend)
  and in `user_data` (metadata-API retrievable) — accepted, it is semi-public. The Better Stack
  token must **not** land in `user_data`. The LUKS passphrase remains **never** in `user_data`.
  `base64gzip` is **encoding, not encryption**.
- **`user_data` size budget — a hard gate.** Hetzner's cap is 32,768 bytes on the **base64-of-gzip**
  render. Current: ~21.9 KB stored (~16.4 KB gzip from ~41.7 KB raw) → ~10.8 KB headroom. Measure
  with `gzip -9 -c <rendered> | base64 -w0 | wc -c`, **never** `wc -c`. Comments count, and prose
  bloat is the historical cause of both prior breaches.
- **Template escaping:** shell `${VAR}` → `$${VAR}`; `${VAR:-default}` → `$${VAR:-default}` (a `:-`
  inside a `trap` string breaks the render); **never write `%{` anywhere in the file, including
  comments** — Terraform's directive scanner does not skip `#` prose; `curl -w` format specifiers
  need `%%{…}`. Verify by a real `terraform console` render, then `cloud-init schema -c <rendered>`
  (running it on the raw template always false-alarms). Note `validate-infra-templates.sh` **skips
  any `$${key}` by design**, so it is blind to a `$${sentry_dsn}` mistake — the readiness gate is
  what catches that direction.

### Vendor-tier reality check

`var.betterstack_paid_tier` is **false**. (a) `betteruptime_heartbeat` is **not** tier-gated — only
`policy_id` is — but the **object pool may be at 10/10** (7 heartbeats + 3 monitors against a
vendor-page reading of *"10 monitors & heartbeats"*), which is one more reason W2 is deferred; this
plan creates **no new Better Stack object**. (b) Free tier is **3 GB/mo logs, 3-day retention**, and
`[sinks.betterstack]` is `type = "http"` so **metric events bill against the logs quota** — the
cause of the 2026-06-10 breach (Vector `host_metrics` at 30 s scrape, >99 % of ingest). git-data
ships **no Vector and no `host_metrics`**, so it cannot reopen that quota; its emitters are
event-driven (~12 events per birth; disk 96/day at 15 min; gc 1/week). Happy-path narration stays
behind `SOLEUR_PROBE_VERBOSE` (default OFF); fault classifications always emit. (c) **Sentry**: PAYG
headroom is ~$7.78 against a $50 cap with a hard cliff at `onDemandPeriodEnd` 2026-08-16 — so this
plan adds **no Sentry cron monitor** ($0.78/mo each). The disk poller rides an **existing** scheduled
workflow.

## Observability

```yaml
liveness_signal:
  what: The boot-completion emit from git-data-bootstrap.sh — a final stage that ASSERTS and
        reports (i) /mnt/git-data-luks is a mountpoint, (ii) the bare-repo root exists with the
        expected owner/mode, (iii) core.hooksPath resolves to the on-volume hooks dir, (iv) the
        provision wrapper is executable. Emitted to BOTH Sentry (level=info) and Better Stack
        Logs. This is ADR-149 checklist item 4's post-apply signal — chosen over the
        heartbeat because a TCP connect-and-close to :22 succeeds on a host whose LUKS never
        mounted (see D-HB).
  cadence: once per boot (the host is a stateful pet; there is no steady-state liveness beat in
           this PR — reachability is already covered by web-1's existing probe)
  alert_target: Sentry issue alert -> founder email (issue-alerts.tf actions_v2 IssueOwners ->
                fallthrough ActiveMembers). Second-source: the Better Stack copy is queryable
                and pollable independently, per model.c4's deliberate vendor duplication.
  configured_in: apps/web-platform/infra/git-data-bootstrap.sh (the assertions + emit) ·
                 apps/web-platform/infra/cloud-init-git-data.yml (the emitter helpers) ·
                 apps/web-platform/infra/git-data.tf (the baked DSN + ingest URL)

error_reporting:
  destination: Sentry (project web-platform, org jikigai-eu, DE residency) via the raw store API —
               POST https://<host>/api/<proj>/store/ with an X-Sentry-Auth header, from a BAKED
               ${sentry_dsn} with NO Doppler fallback (the scoped token cannot read SENTRY_DSN, and
               a fallback that is dark by construction is worse than none — it reads as a safety
               net). Layer citation: this is the BOOT-PHASE fatal channel, the same layer as the
               web host's _emit/on_err in cloud-init.yml — NOT the app-runtime Sentry SDK layer,
               and NOT the Vector journald layer (which git-data does not have).
  fail_loud: yes. `trap on_err EXIT` is armed at the top of the FIRST runcmd item and emits
             level=fatal with the current STAGE before `exit 1`. The trap fires only under `set -e`,
             which W3 turns on explicitly — Phase 3 audits every existing runcmd item for
             must-abort vs must-tolerate before arming.

failure_modes:
  - mode: `doppler run` config-scope mismatch (W0) — the token is scoped to prd_git_data while the
          invocation names prd, so GIT_DATA_LUKS_KEY may never reach the heredoc
    detection: STAGE=doppler_run fatal to Sentry carrying rc and 200 redacted bytes of stderr.
               IN-SURFACE: emitted FROM the booting host. Pre-birth this is discharged by the
               Phase-0 probe rather than left to runtime.
    alert_route: Sentry issue alert -> founder email
  - mode: Doppler CLI checksum mismatch or wrong-arch tarball (supply-chain / mis-derivation)
    # AS-SHIPPED (corrected): the Better Stack marker named here was CUT by R3 and never
    # built — it was unreachable by construction, since the Doppler CLI that fetches the
    # ingest token does not exist until this very stage succeeds. `doppler-cli-install-FAILED`
    # exists only on the inngest host (cloud-init-inngest.yml), never on git-data.
    detection: STAGE=gitdata_doppler_dl fatal via /usr/local/bin/git-data-emit, carrying rc
               and the redacted tail of /var/log/cloud-init-output.log. Sentry ONLY — from
               the BAKED DSN, which is precisely what makes it work when Doppler is the
               broken stage. The armed `trap`/`set -e` means a checksum failure ABORTS here
               rather than continuing into `tar xzf`/`chmod +x` on an unverified tarball.
    alert_route: same Sentry route
  - mode: `cryptsetup luksOpen` fails / LUKS volume never mounts — at-rest encryption silently absent
    detection: STAGE=luks_open fatal; AND the boot-completion emit's mountpoint assertion FAILS
               loud rather than reporting success. This is the single most important discriminator:
               it is the state today's zero-emit path cannot tell from success, and the state a
               :22 reachability beat would report as healthy.
    alert_route: same Sentry route
  - mode: Host boots but never takes its private NIC (#6416 shape)
    detection: web-1's existing probe keeps emitting `SUPPRESS ping: 10.0.1.20:22 UNREACHABLE`,
               so the absence of the boot-completion emit and the persistence of SUPPRESS lines
               agree. This is the one mode an in-surface probe structurally CANNOT report — a host
               with no private NIC cannot be reached — which is why the two channels are kept
               independent.
    alert_route: the SUPPRESS-line recurrence poller (below) + the missing boot-completion emit
  - mode: Store fills (10 GB; `--force` pushes orphan objects, nothing prunes)
    # AS-SHIPPED (corrected — the v2 text below described a route that was never built:
    # there is no SOLEUR_GIT_DATA_DISK event, no 15-minute cadence, and no GitHub-cron
    # poller for git-data. Verified: `grep -rn SOLEUR_GIT_DATA_DISK` matches nothing
    # outside this plan.)
    detection: `disk_pct` rides as a k=v TAG on the git-data-gc emit (`df --output=pcent`
               on the GUEST filesystem, never the block-device size — a full ext4 reads as
               not-full via the Hetzner Volume API), and on the boot-completion emit. It is
               AGGREGATE only; no per-repo identifiers (AC22).
    cadence: the gc timer, `OnCalendar=Sun *-*-* 03:20:00` (+ up to 1800 s jitter) — WEEKLY,
             not every 15 minutes. A fill that starts on a Monday is therefore not visible
             for up to a week.
    alert_route: NONE AUTOMATED — this is the honest gap. The tag is queryable in Better
                 Stack but nothing polls it and nothing pages on it. Tracked in #7026; the
                 threshold alarm (mirroring the #6291 SOLEUR_ZOT_DISK pattern) is deferred
                 work, not shipped work.
  - mode: Maintenance gc OOM-killed on the 4 GB no-swap box
    # AS-SHIPPED (corrected): the cgroup-v2 oom-kill-counter confirmation was not built.
    detection: git-data-gc.service sets `MemoryMax=1G` so a runaway repack is killed in ITS
               cgroup rather than by the kernel choosing among sshd and the git transport,
               and carries `OnFailure=git-data-gc-failure.service`, which emits
               `SOLEUR_GIT_DATA_GC unit failed` through /usr/local/bin/git-data-emit with
               `unit=git-data-gc.service`. That emit has a no-Doppler fallback arm, so it
               still reaches Sentry from the baked DSN when `doppler run` is the broken thing.
               Per-repo failures deliberately exit 0 — OnFailure= is reserved for the unit
               DYING, so a partial failure does not page.
    alert_route: Sentry (pages), plus Better Stack when the Doppler stage has run. No poller
                 and no OOM-counter corroboration; the signal is the unit death itself.
  - mode: The emitter itself is dark (baked DSN empty, or the emit curl fails)
    detection: the birth job already asserts SENTRY_DSN non-empty in prd_terraform BEFORE any
               create (ADR-149 §1, implemented). A `Type=oneshot` unit reads `inactive` as its
               HEALTHY steady state, so unit-state checks are reported on the .timer, not the
               .service.
    alert_route: red apply (fails closed before any resource is created)

logs:
  # v3 channel split (D1) — forced by the sweeper's auth, not by taste:
  #   * EARLY STAGES + ALL FATALS -> Sentry ONLY. Baked DSN, no Doppler dependency, so it works
  #     precisely when Doppler is the broken stage. This is also the interlock's sentinel.
  #   * BOOT-COMPLETION + GC FAULTS -> Sentry AND Better Stack. Both are post-Doppler BY
  #     CONSTRUCTION (the bootstrap reaches its last stage only after `doppler run` succeeded; the
  #     gc timer runs long after boot), so the ingest token IS readable here.
  #   * The FOLLOW-THROUGH PROBE reads Better Stack, because that is the only channel
  #     scheduled-followthrough-sweeper.yml can authenticate: it passes SENTRY_AUTH_TOKEN (from
  #     SENTRY_IAC_AUTH_TOKEN), which sentry-issue.sh's own header records as 403-ing on
  #     event:read — the script needs SENTRY_ISSUE_RO_TOKEN, which the sweeper does not pass.
  where: Sentry (project web-platform, org jikigai-eu, de.sentry.io ingest) for every stage and
         fatal; PLUS a Better Stack Logs copy of boot-completion and gc faults on shared source
         2457081 (eu-fsn-3), reached by DIRECT CURL from the host — NOT via a Vector agent (A1),
         so git-data ships no host_metrics and structurally cannot reopen the 3 GB/mo quota
         breached on 2026-06-10. Discriminated from sibling hosts by the baked
         host_name=soleur-git-data field. Create-time-render caveat: host_name is baked at render
         time and is not a runtime-guaranteed invariant.
  retention: Sentry per plan — the durable record, and the only channel that PAGES (see D2: git-data
             has one paging vendor until #6548 arms the second). Better Stack 3 days on the free
             tier — a query surface for the follow-through probe, not an alert surface.

discoverability_test:
  # v2 (R10). Three defects in v1 are fixed here: the credential wrapper (bare invocation exits 3),
  # the query MODE (--grep compiles to `raw LIKE '%…%'` — the bare-substring form this very block
  # forbids, because the shared source is contaminated by inngest webhook logs quoting issue bodies
  # verbatim), and the WINDOW (default --since is 1h; a once-per-boot marker is invisible to a probe
  # running at earliest=merge+1d). $BS_TABLE is pinned explicitly rather than relying on the default,
  # which is the inngest-vector table, not necessarily source 2457081.
  command: |
    # 1+2. Boot stages and the boot-completion assertions — Sentry, the PRIMARY boot channel.
    #      CORRECTED: scripts/sentry-issue.sh has NO --search flag (usage is
    #      `[--latest-event] [--redact] <issue-id>`), so both lines below were unrunnable.
    #      Query the issues API directly; feed any id it returns to sentry-issue.sh.
    doppler run -p soleur -c prd -- sh -c '
      for q in "stage:bootstrap-done host_name:soleur-git-data" \
               "stage:boot_complete host_name:soleur-git-data"; do
        e=$(printf "%s" "$q" | jq -sRr @uri)
        curl -sS -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" -H "Accept: application/json" \
          "https://sentry.io/api/0/organizations/jikigai-eu/issues/?query=$e&statsPeriod=7d" \
        | jq -r --arg q "$q" ".[] | \"\($q): \(.shortId) \(.count)x \(.title)\""
      done'
    # 3. gc faults — Better Stack, the STEADY-STATE channel. Mode 1 raw SQL for FIELD isolation,
    #    with the s3Cluster archive arm (Mode 1 does NOT auto-add it, and remote() alone covers
    #    only the ~40-minute hot window, so a boot-time event would be invisible without it).
    doppler run -p soleur -c prd_terraform -- \
      env BS_TABLE="$BS_TABLE" bash scripts/betterstack-query.sh --since 7d "
        SELECT dt, JSONExtractString(raw,'message') AS msg,
                   JSONExtractString(raw,'complete')   AS complete,
                   JSONExtractString(raw,'failures')   AS failures,
                   JSONExtractString(raw,'disk_pct')   AS disk_pct,
                   JSONExtractString(raw,'inode_pct')  AS inode_pct
        FROM (SELECT dt, raw FROM remote($BS_TABLE)
              UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1)
        WHERE JSONExtractString(raw,'message') LIKE 'SOLEUR_GIT_DATA_GC%'
        ORDER BY dt DESC LIMIT 50"
  expected_output: |
    1. One Sentry issue per boot stage, the last being `stage:bootstrap-done`.
    2. Exactly one `stage:boot_complete` event per boot, carrying luks_mounted / repo_root /
       hooks_path / provision. ANY false value is a failure regardless of the apply's exit status.
       (Pre-birth, zero rows is the correct and expected result for 1 and 2.)
    3. ONE ROW PER RUN (the timer is daily since B12, so ~7 rows over 7d on a healthy host).
       Investigate any row whose `complete` is `no` (the run was killed part-way and every repo
       after that point is unmaintained), whose `failures` is non-zero, or whose `inode_pct` is
       high while `disk_pct` looks healthy (the A1 exhaustion path: loose objects exhaust inodes
       at roughly 55-60% of bytes).
       NOTE the `LIKE 'SOLEUR_GIT_DATA_GC%'` prefix rather than `=`. Equality matched ONLY the
       healthy/per-repo-failure summaries and missed every fault this PR added -- the killed-run,
       lock-unopenable, lock-held and unit-failed messages all carry a suffix. The equality form
       returned rows exactly when the host was fine and zero rows for every fault, which is the
       inversion of this section's own stated purpose.
  # NO `ssh ` appears in any command above. hr-no-ssh-fallback-in-runbooks becomes satisfiable for
  # this host for the first time — which is the point of the PR.
```

**Affected-surface note (Phase 2.9.2).** git-data is a **blind execution surface**: no SSH for
humans, no interactive shell, no docker, no operator console. Every `detection` above names an
**in-surface** probe — a signal emitted *from* the host — except the NIC-failure mode, which is
deliberately host-side because a host with no private NIC cannot be reached and a host that never
finished booting has no emitter yet. **The stage markers carry discriminating structured fields**
(`stage`, `rc`, `arch`, `apiprobe`, redacted `derr`, and the four boot-completion booleans) so a
boot failure resolves the supply-chain-vs-LUKS-vs-network hypothesis set **in one event**, rather
than requiring an nth blind fix.

### Soak follow-through enrollment (Phase 2.9.1)

The effectiveness of this hardening is only observable after a birth this PR deliberately does not
perform. That is a time-gated close criterion, so it is enrolled rather than left to memory:

- **Script:** `scripts/followthroughs/git-data-birth-emitter-6982.sh`, following the repo's
  documented three-state contract (`chardevice-wedge-nonrecurrence-5934.sh`): **`0` = PASS** — a
  field-isolated query returns ≥ 1 `boot_complete` event with all four assertions positive;
  **`1` = FAIL** — an event exists with a false assertion (the host booted dark); **`2` = TRANSIENT**
  — the host is still unborn, or the query is unreachable/unauthorised. **Unborn is TRANSIENT, not
  FAIL** (R21): using `1` would post a daily FAIL comment from `merge+1d` until the birth —
  potentially weeks — byte-identical in kind to the comment a genuine post-birth boot failure
  produces, training the reader to ignore the one signal that matters. `REOPEN_MAX` caps only the
  closed path, so the open path has no brake.
  It deliberately does **not** read the heartbeat API: `status == "up"` would prove reachability,
  the proxy D-HB rejects (and the API exposes no `last_event_at`, so no freshness computation is
  implementable anyway).
- **Tracker directive:** `<!-- soleur:followthrough script=scripts/followthroughs/git-data-birth-emitter-6982.sh earliest=<merge+1d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->`
  plus the `follow-through` label, on the tracking issue (**not** on #6982, which closes at merge).
- **Sweeper wiring (R4):** those three are the names `betterstack-query.sh` actually requires and the
  sweeper already passes. `BETTERSTACK_LOGS_QUERY_TOKEN` — v1's name — **exists nowhere in the
  repo**, and `sweep-followthroughs.sh` responds to an unknown `secrets=` name by failing and
  `return 0`-ing: issue left open, no comment, green run. That would have reproduced, inside the
  plan's own close-the-loop mechanism, the exact silent-failure class this PR exists to eliminate.

## Encryption Posture

`plan` Phase 2.11 fired (`.tf` + `cloud-init*.yml` in Files to Edit).

```yaml
at_rest:
  - store: hcloud_volume.git_data (/mnt/git-data, ext4, 10 GB) — the Phase-2 store; vestigial per #6976
    mechanism: plaintext-exception
    evidence: git-data.tf `format = "ext4"`, no LUKS apparatus; scripts/encryption-posture-ledger.json
              row `hcloud_volume.git_data`; model.c4 gitDataStore description states it verbatim.
    defends_against: nothing at rest. Hetzner volume-level tenancy isolation only.
    does_not_defend: a Hetzner-side snapshot/volume-detach read, a host compromise, or a
                     provider-side disk seizure — any of which yields every connected user's
                     source code in cleartext.
    disclosed_as: existing ledgered exception, tracking #6897, `disclosed_as: not-publicly-claimed`
                  (so no public statement is contradicted). PRE-EXISTING; neither introduced nor
                  widened by this plan.
    live_verification: n/a — never provisioned.
  - store: hcloud_volume.git_data_luks (/mnt/git-data-luks via /dev/mapper/git-data, LUKS2 -> ext4, 10 GB)
    mechanism: LUKS2 (cryptsetup luksOpen in cloud-init runcmd; passphrase random_password.git_data_luks,
               delivered via doppler_service_token.git_data reading GIT_DATA_LUKS_KEY)
    evidence: git-data-luks.tf; the LUKSEOF heredoc; drift-guarded by git-data-luks.test.sh.
              Resolution is by DEVICE BINDING (scripts/lint-encryption-posture.py), never name
              similarity — the plaintext sibling differs by one suffix.
    defends_against: offline disk/snapshot read of the cutover store.
    does_not_defend: a live host compromise (the mapper is open while mounted); and it does not
                     protect the plaintext sibling, which remains the live store until
                     GIT_DATA_STORE_ENABLED gates the cutover.
    disclosed_as: declared cutover target, not yet live. NOTE the Art. 30 register currently
                  asserts this in the PRESENT TENSE (PA-1 g13, PA-2 g17) — W10 corrects it, because
                  the birth is what converts a premature claim into a false one.
    live_verification: n/a pre-birth. Post-birth this is precisely what W1's STAGE=luks_open fatal
                       and the boot-completion mountpoint assertion make observable for the first
                       time — today a failed luksOpen is silent. W0's probe is a precondition: if
                       `doppler run` cannot read the key, luksOpen never runs at all.
  - store: swap
    mechanism: none — DELIBERATELY ABSENT
    evidence: no swap is configured anywhere in cloud-init-git-data.yml (verified).
    defends_against: n/a
    does_not_defend: n/a
    disclosed_as: a design decision, not an omission (D-SIZE companion). An unencrypted root-disk
                  swapfile could page plaintext git object data out from under the LUKS posture, so
                  memory is BOUNDED instead. Any future swap here must be random-key dm-crypt.
    live_verification: an AC asserts no swap is configured in the rendered boot path.

in_transit:
  - connection: web host -> git-data (git transport: upload-pack / receive-pack)
    tls: n/a — SSH transport (ED25519 forced commands over the private net to 10.0.1.20:22)
    cert_verification: on — host-key pinning via the web host's known_hosts; three distinct
                       forced-command keypairs (transport / provision / remove).
    does_not_defend: an attacker already inside the private segment observes connection metadata;
                     the transport wrapper's two-verb allowlist is the only authorisation boundary
                     once a key is held.
    disclosed_as: existing design (ADR-068), unchanged by this plan.
  - connection: git-data -> Sentry (boot-fatal + boot-completion emit)   [NEW]
    tls: yes — HTTPS to the DSN host (de.sentry.io ingest, DE residency, Art. 30 PA8 (e))
    cert_verification: on — plain `curl`, default verification; NO -k/--insecure anywhere.
    does_not_defend: content confidentiality FROM Sentry. Mitigated by the ADR-147 sanitiser chain,
                     whose ORDER is load-bearing: preamble strip -> ANSI strip -> dp./gh_/URI-userinfo/
                     Bearer/PEM redaction -> control-char strip -> newline fold -> trim -> tail -c 180
                     -> tr -cd '\040-\176'. PLUS the value-based redactor (enumerate known secret
                     values and substitute), because pattern matching alone misses a passphrase that
                     looks like ordinary text.
    disclosed_as: Sentry is an existing sub-processor with a DE-residency ingest edge already in the
                  Art. 30 register. This adds a new EMITTER, not a new processor — no DPA re-sign,
                  no Art. 28(4) flow-down event, no TC_VERSION bump.
  - connection: git-data -> Better Stack Logs (stage markers, disk/gc events)   [NEW]
    tls: yes — HTTPS POST to https://s2457081.eu-fsn-3.betterstackdata.com/
    cert_verification: on — plain `curl`, default verification.
    does_not_defend: content confidentiality FROM Better Stack. Same sanitiser chain. CRITICAL
                     ADDITIONAL CONSTRAINT (CLO finding D): `vector.toml`'s pii_scrub_string does NOT
                     scrub a BARE UUID in free text, and on this host workspace_id === user_id with
                     repos named <workspace_id>.git — so NO emitted line may contain a repo path or
                     workspace/user UUID. Enforced by AC22-AC24, not by a note.
    disclosed_as: Better Stack s.r.o. is already a PA-8 (d) recipient (EU region eu-fsn-3,
                  Falkenstein, source 2457081), and vector.toml records the design intent that
                  2457081 is "the ONE Logs source — host_name is the sole discriminator". A fifth
                  emitting host on the same source is the architecture working as designed. Art. 30
                  PA-8 (c)(ii)/(d)/(f)/(g) amended by W10 as a record-keeping discharge (Art. 30(1)(d)).

exception:
  - row: hcloud_volume.git_data (plaintext-exception)
    justification: PRE-EXISTING. The plaintext volume is the Phase-2 store; the LUKS volume is the
                   declared cutover target gated by GIT_DATA_STORE_ENABLED. This plan neither
                   introduces nor widens it — it makes a failed luksOpen OBSERVABLE for the first
                   time, a prerequisite for ever completing the cutover.
    tracking_issue: 6897
    reevaluate_when: the GIT_DATA_STORE_ENABLED cutover completes (#5274 Phase 3)
    expires_on: UNCHANGED from the existing ledger row — this plan MUST NOT extend it. AC10 asserts
                the row's expires_on is byte-identical to origin/main's.
```

## Open Code-Review Overlap

Checked `gh issue list --label code-review --state open --limit 200` against every path in *Files to
Edit* / *Files to Create*. **None** — zero open `code-review` issues reference any planned path.

**Adjacent open issues that do overlap, with explicit dispositions:**

- **#6548** (*"soleur-git-data-prd is a second never-unpaused heartbeat — and is absent from live
  Better Stack with no count gate"*) — **DEFER, with findings recorded.** The first draft proposed
  folding it in; D-HB withdraws that. This PR comments on #6548 with the three blockers its
  implementer must resolve first: (i) `arm_one` for `git_data_prd` lives in the **per-merge apply
  job**, so creating the monitor makes git-data reachability a merge-blocking dependency for the
  whole repo; (ii) the beat proves **reachability, not boot correctness**, so it must be labelled as
  such and must not be sold as a boot signal; (iii) the Better Stack object pool may be at **10/10**,
  and the free slot is the un-Terraformed `app.soleur.ai/health` monitor. Plus the #6975 dependency.
- **#6975** (*"git-data heartbeat key is unsuffixed — a healthy web-1 probe MASKS a dead
  web-2→git-data path"*) — **ACKNOWLEDGE.** Its premise, recorded in-code as *"single-host makes
  masking moot"*, is now **stale**: `var.web_hosts` contains both web-1 and web-2, and
  `cloud-init.yml` enables `web-git-data-probe.timer` on any fresh host, so both hosts ping the same
  unsuffixed URL today. This PR does not fix it and does not make it harder; a re-evaluation note
  recording the staleness is posted.
- **#6977** (*"git-data has NO birth route"*) — still open although PR #6989 merged the route.
  **ACKNOWLEDGE.** #6982 releases its interlock; its own closure is the #6977 owner's housekeeping.
- **#6897** (encryption-posture ledger row) — **ACKNOWLEDGE.** Untouched, not extended.
- **#6976** (`hcloud_volume.git_data` vestigial) — **ACKNOWLEDGE.** W5 targets
  `/mnt/git-data-luks` for reclaim in line with it; no ownership claimed.

## Domain Review

**Domains relevant:** Engineering, Legal, Operations. **Product: NONE** — the mechanical UI-surface
override did not fire; no path in *Files to Create*/*Files to Edit* matches `components/**/*.tsx`,
`app/**/page.tsx`, `app/**/layout.tsx`, or any UI-surface term. This is a host-provisioning change
with no user-facing surface, so the Product/UX Gate is skipped and **no `.pen` wireframe is
required** (`wg-ui-feature-requires-pen-wireframe` does not fire).

**Brainstorm-recommended specialists:** none (no brainstorm preceded this plan; the 2026-07-27
git-data brainstorm belongs to #6570 and was read as research input, not as this plan's brainstorm).

### Engineering (CTO)

**Status:** reviewed.
**Assessment:** Found one unlisted P0 (the `doppler run` config-scope mismatch, now W0/Phase 0) and
falsified the plan's "post-birth uncorrectable" premise (the `git-data-host-replace` route exists;
the honest argument is that the replace is destructive). Rejected the first draft's heartbeat design
on three independent grounds (per-merge `arm_one` wedge; reachability ≠ boot correctness; ADR-149's
verdict stands on better evidence) — now D-HB. Confirmed W8's feasibility trap is an artifact of one
assumed remedy, not structural, and prescribed the static-local + `depends_on` + three-way-registration
shape now in *Infrastructure (IaC)*. Named the highest-leverage residual risk: **the interlock is a
one-bit latch guarding a nine-item checklist, and the bit flips on threading, not on emitting** —
mitigated by mutation-battery arms that go red when the trap and the emits are neutered (AC25), by
doing W0's probe first, and by keeping W9 (the banner) as the final commit with an item-by-item
checklist in the PR body. Recommended a 4-PR split; see A12 for why this plan keeps it atomic and
what the split boundary is if `/work` needs one.
**Capability gaps:** none — every mechanism exists in-repo.

### Legal (CLO)

**Status:** reviewed.
**Assessment:** Corrected the legal characterisation of the Art. 17 defect: it is **not** an Art. 17
breach (the throw is caught, deletion proceeds, and pre-cutover the store holds nothing) but an
**Art. 5(2) accountability-evidence** failure — PA-8 (b)(ii) designates Sentry as the canonical
Art. 33 first-observed-at anchor, and a deterministic 100 %-false "erasure failed" event on every
deletion makes a genuine future failure indistinguishable from the noise floor, silently voiding the
PA-8 (g) TOM. Must-fix (W8). Surfaced a scope item nobody had listed: the Art. 30 register asserts in
the **present tense** that the git-data volume is LUKS-encrypted (PA-1 g13, PA-2 g17) — harmlessly
premature today, **false the moment the host is born onto the plaintext volume** — must-fix via the
DRAFTED / NOT-YET-ACTIVE wrapper PA-2 already uses (W10). Surfaced the cross-item PII collision
(items 1 + 5 together, neither alone) now bound by AC22–AC24. Flagged that quota-triggered pruning
of user content has **no contractual basis** — no storage-limit clause exists in T&C or AUP — which
blocks *arming* a content-deleting prune, not building one. Confirmed: **no new sub-processor, no
new third-country transfer, no DPA re-sign, no public-doc amendment.**

### Operations (COO)

**Status:** reviewed.
**Assessment:** Confirmed `cpx22` on cost grounds (the only orderable saving is `cpx12` at
−$103.68/yr, which does not buy a destructive replace-dispatch on an unmeasured host; `ccx13` is
+$304.56/yr). Live-probed Hetzner: `cx23`/`cx33`/`cax11` are out of stock in all three EU DCs and
**cannot birth**; `cx22` is a **phantom SKU** that ADR-143 lists as a fallback (same class as the
`cx32` that destroyed the registry host, #6288). Found the ledger defect (W11): birth creates **two**
10 GB volumes and the ledger books one, at a stale $0.48 against a live $0.62 — required before
PR-ready per `wg-record-recurring-vendor-expense-before-ready`. Flagged the Better Stack object pool
at a possible **10/10** and the Sentry PAYG headroom at ~$7.78 with a 2026-08-16 cliff — both
reinforcing the W2 deferral and the no-new-Sentry-cron-monitor choice. Confirmed **no
non-automatable operator action exists** anywhere in this scope. Account limits are not binding
(servers 4/10, volumes 110/1024 GB, IPv4 8/20).

#### Findings

Folded into the sections above and into *Risks & Mitigations*, rather than duplicated here.

## GDPR / Compliance Gate

`plan` Phase 2.7 fired on trigger (b) — a `single-user incident` threshold — and on the Art. 17
surface, not the canonical schema/migration regex.

**A. Art. 5(2) accountability failure (not an Art. 17 breach) — MUST FIX IN THIS PR (W8).**
`resolveGitDataSshHost()` returns the `10.0.1.20` default **only when `NODE_ENV !== "production"`**;
in prd it **throws**. `GIT_DATA_SSH_HOST` has **no producer anywhere in the repo**.
`removeGitDataRepo` is deliberately **not** gated on `isGitDataStoreEnabled()` — flag-gating erasure
would strand PII across a rollback window — it gates on the remove key's presence, and that key
co-lands with the server. So after any successful birth plus the next `ci-deploy`, **every** account
deletion throws, is caught, and files a false *"Art. 17 erasure failed"* event into the channel
PA-8 (b)(ii) designates as the canonical Art. 33 anchor. Deletion still succeeds and no data subject
is harmed — the harm is that a 100 %-false-positive detective control **is not a control**.
Must-fix because this plan is the gate that authorises the first birth, and the defect goes live at
that birth.

**B. Empty-store Art. 17 silent success (ADR-149 Residual 3) — DEFER, gate-bound not date-bound.**
Post-birth and pre-cutover the store is empty and `git-data-remove.sh` is idempotent, so an erasure
exits 0 and records success for a repo the store never held. Substantively that record is
**accurate** — there is nothing to erase, so Art. 17 is satisfied in fact. It becomes a real
Art. 5(2) failure only once the store actually holds data. **The tracking issue must therefore be
bound to the `GIT_DATA_STORE_ENABLED` cutover — "must close before the flag flips in prd" — not to a
calendar date and not to the birth.** W1's boot-completion emit gives it the birth-completion marker
it needs, so the issue names a concrete design rather than an open question.

**C. Art. 30 register present-tense encryption claim — MUST FIX IN THIS PR (W10).** PA-1 limb
(g)(13) and PA-2 limb (g)(17) both assert, as registered Art. 32 technical measures, that *"the fresh
Hetzner block volume backing the bare per-workspace git data (objects/refs) **is** LUKS-encrypted at
rest."* Today no reader can be misled about a store that does not exist; **birth converts a premature
claim into a false one**, because the live store is the plaintext volume. In-repo precedent to copy
verbatim: PA-2 already carries a *"Cross-host workspace replication between web hosts — DRAFTED /
NOT-YET-ACTIVE"* row that opens by asserting it describes no present-tense processing. ~10 minutes.

**D. Log-content PII — the cross-item collision, MUST FIX before the log flow ships.** On this host
the repo identifier **is** the user identifier (`workspace_id === user_id`, mig-053 N2; repos named
`<workspace_id>.git`, echoed by `git-data-provision.sh` and `git-data-remove.sh`).
`vector.toml`'s `pii_scrub_structured` renames JSON *keys* only; `pii_scrub_string` scrubs
`userid=<token>` pairs, emails, bearer tokens and DSNs — **neither scrubs a bare UUID in free text**.
Today those echoes go to the SSH *channel* stderr under a forced command, not journald, and
`cloud-init-git-data.yml` defines **no systemd units at all** — so the exposure is conditional, not
live. **The condition is item 5**: a disk/reclaim unit naturally logs which repo it pruned, as a
systemd unit, into the emitter channel, naming user UUIDs. Neither item creates this alone; together
they do. Bound by AC22–AC24. Also noted: `vector.toml`'s pepper fail-safe leaves the line **raw** and
merely tags `+skipped_pepper_unset`, so a missing pepper degrades silently to no pseudonymisation —
another reason git-data's emitters must never carry an identifier that would need pseudonymising.

**E. Reclaim and the missing contractual basis — DEFER the arming, ship the distinction.** There is
no storage-limit or content-deletion clause in `docs/legal/terms-and-conditions.md` or
`acceptable-use-policy.md`; the only quota language governs *third-party* service quotas the user
must not exceed. So a **quota-triggered prune of reachable user content has no contractual basis**.
This plan does not need one, and the distinction is load-bearing: W5's reclaim collects **only
objects unreachable from any ref** — the garbage `--force` pushes orphan, which no user-visible ref
addresses. That is garbage collection, not deletion of user content. **AC26 pins it**: the reclaim
must be unreachable-only, and it must never be recorded as an Art. 17 pathway. A future
reachable-content quota needs the T&C/AUP clause first (A10, deferred).

**F. Record-keeping discharge (Art. 30(1)(d)) — this PR.** Amend PA-8 (c)(ii)/(d)/(f)/(g) to record
the additional emitting host on source 2457081. For **the emitter addition specifically**, no
public-document amendment is required: the privacy policy, GDPR policy and data-protection
disclosure already name the Hetzner git-data host and Better Stack at an abstraction level that
covers it, and all three vendor DPAs are signed and current. **No new sub-processor, no new
third-country transfer, no DPA re-sign, no Art. 28(4) flow-down event, no `TC_VERSION` bump.**

**F(ii). The public LUKS claim — corrected from v1's blanket (R33, CPO C1).** v1 said flatly *"no
public-document amendment is required"*, defended only for the emitter. That blanket is wrong as a
general statement, and a blanket surviving into the runbook reads as permanent clearance. The
identical present-tense claim W10 fixes internally is **published** in three places:
`docs/legal/privacy-policy.md`, its site mirror
`plugins/soleur/docs/pages/legal/privacy-policy.md`, and
`docs/legal/data-protection-disclosure.md`.

The correct scoping is narrower than it first looks, and the difference is load-bearing: the public
sentence is **conditional and predicated on *stored* data** (*"Where the Web Platform spans more than
one Hetzner host… **stored** workspace git data sits on…"*). Post-birth but pre-cutover the store is
empty, so the antecedent is not yet operative. **The public claim therefore goes false at the
`GIT_DATA_STORE_ENABLED` cutover, not at the birth** — one step later than the internal register,
which is a claim about the *volume* and does go false at birth. So: **§F is "not required at birth;
required before the cutover flag flips"**, no public-doc edit lands in this PR, and the three paths
join the **existing A11 cutover-bound tracking issue** — zero new machinery, and it is already
gated on exactly the right flag.

**G. Explicitly NOT this PR's to carry** (`wg-when-an-audit-identifies-pre-existing`, CPO C6). Two
pre-existing defects were found and must be filed separately rather than loaded onto an
eleven-workstream infra PR: (i) a blog post asserting *"No code is stored on Soleur servers"* — false
**today**, and one instance sits inside a `FAQPage` JSON-LD `acceptedAnswer`, the surface answer
engines quote verbatim with no page context; (ii) `docs/legal/acceptable-use-policy.md` §5.1 assigns
backup responsibility to the user for Plugin/local execution and **omits it from the Web Platform
list**, while no backup/restore/durability row exists anywhere in the roadmap. (ii) is CPO-owned.

## Implementation Phases

Phase order is **dependency-directed, not file-directed**: contract-changing edits precede their
consumers, and the probe that decides a design precedes the design.

### Phase 0 — Probes and preconditions (no product code)

0.1 **W0 — the `doppler run` config-scope probe.** Mint a throwaway `read` service token scoped
**exactly as `doppler_service_token.git_data` is** (single config), then run
`doppler run --project soleur --config prd -- env` with it and **grep the resulting environment for
`GIT_DATA_LUKS_KEY`** (R36). Exit status is *not* the question: a CLI that silently resolves to an
empty `prd` view exits 0 with the key **absent**, which is the dark boot. Record the result verbatim.
0.2 Verify the birth-readiness gate currently **HOLDs**:
`source tests/scripts/lib/git-data-birth-readiness-gate.sh && git_data_birth_readiness_gate apps/web-platform/infra/cloud-init-git-data.yml; echo $?` → `1`. This is the RED half — prove the
gate can refuse before trusting it to release.
0.3 Measure the baseline `user_data` render: `gzip -9 -c <rendered> | base64 -w0 | wc -c`.
0.4 Classify **every** `runcmd` item must-abort / must-tolerate — **including the ones this PR
adds** (W4/W5/W6 add `systemctl enable --now git-data-gc.timer` and the sshd changes; v1's wording
said "every *existing* item" and would have left the new ones unclassified, R16). The nine current
items, pre-classified so this cannot be skipped:

| # | Item | Under `set -e` |
|---|---|---|
| 1 | `systemctl restart sshd` | **the real hazard** — must-tolerate, or gate on `sshd -t` (Phase 3.2). W6 edits the drop-in in this same PR, so a malformed directive aborts the boot. |
| 2 | `mkdir -p /mnt/git-data` | safe |
| 3 | `mount … \|\| true` | the sole already-declared must-tolerate; reclassify once 4.1's assertions cover it |
| 4 | `echo … >> /etc/fstab` | safe |
| 5 | `curl -fsSL` / `sha256sum -c -` / `tar xzf` / `chmod +x` / `rm` | must-abort **by design** — this is issue item 3. Note `rm` is unreachable-as-abort because `curl -f` aborts first. |
| 6–7 | `printf … > /etc/default/…`, `chmod 600` | safe |
| 8–9 | `. /etc/default/git-data-doppler`, `doppler run …` | must-abort by design |
0.5 Confirm `export HOME=/root` reaches the runcmd shell **before** any `doppler` invocation
(`cloud-final.service` synthesises no `$HOME`; the Doppler CLI resolves its home dir before reading
`DOPPLER_CONFIG_DIR`, so a missing `HOME` is `Doppler Error: $HOME is not defined` — three prior
dark boots).
0.6 Record the verification that ADR-149 item 6 (firewall entailment) is **already corrected**.
0.7 Confirm `scripts/betterstack-query.sh` supports the field-isolating query form the ACs use and
that its token is reachable from the sweeper workflow.

### Phase 1 — Terraform contract (W8, W7 description, the private-IP local)

1.1 Hoist `local.git_data_private_ip = "10.0.1.20"`; have `hcloud_server_network.git_data.ip` read
it. Do **not** reference `hcloud_server_network.git_data.ip` from the new secret.
1.2 Add `doppler_secret.git_data_ssh_host` (project `soleur`, config `prd`, name
`GIT_DATA_SSH_HOST`, `value = local.git_data_private_ip`, `visibility = "masked"`,
`lifecycle { ignore_changes = [value] }`, `depends_on = [hcloud_server.git_data]`).
1.3 Amend `variables.tf`'s `git_data_server_type` description (corrected D1 + the orderability
finding).
1.4 **Register the new address at all SIX sites, in this same commit** (R6, and Kieran's P1-9 —
v1 assigned these to no phase at all while its own IaC section required them to be one commit):
(i) the birth `-target` list in `apply-web-platform-infra.yml` (**18 → 20**, D1) and its "eighteen -targets"
prose; (ii) `_GIT_DATA_BIRTH_ALLOW`'s `def allow: [ … ]`; (iii) the gate's **separate hardcoded
presence loop** — the fourth site v1 never named, and the one whose omission lets a birth pass while
the Doppler write is absent; (iv) the gate's two prose counts; (v) `GIT_DATA_BIRTH_TARGET_BASES`
plus the two "eighteen members" comments in the parity test; (vi) the
`rest_thirteen_except`/`rest_thirteen_with` fixture helpers in `test-git-data-host-birth-gate.sh`.
**The address joins the PRESENCE half, never the entailed loop** — entailed would demand
`creates == 1` and reproduce ADR-149's *"Too strict → a permanent wedge"*.

### Phase 2 — The emitter (W1)

2.0 **Per D1**, re-add `doppler_secret.git_data_betterstack_logs_token` to
`doppler_config.git_data_prd` (the `registry_betterstack_logs_token` precedent), gated on W0's probe
result, and register it at all six sites alongside the SSH-host secret (birth `-target` set
**18 → 20**). It is read via `doppler run` **only** by the post-Doppler emits (boot-completion, gc
faults) — never by the early stages, which stay Sentry-only because the token is unreadable there.
2.1 `write_files:` **one** script, `/usr/local/bin/git-data-emit` (R13) — the Sentry store-API emit
from the baked DSN, with **no** Doppler fallback (the scoped token demonstrably cannot read
`SENTRY_DSN`, and a fallback that is dark by construction is worse than none because it reads as a
safety net). It applies the ADR-147 sanitiser chain **plus** the value-based redactor **internally,
on every path**, so "everything emitted is redacted" is structural rather than a convention two
sibling scripts must remember. Both in-repo precedents (`cloud-init.yml`'s `_emit`,
`cloud-init-registry.yml`'s `post()`) are one thing, not three.
2.2 Add `curl` to `packages:` and make the emitter degrade silently if it is nonetheless absent
(R23) — `packages:` today is `[git, util-linux, cryptsetup]`, yet the entire emit chain depends on
curl, and cloud-init treats a failed package install as **non-fatal**.
2.3 Add a `bootcmd:` beacon (R23). `packages:` and seven `write_files` entries all run **before**
`runcmd`; a failure there leaves sshd up — so the web-side reachability probe goes green — and emits
nothing. The web host carries a `bootcmd` for exactly this reason: a landed `bootcmd_start` with no
`runcmd_start` brackets the death to the pre-runcmd phase.
2.4 **Add the `git_data_boot_fatal` rule to `apps/web-platform/infra/sentry/issue-alerts.tf`**
(R1, AC33). Justify the `event_frequency` threshold in a comment against the group-shape rule that
file documents — do **not** copy `value = 1` without checking whether git-data's group is hot.
2.5 The `${sentry_dsn}` interpolation must land in **non-comment** template text — this is the
sentinel. `$${sentry_dsn}` does **not** count, and `validate-infra-templates.sh` skips any
`$${key}` by design, so it is blind to that direction; the readiness gate is the only thing that
catches it.

### Phase 3 — Fail-closed boot (W3)

3.1 First runcmd item: `export HOME=/root`, `STAGE=runcmd_early`, define `on_err`,
`trap on_err EXIT` **with the `rc=$?; [ "$rc" -eq 0 ] && exit 0` guard** (R7 — without it every
healthy boot emits `level=fatal`), then emit `runcmd-entered` **and assert the transport returned
2xx**, failing loudly otherwise (R8/AC34). No Better Stack token file — the boot channel is
Sentry-only (R3).
3.2 Add `sshd -t` before `systemctl restart sshd` (R16). This is the concrete hazard Phase 0.4's
classification must not miss: the restart is runcmd item #1, and **this same PR adds
`MaxStartups`/`MaxSessions` to the sshd drop-in** — a malformed directive under a newly-armed
`set -e` means a failed restart aborts runcmd, so LUKS never opens and the bootstrap never runs.
3.3 Turn on `set -e` **after** the Phase-0.4 classification; wrap each must-tolerate command in an
explicit `|| true` with a comment naming why.
3.4 `STAGE=` progression: `runcmd_early → sshd_restart → volume_mount → doppler_dl → doppler_verify
→ doppler_run → luks_open → bootstrap → done`. `STAGE=doppler_dl` sits immediately above the
`sha256sum -c -` / `tar xzf` / `chmod +x` block — the fix item 3 asks for.
3.5 **Arm a heredoc-local `STAGE=` and trap inside the `LUKSEOF` block** (R2). `luksOpen` runs in a
**child bash** under `doppler run`; the parent's `STAGE` and `on_err` do not cross the exec
boundary, so without this a failed `luksOpen` and a W0 scope failure both surface as
`STAGE=doppler_run` — collapsing the plan's single most important discriminator into another mode.
This is only possible because 2.1 ships the emitter as a `/usr/local/bin/` **binary** rather than the
web host's non-exported inline function: a child process can call it. Same `rc` guard.
3.6 Disarm (`trap - EXIT`) before handing to `git-data-bootstrap.sh` so a bootstrap-stage failure is
not re-emitted mislabelled; re-arm with a bootstrap-specific trap (same `rc` guard) capturing the
last 20 redacted lines of the captured bootstrap log.

### Phase 4 — Boot-completion signal (W1, ADR-149 item 4)

4.1 **This is ~90 % already implemented (R14) — the task is to give it a voice, not to write it.**
`git-data-bootstrap.sh` step 7 already asserts, fail-loud, every one of the four properties v1
proposed as new work: `mountpoint -q "$GIT_DATA_ROOT"`, `mountpoint -q "$LUKS_ROOT"`,
`[[ -x "$PRE_RECEIVE" ]]`, and the `git config --system core.hooksPath == $HOOKS_DIR` equality. The
only defect is that `log() { echo "[git-data-bootstrap] $*"; }` goes **nowhere off-box**. So: route
`log` through `/usr/local/bin/git-data-emit` on the FATAL paths, and add one success line at the end
emitting `stage:boot_complete` with the four booleans. The "augment-then-fail-closed vs pure
fail-closed" design discussion dissolves — the existing assertions already have the right shape.
4.2 Include the guest `df%` for `/mnt/git-data` (the **live** repo root) in the boot-complete
payload — this is where disk observability lives now that R11 cut the 15-minute timer.
4.3 No repo paths, no workspace/user UUIDs in any payload (AC22). The four booleans and a df
percentage carry no identifiers by construction, which is the point.

### Phase 5 — Store maintenance (W4, W5)

5.1 `git-data-bootstrap.sh`: add the `git config --system` set — `receive.autogc false`,
`gc.auto 0`, `gc.autoDetach false`, `pack.windowMemory`, `pack.packSizeLimit`, `pack.threads 1`,
`pack.deltaCacheSize`, `core.bigFileThreshold` — and add each to the existing fail-loud re-assert
block so a silently-dropped setting is loud.
5.2 `git-data-gc.service`/`.timer` — weekly; `MemoryMax=`, `CPUQuota=`, `IOSchedulingClass=idle`,
`Nice=19`; `OnFailure=` → a `SOLEUR_GIT_DATA_GC` fault event routed to the **R1 Sentry rule** (not
to a Better Stack poller — v1 declared that route and never built it, R12). Body: per-repo
`git repack -adq --window-memory=…` + `git reflog expire --expire-unreachable=now --all` +
`git prune --expire=…` over **`/mnt/git-data/repositories`** — the live root (R11/R34), not the
empty LUKS volume — and **unreachable objects only** (AC26). Held under `flock` on a shared lock so
it can never run concurrently with a cutover fsck window. Emits the guest `df%` on every run, which
together with 4.2 is the whole of the disk observability.
5.3 *(cut in v2 — R11.)* `git-data-store-monitor.{sh,service,timer}` polled `/mnt/git-data-luks`
every 15 minutes. That volume is **empty by construction** until the `GIT_DATA_STORE_ENABLED`
cutover — the plan's own GDPR §B says so — while `/mnt/git-data/repositories` (the filesystem that
actually fills) went unwatched. 96 events/day about a filesystem that cannot change. Disk state now
rides the boot-completion emit (4.2) and the gc run (5.2): zero new mechanism, correct mountpoint.
5.4 `mkfs.ext4 -q` → `mkfs.ext4 -q -O quota,project` on the LUKS volume. **Ship the flag; defer the
`prjquota` mount option** (R31) — they look like one decision and have opposite cost profiles. The
flag is genuinely migration-forcing: adding it later needs a replace **plus** an rsync of every
user's git objects. The mount option is not migration-forcing, does nothing until projects are
assigned (deferred, and legally blocked per GDPR §E), and introduces **a new way for the mount to
fail at boot** on a host with no SSH, no console and no recovery path — speculative generality
buying a fresh boot-failure mode on the very host whose boot fragility is this PR's subject. Note
the deferral in the runbook in one sentence.
5.5 *(cut in v2 — R12.)* There is no generic disk-recurrence poller to extend:
`scheduled-zot-restart-loop.yml` delegates wholly to `scripts/zot-restart-loop-alarm.sh`, a
zot-specific alarm with boot_id scoping, restart-count plateaus and a NIC discriminator. Building a
git-data equivalent is a new alarm script, not "the git-data grep" — and R11 removed the need.

### Phase 6 — Concurrency (W6) and the post-apply reader (R20)

6.0 **Add a post-apply boot-signal poll to the `git_data_host_create` job, `if: always()`.** This is
the actual ADR-149 item-4 discharge, and v1 shipped only its producer half. ADR-145's R2–R5 is a
**poll inside the birth job** — *"the job now waits [for] a bad outcome, which is what makes ADR-128's
R2 a signal rather than a step"* — whereas v1's only post-apply step was a text summary whose own
comment reads *"A green apply is NOT a green boot — and for THIS host there is currently no boot
signal at all."* An unread signal is not a signal. The credentials and the query tooling already
exist, so this costs one step: poll for `stage:boot_complete` with the four booleans, fail the job
if it does not arrive within the window or arrives with any false assertion.

6.1 `01-hardening.conf`: add `MaxStartups`, `MaxSessions`; tighten `ClientAliveInterval` 300 → 60.
Keep the `01-` prefix — OpenSSH is **first-match-wins** and Hetzner ships `50-cloud-init.conf`.
Declarative `write_files`, never `sed`.
6.2 `apps/web-platform/server/git-data-replication.ts`: a module-level in-process semaphore bounding
concurrent `provisionGitDataRepo` + `replicateToGitData` pairs. **Fail-soft on queue timeout** —
git-data is an overlay and session end must never block on it. Emit a `reportSilentFallback`-class
event when the limiter sheds, so shedding is visible. `server/concurrency.ts`'s `acquireSlot` is
**not** reusable — it is a DB-backed workspace-slot primitive, not an in-process semaphore.

### Phase 7 — Records (W7, W9, W10, W11) and tests

7.1 Amend ADR-068's addendum (D1-corrected + D-SIZE) and ADR-149 (checklist item 9 as merged, the D-HB
Alternatives amendment, the Residual 2 disposition).
7.2 W10 — Art. 30 register: wrap PA-1 (g)(13) and PA-2 (g)(17) in the DRAFTED / NOT-YET-ACTIVE
pattern; amend PA-8 (c)(ii)/(d)/(f)/(g) for the additional emitting host.
7.3 W11 — `knowledge-base/operations/expenses.md`: the existing `Hetzner Volume (git-data, 10 GB,
LUKS)` row is already annotated **"PHANTOM ROW — corrected 2026-07-15 (#6453)"**, so this is an
amendment to a corrected row, not a first correction. Add the **missing plaintext-volume row**
(birth's `-target` set creates `hcloud_volume.git_data` *and* `hcloud_volume.git_data_luks`), bring
both to `0.62` (live `volume.price_per_gb_month.net` = €0.0572/GB/mo × 10, vs the stale `0.48`),
strike the "no net-new / replacement not addition" reasoning for the **pre-cutover** period (it
describes the post-cutover steady state, and the #5274 Phase-3 cutover is Post-MVP), keep all
git-data rows `approved-not-billing` (this PR ships hardening, not the birth), and carry the standing
`<!-- estimate verify_by=… owner=cfo -->` marker. Mirror the shape of the existing
`Hetzner Volume (workspaces-luks, 20 GB)` row, which already handles the dual-volume case correctly.
7.4 Edit `model.c4` (two edges + two descriptions); run the C4 tests.
7.5 W9 — `git-data-birth.md`: **retain** the DO-NOT-DISPATCH banner and rewrite its release
condition to name the W12 rehearsal evidence; add a **sizing** row and an **emitter-verified** row
to *Before you dispatch*; add a post-birth verification section built from `discoverability_test`;
note the ForceNew-comment hazard. File the banner-clear follow-up issue (AC32).
7.6 Tests — **append to already-registered suites** wherever possible (`git-data-luks.test.sh`
already opens `cloud-init-git-data.yml` and carries `assert_mutation`). Any **new** `*.test.sh` MUST
also get an explicit `run: bash …` step in `.github/workflows/infra-validation.yml` — the infra
orphan reporter is **advisory and returns 0**, so an unregistered suite gates nothing and nothing
tells you.
7.7 *(cut in v2 — R15.)* `tests/scripts/test-git-data-birth-readiness-gate.sh` **already** carries
the `RELEASED` arm plus the interpolation-beside-comment and beside-escaped-literal arms. The work
is done; do not re-write it.
7.8 File the deferred tracking issues (A10 quota assignment + T&C clause; A11 Residual 3 bound to
the cutover flag; the ADR-143 `cx22` phantom SKU; the registry-volume ledger cell) and create the
follow-through probe + tracker.
7.9 Post the #6548 and #6975 comments.

### Phase 8 — Rehearsal (W12), after the code exists and before PR-ready

8.1 Rung (1): render the real template and execute the `runcmd` in the pinned Ubuntu 24.04 container
harness; capture every emitted payload. This is also where T5/T6/T15/T16 run.
8.2 Rung (2): boot the rendered template once on a throwaway `cpx22` **outside** the
`hcloud_server.git_data` address, with stub volume ids and a scratch Doppler branch config; observe
the three artifacts off-box; destroy the host. This is the rung that answers W0 for real.
8.3 Pin the evidence per AC31. If rung (2) is unreachable in-session, say so explicitly and move the
requirement onto the banner-clear follow-up issue (AC32) rather than letting it lapse.

## Acceptance Criteria

### Pre-merge (PR)

1. `source tests/scripts/lib/git-data-birth-readiness-gate.sh && git_data_birth_readiness_gate apps/web-platform/infra/cloud-init-git-data.yml` exits **0** and prints `RELEASED`.
2. *(cut in v2 — R15. `tests/scripts/test-git-data-birth-readiness-gate.sh` already carries the
   trailing-comment and escaped-`$${sentry_dsn}` arms; this AC asserted existing green.)*
3. `terraform console`-rendered `cloud-init-git-data.yml` passes `cloud-init schema -c <rendered>`,
   and the render is **< 32768 bytes** measured the way Hetzner measures it — **Terraform's own
   `base64gzip` default compression level, not `gzip -9`** (R38: `-9` overstates headroom on what
   this plan calls a hard gate). Assert via `terraform console` on the real
   `base64gzip(templatefile(…))` expression, not a shell approximation.
4. `grep -cP '(?<!%)%\{' apps/web-platform/infra/cloud-init-git-data.yml` returns **0** — a bare
   Terraform directive is forbidden, but the doubled `%%{…}` that `curl -w` requires must pass
   (R5: a plain `grep -c '%{'` matches `%%{` as a substring and would fail every correct
   implementation).
5. `MaxStartups` and `MaxSessions` each appear **inside the `01-hardening.conf` `write_files` block**
   (assert the anchor, not the bare token), and `ClientAliveInterval` is `60`.
6. `git-data-bootstrap.sh` sets `receive.autogc`, `gc.auto`, `gc.autoDetach`, `pack.windowMemory`
   and `pack.threads`, **and** each appears in the script's fail-loud re-assert block.
7. `terraform plan` on the **per-merge** allow-list path shows **zero** `create` actions for any
   `*git_data*` address.
8. `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes, with **three** arms
   (R6, R19):
   (a) the workflow `-target` list, `_GIT_DATA_BIRTH_ALLOW`'s `def allow: [ … ]`, and
   `GIT_DATA_BIRTH_TARGET_BASES` are equal **and** the gate's separate **presence loop** is
   extracted and asserted, so `presence ∪ entailed ∪ {server} ∪ {firewall_attachment} ==
   GIT_DATA_BIRTH_TARGET_BASES` — v1's three-way check left a **fourth** site unguarded, and a
   three-of-four edit was green;
   (b) the new address is in `OPERATOR_APPLIED_EXCLUSIONS` and joins the **presence** half, never
   the entailed loop (which would be a permanent wedge);
   (c) **the zero-of-N case**: every `doppler_secret.*` and `betteruptime_*` address declared in
   `git-data.tf` appears in either the birth target set or `OPERATOR_APPLIED_EXCLUSIONS`. Without
   (c), adding the resource and touching none of the registration sites is completely silent — the
   parity census does not cover general resources, and an untargeted resource is never planned.
9. `git diff origin/main -- plugins/soleur/lib/heartbeat-manifest.ts` is **empty** — the mechanical
   form of the W2 deferral (R18). *"`heartbeat-reprovision-parity.test.ts` passes unchanged"* was
   wrong twice: `bun test` never reports "unchanged", and that suite reads
   `apply-web-platform-infra.yml`, which this PR **does** edit.
10. `python3 scripts/lint-encryption-posture.py` passes, and
    `git diff origin/main -- scripts/encryption-posture-ledger.json` shows **no change to any
    `expires_on`**.
11. `bash apps/web-platform/infra/run-registered-suites.sh` is green, and **every new `*.test.sh`
    has a matching `run: bash …` step** in `.github/workflows/infra-validation.yml` (assert by
    grepping the workflow for each new suite path).
12. `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` pass; `model.c4` contains
    a `gitDataStore -> betterstack` edge and a `gitDataStore -> sentry` edge.
13. `git-data-birth.md` **still contains** the `DO NOT DISPATCH` banner (the clear moves to the W12
    follow-up PR), its text is updated to name the W12 rehearsal evidence as the release condition,
    and its *Before you dispatch* table gains a sizing row and an emitter-verified row.
14. All **three** sites of the unqualified *"neither CPU- nor RAM-bound"* claim are burst-qualified —
    ADR-068's addendum D1, `variables.tf`'s `git_data_server_type` description, **and**
    `knowledge-base/operations/expenses.md` (the third site v1's Phase 7.3 never assigned, R27).
    Verified by
    `grep -rn "neither CPU- nor RAM-bound" --include='*.tf' --include='*.md' --exclude-dir=archive --exclude-dir=plans --exclude-dir=specs .`
    returning only qualified occurrences. **The `--exclude-dir` flags are load-bearing**: without
    them the command matches this plan file itself (R27).
15. ADR-149 carries the sizing checklist item — **item 9 as merged**, not item 8: #7003 landed
    the DC-2 mandate as item 7 while this branch was open, so banner-clearing moved to 8 and
    sizing to 9 (see the ADR's `Disposition — #6982` table) — and an Alternatives amendment
    recording D-HB's three findings with the original reasoning preserved.
16. The `resource "doppler_secret" "git_data_ssh_host"` **block** in `git-data.tf` has
    `value = local.git_data_private_ip` and **no `depends_on`** — asserted by extracting the block
    (e.g. `awk '/resource "doppler_secret" "git_data_ssh_host"/,/^}/'`) and checking both
    properties. v1's `grep -rn 'GIT_DATA_SSH_HOST' … *.tf` was case-sensitive and would have matched
    only the `name =` line, never the `value =` line the AC exists to pin (R28). The absent
    `depends_on` is the R9 correction and is what keeps the address free of any edge that could drag
    `hcloud_server.git_data` into an upstream `-target` closure.
17. *(cut in v2 — R37. "the literal is single-sourced" is a refactor with no behavioural
    consequence; AC16 already pins the property that matters.)*
18. The client-side limiter exists and sheds visibly: a unit test drives N+1 concurrent
    `replicateToGitData` calls, asserts at most N in flight, **and** asserts shedding emits an
    observable event rather than failing silently.
19. *(cut in v2 — R37. Asserting the absence of a thing nobody proposed adding; A6 already rejects
    swap with reasons.)*
20. `scripts/followthroughs/git-data-birth-emitter-6982.sh` exists, is executable, exits **2
    (TRANSIENT)** against today's unborn live state (R21 — **not** 1/FAIL, which would post a daily
    false-alarm comment for weeks), **and the sweeper can actually execute it**: every name in its
    `secrets=` directive is present in `scheduled-followthrough-sweeper.yml`'s env block. The second
    half is the one that matters — v1's proven-RED arm was satisfied by a *credential* failure, so
    the probe could never have flipped to pass (R4).
21. *(cut in v2 — R37. Process ceremony; W0's own probe catches a mismatched design.)*
22. **No emitted line carries a repo path or a workspace/user UUID.** Asserted mechanically with all
    three v1 gaps closed (R17): the fixture repo lives at **`/mnt/git-data/repositories/<uuid>.git`**
    — the real `REPO_ROOT` per `git-data-provision.sh`, not the empty LUKS volume, against which the
    grep would have passed vacuously; the assertion is a **UUID-shape regex**, not the literal
    fixture string, because the sanitiser chain ends `tail -c 180` and a truncated-but-still-
    identifying prefix survives a literal grep; and it carries a **mutation arm** — emitting a repo
    path must turn the suite red.
23. The redactor test covers **both** the pattern chain (in the ADR-147 order) and the value-based
    substitution, including a passphrase-shaped value that no pattern would catch.
24. `/var/log/cloud-init-output.log` content is never forwarded verbatim: any log excerpt in an
    emitted payload passes through `git-data-redact` first, and a test asserts a fixture containing
    a Doppler token and an OpenSSH private-key block emerges redacted.
25. **Mutation arms go red when the observability is neutered:** neutering the `trap on_err`, the
    Sentry emit, or the boot-completion emit each turns a registered suite red (the `assert_mutation`
    discipline `git-data-luks.test.sh` already applies to `doppler run`).
26. The gc/reclaim body touches **unreachable objects only** — a test asserts that a ref-reachable
    object survives a reclaim run — and no artifact describes reclaim as an Art. 17 pathway.
27. Art. 30 register: PA-1 (g)(13) and PA-2 (g)(17) carry the DRAFTED / NOT-YET-ACTIVE wrapper, and
    PA-8 records the additional emitting host.
28. `knowledge-base/operations/expenses.md` contains **two** git-data volume rows, both at `0.62`,
    both `approved-not-billing`, with the "no net-new" claim struck for the pre-cutover period.
29. PR body carries `Closes #6982` **only**; comments are posted to #6548 and #6975 with the
    findings named in *Open Code-Review Overlap*; and the deferred tracking issues from Phase 7.8
    exist and are linked.
30. **The boot-completion emit does not claim the repositories are encrypted at rest.** Its four
    fields are `luks_mounted` / `repo_root` / `hooks_path` / `provision`, and a grep of the emit's
    payload construction returns **zero** occurrences of any at-rest-encryption claim about the
    repo data (per the *Precision note*). The same wording constraint is asserted on the runbook's
    new emitter-verified row.
31. **W12 rehearsal evidence is pinned in the PR body**: which ladder rung was reached, and — for
    each of the three artifacts (Sentry fatal event, ≥1 Better Stack stage marker, one
    `SOLEUR_GIT_DATA_BOOT_COMPLETE` row with its four booleans) — the retrieval query and the
    observed result. If only rung (1) was reachable, the PR body says so explicitly and the
    banner-clear follow-up issue records rung (2) as its own precondition.
32. **The banner-clear follow-up issue exists**, is linked from the PR body, and its body states the
    W12 rung-(2) evidence requirement plus the ADR-149 checklist items it discharges.
33. **The Sentry emits are readable by a human without anyone deciding to go look.**
    `apps/web-platform/infra/sentry/issue-alerts.tf` contains a `git_data_boot_fatal` rule whose
    filter matches this plan's `stage` tag values, and its `event_frequency` threshold is justified
    in a comment against the group-shape rule that file already documents — **`value = 1` must not
    be copied blindly**: it works for `web_terminal_boot_fatal` only because that shared group is
    always already hot, and on a fresh per-deploy group `value = 1` means ">1", so a single event
    does **not** page. git-data's first-ever boot fatal is by definition the first event in its
    group. Without this rule every emit this plan adds is write-only (R1).
34. **The emitter is proven to deliver before `set -e` is armed.** At `STAGE=runcmd_early` the boot
    path emits `runcmd-entered`, checks the transport returned 2xx, and fails loudly otherwise. A
    test asserts that an emitter which is missing, non-executable, or non-delivering produces a
    **loud** failure — not the silent `exit 1` the web-host precedent's trailing `|| true` would
    give (R8). This replaces v1's T6, which asserted the dark boot as a *passing* scenario.
35. **Birth-apply ordering is pinned so a partial birth cannot re-open what W8 closes.**
    `doppler_secret.git_data_ssh_host` cannot land after `doppler_secret.git_remove_ssh_private_key`
    — a birth landing the server plus the remove key but not the ssh-host secret returns
    `removeGitDataRepo` to the throw path, and the host is un-completable by hand (R22).
36. **A healthy boot emits zero fatals.** The `trap on_err EXIT` carries the
    `rc=$?; [ "$rc" -eq 0 ] && exit 0` guard at every arming site — the top-level trap, the
    bootstrap re-arm, and the heredoc-local trap. Without it every successful boot emits
    `level=fatal`, inverting the entire fatal channel (R7).

### Post-merge (operator)

**Empty by design.** Every item above is verified in CI or by an automatable command, and the COO
review confirmed **no non-automatable operator action exists anywhere in this scope**. The **birth
dispatch** is not a deferred step of this PR — it is a separate, independently-authorised production
write governed by `git-data-birth.md`, and it is the follow-up this PR *enables*. The follow-through
probe (AC20) closes the loop without relying on human memory.

## Test Scenarios

| # | Given | When | Then |
|---|---|---|---|
| T1 | `cloud-init-git-data.yml` on `origin/main` | the readiness gate runs | exit 1, `HOLD` — proves the gate can refuse |
| T2 | the same file with only a **trailing comment** naming `${sentry_dsn}` | the gate runs | exit 1 — prose must not release the interlock |
| T3 | the same with `$${sentry_dsn}` | the gate runs | exit 1 — terraform renders it as text |
| T4 | the post-change file | the gate runs | exit 0, `RELEASED` |
| T5 | the Doppler block with a deliberately wrong `DOPPLER_SHA256` | the rendered runcmd runs in a container harness | aborts at `sha256sum`; `tar xzf` and `chmod +x` never run; one `STAGE=doppler_dl` fatal is emitted |
| T6 | **(replaced in v2 — R8)** the emitter binary missing, non-executable, or its transport returning non-2xx | the boot path reaches `STAGE=runcmd_early` | the delivery assertion **fails loudly**. v1's T6 asserted the opposite — *"DSN empty → the abort still happens"* — which certifies the dark boot as a **passing** scenario, i.e. exactly the state the interlock exists to prevent. |
| T17 | a fully healthy boot | the whole runcmd chain runs to `stage:boot_complete` | **zero** `level=fatal` events are emitted — the `rc=$?; [ "$rc" -eq 0 ] && exit 0` guard holds at all three arming sites (top-level, bootstrap re-arm, heredoc-local) |
| T18 | a boot where `doppler run` resolves to an empty config view | the LUKS heredoc runs | the failure is reported as `STAGE=luks_open` (or a distinct `doppler_run` scope stage), **not** collapsed into one indistinguishable stage — R2's discriminator is preserved |
| T7 | a boot where the LUKS mapper is absent | the boot-completion stage runs | it reports `luks_mounted=no` and fails loud — it does **not** report success |
| T8 | a bare repo with unreachable objects from a prior `--force` push, plus one ref-reachable object | the gc timer body runs | unreachable objects are collected; the **reachable object survives**; the unit stays within `MemoryMax=` |
| T9 | a push arriving while gc holds the lock | `git-receive-pack` runs | the push succeeds (`receive.autogc=false` keeps gc off the push path) and gc does not run concurrently with a cutover fsck |
| T10 | `/mnt/git-data-luks` above the warn threshold, with repos named with real UUID shapes | the maintenance run reports | **AS SHIPPED: there is no `SOLEUR_GIT_DATA_DISK` event and no separate store monitor.** Disk state rides the `SOLEUR_GIT_DATA_GC` `gc_report` emit and the `boot_complete` emit, as `disk_pct` + `inode_pct` tags — a deliberate choice recorded at §853 of this plan (no 15-minute poller). The assertion that survives is the one that mattered: aggregate counts and `df%`/inode% only, and **zero** UUID substrings in the payload. |
| T11 | N+1 concurrent session-ends | the limiter is engaged | at most N concurrent replications; the shed path emits an observable event and does **not** block session end |
| T12 | tfplan for the per-merge allow-list path | destroy-guard + parity tests run | zero git-data creates; parity green three ways |
| T13 | tfplan for the birth path including the SSH-host secret | `git-data-host-birth-gate.sh` runs | PASS — 1 host create, 3 entailed creates, firewall attachment bound to exactly 1 server, all presence members create-or-no-op, 0 destroys / 0 firewall rules / 0 passphrase mutations / 0 reboots / 0 out-of-scope |
| T14 | live state today (host unborn) | the follow-through probe runs | **AS SHIPPED: exit 2**, not 1, with a "still waiting" message and not a false alarm. The probe reserves **exit 1** for the genuine FAIL case (a `boot_complete` event carrying a FALSE assertion — a host that reached its final stage with an invariant unmet) and uses **exit 2** for every transient/not-yet condition, so "the host is not born" can never be mistaken for "the host booted dark". |
| T15 | a payload fixture containing a Doppler token, an OpenSSH private key and a passphrase-shaped value | `git-data-redact` runs | all three are redacted — the value-based arm catches the one no pattern would |
| T16 | the `trap on_err` / Sentry emit / boot-completion emit each neutered in turn | the registered suites run | each mutation turns a suite **red** |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The interlock is a one-bit latch guarding a nine-item checklist, and the bit flips on threading, not on emitting.** The gate's own success message says so, and a prior probe found that repointing its path argument at the web host's cloud-init left every suite green and released the gate. A well-intentioned PR that threads `sentry_dsn` without a working emitter permanently releases the hold on the route that creates the store holding every user's source code. **W12's rehearsal is the primary mitigation** — it converts the release condition from "the variable is referenced" to "the signal was received", and it is the only safeguard here that is not static. AC25's mutation arms are the secondary one: they prove the code *can go red when neutered*, which is necessary but never proves an event *arrives* when it is intact. W0's probe runs first, so "the credential is unreadable" is discharged before the design depends on it. And the banner-clear **moves out of this PR** (W12(b)): a PR merges atomically, so a banner cleared in the final commit clears at the same instant as the untested code it is meant to be downstream of. The PR body walks the checklist item-by-item so a reviewer checks nine boxes rather than trusting one bit. |
| **`set -e` un-gates previously-tolerated non-zero exits and bricks every future boot.** The precedent is exact: a prior fix added assertions above the heredocs that create the files, under a top-level `set -e`, and would have darkened every new host, unpaged. | Phase 0.4 enumerates and classifies **every** runcmd item before `set -e` is armed; each must-tolerate command gets an explicit `|| true` with a naming comment. T5/T6 exercise the abort path in a harness. The emitter ships **before** `set -e` is armed (Phase 2 precedes Phase 3), so the first thing that can abort already has a voice. |
| **W0's scope mismatch is worse than assumed and blocks the emitter design.** | It is Phase 0.1, before any design commits. Two remedies are pre-specified (bake vs correct-then-read); AC21 requires the shipped design to match the probe result rather than an assumption. |
| **PII leak through the new channel** — repo paths are user UUIDs and `pii_scrub_string` does not catch bare UUIDs. | AC22 asserts zero UUID substrings across every emitter and unit body with a UUID-shaped fixture; AC23/AC24 cover the redactor's two arms and the log-excerpt path. The design avoids the hazard structurally: the monitor emits **aggregate** counts, never per-repo rows. |
| **Comment edits to `cloud-init-git-data.yml` destroy a live host** (`user_data` is ForceNew, no `ignore_changes`). Free today; a replace dispatch the day after birth. | A warning banner at the template head and a runbook note. Recorded as a residual, not claimed fixed — `ignore_changes = [user_data]` would forfeit the clean replace-to-reprovision path the resource comment says is deliberate. |
| **`user_data` budget overrun.** | AC3 pins the measured base64-of-gzip value with headroom. The single largest candidate addition — a Vector agent — is rejected outright (A1). Comments count; prose bloat caused both prior breaches. |
| **Partial-birth surface widens with every new address.** | Additions held to one (or two if W0 forces it); all three registration sites edited in the same commit; the parity test's exact-length equality makes a two-of-three edit fail loudly. |
| **A green suite that asserts nothing.** The two most recent git-data PRs each shipped green batteries an agent panel then holed — one because `source`-ing a gate only *defines* the function, one because the two endpoints were asserted and the wire between them was not. | Every gate assertion asserts the **invocation** and that the step cannot be skipped; every new probe has a proven-RED arm (T1, T14, T16, AC20). New `*.test.sh` files must be registered in `infra-validation.yml` or they gate nothing (AC11). |
| **Sizing is wrong.** | D-SIZE keeps headroom rather than the $104/yr saving, and W4 converts the boundedness claim from an assertion into an enforced invariant. The residual — no pre-birth measurement is possible — is stated in the ADR rather than papered over, and ADR-149 item 9 (as merged) plus the runbook row make the next person confront it. The correction path (a destructive replace) is stated accurately, not overstated. |
| **Art. 5(2) accountability failure after birth.** | W8, in this PR, with the trap dissolved by static-literal sourcing. |
| **Scope size — eleven workstreams in one PR.** | See A12. The forcing function is shared (all pre-dispatch, and the sentinel releases the route on merge), the birth itself is out of scope, and the split boundary is pre-specified if `/work` needs one. |

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| **A1 — Install a Vector agent on git-data** | **Rejected**, three independently sufficient reasons. (a) *Delivery*: the shared `vector.toml` is 27 KB against ~10.8 KB of `user_data` headroom; a git-data-specific trim would duplicate the PII-scrub chain, the part that must not drift. (b) *Credentials*: Vector reads `BETTERSTACK_LOGS_TOKEN` via `doppler run`, and git-data's token is scoped to a single config holding only `GIT_DATA_LUKS_KEY` — the "dark by construction" trap ADR-149 item 2 names, and the subject of W0. (c) *Coverage*: it would not ship what the issue asks for — `[sources.system_journald]` filters `PRIORITY ∈ {0,1,2}` while cloud-init output is PRIORITY 6, and there is **no `type = "file"` source anywhere** in `vector.toml`. Bonus: no Vector means no `host_metrics`, so git-data structurally cannot reopen the 3 GB/mo quota breach of 2026-06-10. |
| **A2 — Add a `[sources.file]` for `/var/log/cloud-init-output.log`** | **Rejected for v1.** Net-new with no in-repo precedent, and that file is precisely where secrets leak — it would need the most careful scrubbing on the rawest input. The inngest pattern (`tail -n 20 <captured log>` through the redactor into a structured field) gets the same diagnostic value with a bounded, reviewable payload. |
| **A3 — Fold the heartbeat into the birth route and arm it there** (the first draft's design) | **Rejected — see D-HB.** It would wedge every merge to `main` via the per-merge `arm_one`; it would prove reachability while being sold as boot correctness; and it would consume a Better Stack object at a possible 10/10 cap. |
| **A4 — Downsize to `cpx12`** (−$103.68/yr) | **Rejected.** One vCPU serialises maintenance against `git-receive-pack` even after the tuning, and the correction path is a destructive replace. |
| **A5 — Upsize to `ccx13`** (+$304.56/yr, consumes 2/8 dedicated vCPUs) | **Rejected.** Over-provisions against no measurement. |
| **A6 — Add a swapfile as an OOM backstop** | **Rejected.** An unencrypted root-disk swapfile can hold plaintext git object data paged out from under the LUKS posture. Encrypted swap adds a second crypt device to a host already barred from the reboot primitive. Bound memory instead. |
| **A7 — Reuse `disk-monitor.sh`** | **Rejected.** It watches `/` only, alerts via Resend (requiring `RESEND_API_KEY` in `prd_git_data`, widening a deliberately-minimal blast radius, or baking it into metadata-retrievable `user_data`), and is installed by an SSH `remote-exec` provisioner git-data does not have by design. |
| **A8 — Add a maintenance verb to `git-data-transport-wrapper.sh`** | **Rejected.** The two-verb allowlist is the authorisation boundary for a host holding every user's source code; widening it to enable a scheduled job is the wrong trade. Maintenance runs host-local as root. |
| **A9 — Fold #6975 (per-host heartbeat suffixing) in** | **Rejected.** Out of scope once W2 is deferred; and it would change the resource address to `…["web-1"]`, which the per-merge `arm_one`'s exact-`.address` match would silently no-op on. Acknowledged with a staleness note. |
| **A10 — Assign ext4 project quotas per workspace now** | **Deferred, two tracking issues.** It needs an app-side workspace→project-id map and a provisioning hook **and** a T&C/AUP storage-limit clause that does not exist (CLO §E) — a quota-triggered prune of *reachable* user content has no contractual basis today. The **irreversible** half (`mkfs -O quota,project` + `prjquota`) ships now, because that is the part that cannot be added later without a replace *and* a data migration. |
| **A11 — Close ADR-149 Residual 3** (empty-store Art. 17 silent success) here | **Deferred with a tracking issue bound to the `GIT_DATA_STORE_ENABLED` cutover**, not to a date and not to the birth — per CLO, it is substantively accurate until the store holds data. W1's boot-completion emit gives it the marker it needs, so the issue names a design rather than an open question. |
| **A13 — Skip the rehearsal and rely on mutation arms alone** | **Rejected** (advisor consult). Mutation arms prove the code can go red when neutered; they never prove an event arrives when it is intact — and W0's token-scope mismatch is exactly the defect class that passes every static check and then dies on first boot. The host has never existed, so the rehearsal is free exactly once, and this is that moment. |
| **A14 — Perform the real birth in this PR** so the hardening is proven end-to-end | **Rejected.** It is a production write on the host that will hold every user's source code, it needs independent operator authorisation (`hr-menu-option-ack-not-prod-write-auth`), and it forecloses the pre-birth window for anything review then surfaces. W12's throwaway-host rung gets the same evidence at a fraction of the commitment, and the follow-through probe (AC20) covers the real birth when it happens. |
| **A12 — Split into 4 PRs** (CTO's recommendation: atomic core `W0+W1+W3+W8`; then `W4+W7`; then `W6`; then `W5`) | **Not adopted — but the verdict is rewritten in v2 (R26), because v1's reason was wrong.** v1 argued a split *forfeits the interlock*: the sentinel releases the route on merge, so anything in a later PR is a hardening the route no longer waits for. **That does not hold.** Sequencing the emitter PR **last** preserves the mechanical hold across a split with no gate change at all — the sentinel is then the final thing to land. Independently, the latch is a one-bit gate only by construction: adding a second sentinel (the boot-completion marker) and a third (`doppler_secret.git_data_ssh_host` in `*.tf`) is ~5 lines of bash. So atomicity is a **choice**, not a constraint. It is chosen for review coherence, the shared forcing function, and CPO's endorsement — not because a split is unsafe. **If `/work` finds the PR unmanageable this is the split boundary**, sequenced emitter-last. The multi-sentinel gate hardening is filed as a follow-up on its own merits: it strengthens the latch for every future PR, and it discharges this plan's highest-rated residual more strongly than a PR-body checklist ever will. |

## Files to Create

Trimmed by R11 and R13 — five files fewer than v1.

- `apps/web-platform/infra/git-data-gc.service`, `apps/web-platform/infra/git-data-gc.timer` — the
  **one** timer that survives. It is also the one that genuinely needs systemd resource control
  (`MemoryMax=` / `CPUQuota=` / `IOSchedulingClass=idle`), which a cron line cannot express.
- `apps/web-platform/infra/git-data-emit.test.sh` — **one** suite for the **one** emitter (R13),
  registered in `infra-validation.yml`. Covers both redactor arms (AC23), the delivery assertion
  (AC34), the exit-0 trap guard (T17) and the mutation battery (AC25).
- `scripts/followthroughs/git-data-birth-emitter-6982.sh`

**Cut in v2:** `git-data-store-monitor.{sh,service,timer,test.sh}` (R11 — it polled the
empty-by-construction LUKS volume while the filesystem that actually fills went unwatched);
`git-data-phone-home` + `git-data-redact` as separate scripts and `git-data-boot-emit.test.sh` +
`git-data-redact.test.sh` as separate suites (R13 — consolidating makes the redaction guarantee
structural instead of conventional).

## Files to Edit

- `apps/web-platform/infra/cloud-init-git-data.yml` (W1, W3, W5, W6)
- `apps/web-platform/infra/git-data.tf` (W1 vars, W8 secret)
- `apps/web-platform/infra/network.tf` (hoist `local.git_data_private_ip`)
- `apps/web-platform/infra/variables.tf` (W7 description)
- `apps/web-platform/infra/git-data-bootstrap.sh` (W4 config + W1 boot-completion assertions)
- `apps/web-platform/server/git-data-replication.ts` (W6 limiter)
- `.github/workflows/apply-web-platform-infra.yml` — birth `-target` set **18 → 20** (the SSH-host
  secret **and** the Better Stack ingest secret, per D1), the "eighteen -targets" prose, **and** the
  new post-apply `if: always()` boot-signal poll (R20)
- `.github/workflows/infra-validation.yml` (register the one new suite)
- `.github/workflows/scheduled-followthrough-sweeper.yml` — verify the three real
  `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` secrets are passed (R4); add only if missing.
  **Do not add `BETTERSTACK_LOGS_QUERY_TOKEN` — it does not exist**, and `BETTERSTACK_LOGS_TOKEN`
  is ingest-only (write)
- **`apps/web-platform/infra/sentry/issue-alerts.tf`** — **R1, the largest v1 omission.** Without a
  `git_data_boot_fatal` rule every Sentry emit this plan adds is write-only, exactly as the file's
  own `web_terminal_boot_fatal` comment records for the web host's runcmd stages. Auto-applied on
  push to `main` by `apply-sentry-infra.yml`, so it is a cheap per-merge path.
- `tests/scripts/lib/git-data-host-birth-gate.sh` — **two** sites (R6): `_GIT_DATA_BIRTH_ALLOW`'s
  unparameterised `def allow: [ … ]`, **and** the separate hardcoded presence loop, plus the two
  prose counts ("eighteen-address", "13 presence members")
- `tests/scripts/test-git-data-host-birth-gate.sh` — the `rest_thirteen_except` /
  `rest_thirteen_with` fixture helpers (R6; their header declares one-entry-per-address an invariant)
- `tests/scripts/test-git-data-birth-readiness-gate.sh` (GREEN arm)
- `plugins/soleur/test/terraform-target-parity.test.ts` (`GIT_DATA_BIRTH_TARGET_BASES`, `OPERATOR_APPLIED_EXCLUSIONS`)
- `apps/web-platform/infra/git-data-luks.test.sh` (append cloud-init + mutation assertions)
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`
- `knowledge-base/engineering/architecture/decisions/ADR-149-git-data-host-birth-route-and-readiness-interlock.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/operations/runbooks/git-data-birth.md`
- `knowledge-base/legal/article-30-register.md` (W10)
- `knowledge-base/operations/expenses.md` (W11)

## Research Insights

- **The authoritative scope contract is ADR-149's release checklist, not the issue body**, and its
  own text warns *"#6982 could have satisfied every listed item and still shipped this."* Two further
  items (the Art. 30 present-tense claim; the `doppler run` scope mismatch) were surfaced by the
  domain panel and are in neither.
- **Skill-description budget check:** not applicable — no `plugins/soleur/skills/*/SKILL.md`
  `description:` edit is candidate or finalised in *Files to Edit*.
- **Community/functional discovery:** all three registries queried across nine searches; four
  queries (heartbeat alerting, log shipping, bash `trap` error handling, git gc maintenance) returned
  **zero** results. Nearest candidates are greenfield Hetzner provisioning boilerplate whose
  cloud-init is *less* hardened than what already exists here. **No meaningful overlap — build
  in-repo.** No stack gap: Terraform/bash/cloud-init/systemd are covered by `terraform-architect`,
  `platform-strategist` and `observability-coverage-reviewer`.
- **Infra suites do not run under `scripts/test-all.sh`.** They are registered as named
  `run: bash …` steps in `.github/workflows/infra-validation.yml` (job `deploy-script-tests`,
  `timeout-minutes: 12`, at-budget on main). A green `test-all` says nothing about an infra change.
  Local mirror: `bash apps/web-platform/infra/run-registered-suites.sh`.
- **`-target`-scoped applies make a new resource a no-op.** A bare new `*.tf` resource is never
  created and is invisible to `terraform validate`, `tsc`, and a green PR branch.
- **`-target` prunes unreferenced data sources.** `data.hcloud_server_type.git_data` stays alive only
  because `hcloud_server.git_data`'s `lifecycle.precondition` references it. Do not "simplify" that
  precondition away.
- **Verified constants** (live-probed 2026-07-27; do not re-derive from memory): `cpx22` = 2c/4 GB/
  80 GB x86, €19.49/mo net ≈ $21.05; `cpx12` = 1c/2 GB, €11.49 ≈ $12.41; `ccx13` = 2 dedicated c/
  8 GB, €42.99 ≈ $46.43; **`cx23`, `cx33` and `cax11` are out of stock in all three EU DCs**;
  **`cx22` does not exist in the catalogue**. Hetzner volumes €0.0572/GB/mo → 10 GB ≈ $0.62.
  Better Stack free tier: 3 GB/mo logs, 3-day retention, 30 GB metrics; heartbeats are **not**
  tier-gated (only `policy_id` is); live objects = 7 heartbeats + 3 monitors. Sentry PAYG headroom
  ≈ $7.78 against a $50 cap, cliff `onDemandPeriodEnd` 2026-08-16.
- **Next free ADR ordinal on `origin/main` is 150** — provisional; this plan claims none.
