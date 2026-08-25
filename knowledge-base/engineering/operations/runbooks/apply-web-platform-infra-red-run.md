# Runbook — a RED `Apply web-platform infra` run (`manual-rerun`)

What to do when the ops mailbox receives **"Apply web-platform infra: run did NOT complete —
production infrastructure may be un-applied"**, or when you notice the workflow is red on `main`.

- **Dispatch target:** `apply-web-platform-infra.yml`, `apply_target=manual-rerun`
- **Confirm token:** none — `manual-rerun` is the historical escape hatch and takes only a `reason`
- **Irreversible:** no. It re-runs the ordinary per-merge apply against `main`'s current state
- **Who sends the email:** the `notify-apply-failure` job in the same workflow (#7586)
- **ADR:** none. The decision content lives in that job's own header

Written because the recovery lever the email prescribes had no runbook entry while every sibling
`apply_target` in that workflow had one (#7659 F4). An agent — or a person — who learns the apply
pipeline is red from CI status alone had nothing to follow.

## Read the email first. It is not a form letter.

Four of its lines are computed per run and each one changes what you should do.

| Line | What it means |
|---|---|
| **Outcome: preflight `X`, apply `Y`** | `preflight failure` means the run stopped **before applying anything** — nothing is half-applied. `apply cancelled` means it was stopped or ran out of time, possibly part-way through. |
| **Failing step** | The step the jobs API reported as `failure`/`cancelled`. `unresolved` means either the run never reached a named step (a preflight failure) or the jobs API could not be read. |
| **What to do** | Three arms: preflight-failed, cancelled, failed. Read it — a re-dispatch is a retry, not a diagnosis. |
| **Is uptime alerting still watching the servers?** | The one line that can require action **before** you re-run. See below. |

## The heartbeat line is the part that is time-sensitive

The apply job unpauses Better Stack heartbeat monitors to measure a real beat, then re-pauses them.
If the run is cut between those two points, a monitor is left switched **ON with nothing reporting
to it**, and it will raise a false page when its grace window expires — at whatever hour that is.

| The email says | Do this |
|---|---|
| the sweep **ran and finished** | Nothing. Re-run when convenient. |
| the sweep **FAILED** | **Act now, before re-running.** Open Better Stack → Monitors → Heartbeats, find each id from the run log, press **Pause** on each. A re-run will NOT clear this: the arming gate skips any monitor that is already switched on, so it leaves them exactly as they are. |
| the sweep was **CUT OFF part-way** | Same as FAILED. This is the state where a live-and-unfed monitor is most likely. |
| we **could not find out** | Open the run page, find the **Heartbeat re-pause sweep** step. If it is red or absent, check Better Stack as above. |

The ids are in the run log, and in the annotation
`::notice::heartbeat-repause-sweep armed=N repaused=N failed=N outcome=…`. Retrieve it without
opening the web page with:

```bash
gh api "repos/jikig-ai/soleur/actions/runs/<run-id>/jobs" --jq '.jobs[]|select(.name=="apply")|.id'
gh api "repos/jikig-ai/soleur/check-runs/<job-id>/annotations" --jq '.[]|select(.message|test("heartbeat-repause-sweep"))|.message'
```

`outcome=` is one of exactly four values: `noop` (nothing was ever switched on — the common case),
`repaused` (all clear), `partial` (at least one is still live — act), `mint-unreadable` (the sweep
could not get a Better Stack credential and attempted nothing — act, and the ids are in the
`::error::` beside it).

## Re-running

**Easiest, no tools needed.** Open the run link in the email and press **Re-run failed jobs** at the
top right.

**Or as a form.** Repository → **Actions** → **Apply web-platform infra** → **Run workflow** →
`apply_target: manual-rerun`, fill in `reason`.

**Or from a terminal**, if you have the GitHub CLI signed in with `workflow` scope:

```bash
gh workflow run apply-web-platform-infra.yml --ref main \
  -f apply_target=manual-rerun \
  -f reason='re-run after a non-green apply'
```

It holds the fleet-wide apply mutex (`terraform-apply-web-platform-host`) for up to 47 minutes in
the worst case, so an emergency dispatch issued at the same time will queue behind it.

## Do NOT fire this on these

| Symptom | Meaning | What to do instead |
|---|---|---|
| The email says the sweep FAILED | A monitor is switched on with nothing feeding it | Pause it in Better Stack **first**. `manual-rerun` cannot re-pause it — `arm_one` no-ops any monitor that is not `paused`. |
| `preflight failure` | The kill switch or the pre-flight check refused | Read the `preflight` job. A re-run repeats the refusal. |
| Only a `vector.toml` / `journald-soleur.conf` change needs to land | The whole-plan apply is blocked by unrelated drift | [`vector-redeliver`](vector-redeliver.md) |
| A host needs replacing | Out of scope for the per-merge apply | The dedicated `*-host-replace` target and its own runbook |
| No email arrived and the run is red anyway | The run was cancelled at RUN level, or it was a non-`manual-rerun` dispatch | Both are recorded uncovered residuals (6 of the last 60 runs) in the `notify-apply-failure` header. Re-run by hand. |

## After it succeeds

- The workflow is green on `main`.
- The `Heartbeat re-pause sweep` step reports `outcome=noop` (nothing was left unconfirmed).
- No further ops email arrives; there is deliberately **no** green-again email (deferred to a
  repo-wide `workflow_run` watcher).
