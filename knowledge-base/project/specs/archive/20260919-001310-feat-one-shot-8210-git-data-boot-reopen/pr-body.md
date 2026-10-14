# fix(git-data): reopen /dev/mapper/git-data on every boot, proven by a rung-2 reset arm

`Ref #8210` — deliberately not `Closes`. The fix reaches no live host at merge: it ships inert
and is delivered by PM4's guarded replace, so the issue is closed by a follow-through probe once
the reboot evidence really lands on `main`. `Ref #8010`, `Ref #8211`.

Plan: knowledge-base/project/plans/archive/20260919-001310-2026-09-18-fix-git-data-luks-mapper-reopen-at-boot-plan.md
(archived by compound; its `## User-Brand Impact` and `## Observability` sections carry the dated
review addenda). Learning:
knowledge-base/project/learnings/2026-09-19-every-systemd-claim-i-reasoned-was-inverted-by-a-thirty-second-measurement.md

## User-Brand Impact

- **Brand-survival threshold:** `single-user incident` — the store will hold every user's source.
- **Artifact at risk:** a user's `<user_id>.git` (objects, refs, hooks) on the git-data volume.
- **Vector this PR closes:** a post-cutover reboot left the encrypted store absent and no signal
  emitted, so a push could land in an empty root-disk directory and vanish when the store was later
  mounted (until #8101), and every `Settings → Delete Account` hit a fail-closed erasure refusal
  that was swallowed (#8094, not closed here).
- **Vector this PR must not open:** formatting the store. The reopen never formats, never runs
  `mkfs`, never calls `mount(8)`; the birth heredoc's `mkfs` guard is now keyed on the run having
  `luksFormat`'d the device itself; every runbook lever that could reach a replace says so.
- **Passphrase surface:** the unit's process environment under `doppler run` for the seconds it
  runs; `--no-fallback`, `--only-secrets`, tmpfs `TMPDIR`, `PrivateTmp`, `LimitCORE=0` on the reopen
  pair AND (review) the gc pair, which had been caching the resolved config on the root disk.

## The defect

The git-data host opened its LUKS mapper exactly once in its life. `cryptsetup luksOpen` runs
inside cloud-init's `runcmd:` stage, and cloud-init runs `runcmd` **once per instance**; the
fstab line that stage appends carries `nofail`. So on any later boot the mount job waited for a
mapper nothing opened, timed out, and the boot continued with the encrypted store absent **and
no signal emitted** — the host answering on :22 the whole time, which is what every reachability
probe checks. ADR-115 already recorded this as a normative blocker.

No live impact today: the host is born but `GIT_DATA_STORE_ENABLED` gates every write path. This
is the window to land a payload change, which is why it is a precondition of the first real
cutover (#7226, #8209, #8211).

## What ships

One script, one unit, one reporter, two env lines, one runcmd arm, one measured boolean, one
rehearsal reset arm, two ADR amendments, one C4 edge.

- **`git-data-luks-reopen.sh`** — straight-line, no traps, never formats, never calls `mount(8)`.
  Phases: `config → key → device → header → open → identity → target → mount → identity-mount → emit`,
  each written to a phase file *before* it runs so the tag names the phase that was executing
  when the script died, including on SIGTERM.
- **`git-data-luks-reopen.service`** — the `git-data-gc.service` shape under
  `doppler run --only-secrets … --no-fallback` with a templated `--config`, bounded
  `Restart=on-failure` under **`RestartMode=direct`** (so `OnFailure=` fires once per exhausted
  ladder, not once per attempt — measured), `RestartPreventExitStatus=3` for the structural
  emitter refusal, `RuntimeDirectoryPreserve=yes`, `LimitCORE=0`.
- **`git-data-luks-reopen-failure.service`** — `OnFailure=` reporter. One fatal per exhausted
  ladder, carrying `action=<phase>` plus the unit's own `Result`/`ExecMainStatus`/`ExecMainCode`/
  `NRestarts`, with a `timeout 90` that keeps the direct arm reachable when Doppler *hangs*.
- **Routing** — `luks_reopen` and `gitdata_luks_reopen_arm` join the fatal rule;
  `gitdata_luks_reopen_arm_warn` joins the warning rule; **`luks_reopen_ok` is in NO rule**,
  because the fatal router has no `level` condition and an `info` row on a routed stage would
  page on every healthy reboot.
- **`boot_complete` gains `luks_reopen_unit`** — MEASURED (`systemctl is-enabled` AND
  `Result=success`) and TERMINAL, swept into both readers, both SQL projections, the birth
  runbook, the emitter follow-through and the apply workflow's disclosure prose.
- **The rung-2 reset arm** — settle, hard reset by exact server name, then a `--reboot-since`
  probe reading both channels server-side-bounded. The upload gates on both rcs.
- **`git_data_host_replace` joins the rung-2 interlock** — only the create job called it, so an
  un-rehearsed payload could reach the live host by replace from any ref.

## Measured, not assumed (Phase 0)

| Claim | Measurement |
|---|---|
| `luksOpen` is per-instance | It is under `runcmd:`; `bootcmd:` holds only the Sentry beacon; no crypttab; fstab is `nofail` |
| A `mount(8)` inside the unit is invisible to PID 1 | systemd 255 container, shared root: inside `tmpfs`, outside `NONE`. A PID-1 mount propagates back in |
| `RuntimeDirectoryPreserve=yes` is mandatory | Without it systemd removes the dir at the final failed state, **before** `OnFailure=` runs — the reporter would read nothing |
| `Restart=on-failure` is legal on a oneshot | Verified on 255 and 261; `Result`/`ExecMainStatus`/`ExecMainCode`/`NRestarts` all survive `start-limit-hit` |
| Doppler CLI 3.75.3 (pinned, not the host's 3.76.5) | Repeated `--only-secrets`, `--no-fallback`, `--config` all parse; child exit codes forward (measured 7) |
| `cryptsetup isLuks` rc table | 0 LUKS / 1 not-LUKS / 4 absent. `findmnt --fstab` exits 1 on no match |
| Budget | 15,444 → 19,028 B of a 32,768 cap |
| `OnFailure=` under default `RestartMode` | Fires on EVERY attempt (3 reporter runs for a 2-burst ladder); with `RestartMode=direct` exactly 1; a refused tick on an already-failed unit fires 0 |
| `Result=success` is not terminal | Resets to `success` the instant a retry attempt STARTS; `ActiveState=active` is the only terminal-success state of a `RemainAfterExit` oneshot |
| `enable --now` under `RestartMode=direct` | Blocks through the whole ladder; `--no-block` returns in 0 s |

## Deviation from the plan

**AC17** expects the follow-through probe to exit 1 against today's `main`; it exits **2
(TRANSIENT)**. The repo's three-state convention makes "the rehearsal has not run yet" transient,
and a 1 would post a daily false alarm from merge+1d until the operator schedules PM1 — about a
state the plan itself calls the intended safe one. Recorded in `decision-challenges.md` (T4).

## Defects found in this PR's own work, fixed at the cause

1. **`RUNDIR` seam unguarded** — every write derives from it, so an empty value resolved
   `"$RUNDIR/action"` to `/action`: a root-filesystem write, as root, on the host holding every
   user's source. Now validated and `${VAR:?}`-guarded at each use (both needed: the P1b scanner
   reads `readonly` as a re-binding). Measured: `/`, a relative path, `/run/../etc` and
   `/proc/self` each refused by name; the production default still proceeds.
2. **Deferral ledger 47 → 48** — closed by **promotion**, as the gate's own message prescribes,
   not by raising the ratchet.
3. **Inline `assert_fixture_dir` drifted** from the canonical definition by one message string.
4. **The Sentry warn-emit arm checked only the FIRST `$${STAGE}_warn` emit** — blind to a second
   by construction. Generalised to all, mutation-verified.
5. **The capture's FAIL alternation gained a name with no fixture driving it** — a guard nobody
   had seen fire. Now 107/0 → 2 failed when the name is removed.
6. **`NON_TERMINAL` was DEAD** — the consumer-roster guard declared
   `NON_TERMINAL="nft_metadata_drop disk_pct inode_pct"` under a comment reading "declared ONCE,
   here", then re-typed the same three names on the next line in
   `grep -vxF -e nft_metadata_drop -e disk_pct -e inode_pct`. Measured against the PRE-FIX file:
   adding a fourth name to the declared single source left the suite **64/0, rc=0** — a mutation of
   the single source that no assertion could see. Post-fix that mutation REDs 2 arms and dropping
   `inode_pct` REDs 4. Found by `shellcheck SC2034`, run because semgrep cannot match rules on bash.

7. **The replace route was held PERMANENTLY, not until PM2** — the rung-2 interlock was copied
   onto `git_data_host_replace` without the create job's `fetch-depth: 0`, and the gate's
   provenance arm HOLDs on a shallow clone. Pinned in `terraform-target-parity.test.ts`.
8. **`Result=success` is not terminal** — measured on 261, it resets to `success` when retry
   attempt 2 starts, so the boolean read `yes` on a still-retrying unit. Now
   `ActiveState=active`, and the wait loop is DRIVEN against a `systemctl` spy (a busy loop, a
   `while`→`if`, and `|| true` on the predicate each RED).
9. **`OnFailure=` fired per attempt, not once** — the unit comment claimed
   `service_enter_dead()` suppresses it during auto-restart; the opposite is true. A transient
   blip that recovered on attempt 2 paged a fatal and failed the rehearsal's reboot arm.
   `RestartMode=direct` (systemd ≥254; 24.04 ships 255) fixes it; the arm item's two starts are
   `--no-block` so cloud-final does not wait through the ladder. The "~96 fatals/day" cost I
   documented was also false: a refused tick fires nothing; it is one ladder per hour.
10. **The `emit` refusal was invisible** — a retry landed in the silent `noop` branch and erased
    it. Exit 3 + `RestartPreventExitStatus=3`; the runbook row now says the phase is dark by
    construction and names the observable (`luks_reopen_unit=no`; a missing `luks_reopen_ok`).
11. **The gc unit pair wrote the passphrase to the root disk** — no `--no-fallback`, disk-backed
    `/tmp`; ADR-198's "never written to the root disk" was false on the incumbent. Fixed on the
    class (`--no-fallback`, tmpfs `TMPDIR`, `PrivateTmp`, `LimitCORE=0`); ADR-198 corrected and
    its token-scope claim qualified with #6167's measured ceiling.
12. **The birth heredoc's `mkfs` guard was fail-open** — `if ! blkid` treated a damaged ext4
    superblock as blank, on the path every replace this runbook orders re-runs. Keyed on the run
    having `luksFormat`'d the device itself; `B18m` in `git-data-luks.test.sh`, four mutations.
13. **The follow-through probe could never PASS** (a lone `mktemp` template; the gate derives
    the evidence, module and payloads from the template's directory, and reads provenance from
    the checkout's history). Reads the checkout it stands in; TRANSIENT off-main.
14. **`sort=-timestamp` silently dropped** from `sentry-issue.sh`; restored and pinned, with
    four `--stage` callee rows that RED the term-ignored, validator-deleted and pins-dropped
    mutations.
15. **Eleven more vacuous test arms** (test-design seat): the central wire (`enable --now`) was
    a raw-file grep a `#` walked past — now an extracted, comment-stripped body pinned by
    statement shape AND run under `sh` against a `systemctl` spy; the "never formats" and "never
    mounts" regexes were column-0 anchored with the real `mkfs.ext4` reachable from the scratch
    PATH — token-boundary regexes plus recording format traps; the hang row's `sleep 200` hit
    the suite's own no-op `sleep` stub so the timeout arm never ran — now a real sleep with a
    2–20 s range; the passphrase's "on stdin" row had no negative half — every fixture now asserts
    it appears in no artifact but the stdin recorder; `unit_has` was substring — now exact-line
    with section checks; the floor now counts call sites, not verdicts.

## Static analysis, with the coverage stated honestly

`semgrep` returned **0 findings** on all 45 scannable changed files (133 rules from
`p/security-audit` + `p/secrets` + `p/terraform` + this repo's custom rules; plus `p/typescript`
on the 2 `.ts` and `p/terraform` on the 3 `.tf`). That number is not coverage of this diff, and
saying otherwise would misrepresent it:

- Across all 339 rules in those packs, the count declaring `bash`, `sh` or `shell` is **zero**. A
  `.sh` file draws 40 applicable rules; a `.md` file from the same diff draws 38 — shell-awareness
  is a delta of two text-matching rules.
- Canary: a synthetic bash file carrying a hardcoded AWS secret key, a `ghp_` token, `curl … | bash`,
  `eval "$1"`, `rm -rf /$USERDIR`, `ssh -o StrictHostKeyChecking=no`, `chmod 777 /etc/shadow` and
  `echo "$PASSWORD" | sudo -S` produced **one** hit — a text regex on an unrelated
  `wget --no-check-certificate` line. Everything else passed silently.

So semgrep genuinely analysed **5 of 45 files**: the 3 `.tf` (103 applicable hcl/terraform rules,
full parse, clean) and the 2 `.ts` (74 + 66 rules, full parse, clean — both test files, a low-yield
SAST surface). The 17 `.sh` files that carry the substance of this change were **grepped, not
scanned**, and the 3 `.service`, 1 `.timer` and 4 `.yml` — where the `doppler run` invocation and
the unit hardening actually live — drew the same file-type-agnostic rules a Markdown file draws.

The load-bearing static analysis for this diff is therefore **`shellcheck -S error` across all 17
`.sh` files: 0 error-level findings**. At warning level: 33 `SC2319` (this repo's
`ok "$([ … ]; echo $?)"` idiom) and 6 `SC2034`, of which 5 are pre-existing on `origin/main`. The
sixth was a real defect and is fixed above.

## Pre-existing failures, confirmed not mine

23 suites fail on this box independently of this branch: 5 script suites (`scratch-root`,
`guardrails`, both `notice-frontmatter`, `lint-legal-scope-block-placement`) and 18 web-platform
component files (happy-dom 20.8.9 not providing `localStorage`). Each was confirmed by
reproduction in a **sibling worktree on an unrelated branch**, or by this diff provably not
touching the files. (An earlier revision of this paragraph said the diff changes zero files
under `apps/web-platform` outside `infra/`; the git-history seat found that false — it changes
`apps/web-platform/test/sentry-git-data-warning-stages-op-contract.test.ts`. That file is a
string-assertion contract test over the Sentry rules, not a happy-dom component test, so the
conclusion stands on the reproduction, not on the false proof.)

## The full gate, HEAD-frozen — final run on the merged tree

`TEST_GROUP=all bash scripts/test-all.sh` (unsharded, detached, rc-file watched) on `ad67cbdf7`,
the tree that merges: **440/444 suites, 2 skipped (declined, not relevant), 1 `[FAIL]`** —
the nested infra runner, 122/124, whose two reds are environment with inputs identical to
`origin/main`: `canary-bundle-claim-check` (`python3 -m http.server` not answering on
`localhost` within 4 s on this box; reproduced in isolation) and `zot-config-deadlines` (docker
unavailable; fails closed). Both `apps/web-platform` groups are green (the 18 happy-dom files
were fixed on `main` by #8270), and the five pre-existing scripts reds from the earlier run are
green for the same reason. Every suite this PR touches passed.

The earlier (pre-merge) run, kept for the record:

### The full gate, HEAD-frozen (before the main sync)

`bash scripts/test-all.sh` in all three shards (`scripts`, `webplat`, `infra`) against
`b06dad3dd`, queued inside the ADR-133 advisory lock behind another worktree's run rather than
polled for a gap. Every red, by cause:

- **scripts 423/430** — the five pre-existing suites named above, and nothing else. The three
  reds an earlier (moving-tree) run charged to this branch are gone.
- **webplat 3/4** — the 18 happy-dom component files named above; this diff changes no file
  they read.
- **infra 119/123** — one was mine: `ci-deploy.test.sh`'s pinned inventory of every line that
  can `systemctl start` a variable unit (a #8077 ratchet no file-selected suite can see) found
  the reopen script's `systemctl start "$_munit"`. Pinned with the reason it can never be
  `inngest-server` (`--suffix=mount` over a two-name allowlist); 305/305 after. The other
  three are environment or live drift with the inputs identical to `origin/main`:
  `cloud-init-inngest-bootstrap` (pinned inngest tag v1.1.35 vs published v1.1.37),
  `zot-config-deadlines` (docker unavailable, fails closed), `canary-bundle-claim-check`
  (`python3 -m http.server` not answering on `localhost` within 4 s on this box, where
  `localhost` resolves to `::1`; reproduced in isolation).

Two commits followed that run: `8fe66160f` (reporter `TimeoutStartSec` 120→150 + a runbook
sharp edge; Guard 1, strip-parity and doppler-injection-bound re-run green) and the
`ci-deploy` pin above (ci-deploy 305/305). Neither touches a file another suite reads.

## Changelog

### Web Platform (infra)

- git-data: the LUKS mapper is reopened on every boot by a Doppler-fed systemd oneshot; a failure is reported off-host once per exhausted restart ladder with the phase that failed; a 15-minute timer re-runs the ladder hourly on a broken host.
- git-data: `boot_complete` gains a measured, terminal `luks_reopen_unit` boolean; the rung-2 rehearsal hard-resets its throwaway host and proves the reopen before the payload may reach the live host; the replace route joins that interlock (with a full-history checkout so it can release).
- git-data: the birth heredoc no longer formats an existing LUKS container whose ext4 superblock blkid cannot read; the gc unit pair no longer caches the resolved Doppler config on the root disk.
- sentry-issue.sh: `--stage` filter; newest-first sort restored.

### Plugin

- review/work/one-shot skills: three sharp-edge bullets from this session (measure runtime semantics before writing the directive; stub-on-PATH shadowing; a gate reads the live tree).

## Post-merge (all `gh`-driven)

- **PM1** dispatch the rehearsal from `main` (dry-run, then real); the environment approval is the
  one human gate, granted via `gh api … pending_deployments`.
- **PM2** commit the evidence ALONE in an evidence-only PR (Guard 4).
- **PM3** the follow-through probe is what retires the tracking issue once PM2 lands — the issue stays open at merge (see the `Ref`, not `Closes`, at the top).
- **PM4** `git-data-host-replace` — the replace route is HELD until PM2, which is the intended
  safe state. Record as an #8211 prerequisite with contract clauses (a)–(j).
- **PM5** file the follow-on for `--only-secrets … --no-fallback` on the two untouched (the gc
  pair were the other two of four and are fixed here)
  `doppler run` sites and `--retry 2` on the emitter's Better Stack POST.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
