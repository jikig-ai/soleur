---
title: "fix(infra): finish the zot queue — stop presenting the dead GHCR credential, fix the bare-$$ template defect, and give the registry LUKS posture its watcher, launch gate and escrow re-test"
date: 2026-09-21
slug: fix-zot-queue-dead-ghcr-credential
branch: feat-one-shot-8036-zot-queue
issue: 8036
closes: []
refs: [8036, 8037, 8417, 8408, 8449, 8278]
type: fix
priority: p2
domain: engineering
lane: single-domain
brand_survival_threshold: aggregate pattern
---

# fix(infra): finish the zot queue

## Enhancement Summary

**Deepened on:** 2026-09-21. **Review inputs:**

- plan-review: DHH, Kieran, code-simplicity
- the plan-time CTO and the scoped advisor
- the deepen pass: security-sentinel, architecture-strategist, observability-coverage-reviewer,
  test-design-reviewer

Live measurements taken during deepen:

- SOLEUR_ZOT_DISK over 2 h: 23/23 rows `store_luks=yes`, and still the PID-shaped
  `store_probe_rc`
- ci-deploy over 24 h: 9 `cosign_absent` and 9 `relogin_failed`, all on one host
- registry memory: 3,814 MB total, zot ≈ 50 MB resident
- user_data: 15,940 B stored, 16,828 B headroom

Key improvements:

1. **Phase 1 collapsed** to a `DOCKER_CONFIG` prefix plus a `{"auths":{}}` file plus
   `env -u DOCKER_AUTH_CONFIG`. A `VERIFIED_REF` stdout-corruption P0 dissolved with it.
2. **Sentinel gate** gains its NIC-guard recovery arm, which prevents a permanent outage on the
   late-mount path. It also gains a shipped `zot_start_action` field and `luks_open_arm` field.
3. **Escrow:**
   - an OOM-safe KDF run (memory pre-check plus `OOMScoreAdjust`)
   - `--only-secrets`
   - cron minute 19, clear of the other jobs
   - a backgrounded boot run after zot starts
   - a 26 h stale threshold, and every value other than `ok` pages
4. **Alert:**
   - the direct-POST envelope anchor, against forgery on the shared source
   - the `raw`/`message` column form
   - per-arm ordering asserts
   - a ≥2-row grace
5. **UC2 workflow:** host text never reaches the public job summary.
6. **Guard 1:** covers the nested `modules/git-data-userdata` template, 8 files in all.
7. **`_bk_rc`** reset, so a healthy host reads `cs0.bk0` and not `cs0.bkna`.

New considerations:

- The merge fires **four** pipelines, not three, and P3 waits for the co-fired release.
- The C4 edge moved to a second `hetzner -> ghcr` edge, the live anonymous dependency.
- ADR-096 gains a fail-closed-launch amendment.

## Overview

One branch (draft PR #8456) drains the zot/registry queue, in this order:

1. **#8036 / #8037 — the dead GHCR credential.** The deploy's cosign verifier-image pull stops
   presenting a revoked credential (1a). One deploy then reports, without SSH, which docker config
   carries the stale `ghcr.io` entry (1b). GHCR's fate (1c) is **recommended** in the PR body. It
   is not decided here, and it does not block 1a/1b.
2. **#8417 — the bare `$$` defect in the registry template.** There are **two** instances, not
   one (see Research Insights). Fix both, and add a guard over every `templatefile()`-rendered file.
3. **#8408 — the standing alert (a), the reboot-surviving launch gate (b), and the escrow re-test
   (c).** None of the three on its own discharges #8408. It stays open under its existing
   follow-through enrolment.
4. **#8449 UC2 — make `scripts/inngest-host-state.sh` dispatchable.** A ~40-line
   `workflow_dispatch` wrapper. UC1 gets a recommendation. UC3 is repo-wide and is not touched.
5. **#8278 — re-check the premise and leave it blocked.** One comment. No code.
6. **The sweep — file LAST, as ONE issue**, after a dedup search and a CONCUR gate.

**Merging fires four production pipelines.** This is the single most important fact for whoever
merges. The count was corrected from three by the deepen review.

- `ci-deploy.sh` is a `terraform_data.deploy_pipeline_fix` trigger file, so the auto-apply pushes
  it to the web hosts.
- `cloud-init-registry.yml` gets a non-comment edit. That fires
  `registry-host-replace-dispatch.yml` on push to main, which is preflight-gated and delta-gated.
  The result is a **registry host replace** that keeps the volume.
- The new `logtail_exploration*` pair is applied through the `-target=` lines added to
  `apply-web-platform-infra.yml`.
- `web-platform-release.yml` runs, because `ci-deploy.sh` is under `apps/web-platform/**`.
  Preflight P3 **waits up to 2,100 s** for that co-fired release before it lets the replace
  proceed. If the release outlasts the wait, the replace refuses, and it is re-fired through
  the dispatcher's own `workflow_dispatch` (`reason=` and `tracker=8408`) once the release
  completes. That re-fire is the ship post-merge step, not an operator action. The release's
  own deploy may still run the **old** `ci-deploy.sh`, so evidence for 1a and 1b counts only
  from deploys after the `deploy_pipeline_fix` apply concludes.

The PR body states all four. Before merge it asserts "merged", never "deployed".

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (measured 2026-09-21) | Plan response |
|---|---|---|
| The #8036 credential is dead (7-week-old measurement) | **Re-probed 06:57Z.** `GHCR_READ_TOKEN` is 40 chars with a `ghp_` prefix. `GET api.github.com/user` returns **401**. `GHCR_MINTER_DISABLED=true`. An anonymous token plus a manifest HEAD on `COSIGN_IMAGE@sha256:57c0e93a…` returns **200**. | The prose may assert "still dead", **dated 2026-09-21T06:57Z**. The work phase re-runs both probes on the day of the PR body and updates the date. |
| #8417: one bare `$$` at `cloud-init-registry.yml:788` | **Two.** Line 191 is `PATH="…/bin$${PATH:+:$$PATH}"`. It renders (verified with `terraform` `templatefile()` on a scratch template) to `${PATH:+:$$PATH}`, which bash expands to `:<PID>PATH`. The inherited PATH was **never appended**, contrary to that block's own "APPEND" comment. Line 788 renders `cs$$_cs_rc.bk$$_bk_rc` verbatim, as the issue says. | Fix both. The guard's property is "no `$$` followed by an identifier-start or `(` on a non-comment line of any `templatefile()`-rendered file". A bare `$$` followed by anything else is a legitimate PID use. |
| "registry-luks-blocker-6929.sh … enrolled on open #7377" | **Cited, not enrolled.** #7377 names the script in prose (its tracker is #7340) and in one checkbox ("A live at-rest posture probe replaces the issue-state proxy"). No open issue carries a `soleur:followthrough` directive naming it. #7340 is **CLOSED**. | The sweep still says *correct it, don't annotate*: #7377's checkbox is a live re-enrolment path. The issue body states the enrolment fact correctly. |
| "encryption-posture-audit-2026-07-23.md is not on main at all" | **It is on main**, at `knowledge-base/engineering/architecture/encryption-posture-audit-2026-07-23.md`, with 8 `plaintext` lines. The registry row (line 39) already carries "⚠️ AS MEASURED 2026-07-23; NO LONGER TRUE — live LUKS since 2026-08-10", added by #7547. The other hits are about *other* volumes (`workspaces`, `git_data`, `inngest_redis`). | Drop it from the sweep. It is already corrected, and the remaining hits are not about the registry. The issue body records why, so the next reader does not re-add it. |
| `scheduled-zot-restart-loop.yml` line 221 | 0 hits for `plaintext\|unencrypted` on `origin/main`. | Drop it. |
| `registry-luks-recut-6929.md` 5 hits / blocker script 5 / inventory 1 | Confirmed with `plaintext\|unencrypted`. Recut runbook lines 365, 366, 376, 455, 655. Blocker script lines 16, 54, 57, 59, 95. `registry-zot-inventory.yml:6`. | These are carried into the sweep issue as content anchors (quoted phrases), not line numbers. |
| nfr-register.md is "a missing row" | Line 522 is the web-1 workspaces LUKS row. There is no `hcloud_volume.registry` at-rest row. | The sweep adds the row. |
| #8386 ledger flip shipped, so the tracker is closed | #8386 is **OPEN**. Its probe `registry-luks-live-8386.sh` **never returns 0 by design** (V7 is exit 5, "action required", because Better Stack source 2457081 is multi-tenant). #8408 enrols the same probe (`earliest=2026-09-22T00:00:00Z`). | This is not a two-trackers problem. The sweeper runs each open enrolment independently (the probe reads `SOLEUR_FT_EARLIEST` from the directive that gated it), and neither run auto-closes. Nothing to change. Neither issue takes a closing keyword in the PR body or a commit message. |
| #8036 is the only issue the cosign fix touches | **#8037 is OPEN**: "image signature verification has never succeeded (53/53 cosign_absent) — the enforce soak can never pass". 1a is its fix. | `Ref #8037`. It closes through a **new follow-through probe** (Phase 2.9.1) that requires a positive `IMAGE_VERIFY: ok` per host, not the absence of `cosign_absent`. Signature verification has **not run for seven weeks** (WARN mode, every deploy `cosign_absent`). After 1a it runs for the first time since then, and it may surface a *new* result class (`unsigned`, `wrong_identity`). That is a finding, not a regression. |
| (1b) the marker names "the identity it carries" | ci-deploy's own header records that `GHCR_READ_USER` is the founder's personal login, and that journald → Vector → Better Stack is **UNSCRUBBED**. | The marker emits a **closed vocabulary** (`same\|differs\|undecodable\|na` against `GHCR_READ_USER`), never the username. This is the file's own Form-B discipline. The deviation from the diagnosis comment's wording is stated in the PR body. |

## Research Insights

**Premise Validation (Phase 0.6).**

- Issue states, re-checked 2026-09-21 with `gh issue view`:
  - #8036, #8037, #8417, #8408, #8449, #8278, #8386, #7377, #6122 and #6073 are OPEN.
  - #8361, #7340, #7287, #7247 and #7248 are CLOSED.
- All the cited file paths exist on `origin/main` (`71e7585ea`).
- The #8417 bug is still present, and a second instance was found.
- The #8278 premise holds. No directive enrols `zot-log-channel-7440.sh`: the five issues that
  mention it (#8278, #7556, #7456, #7530, #7959) have zero `script=…zot-log-channel-7440` hits.
- The `feat-zot-primary-write-path` branch carries a draft ADR-167 ("write path stays
  dual-push"). It is Proposed, not Accepted, and it is scoped as a *hold while #7247 is open*.
  **#7247 is CLOSED**, so its own hold condition has lapsed. ADR-167 is **unclaimed on main**
  (ADR-168 and ADR-169 exist). The branch is not adopted.
- ADR corpus against the proposed mechanisms:
  - ADR-087 (Design B′) prescribes mounting the host docker config for the `.sig` fetch. 1a keeps
    that mount and changes only how the verifier **image** is obtained. That is an amendment to
    ADR-087, not a reversal.
  - ADR-096 names GHCR as the interim break-glass path, retiring at Phase 5, and its 2026-07-30
    amendment retracts the GHCR fallback.
  - ADR-088 arm-b: an App installation token cannot pull private repo-linked GHCR packages.
  - ADR-169: CI reads GHCR to restore zot.
  - ADR-185: registry user_data headroom is `stored < cap`, with no 20 kB floor.
  - ADR-190: the replace dispatcher.

**Property List (Phase 0.6b).**

- P1 — A deploy's cosign verifier-image pull presents **no** credential. The image is public.
- P2 — The `.sig` fetch still authenticates to the registry the digest was pulled from (zot
  auths entry, ADR-087 unchanged).
- P3 — One deploy self-reports, with no host access, which docker config(s) carry a `ghcr.io`
  auths entry, whether a creds store or helper is set, and whether that entry's user matches the
  current read user. No credential or username is emitted.
- P4 — No `templatefile()`-rendered file contains a `$$` that bash would read as PID-plus-literal
  where a variable was meant.
- P5 — `store_probe_rc` carries the two exit codes: `cs<rc|na>.bk<rc|na>`.
- P6 — A standing alert pages when the registry heartbeat's **trusted head** does not say
  `store_luks=yes`, or reports an escrow failure.
- P7 — zot cannot start, **on any container start** (first boot, docker's restart policy at daemon
  start, the NIC-guard `docker restart zot`), unless `/var/lib/zot` is the decrypted LUKS
  filesystem.
- P8 — At most daily, the registry proves the Doppler-held passphrase still opens the header and
  that the header UUID resolves. The result is visible off-box and can be alerted on.
- P9 — An operator can obtain the dedicated Inngest host's state verdict from a phone. That means
  no checkout and no Doppler.
- P10 — #8037's closure is automated. It needs a positive per-host `IMAGE_VERIFY: ok` after
  delivery.

**Cut List (Phase 0.6b).**

- *"Mint a new GHCR PAT"* would restore a working credential. It is cut for 1a, because P1 needs no
  credential. It is also not a legitimate option for 1c: hr-github-app-auth-not-pat, and
  ADR-088 arm-b says only a personal credential can pull.
- *"Alarm on `relogin_failed`"* would signal the symptom. It is cut, as #8036 §5 argues: 89/week
  of a known state is noise. The single-path-degradation page already exists through the zot
  health and `image_pull_failed` channels.
- *"`docker logout ghcr.io` on relogin failure"* would remove the stale entry. It is cut because
  it is 1c territory (it changes GHCR-fallback semantics), and P1 is fully bought by the isolated
  pull.
- *"A systemd unit that owns zot with `ExecStartPre=` findmnt"* for P7 would replace docker's
  restart-policy ownership. The NIC guard (`docker restart zot`), the recut, the inventory and the
  restart-loop tooling all address the container by name, and a systemd owner rewires all of them.
  It is cut in favour of the sentinel bind (below), which docker enforces on **every** start with
  zero ownership change.
- *"`docker.service` `Requires=registry-luks-open.service`"* for P7 would block docker on a failed
  open. It is cut: it gates only the daemon start, not `docker restart zot`, and it also takes
  down the NIC-guard self-heal path.
- *"A separate escrow emitter + Better Stack source"* for P8 is cut. The registry host ships only
  by direct POST from the heartbeat, which already runs under
  `doppler run --project soleur-registry`, so `REGISTRY_LUKS_KEY` is already in its env. The
  heartbeat reads a daily state file instead.
- *"A second alert for escrow"* is cut. One exploration's predicate covers P6 and P8, and it costs
  two `-target=` lines instead of four.

**Plan-review cuts (2026-09-21).** Each cut is recorded with the reviewer who proposed it.

- *`_ensure_cosign_image` pre-pull + `--pull=never` + `IMAGE_VERIFY_PREP` vocabulary* is replaced
  by a one-line `DOCKER_CONFIG` prefix on the verify run (simplicity). The pre-pull also had a
  `VERIFIED_REF` stdout-corruption P0 (Kieran), which the cut dissolves. The pruned image made
  its `present` arm dead code anyway (CTO).
- *1b `user_vs_read`* is cut, because it decoded a live credential in shell and neither answer
  changes 1a or 1c (DHH, simplicity). It is recorded as Taste in `decision-challenges.md`.
- *`registry-probe-rc-8417.sh`* is cut in favour of ship's post-merge verification (DHH,
  simplicity).
- *A new `sigstoreCosignImage` C4 node* was cut (DHH, simplicity). The deepen review then moved
  it to a second `hetzner -> ghcr` edge: the live dependency is ghcr.io, not Sigstore.
- *The `position()` Python evaluator* is replaced by structural assertions plus recorded live
  probes (DHH).
- *The escrow vocabulary* goes from nine tokens to five (DHH, simplicity). *The torn-write kill
  test* becomes a static check plus an `mv`-fails stub (DHH, Kieran).

**Plan-review rejections.** Each is recorded with its reason.

- *Cut the CONCUR gate before the sweep issue* (DHH): rejected, because the operator's brief
  mandates it.
- *Cut the #8037 probe* (DHH): rejected. #8037's closure depends on the first deploy that runs
  the new script, whose timing relative to the `deploy_pipeline_fix` apply is not controlled.
  That is a time-gated closure, so the follow-through convention requires automation.
  Simplicity concurred.
- *Drop the templatefile guard floor* (simplicity): rejected. Set identity is measured against
  the same derivation it would guard, so only an absolute floor catches a shrinking derivation.
- *Split into two PRs* (CTO): not auto-applied, because it changes the operator's stated shape.
  It is recorded as a User-Challenge in `decision-challenges.md`. The in-PR mitigation, a
  ≥2-row alert grace, is applied.

**Relevant file paths (content anchors).**

- `apps/web-platform/infra/ci-deploy.sh`:
  - `readonly COSIGN_IMAGE=` (the public Sigstore image, pinned `@sha256:57c0e93a…`, v3.1.1)
  - `export DOCKER_CONFIG="$DEPLOY_DOCKER_CONFIG_DIR"` (`/mnt/data/deploy-docker`, a *persistent*
    ReadWritePath, which is why a pre-revocation inline `ghcr.io` entry can survive every later
    failed login)
  - `ghcr_prelude_and_login()`
  - `refetch_ghcr_and_relogin` (`printf relogin_failed`)
  - `verify_image_signature()`: the `docker run --rm --network host -v "$GHCR_DOCKER_CONFIG:/root/.docker/config.json:ro"`
    line, and the classifier arm `Unable to find image|manifest unknown|pull access denied|no such image` → `cosign_absent`
- `apps/web-platform/infra/ci-deploy.test.sh`: the docker mock's `run`/`verify` handler
  (`MOCK_COSIGN_ARGS_FILE`, `COSIGN_VERIFY_ARGS:`), `assert_bprime_cosign_invocation`, T-ZOT-1 and
  T-ZOT-2 (the cosign args follow the registry), and the "#6122 Phase 4: cosign continuity" block.
- `apps/web-platform/infra/server.tf`: `terraform_data.deploy_pipeline_fix` `triggers_replace`
  hashes `ci-deploy.sh`.
- `apps/web-platform/infra/cloud-init-registry.yml`:
  - `PATH="/usr/local/sbin:…/bin$${PATH:+:$$PATH}"` (heartbeat preamble)
  - `STORE_PROBE_RC="cs$$_cs_rc.bk$$_bk_rc"`
  - the heartbeat `LINE="SOLEUR_ZOT_DISK …"` assembly (`store_probe_rc=… store_luks=… host=… zot_last_err=…`)
  - `*/5 * * * * root … doppler run --project soleur-registry --config prd -- /usr/local/bin/zot-disk-heartbeat.sh`
  - the `registry-luks-open.sh` write_files block and `registry-luks-open.service`
  - the runcmd LUKS mount block (`mountpoint -q /var/lib/zot || mount /dev/mapper/registry /var/lib/zot`)
  - the zot launch (`findmnt … | grep -qx /dev/mapper/registry || { … FATAL …; exit 1; }` then
    `docker run -d --name zot --restart unless-stopped`)
  - the NIC-guard self-heal (`docker restart zot`)
- `apps/web-platform/infra/zot-registry.tf`: `registry_rationale_strip`, and the `templatefile()`
  of `cloud-init-registry.yml`.
- `.github/workflows/registry-host-replace-dispatch.yml`: `on.push.paths` includes
  `cloud-init-registry.yml`, and a delta gate compares against the last successful run, so a
  comment-only edit (stripped) is byte-identical and does not fire.
- `apps/web-platform/infra/betterstack-logs-alerts.tf`: the `inngest_luks_wrong_volume` locals,
  `logtail_exploration` and `logtail_exploration_alert` (the template for (a)).
- `.github/workflows/apply-web-platform-infra.yml`:
  - the `-target=logtail_exploration.inngest_luks_wrong_volume` and
    `-target=logtail_exploration_alert.inngest_luks_wrong_volume` lines
  - size **476,841 B**, against the self-imposed 490,000 B limit and GitHub's 512,000 B limit
- `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh`: the suite shape (a)
  copies.
- `apps/web-platform/infra/luks-monitor.sh`: the workspaces sibling's escrow
  (`cryptsetup luksOpen --test-passphrase --key-file -`) and header-UUID read
  (`cryptsetup luksUUID`), plus `luks-monitor.test.sh`.
- `scripts/lib/zot-telemetry-parse.sh`: `zot_envelope_anchor` (`"raw":"{\"message\":\"SOLEUR_ZOT_DISK `)
  and `zot_trusted_region` (cut at ` zot_last_err=`).
- `scripts/followthroughs/registry-luks-live-8386.sh`: exit contract 0/1/2/3/5, and "never
  returns 0".
- `scripts/followthroughs/zot-login-gate-erofs-repaired-6565.sh`: the per-host `_MACHINE_ID`
  positive-OK soak shape that the #8037 probe copies.
- `scripts/inngest-host-state.sh`:
  - needs only `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}`
  - `--since <N>[hmd]` is validated by the script
  - exit codes 0/2/3/4/5/6/78
  - no workflow wraps it (`git grep -ln inngest-host-state -- .github` is empty)
  - the same three secrets already exist in eight workflows, including
    `scheduled-followthrough-sweeper.yml` and `scheduled-inngest-health.yml`
- `knowledge-base/engineering/architecture/diagrams/model.c4`:
  - `ghcr` ("PRIVATE GHCR registry … DEAD AS A FALLBACK")
  - `projectZot` (the precedent: a *live public* ghcr.io dependency that hid behind the *dead
    private* one)
  - `sigstore` ("NO live sigstore call at verify time")
  - `hetzner -> ghcr` ("DEAD EDGE")
- `views.c4` includes `projectZot` in two views.

**Institutional learnings applied.**

- `2026-07-15-silent-fallback-masked-a-dead-primary-for-14-days.md`: a positive OK line per host,
  never the "absence of failure".
- `2026-07-24-guest-luks-store-must-gate-consumer-on-mount-and-guard-suite-must-pin-fail-loud-semantics.md`:
  the launch gate must be fail-loud, and the suite must pin the exit, not a token.
- `2026-07-04-cosign-verify-phase0-falsifies-plan-flags-and-userdata-cap-relocation.md`: probe the capability before writing
  shell. `--offline` still does a registry round-trip for the `.sig`, which is why P2's mount
  stays.
- `2026-07-06-ghcr-app-token-cannot-pull-and-oidc-needs-native-identity-source.md`: 1c has no zero-touch credential option.
- `2026-08-09-the-shell-capture-trap-recurred-three-times-and-finally-earned-a-lint.md`: any new `x=$(grep …)` under `set -e` needs an explicit
  rc capture, and `lint-shell-capture-exit.py --baseline` must not grow.
- `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md`: the #8037
  probe keys on the `SYSLOG_IDENTIFIER` field, not on a bare substring.
- `2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md`: the PR body must not contain the word
  "closes" near #8037, #8408, #8417 or #8036 in prose.
- The cloud-init-inngest.yml comment block (the #7695 `$$VAR` / `$$((…))` precedent): the bare-`$$`
  class has already bitten another host once.

<!-- lint-infra-ignore start: quotes Docker documentation; prescribes no human step -->
**External research.** Skipped. The codebase has strong local precedents for every mechanism. One
external fact is load-bearing, and the work phase verifies it on a real daemon (task 3.2.1): a
`--mount type=bind` source that does not exist is an error, and it is never auto-created the way
`-v` does. Docker docs, bind mounts: *"If you use `--mount` to bind-mount a file or directory
that does not yet exist on the Docker host, Docker does not automatically create it for you, but
generates an error."* <!-- verified: 2026-09-21 source: https://docs.docker.com/engine/storage/bind-mounts/ -->
That covers *create*. Whether a container **restart** fails when the source has disappeared is
**not** documented. The work phase measures it before the gate is trusted.
<!-- lint-infra-ignore end -->

## Hypotheses

The network-outage trigger words `denied`, `401` and `timeout` appear in the brief, but no
SSH/connectivity question is being diagnosed. The registry denial is an **authentication**
outcome, measured at L7 with credentials held constant. The L3 path to ghcr.io is proven healthy
by the anonymous 200 from the same egress class (host `--network host` unrestricted egress,
ADR-087). No firewall/sshd hypothesis applies.

For §6 of the #8036 diagnosis, which config presents credentials, the leading hypothesis is:

- The CLI sends the auth from `$DOCKER_CONFIG/config.json` = `/mnt/data/deploy-docker/config.json`
  for the implicit `docker run` pull.
- `/mnt/data` persists across deploys.
- `docker login` does not remove an entry on failure.

So an inline `ghcr.io` entry written before the revocation is presented on every deploy. 1b
confirms or refutes this in one deploy. 1a is correct under every hypothesis, because the
isolated config presents nothing.

## Implementation Phases

Each phase is one commit. Never commit while the test battery is running.

### Phase 1 — #8036 1a: anonymous cosign verifier-image pull (`ci-deploy.sh`)

[Revised after plan review. The simplicity reviewer found a one-line mechanism that buys P1.]

1. In `verify_image_signature()`, run the verify `docker run` with `DOCKER_CONFIG="$anon_dir"`
   prefixed to that one command.
   - `anon_dir="$(mktemp -d 2>/dev/null)" || anon_dir=""` (no bare capture). **Write
     `{"auths":{}}` into it** rather than leaving it empty, because a missing `config.json` lets
     the CLI fall back to legacy `~/.dockercfg` (security review). Prefix the run with
     `env -u DOCKER_AUTH_CONFIG`, which newer CLIs honour regardless of `DOCKER_CONFIG`. `/tmp`
     is `PrivateTmp=true` under `webhook.service` (`webhook.service:38`), so the path cannot be
     attacker-influenced.
   - The docker **CLI** reads auths for the implicit `COSIGN_IMAGE` pull from its own
     `DOCKER_CONFIG`, so that pull becomes anonymous. That is P1.
   - `-v "$GHCR_DOCKER_CONFIG:/root/.docker/config.json:ro"` is a **host path** bind, resolved
     independently of the CLI's `DOCKER_CONFIG`. The `.sig` fetch inside the container still
     authenticates to zot, so P2 holds unchanged.
   - `rm -rf "$anon_dir"` on every exit arm of the function. The existing `rm -f "$err"` sites
     are the pattern.
   - Fallback when `mktemp -d` fails (practically only on a full disk): `rm -rf` then
     `mkdir -m 700` of `"$DEPLOY_DOCKER_CONFIG_DIR/anon-cosign"`, **recreated every deploy**, and
     **never** `$DOCKER_CONFIG` itself. Then write the same `{"auths":{}}`.
   - A **content check** runs before use: the dir is absolute, exists, and its `config.json` is
     exactly `{"auths":{}}`. If any of that fails, skip the prefix and log
     `IMAGE_VERIFY_PREP: anon_config=unavailable` through `logger` (never stdout), a logged
     fail-open to today's behaviour.
   - The failure is forced through a named seam, `SOLEUR_COSIGN_ANON_DIR_FORCE_FAIL=1`, read
     **only** by this function. `ci-deploy.sh` calls `mktemp` 21 times, so a `mktemp` stub would
     break unrelated paths (test review).
   - Guard `rm -rf` with `[ -n "$anon_dir" ]`.
2. **Measured, and not a regression:** `ci-deploy.sh` runs `docker image prune -af` (the
   `docker image prune -af 200>&-` line) **before** `verify_image_signature`. The cosign image
   has no live container, so it is pruned and re-pulled on **every** deploy. It always has been,
   including before the revocation. The anonymous pull therefore runs once per deploy. The
   ENFORCE flip must account for this dependency on public ghcr.io (see the ADR-087 amendment),
   and it is recorded there rather than engineered around here.
3. **Do not change** the `-v "$GHCR_DOCKER_CONFIG:…:ro"` mount (P2), the classifier, or any
   existing `logger` string. #6565's open follow-through and existing runbooks grep those strings.
4. Tests, in `apps/web-platform/infra/ci-deploy.test.sh`, extending the docker mock's
   `run`/`verify` handler so it also records `DOCKER_CONFIG=<value> HAS_CONFIG_JSON=<0|1>` at
   verify time:
   - **T-1a-1** (P1): at verify time, the mock records that `DOCKER_CONFIG` is **non-empty,
     absolute, an existing directory** other than the deploy config dir, that its `config.json`
     equals `{"auths":{}}`, and that `DOCKER_AUTH_CONFIG` is unset. A `DOCKER_CONFIG=""`
     regression must fail this case (test review).
   - **T-1a-2** (P2): the verify argv still carries `-v <deploy config.json>:/root/.docker/config.json:ro`.
     Extend `assert_bprime_cosign invocation` and do not replace its existing asserts.
   - **T-1a-3**, the P1 property rather than its spelling: arm a sentinel inline `ghcr.io` auths
     entry (`canary-ghcr-auth-5d2b`) in the deploy config, and set `DOCKER_AUTH_CONFIG` to a
     canary. The **mock** greps its own `DOCKER_CONFIG` directory **inside the mock, before the
     `rm -rf`**. Neither canary may be visible.
   - **T-1a-4**: the anonymous dir is removed after both the verify-ok and the verify-fail arms.
   - **T-1a-5**: with `SOLEUR_COSIGN_ANON_DIR_FORCE_FAIL=1`, the fallback dir is recreated, is
     not `$DOCKER_CONFIG`, and holds `{"auths":{}}`. A pre-seeded fallback dir holding a real
     `config.json` is wiped and recreated. When the content check fails, the case expects
     `anon_config=unavailable` in the logger output and `VERIFIED_REF` unchanged.
   - **T-1a-6**: `VERIFIED_REF` is exactly the repo digest. No new stdout reaches the capture.
   - Raise `CI_DEPLOY_ASSERT_FLOOR` (305 today) by the number of new assertions in the same edit.
   - The existing WARN/ENFORCE cosign cases stay green unchanged.
5. The ENFORCE decision stays out of scope. `IMAGE_VERIFY_MODE:-warn` is asserted unchanged by
   the existing test.

### Phase 2 — #8036 1b: `SOLEUR_DEPLOY_GHCR_CONFIG` marker (`ci-deploy.sh`)

[Revised after plan review. DHH and simplicity dropped `user_vs_read`: it decoded a live
credential in shell, and neither of its answers changes 1a or 1c. Kieran found a `set -e`
abort path.]

1. At the end of `ghcr_prelude_and_login()`, after both login attempts, emit one line:

   ```
   SOLEUR_DEPLOY_GHCR_CONFIG effective=deploy_cfg
     deploy_cfg=<absent|unreadable|unparseable|present> deploy_ghcr_auth=<inline|none|na> deploy_creds_store=<none|set|na> deploy_ghcr_helper=<none|set|na>
     home_cfg=<…> home_ghcr_auth=<…> home_creds_store=<…> home_ghcr_helper=<…>
     root_cfg=<…> root_ghcr_auth=<…> root_creds_store=<…> root_ghcr_helper=<…>
   ```

   The emitted line is a single line. It is wrapped here only for readability.
   - `deploy_cfg` is `$DOCKER_CONFIG/config.json`. It is the config the CLI presents, and the
     `effective=` token says so.
   - `home_cfg` is `$HOME/.docker/config.json`, the pre-#6565 location.
   - `root_cfg` is `/root/.docker/config.json`. It stays in: a measured `unreadable` from the
     deploy user is a direct answer to the "root-vs-deploy split" hypothesis in §6. It costs one
     token.
2. Every value is a **hardcoded token** chosen from `jq -e` exit statuses
   (`jq -e '.auths["ghcr.io"].auth // empty'` means inline, then `.credsStore`, then
   `.credHelpers["ghcr.io"]`).
   - Output goes to `>/dev/null`. **No config content reaches a variable, `printf` or `logger`.**
     This is Form B, the same discipline as `_login_kw`.
   - Every probe is `rc=0; jq -e … >/dev/null 2>&1 || rc=$?`. There is no bare capture under
     `set -euo pipefail`. An unreadable file or unparseable JSON maps to a token, never to an
     abort. When `jq` is absent, every token is `na`.
3. Emit to journald only (`logger -t "$LOG_TAG"`). There is **no Sentry event**, for the same
   volume rationale as the prelude lines.
4. Tests:
   - **T-1b-1**: the fixture matrix is absent, unreadable, unparseable JSON, inline entry,
     `credsStore` set, `credHelpers["ghcr.io"]` set, and no `ghcr.io` key. Each case has an exact
     expected token set.
     - `HOME` is a temp directory.
     - The root path comes through a test-only seam, `SOLEUR_GHCR_CONFIG_ROOT_PATH`, mirroring
       `SOLEUR_GHCR_READ_FILE`.
     - "Unreadable" is a **directory** at the config path, not a mode-000 file, so the result is
       the same when the suite runs as root (test review).
   - **T-1b-2**, the leak canary: fixture auth `Y2FuYXJ5dXNlci03ZjNhOmNhbmFyeXRvay05YzFl`, which
     is base64 of a canary user and token. Neither that string nor its decoded parts appear in
     the captured logger output or on stderr.
   - **T-1b-3**: exactly one `SOLEUR_DEPLOY_GHCR_CONFIG` line per deploy, on the relogin_failed
     path **and** on the skipped path. The unparseable and unreadable fixtures do **not** abort
     the deploy: the deploy completes and exits 0.

### Phase 3 — #8036 1c: recommendation (PR body only, no code)

The recommendation goes in the PR body under `## GHCR's fate (1c) — recommendation, operator decides`:

- **Recommend: retire the host-side GHCR read path.** That means the prelude `docker login ghcr.io`,
  `refetch_ghcr_and_relogin`, and `_ghcr_pull_or_recover`'s GHCR leg. It should happen in a
  follow-up PR, and **keep CI's GHCR write + read** (the dual-push stays, and ADR-169's restore
  path reads GHCR).
- Rationale:
  1. A working host credential can only be a personal PAT (ADR-088 arm-b). That contradicts
     hr-github-app-auth-not-pat.
  2. `model.c4` already declares `hetzner -> ghcr` DEAD, and ADR-096's 2026-07-30 amendment made
     zot the sole pull path.
  3. The real second tier today is `_try_local_cache_reload` plus the CI restore (ADR-169). Those
     are minutes, not a mid-pull fallback, and that is already documented.
  4. The current "third state" costs 89 journald lines/week, plus a ~2×45 s Doppler re-fetch
     budget per deploy, for zero serving capacity.
- **What re-opens it:** a yes from GitHub on #6073 (App-token pull). The minter (ADR-088) would
  then re-establish a legitimate host path.
- **Recorded, not adopted:** the stale ADR-167 draft was a *write-path* hold, and its #7247
  condition has lapsed. It does not bear on the host read path.
- #8036 stays **open** (`Ref`) until the operator rules. A PR comment on #8036 carries the same
  text. Filing the retirement is the operator's decision, so no issue is pre-filed.

### Phase 4 — #8417: fix both bare-`$$` sites + a template-wide guard

1. `cloud-init-registry.yml` heartbeat preamble: change `$${PATH:+:$$PATH}` to
   `$${PATH:+:$${PATH}}`.
   - **Behavioural consequence, stated in the PR:** the inherited PATH is now actually appended
     (after the literal list, so the literal list still wins). This matches the block's own
     "APPEND, never prepend" comment, and it restores the designed behaviour.
   - **Measured:** `zot-disk-heartbeat-redaction.test.sh` substitutes this PATH line **whole**
     (`sed -i "s|^PATH=.*|…|"`), so its behavioural cases never run the shipped expansion. Its
     "the SHIPPED template prepends trusted dirs" assert `grep -qF`s the **defective spelling**
     `$${PATH:+:$$PATH}`, so it pins the bug. Replace that pin in the same commit with an
     **evaluation**:
     - render the shipped line the way Terraform does (`$${` → `${`, and a bare `$$` left
       verbatim)
     - `eval` it under `PATH=/inherited/dir`
     - assert the result starts with `/usr/local/sbin:` (the prepend property is kept), ends
       with `:/inherited/dir`, and contains no `[0-9]+PATH` token
2. `STORE_PROBE_RC="cs$$_cs_rc.bk$$_bk_rc"` → `STORE_PROBE_RC="cs$${_cs_rc}.bk$${_bk_rc}"`.
   **Also** set `_bk_rc=0` immediately before the `blkid` call inside its `/dev/*` arm.
   - Kieran measured this. `_bk_rc=na` is only overwritten on **failure** (`… || _bk_rc=$?`).
     `_cs_rc` is reset to 0 before its call, but `_bk_rc` is not. So a healthy LUKS host would
     report `cs0.bkna`, the same token as "blkid never ran".
   - After the reset, `bkna` means "not run" and `bk0` means "ran OK". That is the decoding the
     `v4b_newest_indeterminate` verdict text assumes. The PR states this as a behaviour change.
3. The guard is a new `apps/web-platform/infra/templatefile-bare-dollar-guard.test.sh`. The
   assembly spans hosts. It needs:
   - (i) **dispatch**: derive the file set from `templatefile(` call sites in
     `apps/web-platform/infra/**/*.tf`, resolving `${path.module}` against **each `.tf` file's own
     directory**. `modules/git-data-userdata/main.tf` renders `cloud-init-git-data.yml` through
     `${path.module}/../../`, which a top-level-only glob misses (test review, verified).
   - (ii) strip comment lines with the `registry_rationale_strip` regex (`^[ \t]*#…`).
   - (iii) fail on `\$\$[A-Za-z_(]`.
   - (iv) a floor of `files_scanned >= 8` (today's measured count, including the git-data module)
     **plus** set identity against the derived list. The floor uses the shape
     `guard-vacuity-floor` recognises, not an ad-hoc `fail`. The floor catches a derivation that silently shrinks, which identity
     alone cannot see, because identity is measured against the same derivation.
   - (v) a **rendered-shape** assert for `store_probe_rc`: render the assignment line and execute
     it under both `_cs_rc=127 _bk_rc=na` and `_cs_rc=0 _bk_rc=0`. Expect `cs127.bkna` and
     `cs0.bk0` exactly, and both must match `^cs([0-9]+|na)\.bk([0-9]+|na)$`.
   - Registration: add a `run: bash` step in `infra-validation.yml` `deploy-script-tests`, which
     is what `run-registered-suites.sh` reads, and check it with `scripts/lint-orphan-test-suites.sh`.
4a. **PATH hardening (security review).** Once the inherited PATH is actually appended, a command
   absent from the literal directories would resolve through a PATH the Doppler config can set.
   Add a guard case: every external command the heartbeat invokes resolves inside the literal
   `/usr/local/sbin:…:/bin` list on the target image. The set is derived from the rendered
   script's command words, not hand-listed, and it asserts the literal list resolves each one.
4. **Delivery, stated in the PR:** this is a non-comment edit to `cloud-init-registry.yml`, so
   the merge fires `registry-host-replace-dispatch.yml` (preflight-gated).
   - It is **not** "deployed" until a post-merge SOLEUR_ZOT_DISK row on a **new** `boot_id`
     reads `store_probe_rc=cs0.bk0`.
   - If the preflight refuses, the fix is **dormant until the next replace**, and the PR comment
     says so, with the refusal artifact link.
   - Closure of #8417 is the ship post-merge verification step, not a new follow-through probe
     (cut in plan review). It queries `scripts/betterstack-query.sh --since 2h --grep SOLEUR_ZOT_DISK`
     for new-boot rows, comments the observed tokens on #8417, and closes it only when
     `cs0.bk0` is observed on the new boot.

### Phase 5 — #8408 (a): standing alert `registry_store_not_luks`

1. `betterstack-logs-alerts.tf` gets:
   - `local.registry_store_not_luks_sql`
   - `logtail_exploration.registry_store_not_luks`
   - `logtail_exploration_alert.registry_store_not_luks`

   Mirror `inngest_luks_wrong_volume`, with `values = [local.vector_prd_source_id]`. That
   source is **verified** to be the registry heartbeat's source: `zot-registry.tf`'s
   `betterstack_logs_ingest_url` is `s2457081`, and `vector_prd_source_id = "2457081"`.
2. The predicate uses `m = JSONExtractString(raw, 'message')`, the sibling's exact column form.
   Kieran confirmed there is no bare `msg` column. The **trusted head** is everything before
   ` zot_last_err=`. The alert fires on rows where
   `startsWith(raw, '{"message":"SOLEUR_ZOT_DISK ')`, which is the direct-POST envelope that
   `zot_envelope_anchor` uses, so a web-host journald line quoting the marker cannot match
   (security review). The row must also satisfy `position(m, 'SOLEUR_ZOT_DISK ') = 1`, AND
   either:
   - (A) the head lacks `store_luks=yes ` (with the trailing space, and only counting a position
     before `position(m, ' zot_last_err=')`), OR
   - (B) the head carries `store_escrow=` AND does not carry `store_escrow=ok ` (both before the
     tail).

   Arm (B) is the plan-review fix. CTO, DHH and simplicity all found that `fail`-only matching
   leaves `stale`, `none` and `indeterminate` silent, which is exactly how a dead escrow job
   would rot. Rows that predate delivery carry no `store_escrow=` at all, so (B) cannot fire on
   them. That lets the alert apply at merge, before the replace, without paging.
3. Alert settings:
   - `check_period = 300`
   - `query_period = 900` (two `*/5` heartbeats)
   - `value = 1` with `operator = "higher_than"`, so it fires on **≥2** matching rows in the
     window. This is the CTO's replace-window grace: a single transient row during a replace
     does not page, and a persistent condition pages within 10 minutes.
   - `on_missing_data = "treat_as_zero"`. Silence is the existing heartbeat-liveness alarm's
     job, and a comment says so.
   - `paused = false`
   - `escalation_target` exactly as the sibling has it
4. **LIVE-PROBE the SQL before merge** through `scripts/betterstack-query.sh`'s warehouse path
   (24 h window). Record the three counts in the tf comment, as the sibling does:
   - (i) as written → 0 rows
   - (ii) positive control: `store_luks=yes ` replaced by `store_luks=nope ` → N > 0
   - (iii) arm-(B) control: `store_escrow=` replaced by `store_luks=` in the arm-(B) presence
     test → N > 0, so arm (B) is live SQL, not dead syntax
5. `.github/workflows/apply-web-platform-infra.yml`: add the two `-target=` lines next to the
   sibling pair.
   - They go inside the push-triggered `apply` job. This is verified: the sibling pair sits in
     `apply:`, which runs on `push`. So the merge applies them. Do not put them in a
     `workflow_dispatch`-only job.
   - **Re-measure the size** with `wc -c` before and after (it is 476,841 B today), and record
     both. It must stay < 490,000 B.
6. The suite `apps/web-platform/test/infra/registry-store-not-luks-alert.test.sh` copies
   `inngest-luks-wrong-volume-alert.test.sh`'s shape. It makes **structural** assertions over the
   SQL string parsed out of the `.tf` local: the `SOLEUR_ZOT_DISK ` anchor, the literal
   `'store_luks=yes '` with its trailing space, the ordering conjunct against `' zot_last_err='`,
   the arm-(B) presence and ok literals, `paused = false`, `query_period = 900`, `value = 1`,
   `operator = "higher_than"`, the envelope `startsWith` conjunct, and both `-target=` lines.
   The ordering conjunct is asserted **per arm**: exactly one `' zot_last_err='` reference in
   arm (A) and one in arm (B). Dropping it from one arm is visible even though the other arm
   still carries it (test review). The re-implemented `position()` evaluator was cut in plan review:
   the live-probe controls exercise the real engine, and a port can drift from it.

### Phase 6 — #8408 (b): reboot-surviving launch gate (sentinel bind) + its recovery arm

1. In the runcmd LUKS mount block, after the mount, **and before the runcmd `docker run -d --name zot`**,
   create the sentinel if absent. It is created only when `findmnt -no SOURCE /var/lib/zot` is
   exactly `/dev/mapper/registry`.
   - The file is `/var/lib/zot/.soleur-luks-sentinel`: zero bytes, root:root, mode 0444.
   - The sentinel lives **inside** the LUKS filesystem, so it is visible **only** through an
     opened mapper. Its presence at `/var/lib/zot` is a binding proof **against the failure mode**
     (a closed mapper). It is not proof against an adversary, or an `rsync -a` of the store to
     the root disk, which would copy the sentinel along (security review). The recut runbook
     gains one line: exclude `.soleur-luks-sentinel` from any store copy. A second bind of
     `/dev/mapper/registry` was considered and is not adopted: a device-node bind proves the
     mapper exists, which is the weaker name check #8408 rejected.
   - zot already tolerates root dotfiles (the CTO points to `.resize-result`).
   - On the preserved volume, the first boot after this change writes it.
2. The zot `docker run` gains
   `--mount type=bind,source=/var/lib/zot/.soleur-luks-sentinel,target=/run/soleur-luks-sentinel,readonly`.
   Docker refuses a `--mount` bind whose source is missing, where `-v` would create it. So after
   a reboot where the mapper stayed closed, **zot fails to start** instead of serving the
   root-disk directory. Docker does not retry a start that failed at daemon boot.
3. **The recovery arm (advisor finding, in the same commit).**
   - The NIC guard runs every 5 minutes (`2-59/5`). Today it restarts zot **only** on the branch
     where `mountpoint -q /var/lib/zot` was false.
   - On the late-volume path (the `nofail` fstab mount lands after docker has started), the
     guard sees the mount present and never touches zot, so the gate would become a
     **permanent** outage.
   - Add an arm: mount present **and** `docker inspect -f '{{.State.Running}}' zot` is not `true`
     **and** the sentinel is present, then `docker start zot`.
   - This arm and the existing remount-then-`docker restart` arm are **mutually exclusive on one
     tick**: an `elif` on the same `mountpoint` branch (architecture review).
   - The outcome rides the **POSTed** `SOLEUR_PRIVATE_NIC` `LINE` as a new field
     `zot_start_action=<none|start_ok|start_failed>`, placed before ` zot_last_err=`. A stderr
     echo would never leave the host: the registry runs no Vector, and only the direct POSTs ship
     (observability review, verified).
   - The worst case of the gate is then **≤5 min of fail-closed downtime**, stated in the PR, and
     never a silent empty-store serve.
4. Keep the first-boot `findmnt … || exit 1` gate. It is defence in depth.
5. `registry-luks-open.sh` stays fail-open on its arms: device absent, not `crypto_LUKS`, and a
   `luksOpen` failure falling through `mount … || true`. The **consumer** is now fail-closed.
   - Record which arm fired as one hardcoded token (`already_open|opened|dev_absent|not_luks|key_empty|open_failed`)
     in `/run/soleur-registry/luks-open.arm`, which is tmpfs and per boot.
   - The heartbeat reads it into the trusted head as `luks_open_arm=<token>`, or `none` when the
     file is absent. Boot-journald stderr is not visible off-box, so the heartbeat is the only
     channel that is.
6. Suite: `apps/web-platform/infra/registry-luks-launch-gate.test.sh`.
   - **Static assertions**:
     - The zot `docker run` carries `--mount type=bind,source=/var/lib/zot/.soleur-luks-sentinel`
       and never `-v` for it.
     - Exactly **one** `docker run … --name zot` site (set identity).
     - The sentinel write is inside the `findmnt` conjunction and **precedes** the runcmd
       `docker run`.
     - The NIC-guard recovery arm exists, and it is keyed on `.State.Running` plus the sentinel.
   - **Behavioural NIC-guard arm**: execute the extracted NIC-guard block with stubbed
     `mountpoint` and `docker`. It must call `docker start zot` **iff** the store is mounted, zot
     is not running, and the sentinel is present, and it must never call it together with
     `docker restart` on the same tick.
   - **Behavioural, docker-gated, fail-closed without a daemon.** It uses an image already
     present on the runner (no network pull), unique container names, and cleanup on `EXIT`. It exits non-zero with
     `NO-DOCKER`, the same way `zot-config-deadlines.test.sh` does. This is identical on main,
     not a defect, and CI has docker. The sequence:
     - create a container with `--mount type=bind` of a temp file, then stop it
     - delete the file, then `docker start` **fails** and `docker restart` **fails**
     - recreate the file, then `docker start` **succeeds** (the recovery leg)
     - negative control: the same sequence with `-v` in place of `--mount`, where `start`
       **succeeds** after deletion. This proves the suite can tell the two mount kinds apart.

### Phase 7 — #8408 (c): daily escrow re-test surfaced on the heartbeat

1. A new write_files script `/usr/local/bin/registry-luks-escrow.sh` runs from a new cron.d line
   (`19 3 * * * root … doppler run --project soleur-registry --config prd --only-secrets REGISTRY_LUKS_KEY -- /usr/local/bin/registry-luks-escrow.sh`,
   the same wrapper form as the heartbeat).
   - Minute **19** avoids the NIC guard's `2-59/5` set and the heartbeat's `*/5`, because
     concurrent `doppler run` jobs strain the host's ~1024 MB reserve (architecture review). The
     suite asserts that no two cron.d minute sets on the host intersect with the escrow minute.
   - It also runs **once at boot, in the background, after the runcmd `docker run -d --name zot`**
     (never before it, so a slow KDF can never lengthen the pull path's downtime). The field is
     therefore populated from boot and never sits at `none` for a day. The Guard 4 suite asserts
     this ordering. Under `timeout 120` it does the following, in order:
   - Resolve `DEV` via `findmnt -no SOURCE /var/lib/zot` → `cryptsetup status` device (the same
     chain the heartbeat uses).
   - Header check: `cryptsetup luksUUID "$DEV"` is non-empty.
   - **Memory pre-check (CTO finding).**
     - Read the header's PBKDF memory from `cryptsetup luksDump "$DEV"`. The `Memory:` line of
       the keyslot is non-secret.
     - Proceed only if `MemAvailable` (`/proc/meminfo`) is at least that value plus 262,144 KiB.
       Otherwise record `indeterminate`.
     - The zot cap is host RAM minus 1024 MB (`registry_host_reserve_mb`), and a LUKS2 argon2id
       slot on a 4 GB host is up to ~1 GiB. The first runtime KDF with zot resident is exactly
       when an OOM kill would take zot.
   - Escrow proof:
     `printf '%s' "$REGISTRY_LUKS_KEY" | systemd-run --scope --quiet -p OOMScoreAdjust=1000 cryptsetup luksOpen --test-passphrase --key-file - "$DEV"`.
     The OOM score makes the kernel pick the test over zot. An rc of 137 or 124 maps to
     `indeterminate`.
   - `mkdir -p -m 0700 /var/lib/soleur-registry`. The directory does not exist in the template
     today (Kieran).
   - Write `/var/lib/soleur-registry/escrow.state` atomically: a temp file in the same directory,
     then `mv -f`, owner root:root, mode 0600. The file contains `result=<token> at=<epoch>`.
   - An `EXIT` trap that has not yet written a result writes `indeterminate`, so a crash
     mid-script is visible on the next heartbeat instead of ageing into `stale`.
   - **Measured on 2026-09-21** (SOLEUR_ZOT_DISK, 23 rows over 2 h): `mem_total_mb=3814`,
     `zot_memory_cap_mb=3072`, `zot_anon_mb` ≈ 50. zot's resident set is tiny compared with an
     up-to-1 GiB argon2id slot, so the memory pre-check is expected to pass. A daily
     `indeterminate` would be a real finding, not noise.
2. The vocabulary is closed. DHH and simplicity collapsed it from nine tokens:
   - `ok`
   - `fail_passphrase`
   - `fail_header` (empty luksUUID)
   - `fail_key_absent` (empty `REGISTRY_LUKS_KEY`: the **next reboot cannot reopen**)
   - `indeterminate` (a tool refusal, the memory pre-check, a timeout or OOM, or no mapper mount)

   The three `fail_*` flavours stay distinct. The escrow script's own output is not shipped: the
   host runs no Vector, and its off-box channels are three direct POSTs (heartbeat, NIC guard,
   zot-log-shipper), none of which carries it. So the remediation cue must ride the field
   itself. The state file
   never holds key material.
3. The heartbeat reads the state file (a `timeout 5` cat, sanitised with the same
   `[A-Za-z0-9_.-]` guard as `STORE_PROBE_RC`) and emits `store_escrow=<token> store_escrow_age_s=<n>`
   **before** ` host=`, in the trusted head. Rules:
   - A missing file emits `none`.
   - An age > 93,600 s (26 h: one daily run plus two hours' slack) emits `stale`. The
     observability review showed a 48 h threshold hides a dead escrow job for two days.
   - A value outside the vocabulary emits `__UNREADABLE__`.

   The escrow never runs inside the heartbeat. The KDF would break the heartbeat's 5 s discipline.
4. Security hardening (security review):
   - `--only-secrets REGISTRY_LUKS_KEY` narrows the injected environment to the one secret. The
     precedent is the zot-log-shipper's cron line, the `--only-secrets narrows the injected`
     comment in `cloud-init-registry.yml`. This closes the #7761 class (`LD_PRELOAD`/`BASH_ENV`
     from the config store).
   - The key is fed only through a `printf '%s' | …` pipe, never a here-string.
   - A `set -x` refusal, as in `inngest-host-state.sh`.
   - Literal paths plus the heartbeat's literal PATH preamble.
   - The **boot** run uses the **same wrapper as the cron line**. It is launched in the
     background (`nohup … &`) right after the runcmd `docker run -d --name zot`. Two failures
     are ruled out:
     - Running it inside the earlier `REGLUKSEOF` LUKS shell would delay zot's start (the
       architecture review).
     - Running it bare, without the wrapper, would record `fail_key_absent` and page until 03:19
       (the security review).

     The wrapper resolves both.
   - **Test seam** (test review): literal paths bypass PATH stubs, so the suite extracts the
     script and rewrites the literal paths and `/proc/meminfo` with `sed`, the same approach
     the heartbeat suite already uses for its PATH line. There is no env-var override.
5. Suite: extend `zot-disk-heartbeat-redaction.test.sh` for the field, and add a new
   `registry-luks-escrow.test.sh` modelled on `luks-monitor.test.sh`. `cryptsetup`, `blkid` and
   `systemd-run` are PATH-stubbed. It checks:
   - Every vocabulary member is reachable from exactly one stubbed condition.
   - `fail_key_absent` fires on an empty key.
   - The memory pre-check yields `indeterminate` when the stubbed `MemAvailable` is below the
     stubbed PBKDF memory.
   - **Atomicity is asserted statically and by a stub, never by a kill race.** The static half:
     the write is temp file plus `mv -f` into the same directory. The stub half: `mv` stubbed to
     fail must leave the old state file intact.
   - The reader places the field before ` zot_last_err=`.
   - `stale` and `none` are reachable.
   - The key canary: the key string never appears in the state file, on stdout, or on stderr.
6. **User-data budget.** The baseline was measured on 2026-09-21 with
   `bash apps/web-platform/infra/registry-userdata-budget.sh`: stored **15,940 B**, cap
   32,768 B, headroom **16,828 B**. Re-run it after Phases 4, 6 and 7, and record the numbers.
   ADR-185's rule is `stored < cap`.
7. `registry-luks-live-8386.sh` reads fields by key inside the trusted region, and its only use
   of `store_probe_rc` is message text. Re-run `registry-luks-live-8386.test.sh` in the derived
   suite set.

### Phase 8 — #8449 UC2: `inngest-host-state` dispatch wrapper

1. `.github/workflows/inngest-host-state.yml`:
   - `on: workflow_dispatch` with the inputs `since` (string, default `90m`) and
     `include_errors` (boolean, default true)
   - `permissions: contents: read`
   - `concurrency: inngest-host-state`
   - `timeout-minutes: 5`
   - `uses:` SHA-pinned to the same pins `scheduled-inngest-health.yml` uses
   - `env:` `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` from `secrets.*`
   - Inputs pass through `env:` only, **never** `${{ inputs.* }}` inside `run:`. `since` is
     regex-checked `^[0-9]+[hmd]$` in the step. The script checks it too.
1a. **The repository is PUBLIC** (security review). The script prints up to 8 free-form journald
   messages (200 chars each), plus the query tool's stderr head. That is unscrubbed host text,
   so **`out.txt` never goes to `$GITHUB_STEP_SUMMARY` or the job log**.
   - `include_errors` defaults to **false**.
   - The summary and log carry only the rc, its plain-language meaning, and the verdict line.
     The verdict line is extracted by an anchored grep of the script's own verdict marker, and
     the suite checks the marker against the script.
   - The full output is not uploaded as an artifact either: a public repo's artifacts are
     readable by anyone with a GitHub account.
   - A guard case asserts that `out.txt` is never catted, echoed or uploaded.
2. Run it as:
   `rc=0; bash scripts/inngest-host-state.sh --since "$SINCE" $( [ "$INCLUDE_ERRORS" = true ] || printf -- --no-errors ) > out.txt 2>&1 || rc=$?`.
   Actions `run:` is `bash -e`, so the `|| rc=$?` is required (Kieran). Write `out.txt` and a
   **plain-language table covering every code the script's header lists** to
   `$GITHUB_STEP_SUMMARY`:
   - 0: host state printed
   - 2: bad usage, nothing queried
   - 3: credentials not configured in this repo
   - 4: **the host is not shipping; silence is not health**
   - 5: no verdict
   - 6: **the read failed; this says nothing about the host**
   - 78: refused, tracing
3. Exit behaviour: exit 0 only on rc 0. Every non-zero rc emits `::error::inngest-host-state rc=<n> — <meaning>`
   before exiting, and a missing `out.txt` is itself non-zero. **Any other rc exits non-zero**, including rc 4, which
   the script's own header calls a finding ("SILENCE IS NOT HEALTH"). A red run is the correct
   phone-visible signal.
4. Update `knowledge-base/engineering/operations/runbooks/inngest-server.md`, the "Reading host
   state without SSH" section, with the one-tap route. Keep the `doppler run` form as the laptop
   route.
5. Suite: `apps/web-platform/infra/inngest-host-state-workflow-guard.test.sh`. Beyond static
   checks, it **executes** the extracted `run:` block with the script stubbed to return each exit
   code, and asserts the job's exit and the summary text per code. The exit-code set it derives
   has a floor of ≥7 plus set identity (test review). Otherwise it is modelled on
   `registry-zot-inventory-workflow-guard.test.sh`. No repo-wide lint covers SHA pins or
   `${{ inputs` in `run:`; `scripts/lint-workflows.sh` was checked. The suite covers:
   - no `${{ inputs` inside any `run:`
   - `permissions` is exactly `contents: read`
   - all three secrets are wired
   - every `uses:` is SHA-pinned
   - the step-summary table names **every** code parsed out of the script's `Exit codes:` header
     block, so the code set is derived, not hand-listed
   - `|| rc=$?` is present
6. **UC1 recommendation**, in one sentence in the PR body and in a short #8449 comment: keep the
   graded verdict, and add the single `::error::` routing line naming the dispatchable reads,
   which UC2 now makes one tap. **UC3:** not touched, because it is repo-wide.
7. #8449 stays open (`Ref`) for the operator's UC1 and UC3 rulings.
8. **Post-merge (automated):** `gh workflow run inngest-host-state.yml`. A new workflow can only
   be dispatched once it is on the default branch. Watch the run and record its rc and summary
   on #8449.

### Phase 9 — #8278: premise re-check (comment only)

Post one comment on #8278, and do not change the `blocked` label. The comment says:

- The trigger is "re-enrolled in any open follow-through issue". It is **not met**, measured on
  2026-09-21: 0 directives name `zot-log-channel-7440.sh`.
- The "landscape moved" claim was checked. #7377 cites the **sibling**
  `registry-luks-blocker-6929.sh` in prose and in a checkbox. It does not enrol it, and that
  script's tracker #7340 is CLOSED.
- The sweep issue (Phase 10) owns correcting that sibling's stale plaintext claims.

### Phase 10 — the sweep issue (LAST)

1. Dedup:
   `gh issue list --state all -L 200 --search "registry plaintext in:title,body"`, then
   `… --search "LUKS stale in:title,body"`. Each search is two AND-joined nouns. Read every hit's
   title and state, and record them in the session.
2. Scope boundary: #6897 (open) owns *legal-doc* reconciliation and the *superseded* plaintext
   volumes. This sweep is the registry-specific stale operator docs and script. The body says so
   and cross-references #6897, so neither issue absorbs the other.
3. The body is built from the Reconciliation table above:
   - Recut runbook: the five "unencrypted/plaintext" phrases, quoted. These are live operator
     instructions.
   - Blocker script: the five phrases. **Correct them, don't annotate.** #7377's checkbox is a
     live re-enrolment path.
   - `registry-zot-inventory.yml` header: one phrase.
   - `nfr-register.md`: the **missing** `hcloud_volume.registry` at-rest row.
   - Dropped, with reasons: `scheduled-zot-restart-loop.yml` (0 hits) and
     `encryption-posture-audit-2026-07-23.md` (already corrected by #7547).
   - Labels: `domain/engineering`, `type/chore`, `priority/p3-low`. Milestone:
     `Post-MVP / Later`.
4. **CONCUR gate**: spawn one independent subagent with the draft body and the instruction
   *"re-grep origin/main for each quoted phrase and confirm it still asserts plaintext about the
   registry volume, and that nothing in the dropped list should be restored; reply CONCUR or list
   corrections."* `gh issue create` runs only after it returns CONCUR, with corrections applied
   and re-checked.

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh`: Phases 1 and 2.
- `apps/web-platform/infra/ci-deploy.test.sh`: Phases 1 and 2.
- `apps/web-platform/infra/cloud-init-registry.yml`: Phases 4, 6 and 7.
- `apps/web-platform/infra/registry-boot-guard.test.sh`: Phase 4 floor/rows. It is also the
  single-launch-site set identity, if colocated.
- `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh`: Phase 4 (the PATH literal
  substitution) and Phase 7 (the field).
- `apps/web-platform/infra/betterstack-logs-alerts.tf`: Phase 5.
- `.github/workflows/apply-web-platform-infra.yml`: Phase 5, two `-target=` lines.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`: Phase 8.
- `knowledge-base/engineering/architecture/decisions/ADR-087-cosign-deploy-verify-host-net-ephemeral-verifier-over-private-ghcr.md`:
  an amendment (see Architecture Decision).
- `knowledge-base/engineering/architecture/diagrams/model.c4` and `views.c4`: see Architecture
  Decision.
- The `guard-vacuity-floor` / `_EXACT_FLOOR` rows for every suite whose case count changes, in
  the same edit as the cases.

## Files to Create

- `apps/web-platform/infra/templatefile-bare-dollar-guard.test.sh` (Phase 4)
- `apps/web-platform/test/infra/registry-store-not-luks-alert.test.sh` (Phase 5)
- `apps/web-platform/infra/registry-luks-launch-gate.test.sh` (Phase 6)
- `apps/web-platform/infra/registry-luks-escrow.test.sh` (Phase 7)
- `.github/workflows/inngest-host-state.yml` (Phase 8)
- `apps/web-platform/infra/inngest-host-state-workflow-guard.test.sh` (Phase 8)
- `scripts/followthroughs/cosign-verify-live-8037.sh` and its `.test.sh` (Phase 2.9.1 enrolment,
  see Observability)

Every new `*.test.sh` must be picked up by `scripts/test-all.sh`'s enumeration. Verify it with
the toolchain-enumeration suite (`test-all-enumerate-toolchain.test.sh`), not by assuming the
glob.

## Open Code-Review Overlap

None. On 2026-09-21, the 68 open `code-review` issues were checked against every path in Files to
Edit and Files to Create, plus `ADR-087` and `zot-disk-heartbeat`. There were 0 matches.

## User-Brand Impact

**If this lands broken, the user experiences:** production that cannot take a new release. There
are two ways this happens:

- A `ci-deploy.sh` regression in the verify path or the new emitter. For example, an abort under
  `set -e` in a config probe, or a stray stdout write into the `VERIFIED_REF` capture (Kieran's
  P0: `verify_image_signature` runs inside `VERIFIED_REF="$(…)"`, so any new stdout corrupts the
  ref the deploy runs; every new line goes to `logger` or `>/dev/null`).
- A registry replace that leaves zot unable to start. For example, the sentinel is missing on a
  preserved volume because the write was mis-ordered.

The running app keeps serving through both. The failure is "new releases stop", not "the site
goes down". It is visible as `image_pull_failed` or `IMAGE_VERIFY_FAIL` in Better Stack, or as
zot down in the heartbeat.

**If this leaks, the user's workflow is exposed via:** the one credential-adjacent surface this
adds, the 1b marker. A careless implementation would print the founder's GHCR username, or a
decoded `auths` value, into journald → Better Stack (unscrubbed). That is a supply-chain path to
every user, because a GHCR read credential pulls the private app image. The escrow script handles
`REGISTRY_LUKS_KEY`, and a leak of that key would defeat the registry at-rest claim. Both are
covered by the canary cases (T-1b-2, and the Phase 7 key canary).

**Brand-survival threshold:** aggregate pattern.

No single user's data is exposed by any failure mode here. The registry holds container images,
not user data, and the web image carries no user data. The worst outcome is fleet-wide release
blockage (an aggregate availability pattern), bounded by `_try_local_cache_reload` and the
running containers. `threshold: aggregate pattern, reason: the diff touches deploy and
infrastructure paths whose failure blocks releases fleet-wide but cannot expose any single user's
data`.

## Observability

```yaml
liveness_signal:
  what: >-
    (1) SOLEUR_DEPLOY_GHCR_CONFIG, and the existing IMAGE_VERIFY: ok / IMAGE_VERIFY_FAIL result=
    line, once per deploy on SYSLOG_IDENTIFIER=ci-deploy.
    (2) The SOLEUR_ZOT_DISK heartbeat (*/5), now carrying a well-formed
    store_probe_rc=cs<rc|na>.bk<rc|na> and store_escrow=<token> store_escrow_age_s=<n>.
  cadence: per deploy (6-12/day); heartbeat every 5 min; escrow daily at 03:17 UTC
  alert_target: >-
    Better Stack exploration alert registry_store_not_luks (email + escalation policy, as the
    inngest_luks_wrong_volume sibling), plus the existing zot heartbeat-liveness alarm for "zot
    did not start" (the sentinel gate's fail-closed arm)
  configured_in: >-
    apps/web-platform/infra/betterstack-logs-alerts.tf (new pair);
    apps/web-platform/infra/cloud-init-registry.yml (heartbeat + escrow cron);
    apps/web-platform/infra/ci-deploy.sh (journald lines)
error_reporting:
  destination: >-
    Better Stack (journald -> Vector for ci-deploy; direct POST for the registry heartbeat).
    Sentry via the existing cosign_verify_event on IMAGE_VERIFY_FAIL (unchanged).
  fail_loud: >-
    yes. Every escrow value other than ok pages through the alert predicate. A missing sentinel
    fails zot's start (a liveness alarm, self-healed within one NIC-guard tick once the store
    returns), never a quiet serve. A failed anonymous cosign pull still yields a Sentry-visible
    IMAGE_VERIFY_FAIL result=cosign_absent.
failure_modes:
  - mode: anonymous cosign pull fails (ghcr.io outage or rate limit)
    detection: IMAGE_VERIFY_FAIL result=cosign_absent (Sentry). The image is pruned before every verify, so the anonymous pull runs on every deploy
    alert_route: Sentry cosign_verify_event (existing); cosign-verify-live-8037.sh follow-through FAIL
  - mode: verify now runs and reports a real result class (unsigned / wrong_identity / verify_failed)
    detection: IMAGE_VERIFY_FAIL result=<class> (Sentry, existing)
    alert_route: Sentry; the #8037 probe maps a non-cosign_absent failure to exit 5 ACTION REQUIRED
  - mode: registry store not on LUKS after a replace or reboot
    detection: SOLEUR_ZOT_DISK trusted head lacks store_luks=yes
    alert_route: registry_store_not_luks (Better Stack)
  - mode: mapper failed to open after a reboot
    detection: >-
      zot fails to start (sentinel bind source missing), so zot-liveness-heartbeat stops pinging.
      Corroboration in SOLEUR_ZOT_DISK: state_status=exited|created and luks_open_arm=<arm>.
      The NIC-guard recovery (<=5 min) always pages before it heals, and that is correct.
    alert_route: betteruptime_heartbeat.registry_prd ("soleur-registry-prd", 60 s period + 30 s grace; measured live and unpaused)
  - mode: the passphrase no longer opens the header, the header is unreadable, or the key is absent from Doppler
    detection: store_escrow=fail_passphrase|fail_header|fail_key_absent in the trusted head
    alert_route: registry_store_not_luks arm (B) (Better Stack)
  - mode: the escrow job silently stops running
    detection: store_escrow=stale (age > 48h), none, or indeterminate
    alert_route: registry_store_not_luks arm (B) (Better Stack). Plan review widened the arm from fail-only to any value other than ok
logs:
  where: Better Stack source shared with vector_prd (SYSLOG_IDENTIFIER=ci-deploy; SOLEUR_ZOT_DISK direct POST)
  retention: Better Stack plan retention (unchanged)
discoverability_test:
  command: bash scripts/betterstack-query.sh --since 24h --grep SOLEUR_ZOT_DISK --limit 5
  expected_output: "SOLEUR_ZOT_DISK"
  credentials_required: >-
    BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} (read-only warehouse query) — the heartbeat rows
    are only in the Better Stack warehouse, and there is no unauthenticated read of that store.
```

**Follow-through enrolment (Phase 2.9.1).**

- **#8037**: `scripts/followthroughs/cosign-verify-live-8037.sh`, modelled on
  `zot-login-gate-erofs-repaired-6565.sh`.
  - Per `_MACHINE_ID`, since `SOLEUR_FT_EARLIEST`:
    - **PASS (0)**: every host that emitted any `IMAGE_VERIFY` line has ≥1 `IMAGE_VERIFY: ok`
      and 0 `result=cosign_absent`, with ≥1 host observed.
    - **FAIL (1)**: a host's **latest** `IMAGE_VERIFY*` line after earliest is still
      `cosign_absent`. The observability review found that "any occurrence" would FAIL forever on
      one ghcr.io blip. Each host is graded on its most recent verdict.
    - A host whose latest verdict is preceded in the same deploy by `IMAGE_VERIFY_PREP: anon_config=unavailable`
      grades **5**, with its own message: the fallback put the credentialed pull back.
    - Evidence counts only from deploys that ran **after** the `deploy_pipeline_fix` apply
      concluded. The co-fired release may still run the old script, so `earliest` is set from
      that apply's completion time plus a margin (architecture review).
    - **5**: a host emits a *different* failure class. The verifier runs and says something about
      the image, which is a human decision.
    - **2/3**: the usual channel and evidence guards.
  - It keys on the `SYSLOG_IDENTIFIER` field. The test rows cover:
    - zero hosts, which never PASSes
    - an `IMAGE_VERIFY: ok` under another identifier, which does not count
    - the double-encoded `raw` fixture
  - It is registered via `run_suite` in `scripts/test-all.sh`, because follow-through suites are
    not picked up by the globs.
  - **Measured on 2026-09-21** (24 h): 9 × `IMAGE_VERIFY_FAIL: result=cosign_absent` and 9 ×
    `stage=relogin_failed`, all on one `_MACHINE_ID` (web-1). So PASS needs ≥1 host, never ≥2.
  - Directive on #8037:
    `<!-- soleur:followthrough script=scripts/followthroughs/cosign-verify-live-8037.sh earliest=<merge+1d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->`
    plus the `follow-through` label. It needs no new sweeper secrets.
- **#8417** is closed by ship's post-merge verification (Phase 4.4), not a new probe. The probe was
  cut in plan review: the closing observation lands minutes after merge, when the replace
  completes, so there is no soak to automate.
- **#8408** keeps its existing enrolment. The PR comments on it with what landed ((a), (b), (c))
  and what closes it: a post-delivery boot showing `store_escrow=ok` plus a human reading of the
  8386-probe V7.

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.registry (zot OCI store, /var/lib/zot)
    mechanism: guest-side LUKS2 (cryptsetup luksFormat --type luks2) on /dev/mapper/registry, passphrase REGISTRY_LUKS_KEY in Doppler soleur-registry/prd only
    evidence: >-
      scripts/encryption-posture-ledger.json row hcloud_volume.registry (live_verification:
      available); SOLEUR_ZOT_DISK store_luks=yes with store_mount_devid == store_expected_devid,
      boot b3ec6c3b (120+ rows, 2026-09-20). This change ADDS a reboot-time consumer gate
      (sentinel bind) and a daily escrow re-test.
    defends_against: offline theft or reuse of the Hetzner volume, and provider-side snapshot disclosure
    does_not_defend: >-
      a compromised running host (the mapper is open); a Doppler soleur-registry/prd reader (holds
      the key); an attacker with root who copies the store to a plaintext path and re-plants the
      sentinel (the gate is a failure-mode control, not an adversary control)
    disclosed_as: ledger row hcloud_volume.registry; model.c4 zotRegistry "AT REST: guest-side LUKS, LIVE-VERIFIED"
    live_verification: available (unchanged by this plan; escrow adds a second live signal)
  - store: /var/lib/soleur-registry/escrow.state (root disk, new)
    mechanism: plaintext-exception — the file holds only a result token and an epoch, never key material
    evidence: registry-luks-escrow.test.sh key canary (the key string never appears in the state file)
    defends_against: nothing (non-sensitive by construction)
    does_not_defend: disclosure of the file to a root-disk reader reveals the last escrow verdict and its time (by design non-secret); it provides no protection for the key, which never enters it (see the canary)
    disclosed_as: this plan and the escrow script header
    live_verification: unavailable — a host-local file, reported only as the heartbeat field
in_transit:
  - connection: web host docker daemon -> ghcr.io (cosign verifier image, anonymous)
    tls: HTTPS (registry v2)
    cert_verification: on (docker default; no insecure-registries entry for ghcr.io)
    does_not_defend: >-
      a compromised Sigstore publisher or ghcr.io serving different bytes under the tag. It is
      defended instead by the @sha256 digest pin in COSIGN_IMAGE.
    disclosed_as: model.c4 second hetzner -> ghcr edge (LIVE anonymous verifier-image pull); ADR-087 amendment
  - connection: registry heartbeat -> Better Stack ingest (unchanged, gains two fields)
    tls: HTTPS
    cert_verification: on
    does_not_defend: any holder of the shared source's ingest token forging rows (see the registry-luks-live-8386.sh header)
    disclosed_as: registry-luks-live-8386.sh header; scripts/lib/betterstack-sources.sh
exception:
  - store: /var/lib/soleur-registry/escrow.state
    justification: holds a closed-vocabulary result token and an epoch, no secret; encrypting it buys nothing
    tracking_issue: "8408"
    reevaluate_when: the state file ever gains a field other than result= and at=
    expires_on: 2027-09-21
```

## Downtime & Cutover

- **Operation.** A volume-preserving `registry-host-replace`, fired by
  `registry-host-replace-dispatch.yml` on the merge.
- **Surface.** zot is the fleet's **only** image pull path. The host GHCR fallback is dead
  (#7071). Running containers keep serving, and only new pulls are affected.
- **Zero-downtime evaluation.** Not possible, and the reasons were measured, not assumed:
  - the registry is a singleton with a fixed private IP (`10.0.1.30`)
  - its volume attaches to one host at a time
  - create-before-destroy therefore cannot hold both

  Blue-green would need a second volume and a store copy. That is a recut-class operation
  (ADR-169), far larger than this change.
- **Bounded window.** Destroy, create, boot, LUKS open, then zot start: about 3–8 minutes. It
  opens only after preflight P3 clears the co-fired release (up to 35 minutes of waiting, during
  which nothing is down). Deploys inside the window fall to `_try_local_cache_reload`. The boot
  escrow run is backgrounded **after** `docker run zot`, so it never lengthens the window.
- **Expected page.** `registry_store_not_luks` needs ≥2 matching rows in 15 minutes. A single
  pre-mount heartbeat tick on the new boot cannot page. `soleur-registry-prd` may page during
  the window, which is existing behaviour for any replace.
- **Verification.** A SOLEUR_ZOT_DISK row with a **new** `boot_id` and `store_luks=yes`,
  `store_escrow=ok`, `store_probe_rc=cs0.bk0` and `luks_open_arm=` present, plus a green
  `web_zot_consumer` probe.
- **Rollback.** Revert the PR, which is another volume-preserving replace carrying the old
  user_data. For a replace that fails to boot, re-dispatch `registry-host-replace`.
- **Sign-off.** This is the delivery mechanism the repo already automates (ADR-190: "the merge
  IS the intent to deliver"). The residual window is the one every registry user_data change
  accepts. No new maintenance window is introduced.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/betterstack-logs-alerts.tf` gets the new
  `logtail_exploration.registry_store_not_luks` and
  `logtail_exploration_alert.registry_store_not_luks`.
- Providers: the existing `logtail` pin is unchanged. There are no new sensitive variables.
- `cloud-init-registry.yml` changes are `templatefile()` content. There is no new tf variable.
  `${registry_volume_id}` is already interpolated.

### Apply path

- (b) cloud-init plus the existing automated replace: the merge fires
  `registry-host-replace-dispatch.yml` (push-to-main on `cloud-init-registry.yml`). It is
  preflight-gated (`scripts/registry-replace-preflight.sh`, fail-closed) and preserves the volume.
  The expected blast radius is one replace window on the sole pull path, a few minutes, with
  deploys in that window falling to `_try_local_cache_reload`.
- The alert pair is applied by `apply-web-platform-infra.yml` via the new `-target=` lines, in
  place and with no downtime.
- `ci-deploy.sh` is delivered by the `deploy_pipeline_fix` auto-apply (in place).
- Nothing in this plan needs a person to SSH or click. The new cron line and scripts ship in
  user_data and reach the host only through the replace.

### Distinctness / drift safeguards

- `registry_rationale_strip` makes comment-only edits byte-identical. Phases 4, 6 and 7 are
  non-comment, so the delta gate **will** fire. That is intended.
- The registry user_data budget: `registry-userdata-budget.sh` (ADR-185: `stored < cap`) is run
  before and after.
- `apply-web-platform-infra.yml` stays under 490,000 B. This is re-measured.

### Vendor-tier reality check

The alert uses `escalation_target { policy_id = var.betterstack_paid_tier ? … : null }`, exactly
as the sibling does. It works on the free tier because email is always on.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-087.** Add a `## Amendment 2026-09-21 (#8036)` section:

- The verify `docker run` executes with the CLI's `DOCKER_CONFIG` pointed at an isolated empty
  directory, so the verifier **image** is always pulled anonymously.
- It is pulled on **every** deploy, because `docker image prune -af` runs before the verify.
  This makes public ghcr.io a per-deploy dependency. An ENFORCE flip must first decide whether
  to pin the verifier image locally.
- The failure mode, stated: if the anonymous pull fails (a ghcr.io outage or rate limit), the
  `docker run` fails with `Unable to find image` / `denied`, and it is classified
  `cosign_absent`. Under WARN the deploy runs the digest unverified and Sentry receives
  `cosign_verify_event`. Under ENFORCE the deploy would be blocked. That is why a local pin is
  the ENFORCE precondition.
- The mounted host config's purpose narrows to the `.sig` referrer fetch only.
- Why: the implicit pull presented a revoked inline `ghcr.io` credential, and GHCR returns DENIED
  to a revoked credential where it serves a public image anonymously. That made verification dead
  for seven weeks (#8037).
- Add to `## Alternatives Considered`: "mint a new read credential", rejected by ADR-088 arm-b and
  hr-github-app-auth-not-pat, and "logout ghcr.io", deferred to #8036 1c.

No new ADR. **Amend ADR-096** with one line: zot launch moves from fail-open (serve whatever
`/var/lib/zot` holds) to **fail-closed on every container start** (the sentinel bind), with
≤5-min self-heal through the NIC guard. That is an explicit availability-for-integrity trade on
the sole pull path. The gate otherwise implements ADR-096's existing LUKS decision (#6895 D2). It is recorded in the cloud-init comment and in the ledger's
`does_not_defend` wording after delivery.

### C4 views

All three files were read (`model.c4`, `views.c4`, `spec.c4`). This is the enumeration.

- **External systems.**
  - `ghcr` (private, DEAD for hosts) is already modelled.
  - `sigstore` is already modelled. It is the keyless signing service, with no live call at
    verify time.
  - `projectZot` (the public upstream for the zot binary) is already modelled.
  - **Unmodelled:** the web hosts' live pull of the cosign **verifier image** from public
    `ghcr.io/sigstore/cosign`. This is exactly the #7282 lesson (a live public-ghcr dependency
    hiding behind the dead private node), repeated on the web hosts.
  - **Revised twice.** Plan review rejected a new node. Deepen review (architecture) then showed
    that a `hetzner -> sigstore` edge would repeat the #7282 mistake: the live dependency is
    **ghcr.io's availability and its anonymous rate limit**, not Sigstore's. The edge would also
    pull `sigstore` into the containers view and move the counts.
  - **Final form:** a **second** `hetzner -> ghcr` edge (duplicate edges already exist, for
    example `hetzner -> zotRegistry` twice):
    `hetzner -> ghcr "LIVE (#8036): anonymous public pull of the @sha256-pinned cosign VERIFIER
    IMAGE (ghcr.io/sigstore/cosign) on every deploy — pruned before each verify. Distinct from
    the DEAD private-package edge: this one needs no credential and is a per-deploy dependency on
    ghcr.io availability and anonymous rate limits (ADR-087 amendment)"`, with technology
    "Docker/HTTPS (anonymous, digest-pinned)".
  - Also amend the `ghcr` node description, which says "can serve none TO HOSTS", to scope that
    claim to the private packages.
  - No `sigstore` or view change.
  - `views.c4`: unchanged. `ghcr` and `hetzner` are both already included wherever the existing
    `hetzner -> ghcr` edge renders.
- **Edge text.** `hetzner -> ghcr`: append that the cosign verifier pull no longer traverses this
  edge's credential (#8036). The edge stays DEAD, pending 1c.
- **Containers and data stores touched.**
  - `zotRegistry`: its description already says LUKS LIVE-VERIFIED. Append "zot start is gated on
    the LUKS filesystem's sentinel (every container start) and the passphrase is re-tested daily
    (#8408)".
- **Human actors.** None changes. No actor↔surface access relationship changes.
- **Counts.** Run `plugins/soleur/test/c4-count-parity.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts`
  and `c4-render.test.ts`. The new edge may move a cardinality in edge prose, and the parity
  gate owns that.

### Sequencing

The ADR amendment and the C4 edits land in the same PR as Phase 1. There is no deferral.

## Guard Contract

### Guard 1 — templatefile bare-dollar guard

**Property.** No non-comment line of any file rendered through `templatefile()` in
`apps/web-platform/infra/*.tf` contains `$$` immediately followed by an identifier-start
character or `(`.

**Assembly.** The chokepoint is `templatefile(` call sites in `apps/web-platform/infra/*.tf`.
The file set is **derived** by grepping those call sites (`apps/web-platform/infra/**/*.tf`, with
`${path.module}` resolved per file) for their first argument, never hand-listed. Today that is 8
files: `cloud-init.yml`, `cloud-init-inngest.yml`, `cloud-init-registry.yml`,
`cloud-init-grok-dogfood.yml`, `docker-daemon.json.tmpl`, `hooks.json.tmpl`,
`soleur-doppler-token.tmpl`, and `cloud-init-git-data.yml` (the one rendered through
`modules/git-data-userdata/main.tf`). The comment filter is the
`registry_rationale_strip` regex.

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| 1 | Restore `cs$$_cs_rc` at the `STORE_PROBE_RC` site | RED |
| 2 | Restore `$$PATH` at the heartbeat PATH line (a second member after a compliant first) | RED |
| 3 | Add `x=$$((1+1))` to `cloud-init-inngest.yml` (a different file of the assembly, so the scan is not pinned to the registry file) | RED |
| 4 | Add a new `templatefile("${path.module}/new.tmpl"…)` call site in a **nested module** whose template contains `$$FOO` (dispatch: the derived count becomes 9) | RED |
| 5 | Make the derivation return 0 files | RED (floor + set identity) |

**Harness rows.**

| # | Edit to the suite / input | Expected |
|---|---|---|
| H1 | Replace the scan loop body with `:` | RED (`files_scanned` floor) |
| H2 | Must-PASS: `tmp=/tmp/x.$$` followed by `.` (a legitimate PID use) | GREEN |
| H3 | Must-PASS: a bare `$$FOO` on a comment line (stripped exactly as the render strips it) | GREEN |

**Anchor.** The floor `>= 8` is paired with set identity against the list derived from the
`.tf` call sites. Removing a file from the set needs a `.tf` edit that review sees.

### Guard 2 — cosign verifier image is never pulled with a credential

**Property.** The docker CLI invocation that can pull `COSIGN_IMAGE` never has access to a docker
config holding auths, a `credsStore` or `credHelpers`.

**Assembly.** Every docker subcommand in `ci-deploy.sh` that names `$COSIGN_IMAGE`. Today that is
exactly one: the verify `docker run`. The suite **joins backslash-continued lines first** (the
image sits on a continuation line), excludes the `readonly COSIGN_IMAGE=` declaration and
comments, and counts the remaining references as set identity (=1). A second pull or run site
added later fails until it carries the prefix too. The property also covers the logged fail-open
(`anon_config=unavailable`) as the one sanctioned exception, which must be logged.

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| 1 | Drop the `DOCKER_CONFIG="$anon_dir"` prefix from the verify `docker run` | RED (T-1a-1, T-1a-3) |
| 2 | Point `anon_dir` at `$DOCKER_CONFIG` | RED (T-1a-3: the canary auth becomes readable) |
| 3 | Make the `mktemp -d` failure yield `DOCKER_CONFIG=""` (the CLI then falls back to `~/.docker`) | RED (T-1a-5) |
| 4 | Add a second `docker pull "$COSIGN_IMAGE"` without the prefix (a second member) | RED (set-identity count) |
| 5 | Delete the `$GHCR_DOCKER_CONFIG` `:ro` mount. P1 still holds, but P2 fails: the precondition-holds, property-fails row | RED (T-1a-2) |

**Harness rows.**

| # | Edit to the suite / input | Expected |
|---|---|---|
| H1 | Make the mock's verify-time `DOCKER_CONFIG` recorder a no-op | RED (T-1a-1 requires the recorded line) |
| H2 | Must-PASS: a deploy config holding only a zot auths entry, with no `ghcr.io` key | GREEN; the verify still sees an empty anon config |

### Guard 3 — alert predicate is head-scoped and live

**Property.** `registry_store_not_luks` fires on SOLEUR_ZOT_DISK rows whose trusted head (before
` zot_last_err=`) lacks `store_luks=yes `, or carries a `store_escrow=` value other than `ok`.
Tail text cannot satisfy or suppress either arm.

**Assembly.**

- The one SQL local, parsed out of the `.tf` by the suite.
- The one alert resource.
- The two `-target=` lines in the push-triggered `apply` job.
- The recorded live-probe counts in the tf comment, which are the engine-level evidence.

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| 1 | Drop the ordering conjunct against `' zot_last_err='` in arm (A) | RED (structural) |
| 2 | `paused = true` | RED |
| 3 | Drop one `-target=` line | RED |
| 4 | `'store_luks=yes '` becomes `'store_luks=yes'` (no trailing space) | RED (exact-literal assert) |
| 5 | Narrow arm (B) back to `store_escrow=fail` | RED (the `store_escrow=ok ` negation literal is required) |
| 6 | Replace `JSONExtractString(raw, 'message')` with a bare `msg` | RED (column-form assert) |

**Harness rows.**

| # | Edit to the suite / input | Expected |
|---|---|---|
| H1 | Point the suite's SQL extractor at an empty string | RED (the extracted SQL must be non-empty and carry the anchor) |
| H2 | Must-PASS: whitespace reflow of the heredoc (the resource site collapses whitespace) | GREEN |

### Guard 4 — zot cannot start off the LUKS filesystem, and recovers when it returns

**Property.** Every zot container start requires the bind source
`/var/lib/zot/.soleur-luks-sentinel`, which exists only inside the opened LUKS filesystem. When
the filesystem returns, zot is started within one NIC-guard tick.

**Assembly.**

- Every `docker run … --name zot` site. There is exactly one, checked by set identity.
- The sentinel write, inside the `findmnt` conjunction and before the runcmd `docker run`.
- The NIC-guard recovery arm.
- Docker's start-time bind resolution, measured by the docker-gated case.

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| 1 | The zot `--mount type=bind` becomes `-v` (which auto-creates the source) | RED (static; the behavioural negative control shows why) |
| 2 | REORDER: move the sentinel write out of the `findmnt` conjunction and above the mount, so it runs unconditionally and lands on the root disk | RED (static ordering and conjunction assert) |
| 3 | Add a second zot `docker run` without the mount (a second member) | RED |
| 4 | Delete the NIC-guard `.State.Running` recovery arm | RED (static) |

**Harness rows.**

| # | Edit to the suite / input | Expected |
|---|---|---|
| H1 | Swap the behavioural case's `--mount` for `-v` | RED (the "start fails after deletion" leg now succeeds) |
| H2 | Must-PASS: sentinel present, start succeeds; recreate after deletion, start succeeds | GREEN |
| H3 | No docker daemon | exits non-zero (`NO-DOCKER`), never passes |

### Guard 5 — escrow result is honest and keyless

**Property.** `store_escrow=ok` is emitted only when `luksOpen --test-passphrase` exited 0 with the
Doppler-held key, against the device backing `/var/lib/zot`, within the last 48 h. The key never
leaves the process.

**Assembly.** `registry-luks-escrow.sh` (the producer: the cron line and the runcmd boot call),
the state file (the one channel), and the heartbeat reader (the one consumer).

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| 1 | Ignore the `--test-passphrase` rc (append an or-true) | RED (a stubbed rc=2 must yield `fail_passphrase`) |
| 2 | Treat an empty key as a skip | RED (`fail_key_absent` is required) |
| 3 | Remove the age check | RED (a 3-day-old state must read `stale`) |
| 4 | Write the state with a plain redirect instead of temp plus `mv` | RED (static pattern assert, plus the `mv`-fails stub leaving the old file intact) |
| 5 | Echo the key into the log | RED (canary) |
| 6 | The reader places the field after ` zot_last_err=` | RED |
| 7 | Drop the memory pre-check | RED (a stubbed `MemAvailable` below the PBKDF memory must yield `indeterminate`) |

**Harness rows.**

| # | Edit to the suite / input | Expected |
|---|---|---|
| H1 | Stub cryptsetup to succeed regardless of input | the header and key rows still RED |
| H2 | Must-PASS: a fresh `ok` state | `store_escrow=ok`, GREEN |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] The PR body re-dates both probes on the day it is written: the token's `GET /user` status,
      and the anonymous cosign manifest HEAD status. A seven-week-old measurement is not quoted as
      current.
- [ ] Phase 1: T-1a-1 … T-1a-5 pass. The verify-time `DOCKER_CONFIG` is an empty directory,
      the deploy config's `:ro` mount is unchanged, and the canary auth is unreadable from the
      verify-time config.
- [ ] Phase 2: T-1b-1 … T-1b-3 pass. The canary strings are absent from all captured output, and
      the unreadable and unparseable fixtures do not abort the deploy.
- [ ] Phase 4: both bare-`$$` sites are fixed. Guard 1 is green, and each of its mutation rows was
      driven RED once by hand, recorded in the PR with the command. Evaluating the rendered
      `STORE_PROBE_RC` line prints `cs127.bkna` for `_cs_rc=127 _bk_rc=na` and `cs0.bk0` for
      `0/0`. `_bk_rc=0` is set before blkid.
- [ ] Phase 5: the alert SQL was live-probed with three controls, and the counts are recorded in
      the tf comment. The apply workflow is < 490,000 B, with before/after sizes in the PR.
- [ ] Phase 6: the docker-gated behavioural case **ran** in CI. It shows start and restart
      failing after sentinel deletion, start succeeding after recreation, and the `-v` negative
      control succeeding. The NIC-guard `.State.Running` recovery arm is present.
- [ ] Phase 7: every escrow vocabulary member is reachable, including `indeterminate` via the
      memory pre-check. The key canary passes. The field sits in the trusted head. The runcmd
      boot call exists.
- [ ] `registry-userdata-budget.sh` reports `stored < cap` after Phases 4 + 6 + 7, with the
      numbers in the PR.
- [ ] Phase 8: the workflow guard suite is green, with no `${{ inputs` inside `run:`. Every
      script exit code is in the summary table, and the run exits non-zero on any rc other than 0.
- [ ] ADR-087 (mechanism and failure mode) and ADR-096 (fail-closed launch trade) are amended.
      The second `hetzner -> ghcr` edge and the `ghcr` description scope are in `model.c4`. `c4-count-parity.test.sh`,
      `c4-code-syntax.test.ts` and `c4-render.test.ts` are green.
- [ ] The suite set was derived mechanically:
      `git grep -ln '<changed-path>' -- 'tests/**' 'scripts/**' 'apps/**' 'plugins/**' '.github/**'`
      for every changed path, unioned. All suites were run, and the list and results are in the
      PR.
- [ ] Repo-global gates, run by hand:
  - `fixture-relative-assert`: compared **row by row** against its baseline, not as a count.
    Regenerate it with `--write-baseline` in the same commit and review the diff (test review).
  - `guard-vacuity-floor`: it discovers suites by their shape, so every new suite's floor uses
    the recognised shape. It has no per-suite rows to add.
  - `lint-diagnosis-claims` 24/24
  - `lint-window-closure-assertion` 24/24
  - `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
    clean
  - `python3 scripts/lint-encryption-posture.py --repo-sweep` clean
  - `python3 scripts/lint-guard-contract.py <this plan>` clean

  Any floor raised is raised in the same edit as its row.
- [ ] The PR body names the four merge-time pipelines. It uses `Ref #8036 #8037 #8417 #8408
      #8449 #8278`. It contains **no** closing keyword for any of them, not even in prose. It
      carries the 1c recommendation, the UC1 recommendation, the 1b closed-vocabulary deviation
      (no username or identity field), the ≤5-min fail-closed bound of the sentinel gate, and the
      `_bk_rc` behaviour change.
- [ ] The #8278 comment was posted, and `blocked` was retained.
- [ ] The #8037 directive was added, with the `follow-through` label.

### Post-merge (operator-free, automated)

- [ ] `deploy_pipeline_fix` applied. The first deploy that ran the new `ci-deploy.sh` emits one
      `SOLEUR_DEPLOY_GHCR_CONFIG` line. Its tokens are posted to #8036 as the §6 answer.
- [ ] `cosign_absent` stops. Whether `IMAGE_VERIFY: ok` appears is graded by the #8037 probe,
      not asserted in the PR.
- [ ] `registry-host-replace-dispatch.yml` ran. Either the replace succeeded, and a new `boot_id`
      shows `store_probe_rc=cs0.bk0`, `store_escrow=ok`, and zot serving, or the preflight
      refused. On the replace path, #8417 is commented and closed. A refusal is reported on the PR
      and on #8417 as "dormant until next replace", with the artifact link. Nothing says
      "deployed" without the new-boot rows.
- [ ] `gh workflow run inngest-host-state.yml` was dispatched once, and its rc and summary were
      recorded on #8449.
- [ ] The `registry_store_not_luks` alert exists, is unpaused, and is silent.
- [ ] The sweep issue is filed after the CONCUR gate, and it is the last GitHub write of the
      session.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO, run at plan time, found four risks. All are folded in.

1. `docker image prune -af` runs before verify, so the cosign image is re-pulled on every deploy.
   This is accepted, documented, and recorded in the ADR-087 amendment.
2. The escrow KDF (LUKS2 argon2id, up to ~1 GiB) could OOM-kill zot. Fixed with the memory
   pre-check plus `systemd-run --scope -p OOMScoreAdjust=1000`.
3. One PR carries three deliveries. Recorded as a User-Challenge, with an alert grace of ≥2 rows
   applied in-PR.
4. Escrow `stale`/`none` did not page. The predicate's arm (B) now fires on any value other than
   `ok`.

The CTO also confirmed:

- the sentinel gate's recovery depends on the NIC guard, extended per the advisor to the
  late-mount path
- `--pull=never` concerns are moot after the simplification
- user_data headroom is 16,828 B
- `$$(` is correctly in the guard's class

Scoped advisor (plan Step 4.5): the NIC-guard recovery-arm gap. It is adopted as Phase 6.3 and
Guard 4 row 4.

Product/UX Gate: NONE. There is no UI surface in Files to Create or Files to Edit, and the
mechanical override did not fire. Legal/GDPR: no regulated-data surface. The 1b marker was
designed to emit no personal identifier, which is the only personal-data-adjacent decision here.

## Test Scenarios

- The suite set is derived mechanically per changed path, then unioned. For example,
  `git grep -ln 'ci-deploy.sh'` alone yields 114 files, so run the union and not a directory
  guess.
- Run `scripts/test-all.sh --capacity` first. Use the lock-queued form, with the rc written to a
  file. Never `wait $!`.
- `zot-config-deadlines.test.sh` fails closed without a docker daemon. It does the same on main,
  so it is not a defect, and it must be noted, not "fixed".
- Behavioural evaluation over spelling: the Phase 4 rendered-line evaluation, the Phase 5
  predicate evaluator, and the Phase 7 vocabulary reachability.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it in before requesting
  deepen-plan or `soleur:work`.
- A **future** ENFORCE flip makes the per-deploy anonymous public-ghcr.io pull a deploy blocker.
  The image is pruned before every verify (measured). The ENFORCE flip must cite the #8037
  probe's PASS, and must decide on pinning the verifier image locally first. That is recorded in
  the ADR-087 amendment.
- The sentinel must be written **inside** the `findmnt = /dev/mapper/registry` conjunction,
  after the mount. A write outside it lands on the root disk and **defeats** the gate. That is
  why Guard 4 has a reorder row.
- Without the NIC-guard `.State.Running` arm, the sentinel gate turns a late-mount reboot into a
  **permanent** zot outage (advisor finding). The arm ships in the same commit as the gate.
- The PATH fix changes observable behaviour: the inherited PATH is now appended. The heartbeat
  suite's render seam must be read before editing, per Phase 4.1.
- #8386 and #8408 take no closing keyword. Their probes never auto-close, and a human reads V7.
- The escrow cron's `doppler run` injects every soleur-registry secret into the escrow script's
  env, as the heartbeat's does. Keep the script free of env-overridable command names (the #7761
  class): use literal paths for `cryptsetup`, and the same literal PATH preamble as the heartbeat.
