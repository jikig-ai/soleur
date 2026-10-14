---
title: "fix(infra): remove dead inngest pause/resume calls from the bootstrap upgrade drain"
type: fix
date: 2026-09-30
slug: fix-inngest-bootstrap-dead-pause-resume
branch: feat-one-shot-9219-inngest-dead-pause-resume
issue: 9219
closes: 9219
priority: p3
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix(infra): remove dead inngest pause/resume calls from the bootstrap upgrade drain

## Enhancement Summary

**Deepened on:** 2026-09-30. The fan-out was proportionate, not all-agents, because this is a
p3 dead-code removal of about 6 lines.

- **Gates:** 4.6 User-Brand Impact, 4.7 Observability (probe-verb gate rc=0), 4.8 no PAT
  shapes, and 4.11 `lint-guard-contract.py` all passed. These were not applicable: 4.5
  network-outage, 4.55 downtime, 4.9 UI and 4.10 encryption (no new store or connection).
- **Agents:**
  - a verify-the-negative and self-audit pass
  - `observability-coverage-reviewer`
  - `test-design-reviewer`
  - `git-history-analyzer` (attribution claims)

### Key improvements

1. **The observability claim was corrected.** The success-path bootstrap log lines never leave
   the host: `ci-deploy.sh` redirects the bootstrap's stderr to
   `/tmp/inngest-bootstrap-stderr.log`. Only a failure tail reaches Better Stack and
   deploy-status. The block now says so, and cites layer 6 (workflow run log) and layer 3
   (Vector).
2. **The guard floor was hardened.** It went from "non-empty" to "`start` must be found".
   After the edit, both surviving verbs come from the literal-path spelling, so a non-empty
   check could not detect a broken `INSTALL_PATH` branch. Rows 5 (heredoc literal path) and 6
   (unquoted variable) were added. All rows were re-validated.
3. **The mutation-run procedure is now concrete.** Copy `infra/`, run an instrument control,
   and read the guard's own PASS/FAIL line rather than the suite exit code.
4. **Six negative claims were confirmed by grep:**
   - no `.tf` coupling
   - no other test asserts the removed lines
   - the provenance sidecar and the test are not image carriers
   - `DRAIN_SLEEP_SEC` has no setter
   - no alert is keyed on the removed log strings
   - the staleness suites do not parse the edited provenance row

   One stale rationale in the Cut List was fixed.
5. **Attribution was verified live** (`gh`, `git log -S`):
   - The pause call came from commit `8e170b7eec` (#3960).
   - The "resume still present" assertion came from `d844b41d48` (#4652, R2).
   - The dead-call annotation came from `1cf0a76aa0` in PR #9201.
   - `vinngest-v1.1.43` is merged into a freshly fetched `origin/main`. The worktree's local
     `main` ref is stale at `v1.1.25`, so compare against `origin/main`, never local `main`.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

The in-place upgrade block of the inngest bootstrap installer
(`apps/web-platform/infra/inngest-bootstrap.sh`) invokes two CLI verbs, `pause` and `resume`,
that no pinned inngest-cli version provides. Both were measured absent on v1.19.4 and v1.45.1
(`No help topic for 'pause'`, #7463 re-spike). Both calls are `|| log warn`-guarded, so they are
no-ops that emit a misleading `warn:` line on every in-place upgrade. The real upgrade behavior
is already: a `DRAIN_SLEEP_SEC` sleep, then binary download and replace, then the bootstrap's
guarded unit restart of `inngest-server.service`.

This plan **drops the dead calls** and keeps behavior otherwise identical. It rewrites the prose
so the script, the runbook and the provenance sidecar describe what actually happens, and it
replaces the one test assertion that currently *requires* the dead `resume` call with a
verb-allowlist guard. The new guard fails if any unmeasured CLI verb is invoked again.

One PR. Closes #9219. No production writes: we push no tags, dispatch no workflows and apply no
Terraform. We also edit no workflow files.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (measured 2026-09-30) | Plan response |
|---|---|---|
| Dead calls at "~lines 128-135 and ~1744" (issue body) | PR #9201's comment annotation moved them. `"$INSTALL_PATH" pause` is at line 137 and `"$INSTALL_PATH" resume` at line 1751, with the `sleep 2` before it at line 1750 | Cite content anchors, not line numbers (`cq-cite-content-anchor-not-line-number`) |
| Option A: "gate the block on `"$INSTALL_PATH" pause --help` succeeding" | The exit code of `inngest <unknown-verb> --help` was never measured. Only the stdout text `No help topic` was recorded (`phase0-respike-evidence.md` §`inngest pause`). A gate on an unmeasured exit code could pass vacuously. Even if a future CLI added `pause`, auto-engaging it on upgrade is the fail-dangerous mechanism ADR-078 rejected: a server-global freeze that darks every event-driven function if resume is lost | **Rejected.** Drop the calls (Option B) |
| "Editing inngest-bootstrap.sh triggers an auto-mint on merge" (brief) | **Confirmed.** `inngest-bootstrap.sh` is a `cp`-staged carrier (`build-inngest-bootstrap-image.yml` staging block; the carrier extractor in `.github/scripts/mint-inngest-bootstrap-tag.sh`). On push to main: mint `would-mint` → next `vinngest-v*` tag (current max merged tag is `v1.1.43`) → build → `bump-cloud-init-pin` job opens the pin-bump PR for `cloud-init.yml` + `cloud-init-inngest.yml`. It auto-merges when tag == target, mirror ok and provenance bound (`bump-inngest-bootstrap-pin.sh` auto-merge arm) | No manual tag or pin action in this PR. Do **not** edit `cloud-init*.yml` |
| (not in brief) PR-time CI reaction | **Guard A** (carrier coherence, `cloud-init-inngest-bootstrap.test.sh`, `deploy-script-tests`) is **red by construction** on any PR that changes a baked carrier: `FAIL: GuardA: every baked carrier is byte-identical at vinngest-vX (drifted: inngest-bootstrap.sh)`. #9081 (open) tracks the PR-context exemption. `deploy-script-tests` is **not** in the `CI Required` ruleset (measured via `gh api …/rulesets`). Precedent: PR #9201 merged with exactly this row red | Ship-time merge criterion: see "CI expectations" below. This is the one expected red; everything else must be green |
| (not in brief) post-merge window | ADR-232 §"Prerequisite before Guard A becomes required (#9081)": after a carrier-changing merge, main's Guard A/AC6 stay red until mint, build and bump land, and PRs based on that main inherit the red | Documented transient. Nothing to do in this PR |
| Runbook says the upgrade "pauses → drains → restarts → resumes (~5s downtime)" (`inngest-server.md`, inngest-cli version bump step 3) | False: the verbs never existed | Fix the prose in the same PR |
| `sleep 2` wall-clock budget (#8562 impl-notes count `DRAIN_SLEEP_SEC 2 s + sleep 2 = 4 s` toward `TimeoutStartSec=65min`) | Removing `sleep 2` only loosens the budget by 2 s. `cloud-init-inngest.yml` does not restate the 4 s figure (grep: no `DRAIN_SLEEP`/`own sleeps`) | No edit. The archived impl-notes are a point-in-time record |

## Research Insights

**Premise Validation.** #9219 is OPEN and no PR closes it yet (`gh issue view 9219`). Draft PR
#9266 is an empty WIP. Both cited call sites exist on this branch. Both verbs were measured
absent (`knowledge-base/project/specs/feat-one-shot-7463-inngest-cli-pin-bump/phase0-respike-evidence.md`
§"`inngest pause` — absent on BOTH endpoints"). The auto-mint premise holds (table above). ADR
corpus check: ADR-078 §"Why lease over native `inngest pause`/`resume`" already rejected native
pause as a drain mechanism for crons. Our change aligns with that ruling and does not reverse it.
No stale premise.

**Property List (Phase 0.6b).**

- P1: The bootstrap invokes no inngest-cli verb that the pinned binary lacks. No call fails
  silently and no misleading `warn:` line is emitted on upgrade.
- P2: The script, runbook and provenance sidecar describe the upgrade path truthfully. They say:
  sleep-only delay, then binary replace, then unit restart. Nothing is paused and nothing is
  resumed.
- P3: A CI assertion goes red if an unmeasured CLI verb is reintroduced. It replaces the current
  assertion, which pins the dead `resume` call as *required*.
- P4: Behavior is otherwise unchanged. The `DRAIN_SLEEP_SEC` sleep and its env override, the
  upgrade-detection branch, the restart and the `upgrade complete` log line all stay.

**Cut List.**

- `pause --help` capability gate → would buy "engage pause if a future CLI adds it". That is not
  in the property list. No pinned version has the verb, the exit code is unmeasured (a vacuous
  gate is likely), and auto-engaging a server-global freeze is the ADR-078-rejected hazard. **Cut.**
- Removing `DRAIN_SLEEP_SEC` entirely → changes upgrade timing. That is not asked for (the issue
  says "document the drain as sleep-only"), even though nothing sets the variable. **Cut.** It is
  recorded in Alternatives and in `decision-challenges.md`.
- Scanning every infra script for unmeasured verbs → P1 is scoped to the bootstrap, the only
  file with CLI-verb calls beyond `start` in unit strings (grep of `apps/web-platform/infra`,
  `scripts`, `.github`: other hits are test fixtures for `start`). **Cut.**

**Relevant files.**

- `apps/web-platform/infra/inngest-bootstrap.sh`, with these anchors:
  - header contract comment ("On version bump, sleeps DRAIN_SLEEP_SEC then restarts. NOTE: the `inngest pause`/`resume` calls below are DEAD")
  - `DRAIN_SLEEP_SEC="${DRAIN_SLEEP_SEC:-2}"`
  - upgrade-detection block ("# Detect in-place version upgrade" through `sleep "$DRAIN_SLEEP_SEC"`)
  - the ExecStart comment ("the `inngest pause` drain never engages — the pause call above is a dead call")
  - the restart comment ("The upgrade-drain (best-effort; dead call on current versions) above runs before the binary replace; this restart subsumes the start and the resume below runs after.")
  - the resume block ("# Resume from upgrade pause (if any)" through `log "upgrade complete: …"`)
- `apps/web-platform/infra/inngest.test.sh`, the assertion "upgrade-drain resume command still
  present (pause/resume pairing intact)" and its comment ("The upgrade-drain resume must still
  run after the restart (R2 …)").
- `apps/web-platform/infra/inngest-cli.provenance.md`, re-verification table row
  "`inngest pause` drain verb".
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`, sentence "pauses → drains →
  restarts → resumes (~5s downtime on loopback)".
- Who runs the upgrade block: only an **in-place** bootstrap on a host where
  `inngest-server.service` is already active at an older CLI version. That is the
  `ci-deploy.sh` `inngest)` case (extracts the bootstrap from the pinned image and runs it as
  root). A fresh host (cloud-init, host replace) has no active unit, so `UPGRADE_FROM` stays
  empty and the block is skipped. That matches the issue's note that the dedicated host's
  flip path is a host replace.

**Institutional learnings applied.**

- `2026-07-18-forbiddance-drift-guard-encodes-pre-refactor-threat-model.md`: allowlist the good
  form (measured verbs) rather than blacklist the removed one. This drives the guard shape.
- `2026-09-07-the-guard-i-wrote-died-on-the-case-it-was-written-to-catch.md`: under
  `set -euo pipefail`, a `$(grep …)` capture exits 1 on no-match and aborts the suite on the very
  case it detects. Captures carry `|| true`. Run `scripts/lint-shell-capture-exit.py`
  (via `scripts/lint-shell-capture-exit.test.sh`).
- `best-practices/2026-07-07-refactoring-a-shape-a-drift-guard-greps-breaks-the-guard.md` and
  `best-practices/2026-06-03-grep-over-markdown-marker-tests-line-wrap-and-vacuous-alternation.md`:
  strip comment lines before extracting, because prose carries backticked commands.
- `2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md`: check every
  extracted member, not mere presence. A second invocation must be checked, not masked by a
  compliant first one. The subset check does this over the whole extracted set.
- `cloud-init-inngest-bootstrap.test.sh` header: never `producer | grep -q` under pipefail
  (SIGPIPE false negative). Feed readers a variable or here-string.

**Related issues/PRs.** #7463 (pin bump and re-spike, source of the measurement). PR #9201
(comment-only dead-call annotation, merged with the Guard A red precedent). #9081 (Guard A
PR-context exemption, open). ADR-232 (pin bumps authored by the publish workflow). ADR-078
(lease over native pause).

**CLAUDE.md / AGENTS conventions.** `cq-cite-content-anchor-not-line-number`,
`cq-assert-anchor-not-bare-token`, `hr-prod-host-config-change-immutable-redeploy` (satisfied:
the change ships through the image pipeline and no host is touched by hand), and
`hr-menu-option-ack-not-prod-write-auth` (no prod writes).

**CLI verification (#2566 gate).** This plan prescribes no new CLI invocation. It removes two.
The absence of `pause`/`resume` is sourced from `phase0-respike-evidence.md` §"`inngest pause`".
The retained `start`/`version` verbs are already in production use (ExecStart and the
server-probe `cli_version` read).

**Functional overlap (Phase 1.5b).** Not run. This is a repo-internal infra dead-code removal
with no plugin capability, so community registries cannot overlap. External research was also
skipped: local context is complete.

## Proposed Solution

### 1. `apps/web-platform/infra/inngest-bootstrap.sh` (carrier edit, which triggers the auto-mint on merge)

- **Upgrade-detection block.** Delete the `"$INSTALL_PATH" pause … || log "warn: pause command failed (continuing)"` line.
  Keep `sleep "$DRAIN_SLEEP_SEC"`. Reword the log line so it no longer claims a pause, for example:
  `log "upgrade detected: $UPGRADE_FROM → $INNGEST_CLI_VERSION; ${DRAIN_SLEEP_SEC}s settle delay before binary replace"`.
  The log line and the comments call the sleep a **settle delay**, not a drain, because nothing
  is drained: the server keeps accepting work until the restart (advisor consult, Phase 4.5).
  The variable keeps its name `DRAIN_SLEEP_SEC`. It has no known setter (`git grep` finds only
  the bootstrap default and archived notes), and it is kept only to avoid a behavior change
  beyond the issue's scope.
  Shrink the block comment to two lines: "no pause/resume verb exists (measured absent on
  v1.19.4 and v1.45.1, #7463/#9219); the sleep is a settle delay, not a drain — the server
  keeps accepting work until the restart, and a host replace never enters this block". Use the
  exact phrase `not a drain` on one physical line (no wrap inside it), because AC4's drain
  check excludes it.
  Drop the inline `# allow in-flight events to drain to SQLite` on the `sleep` line, and the
  "Wall-clock downtime per in-place upgrade: ~5s" claim.
- **Resume block.** Delete the `sleep 2` (its only purpose was to wait before `resume`) and the
  `"$INSTALL_PATH" resume … || log warn` line. Keep the `if [[ -n "${UPGRADE_FROM:-}" ]]` branch
  with `log "upgrade complete: $UPGRADE_FROM → $INNGEST_CLI_VERSION"` as the upgrade's
  completion marker. Replace the "Resume from upgrade pause" comment.
- **Comment sweep.** Fix every stale reference, found by content anchor (Kieran enumerated
  these with `grep -nE '[Dd]rain|DRAIN|DEAD|no-op on tested|~5s'`):
  - header contract ("On version bump, sleeps DRAIN_SLEEP_SEC then restarts. NOTE: … DEAD on
    every tested version … the drain is sleep-only"). Replace it with "on version bump, a
    DRAIN_SLEEP_SEC settle delay (no pause/resume verb exists), then binary replace, then
    restart".
  - `DRAIN_SLEEP_SEC`'s own comment ("In-place upgrade drain. Override via env …"). Reword it to
    "In-place upgrade settle delay (DRAIN_SLEEP_SEC: the name is historical — nothing is drained)". Keep the literal `DRAIN_SLEEP_SEC` on that physical line, because AC4's drain check excludes lines carrying it. Keep the
    override note, or drop the event-rate rationale, which presumed a drain.
  - upgrade-block comment ("The `pause`/`resume` calls below are a no-op on tested versions …
    ~5s"), covered above.
  - "upgrade-drain stay inside the guard above". Reword it to "upgrade settle delay".
  - ExecStart comment ("the `inngest pause` drain never engages — the pause call above is a
    dead call on current versions"). Remove that clause and keep the doppler-MainPID note.
  - restart comment ("The upgrade-drain (best-effort; dead call on current versions) above runs
    before the binary replace; this restart subsumes the start and the resume below runs
    after."). Reduce it to "the settle delay above runs before the binary replace; this restart
    subsumes the start".
  - resume-block comment ("Resume from upgrade pause (if any) — dead call …"), covered by the
    resume-block bullet.
  - Leave alone: the unrelated `#6258 idle-drain` / "DRAINS idle conns" (Postgres pool) prose,
    and the line-204 "a DEAD" (heartbeat monitor) prose.
- **No other change.** The diff adds and removes no systemd start/restart line (the
  `systemctl`-plus-`start`/`restart` shape), so the `ci-deploy.test.sh` inngest-server
  start-writer inventory is not triggered. Do not touch the flip-guard restart block.

### 2. `apps/web-platform/infra/inngest.test.sh` (not a carrier, no mint)

Replace the assertion "upgrade-drain resume command still present (pause/resume pairing
intact)" and its R2 comment with the verb-allowlist guard (Guard 1 below). The form is
subset plus non-empty, not exact set identity: removing the unrelated `version` probe must not
turn the suite red (plan review: DHH, CTO, simplicity). Sketch (the work phase first confirms
the extractor output on the edited file):

```bash
# #9219: the bootstrap may invoke ONLY inngest-cli verbs measured to exist on the pinned
# binary. `pause`/`resume` were measured ABSENT on v1.19.4 and v1.45.1 ("No help topic",
# phase0-respike-evidence.md) and were removed. Add a verb to the allowlist ONLY after
# recording a measurement in inngest-cli.provenance.md. An empty extraction (a broken
# extractor) is RED, so the guard cannot pass vacuously.
echo ""
echo "--- inngest-cli verb allowlist (#9219) ---"
INNGEST_VERB_ALLOWLIST_RE='^(start|version)$'
BOOTSTRAP_CODE_LINES=$(grep -vE '^[[:space:]]*#' "$BOOTSTRAP_SH" || true)
INNGEST_VERBS_USED=$(grep -oE '(\$INSTALL_PATH|\$\{INSTALL_PATH\}|/usr/local/bin/inngest)"?[[:space:]]+[A-Za-z][A-Za-z0-9_-]*' <<<"$BOOTSTRAP_CODE_LINES" \
  | awk '{print $NF}' | sort -u || true)
INNGEST_VERBS_UNMEASURED=$(grep -vE "$INNGEST_VERB_ALLOWLIST_RE" <<<"$INNGEST_VERBS_USED" || true)
# Floor: `start` (the ExecStart verb) must be found. The server cannot run without it, so it
# survives any legitimate refactor, and a broken extractor cannot pass.
INNGEST_HAS_START=$(grep -cx start <<<"$INNGEST_VERBS_USED" || true)
assert "bootstrap invokes only measured inngest-cli verbs (allowlist: start, version; add one only with a provenance measurement) — no pause/resume (#9219) (got: $(tr '\n' ' ' <<<"$INNGEST_VERBS_USED"); unmeasured: $(tr '\n' ' ' <<<"$INNGEST_VERBS_UNMEASURED"))" \
  "[[ \"\$INNGEST_HAS_START\" == 1 && -z \"\$INNGEST_VERBS_UNMEASURED\" ]]"
```

(Measured on the pre-edit file, the extractor returns exactly `pause`, `resume`, `start`,
`version`. After the edit it must return `start`, `version`. The description interpolates the
found verbs at call time because `assert` prints only the unexpanded condition. That was a
CTO and Kieran finding, and it mirrors how Guard A prints `drifted:`.)

**Pre-validated at plan time (2026-09-30, deepen pass).** The final sketch was run as a
standalone script under `set -euo pipefail`:

| Input | Result |
|---|---|
| Current bootstrap | FAIL (`unmeasured: pause resume`) |
| Two dead lines deleted | PASS |
| Row 1 (re-added `pause`) | FAIL (`unmeasured: pause`) |
| Row 2 (empty file) | FAIL (floor) |
| Row 3 (`${INSTALL_PATH} resume`) | FAIL |
| Row 4 (comment line) | PASS |
| Row 5 (heredoc `/usr/local/bin/inngest pause`) | FAIL |
| Row 6 (unquoted `$INSTALL_PATH resume`) | FAIL |
| Added `"$VECTOR_INSTALL_PATH" validate` | PASS |

The last row refutes a test-design-reviewer P2 that the regex false-matches
`$VECTOR_INSTALL_PATH`. The substring `$INSTALL_PATH` does not occur in `$VECTOR_INSTALL_PATH`.
The work phase re-runs these against the real edit.

### 3. `apps/web-platform/infra/inngest-cli.provenance.md` (matches the `inngest*` path filter but is not `cp`-staged, so the mint decision is unaffected)

Amend the row "`inngest pause` drain verb" verdict so it records that the dead calls were
removed and the upgrade path is a settle delay with no drain (#9219). Keep the measurement (ABSENT on both endpoints)
verbatim. Only the "follow-up issue" tail changes.

### 4. `knowledge-base/engineering/operations/runbooks/inngest-server.md`

Replace "pauses → drains → restarts → resumes (~5s downtime on loopback)" with the truthful
sequence: a `DRAIN_SLEEP_SEC` settle delay, then binary replace, then the bootstrap's unit
restart. Nothing pauses, drains or resumes.

### Explicitly not touched

- `cloud-init.yml` / `cloud-init-inngest.yml`: pins are bumped by the bot. A comment edit would
  also change the rendered `user_data`.
- Any `.github/workflows/*` file (UNTRUSTED-CI split not needed).
- `ci-deploy.sh`.
- ADR-078 and ADR-100. Historical records: ADR-100's table row names #9219 as the follow-up
  and stays true as history.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| A. Gate on `"$INSTALL_PATH" pause --help` succeeding | Rejected. The exit code is unmeasured and no pinned version has the verb. Auto-engaging a server-global pause on upgrade is the ADR-078-rejected fail-dangerous mechanism (a lost resume darks every event-driven function) |
| B. Drop the calls, document sleep-only (**chosen**) | Smallest change. Behavior-identical except for 2 s less wall clock and no misleading `warn:` lines |
| C. B plus remove `DRAIN_SLEEP_SEC` (the sleep drains nothing, because the server keeps accepting) | Rejected for scope. The variable has no known setter, so removing it is safe. But it changes upgrade timing, which the issue did not ask for. No tracking issue: the honest docs make the trade-off visible, and there is no demand signal |
| D. Blacklist guard (`! grep '"$INSTALL_PATH" (pause\|resume)'`) | Rejected in favor of the allowlist. A blacklist guards only the removed mechanism (learning 2026-07-18) |
| E. Delete the old assertion and add no guard (the simplicity reviewer's option) | Rejected. The subset allowlist is about 6 lines and replaces an assertion that must go anyway. A reintroduced no-op verb is low-stakes, but the guard costs almost nothing, and DHH and the CTO both kept a guard |

## Does merging this alone mutate production?

No host or Terraform resource is mutated by this diff. The PR body's first line must say so.

- `apply-web-platform-infra.yml` fires on push to main for `apps/web-platform/infra/**`. That
  includes this diff's three infra files. No `.tf` input references them, though: there is no
  `file()`, `templatefile()` or `filesha256()` of `inngest-bootstrap.sh`, `inngest.test.sh` or
  the provenance sidecar (grep of `apps/web-platform/infra/*.tf`). So the run's plan is expected
  to be a no-op for this change.
- `mint-inngest-bootstrap-tag.yml` creates a `vinngest-v*` tag and dispatches the image build,
  and the build's bump job opens the pin-bump PR. These are release artifacts from the existing
  ADR-232 pipeline, not host mutations. The running host changes only when a later deploy runs
  the new image, and the behavior difference shows only on an in-place CLI-version upgrade.
- Removing `sleep 2` is safe for downstream consumers. The common, non-upgrade path never had
  it. `ci-deploy.sh`'s `verify_inngest_health` runs after the bootstrap on every path, so nothing
  can depend on those 2 s.

## CI expectations and merge criterion

- **Expected red, the only one:** `deploy-script-tests`, `cloud-init-inngest-bootstrap.test.sh`
  with `FAIL: GuardA: every baked carrier is byte-identical at vinngest-<pinned> (drifted: inngest-bootstrap.sh)`.
  This is by construction (#9081, ADR-232 §7). The check is not in the `CI Required` ruleset,
  and PR #9201 merged with the same row red.
- **Merge criterion:** every `CI Required` check is green. The failing shard's only `FAIL:`
  line is that Guard A row, naming `inngest-bootstrap.sh` alone. A second drifted carrier or
  any other FAIL blocks the merge. A known timing flake gets one re-run.
- **After merge:** the mint → build → pin-bump chain is automatic, and we take no action.
  Main's Guard A/AC6 stay red for that one publish cycle. If the 6-hourly `main-health-monitor`
  run lands inside that window, it may file `ci/main-broken`. Its closer retires its own tracker
  on the next green run, so this is expected, not a defect. A failed mint is reported, never
  re-dispatched by us: a dispatch is a production write.

## User-Brand Impact

- **If this lands broken, the user experiences:** a failed or stalled in-place inngest upgrade
  on the web host. For example, a syntax error in the bootstrap aborts `ci-deploy.sh`'s
  `inngest)` step, so scheduled crons and event-driven functions (Stripe-webhook CFO drafts)
  do not run until the next deploy. The mitigations: `bash -n` + shellcheck + the inngest suites
  in CI, and the change deletes code rather than adding control flow.
- **If this leaks, the user's data / workflow / money is exposed via:** no new exposure
  vector. The diff removes two no-op CLI calls and edits comments/docs. It touches no
  secrets, network binds, units or credentials.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff under apps/web-platform/infra/ deletes two failure-tolerant no-op CLI calls and a 2 s sleep and rewrites comments; no unit, bind, secret, or user-data surface changes, so no user-facing path can regress beyond the in-place-upgrade abort covered by bash -n/shellcheck/CI.`

## Observability

```yaml
liveness_signal:
  what: "none off-host on the SUCCESS path, accepted. The bootstrap's log() writes to stderr, and ci-deploy.sh's inngest) arm redirects it to the host-local file /tmp/inngest-bootstrap-stderr.log. So the upgrade detected (settle delay) and upgrade complete lines never reach journald, Vector or Better Stack. This path fires only on a rare in-place CLI-version upgrade, and this change removes lines rather than adding a signal. The off-host signal is the deploy outcome itself (see failure_modes), which is unchanged."
  cadence: "per deploy (the deploy-status outcome); the success-path lines are host-local only"
  alert_target: "existing deploy failure path only: deploy-inngest-image.yml run log + Better Stack ci-deploy FAILED line; no new alert"
  configured_in: "apps/web-platform/infra/ci-deploy.sh (inngest) arm: BOOTSTRAP_STDERR capture, final_write_state, logger -t ci-deploy); apps/web-platform/infra/vector.toml (Source 4 ci-deploy tag allowlist)"
error_reporting:
  destination: "layer 6 workflow run log (deploy-inngest-image.yml polls /hooks/deploy-status and prints reason=inngest_bootstrap_failed:<stderr_tail>) + layer 3 Vector to Better Stack (logger -t ci-deploy FAILED line with stderr_tail); both unchanged by this diff"
  fail_loud: "a bootstrap abort exits non-zero, so ci-deploy writes final_write_state 1 inngest_bootstrap_failed:<last 600 bytes of stderr>. The removed lines only ever emitted a misleading warn: pause/resume command failed and never gated anything."
failure_modes:
  - mode: "bootstrap syntax/logic regression from the edit aborts the in-place deploy"
    detection: "pre-merge: CI workflow run log (bash -n, shellcheck, inngest.test.sh, cloud-init-inngest suites). Runtime: layer 6 deploy-inngest-image.yml run log (reason=inngest_bootstrap_failed:<stderr_tail>) and layer 3 Vector ci-deploy FAILED line in Better Stack"
    alert_route: "PR checks (pre-merge); deploy workflow failure + Better Stack ci-deploy FAILED line (runtime)"
  - mode: "an unmeasured inngest-cli verb is reintroduced"
    detection: "CI workflow run log: the inngest.test.sh verb-allowlist assertion prints FAIL with the found verbs (Guard 1)"
    alert_route: "PR check deploy-script-tests"
  - mode: "post-merge auto-mint or bump fails, so the fix never reaches the image pin"
    detection: "CI workflow run log: mint-inngest-bootstrap-tag.yml stage-named ::error:: + Slack; main's AC6/Guard A stays red and main-health-monitor files ci/main-broken"
    alert_route: "Slack releases channel + ci/main-broken issue"
logs:
  where: "success-path bootstrap lines: host-local /tmp/inngest-bootstrap-stderr.log only (overwritten per deploy). Failure tail: deploy-status payload + Better Stack via Vector (ci-deploy tag). Mint/build/bump: GitHub Actions logs."
  retention: "host-local file until the next deploy; Better Stack plan retention; GitHub Actions default 90 days"
discoverability_test:
  command: grep -oF 'settle delay before binary replace' apps/web-platform/infra/inngest-bootstrap.sh
  expected_output: "settle delay before binary replace"
```

The discoverability probe checks the source. The honest runtime answer is that the success
lines are host-local. Adding a `logger -t ci-deploy "INNGEST_UPGRADE: …"` line in `ci-deploy.sh`
was considered and declined: it would add a new signal to a file this PR explicitly does not
touch, for a rare path whose failure is already visible off-host (observability-coverage-reviewer,
deepen pass).

## Guard Contract

### Guard 1 — inngest-cli verb allowlist (inngest.test.sh)

**Property.** Every inngest-cli invocation in `inngest-bootstrap.sh` code (non-comment lines)
uses a verb from the measured set {`start`, `version`}, and at least one invocation is found
(no vacuous pass).

**Assembly.** The chokepoint is the binary's two spellings in the script. Every CLI call must
flow through one of them:

- the `INSTALL_PATH` variable (`readonly INSTALL_PATH="/usr/local/bin/inngest"`), spelled
  `"$INSTALL_PATH"`, `$INSTALL_PATH` or `${INSTALL_PATH}`
- the literal absolute path `/usr/local/bin/inngest`: the ExecStart heredoc and the
  server-probe `timeout 10 /usr/local/bin/inngest version`

The comment-stripped file is the population. Two spellings are out of assembly, deliberately:

- a bare-PATH `inngest <verb>` spelling. The script never relies on PATH for the binary; the
  only bare `inngest <word>` hits are inside log prose.
- invocations in other files. P1 is scoped to the bootstrap.
- three single-line-extractor blind spots, measured PASS by Kieran:
  - a line continuation (`"$INSTALL_PATH" \` with the verb on the next line)
  - a flag before the verb (`"$INSTALL_PATH" --json pause`)
  - an alias variable holding the path

  Review is the backstop for these.

A trailing inline comment on a code line is *not* stripped. That errs toward RED, never toward
a false pass.

**Mutation matrix** (cut from 8 rows to 4 at plan review; the suite's existing INSTRUMENT
SELF-TEST already covers a neutered `assert`):

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `"$INSTALL_PATH" pause >/dev/null 2>&1 \|\| true` inside the upgrade block | RED |
| 2 | Guard's own dispatch: run the block against an empty file so `INNGEST_VERBS_USED` is empty | RED (`start` floor) |
| 3 | Second member after a compliant first: keep `/usr/local/bin/inngest version` and add `${INSTALL_PATH} resume` on a later line | RED |
| 4 | Harness must-PASS: add a *comment* line `# "$INSTALL_PATH" pause was removed (#9219)` | PASS (comment lines are stripped) |
| 5 | Literal-path spelling with a forbidden verb, inside a heredoc: `/usr/local/bin/inngest pause` | RED |
| 6 | Unquoted variable spelling: `$INSTALL_PATH resume` | RED |

**Anchor.** The allowlist regex lives in the same file as the assertion, so one diff can widen
both. The backstop is its comment: a new verb requires a measurement in
`inngest-cli.provenance.md`, and review sees the edit. This is consistency, not integrity, and
that is adequate for an honest-mistake threat.

Run the rows by hand in the work phase. Do not commit them as a battery:

1. Copy the whole `apps/web-platform/infra/` directory to scratch. `BOOTSTRAP_SH` is derived
   from the suite's own `SCRIPT_DIR`, and about 50 other rows read it.
2. Run the unmutated copy first and confirm it exits 0. That is the instrument control.
3. Apply each mutation to the copy's `inngest-bootstrap.sh` and run the copy's `inngest.test.sh`.
4. Read the verdict from the specific `PASS:`/`FAIL: bootstrap invokes only measured
   inngest-cli verbs` line, never from the suite exit code. Row 2 reddens many unrelated rows.

(test-design-reviewer, deepen pass)
After the edit, only rows 1 and 3 exercise the `INSTALL_PATH` branch. No `$INSTALL_PATH`-spelled
call remains, so breaking that regex token alone would not redden anything.

## Plan Review Revisions

Panel: `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer` and a named
`cto` devex seat. The advisor consult ran at Phase 4.5.

**Applied (mechanical):**

- The guard went from exact set identity to subset plus a `start` floor (deepen pass), and it prints the
  found verbs.
- The mutation matrix went from 8 rows to 4. Row 2 lost its vacuous "break the token" option.
- The single-line-extractor blind spots are now listed.
- The false "install-time env interface" rationale was replaced.
- The sleep is called a "settle delay", not a drain, and the drain prose was swept with named
  anchors.
- AC4 and AC8 were widened. AC1 notes its expected exit code. AC5 and AC9 were merged.
- The CI section was de-duplicated. The `main-health-monitor` `ci/main-broken` window is noted,
  and the post-merge `gh` commands were cut.

**Taste, recorded in `specs/feat-one-shot-9219-inngest-dead-pause-resume/decision-challenges.md`:**

- Keep the guard rather than cutting it (simplicity).
- Keep the sleep rather than deleting it (DHH, advisor).

## Acceptance Criteria

- [x] AC1: no non-comment line of `apps/web-platform/infra/inngest-bootstrap.sh` invokes
  `pause` or `resume` through the binary. Check:
  `grep -vE '^[[:space:]]*#' apps/web-platform/infra/inngest-bootstrap.sh | grep -cE '(INSTALL_PATH\}?"?|/usr/local/bin/inngest)[[:space:]]+(pause|resume)'`
  prints `0`. Its exit 1 is expected, because `grep -c` exits 1 on zero matches.
- [x] AC2: the upgrade block still sleeps `DRAIN_SLEEP_SEC`. `grep -cF 'sleep "$DRAIN_SLEEP_SEC"' apps/web-platform/infra/inngest-bootstrap.sh`
  prints `1`, and the `DRAIN_SLEEP_SEC="${DRAIN_SLEEP_SEC:-2}"` default is unchanged.
- [x] AC3: the upgrade completion log survives. `grep -cF 'log "upgrade complete: $UPGRADE_FROM → $INNGEST_CLI_VERSION"' apps/web-platform/infra/inngest-bootstrap.sh`
  prints `1`, still inside an `if [[ -n "${UPGRADE_FROM:-}" ]]` branch.
- [x] AC4: no stale prose remains in the bootstrap. Three checks:
  - `grep -nE 'DEAD on every|dead call|no-op on tested|~5s|pausing for queue drain|resume below|Resume from upgrade pause|drain to SQLite' apps/web-platform/infra/inngest-bootstrap.sh`
    returns nothing.
  - `grep -nE '[Dd]rain' apps/web-platform/infra/inngest-bootstrap.sh | grep -vE 'DRAIN_SLEEP_SEC|idle-drain|DRAINS idle|not a drain'`
    returns nothing.
  - `grep -cF 'settle delay before binary replace' apps/web-platform/infra/inngest-bootstrap.sh`
    prints `1`.
- [x] AC5: diff scope. `git diff --name-only origin/main...HEAD` lists only:
  - `inngest-bootstrap.sh`, `inngest.test.sh` and `inngest-cli.provenance.md` (all under
    `apps/web-platform/infra/`)
  - `knowledge-base/engineering/operations/runbooks/inngest-server.md`
  - this plan, `specs/feat-one-shot-9219-inngest-dead-pause-resume/*`
  - pipeline-written files (`knowledge-base/INDEX.md`, session-state)

  It lists no `.github/workflows/*`, no `cloud-init*.yml` and no `ci-deploy.sh`. Also,
  `git diff origin/main...HEAD -- apps/web-platform/infra/ | grep -E '^\+.*systemctl[[:space:]]+(start|restart)'`
  returns nothing. If it does return a line, `ci-deploy.test.sh` becomes mandatory.
- [x] AC6: `inngest.test.sh` no longer contains the "upgrade-drain resume command still present"
  assertion. It contains the #9219 verb-allowlist assertion, which passes on the edited
  bootstrap. Mutation rows 1, 2, 3, 5 and 6 were each observed FAIL and row 4 PASS, read from the guard's own line on a scratch copy of `infra/`.
- [x] AC7: targeted ratchets pass locally:
  - `bash apps/web-platform/infra/inngest.test.sh`
  - `bash apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`
  - `bash apps/web-platform/infra/inngest-cli-staleness.test.sh` and `inngest-cli-staleness-mutation.test.sh`
  - `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`. For this suite the
    only permitted FAIL is the Guard A carrier row naming `inngest-bootstrap.sh`.
  - `bash -n` and `shellcheck` on `inngest-bootstrap.sh` and `inngest.test.sh`
  - `bash scripts/lint-shell-capture-exit.test.sh`
  - `bash plugins/soleur/test/fixture-relative-assert.test.sh`, with no baseline row change. If
    a row does change, regenerate with `--write-baseline` in the same commit, with a stated reason.
- [x] AC8: the runbook sentence and the provenance row are corrected. Each of these prints `0`:
  - `grep -c 'pauses → drains → restarts → resumes' knowledge-base/engineering/operations/runbooks/inngest-server.md`
  - `grep -c '~5s downtime on loopback' knowledge-base/engineering/operations/runbooks/inngest-server.md`
  - `grep -c 'follow-up issue, not an upgrade regression' apps/web-platform/infra/inngest-cli.provenance.md`
- [ ] AC9: the PR body's first line says that merging this mutates no host or Terraform
  resource (see "Does merging this alone mutate production?"). The body carries
  `Closes #9219`, and it states the expected Guard A red and the automatic post-merge
  mint → bump chain, so the reviewer and ship do not mistake either for a defect.

## Test Scenarios

- Given the edited bootstrap, when `inngest.test.sh` runs, then the allowlist assertion passes.
  The extracted verbs are `start` and `version`.
- Given a scratch copy with `"$INSTALL_PATH" pause` re-added, when the suite runs against it,
  then the allowlist assertion is RED. The same holds for matrix rows 2, 3, 5 and 6.
- Given a comment line mentioning `"$INSTALL_PATH" pause`, when the suite runs, then it still
  passes (matrix row 4).
- Given an in-place upgrade (the service is active and the version file differs), when the
  bootstrap runs, then it logs `settle delay`, sleeps `DRAIN_SLEEP_SEC`, replaces the binary,
  restarts the unit, and logs `upgrade complete`. No `warn: pause/resume command failed` line
  appears. This scenario is verified by reading the code path (no suite executes the bootstrap
  end to end), backed by `bash -n` and shellcheck.
- Given a fresh host (the service is not active), when the bootstrap runs, then `UPGRADE_FROM`
  stays empty and neither the sleep nor the `upgrade complete` log runs. This path is unchanged.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is an infrastructure/tooling change: dead-code
removal in an infra bootstrap script, plus docs.

## Open Code-Review Overlap

None. No open `code-review` issue body references `inngest-bootstrap.sh`, `inngest.test.sh`,
`inngest-cli.provenance.md` or `runbooks/inngest-server.md` (87 open issues checked).

## Dependencies & Risks

- **CI-reading risks** (Guard A red, flakes, mint failure) are covered once, in "CI
  expectations and merge criterion".
- **No dependency** on #9081 (the Guard A exemption). This PR merges under today's non-required
  status, like #9201.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6. This one is filled (`none` + scope-out
  reason, because `apps/*/infra/` is a sensitive path).
- Do not "fix" Guard A by hand-bumping the cloud-init pin or pushing a `vinngest-v*` tag. Both
  are forbidden here (production write). The first would also route around the #8747 on-main
  gate.
- Do not edit `cloud-init-inngest.yml` even for a comment. It changes the rendered `user_data`,
  and the dedicated host's `apply_target=inngest-host-replace` path treats the file as the
  host's payload.
- The allowlist regex must not match `$VECTOR_INSTALL_PATH`. It doesn't, because the regex
  anchors on a literal `$INSTALL_PATH` / `${INSTALL_PATH}`, and `"$VECTOR_INSTALL_PATH" --version`
  has a `-`-leading token anyway. Keep it that way if the regex is edited.
