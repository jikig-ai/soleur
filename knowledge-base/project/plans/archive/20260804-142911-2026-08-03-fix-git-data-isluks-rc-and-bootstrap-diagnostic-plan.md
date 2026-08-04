---
title: "fix(git-data): isLuks rc-branching + the bootstrap stage's diagnostic path"
date: 2026-08-03
type: fix
lane: cross-domain
branch: feat-one-shot-7216-7227-isluks-rc-and-bootstrap-diag
closes: ["#7216", "#7227"]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
plan_revision: v2 (post 6-agent plan-review)
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed. This plan introduces NO infrastructure. The `systemctl` tokens it contains
  are QUOTATIONS of runcmd lines already shipping inside cloud-init-git-data.yml — already
  IaC-routed through cloud-init. No operator SSH, no dashboard step, no manual provisioning
  appears in any phase. See ## Infrastructure (IaC).
-->

# fix(git-data): `isLuks` rc-branching + the bootstrap stage's diagnostic path

Closes #7216. Closes #7227.

> **v2.** Revised after a 6-agent plan-review panel (dhh, kieran, code-simplicity,
> architecture-strategist, spec-flow-analyzer, cto). The panel found **two P0 defects in v1's own
> fix** — one of which reconstructed #7216's catastrophe inside the patch meant to close it — plus
> a guard-widening that would have shipped *weaker* than the guard on `main`. All three are
> corrected below and each is now measured rather than argued. Non-applied findings (one
> User-Challenge, four Taste) are in
> `knowledge-base/project/specs/feat-one-shot-7216-7227-isluks-rc-and-bootstrap-diag/decision-challenges.md`.
>
> Spec note: no `spec.md` exists for this branch, so `lane:` was defaulted to `cross-domain`
> (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-08-03 · **Gates run:** 4.4, 4.45, 4.55, 4.6, 4.7, 4.8, 4.9, 4.10

### Halt gates

| Gate | Result |
| --- | --- |
| 4.6 User-Brand Impact | **PASS** — section present, threshold `single-user incident` |
| 4.7 Observability | **PASS** — all 5 fields present, non-placeholder, no `ssh ` in `discoverability_test.command` |
| 4.10 Encryption Posture | **PASS** — all 6 `at_rest` fields present; `does_not_defend` non-empty; `exception` carries `tracking_issue` + `expires_on` |
| 4.9 UI wireframe | **N/A** — zero UI-surface files |
| 4.8 PAT-shaped variable | **PASS** — no matches |
| **4.55 Downtime & Cutover** | **FIRED** — `user_data` edit is `ForceNew` on `hcloud_server.git_data`. New `## Downtime & Cutover` section added; telemetry emitted. |

### Verify-the-negative pass (10 claims probed against source)

**All 10 `confirms`, zero `contradicts`.** The load-bearing ones:

- `hcloud_server.git_data` has `ignore_changes = [ssh_keys]` only — the `user_data` ForceNew is
  deliberate and documented in-file.
- No `set -x` in either file; `random_password.git_data_luks` is `length = 40, special = false`;
  all **3 key-consuming** `cryptsetup` calls (of 5 total) use `--key-file -` on stdin. Together
  these are the evidence base for Decision **clause B**, and Phase 3.5 mechanizes them.
- `log()` writes **stdout** — confirming Phase 2.10 is required, not optional.
- Better Stack is gated on `BETTERSTACK_LOGS_TOKEN`, absent from the parent shell; the capture
  script routes every query through `betterstack-query.sh` and its own header disclaims Sentry.
  **This is the #7116 chain, confirmed end-to-end.**
- Exactly **9** `replace(file(...), git_data_rationale_strip, "")` calls vs an unstripped
  `templatefile()` on the template itself — the byte-budget premise holds.

### Citation verification (live)

`#7116` OPEN · `#6897` OPEN · `#7217` OPEN · `#7204` OPEN · `#7197` MERGED · `#6982` CLOSED ·
`#7025` OPEN · `#6588` OPEN. Both cited AGENTS rule IDs active. `AP-008` present in the
principles register. All 6 knowledge-base citations + the runbook path resolve on disk.

### Key improvements from this pass

1. **`## Downtime & Cutover` added**, and it corrected a framing error: the host has **never been
   born**, so the first apply is a *birth*, not a replacement — and the already-LUKS danger state
   is reached by a **retried birth**, a later `user_data` edit, or an unrelated replace. That
   makes #7216 a near-path risk rather than a hypothetical, and pins why the fix must precede the
   dispatch.
2. Decision clause B moved from assertion to **verified evidence** (all four sub-claims probed).
3. Confirmed Phase 2.10 (`log()` → stderr) is load-bearing, not defensive.

## Overview

Two defects in `apps/web-platform/infra/cloud-init-git-data.yml` and the artifacts bound to it.

**#7216** — `if ! cryptsetup isLuks "$DEV"` treats *every* non-zero exit as "not yet LUKS",
including 126 (not executable) and 127 (not found), and falls through to `luksFormat`. On a
device that *is* already LUKS but whose probe could not execute, that destroys the header and
every key slot.

**#7227** — four items on the bootstrap/parent-shell diagnostic path: an unredacted detail source
in the parent runcmd shell, no seeded scoped detail file for the bootstrap stage, an `R3(3b)`
guard scoped to one call site out of four, and an evidence-capture script that will happily be
aimed at production.

**Why one PR.** Files 1-3 (the template and its two static guards) are genuinely hash-coupled:
`git_data_rung2_user_data_sha256` (`tests/scripts/lib/git-data-birth-readiness-gate.sh`) hashes
the template, `modules/git-data-userdata/*.tf`, and the nine `file()`-bound payloads, so any edit
to them re-hashes `RUNG2_TEMPLATE_SHA256` and a rehearsal costs a real paid `cpx22`. Files 4-7
(the capture script, its test, the rehearsal guard, the CI path filter) are **not** in that hash
set and carry no dispatch coupling — they ride along by **operator direction**, not by necessity.
That distinction was wrong in v1 and is recorded as **UC-1** in `decision-challenges.md`, where
the operator can take the split if they prefer. Spend cap: **two paid dispatches**; **no dispatch
happens in this run.**

---

## The three corrections that changed what ships

### C1 (P0) — the issue's proposed capture form aborts under `set -e`

The `luks_open` stage runs inside `doppler run -- bash -s <<'LUKSEOF'` under `set -euo pipefail`.
Measured 2026-08-03:

| form | rc=1 (genuinely not LUKS) | rc=127 | rc=126 |
| --- | --- | --- | --- |
| `cmd; _rc=$?` (the issue's shape) | **aborts before the assignment** | n/a | n/a |
| `_rc=0; cmd \|\| _rc=$?` | reached, `_rc=1` | reached, `_rc=127` | reached, `_rc=126` |
| `if ! cmd` (the shipped shape) | format branch | **format branch** | **format branch** |

Row 1 means the issue's shape converts the bug into a *different* bug: a blank volume at birth
returns rc=1, the naked capture aborts, and the store can never be created at all.

The `sshd_config` precedent uses the naked form legally **only because it sits above the `set -e`
armed at the end of that same runcmd entry** (~30 lines below it, not "two lines later" as v1
said). Mirror the *discipline*, not the two lines.

### C2 (P0, found by kieran) — `2>>` on the probe line can FORGE rc=1 without running the probe

This is the one that mattered. **Measured:**

```
$ ( set -euo pipefail; _rc=0; /bin/true 2>>/proc/sys/nonexistent/x.log || _rc=$?; echo "rc=$_rc" )
rc=1
```

A failed redirection on a simple command means **the command never runs** and the shell reports
**rc 1**. v1's shape put `2>>"$GIT_DATA_LUKS_DETAIL"` directly on the probe. On an unwritable or
full `/run` — a state this plan *itself enumerates* as a live failure mode — `_isluks_rc` would be
1 with the probe never executed, and the `1)` arm would `luksFormat` a store that may already be
LUKS. **v1 reconstructed #7216 inside its own fix**, and the seed is `|| true`'d so nothing aborts
before reaching it.

Fix: decouple measurement from capture. Measured against the pinned image's cryptsetup 2.7.0:

```
missing device -> rc=4    blank device -> rc=1    not-on-PATH -> rc=127
```

all three correct through a command substitution, with the append a separate tolerated statement.

### C3 (P0, found independently by 3 reviewers) — the widened `R3(3b)` would ship weaker than `main`

`R3(3b)`'s guard search is **file-global and keyed on the variable's name**:

```python
gpat = re.compile(r'\[\s+-[rs]\s+"?' + re.escape(name))
gm = gpat.search(joined)            # global — first match anywhere
guarded = "GUARDED" if (gm and gm.start() < epos) else "UNGUARDED"
```

Safe today only because the input is `luks-stage.code.sh`: one stage, one site, one `_detail`.
v1 prescribed `on_err` and `bootstrap_err` as "identical bodies" — all three sites named `_detail`
— so `on_err`'s guard (first in the file) would satisfy `gm.start() < epos` for every later site.
**Delete `luks_err`'s guard and the widened arm still reports `VAR:GUARDED`.** `luks_err` is
genuinely checked today; after v1's widening it would not be.

Fix: distinct locals per handler, a region-scoped guard search, an `UNGUARDED` negative control,
and a named-message **set** rather than a bare count.

Two related tokenization defects, both measured:

- `toks[4]` is wrong for any `||`-chained emit. On the `gc_timer` line
  `shlex.split(..., posix=False)[4] == '||'` — v1's AC6 would have reported "0 sites pass the
  literal" while the literal was still passed, on the exact call site #7227 names. Index
  **relative to the emitter token**: measured, that yields `/var/log/cloud-init-output.log`.
- The floor `36 -> 41` was arithmetically unreachable: v1 counted a python `assert` inside the
  extraction heredoc as an assertion, but nothing there increments `passes`/`fails`. Floors are
  re-derived from **measured** totals after the arms exist.

---

## Measured baselines (2026-08-03, this worktree)

```
git-data-luks:                 113 passed, 0 failed   (floor 113)
git-data-runcmd-rehearsal:      36 assertions          (floor 36)
git-data-rung2-evidence-capture: 30 passed, 0 failed   (floor 30)
git-data-rung2-rehearsal:       70 passed, 0 failed   (floor 70)
git-data user_data: stored=25968 B / cap=32768 B (headroom 6800 B, raw 58060 B)
encryption-posture: 16 stores, 3 connections, 0 unledgered, 0 failing checks -> PASS
terraform v1.10.5 present; docker present
```

All four suites sit **exactly** on their floors — so every floor must move with its arms.

**Comment-byte measurement (dhh):** v1's prescribed template prose cost **+2,012 stored B — 30%
of the entire headroom** — against **+400 stored B** for the executable lines it explains. v2 caps
each template comment block at ~6 lines. The durable statement is the mutation arm, not the
paragraph; `B18 (naked rc capture)` cannot go stale and costs zero template bytes.

## Research Reconciliation — Issue Text vs. Codebase

| Issue claim | Reality | Plan response |
| --- | --- | --- |
| `if ! cryptsetup isLuks` at "line 548" | Correct | Anchor by content (`cq-cite-content-anchor-not-line-number`) |
| Proposed `cmd; _rc=$?` capture | **Aborts under `set -euo pipefail`** (C1) | `_rc=0; cmd \|\| _rc=$?` |
| — (not in the issue) | **`2>>` on the probe forges rc=1** (C2) | Command substitution; append separately |
| "`sshd_config` … does exactly this … Mirror it" | Naked form (legal only above `set -e`), and the **opposite** disposition | Mirror the discipline; document both divergences |
| Lines 307, 602, 628 bare `/var/log/cloud-init-output.log` | Correct: `on_err`, `bootstrap_err`, `gc_timer` | All three in scope |
| "`_devalue()` degrades to `cat`" | Confirmed | Option 3 + a two-clause invariant (below) |
| "Widen `R3(3b)` … not just the luks one" | **Four** fatal sites, not two; and the widening as specified ships weaker than `main` (C3) | Distinct locals + region-scoped search + set-not-count |
| "`--host-name` validates charset only" | Correct; the only production call site passes `${REHEARSAL_PREFIX}${GITHUB_RUN_ID}` | Prefix constraint, zero workflow change |
| Implicit: "the template has room" | 6,800 B headroom; template comments **not** stripped at render | ~6-line comment blocks; AC-gated |
| Implicit: "bootstrap.sh has the same isLuks bug" | Its `if cryptsetup isLuks "$dev"` is a fail-**closed** selector — an unrunnable probe leaves `luks_dev=""` → `FATAL: no LUKS-formatted volume found`, never a format | Out of scope **by construction**; stated so a reviewer grepping the pattern finds the answer |
| Implicit: "the rehearsal job fails on any fatal" | **False for every parent-shell stage** — they reach Sentry only, and the capture script polls Better Stack exclusively. That is #7116, OPEN | Observability corrected + #7116 cited; the fix is T-1 in `decision-challenges.md` |

## User-Brand Impact

- **If this lands broken, the user experiences:** every workspace's bare repo on
  `/mnt/git-data-luks` destroyed by a `luksFormat` that overwrote the LUKS header and all key
  slots. No recovery — the old passphrase opens nothing.
  **Corrected trigger (v1 said "any reboot"):** `runcmd` is once-per-instance and does not re-run
  on reboot. The real trigger is a **host replacement** — and `hcloud_server.git_data` carries no
  `ignore_changes = [user_data]`, so a template edit is `ForceNew`. The volume persists across the
  replace, so the replacement instance runs `isLuks` against an **already-LUKS volume**. That is
  precisely the #7216 scenario, and **this PR's own eventual apply creates it.**
- **If this leaks, the user's source code and credentials are exposed via:** the `detail` field of
  a `level:fatal` event from the parent runcmd shell, today an unredacted
  `tail -n 20 /var/log/cloud-init-output.log`. The rung-2 capture projects `detail` into a
  **public** Actions log on a **public** repo, and `_devalue` is inert outside `doppler run`.
- **Brand-survival threshold:** `single-user incident`

## Open Code-Review Overlap

**None.** No open `code-review` issue names any path in *Files to Edit*.

## Decision — #7227 item 1: option 3, with an honest two-clause bound

**Chosen: option 3 — a seeded, per-stage-truncated scoped detail file for the parent runcmd
shell**, replacing `/var/log/cloud-init-output.log` as the detail source for every parent emit.

- **Option 1** (move the emit inside `doppler run`) covers one of three offending sites; `on_err`
  fires for `gitdata_runcmd_early`, `sshd_config`, `volume_mount` and `gitdata_doppler_dl`, which
  have no doppler child to move into.
- **Option 2** (pass the key into the emitter's env) widens `GIT_DATA_LUKS_KEY` into the parent
  shell and `/proc/<pid>/environ`. Directly against **AP-008** (Doppler for all secrets, NFR-014)
  and the template's own "delivered ONLY as the Doppler-injected env" invariant.
- **Option 3** bounds the detail source by construction.

**The invariant, restated truthfully (v1's version was falsified by its own Phase 2.5).** It has
**two clauses of different strength**, and saying so is the point:

- **Clause A — structural.** Parent-shell commands have `GIT_DATA_LUKS_KEY` provably absent from
  their environment. They cannot leak what they do not hold. This covers every stage except
  `bootstrap` and `luks_open`.
- **Clause B — behavioural, and weaker.** The two `doppler run` children **do** hold the key, and
  Phase 2.5 routes their stderr into the parent file. The bound is therefore that no command in
  that subtree writes key-derived bytes to any stream: the passphrase is `special = false`,
  `length = 40` alphanumeric (`git-data-luks.tf`, verified) so it contains no regex metacharacter
  and cannot malform `_devalue`'s constructed `sed`; it reaches only `cryptsetup` via stdin
  `--key-file -`, which never echoes it; `git-data-bootstrap.sh`'s `log()` never interpolates it;
  and there is no `set -x` anywhere in either file (verified).

Clause B is a behavioural bound, so **it is mechanized** by a new guard (Phase 3.5) asserting
`special = false`, the absence of `set -x`, and `--key-file -` on every key-consuming
`cryptsetup` call — otherwise a future `special = true` rotation silently converts this from safe
to a live redactor bypass. And because clause B is the weaker half, the **bootstrap stage's
primary cause-carrier stays the child's own `log() FATAL` emit**, which fires *inside* `doppler
run` with `_devalue` armed; the parent's emit is the backstop for bash-level failures the child's
`log()` never sees.

**Consequence:** the parent handler drops `tail -n 20 /var/log/cloud-init-output.log`. `luks_err`
keeps it (it runs under `doppler run`). The cost — bash's own parent-shell errors reach only the
cloud-init log — is documented and is why the self-describing literal must remain **reachable**
(see C4 below).

### C4 — the dmesg tail would impersonate a cause (architecture P1-1)

`[ -s "$_detail" ]` passes whenever dmesg wrote 20 lines, so v1's terminal literal was
**unreachable** and the shipped `detail` would be the tail of unrelated kernel chatter. That is
worse than #7204: not a verdict with no cause, but a verdict with a **plausible wrong** cause.
Fix: emit the literal as the **last** line inside `.final` when the scoped file is empty (last,
because `_clean` ends in `tail -c 180`).

### C5 — the scoped file must be truncated per stage (spec-flow P1-4)

The file is append-only across the whole boot, and `mount … || true` writes an error while the
boot **continues**. A later stage's fatal would then ship that tolerated earlier error as its
cause — active misattribution. Fix: `: > "$GIT_DATA_RUNCMD_DETAIL"` at each `STAGE=` boundary.
This also dissolves the "which commands deserve a `2>>`" argument: a stage-scoped file cannot
inherit another stage's noise.

## Architecture Decision (ADR/C4)

**No new ADR. One amendment.**

- No ownership/tenancy boundary moves; no new substrate, queue, auth boundary or external edge;
  no resolver/dispatch/trust boundary change.
- **ADR-147 amendment (in scope, this PR).** ADR-147's decision is "boot-stage diagnostics live in
  baked host-scripts, **not** `user_data`", and its 2026-07-27 addendum records git-data as a
  forced exception ("no bake path"). This PR **extends** that exception to *diagnostic capture
  plumbing* — a scoped detail file, per-stage truncation, per-command stderr routing — all inside
  `user_data`. Per `wg-architecture-decision-is-a-plan-deliverable` the amendment ships here, not
  as a follow-up: add an addendum recording the widened exception, the measured byte cost, and the
  remaining headroom, so the next diagnostics PR treats the budget as a governed axis.
- ADR-149 (hash-of-hashes), ADR-152 (strip covers only the nine payloads), ADR-163 (birth `mkfs`
  features), ADR-140 (encryption posture) — all verified untouched.
- **C4 completeness check** (all three of `model.c4`, `views.c4`, `spec.c4` read in full, not
  grepped for the feature noun): **no new external human actor** (no new correspondent, reviewer
  or recipient); **no new external system or vendor** (Sentry and Better Stack are already the
  emitter's two modelled sinks; Doppler, Hetzner, GitHub Actions already present); **no new
  container or data store** (both git-data volumes and their mappers already modelled); **no
  changed actor↔surface access relationship** (the operator's reach into the rehearsal route is
  narrowed *within* an existing edge, not re-pointed). Nothing to add; no element description is
  falsified.

## Encryption Posture

No store introduced, no mechanism changed. Emitted because `cloud-init.*\.ya?ml$` fires. Rows
restate `scripts/encryption-posture-ledger.json` unchanged; **no ledger edit is in scope** and
`lint-encryption-posture.py` must stay `PASS` at the baseline counts.

```yaml
at_rest:
  - store: hcloud_volume.git_data_luks
    mechanism: luks
    evidence: >
      apps/web-platform/infra/cloud-init-git-data.yml — the
      `cryptsetup luksFormat --batch-mode --type luks2 --key-file -` and
      `cryptsetup luksOpen --key-file - "$DEV" git-data` calls, and the
      `/dev/mapper/git-data /mnt/git-data-luks ext4` fstab line. Key:
      random_password.git_data_luks (length=40, special=false) + doppler_secret.git_data_luks_key
      (git-data-luks.tf). UNCHANGED by this plan — luksFormat keeps its flags, its stdin key
      delivery and its mapper operand; only the guard deciding WHETHER to reach it changes.
    defends_against: "a seized/RMA'd or snapshot-imaged git-data block volume: unreadable without the Doppler-held passphrase"
    does_not_defend: "a leaked credential, an app-layer read on the unlocked host, or exfiltration via a compromised git-data process — and, until #7216 lands, a HOST REPLACEMENT on which the isLuks probe cannot execute, which reformats the store rather than reading it"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable:no per-volume host posture probe on the git-data host yet; tracked #6897"
  - store: hcloud_volume.git_data
    mechanism: plaintext-exception
    evidence: 'apps/web-platform/infra/git-data.tf — resource "hcloud_volume" "git_data" (format = "ext4", no LUKS apparatus)'
    defends_against: "nothing at the volume layer; the pre-cutover rollback backstop pending the DL-2 wipe"
    does_not_defend: "a seized/snapshot disk exposes any git data still resident on this volume"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable:host attachment state not pulled in the code-sourced audit; tracked #6897"
in_transit:
  - connection: "git-data host runcmd shell -> sentry.io ingest"
    enforced_at: 'apps/web-platform/infra/cloud-init-git-data.yml — the `curl … -X POST "https://${SHOST}/api/${PROJ}/store/"` call inside /usr/local/bin/git-data-emit'
    tls: "https, curl default minimum (TLS 1.2)"
    cert_verification: "on"
    does_not_defend: "the payload's CONTENT once in Sentry — which is why the detail SOURCE, not the transport, is what this plan changes"
    disclosed_as: not-publicly-claimed
  - connection: "git-data host doppler-run children -> Better Stack ingest"
    enforced_at: 'apps/web-platform/infra/cloud-init-git-data.yml — the `curl … -X POST ${betterstack_ingest_url}` call inside /usr/local/bin/git-data-emit'
    tls: "https, curl default minimum (TLS 1.2)"
    cert_verification: "on"
    does_not_defend: "the payload's content once in Better Stack; the rung-2 capture re-projects `detail` into a PUBLIC Actions log — the exposure #7227 item 1 closes"
    disclosed_as: not-publicly-claimed
exception:
  justification: "hcloud_volume.git_data stays plaintext as the rollback backstop for the LUKS cutover, pending the DL-2 destructive wipe. Pre-existing; not introduced or widened here."
  tracking_issue: "#6897"
  reevaluate_when: "the git_data_luks cutover is confirmed and the DL-2 wipe runs"
  expires_on: "2026-10-22"
```

## Observability

```yaml
liveness_signal:
  what: "git-data-emit stage events. Sentry is UNCONDITIONAL (baked DSN). Better Stack fires ONLY under `doppler run` (the BETTERSTACK_LOGS_TOKEN gate) — so luks_open and the bootstrap CHILD reach both sinks; every parent-shell stage reaches SENTRY ONLY."
  cadence: "per-boot, per-stage; boot_complete once per successful boot from git-data-bootstrap.sh step 8"
  alert_target: "Sentry project web-platform, org jikigai-eu. CORRECTED FROM v1: the rung-2 rehearsal job does NOT fail on parent-shell fatals — git-data-rung2-evidence-capture.sh polls Better Stack exclusively and issues zero Sentry queries, so an on_err/sshd_config/volume_mount/doppler_dl/gc_timer fatal reports TRANSIENT, not FAIL. That is issue #7116 (OPEN), named in git-data-rung2-rehearsal.yml as a documented dispatch-burner. Closing it is T-1 in decision-challenges.md."
  configured_in: "apps/web-platform/infra/cloud-init-git-data.yml — the /usr/local/bin/git-data-emit write_files payload; modules/git-data-userdata/main.tf binds it."

error_reporting:
  destination: "Sentry web-platform via the terraform-interpolated sentry_dsn baked into /usr/local/bin/git-data-emit; Better Stack via BETTERSTACK_LOGS_TOKEN (doppler-run children only)."
  fail_loud: "a level:fatal event whose `stage` tag names the failing stage and whose `detail` carries the failing command's own stderr — after this plan, a dmesg tail plus the per-stage-truncated /run/git-data-runcmd.log, never a path literal and never the shared cloud-init log."

failure_modes:
  - mode: "cryptsetup isLuks cannot execute (126/127) or the device is absent/denied (4)"
    detection: "NEW — level:fatal, stage=luks_open, detail names `isLuks could not run (rc=<n>)`. Today this mode is SILENT: the stage proceeds to luksFormat and the boot looks healthy. Reaches Better Stack too (under doppler), so the capture script DOES see it."
    alert_route: "Sentry issue; the rung-2 job fails on this one because luks_open reaches Better Stack"
  - mode: "the probe's stderr append fails on an unwritable /run"
    detection: "NEW (C2) — the probe now runs regardless and its rc is real; a failed append is tolerated and the detail degrades to the self-describing literal. Previously this FORGED rc=1 and reformatted the store."
    alert_route: "Sentry issue"
  - mode: "git-data-bootstrap.sh fails an invariant (mount, LUKS mapper identity, git config read-back)"
    detection: "the child's own `log() FATAL` emit fires INSIDE doppler run with _devalue armed and ships the FATAL sentence as detail — the primary cause-carrier. The parent's on_err is the backstop for bash-level failures log() never sees."
    alert_route: "Sentry + Better Stack; absence of boot_complete is the second signal (ADR-149's poll)"
  - mode: "doppler run cannot resolve its config/token (the #6982 W0 boot-breaker)"
    detection: "level:fatal whose detail carries the CLI's own pre-exec stderr, captured because the doppler run invocations redirect 2>> into the per-stage-truncated file"
    alert_route: "Sentry issue"
  - mode: "the scoped detail file is unwritable (/run read-only or full)"
    detection: "CORRECTED FROM v1 — with 2>> on parent commands under armed `set -e`, a read-only /run makes the redirection fail BEFORE the command runs, so this is a NEW BOOT ABORT, not a degraded diagnostic. Mitigated by the `[ -w ]` fallback to /dev/null in Phase 2.2 so the boot proceeds and the literal is what ships."
    alert_route: "Sentry issue; the self-describing literal is the tell"
  - mode: "the evidence-capture script is aimed at the production host"
    detection: "NEW — refuses at argument-parse time with exit 64 naming the required soleur-git-data-rehearsal- prefix; covered by three new arms"
    alert_route: "the workflow step fails; nothing queried, written, or projected into the Actions log"

logs:
  where: "Sentry (all stages) and Better Stack (doppler-run stages only). On-host: /var/log/cloud-init-output.log and /run/git-data-runcmd.log — both unreachable without SSH, which is why the off-host emit is the contract."
  retention: "Sentry per project retention; Better Stack per source retention; the rehearsal's capture.redacted.log artifact 7 days. /run/* is tmpfs, per-boot by design."

discoverability_test:
  command: "bash apps/web-platform/infra/git-data-luks.test.sh && bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh && bash tests/scripts/test-git-data-rung2-evidence-capture.sh"
  expected_output: "three suites green, each printing `<n> passed, 0 failed` at or above its re-derived floor. The runcmd-rehearsal suite drives the REAL emitter against a local capture endpoint in a ubuntu:24.04 container, so a green run measures the shipped emitter rather than grepping source."
```

## Files to Edit

**Hash-coupled (these three force the paid dispatch):**

1. `apps/web-platform/infra/cloud-init-git-data.yml`
2. `apps/web-platform/infra/git-data-luks.test.sh` — `B18` family; floor re-derived
3. `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` — widened `R3(3b)` + ordering arm;
   floor re-derived
4. `apps/web-platform/infra/git-data-bootstrap.sh` — **newly in scope** (v1 wrongly excluded it):
   `log()` must write to **stderr**, and its comments are stripped at render so the change costs
   **zero** stored bytes.
5. `knowledge-base/engineering/architecture/decisions/ADR-147-…md` — the addendum.

**Hash-neutral (operator-directed ride-along; see UC-1):**

6. `scripts/followthroughs/git-data-rung2-evidence-capture.sh`
7. `tests/scripts/test-git-data-rung2-evidence-capture.sh` — floor re-derived
8. `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` — fold into arm 10; floor re-derived
9. `.github/workflows/infra-validation.yml` — add the `scripts/followthroughs/…` path

### Files explicitly NOT edited

- **`apps/web-platform/infra/git-data-rung2-boot-evidence.env`** — absent on `main`; only a real
  rehearsal may write it.
- **`/usr/local/bin/git-data-emit`** (the payload inside the template) — its redaction and
  truncation ordering is load-bearing; `R3(3a)` is the positive control proving the literal-path
  leak is still live, and editing the emitter would invalidate that control's rationale.
- **`scripts/encryption-posture-ledger.json`** — no store or mechanism changes.
- **`git-data-bootstrap.sh`'s `if cryptsetup isLuks "$dev"` selector** — same *pattern*, not the
  same *defect*: it is fail-**closed** (an unrunnable probe leaves `luks_dev=""` → a FATAL, never
  a format). Stated here because a reviewer will grep the pattern and find it.

## Implementation Phases

**Sequencing note (kieran):** the handler-variable renaming lands in Phase 2 **before** the
widened guard in Phase 3, or the Phase 1.2 RED passes for the wrong reason on three of four sites
and the failing direction is never observed.

**Shell note (spec-flow):** cloud-init `shellify()`s every `runcmd` entry into ONE `/bin/sh`
script — **dash, not bash**. Everything added to the parent shell must be POSIX (`case` is inside
the `bash -s` heredoc; `( umask )`, `[ -s ]`, `{ } > file` are all fine). Do not reach for
bashisms in the parent.

### Phase 0 — Preconditions

0.1 Confirm clean worktree on the feature branch.

0.2 Re-confirm the six baselines quoted above.

0.3 Confirm **docker** *and* **terraform** are present. Terraform is load-bearing:
`git-data-userdata-budget.sh` opens with `command -v terraform … || { echo "SKIP"; exit 0; }`, so
without it AC11 — the only mechanical gate on the new template prose — passes **vacuously**.
Measured present: `terraform v1.10.5`. **STOP if either is missing.**

0.4 Re-take the `isLuks` rc measurement against the pinned image and paste it into the PR body:

```sh
docker run --rm ubuntu:24.04 bash -c 'export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq cryptsetup-bin >/dev/null 2>&1
  cryptsetup --version
  t=$(mktemp); dd if=/dev/zero of="$t" bs=1M count=2 status=none
  cryptsetup isLuks "$t"; echo "rc_nonluks=$?"
  cryptsetup isLuks /nonexistent/xyzzy >/dev/null 2>&1; echo "rc_missing=$?"
  PATH=/nonexistent sh -c "cryptsetup isLuks \"$t\"" >/dev/null 2>&1; echo "rc_notfound=$?"'
```

Expected `2.7.0`, `rc_nonluks=1`, `rc_missing=4`, `rc_notfound=127`. **If `rc_nonluks` is not 1,
STOP.**

0.5 **`$DEV` readiness (cto F4 / architecture P2-2).** rc=4 becomes a hard abort, so an attach
race that used to "boot eventually" would now burn a paid dispatch. Record whether anything waits
on `$DEV` today (nothing does; the sibling plaintext mount carries an acknowledged `|| true` for
exactly this class). Disposition: **bounded wait, then abort** — Phase 2.1 adds ~60 bytes of
insurance.

### Phase 1 — RED

**Only the `assert_holds` arms are the Phase-1 RED signal.** The `assert_mutation` arms' `sed -E`
expressions cannot match text that does not exist yet, so pre-fix they report
`MUTATION DID NOT LAND` — an *instrument fault*, not a RED. Add them in Phase 3 and do not muddy
AC15's evidence with them.

1.1 `B18` hold → `property does not hold on the real file`.
1.2 Widened `R3(3b)` → record the verdict **set**, which is pre-measured and must match:
`{on_err: LITERAL, sshd_config: LITERAL, bootstrap_err: LITERAL, luks_err: VAR:GUARDED}`.
1.3 Capture-script prefix arm → production name **accepted** (the defect).
1.4 Arm-10 prefix pin → literal absent from the validation regex.

### Phase 2 — GREEN: `cloud-init-git-data.yml`

**2.1 — #7216.** Comment capped at ~6 lines; the mutation arms carry the durable statement.

```sh
    # (#7216) rc CAPTURE, NOT TRUTHINESS: `if !` reads 126/127/4 as "not LUKS" and luksFormats a
    # store that IS LUKS, destroying every key slot. rc 1 is the ONLY "genuinely not LUKS"
    # (cryptsetup 2.7.0: no-header=1, absent=4, not-on-PATH=127).
    # Stderr goes to a SUBSTITUTION, not `2>>`: a failed redirect returns 1 WITHOUT RUNNING the
    # probe (measured), which the 1) arm would answer with luksFormat. `|| _rc=$?` not `; _rc=$?`
    # — this stage is under `set -euo pipefail` (sshd_config sits ABOVE its `set -e`) and the
    # naked form aborts on rc=1. Disposition inverted from sshd_config deliberately: there,
    # continuing risks a boot; here it REFORMATS THE STORE. Enforced by B18, not by this comment.
    _i=0; while [ ! -e "$DEV" ] && [ "$_i" -lt 30 ]; do sleep 1; _i=$((_i+1)); done
    _isluks_rc=0
    _isluks_err="$(cryptsetup isLuks "$DEV" 2>&1)" || _isluks_rc=$?
    [ -z "$_isluks_err" ] || printf '%s\n' "$_isluks_err" >>"$GIT_DATA_LUKS_DETAIL" 2>/dev/null || true
    case "$_isluks_rc" in
      0) : ;;
      1) printf '%s' "$GIT_DATA_LUKS_KEY" | cryptsetup luksFormat --batch-mode --type luks2 --key-file - "$DEV" 2>>"$GIT_DATA_LUKS_DETAIL" ;;
      *) { echo "[git-data-luks] FATAL: the LUKS-status probe could not run (rc=$_isluks_rc) — refusing to format a device whose status is unknown" | tee -a "$GIT_DATA_LUKS_DETAIL" >/dev/null; exit 1; } || exit 1 ;;
    esac
```

Three details, each from a specific finding:

- The catch-all message **must not contain the tokens `cryptsetup isLuks` or `luksFormat`**.
  `p_isluks` greps the **whole file including comments** (kieran P1-1), and B18's predicate (d)
  would see two arms "reaching `luksFormat`" (kieran P1-7). Predicate (d) must also match
  `cryptsetup[[:space:]]+luksFormat`, not the bare token.
- `{ …; exit 1; } || exit 1` — a `case` arm is **not** errexit-exempt (unlike the `||`-RHS the
  empty-key guard uses), so a failing `tee` on an unwritable `/run` would otherwise exit with
  `tee`'s status. Drop v1's false "mirrors the guard above it" claim.
- Do not change `luksFormat`'s flags, its `printf … | … --key-file -` stdin delivery, or its
  `$DEV` operand — A2/A3 and `lint-encryption-posture.py`'s apparatus resolver read them.

**2.2 — the parent scoped file**, seeded after `export HOME=/root`, **before** `trap on_err EXIT`:

```sh
    # (#7227) Parent-shell detail source. NOT /var/log/cloud-init-output.log: this shell runs
    # outside `doppler run`, so _devalue degrades to `cat` and a shared multi-stage log is
    # bounded by nothing — and the rung-2 capture projects `detail` into a PUBLIC Actions log.
    # Seeded above the trap so the handler never reads an unset path. /dev/null fallback keeps
    # an unwritable /run from aborting the boot at the first redirected command.
    GIT_DATA_RUNCMD_DETAIL=/run/git-data-runcmd.log
    ( umask 077; : > "$GIT_DATA_RUNCMD_DETAIL" ) || true
    [ -w "$GIT_DATA_RUNCMD_DETAIL" ] || GIT_DATA_RUNCMD_DETAIL=/dev/null
```

The ordering rationale is **not** `set -u` (kieran P2-3): the parent arms `set -e` only. Unseeded,
`$GIT_DATA_RUNCMD_DETAIL` expands empty and `_detail=".final"` — a relative path in cloud-init's
cwd. Say the true reason.

**2.3 — `on_err`, with a distinct local**, and **delete `bootstrap_err` entirely**
(code-simplicity #2). The two handlers were byte-identical but for `MSG`; `$STAGE` is already
interpolated and already set per stage. Deriving `MSG` also fixes a **latent live bug**: nothing
disarms `bootstrap_err` after the bootstrap stage, so a `gc_timer` failure today emits the title
"git-data bootstrap FAILED". This is the same principle the template already argues at "Title says
what was MEASURED". `MSG` is `_san`'d, so interpolation is safe. Flag the Sentry regrouping in the
PR body as a deliberate consequence.

```sh
    on_err() {
      rc=$?
      trap - EXIT
      [ "$rc" -eq 0 ] && exit 0
      # dmesg FIRST, the stage's own stderr LAST — the emitter double-truncates
      # (tail -n 20 | … | tail -c 180), so whatever is last survives. No cloud-init-log slot:
      # luks_err can afford it under doppler with _devalue armed; this handler cannot.
      _onerr_detail="$GIT_DATA_RUNCMD_DETAIL.final"
      ( umask 077; : > "$_onerr_detail" ) || true
      {
        dmesg 2>/dev/null | tail -n 20 || true
        if [ -s "$GIT_DATA_RUNCMD_DETAIL" ]; then
          grep -v 'dmesg(1) may have more information' "$GIT_DATA_RUNCMD_DETAIL" 2>/dev/null || true
        else
          echo "git-data $STAGE rc=$rc: no stderr captured for this command (dmesg tail above)" || true
        fi
      } > "$_onerr_detail" 2>/dev/null || true
      [ -s "$_onerr_detail" ] || _onerr_detail="git-data $STAGE rc=$rc: detail capture unavailable (/run unwritable or empty)"
      /usr/local/bin/git-data-emit "git-data $STAGE FAILED" "$STAGE" fatal \
        "$_onerr_detail" "rc=$rc" || true
      exit 1
    }
```

The `else` branch is C4: without it the dmesg tail alone satisfies `[ -s ]` and the literal is
unreachable. The `( umask 077; : > … )` on `.final` is C-architecture-P1-2 — v1's comment claimed
0600 protection the ambient 022 umask did not deliver. **Apply the same one-line umask fix to
`luks_err`'s `.final`** in this PR; it is a live 0644 on a host with a real local `git` account,
and the template is already being re-hashed.

Rename `luks_err`'s local `_detail` → `_luks_detail` so no two sites share a name (C3).

**2.4 — per-stage truncation (C5).** After each `STAGE=` assignment in the parent, add
`: > "$GIT_DATA_RUNCMD_DETAIL" 2>/dev/null || true`. This makes the file stage-scoped and is what
lets the `2>>` list stay short.

**2.5 — `2>>` on the parent's fallible commands.** Trimmed from v1's nine to the four that
produce stderr worth a slot in a 180-byte window (code-simplicity #4): the doppler-download
`curl` (it sets `-S`), `sha256sum -c -` (a supply-chain event), and **both** `doppler run`
invocations (the #6982 W0 discriminator — clause B of the Decision governs these). Dropped:
`tar xzf` and `chmod +x` (only reachable after the checksum passed), `mount … || true` and
`systemctl daemon-reload` (both MUST-TOLERATE — they can only inject noise from a *tolerated*
failure). Per-stage truncation makes those drops safe rather than merely cheap.

Add no new redirect to any `cryptsetup` line beyond the existing ones.

**2.6 — the `gc_timer` warning.** The guard must live **inside the failure branch** (kieran
P1-6): placed above the `||` chain it runs *before* `systemctl` writes stderr, so on a real
failure it would unconditionally discard the actual error. The `{ }` group is the RHS of `||`, so
errexit is suspended inside it — the same exemption `systemctl restart sshd || { … }` already uses.

```sh
    systemctl enable --now git-data-gc.timer 2>>"$GIT_DATA_RUNCMD_DETAIL" || {
      _gc_detail="$GIT_DATA_RUNCMD_DETAIL"
      [ -s "$_gc_detail" ] || _gc_detail="git-data gc timer failed to arm: no captured stderr"
      /usr/local/bin/git-data-emit "SOLEUR_GIT_DATA_GC timer failed to arm" "$STAGE" warning \
        "$_gc_detail" "gc_timer=unarmed" || true
    }
```

This also makes the emitter `toks[0]` of its own simple command, which is what lets the widened
guard read it (kieran P1-5).

**2.7 — the `sshd_config` stage.** It has **three** emits, not two (spec-flow): the fatal, the
126/127 warning, and the `systemctl restart sshd || { … }` warning that ships `detail=""`. Bind
`_sshd_detail` immediately after `_sshd_t_rc=$?` (so the 126/127 branch cannot reference it
unbound), `[ -s ]`-guard it, and use it in all three:

```sh
    _sshd_detail=/run/git-data-sshd-t.err
    [ -s "$_sshd_detail" ] || _sshd_detail="git-data sshd -t rc=$_sshd_t_rc: no stderr captured"
```

Also fix the **naked capture on that stage's own probe** (kieran P2-5): the plan spends a page
arguing "could not measure" must never read as "measurement is false", on a line it is already
editing. `2>/run/git-data-sshd-t.err` failing on an unwritable `/run` yields rc=1, which this
stage reads as "config REJECTED" and answers with `exit 1` — a permanently bricked boot. Use the
same substitution shape as 2.1.

**2.8 — `git-data-bootstrap.sh`: `log()` writes stderr.** One line
(`echo "[git-data-bootstrap] $*" >&2`). Its 20 `log "FATAL: …"` sentences currently go to
**stdout**, so the parent's scoped file would capture none of them. Free: comments and content in
this file are render-stripped, so it costs zero stored bytes.

**2.9 — budget.** Re-run `git-data-userdata-budget.sh`; headroom must be `> 0`. Overflow prose
moves to `git-data-bootstrap.sh` (free) or the ADR-147 addendum — never a guard, a redirect, or a
`case` arm.

### Phase 3 — GREEN: the guards

**3.1 — `git-data-luks.test.sh`, the `B18` family.** Re-point `p_isluks` (A1) at
`_luks_slice "$1"` instead of the raw file — it is a whole-file grep today and this plan's own
comment would otherwise satisfy it. Predicates: no `if ! cryptsetup isLuks` survives; a
substitution capture with `|| _isluks_rc=$?` exists; `case "$_isluks_rc" in` exists; exactly one
arm reaches `cryptsetup[[:space:]]+luksFormat`; a catch-all `*)` reaches `exit 1`.

Four arms. Anchoring notes (kieran P2-4): the revert-to-`if!` mutation cannot be a single-line
`s///` — use `s/^([[:space:]]*)_isluks_rc=0$/\1if ! cryptsetup isLuks "$DEV"; then :; fi/`; the
drop-`exit 1` arm must anchor on `\*\)` so it does not also hit the empty-key guard; the
naked-capture arm needs a non-`|` delimiter (`s#\|\| _isluks_rc#; _isluks_rc#`).

**3.2 — the widened `R3(3b)`.** Build a comment-stripped `runcmd-all.code.sh` beside the existing
`runcmd-all.sh`, with a **shell-level counted** non-vacuity arm (a python `assert` inside the
extraction heredoc does not increment `passes`/`fails` — kieran P1-4 — and aborts extraction in a
way that surfaces as a *different* arm's failure). Then:

- locate the emitter token and index **relative to it**, never `toks[4]`
- assert the **set of message literals**, not a count: a bare `len(m) == 4` passes a tree where
  one site was deleted and another added
- scope the guard search to the site's own window (`gpat.search(joined, wstart, epos)` where
  `wstart` is the enclosing handler's start), and assert the arg-4 names are **pairwise distinct**
  so the next author cannot re-create the alias
- **`R3(3c)`** literal-direction control and **`R3(3d)`** deleted-guard control → `UNGUARDED`.
  Without `R3(3d)` the `UNGUARDED` verdict has no demonstrated failing direction anywhere.
- **`R3(2d)`** the AC7 ordering arm (seed precedes `trap on_err EXIT` and the first `2>>`), plus
  its relocation mutation, mirroring `R3(2c)`.

Correct the Phase 2.1 comment's claim about what `R3(3b)` asserts — after this it is a **set**,
not "exactly one per stage".

**3.3 — capture-script arms** (production name refused / rehearsal name accepted / a
rehearsal-prefixed name with a quote still refused — the charset property must not be lost).

**3.4 — fold the prefix pin into arm 10's existing comparison chain** (dhh) rather than a new arm
plus its own mutation: arm 10 already compares `rehearsal.tf` against two workflow literals.

**3.5 — clause-B mechanization** (the Decision section): assert `special = false` on
`random_password.git_data_luks`, no `set -x` in the template or bootstrap, and `--key-file -` on
every key-consuming `cryptsetup` call.

**Floors: re-derive all four from measured totals after the arms exist.** Do not carry a number
from this plan — v1's `36 -> 41` was arithmetically unreachable, and all four suites currently sit
exactly on their floors, so every floor moves. Each raise carries an itemised sum in the style
already used in its file.

### Phase 4 — the capture script and the CI path filter

**4.1** Constrain `--host-name` to `^soleur-git-data-rehearsal-[A-Za-z0-9._-]+$` — strictly
narrower than the existing charset check, compatible with the only production call site
(`${REHEARSAL_PREFIX}${GITHUB_RUN_ID}`) and with the test fixture. **No override flag:** reading
production boot telemetry is a different tool with a different output contract, not a flag on this
one. Comment states that the 180-byte emit-time bound is a bound on *volume*, not a guarantee
about *content*, and is applied on the host — this script is a reader and inherits what shipped.

**4.2** Add `scripts/followthroughs/git-data-rung2-evidence-capture.sh` to
`infra-validation.yml`'s `paths:`, beside the three workflow paths already there for the same
reason.

**4.3** Write the ADR-147 addendum.

### Phase 5 — Verification

5.1 Re-run the Phase 0 baselines plus `bash scripts/test-all.sh`. Note the correct invocation for
the second user_data gate: `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` — it
lives in `plugins/soleur/test/`, imports from `bun:test`, and is **not** a vitest suite in
`apps/web-platform/test/` as v1 claimed. Read its modelled ceiling before Phase 2; it may bind
tighter than the raw 32,768 cap.

5.2 `python3 scripts/lint-encryption-posture.py` **and** `--repo-sweep` (the form `ci.yml` runs).
Both `PASS` at the baseline counts.

5.3 `apps/web-platform/infra/git-data-rung2-boot-evidence.env` still absent and not in the diff.

5.4 The birth-readiness gate library untouched; `git_data_rung2_rehearsal_gate` still HOLDs
fail-closed with no evidence file.

### Phase 6 — Ship

PR body carries: the Phase 0.4 rc measurement verbatim; the C2 forged-rc-1 measurement (it is the
strongest evidence in the PR); the chosen #7227 item-1 option with its **two-clause** invariant;
the two deliberate divergences from `sshd_config`; before/after budget numbers; the deliberate
Sentry-regrouping consequence of deriving `MSG` from `$STAGE`; and `Closes #7216. Closes #7227.`
in the body. `decision-challenges.md` is rendered in and filed as an `action-required` issue.

**No rehearsal dispatch, no birth.**

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — No `if ! cryptsetup isLuks` survives on the comment-stripped luks slice; a
  substitution capture with `|| _isluks_rc=$?` and a `case "$_isluks_rc" in` do. `B18` green.
- **AC2** — Exactly one `case` arm reaches `cryptsetup luksFormat`; the catch-all reaches
  `exit 1`. Both mutation-armed.
- **AC3** — The naked-capture form and the `2>>`-on-the-probe form are both **detected**
  regressions (the mutation arms flip the predicate).
- **AC4** — `p_isluks` (A1) reads `_luks_slice`, not the raw file: deleting the `case` block and
  the real probe must redden A1. *(v1's AC4 — "the comment contains the token `sshd_config`" — is
  **deleted**: it was a token-presence check on a comment, in a plan whose own Sharp Edges cite
  the learning about guards satisfied by the comment written to explain them.)*
- **AC5** — Every `git-data-emit … fatal` site **in the concatenated `runcmd`** passes a variable
  whose `[ -r ]`/`[ -s ]` guard precedes it *within that site's own window*, the arg-4 names are
  pairwise distinct, and the message-literal set matches exactly. `R3(3c)` and `R3(3d)` both
  demonstrate failing directions.
- **AC6** — No emit site **at any level** passes `/var/log/cloud-init-output.log`, evaluated with
  **emitter-relative** token indexing (measured: `toks[4]` is `'||'` on the `gc_timer` line and
  would report a false zero).
- **AC7** — `GIT_DATA_RUNCMD_DETAIL` is seeded before `trap on_err EXIT` and before the first
  `2>>`, asserted as an **ordering** by `R3(2d)` with a relocation mutation. *(In v1 this AC had
  no arm behind it at all.)*
- **AC8** — The capture script refuses `soleur-git-data` (rc 64), accepts
  `soleur-git-data-rehearsal-17250000001`, and still refuses a quote-bearing name.
- **AC9** — Arm 10's comparison chain includes the capture script's prefix literal.
- **AC10** — `infra-validation.yml`'s `paths:` list **parsed as YAML** contains the capture-script
  path. *(A grep would be satisfied by a commented-out line.)*
- **AC11** — `git-data-userdata-budget.sh` output **contains a `stored=<n> B` line** and
  `n < 32768`. *(Asserting the measurement exists, not just exit 0 — the script SKIPs and exits 0
  without terraform.)*
- **AC12** — `lint-encryption-posture.py --repo-sweep` PASS at the baseline counts.
- **AC13** — `git-data-rung2-boot-evidence.env` absent and not in the diff.
- **AC14** — `git-data-bootstrap.sh`'s `log()` writes to fd 2, asserted by an arm.
- **AC15** — Clause B is mechanized: `special = false`, no `set -x`, `--key-file -` on every
  key-consuming `cryptsetup` call.
- **AC16** — Each Phase-1 `assert_holds` RED was **observed failing** and quoted in the PR body,
  with the pre-measured `R3(3b)` verdict set matching
  `{on_err: LITERAL, sshd_config: LITERAL, bootstrap_err: LITERAL, luks_err: VAR:GUARDED}`.
- **AC17** — The Phase 0.4 measurement is re-taken on the branch showing `rc_nonluks=1`.
- **AC18** — All four floors re-derived from measured totals, each with an itemised sum.
- **AC19** — The ADR-147 addendum exists and records the widened exception + measured byte cost.

*(v1's "arm 20d stays green" AC is deleted — it restated "do not break the suite", which Phase 5.1
already means. Floor-comment formatting moved from an AC to a Phase 3 instruction.)*

### Post-merge (operator)

- **AC20** — Dispatch `git-data-rung2-rehearsal.yml` once; PASS = `stage:boot_complete`, four
  booleans positive, no `level:fatal`. **Automation: not feasible because** each dispatch spends a
  real paid `cpx22` and the spend decision is the operator's (`workflow_dispatch` by design,
  #7025's DO-NOT-DISPATCH banner). **On FAIL:** diagnose from the `git-data-rung2-capture-log`
  artifact (7-day retention) **and Sentry** — note that a parent-shell fatal reports **TRANSIENT**,
  not FAIL, until #7116 is closed, so confirm against Sentry
  (`host_name:soleur-git-data-rehearsal-<run-id>`, org `jikigai-eu`, project `web-platform`) before
  concluding. **Spend dispatch #2 only after a fix lands — never as a bare retry.**
- **AC21** — Only after AC20 passes does the capture script write the evidence file and the
  interlock release; the procedure is
  `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md`.

## Test Scenarios

| # | Scenario | Expected |
| --- | --- | --- |
| T1 | `cryptsetup` absent from `PATH`, volume already LUKS | fatal `rc=127`; **no** `luksFormat`; store survives |
| T2 | Fresh blank volume at birth | rc=1 → `luksFormat`; birth proceeds |
| T3 | Volume not yet attached | bounded wait, then rc=4 → fatal naming rc=4 |
| T4 | `cryptsetup` present, not executable | rc=126 → fatal |
| T5 | **`/run` unwritable at probe time** | the probe still RUNS; rc is real; the append is skipped. **v1 would have forged rc=1 and reformatted the store.** |
| T6 | Bootstrap fails an invariant | child's `log() FATAL` emit (redacted, under doppler) carries the cause; `on_err` is the backstop |
| T7 | Bootstrap fails at bash level (no `log()`) | `on_err` ships the stage-truncated scoped file |
| T8 | `/run` read-only at handler time | self-describing literal, reachable because it is the last line when the scoped file is empty |
| T9 | An earlier tolerated `mount` failure, later stage fatals | the later stage's detail does **not** carry the earlier error (per-stage truncation) |
| T10 | A 5th fatal site added with a bare literal | message-set mismatch **and** a `LITERAL` verdict |
| T11 | A site's `[ -s ]` guard deleted | `UNGUARDED` (`R3(3d)`) — in v1 this stayed green |
| T12 | Capture script aimed at `soleur-git-data` | exit 64; nothing queried, written, or logged |

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| `rc_nonluks` differs on some build | Phase 0.4 STOPs. Measured 1 on 2.7.0 (image) and 2.8.4 (local). The rehearsal boots a real blank volume — the authoritative second check. |
| Birth becomes stricter (rc=4 aborts) on an attach race | Phase 0.5 + the bounded 30 s `$DEV` wait. ~60 bytes of insurance on a two-dispatch budget. |
| Byte budget overflow | AC11 gates it *and* asserts the measurement exists. Comment blocks capped at ~6 lines (v1's prose measured +2,012 stored B = 30% of headroom). |
| Clause B is behavioural, not structural | Mechanized by Phase 3.5. The bootstrap stage's primary cause-carrier remains the child's redacted emit. |
| A parent-shell fatal reports TRANSIENT and burns dispatch #2 | AC20's FAIL branch names Sentry as the confirming channel and forbids a bare retry. The real fix is T-1 (#7116) — recommended **before** dispatch. |
| Deriving `MSG` from `$STAGE` regroups a Sentry issue | Deliberate; the template already argues "title says what was MEASURED". Flagged in the PR body. |
| `encryption-posture` linter mis-parses a redirect near cryptsetup | The probe no longer carries a redirect at all; the linter's `luksOpen`-only parser never reads `isLuks`. Phase 5.2 runs both forms locally. |
| Rung-2 evidence goes stale | Expected — the reason files 1-3 batch. The file does not exist on main; AC13 keeps it that way. |

## Alternative Approaches Considered

| Alternative | Why not |
| --- | --- |
| Split PR-A (hash-coupled) / PR-B (hash-neutral) | Surfaced as **UC-1**; not auto-applied. The operator directed one PR, and the operator's stated direction is the default (ADR-084). The plan is cut so the split remains clean if wanted. |
| Option 1 (move the emit inside `doppler run`) | Covers 1 of 3 sites; `on_err` fires for stages with no doppler child. Partially adopted anyway — the bootstrap child's own redacted emit is the primary cause-carrier. |
| Option 2 (pass the key into the emitter's env) | Widens the key into the parent shell and `/proc`. Against **AP-008** and the template's own invariant. |
| Keep `bootstrap_err` as a second handler | Byte-identical to `on_err` but for `MSG`, which `$STAGE` already supplies. Deleting it fixes a latent `gc_timer` mislabel, removes the `_detail` name collision that defeats `R3(3b)`, and recovers ~1.3 kB. |
| A shared `_runcmd_detail()` helper | Moot once `bootstrap_err` is deleted — there is one parent handler. |
| Per-stage detail **files** | Per-stage **truncation** of one file buys the same isolation for one seed and one ordering guard. |
| `exec 2>>"$file"` for the whole parent shell | Diverts stderr from the serial console and the cloud-init log — the only things a human with console access can read. |
| An `--allow-production` override | Reopens the hole for the caller most likely to be in a hurry. |
| "The 180-byte bound is sufficient" | A bound on *volume* is not a claim about *content*, and it is applied on the host at emit time; the script is a reader. |

## Domain Review

**Domains relevant:** Engineering (CTO), Legal/Compliance (CLO), Product (CPO — `single-user
incident` threshold).

### Engineering

**Status:** reviewed. Confined to boot-time shell in one cloud-init template, one stripped payload,
and static guards. No new dependency, service, runtime process, or schema. The panel found two P0
defects in v1's own fix (C1 was correct in v1; **C2 was not**, and would have reconstructed the
bug being fixed) and one guard-widening that shipped weaker than `main` (C3). All are corrected and
measured. Highest residual risk is that birth becomes stricter — bounded by the `$DEV` wait and by
the rehearsal.

### Legal / Compliance

**Status:** reviewed. `detail` can carry repo paths that are `<workspace_id>.git` where
`workspace_id === user_id` — a raw `auth.users.id`; `_clean`'s UUID rule redacts those and is
untouched. The class this plan closes is the **passphrase**, which no pattern rule catches.
Constraining `--host-name` additionally removes the path by which *production* detail could reach a
public Actions log. No new processing activity, data category, or sub-processor — Article 30
register unchanged. No GDPR-gate invocation required: no regulated-data surface per the canonical
regex, and none of the four expansion triggers fire.

### Product/UX Gate

**Tier:** none — no UI surface; the mechanical UI-surface override does not fire.
**Decision:** skipped. **Agents invoked:** none.
**Skipped specialists:** `ux-design-lead` (N/A — no UI surface). **Pencil available:** N/A.

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

**No new infrastructure.** No Terraform resource created, destroyed, or re-mechanised; no vendor
account, secret, DNS record, unit file, or cron. The change edits the *content* of an existing
`templatefile()` input and one `file()`-bound payload.

### Terraform changes

None. No binding, variable, provider or version pin changes; no new `TF_VAR_*`, so no operator
mint and no sequencing constraint.

### Apply path

**(a) cloud-init-only, deferred behind the existing interlock.** `hcloud_server.git_data` has no
`ignore_changes = [user_data]`, so the edit is `ForceNew` — which is why the interlock exists and
why this PR applies nothing. `apply-web-platform-infra.yml`'s git-data path stays held by
`git_data_rung2_rehearsal_gate`, which HOLDs fail-closed while no evidence file is committed
(verified absent; the CI freshness step is dormant by design). **Blast radius at merge: zero hosts.**

The `systemctl` lines this plan quotes are **pre-existing `runcmd` lines already delivered by
cloud-init** — already IaC-routed; only their stderr routing changes. No phase asks an operator to
SSH, run `systemctl` by hand, click a dashboard, or set a secret.

### Distinctness / drift safeguards

The rung-2 rehearsal root renders through the same module with a distinct state key and a distinct
`host_name` prefix, pinned in three places by arm 10 and, after Phase 3.4, in a fourth. Phase 4.1's
constraint is a further safeguard: the evidence reader can no longer be pointed at production.

### Vendor-tier reality check

Not applicable — no provider resource is created. The only spend is the rehearsal's paid `cpx22`,
capped at two dispatches and gated on the operator.

## Downtime & Cutover

*Required by deepen-plan Phase 4.55: the template edit is `ForceNew` on `hcloud_server.git_data`
(verified — that resource declares no `lifecycle { ignore_changes = [user_data] }`), which is the
infra reboot/replace trigger class.*

**The offline-inducing operation and the surface it affects.** Editing
`cloud-init-git-data.yml` changes `user_data`, which Hetzner applies by **replacing** the server.
The affected surface is the git-data host: the `git` transport user, the bare-repo root on
`/mnt/git-data`, and the LUKS store at `/mnt/git-data-luks`.

**User-visible downtime: none — and for a stronger reason than the flag.** Two independent facts,
both verified:

1. **The host does not exist yet.** `hcloud_server.git_data` has never been born — the birth
   runbook (`knowledge-base/engineering/operations/runbooks/git-data-birth.md`) carries a
   DO-NOT-DISPATCH banner and `git_data_rung2_rehearsal_gate` exits 1 before planning anything
   while `git-data-rung2-boot-evidence.env` is absent. There is no running server to replace.
2. **Even once born, the store is dark.** `GIT_DATA_STORE_ENABLED` is absent from Doppler `prd`,
   and `apps/web-platform/server/workspace-resolver.ts` gates every git-data read/write on
   `process.env.GIT_DATA_STORE_ENABLED === "true"`. `apply-web-platform-infra.yml` says so in its
   own operator banner.

So the first apply is a **birth**, not a replacement, and no user push, clone, or workspace
operation routes to this host in either state. Zero in-flight requests dropped, zero sessions
interrupted. The gate's zero-downtime evaluation is satisfied by *absence of the surface*, not by
a cutover mechanism — and saying exactly which of the two facts is load-bearing matters, because
they expire at different times.

**Blast radius of THIS PR at merge: zero hosts.** The plan applies nothing.
`apply-web-platform-infra.yml`'s git-data path stays held by `git_data_rung2_rehearsal_gate`,
which HOLDs fail-closed while no `git-data-rung2-boot-evidence.env` is committed (verified
absent). The replacement happens later, at the operator-gated birth — not on this merge.

**Where the already-LUKS volume actually comes from — and why #7216 is not hypothetical.** The
*first* birth runs against a blank volume (rc=1 → `luksFormat`, the correct path). The dangerous
state is every boot **after** the volume has been formatted once, because a `ForceNew` provisions
a fresh instance while the **block volumes persist and re-attach**. Three concrete routes reach it,
all on the near path:

- a **retried birth** after a partially-successful one (LUKS formatted, a later stage failed) —
  the most likely single case, and the plan's own AC20 contemplates a second dispatch;
- any **later `user_data` edit** once the host exists (this file is edited constantly);
- a host replace for an unrelated reason (`server_type`, image, placement).

In each, the replacement boots `runcmd` against an already-LUKS volume — precisely the `isLuks`
path this PR fixes. **The fix must land before the birth, not after**: once a volume has been
formatted, every subsequent boot is a coin-flip on whether `cryptsetup` was reachable.

**Per-stage verification and rollback.** Verification is the rung-2 rehearsal itself — a
throwaway host with throwaway volumes, born and destroyed by the workflow, asserting
`stage:boot_complete` with no `level:fatal` before any production host is touched (ADR-149's
interlock). Rollback for the *production* birth is that the volumes are untouched by a failed
boot: a host that aborts in `runcmd` leaves the LUKS header intact (that is the whole point of
the catch-all `exit 1`), so a failed birth is retried by replacing the host again, not by
restoring data. **The one path with no rollback is the bug being fixed** — a `luksFormat` on an
already-LUKS volume destroys every key slot, and no amount of cutover discipline recovers it.

**Residual downtime accepted:** none, and no maintenance window is needed. If the store is
serving by the time the birth actually runs (i.e. `GIT_DATA_STORE_ENABLED` has flipped),
**re-run this section** — the trivial answer above expires with the flag.

## Sharp Edges

- **`2>>` on a probe whose rc you branch on is a forged-rc hazard.** A failed redirect returns 1
  *without running the command* (measured). Any future "capture this probe's stderr" edit must use
  a substitution, not a redirect, wherever rc=1 has a destructive meaning.
- **The issue's proposed fix shape is wrong under `set -e`.** `B18 (naked rc capture)` exists to
  catch it.
- **`p_isluks` (A1) greps the whole file, comments included.** Any comment naming
  `cryptsetup isLuks` makes it vacuous. Phase 3.1 re-points it at `_luks_slice`; keep it that way.
- **`R3(3b)`'s guard search is name-keyed.** Two sites sharing a local name silently disable the
  check for the later one. Phase 3.2 adds a pairwise-distinctness assertion; do not remove it.
- **`toks[4]` is not arg 4** for any `||`-chained emit. Index relative to the emitter token.
- **A python `assert` inside the extraction heredoc is not a counted assertion.** Floors must be
  derived from measured totals.
- **Comments in `cloud-init-git-data.yml` are NOT stripped at render** (ADR-152 covers only the
  nine payloads). Measured: comments are 65% of that file's raw bytes. Comments in
  `git-data-bootstrap.sh` are free.
- **Zero-marginal-dispatch window (cto F2):** because this PR already re-hashes
  `RUNG2_TEMPLATE_SHA256`, a follow-up that extends the render-strip to the template body
  (~14 kB recoverable, measured) costs **zero** extra dispatches **if merged before any dispatch**.
  It is sequencing, not batching, that makes it free. See T-2.
- **The parent runcmd shell is `/bin/sh` = dash.** POSIX only.
- **The rehearsal job does not fail on parent-shell fatals** (#7116). Confirm against Sentry before
  concluding TRANSIENT.
- **`tests/scripts/` is invisible** to `lint-orphan-test-suites.sh` and `run-registered-suites.sh`;
  `test-git-data-rung2-evidence-capture.sh` is reachable only via `scripts/test-all.sh`.
- **`git-data-rung2-rehearsal.test.sh` arm 20d** couples the emitter's `--data-raw` line to the
  capture script's `HOST_SQL`, fail-closed both ways.
- **Do not dispatch the rehearsal or the birth in this run.**

## Research Insights

- `knowledge-base/project/learnings/2026-08-03-four-guards-were-satisfied-by-the-comment-i-wrote-to-explain-them.md`
  — the direct predecessor (#7204/#7197). Strip at extraction; `[ -s ]` not `[ -r ]`; the terminal
  fallback must be a literal. Drove the A1 re-pointing and the catch-all message reword.
- `knowledge-base/project/learnings/2026-07-29-every-guard-i-fixed-this-session-was-narrower-than-the-claim-it-carried.md`
  — a guard whose domain is derived from the artifact under test proves nothing. Drove Phase 3.4's
  hardcoded literal and the region-scoped guard search.
- `knowledge-base/project/learnings/2026-07-24-guest-luks-store-must-gate-consumer-on-mount-and-guard-suite-must-pin-fail-loud-semantics.md`
  — pin exit-code semantics, not token presence. Drove the catch-all `exit 1` arm.
- `knowledge-base/project/learnings/2026-08-01-my-mutation-battery-inferred-the-verdict-from-the-input-under-test.md`
  — `grep -c` prints 0 and exits 1; use `|| true` in count assignments.
- `knowledge-base/project/learnings/2026-07-27-my-assertion-pinned-the-text-not-the-shell-that-runs-it.md`
  — the grep domain must match the execution domain. Drove AC5/AC6's "concatenated `runcmd`"
  scoping.
- `knowledge-base/project/learnings/2026-07-30-four-ways-a-green-guard-asserted-nothing-rung2-route.md`
  — the rung-2 route's own catalogue of vacuous-green shapes.
- Measured this session: `set -e` rc-capture forms; **the forged-rc-1 redirect failure**;
  `cryptsetup isLuks` codes on 2.7.0 and 2.8.4; `shlex` tokenization of all four fatal sites and of
  the `||`-chained emit; the four suite baselines; budget headroom; linter baseline; `special = false`.

## Follow-Through Enrollment

None. No acceptance criterion is soak-gated — the rung-2 rehearsal is a single bounded dispatch
with a pass/fail verdict, not a soak.
