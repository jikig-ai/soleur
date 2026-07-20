# Tasks — #6594: the infra-config gate asserts a count over a coin-flipped read

Plan: `knowledge-base/project/plans/2026-07-17-fix-infra-config-delivery-gate-false-green-plan.md`
Challenges (operator): `decision-challenges.md` — UC-1, UC-2. **Not decided.**

> **PR-A and PR-B are SEPARATE PRs.** Mechanical, not stylistic: the two applying workflows share
> `group: terraform-apply-web-platform-host` (`cancel-in-progress: false`), which **serializes but
> does not order** them. One PR ⇒ the nonce push may fire against the un-repointed tunnel.

## Phase 0 — Preconditions (before any code)

- [ ] 0.1 Verify the **#6416 in-band `hostname` tripwire** exists: grep the 12 `connection {}`
      provisioner inlines in `server.tf` for `hostnamectl` / `/etc/hostname` / `uname -n` /
      `$(hostname)`. If absent → ADR-068, ADR-114 and #6440 all carry a false enforcement claim;
      it becomes ADR amendment item 3 and the amendment's headline.
- [ ] 0.2 Confirm `var.web_hosts["web-1"].private_ip` renders `10.0.1.10` (`terraform console`).
- [ ] 0.3 Confirm the test runner + glob collect `infra-config-gate.test.sh` (plain bash, **no
      bats**): check `package.json scripts.test` and `bunfig.toml pathIgnorePatterns`.

## PR-A — Pin the write and the bridge (zero host writes)

- [ ] A.1 `tunnel.tf`: `deploy.` service → `http://${var.web_hosts["web-1"].private_ip}:9000`.
- [ ] A.2 `tunnel.tf`: `ssh.` service → `ssh://${var.web_hosts["web-1"].private_ip}:22`
      (the `handler_bootstrap` bridge rides this; pinning only `deploy.` leaves it coin-flipped).
- [ ] A.3 `terraform plan` — **AC: `0 to destroy`, no `hcloud_server` create** (#6482: a destroyed
      `cx33` cannot be re-placed).
- [ ] A.4 Merge → auto-applies via `apply-web-platform-infra.yml` (no `lifecycle` on the config
      resource; it IS `-target`ed). **Review carefully — no gate between merge and apply.**
- [ ] A.5 Verify **(a) config plane, authoritative**: read the ingress back from the Cloudflare API;
      assert both `service` values. Vantage-free, scriptable.
- [ ] A.6 Verify **(b) data plane, corroborating**: poll `/hooks/deploy-status` (which already emits
      `host_id` today) N× before/after; compare the `host_id` distribution.
      **Do NOT use "≥2 network vantages"** — you cannot choose your colo, and post-repoint both
      connectors proxy to web-1, so it reads green either way (a confounded experiment).

## PR-B — Phase 2: RED (failing test first, `cq-write-failing-tests-before`)

- [ ] B.2.1 Extract the gate adjudication from inline YAML in `apply-deploy-pipeline-fix.yml` into a
      sourceable `apps/web-platform/infra/infra-config-gate.sh`.
- [ ] B.2.2 Commit fixtures: **stale-same-count** (the REAL captured #6594 payload — 15/15,
      `exit_code=0`, `start_ts=1784233325`, `ci-deploy.sh sha256=2208300a…`; contains no secrets,
      confirm), **fresh-correct**, **sentinel** (`{"exit_code":-2,"reason":"no_prior_apply"}`).
- [ ] B.2.3 **Confirm stale-same-count PASSES — reproducing #6594 — before any fix.**

## PR-B — Phase 3: GREEN (content assert only)

- [ ] B.3.1 Content assert: every non-templated FILE_MAP dest's recorded `sha256` == the repo file.
      - Derive `basename(dest)` → `apps/web-platform/infra/<name>` from **FILE_MAP rows**
        (`VAR|dest|mode|owner`) — NOT from the `sed`+`grep -c` count, which yields a count, not a map.
      - **Key off FILE_MAP, not `files[]`** — the handler appends `orphan_hook_command` entries with
        no repo counterpart.
      - `hooks.json` is the sole exclusion, **derived from the template property** (its repo file is
        `hooks.json.tmpl`), not hardcoded. Assert exactly one exclusion.
      - Compare against **the SHA the apply ran from**, not `HEAD`.
- [ ] B.3.2 Place the assert **OUTSIDE the 3-attempt retry loop**; a mismatch is **terminal**.
      The loop re-issues a fresh `curl` per attempt = a fresh connector selection, and `break`s on
      first pass — **any-of-3 semantics that launder a coin flip into a green.**
- [ ] B.3.3 All three fixtures behave per the plan's table.
- [ ] B.3.4 **Mutation-test** each assert (delete the subject → suite must redden) AND confirm the
      runner actually collects the new file.

## PR-B — Phase 4: Recovery — the ONE prod write (gated)

- [ ] B.4.1 **Do not start before PR-A is verified** (A.5/A.6). Until the write is pinned this is a
      coin flip.
- [ ] B.4.2 Bump `redeploy-nonce` in `push-infra-config.sh` — **only this file** (it is absent from
      `handler_bootstrap`'s 5-element trigger set, so no bridge, no restart, no nonce-1 race).
- [ ] B.4.3 The merge IS the authorization. **No `-replace`, no `workflow_dispatch`, no SSH.**
- [ ] B.4.4 Confirm the new gate verifies delivery; if `ci-deploy.sh` is still `2208300a`, CI must go
      RED and name the file.
- [ ] B.4.5 **Expect main RED between Phase 3 and Phase 4** — a true red against a genuinely stale
      host. Do not "fix" it.

## PR-B — Phase 5: ADR + C4

- [ ] B.5.1 Amend ADR-114, three items: (1) **I1 is inert** on running hosts (measured: web-2's
      connector predates #6426's merge and still runs); (2) **I2 discharged** for `deploy.`+`ssh.`;
      (3) **the #6416 tripwire is unsubstantiated** (per 0.1) — if confirmed, correct `ADR-068:413`
      too. **Headline: this codebase repeatedly records controls as enforced that are inert on
      running hosts.**
- [ ] B.5.2 **Quote and rebut `ADR-114:122`** ("the cheapest fix mirrors ADR-068 Option B — fan out …
      needing no `.tf` and no tunnel change"). Rebuttal: fan-out fixes the WRITE, not the READ
      (`deploy-status`/`inngest-liveness` stay coin-flipped), and presumes web-2 should be converged
      (#6440's open question). Do not silently re-characterize an accepted ADR.
- [ ] B.5.3 Correct `model.c4:177-178` ("ONE tunnel, exactly ONE connector … INVARIANT enforced")
      and `model.c4:375` — **both false today** (2 live connectors, measured). Read all three `.c4`
      files; ensure web-2 is modeled.
- [ ] B.5.4 Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] B.5.5 `server.tf`: fix the comment falsified by `push-infra-config.sh:25-31` — it claims the
      edge means "the push never races a mid-flight listener restart"; nonce-1 is the counterexample
      (edge 2026-06-18 #5516; race 2026-07-10 #6313).

## Handovers (comments/issues — no code)

- [ ] H.1 **#6565** ← the measured datum (it is unblocked NOW; #6528 is merged and live on the host):
      `class=cred_store rc=1 stderr_chars=97|96|94 stdout_chars=0 kw=errsaving tok=error
      docker_ver=29.3.0 (registry=ghcr)`.
- [ ] H.2 **#6525** ← pull mechanics: `pull_image_with_fallback` returns 1 only when **both**
      registries fail; the GHCR leg retries **once, only for auth-classified stderr** → a
      network/timeout failure gets **zero** retries. Fail-closed but downtime-safe.
- [ ] H.3 **New issue** ← cloud-init changes are silent no-ops on running hosts (#6426's class;
      `ignore_changes=[user_data]` + #6482). Propose a CI gate on `cloud-init*.yml`. **The only one
      of the three "merged but never deployed" mechanisms with NO detection at all.**
- [ ] H.4 **New issue (D-A)** ← `host_name` telemetry is lying: a web host self-labels
      `soleur-inngest-prd` (a `sed`-rendered Vector literal, #6396). Every `host_name` attribution is
      suspect, incl. #6425's web-2 reading. Explains #6594's flagged `host`/`host_name` conflict.
- [ ] H.5 **New issue (D-B)** ← the dedicated inngest host may be dark / a colocated scheduler may
      still be live: `soleur-inngest` runs but ships no journald; the live `inngest-server` argv says
      `--sdk-url 127.0.0.1:3000` (colocated). Possible double-scheduler — triage.
- [ ] H.6 **#6483 / #6440** ← acknowledge; contribute the `registry_insecure_config` web-1-hardcode
      evidence to #6440.
- [ ] H.7 **#6441** ← comment narrowing it to the I1 residual (this PR discharges I2 for both rules).
      Use `Ref #6441`, not `Closes`.
- [ ] H.8 Follow-up issue ← the "handler started" beacon (blind surface). Deferred because editing
      `infra-config-apply.sh` re-fires the bridge → the nonce-1 race.

## Ship gates

- [ ] S.1 `Ref #6594` in PR-B's body (**not `Closes`** — closure follows the verified recovery).
- [ ] S.2 `ship` renders `decision-challenges.md` (UC-1, UC-2) into the PR body + files an
      `action-required` issue.
