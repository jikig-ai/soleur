---
title: "fix: close five pre-existing infra/observability defects (#6436, #6437, #6429, #6446, #6447)"
date: 2026-07-15
type: fix
lane: cross-domain
issues: [6436, 6429, 6446, 6447]
deferred_to_pr_b: [6437]
branch: feat-one-shot-6436-infra-observability-batch
brand_survival_threshold: no user impact
requires_cpo_signoff: true
---

<!-- v3 / UC-1 split (operator decision, 2026-07-15).
     `issues:` is PR-A's closing set. #6437 (Phase 4, ci-deploy.sh) ships as PR-B from its
     own worktree and carries `brand_survival_threshold: single-user incident` +
     `user-impact-reviewer`; this plan retains Phase 4 verbatim as PR-B's spec.
     PR-A's threshold is `no user impact`: its four phases are a C4 element, comment/citation
     edits, an alert-comment sweep, and a CI-step deletion — no runtime path.
     See specs/feat-one-shot-6436-infra-observability-batch/decision-challenges.md UC-1. -->


<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# fix: close five pre-existing infra/observability defects

> **Lane note:** no `spec.md` for this branch (one-shot entry, no brainstorm). `lane:`
> defaulted to `cross-domain` fail-closed per TR2.
>
> **Revision note (v2, post-review).** A 6-reviewer panel falsified v1 on four points,
> including **v1's own Phase 4.4 reproducing the exact defect its RR-6 diagnosed**. All
> mechanical findings are applied below.
>
> **Revision note (v3, post-escalation — 2026-07-15).** UC-1 (split Phase 4 into its own
> PR — CPO **blocking**, DHH) is now **APPLIED** by operator decision. v2 declined it
> citing the operator's stated direction *"as one batch"* — but that direction never came
> from the operator: it was synthesised into the `/soleur:go` args from a semicolon-grouped
> issue list, and a headless planner cannot see that provenance. Once surfaced, the
> operator chose the split. See
> [`decision-challenges.md`](../specs/feat-one-shot-6436-infra-observability-batch/decision-challenges.md)
> UC-1.
>
> **Scope of THIS plan's execution:**
> - **PR-A (this worktree, PR #6456)** — Phases 0, 1, 2, 3, 5 → closes **#6436, #6429,
>   #6446, #6447**. `no user impact`; jointly inert (comment edits, a C4 element, an
>   alert-comment sweep, a CI-step deletion).
> - **PR-B (separate worktree, rebases onto PR-A)** — Phase 4 → closes **#6437**.
>   `single-user incident`; `ci-deploy.sh` is the live deploy path
>   (`docker stop:1884` → `docker rm:1885` → `docker run -d:1907` = a ~22-line
>   no-container window), so a fatal error there is an `app.soleur.ai` **outage**.
>   Requires `user-impact-reviewer` + a human read of the deploy ACs.
>
> Phase 4 text below is **retained verbatim as PR-B's specification** — do not implement it
> in PR-A.

## Overview

Five pre-existing defects filed rather than fixed inline during earlier work
(`wg-when-an-audit-identifies-pre-existing`). Four were spun off by the #6285/#6424
zot-threshold work.

| # | Verdict after premise validation + review |
|---|---|
| #6436 | **Holds.** 1 element + 4 edges + 2 view includes. The one right-sized phase. |
| #6437 | **→ PR-B (v3/UC-1).** Holds; both the filed fix (RR-6) and v1's replacement (RR-16) are void. Re-designed on a control probe. Ships separately — the only phase that can cause an outage. |
| #6429 | **Premise falsified (RR-1/2/3/4) — and the real defect is elsewhere (RR-17):** an in-file off-by-one between the rule's stated intent and its config. |
| #6446 | **Holds.** Fix rides; the required-check question is *decided* (D-1) and split. |
| #6447 | **Holds — and is 1 of ~12 live citations** (RR-12, corrected). |

The batch's theme is **claims that no longer match the artifact they point at**. v1 of this
plan committed the same error three times; the RR table below records that rather than
hiding it.

## Research Reconciliation — Spec vs. Codebase

| # | Claim | Reality (verified) | Response |
|---|---|---|---|
| **RR-1** | #6429: `sandbox_startup_failure` uses the same `event_frequency` as the zot rule | **False.** `issue-alerts.tf:1231` uses **`event_unique_user_frequency`** — counts distinct users per issue-group. | Re-scope. |
| **RR-2** | #6429: "only three `event_frequency` rules (`:1233`,`:1380`,`:1462`)" | **False on count and all three lines.** **2** `event_frequency` (`:1396`, `:1478`) + **1** `event_unique_user_frequency` (`:1231`). | Sweep the corrected set. |
| **RR-3** | #6429: apply `value = 0` to the zot sibling | Already done — `:1398` (commit `ee997b6e3`, PR #6424). | Confirm only. |
| **RR-4** | #6429: high-cardinality *message* causes unreachability | True for zot (message-event, `ci-deploy.sh:607` embeds the deploy tag); **wrong lens** for the sandbox rule, whose emitter is `Sentry.captureException` (`observability.ts:258-262`) → **stack-keyed group, stable**. | The discriminator is **capture shape**. |
| **RR-6** | #6437: "emit `zot_gate_degraded_event doppler_absent` **before those early-returns**" | **Void.** The absent Doppler that triggers the early-return is the same thing that empties the `SENTRY_*` prefetch (`:708-713`), so the emitter's guard (`:633`) is false and the emit is a **no-op**. | Break the circularity first. |
| **RR-7** | #6437: the doppler-less early return is the silent path | Real but narrow: `doppler`/`DOPPLER_TOKEN` absent **aborts the deploy** ~280 lines later at `resolve_env_file` (`:1055-1065`, `doppler_unavailable`/`doppler_token_missing`) — loud, named, on `/hooks/deploy-status`. The genuinely silent case is a **live-but-erroring Doppler**: the `SENTRY_*` prefetch has **no timeout/retry** and `\|\| true` swallows failure (contrast the GHCR creds at `:716-721`: `timeout 45` + 3 tries). `:708` admits it: *"(dark event if absent, as today)"*. | Scope #6437 to the flaky-Doppler case. |
| **RR-10** | #6446: "a fixture render mirroring `cloud-init-user-data-size.test.ts` is cheapest" | **That test cannot do it** — substituter is `/\$\{([a-zA-Z0-9_]+)\}/g` only; **no `%{` handling**. The render authority **already exists**: `cloud-init-inngest-bootstrap.test.sh:281-330` renders all three cases via `terraform console`, already calls `render_yaml_ok`, and `:133-137` already documents the `%`-column-0 problem, declaring AC7 "the single home" for rendered-state validity. | **Reuse AC7.** |
| **RR-11** | #6447: comment cites `:554`; real target `:408` | ✓ (`:554` = the hash-verify; `:408` = the `printf … > /etc/default/webhook-deploy`). The issue's own quote of `:554` has itself drifted. | Drop the number; anchor on the token. |
| **RR-12** | #6447 is a single rotted citation; v1 said "1 of 12 across 8 files" | **v1's count was itself rotted** (Learning A, self-inflicted). Repo-wide: **~194** `cloud-init.yml:<N>` citations; **160** ex-archive; **~142 live in `knowledge-base/project/{plans,specs}`**. Outside plans/specs: **~21**, of which **12 wrong**. | **Invert the carve-out** — see RR-18. |
| **RR-13** | *(CLO)* The 4 compliance-surface citations are the same mechanical class | **False, and the batch's most important finding.** `article-30-register.md:164` has **a rotted anchor concealing a false claim**. Its "30 MB rolling (max-size=10m × max-file=3)" is only the **daemon default** (`cloud-init.yml:440`); `soleur-web-platform` runs `--log-driver journald` (`cloud-init.yml:767`; live path `ci-deploy.sh:1676`,`:1909`), **overriding** it. Real retention: `SystemMaxUse=1G` (`journald-soleur.conf:28-30`). Redirect landed in **PR #4786 (#4773)** (`git log -S` → `223364c14`); the 1G bound came later in **PR #4800 (#4792)** (`faf9ea95e`). Re-pointing `:303-310` → `:438-444` would leave the register **wrong *and* freshly "verified"**. | **Split to its own PR (D-3).** Not a citation fix. |
| **RR-14** | *(CTO)* v1's claim that a missing `merge_group` trigger blocks D-1 | **False.** The merge queue was **reverted** (`codeql-1537-revisit-watch.yml:3-8` — CodeQL reports no context on `merge_group`). `grep -n merge_queue infra/github/ruleset-ci-required.tf` → **one hit, `:36`, a comment**. The stale comment **mis-sized this very decision**. | Correct D-1; fix the comment (Phase 1.4). |
| **RR-15** | `infra/github/README.md:52` cleanly records the revert | **README contradicts itself**: `:52` says "REMOVED"; `:63-64`/`:100`/`:107` still describe the block as live. | Extend Phase 1.4. |
| **RR-16** | *(Kieran + spec-flow, post-v1)* v1's Phase 4.4 discriminator — "was `ZOT_REGISTRY_URL` non-empty **before** the fetch" | **Void under both readings — v1 reproduced RR-6's own defect.** (a) Nothing ever exports `ZOT_REGISTRY_URL` into ci-deploy.sh's env: `:80` initialises it empty and `:78-79` says it is fetched from Doppler at runtime; the only `export` in the repo is `zot-entry-gate.test.sh:50`. So a non-empty precondition **never fires in prod**. (b) At `:780` it is a **tautology**: `:778`'s `[[ -n ... ]] ||` short-circuits the fetch when non-empty, so every arrival at `:780` necessarily had an empty pre-fetch value. And `:779` discards the exit code, which returns non-zero for *both* a missing secret and an API error. | **Re-design on a Doppler control probe** (Phase 4.4). |
| **RR-17** | *(code-simplicity + spec-flow, independently)* #6429's defect is a reachability question needing prod tenant volume (v1's H1) | **The real defect is in-file and needs no prod read.** `issue-alerts.tf:1214-1215` states the intent — *"fire when **≥3** distinct tenants … within 1h"* — but `value = 3` under Sentry's **strict `>`** (documented for the sibling at `:1350`: *"compares with a STRICT `current_value > value`"*) fires at **≥4**. **Stated intent and config disagree by one.** | **Cut H1, Phase 0.4, R3** (and the regulated-data read). Fix the off-by-one. |
| **RR-18** | *(Kieran)* v1's carve-out (archive + this plan + this branch's specs + 1 learning + the 4 compliance cites) scopes AC1 correctly | **Inverted.** Residual after v1's full carve-out: **58 files / 146 matches**. And v1 was self-contradictory — it carved out *this* branch's specs as point-in-time records while **rewriting a 2026-04 learning and a 2026-07-07 brainstorm** on the same rot theory. A post-mortem or an old plan citing `cloud-init.yml:412` is a **historical record**; rewriting it is falsification. | **The sweep targets LIVE artifacts only** (`.tf`/`.sh`/`.yml` + active runbooks). Drops the learning + brainstorm edits; **adds `cloud-init-inngest.yml`** (a live artifact v1 missed). |
| **RR-19** | *(spec-flow)* v1's Observability `alert_route` for `sentry_post_failures`: "deploy-status, read by `apply-deploy-pipeline-fix.yml` / operator" | **Fabricated — a false observability-layer citation** (`hr-observability-layer-citation`, Learning H's exact class). That workflow reads only hard-coded fields (`.journald_storage.persistent`, `.tag`/`.exit_code`/`.reason`/`.component`), is a one-shot applier hard-coded to issue 4804, and is **absent from v1's Files to Edit** — it would never read the new field. The only other consumer (`canary-status.yml`) is `workflow_dispatch`. | **Cut `sentry_post_failures`** (D-6). `sentry_source` survives — its fail-loud path is the Sentry event itself. |
| **RR-20** | *(DHH + architecture, independently)* v1's Phase 4.1 sed-scrape was justified as the only "zero `user_data` cost" option, with the env file ranked second behind "trim `cloud-init.yml` comments to fit the 76 B" | **The justification is false twice over.** (a) `soleur-host-bootstrap.sh` is **baked into the image** — it is in `host_script_files` (`server.tf:52`); only its sha256 rides `user_data` (`cloud-init.yml:452`). Writing `/etc/default/soleur-sentry` from it costs **0 bytes**, identically to the scrape. The ladder was a strawman: it assumed the env file must be written *from `cloud-init.yml`*. It need not. (b) Even the strawman fits — architecture **measured** the `soleur-ghcr-read` pattern cloned into the template: 166 raw bytes → **+36 B modeled** (21,716 → 21,752 against a 21,800 budget; 48 B to spare), **+40 B real**. No trimming needed. | **Phase 4.1 rewritten** to the env-file boundary. Deletes the coupling, its drift-guard, and R2. |
| **RR-21** | *(architecture)* v1's 3.5/AC9/R4/T11 guard `issue-alerts.tf:1364` against being **moved** by a Phase-3 edit | **It is already rotted, today, before any edit — and this plan missed it while writing a guard for it.** `:1460`'s back-reference reads `(mirrors zot_mirror_fallback_rate:1364)`; `:1364` is the **last line of the CHANGE-TRIGGER paragraph**; the **GROUPING** paragraph it names starts at **`:1366`**. Off by 2. **#6424 "repaired" this reference to the wrong line** — in the PR whose entire purpose was fixing comment rot. v1's AC9 would therefore have **failed on the pre-fix tree regardless of Phase 3**, and T11 was untestable. | **3.5 becomes a FIX, not a guard** (and re-anchors on the paragraph name so it cannot rot a third time). AC6/T12 restated. |
| **RR-22** | *(architecture)* v1's "no new file, no new mode" constraint in `## User-Brand Impact`, and its "`apply-github-infra.yml` plans a no-op" claim | **Both wrong.** (a) The constraint is **backwards**: `soleur-host-bootstrap.sh:277` is `chmod 0755 /usr/local/bin/soleur-boot-emit` — the DSN is **already world-readable on every host**. A new **0600 `deploy:deploy`** file is *strictly narrower than the status quo*. (b) "No-op" is an **assumption**: the workflow runs a real `terraform plan` **refreshed against the live GitHub API** then `apply -auto-approve`; any UI drift is **silently reconciled**, and its destroy-guard counts **deletes only** — additive/modificative drift passes silently. It is the same post-merge, repo-wide, solo-founder-blocking apply path this plan cites as its reason to defer D-1. | Strike the constraint. **Use the `[skip-github-apply]` kill switch** (`apply-github-infra.yml:22`,`:76`) on the Phase-1.4 merge commit — turning an assumption into a verifiable fact. |

## User-Brand Impact

**If this lands broken, the user experiences:** `app.soleur.ai` **down** — not a stale
image. *(v1 said "stranded on the previous image"; the CPO falsified it and the code
confirms.)* `ci-deploy.sh` does `docker stop` (`:1884`) → `docker rm` (`:1885`) →
`docker run -d` (`:1907`). Between `rm` and `run` there is **no prod container**, and
`--restart unless-stopped` cannot help — it was removed. A fatal error in that ~22-line
window is a site outage. Phase 4's edits are mostly upstream of the cutover (the 7
emitters at `:397`-`:633`, the prefetch at `:709-713`), where the failure really is a
stranded image — but `final_write_state` is reachable **inside** the window (`:1900`),
so the blanket claim does not hold across Phase 4's full surface.

**Recovery path:** revert-merge redeploys the last-good `ci-deploy.sh` via
`web-platform-release.yml`. **AC12 must confirm this, not assume it** — if the broken
script is what runs the deploy, the recovery path runs through the broken script.

**If this leaks, the user's data is exposed via:** no new surface — and Phase 4 **narrows**
the existing one. The Sentry DSN is already baked on every host in
`/usr/local/bin/soleur-boot-emit` at **`chmod 0755`** — world-readable to every user on the
box (`soleur-host-bootstrap.sh:277`). Phase 4.1's `/etc/default/soleur-sentry` is **0600
`deploy:deploy`**, i.e. strictly tighter than the status quo. *(v1 carried a "no new file,
no new mode" constraint here; RR-22 shows it was backwards — it would have preserved the
wider exposure.)* A DSN public key is ingest-only by design; it must still never reach argv
or logs. *(v1's Phase 0.4 prod tenant-count read — the one regulated-data surface — is
**cut** per RR-17.)*

**Brand-survival threshold:** `single-user incident` — `ci-deploy.sh` under
`set -euo pipefail`, 2-host fleet, one operator. `requires_cpo_signoff: true`.
**CPO signed off with conditions** (see `## Domain Review`); the blocking condition is
recorded as UC-1 in `decision-challenges.md`.

## Hypotheses

**Network-outage gate: fired on substring, false positive.** Matches `ssh` (in the
rule-id `hr-no-ssh-fallback-in-runbooks`) and `unreachable` (in `probe_unreachable`).
Neither is a connectivity symptom; this batch diagnoses no SSH or reachability failure.
Recorded rather than skipped silently.

**v1's H1 is withdrawn.** It hypothesised that `sandbox_startup_failure`'s `value = 3`
was unreachable on a *population* axis and proposed a prod tenant-count falsifier. Two
reviewers independently showed the real defect is **in-file** (RR-17), and that the
falsifier was decorative: it had no tooling, no command, no owner, and two of its three
outcomes led to the same action anyway. No hypothesis remains — #6429 is now decidable
by reading.

## Architecture Decision (ADR/C4)

### ADR

**No new ADR; no amendment here.** #6436 records a decision ADR-031
(`ADR-031-sentry-as-iac.md`) already made — the C4 is behind, not the ADR. #6429/#6437
change mechanics inside boundaries ADR-031/ADR-096 already draw. **D-1 amends ADR-032**;
that amendment ships with D-1's PR.

> No ordinal claimed → `/ship`'s collision gate has nothing to verify. *(Observed: two
> ADR-031 files exist on main. Pre-existing, out of scope, not filed by this plan.)*

### C4 views

**Completeness mandate discharged — all three model files read in full** (`model.c4`,
`views.c4`, `spec.c4`). Not a keyword grep: the missing element is the **vendor**, which
is the failure mode #6436's own closing note warns about.

| Class | Element | Modeled? |
|---|---|---|
| External system | **Sentry** | **NO → added** |
| External system | Better Stack (`:262`), GHCR, zot, Doppler, Cloudflare, GitHub, Sigstore | ✓ |
| External actor | `founder` (paging target) | ✓ `:8` |
| Container | `hetzner`, `inngest`, `webapp` | ✓ |
| Access relationship | founder ← paging path | **NO → adds `sentry -> founder`** |

`spec.c4` needs **no change** — `tag external` (`:49`) already exists and is correct.

Phase 2 tasks: add the element (description sourced from `sentry/variables.tf:3-4` +
`main.tf:21-37` — org `jikigai-eu`; API on the **org subdomain**, not `eu.sentry.io`; DSN
ingest `de.sentry.io`; ADR-031); add 4 edges; add `sentry` to **both** view include lists;
run the two C4 tests.

## Infrastructure (IaC)

**No new infrastructure.** No server, service, cron, vendor account, DNS record, cert,
secret, firewall rule, or persistent process. No remote-shell step, no Doppler secret
**write**, no dashboard step. `.tf` edits are comments (`ghcr-minter-doppler-token.tf`,
`ruleset-ci-required.tf`) or one existing-resource attribute (`issue-alerts.tf`).

Apply paths, all automated: `apply-sentry-infra.yml` auto-applies `issue-alerts.tf` on
merge (`-target` allowlist already covers both frequency rules, `:265-266`);
`apply-github-infra.yml` fires for the `ruleset-ci-required.tf` comment and plans a
no-op; `web-platform-release.yml` redeploys `ci-deploy.sh`.

Phase 4.1 adds one line to `soleur-host-bootstrap.sh`, which is **baked into the image**
(`cloud-init.yml:452`; only `host_scripts_content_hash` rides `user_data`) — see RR-20 in
`## Risks`.

## Observability

```yaml
liveness_signal:
  what: >
    ci-deploy.sh telemetry source, self-reported per deploy as
    `sentry_source ∈ {doppler, baked, none}` in the deploy-status state file.
    `none` is the fail-loud state that is silent today.
  cadence: every deploy (each web-platform-release.yml merge to main)
  alert_target: >
    Sentry issue-alert `zot_mirror_fallback_rate` — verified to match: the emitter
    tags `registry: "zot-gate-degraded"` (a CONSTANT literal; the reason rides a
    separate `zot_gate_reason` tag), and filters_v2 matches `registry EQUAL
    zot-gate-degraded` under filter_match="any", reason-agnostic. New reason
    literals need NO filter entry, and value=0 fires on the first event of any group.
  configured_in: >
    apps/web-platform/infra/ci-deploy.sh (emit),
    apps/web-platform/infra/cat-deploy-state.sh (no-SSH surface),
    apps/web-platform/infra/sentry/issue-alerts.tf (route)
error_reporting:
  destination: Sentry project web_platform, org jikigai-eu (ADR-031)
  fail_loud: >
    The Sentry POST stays fail-open — a deploy must not die because telemetry is
    down. What changes: the baked DSN makes the emitters survive a Doppler outage,
    so the events that are dark today actually get sent.
failure_modes:
  - mode: >
      Doppler live-but-erroring; SENTRY_* prefetch returns empty while both
      early-return guards pass (RR-7 — the genuinely silent case)
    detection: >
      baked-DSN fallback supplies SENTRY_*; zot_gate_indeterminate_event
      reason=doppler_fetch_empty, discriminated by a Doppler CONTROL PROBE
      (Phase 4.4), not by pre-fetch emptiness (RR-16)
    alert_route: sentry_issue_alert.zot_mirror_fallback_rate (fires on first event)
  - mode: Doppler CLI absent / DOPPLER_TOKEN unset
    detection: >
      ALREADY LOUD and not this plan's job — resolve_env_file aborts the deploy at
      ci-deploy.sh:1055-1065 with a named state (doppler_unavailable /
      doppler_token_missing) surfaced on /hooks/deploy-status. Recorded so the next
      reader does not re-file it (RR-7).
    alert_route: existing deploy-state path
  - mode: Baked DSN absent, empty, or MALFORMED
    detection: >
      Phase 4.1 validates the DSN SHAPE before accepting it
      (^https://[^@]+@[^/]+/[0-9]+$) and sets sentry_source=none on failure. A bare
      -n test is NOT sufficient: `sed s///` on a non-match emits its INPUT unchanged,
      so a malformed DSN yields three non-empty garbage values, the -n guard PASSES,
      and telemetry is dark while reporting `baked` (Kieran P1-1).
    alert_route: >
      CI (Phase 4.8 drift-guard, pre-merge) + bake-time fail-closed (Phase 4.2)
logs:
  where: >
    journald per host, shipped to Better Stack Logs source 2457081 via Vector.
    journald ALONE does not satisfy hr-no-ssh-fallback-in-runbooks — hence the
    deploy-status surface.
  retention: >
    SystemMaxUse=1G persistent journal (journald-soleur.conf) — NOT the 30 MB
    json-file cap: soleur-web-platform runs --log-driver journald, overriding the
    daemon.json default (RR-13). The Art. 30 register misstates this; correcting it
    is SPLIT to D-3, not fixed here.
discoverability_test:
  command: >
    curl -sS -H "CF-Access-Client-Id: $CF_ID" -H "CF-Access-Client-Secret: $CF_SECRET"
    "https://deploy.soleur.ai/hooks/deploy-status" | jq '.sentry_source'
  expected_output: >
    "doppler" on a healthy deploy; "baked" means Doppler degraded but telemetry
    survived; "none" is the fail-loud state. No remote shell.
```

> **`sentry_post_failures` was CUT** (RR-19). v1 claimed it routed to
> `apply-deploy-pipeline-fix.yml`; that workflow reads only hard-coded fields and was
> not even in v1's Files to Edit — a **fabricated layer citation**, the very thing
> `hr-observability-layer-citation` forbids. A counter whose premise is "Sentry was
> unreachable" has no second layer here. If it is wanted, the repo's mechanism is
> `scripts/followthroughs/*.sh` + `scheduled-followthrough-sweeper.yml` — filed as **D-6**.

## Open Code-Review Overlap

**None.** All 62 open `code-review` issues fetched; every planned path matched against
every body with `jq --arg` — zero matches.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO — sign-off only; no UI
surface, the mechanical UI-surface override did **not** fire against Files to Edit/Create).
Not relevant: Marketing, Sales, Finance, Operations (Sentry/Better Stack already ledgered),
Support.

### Engineering (CTO)

**Status:** reviewed. Four rulings, all adopted: **split D-1** (post-merge, repo-wide
failure mode); the shape is an `infra-validation-required` **aggregator**, not `validate`
(constraints confirmed; the `merge_group` blocker **falsified** → RR-14); **Option A** for
the schema step; **D-4 separate and sequenced before D-1**.

### Legal (CLO)

**Status:** reviewed. **Falsified v1's D-3** (RR-13): the Art. 30 retention statement is
substantively wrong, not mis-anchored. Under-states retention (1G journal vs "30 MB
rolling") → Art. 5(1)(e) + 5(2), **bounded by tenant-zero posture** (sole data subject is
the operator; no arms-length subject; **no Art. 33 clock**) → a **correctable accuracy
defect, not an incident**. File as `compliance`, **not** `compliance/critical`. Root cause
is worse than the citation: the runbook's trigger #4
(`recover-userid-from-pino-stdout.md:145-148` — fires on a `--log-driver` change) **had its
condition met by PR #4786 and did not operate**. Best anchor is **executable**:
`journald-config.test.sh:71` already asserts `SystemMaxUse=1G`. → **D-3**.

### Product (CPO)

**Status:** reviewed — **SIGN OFF WITH CONDITIONS**. Threshold correctly assigned but
v1's stated failure mode was **factually wrong** (applied above). Conditions applied:
corrected User-Brand Impact + recovery path (AC12); `terraform validate` on the sentry
root (AC11 — D-4's deferral leaves *this PR's own diff* unvalidated while
`apply-sentry-infra.yml` auto-applies it); bound D-3 as next-up. The blocking condition
(**split Phase 4**) is **not applied** → UC-1 in `decision-challenges.md`.
Non-blocking, recorded as T-2: re-milestone #6437/#6446 to Phase 4; `roadmap.md`
Current State is stale (says 43/160; API says 51/165).

## Files to Edit

**Phase 1 — #6447 + the LIVE-artifact citation sweep (RR-18):**

| File | Change |
|---|---|
| `apps/web-platform/infra/ghcr-minter-doppler-token.tf` | `:53` — drop `:554`, anchor on `/etc/default/webhook-deploy` (**#6447 proper**) |
| `apps/web-platform/infra/inngest-bootstrap.sh` | `:168` — `:289-290` → anchor on `chmod +x /usr/local/bin/doppler` |
| `apps/web-platform/infra/scripts/web2-recreate-preflight.sh` | `:8`, `:11`, `:87` — `:389-391`/`:390` (a **blank line**) → anchor on the `GOT=` recompute pipeline |
| `tests/scripts/test-web2-recreate-preflight.sh` | `:30` — `:390` (blank) → same anchor |
| `apps/web-platform/infra/cloud-init-inngest.yml` | **ADDED in v2 (RR-18)** — a live infra artifact v1 missed; 5 citations |
| `infra/github/ruleset-ci-required.tf` | `:36-43` — stale `merge_queue` narrative (RR-14) |
| `infra/github/README.md` | `:63-64`, `:100`, `:107` — contradict `:52` (RR-15) |

> **Carve-out (RR-18, inverted from v1).** The sweep touches **live artifacts only**.
> **Excluded as historical point-in-time records:** `**/archive/**`,
> `knowledge-base/project/plans/**`, `knowledge-base/project/specs/**`,
> `knowledge-base/engineering/operations/post-mortems/**`, ADRs, and the rot-narrating
> learning. **v1 was self-contradictory here** — it carved out this branch's specs as
> point-in-time while rewriting a 2026-04 learning and a 2026-07-07 brainstorm on the
> same theory. Those two edits are **dropped**. The 4 compliance citations are excluded
> as **D-3**.

**Phase 2 — #6436:** `model.c4`, `views.c4`.

**Phase 3 — #6429:**

| File | Change |
|---|---|
| `apps/web-platform/infra/sentry/issue-alerts.tf` | fix the **off-by-one** (RR-17); corrected sweep comment + capture-shape rule; fix `:1367`'s "3 fixed literals" inventory |
| `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` | **append** the capture-shape assertion (v1's separate new file is **cut**) |

**Phase 4 — #6437:**

| File | Change |
|---|---|
| `apps/web-platform/infra/soleur-host-bootstrap.sh` | write `/etc/default/soleur-sentry`; **fail closed on an empty DSN at bake time** |
| `apps/web-platform/infra/ci-deploy.sh` | source the baked env file (mirroring `soleur-ghcr-read`); DSN **shape validation**; control-probe discriminator; new indeterminate emitter; `sentry_source`; fix `:628`'s reason inventory |
| `apps/web-platform/infra/cat-deploy-state.sh` | surface `sentry_source` |
| `apps/web-platform/infra/ci-deploy.test.sh` | new assertions |

**Phase 5 — #6446:** `.github/workflows/infra-validation.yml`,
`apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`.

## Files to Create

*(none — v1's new contract-test file is cut; the assertion appends to the existing one.)*

## Implementation Phases

> **Phase order (corrected — v1's "1/2/3/5 are independent" was false).**
> **1, 2, 5 are independent.** **3 → 4.6** is *ordered*: both edit `issue-alerts.tf`, and
> 4.6's target is the reason-literal inventory at `:1367` ("3 fixed literals"), which a
> Phase-3 comment edit above it will move. **4a → 4b** is ordered (the contract before its
> consumer — RR-6). **AC6 must be evaluated after 4.6, not after Phase 3.**
>
> **UC-1 split — how the 3 → 4.6 coupling is paid for (v3).** The split is APPLIED, so
> Phase 3 (PR-A) and Phase 4.6 (PR-B) now edit the same `issue-alerts.tf` comment block in
> different PRs. This is a **sequencing cost, not a blocker**:
> - **PR-A lands first.** Its Phase 3 must describe **PR-A's own end-state** — see the
>   amended 3.7. It must NOT pre-describe a literal that only PR-B adds; a comment
>   asserting a fact its own diff does not contain is this batch's exact thesis,
>   self-inflicted.
> - **PR-B rebases onto PR-A** and moves the inventory 3 → 4 as part of 4.6, alongside
>   `:628`'s reason inventory and the `filters_v2` `registry` entry. One conflict surface,
>   resolved in the PR that owns the change.
> - **AC6 is evaluated in PR-A, and re-verified in PR-B after 4.6.** (v2 said "after 4.6,
>   not after Phase 3" — that held only while a *line-number* anchor could be moved by
>   4.6's edits. Phase 3.5 re-anchors on the **paragraph name**, which is line-independent,
>   so AC6 is satisfiable in PR-A and stays true across PR-B. PR-B re-verifies because 4.6
>   edits the same block.)

### Phase 0 — Preconditions

0.1 `doppler secrets --project soleur --config prd --only-names | grep SENTRY_USERID_PEPPER`
    → must be present (it is). **Name-only; never the value.**
0.2 Confirm RR-3: `value = 0` at `issue-alerts.tf:1398`.
0.3 Confirm `cloud-init` is installable on the runner; measure the added
    `deploy-script-tests` time (R8).
0.4 **CUT (RR-17)** — v1's prod tenant-count read. The defect is decidable in-file.

### Phase 1 — #6447 + live-artifact sweep

1.1 **CUT** — v1's "resolve citations and fail on any that do not land on the construct
    they name" guard. Three reviewers: it needs NLP over prose, and it is **vacuous
    post-fix** (1.2 deletes every in-scope citation, so its in-scope set is empty at
    GREEN).
1.2 Fix the citations by **dropping the line number and anchoring on a grep-able token**
    (Learning B). Do **not** re-point — that resets the rot clock, which is what #6447's
    own suggested fix would have done.
1.3 Do **not** add anchors inside `cloud-init.yml` (76 B headroom, Learning I). All
    citing sites are in `.tf`/`.sh`/`.yml`/`.md`, which are free.
1.4 Fix the stale `merge_queue` narrative in **both** `ruleset-ci-required.tf:36-43` and
    `README.md:63-64`/`:100`/`:107`, citing `codeql-1537-revisit-watch.yml:3-8`.

### Phase 2 — #6436 C4 Sentry

2.1-2.3 Add the element + 4 edges; add `sentry` to **both** view include lists.
2.4 `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`.

### Phase 3 — #6429

3.1 **Read the live rules back** (folds in #6285's never-run AC10 — same action).
    Read-only GET for all three frequency rules; assert `zot_mirror_fallback_rate` stores
    `value: 0` with non-empty actions. Use `SENTRY_ISSUE_RO_TOKEN`. **Never**
    `data "sentry_team"` — it 403s and would wedge every future apply.
3.2 **Fix the off-by-one (RR-17).** `:1214-1215` states *"fire when ≥3 distinct tenants"*;
    `value = 3` under strict `>` fires at **≥4**. Set **`value = 2`** (`>2` → ≥3, matching
    stated intent) **and** state the `>` semantics inline as `:1350` already does for the
    sibling. This is #6429's real answer.
3.3 Record the corrected sweep: **2** `event_frequency` (zot value=0;
    `web_terminal_boot_fatal` value=1, reachable via the always-hot shared
    `soleur-boot-emit` group) + **1** `event_unique_user_frequency`.
3.4 Record the **capture-shape rule** (RR-4): message-event (`captureMessage` / raw
    `/store/` POST with `message:`) → group keyed on the message → a high-cardinality
    token mints a fresh group per event → any threshold >0 unreachable. Exception-event
    (`captureException`) → stack-keyed → stable. `event_unique_user_frequency` also needs
    `event.user` set and distinct (`observability.ts:88-101`).
3.5 **Learning B — a FIX, not a guard (RR-21).** `web_terminal_boot_fatal:1460` says
    `"GROUPING NOTE (mirrors zot_mirror_fallback_rate:1364)"`. **That reference is already
    wrong today**: `:1364` is the last line of the CHANGE-TRIGGER paragraph; the GROUPING
    paragraph it names starts at **`:1366`**. #6424 "repaired" this reference *to the wrong
    line*, in the PR whose entire purpose was fixing comment rot — and v1 of this plan wrote
    a **guard** for it without noticing it was already broken. **Re-anchor on the paragraph
    name** (`mirrors the GROUPING paragraph of zot_mirror_fallback_rate`) so it cannot rot a
    third time. Do not re-point to `:1366`.
3.6 Append the capture-shape assertion to the **existing** zot contract test (v1's
    separate file is cut).
3.7 **AMENDED (v3, UC-1 split).** v1/v2 read *"fix `:1367`'s '3 fixed literals' inventory
    — Phase 4 adds one"* (i.e. 3 → 4). Under the split, Phase 4 is **PR-B**, so in PR-A
    **no fourth literal exists**: writing "4" here would ship a comment asserting a literal
    absent from PR-A's own diff — the defect class this batch exists to close.
    - **In PR-A:** verify `:1367`'s inventory is **accurate for PR-A's end-state** and
      correct it only if it is already wrong today. Do not anticipate PR-B.
    - **In PR-B:** 4.6 moves the inventory 3 → 4 when it adds
      `zot_gate_indeterminate_event`'s literal — the PR that adds the literal owns the
      count.

### Phase 4 — #6437 → **DEFERRED TO PR-B (do NOT implement in PR-A)**

> **v3 / UC-1.** Everything in this phase ships as **PR-B**, a separate PR that rebases
> onto PR-A. Retained here verbatim as PR-B's specification. `/work` on PR-A must skip
> Phase 4 entirely; `git diff` for PR-A must show **zero** changes to `ci-deploy.sh`,
> `soleur-host-bootstrap.sh`, `cat-deploy-state.sh`, and `ci-deploy.test.sh`.

**4a — the contract:**

4.1 **`soleur-host-bootstrap.sh` writes `/etc/default/soleur-sentry`** (`SENTRY_INGEST_DOMAIN`,
    `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY`), mode 0600, `deploy:deploy` — mirroring
    `/etc/default/soleur-ghcr-read` (`cloud-init.yml:416-418`, read by ci-deploy via
    `SOLEUR_GHCR_READ_FILE`). **Zero `user_data` cost** — the bootstrap is **baked into
    the image** (`cloud-init.yml:452`); only `host_scripts_content_hash` rides `user_data`.
    *(v1 sed-scraped the DSN out of `/usr/local/bin/soleur-boot-emit` on a "76-byte"
    rationale that does not apply — RR-20. That coupling, its drift-guard, and R2 are all
    gone.)*
    - **Validate the DSN shape** before accepting: `^https://[^@]+@[^/]+/[0-9]+$`. A bare
      `-n` test is insufficient — `sed s///` on a non-match emits its **input unchanged**,
      so a malformed DSN yields three non-empty garbage values that pass `-n` and POST to
      a garbage URL while reporting `baked`.
    - **`|| true` discipline, in the plan body not the risk table:** `[[ -r "$f" ]] || return 0`
      first, and every parse step `|| true`. `${VAR:-}` guards `set -u` on **read** only —
      it does **nothing** for `set -e` + `pipefail` (`ci-deploy.sh:2`) when `grep` exits 1
      on no match, which would **kill the deploy** — R1's exact catastrophe.
    - **Assign to the EXPORTED env**, not a `local` — `ghcr_prelude_and_login` does
      `export "$k"` (`:709-713`) and `zot_gate_and_login` runs after and relies on it. A
      `local` makes 4.5's "all 7 inherit the fallback" false.
4.2 **Bake-time fail-closed on an empty DSN.** `soleur-host-bootstrap.sh:264` is
    `[ -n "$DSN" ] || exit 0` — an empty `${sentry_dsn}` bakes an emitter that silently
    returns 0 forever, and the `STAGE=boot_emit` trap guards the *write*, not the *value*.
    One line, at bake time: a host with no telemetry never joins the fleet
    (`hr-fresh-host-provisioning`-shaped). This makes `sentry_source=none` nearly
    unrepresentable rather than something detected on every deploy forever.
4.3 **CUT** — v1's `timeout 45` + 3-try retry on the `SENTRY_*` prefetch. Redundant once
    the baked file is primary and Doppler is the fallback: a slow Doppler cannot darken
    telemetry it is no longer the source of.
4.4 Record `sentry_source ∈ {doppler, baked, none}` to the telemetry state file.

**4b — the consumers:**

4.5 **The discriminator, re-designed (RR-16).** v1's "was `ZOT_REGISTRY_URL` non-empty
    before the fetch" is void both ways. Use a **Doppler control probe**: alongside the
    `ZOT_REGISTRY_URL` fetch, probe a known-always-present prd key (or
    `doppler secrets --only-names`).
    - control **succeeds** + `ZOT_REGISTRY_URL` empty ⇒ genuinely unprovisioned ⇒ **stay
      silent** (preserves the dark-launch contract).
    - control **also fails/empty** ⇒ Doppler is degraded ⇒ **emit**.
4.6 **A separate emitter, not a new reason on the old one (Kieran P0-3).**
    `zot_gate_degraded_event`'s payload **hardcodes** *"zot gate degraded (…) — configured
    but inactive, using GHCR"* (`:635`) and its contract (`:621-629`) says *"only fires
    when ZOT_REGISTRY_URL is set"*. On the new path the emitter **cannot know** zot is
    configured — shipping an event whose body asserts a fact the emitter cannot establish
    is this batch's own thesis, self-inflicted. Add `zot_gate_indeterminate_event` with an
    honest message (*"zot gate indeterminate — secret source unavailable"*), its own
    `registry` tag value, and reason `doppler_fetch_empty`.
    - **`doppler_fetch_failed` is NOT available as a literal** — `ci-deploy.sh:1081`
      already uses it as a **deploy-state** reason for a *hard abort*. Reusing it for a
      *soft degradation* in a different namespace would mislead an operator grepping logs.
    - Update `:628`'s `reason ∈ {probe_unreachable, creds_absent, login_failed}` inventory.
    - **Verify the new `registry` value against the alert's `filters_v2`** — a new
      `registry` literal **does** need a filter entry (unlike a new `zot_gate_reason`,
      which is filter-agnostic). This is the one place Phase 4 touches the alert's
      matching, not just its comment.
4.7 All **seven** guarded emitters (RR-5: `:397`, `:477`, `:500`, `:547`, `:577`, `:604`,
    `:633`; none has an `else`) inherit 4.1's fallback via the exported env — no
    per-emitter edit. Verify by test.
4.8 **CUT** — `sentry_post_failures` (RR-19). Filed as D-6.
4.9 `cat-deploy-state.sh`: surface `sentry_source`, mirroring `cron_drain_json()` /
    `sandbox_canary_json()` (safe sentinel when absent).
4.10 Extend `ci-deploy.test.sh`: Doppler absent + baked DSN present → all 7 emitters POST
    (via `MOCK_SENTRY_CAPTURE_FILE`, `:436-441` — verified real); malformed DSN →
    `sentry_source=none`, **not** `baked`; baked DSN absent → deploy still succeeds;
    drift-guard anchored on `^[[:space:]]*DSN='` (a bare `DSN='` would also match a
    comment).

### Phase 5 — #6446

5.1 **Delete** the raw-source `Validate cloud-init schema` step (`infra-validation.yml:83-92`).
    It validates a Terraform `templatefile()` as YAML — structurally incapable. False-green
    for years; false-red since #6344.
5.2 Add `cloud-init schema` on the **rendered** output inside the existing AC7 leg
    (`cloud-init-inngest-bootstrap.test.sh:281-330`). Reuse `render_yaml_ok`'s
    heredoc-strip. **Self-SKIP visibly** if `cloud-init` is absent — never false-green.
5.3 Add `sudo apt-get install -y -qq cloud-init` to `deploy-script-tests`.
5.4 File **six** tracking issues (D-1, D-3, D-4, D-5, D-6), each carrying its design +
    re-evaluation criteria + milestone. **D-1's body must carry the D-4 blocking
    precondition** (spec-flow P1-6: the ordering currently lives only in prose that Phase 5
    archives, and GitHub has no dependency primitive).

## Acceptance Criteria

### Pre-merge (PR)

*(v1 had 18; the panel identified ~9 as ceremony paraphrasing the phase that produced
them. These are the gates.)*

> **v3 / UC-1 scoping.** Each AC is tagged with the PR that must satisfy it.
> **PR-A gates:** AC1, AC2, AC3, AC4, AC5, AC6, AC11, AC13, AC14, AC15, AC16.
> **PR-B gates:** AC7, AC8, AC9, AC10, AC12 — plus AC11, AC14, AC16 re-run, and AC6
> re-verified. A PR-B-tagged AC is **not** a gate on PR-A and must not be checked there;
> that is the point of the split.

- [ ] **AC1** In the **7 files listed in Phase 1**, zero bare `cloud-init.yml:<N>`
      citations remain, and each anchor token is **present**. Scoped per-file — **not**
      repo-wide (RR-18: repo-wide returns ~146 residual across historical records that
      must not be rewritten). Verified to FAIL on the pre-fix tree. State it as "zero
      matching lines" and use `! grep -qE` — bare `grep` exits **1** on no match, so under
      `set -e` the passing state is a non-zero exit.
- [ ] **AC2** `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` passes.
      *(Subsumes v1's AC4/AC5 grep counts — `c4-render.test.ts` already fails on a view
      include referencing an undefined element, which is what those greps approximated
      worse: `grep -c` counts, it does not check.)*
- [ ] **AC3** The Phase-3 live read-back shows `zot_mirror_fallback_rate` storing
      `value: 0` with non-empty actions; recorded in the PR body. (#6285's never-run AC10.)
- [ ] **AC4** `sandbox_startup_failure` fires at its **stated intent**: `value = 2` with the
      `>` semantics documented inline. Verified to FAIL pre-fix (`value = 3` → ≥4 ≠ the
      comment's "≥3").
- [ ] **AC5** The capture-shape assertion is appended to the existing zot contract test and
      **fails** if the sandbox emitter is switched to `captureMessage`.
- [ ] **AC6** `web_terminal_boot_fatal`'s `GROUPING NOTE` back-reference resolves to the
      paragraph it names (the #6424 repeat-offence guard).
- [ ] **AC7** — **[PR-B]** `bash apps/web-platform/infra/ci-deploy.test.sh` passes, including all
      Phase-4.10 cases. **Advisory job — a human must read this one.**
- [ ] **AC8** — **[PR-B]** With `doppler` absent and the baked DSN present, all **7** emitters POST
      (asserted via `MOCK_SENTRY_CAPTURE_FILE`, not by grepping the script). **Advisory —
      human must read.**
- [ ] **AC9** — **[PR-B]** A **malformed** DSN yields `sentry_source=none`, not `baked` (the sed
      garbage-passthrough guard).
- [ ] **AC10** — **[PR-B]** `zot_gate_indeterminate_event`'s new `registry` tag value has a matching
      `filters_v2` entry in `zot_mirror_fallback_rate`, verified against the rule.
- [ ] **AC11** `terraform validate` passes on `apps/web-platform/infra/sentry/` — run
      explicitly. **D-4's deferral leaves this PR's own `issue-alerts.tf` edits
      unvalidated in CI while `apply-sentry-infra.yml` auto-applies them post-merge**
      (CPO condition 3).
- [ ] **AC12** — **[PR-B]** The revert-recovery path is **confirmed, not assumed**: a revert-merge
      redeploys the last-good `ci-deploy.sh`. (CPO condition 2.) *(UC-1 makes this cheaper
      to honour: PR-B is revert-granular — reverting it no longer drags the C4 model, the
      citation sweep, and the alert audit with it, which was the reviewers' 4th argument.)*
- [ ] **AC13** `infra-validation.yml` no longer contains `cloud-init schema -c cloud-init.yml`;
      `cloud-init-inngest-bootstrap.test.sh` contains a `cloud-init schema` on a **rendered**
      path with a visible SKIP arm.
- [ ] **AC14** `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` passes;
      headroom did not regress below the **76 B** measured at 0.1.
- [ ] **AC15** Six tracking issues exist (D-1, D-3, D-4, D-5, D-6) and **D-1's body carries
      the D-4 blocking precondition**.
- [ ] **AC16** Full suite green: `bash scripts/test-all.sh`.

### Post-merge (operator)

*(none — every step is automated. `apply-sentry-infra.yml` and `web-platform-release.yml`
fire on merge; `apply-github-infra.yml` plans a no-op for the comment. **Automation
feasibility gate: no candidate operator step survived it.**)*

## Risks & Mitigations

| # | Risk | Mitigation |
|---|---|---|
| **R1** | **Phase 4 breaks the production deploy path** → `app.soleur.ai` **down** (not stale) if the fault is in the `rm`→`run` window. | `ci-deploy.test.sh` (3,414 lines) sources the script with mocked binaries. The `\|\| true` discipline is specified in Phase 4.1 **body**, not left to the implementer. AC12 confirms the recovery path. **`deploy-script-tests` is advisory — AC7/AC8 must be read by a human.** |
| **R2** | *(retired)* v1's baked-DSN sed-scrape coupling | Gone — 4.1 now writes a real env file. |
| **R3** | *(retired)* v1's prod tenant-count read | Gone — RR-17 makes it unnecessary. |
| **R4** | **Phase 3.5 repeats #6424's mistake** — editing `:1324-1385` moves `:1364`. | AC6; re-anchor on the paragraph name so the class dies rather than moves. |
| **R5** | *(retired — v3)* **Batch size + Phase 4's risk asymmetry.** Three reviewers (CPO blocking, DHH, Kieran) argued Phase 4 must be its own PR — Kieran's reason being that Phases 1/2/3/5 are close to correct while Phase 4 needed a central re-design. | **APPLIED** (operator decision, 2026-07-15). v2's rationale for declining — *"the operator asked for one batch"* — was **false**: that direction was synthesised into the one-shot args, not stated by the operator. PR-A = Phases 1/2/3/5; PR-B = Phase 4. The residual this risk carried is now structural, not accepted. See `decision-challenges.md` UC-1. |
| **R9** | **PR-A ships a comment describing PR-B's state.** The 3 → 4.6 coupling means Phase 3's literal inventory at `:1367` was written assuming Phase 4 rides along. | Amended **3.7**: PR-A describes PR-A's end-state only; PR-B moves the inventory 3 → 4 when it adds the literal. Guarded by PR-A's `git diff` showing zero `ci-deploy.sh` changes. |
| **R6** | Deleting the schema step loses cloud-init **module** validation. | Not lost — 5.2 moves it onto the **rendered** artifact, validating the real thing for the first time. Net capability **increases**. |
| **R7** | **Net gating delta is zero** — Option A moves the assertion from one non-required job to another. | Accepted, stated plainly. It is *why* D-1's aggregator must cover **`deploy-script-tests` as well as `validate`** — the concrete reason D-1 cannot be designed before this lands. |
| **R8** | `cloud-init` install adds time to `deploy-script-tests` (`timeout-minutes: 8`, 60+ suites). | Measure at 0.3; raise `timeout-minutes` rather than drop the check. |
| **RR-20** | **The 76-byte budget does not apply to Phase 4.** `soleur-host-bootstrap.sh` is **baked into the image** (`cloud-init.yml:452`), not in `user_data`. v1 ranked the clean env-file design *second*, in a "ladder", on the strength of a cost it does not have. | AC14 keeps the budget as a **standing guard**; it is no longer Phase 4's rationale. |

## Alternative Approaches Considered

### D-1 — Should `validate` become a required check? (#6446's explicit ask)

**Decision: YES it should be gated — but NOT by requiring `validate`, and NOT in this PR.**
*(CTO ruling, adopted.)* `validate` is a **matrix** job (dynamic context name), is
**skipped** on non-infra PRs (a required context would never report → every non-infra PR
blocks forever), and sits behind a workflow-level `paths:` filter. The correct shape is an
always-run fail-closed **`infra-validation-required` aggregator** cloned from
`tenant-integration-required` (#5585 / ADR-032), with `needs: [detect-changes, validate,
deploy-script-tests]` (R7) and a unit-tested verdict script. Deferred because its failure
mode is **post-merge and repo-wide** — a buggy aggregator does not red this PR; it blocks
**the next** one and every one after, for a solo founder, until an admin bypass. Ordering:
**D-4 → this batch → D-1**. Amends **ADR-032**. v1 asserted a fourth blocker (a missing
`merge_group` trigger) — **false** (RR-14).

### D-2 — How to fix the broken schema step? → **Option A**

Assert `cloud-init schema` on the rendered output in the existing AC7 leg; delete the raw
step. Rejected: **B** (duplicates the 13-var map — AC7's comment calls that map a
deliberate tripwire; two copies means two out-of-sync tripwires); **C** (drop entirely —
loses `write_files`/`runcmd`/`users` module semantics that `yaml.safe_load` cannot see,
and a malformed `write_files` entry fails **silently at boot**). The 3 sibling templates
are scoped out → **D-5**.

**For the PR body:** Option A is not "moving a check" — it is **the first time this check
ever runs against the artifact that actually boots the host.**

### D-3 — Art. 30 register → **split to its own PR** (RR-13)

Not a citation fix. Scope: correct PA8 §(f) substance; **re-anchor to the executable
evidence** (`journald-config.test.sh:71` already asserts `SystemMaxUse=1G`) rather than to
line numbers; fix the **unfilled `__TBD_OBSERVED_VOLUME__` / `__TBD_BETTERSTACK_RETENTION__`
placeholders** (an independent Art. 30(1)(f) defect); repair the runbook's
`docker inspect … .LogPath` step (returns **empty** under the journald driver — a DSAR/Art.
15 step that cannot work); **rebase #3754** (it measures against a cap that does not apply);
add a trigger for `journald-soleur.conf` (the runbook's trigger list is **closed**, so this
is an explicit amendment); record the trigger-that-didn't-operate in `compliance-posture.md`.
Label `compliance`, not `compliance/critical`. **CPO condition 4: bound as next-up.**
*All D-3 output is draft material requiring professional legal review.*

### D-4 — `detect-changes` blind to `apps/web-platform/infra/sentry` → separate issue, **before D-1**

`infra-validation-detect.test.sh:44-47` (TS2) **asserts the blindness as intended**.
Requiring a check while detection is blind would **certify** a dark gate. Note
`terraform fmt -check -recursive .` *does* cover the root — which is why it reads green.
**AC11 covers this PR's own exposure in the meantime.**

### D-5 — Schema-check the 3 sibling templates → deferred

Each needs its own var map (three harnesses, not three lines). DHH dissents — *"you are
deferring the check because it might work"* — recorded as **T-1** in
`decision-challenges.md`. The honest rationale is the var-map cost, not the risk of
finding a defect; D-5's body says so.

### D-6 — `sentry_post_failures` → filed, not built (RR-19)

v1's route was fabricated. If wanted, the mechanism is `scripts/followthroughs/*.sh` +
`scheduled-followthrough-sweeper.yml`.

### Rejected for #6429

- **v1's H1 (population unreachability) + its prod tenant-count falsifier** — withdrawn
  (RR-17): the defect is in-file, the falsifier had no tooling, and two of its three
  outcomes led to the same action.
- **`value = 1`** — on a group that is not always-hot, `1` means ">1" and a single event
  does not page (`issue-alerts.tf:1357-1360`).
- **A `fingerprint` override** — the grouping axis is already fine (exception-event →
  stack-keyed).
- **Live-fire of the zot rule** (#6285's AC11) — a synthetic `ghcr-fallback` burst is
  counted by `zot-soak-6122.sh` (FAILs on ≥1), manufacturing a false FAIL on the gate that
  decides GHCR retirement. Read-back (AC3) is folded in; live-fire is not.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | Pre-fix tree, Phase-1 per-file grep | **FAILS** on all 7 files (non-vacuous) |
| T2 | `views.c4` includes `sentry`, `model.c4` does not define it | `c4-render.test.ts` **fails** |
| T3 | Sandbox emitter switched to `captureMessage` | Appended contract assertion **fails** |
| T4 | Doppler absent, baked DSN present | All 7 emitters POST; `sentry_source=baked` |
| T5 | **Malformed** DSN | `sentry_source=none`, **not** `baked`; garbage URL never POSTed |
| T6 | Baked DSN absent | Deploy still succeeds (fail-open) |
| T7 | Doppler control probe succeeds, `ZOT_REGISTRY_URL` empty | **Silent** (dark-launch contract preserved) |
| T8 | Control probe **also** empty | `zot_gate_indeterminate_event doppler_fetch_empty` emitted |
| T9 | Empty `${sentry_dsn}` tfvar at bake | Bootstrap **fails closed** (host never joins) |
| T10 | Rendered cloud-init with a malformed `write_files` | AC7's `cloud-init schema` **fails** |
| T11 | `cloud-init` unavailable on the runner | AC7 leg **SKIPs visibly** |
| T12 | Phase-3 edit shifts the `:1324-1385` block | AC6 **fails** unless re-anchored |

## Sharp Edges

- **v1 of this plan reproduced the exact defect it diagnosed.** RR-6 catches that the
  filed fix cannot fire; RR-16 catches that v1's *replacement* also could not. If you are
  editing Phase 4, the question to keep asking is **"can this code path actually
  execute in prod?"** — not "is this logic correct?"
- **`doppler_fetch_failed` is taken.** `ci-deploy.sh:1081` uses it as a deploy-state reason
  for a **hard abort**. Do not reuse it for a soft degradation.
- **`sed s///` on a non-match emits its input unchanged** — so a malformed DSN produces
  three non-empty *garbage* values that pass a `-n` guard. Validate the shape.
- **`${VAR:-}` does not protect the deploy.** It guards `set -u` on read. `set -e` +
  `pipefail` on a failing `grep` in a parse pipeline kills the deploy. Use `|| true`.
- **`issue-alerts.tf:1364` is the highest-risk within-file cross-reference in the repo.**
  #6424 staled it *in the PR whose purpose was fixing comment rot*.
- **76 bytes** — `cloud-init.yml` models at 21,724 vs a 21,800 budget, and the model
  **under-counts high-entropy secrets** (it models `sentry_dsn` as 80 `x`s, which gzip to
  nearly nothing). It is a standing guard (AC14) — but it does **not** bear on Phase 4
  (RR-20: the bootstrap is baked into the image).
- **`deploy-script-tests` is advisory.** AC7/AC8/AC13 will **not** block a merge. Until
  D-1 lands, a human must read them — the very failure mode #6446 documents.
- **A comment can mis-size a decision.** `ruleset-ci-required.tf:36-43` describes a
  reverted merge queue; it made v1 assert a false blocker. Comment rot is a
  decision-input defect, not cosmetic. That is the batch's thesis, and it bit the batch's
  own author twice.
- **`bun` vs `vitest`.** `plugins/soleur/test/**` is bun; `apps/web-platform/test/**` is
  vitest. *(v1's Sharp Edge claimed vitest "collects only `test/**/*.test.ts`" — **false**:
  `vitest.config.ts:44` is `["test/**/*.test.ts", "lib/**/*.test.ts"]` and co-located
  `lib/` tests do run. The **decision** to put the assertion in `test/` is right — it
  matches all 20 sibling `sentry-*-op-contract.test.ts` — but the stated reason was
  wrong. In a batch about false claims, in the Sharp Edges section.)*
- **Never `data "sentry_team"`.** It 403s and would wedge every future `apply-sentry-infra`.
