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

## Zero jobs and no email: the file itself was refused

If the run page shows **0 jobs** (conclusion `startup_failure` on a dispatch, `failure` on a
push) and `gh run view` says only "This run likely failed because of a workflow file issue",
nothing below applies — no step ran, so the `notify-apply-failure` email never fires. GitHub
refused the workflow file: either it is over the 512,000-byte limit or it does not parse. Run
`bun test plugins/soleur/test/workflow-file-size.test.ts` and `actionlint` on the file; the size
gate's failure text names the overage and the relocation precedent
(`apply-web-platform-infra-job-rationale.md`). #8361 is the measured instance.

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

It holds the fleet-wide apply mutex (`terraform-apply-web-platform-host`) for up to 59 minutes in
the worst case, so an emergency dispatch issued at the same time will queue behind it.

Cloudflare provider calls now retry API 5xx up to ~8 min per request (#10643), so a plan step red
on `received gateway timeout response (HTTP 504)` post-change means the upstream degradation
outlasted that budget — re-running once Cloudflare settles is the documented remedy.

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

## An apply delivery gap issue (label `apply-delivery-gap`)

**What it is.** The issue titled "infra: apply delivery gap - trigger-file change not applied" is filed by the
`Apply Delivery Gap Follower` workflow (`scripts/apply-delivery-gap.sh`). Both apply workflows share one concurrency
group that keeps a single pending run, so a second push can evict the first: the evicted run ends `cancelled`, usually
with zero jobs, and no email is sent. The issue lists every such push from the last 7 days that no later run of the
**same** workflow applied (table: workflow, push SHA, run, class, minutes since cancel, latest later run of this workflow, any outcome, which is not proof of delivery). It
is detection only: it applies nothing and starts nothing. The body prints one dispatch command per workflow that has rows.

**Decision table** (same shape as "Do NOT fire this on these" above):

| Row says | Do this |
|---|---|
| class `evicted-before-start` | Run the printed command from `main`. It applies `main` HEAD, which covers every listed SHA of that workflow. |
| class `cancelled-mid-run` | Read the cancelled run first: state is possibly partial (the follower over-classifies a preflight-only run as mid-run). If the re-dispatch then goes red, use the heartbeat sweep section above before re-running. |
| "Latest later run" column shows a FAILED run | Read that run first. A failed run after an eviction is a different problem and `notify-apply-failure` already owns it. |
| a kill-switch commit sits between the row and HEAD | The printed dispatch applies HEAD **including** the change that commit deliberately skipped. Decide about that change first. |
| you cancelled the push on purpose because it was bad | A revert commit touching the trigger paths delivers it by descendant and the row clears itself. An operator-cancelled mid-run push correctly stays `cancelled-mid-run`. |

Always dispatch with `--ref main`. A dispatch from another ref applies that branch to production and leaves the gap open.

**Verification.** The issue closes itself on the next reconcile that sees every listed push delivered (a later run of the
same workflow, at the push or a descendant, whose `apply` job succeeded) with nothing in flight. For `deploy-fix` rows
also run `scripts/check-deploy-script-parity.sh` to confirm the host copy matches.

**Closing is not an acknowledgement.** The follower is stateless: while a row remains inside the 7-day window a new
issue is filed after you close this one. Comment on the issue rather than editing it: the body is rewritten on every
refresh. If the follower leaves a comment marked `apply-delivery-gap:aged-out`, no cancelled push remains inside the window
and none was seen delivered: verify delivery (the parity check above, or the latest apply run) and close the issue by
hand. `priority/p0-critical` is only ever added automatically; remove it by hand if the new gap is not mid-run.

**The degraded issue** ("infra: apply delivery gap follower degraded", label `apply-delivery-gap-degraded`, plus
`action-required`) means the follower could not finish a full read, so it cannot tell you the state. It never closes the
gap issue and never reports "no gap" on a partial read. The workflow run's last line names the reason:

| `::error::apply_delivery_gap_<reason>` | Meaning |
|---|---|
| `runs_list_failed`, `jobs_read_failed`, `compare_failed`, `malformed_response` | An Actions API read failed after retries, or returned an unexpected shape. |
| `run_window_truncated` | More than 10 pages of runs fall inside the 7-day window (the apply workflows are running far above their usual rate). |
| `trigger_run_not_visible` | The run that fired the follower was not yet listed as completed after 3 reads. |
| `api_budget_exceeded` | More than 150 jobs and compare reads were needed in one reconcile. |
| `issue_list_failed`, `issue_write_failed`, `label_failed` | The issue API failed; no issue can be written, so the red run is the only trace. |
| `degraded_upsert_failed` | The follower could not even file the degraded issue. |
| `bad_input` | A configuration error in the workflow (rejected before any API call). |

The next step is always `gh run rerun <run-id> --failed`: every reconcile is a full stateless read, so a re-run is safe.
The next fully complete reconcile closes the degraded issue by itself. The 12 h `scheduled-terraform-drift` check remains
the independent backstop.

**Flip-evidence count (read-only).** The decision to build the deferred fixes (merge the two workflows, or add a
re-dispatch follower) needs a count of distinct pushes, not runs. Counting unit: the **SHA**. The same SHA can appear in
several issues (an issue closed by hand is re-filed), so count distinct SHAs:

```bash
gh issue list --author "github-actions[bot]" --state all --limit 500 \
  --json number,createdAt,title,body,comments \
  --jq '[.[] | select(.title | startswith("infra: apply delivery gap - "))]'
```

(Some `gh` versions only match the spelling `app/github-actions`; if the list comes back empty, try that one.)
Add the `::notice title=apply-delivery-gap::row workflow=<key> sha=<40hex> class=<c>` lines of the follower's runs (log
retention is about 90 days, so also read the issue bodies and comments). Row ages come from the close comment's
"minutes from cancel to delivery". The bar is recorded in ADR-270 (2026-10-23 addendum).
