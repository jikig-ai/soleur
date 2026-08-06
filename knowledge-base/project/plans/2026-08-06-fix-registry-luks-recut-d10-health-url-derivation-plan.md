---
title: "fix: registry-luks-recut D10 gate reads a Doppler secret name that does not exist"
date: 2026-08-06
feature: feat-one-shot-d10-health-url-derivation
branch: feat-one-shot-d10-health-url-derivation
worktree: .worktrees/feat-one-shot-d10-health-url-derivation/
issue: 6929
lane: cross-domain
detail_level: MORE
status: planned
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff: "APPROVE WITH CHANGES (2026-08-06) — changes applied in v2"
decision_challenges: knowledge-base/project/specs/feat-one-shot-d10-health-url-derivation/decision-challenges.md
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# fix: the D10 health-URL derivation reads a secret that exists nowhere

> **v2 (post-review).** A six-reviewer panel cut roughly half of v1. The diagnosis
> and the committed-primary inversion survived verbatim; everything built *on top*
> of that decision — a Doppler cross-check tier, its flag surface, its asymmetric
> strictness, a sibling-conversion phase, and nine test rows — was removed. See
> `## Review Consolidation`.

## Overview

The `registry-luks-recut` dispatch is **unfireable**. Its D10 pull-path-health gate
derives the `/health` URL that defines the restore set from a Doppler secret named
`APP_DOMAIN_BASE`, reads it with no fallback, and hard-aborts when the read comes
back empty. The read always comes back empty: **`APP_DOMAIN_BASE` exists in zero of
the 13 Doppler configs in the `soleur` project.**

So the dispatch aborts at D10 PREPARE, before it ever reaches the destroy-guard, the
stock preflight, or the id-pin. It cannot run during exactly the incident it exists
to recover from.

**The fix:** derive the value from the committed Terraform variable that already
defines it, delete the credential the broken read needed, and keep the fail-closed
abort. The consuming script `scripts/registry-pull-path-health.sh` is not touched.

### Why this is not a typo fix

1. **The comment that justifies the bug asserts a false fact.** The block above the
   PREPARE read (anchor: `# APP_DOMAIN_BASE is a DOPPLER SECRET, not a GitHub Actions
   variable`) states the value *is* a Doppler secret. It is not one, in any config.
   ADR-166 ("a CI message may only name a cause the job measured") governs both
   `::error::` strings and the runbook row derived from them.

2. **The naive fix reproduces the pathology that hid the bug.** Two sibling call
   sites in the same file already "handle" this with
   `doppler secrets get APP_DOMAIN_BASE --plain 2>/dev/null || echo "soleur.ai"`.
   Because the name does not exist, those two have taken the hardcoded fallback
   **100% of the time since they shipped** — the `2>/dev/null || echo ""`
   swallow-to-empty antipattern named verbatim in `knowledge-base/project/constitution.md`
(anchor: "When building a fail-closed gate … audit EVERY input branch … for the
`2>/dev/null || echo \"\"` swallow-to-empty antipattern").

3. **The real source is committed config, and it defines the registry itself.**

### The provenance finding (measured, not argued)

`apps/web-platform/infra/variables.tf` declares
`variable "app_domain_base" { default = "soleur.ai" }`. It has **seven `var.` references**
across the infra root (a raw `grep -c app_domain_base` reports 8 — one hit,
`tunnel.tf`'s `ssh.${app_domain_base}`, is a comment with no `var.`; the
count-inflated-by-a-comment trap this plan warns about elsewhere):

- `server.tf` — `APP_DOMAIN_BASE  = var.app_domain_base`, the prod host's own env.
- `tunnel.tf` — `deploy.${var.app_domain_base}`, `ssh.${var.app_domain_base}`, and
  **`registry.${var.app_domain_base}`** (twice: the ingress rule and the Access
  application).

That last one is decisive: **the committed variable literally defines the registry
hostname the recut vehicle operates on.** A live sweep confirms
`TF_VAR_app_domain_base` is absent from Doppler `prd_terraform`, so the variable takes
its default — `variables.tf` is not a parallel copy of the value but the thing
Terraform actually applied.

The same workflow, in the **same job** (`registry_pull_path_gate`, which spans both
D10 arms and the stock probe), already carries a helper for exactly this (anchor:
`read_default() { # $1 = variable name`), with the rationale `this reads it from
variables.tf at run time … nothing here hardcodes a type`. The committed-config read
the gate script's own abort message describes was always available; the workflow
simply never implemented it.

**Verified:** the `read_default` awk idiom returns `soleur.ai` for `app_domain_base`,
and `https://app.soleur.ai/health` returns HTTP 200 with the `version` + `build_sha`
fields A0 requires.

### Why there is no Doppler tier

v1 proposed reading `APP_DOMAIN` from Doppler as a cross-check. Two reviewers
independently killed it, and the argument is decisive: **Doppler's `APP_DOMAIN` is a
derived sibling effect of `var.app_domain_base` — the same authoring intent written
down twice.** Checking one against the other detects "somebody edited one of two
copies"; it does not measure the host. It is an echo, not a second witness.

Worse, v1's `--strict-agreement` made irreversible-destroy authorization contingent
on a live credentialed read *agreeing* — reintroducing, inside the fix, the exact
class the fix exists to remove, on the one path where the plan had already argued
credentials are least trustworthy.

Removing the tier has a concrete dividend. `DOPPLER_TOKEN_PRD` is declared in both
D10 step `env:` blocks and used **only** by the two broken reads — nothing else in the
job touches it. So this change **deletes a production credential from the recovery
path**, and the PREPARE step becomes fully credential-free. That is a stronger
expression of **ADR-169's independence criterion** than v1 achieved. (v1 cited ADR-164
here; architecture review showed that is a category error — see Architecture Decision.)

---

## Premise Validation

Every premise carried in from the task framing was re-checked live on 2026-08-06.

| Premise as given | Verification run | Result |
|---|---|---|
| `APP_DOMAIN_BASE` exists in no Doppler config | Enumerated all 13 configs of project `soleur`, filtered `^APP_DOMAIN` | **HOLDS.** Zero hits in all 13 |
| `APP_DOMAIN` exists in `soleur/prd` = `app.soleur.ai` | `doppler secrets get APP_DOMAIN -p soleur -c prd --plain` | **HOLDS**, but now moot — no Doppler tier ships |
| `https://app.soleur.ai/health` returns the fields A0 needs | `curl -sf --max-time 20 -H 'Cache-Control: no-cache'` | **HOLDS.** HTTP 200, `{status:ok, version:0.249.4, build_sha:f838839e…}` |
| Sibling call sites "already handle this correctly" | Read both sites; cross-checked against the sweep | **FALSE — R1.** They never read the secret at all |
| The fix belongs on the live-read side | Traced `var.app_domain_base` across the infra root | **REVISED — R7.** Committed config is the causal source |
| Existing suites are green pre-change | `bash tests/scripts/test-registry-pull-path-health.sh` | **HOLDS.** 60 passed, 0 failed |
| Blocked issue `#6929` still open | `gh issue view 6929` | **HOLDS.** Open, but mislabeled — see D6 |
| No open issue tracks this bug | `gh issue list --state open --search "APP_DOMAIN"` | **HOLDS.** Returns `[]` |
| `REGISTRY_LUKS_KEY` "handled separately" | `gh issue list --state open --search "REGISTRY_LUKS_KEY"` | **PARTIALLY FALSE — R9.** Only hit is `#7316`, a generic auto-filed drift issue whose plan body contains `doppler_secret.registry_luks_key will be created`. Not tracked *as the blocker* |

**Mechanism vs. the ADR corpus.** No ADR rejects deriving config from `variables.tf`.
The governing decision is **ADR-169** (anchor: a gate on an irreversible destroy may not
depend on the component whose failure motivates it), *not* ADR-164 — whose mechanism is
list-scoping/denominator co-narrowing and does not apply to a single-key GET. `ADR-096` canonised the
wrong name and needs amending. `ADR-007` (Doppler secrets management) is a 19-line
stub with no naming or existence convention — the gap that let this ship.

---

## Research Reconciliation — Spec vs. Codebase

| Claim as framed | Codebase reality | Plan response |
|---|---|---|
| **R1.** "Two sibling call sites already handle this correctly." | They emit `\|\| echo "soleur.ai"` against a name that resolves nowhere, so the fallback fires on every execution. They are hardcoded via a Doppler call that has never returned a value. | Do not copy them. Do not convert them here either (see R10) — fold into the D4 sweep. |
| **R2.** "Read `APP_DOMAIN`; if it starts with `app.` use it as the host directly." | The consuming script builds `https://app.${APP_DOMAIN_BASE}/health`, so the workflow must export a **base**, not a host. | Moot — no Doppler tier ships. The committed variable is already a base. |
| **R3.** "Add a bare `\|\| echo "soleur.ai"` if no cleaner derivation exists." | A cleaner derivation exists in the same job. | Never introduce a literal domain anywhere. |
| **R4.** Fix belongs in `scripts/registry-pull-path-health.sh`. | Its guard line is a **byte-fragile mutation anchor**: battery case G23 requires `[[ -n "${APP_DOMAIN_BASE:-}" ]] \|\| abort A0 ` to stay present **and unique**; any byte change makes the battery `harness_die` (exit 2, no verdict). | **Do not touch the script.** AC5 asserts it is byte-clean. |
| **R5.** Existing suites would catch a regression. | `run_gate()` injects `APP_DOMAIN_BASE="${APP_DOMAIN_BASE-soleur.ai}"`, so the seam sits **above** the read — the read has no test. No test anywhere reads the D10 steps. | Add two small suites (Phases 1, 5). |
| **R6.** Documentation is unaffected. | Three artifacts carry the wrong name: the runbook's A0-ABORT row (points at a Doppler lookup returning nothing, mid-incident), its cold-vehicle check 1 (claims the suites establish the `/health` parse is exercisable — they inject the value), and `ADR-096`'s cold-vehicle item 3. | Phase 7. |
| **R7.** `variables.tf` is a reasonable *fallback*. | It is the **causal source**: 8 references, including `registry.${var.app_domain_base}` in `tunnel.tf`. | Make it the **only** source. |
| **R8.** A shared script needs parameterized Doppler credentials. | The D10 arms carry `DOPPLER_TOKEN_PRD`/`prd`; the siblings carry `DOPPLER_TOKEN`/`prd_terraform`. | Moot — no Doppler tier, and no sibling conversion. |
| **R9.** The `REGISTRY_LUKS_KEY` precondition is "handled separately". | Its only tracker is `#7316`, an auto-filed drift report titled "infra: drift detected in web-platform" whose body happens to contain the create-plan. Nothing links it to the recut. | **D5** makes the linkage explicit in Risk 3 and the runbook. |
| **R10.** Converting the sibling sites is in scope ("health-URL derivation only"). | A web-host **replace** is a live possibility during this very incident. | **Cut.** Blast-radius objection, not a scope one. Folded into D4 (now 7 sites). |
| **R11.** `export X=$(cmd)` preserves fail-closed under `set -euo pipefail`. | **Measured false.** `export X=$(bash failing.sh)` exits 0 and continues; `X=$(bash failing.sh); export X` exits 1. | AC3 and W5 pin the bare-assignment form at both call sites. |

---

## Hypotheses

None required. The root cause was **measured**: the secret name was swept against all
13 live Doppler configs and returns zero hits, and the replacement source was read and
its round-trip through the gate's URL template verified against a live HTTP 200
`/health`. No competing hypothesis survives.

---

## User-Brand Impact

**If this lands broken, the user experiences:** the recut stays unfireable, so the
registry stays at 100% and the deploy path stays dead. The concrete user-facing
consequence is not "deploys fail" — it is that **no security patch, hotfix, or
user-facing bug fix can reach the hosted platform at `app.soleur.ai` while the deploy
path is down.** That has been true for three days, and it is true during week one of
the alpha onboarding motion that started 2026-08-06 (`#1439`, 1 of 10 testers). A
second-order vector: `ADR-096` records that `registry_region_migrate_gate` has **no
D10 gate at all**, so an operator blocked on the guarded path is pushed toward the
unguarded one — exactly what the runbook warns against.

**If this lands subtly wrong, the user experiences:** a derivation resolving to the
wrong host yields a restore inventory for a host nobody measured. The gate then
authorizes an irreversible destroy against a restore set that does not cover
production. Running containers survive, so nothing looks broken — until the next
deploy or host replace, which cannot re-materialise any image.

**If this leaks, the user's data is exposed via:** no new exposure vector. The only
value handled is a public DNS name. No credential is newly read, logged, or widened —
this change **removes** one (`DOPPLER_TOKEN_PRD`) from the D10 steps.

**Brand-survival threshold:** `single-user incident`

**Note on the tier.** The blast radius described above is platform-wide, which reads
as `aggregate pattern` semantically. The tier is deliberately kept at `single-user
incident` because the higher tier buys a **weaker** gate, not a stronger one:
`plan/SKILL.md` adds no per-PR sign-off for `aggregate pattern`, and `ship/SKILL.md`'s
`compliance/critical` auto-label greps `^brand_survival_threshold:\s*single-user
incident` only, so `user-impact-reviewer` would never be invoked. This ladder
inversion is a repo-wide trap and is filed as **D7**.

---

## Architecture Decision (ADR/C4)

### ADR

**Amend `ADR-096`** (`ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`)
— it canonised the wrong name. Its 2026-08-05 (#7277) amendment block lists
cold-vehicle surface 3 as *"The `/health` parse — `version` + `build_sha` from
`APP_DOMAIN_BASE`"* without saying where that value comes from. Amend to name the real
provenance chain (`variables.tf app_domain_base` → `server.tf` / `tunnel.tf`) and
record that the secret named in the original text never existed.

**Amend `ADR-169`'s independence criterion** — *not* ADR-164. v1 and the first draft of
v2 both cited ADR-164 ("a coverage/health metric's denominator must come from a source
the measured credential cannot move"). Architecture review showed that is a **category
error**: ADR-164's mechanism is *silent scoping of list results causing a denominator to
co-narrow with its numerator*. The D10 case has no list, no denominator, and no
numerator — `doppler secrets get APP_DOMAIN` is a single-key GET that returns a value or
errors. (ADR-164's Decision 1 is also superseded by ADR-168 and carries a
"DO NOT BUILD ON THIS DECISION" block.)

The correct parent is **ADR-169**, which already governs this exact gate: *"A gate on an
irreversible destroy may not depend on the component whose failure motivates it."* This
change extends that criterion from *components* to *authorizing inputs*: an input that
authorizes an irreversible destroy is sourced from committed configuration, not from a
credential-scoped read. That is a genuine extension and belongs as an ADR-169 amendment.

ADR-169 additionally **does not model the PREPARE/VERDICT split or the resume arm at
all** — its predicate table treats A0 as a single derivation. Phase 8's condition must
therefore be widened: amend ADR-169 regardless of whether it mentions the Doppler
sourcing (a check that resolves to *no edit* and would have missed this).

> **v1 proposed a new ADR-171 for this.** DHH argued it is ADR-splitting by noun, and
> further that ADR-171's actual stated decision ("a credential-scoped read may serve
> as an advisory cross-check but may not be primary") **has no referent once the
> cross-check is cut** — it would ratify an architecture that is not being built. CPO
> argued to keep it under `wg-architecture-decision-is-a-plan-deliverable`. The
> workflow gate is satisfied by an ADR *amendment*, which is one of its two named
> outputs ("New decision → new ADR; divergence from or extension of an existing one →
> amend that ADR"). Amending ADR-164 + ADR-096 discharges it. Recorded so the choice
> is auditable; `deepen-plan` may reverse it. Cutting the new ADR also removes the
> ordinal-collision surface entirely.

**Check `ADR-169`** (`what-authorizes-destroying-the-sole-pull-path`). This plan does
not change the authorization *condition*, only one input's derivation. `/work` must
read it and amend **only if** it independently asserts the Doppler sourcing.

The insight that *a code comment asserting a premise is a cause-claim under ADR-166*
is folded into ADR-096's amendment prose rather than shipped as a separate ADR-166
amendment (three reviewers flagged the standalone amendment as scope creep).

`ADR-007` (Doppler secrets management) is the durable home for a workflow-read naming
convention — deferred as **D1**.

### C4 views

**No C4 impact.** Checked against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`),
enumerating what this change touches rather than grepping the feature's own noun:

- **External human actors** — none introduced.
- **External systems** — `Doppler` is already modelled (`model.c4`, anchor
  `doppler = system "Doppler"`, tagged `#external`) and already rendered in both views.
  This change **reduces** the system's reliance on it in this job; it adds nothing.
- **Containers / data stores** — none touched. The change reads a file already in the
  job's checkout.
- **Actor ↔ surface access relationships** — the `github -> doppler` edge already
  exists (anchor: `github -> doppler "scheduled-terraform-drift's token-drift scan
  reads token-shaped keys across the soleur project's configs…"`). No edge is added; no
  token scope widens; one credential reference is removed.
- **Element descriptions falsified by the change** — none. No `.c4` description asserts
  anything about how the health URL is derived.

---

## Observability

```yaml
liveness_signal:
  what: "Both D10 steps emit a machine-greppable resolution line to stderr — `derive-app-domain-base: base=<v> source=<path> health_url=<url>` — so every dispatch records which file decided the restore set."
  cadence: "Per registry-luks-recut dispatch (operator-initiated, not scheduled)."
  alert_target: "The dispatching operator/agent reading the run log; ::error:: annotations surface in the GitHub Actions run summary."
  configured_in: ".github/workflows/apply-web-platform-infra.yml, job registry_pull_path_gate; emitted by scripts/derive-app-domain-base.sh"

error_reporting:
  destination: "GitHub Actions ::error:: annotations on the dispatch run. This is a manually dispatched, operator-supervised workflow — the run summary IS the operator-facing channel; there is no long-lived server process to mirror to Sentry."
  fail_loud: true

failure_modes:
  - mode: "variables.tf unreadable, or app_domain_base absent"
    detection: "derive-app-domain-base.sh exits non-zero; ::error:: names the file and the variable it looked for, asserting no cause beyond what was measured (ADR-166)"
    alert_route: "Run fails at PREPARE; nothing is destroyed."
  - mode: "app_domain_base present but malformed (scheme, slash, whitespace, no dot)"
    detection: "Shape guard rejects it and exits non-zero, naming the rejected value. Without this the gate would build https://app./health and the curl failure would blame the endpoint rather than the derivation."
    alert_route: "Run fails at PREPARE; nothing is destroyed."
  - mode: "A future TF_VAR_app_domain_base override makes the committed default stale"
    detection: "The resolution line names the file it read, so the run log states the assumption. The runbook's cold-vehicle checklist re-asserts the override is absent before a first fire."
    alert_route: "Operator reading the run log / completing the checklist. NOT auto-detected — declared as a known limitation, tracked by D3."
  - mode: "Derivation silently regresses to the nonexistent secret name in a future edit"
    detection: "tests/scripts/test-registry-d10-workflow-wiring.sh asserts, over the COMMENT-STRIPPED workflow body, that no `doppler secrets get APP_DOMAIN_BASE` invocation remains"
    alert_route: "CI `scripts` shard goes red on the PR that reintroduces it."
  - mode: "A call site uses `export X=$(cmd)`, silently breaking the fail-closed chain"
    detection: "W5 asserts both bodies use a bare assignment with `export` on its own line, and that both retain `set -euo pipefail`."
    alert_route: "CI `scripts` shard goes red."

logs:
  where: "GitHub Actions run logs for apply-web-platform-infra.yml (job registry_pull_path_gate), retrievable with `gh run view`."
  retention: "GitHub default workflow-log retention; the pinned restore manifest is uploaded as an artifact with retention-days: 7."

discoverability_test:
  command: "bash scripts/derive-app-domain-base.sh   # prints the base on stdout and the resolution line on stderr; runnable from any checkout, no SSH, no CI, no credential"
  expected_output: "stdout `soleur.ai`; stderr `derive-app-domain-base: base=soleur.ai source=apps/web-platform/infra/variables.tf health_url=https://app.soleur.ai/health`"
```

No post-deploy soak or time-gated close criterion is declared, so no follow-through
enrollment is owed. The D10 job is a GitHub Actions runner with fully readable logs,
not a blind execution surface, so §2.9.2's in-surface-probe requirement does not apply.

---

## Reversible Mitigation

`hr-weigh-every-decision-against-target-user-impact` and CPO review both require this
to be on the record: **the only modeled exit from a three-day outage must not be an
irreversible destroy without a reversible alternative having been evaluated.**

Note the shape of the problem. The `registry-luks-recut` vehicle was designed to move
the store volume from plaintext ext4 to guest-side LUKS (`#6929`, ADR-096 amendment) —
**it was not designed as a disk-pressure remedy.** Using it to resolve a full volume is
reusing an encryption-migration vehicle for a capacity problem, and that reuse is worth
stating plainly rather than inheriting.

`/work` must complete this section before implementation, recording for each candidate
whether it was viable and on what **measured** ground it was accepted or rejected:

| Candidate | Reversible? | Verdict | Evidence |
|---|---|---|---|
| zot GC / retention policy | yes | **Already at its floor.** `gc: true`, `gcDelay 1h`, `gcInterval 1h`, `dedupe: true`, plus a retention policy already tightened twice (#6240, #6247) | `cloud-init-registry.yml`, `write_files` → `/etc/zot/config.json` |
| On-demand GC trigger | yes | **Does not exist.** Measured 2026-08-05 (#7282): `/v2/_zot/gc`, `/v2/_catalog/gc`, `/_zot/gc`, `/v2/_zot/ext/gc` all 404; the release's BinaryType excludes mgmt/scrub/search. GC also reclaims only *dangling* blobs, never a blob the keep-set retains | same file's header comment |
| Prune on the host over SSH | yes | **Not reachable.** `disk-monitoring.md` has the recipes but is scoped to the web CX33 and opens with `ssh root@…`. The registry host is deny-all-ingress with no SSH ("There is no SSH in this runbook") | `disk-monitoring.md`, recut runbook |
| In-place restart lever | yes | **Unshipped.** `#7278` is still a plan; the runbook says "**Both** levers are currently unavailable" | `2026-08-04-feat-registry-zot-restart-lever-plan.md` |
| **Hetzner volume online grow** (`registry_volume_size` 60 → N) | **yes** | **Mechanically available and ADR-sanctioned — but its delivery vehicle is self-blocked.** `hcloud_volume.registry` has no `lifecycle` block; the variable's own comment says "A bump resizes the volume in place (data survives)"; the exact precedent is ADR-096's 30 → 60 GB grow, and `registry-host-replace-gate.sh` deliberately permits a volume `["update"]`. **Blocked because:** the ext4 only grows at boot, the only boot vehicle is `registry-host-replace`, and that (a) FATALs on the still-plaintext volume (`reason=refusing-non-luks-device`) and (b) aborts with `out_of_scope=2` because the #6929 LUKS resources are declared but absent from state | `zot-registry.tf`, `variables.tf` `registry_volume_size`, ADR-096, runbook |
| `registry-luks-recut` (destroy + recreate) | **no** | The sanctioned vehicle on file — **for encryption-at-rest, not disk pressure** | runbook `registry-luks-recut-6929.md` |

**Conclusion.** A reversible path exists and is the architecturally preferred one: grow
the volume and boot via `registry-host-replace`. It is blocked by **code/state drift**
(LUKS resources in config but not in state; boot code refusing the plaintext device) —
not by physics — and unblocking it is a `-target`-set/state reconciliation, itself
reversible.

Two consequences this plan must carry rather than bury:

1. **The recut is being used for a problem it was not designed for.** Its runbook opens
   *"destroys the container registry's storage volume and rebuilds it encrypted"*; disk
   pressure appears nowhere in it. Worse, its "disposable mirror" premise is retracted —
   ADR-096: *"THE 'DISPOSABLE' PREMISE NO LONGER HOLDS (2026-07-30) … an emptied store
   re-fills only from a fresh CI dual-push, and until one lands there is NO registry any
   host can pull from."* And a recut leaves `registry_volume_size` at 60, i.e. back at
   the same ceiling after the restore.
2. **This PR still ships regardless.** The D10 gate is broken on its own terms and must
   be fixed whichever remedy is chosen — the recut is not the only consumer of a working
   gate. But the operator's *recommended next step* is not obviously "fire the recut",
   and Phase 7 must say so rather than let a fixed gate read as an endorsement.

---

## Open Code-Review Overlap

- **`#7098`** — *"ci: audit the 56 `run:` bodies whose `set` omits `-e` …"*. Matches on
  `.github/workflows/apply-web-platform-infra.yml`.
  **Disposition: acknowledge.** Different concern (errexit inheritance, cf. ADR-170).
  Both D10 bodies already open with `set -euo pipefail`, so they are not in that
  issue's affected set. W5 pins that invariant — and note it is **load-bearing here for
  a different reason than #7098's**: without `set -e`, a bare assignment does not
  propagate the derivation script's non-zero exit, and one third of the fail-closed
  chain is gone. The scope-out remains open; `/work` cross-references it without
  claiming to close it.

No other open `code-review` issue matches any planned path.

---

## Domain Review

**Domains relevant:** Engineering, Operations, Product

### Engineering (CTO)

**Status:** reviewed. Recommended the committed-primary inversion (four grounds, all
live-verified); identified the sibling-credential blocker in v1's shared-script design;
surfaced the `local x=$(cmd)` exit-status hazard, the empty-but-successful Doppler read,
and the missing post-strip shape guard. The first two findings are moot in v2 (no
Doppler tier); the shape guard and the assignment-form hazard are carried as AC3/AC4
and W5.

### Operations (COO)

**Status:** reviewed (inline). This is the blocking dependency for an active production
incident. The operationally important property — that the fix must not make the
recovery vehicle *more* dependent on live credentials — is now satisfied literally:
v2 **removes** `DOPPLER_TOKEN_PRD` from the recovery path. Merging does not remediate
the incident (Risk 3).

### Product (CPO)

**Status:** reviewed — **APPROVE WITH CHANGES**, all six required changes applied in v2
(D5 tracking linkage, Phase 4 cut, Reversible Mitigation section, threshold reasoning,
naming the user and the hosted platform, tracker corrections as D6).

### Product/UX Gate

**Not applicable.** The mechanical UI-surface override was evaluated against every path
in Files to Edit and Files to Create; none matches `components/**/*.tsx`,
`app/**/page.tsx`, `app/**/layout.tsx`, or any other UI-surface glob.

### GDPR / Compliance Gate

**Invoked** on trigger (b) (`single-user incident` threshold); the canonical
regulated-data regex does not match. **Finding: no regulated-data surface.** The only
value handled is a public DNS name. No personal data, no new processing activity, no
new sub-processor. No Article 30 entry owed.

### Infrastructure-as-Code Gate

<!-- lint-infra-ignore start -->
<!-- This paragraph ENUMERATES the detection set in order to record that the plan does
     NOT trigger any of it. Reproducing the trigger tokens in a negative finding is the
     documented false-positive shape for lint-infra-no-human-steps. -->

**Reviewed; not applicable.** Scanned against the detection set: no `ssh <user>@<host>`,
no systemd unit, no `systemctl`, no Doppler *write* of any kind, no `terraform import`,
no vendor-dashboard step, no cron, no new vendor account. **The plan provisions
nothing** and, in v2, *de-provisions* a credential reference.

<!-- lint-infra-ignore end -->

**No `.tf` file is edited, deliberately** — see D3. `apply-web-platform-infra.yml` fires
on `infra/*.tf` merges, and triggering an infra apply while the registry is
crash-looping is an avoidable coupling. AC8 pins this.

### Encryption Posture Gate

**Not applicable.** No persistent data store and no new cross-component connection. No
file in Files to Edit / Create matches `\.tf$`, `supabase/migrations/.*\.sql$`,
`cloud-init.*\.ya?ml$`, or `docker-compose.*\.ya?ml$`.

---

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

0.1 Confirm `variables.tf` still declares `app_domain_base` with a default, and that
`server.tf` and `tunnel.tf` still consume it.

0.2 Confirm `TF_VAR_app_domain_base` is still absent from Doppler `prd_terraform`. If it
has appeared, the default is no longer the applied value and the derivation must read
the override instead.

0.3 Record the current `scripts/registry-pull-path-health.sh` hash; it must be
byte-identical at the end of the PR (AC5).

0.4 Establish the baseline — run `bash tests/scripts/test-registry-pull-path-health.sh`
and `bash tests/scripts/test-registry-gate-mutation-battery.sh` green **before** any
edit. *(The first was verified green at 60/0 during planning.)*

0.5 Complete the `## Reversible Mitigation` table.

### Phase 1 — RED: the derivation unit suite

Write `scripts/derive-app-domain-base.test.sh` first, failing. It points the script at
fixture `variables.tf` files. Cases in Test Scenarios.

The `scripts/*.test.sh` placement is deliberate: `scripts/lint-orphan-test-suites.sh`
covers that glob and **mechanically requires** registration, closing the orphan-suite
hole (#3366) a `tests/scripts/` placement would leave open.

### Phase 2 — GREEN: `scripts/derive-app-domain-base.sh`

A ~25-line script. **One source, one positional parameter, no flag parsing.**

```
$1 = path to variables.tf   (default: ${GITHUB_WORKSPACE:-.}/apps/web-platform/infra/variables.tf)
stdout = the resolved base, and nothing else   (callers command-substitute it)
stderr = derive-app-domain-base: base=… source=… health_url=…
exit 1 + ::error:: when the value is missing or malformed
```

- **Honour Terraform's own precedence, not just the default.** The plan's provenance
  claim is "what Terraform applied" — but a `variables.tf` `default =` is only that while
  no override exists. Read `TF_VAR_app_domain_base` (equivalently, an `APP_DOMAIN_BASE`
  entry in the Doppler `prd_terraform` config, which the `--name-transformer tf-var`
  invocation maps onto it) **first**, and fall back to the committed default. Encoding
  this in the script is what makes the primary genuinely "what Terraform applied"; a
  one-time plan-phase precondition does not. Absent an override — the measured state
  today — behaviour is identical.
- Parse with the existing awk idiom, but **anchor the variable name including its
  opening brace** so `app_domain_base` cannot prefix-match a hypothetical
  `app_domain_base_legacy`.
- **Do not trust the idiom's exit status.** `read_default`'s pipeline ends in
  `| head -1 | sed …`, so it exits 0 even when the variable is absent; the existing
  caller compensates with a `-z` test. Test for emptiness explicitly — a reader copying
  the idiom without that check reintroduces this bug class.
- Shape-guard the result: must contain a dot; must not contain a scheme, a slash, or
  whitespace; must not itself begin with `app.`.
- Use `local x; x=$(cmd) || x=""` rather than `local x=$(cmd)` — the latter swallows the
  command's exit status even under `set -e`.
- **Resolve the default `variables.tf` path independently of CWD.** Several steps in this
  workflow set `working-directory:`, and the discoverability contract requires the script
  to run "from any checkout". Derive from the script's own location (or
  `git rev-parse --show-toplevel`) with a `$GITHUB_WORKSPACE` override; add a test that
  the script is CWD-independent.

*Considered and rejected:* computing once in PREPARE and passing via `$GITHUB_ENV`
(zero new files). It couples VERDICT to PREPARE's state, whereas the workflow
deliberately has VERDICT re-derive over the same path. A script also makes the
derivation testable, which a `run:` body is not — and that untestability is precisely
why this bug survived (R5).

### Phase 3 — Rewire both D10 arms

In **both** the PREPARE and VERDICT steps, replace the Doppler block with:

```bash
APP_DOMAIN_BASE=$(bash "${GITHUB_WORKSPACE}/scripts/derive-app-domain-base.sh")
[[ -n "$APP_DOMAIN_BASE" ]] || { echo "::error::…"; exit 1; }
export APP_DOMAIN_BASE
```

**The bare assignment is load-bearing and measured.** `export X=$(cmd)` exits 0 even
when `cmd` fails, silently breaking the fail-closed chain; `X=$(cmd)` followed by a
separate `export` propagates the failure under the bodies' existing `set -euo pipefail`.
Fail-closed then holds three times over: the script exits non-zero, the assignment
propagates it, the `-z` guard remains, and `registry-pull-path-health.sh` aborts A0
independently.

**Delete `DOPPLER_TOKEN_PRD`.** In PREPARE that removes the step's entire `env:` block
(it contains nothing else), making the step credential-free. In VERDICT remove only the
`DOPPLER_TOKEN_PRD:` line — `DOPPLER_TOKEN`, `REHEARSE_TARGET`, and the `ZOT_PUSH_*`
entries stay.

Rewrite the false comment to **one or two sentences** stating what was measured. Keep it
short: v1's long explanatory prose is what forced the wiring suite to build a
comment-stripping harness in the first place.

Both step bodies shrink, keeping them clear of the 65536-byte `run:` pipe-buffer ceiling
that `ci.yml`'s actionlint step guards (#7002).

### Phase 4 — Convert the restore leg's dark read (in the recut's own chain)

v1's *web-host birth/replace* conversion stays cut (three reviewers; a host replace is a
live possibility during this incident). But review found an instance that is **not
adjacent to this dispatch — it is inside it**:

`.github/actions/cf-tunnel-registry-bridge/action.yml` carries the same dark read and
uses it to derive the host it pushes to:

```bash
# APP_DOMAIN_BASE is not in prd — fall back to the canonical default exactly …
APP_DOMAIN_BASE=$(doppler secrets get APP_DOMAIN_BASE --plain 2>/dev/null || echo "soleur.ai")
…
  --hostname "registry.${APP_DOMAIN_BASE}" \
```

That action is invoked by the **`registry_store_restore`** job — the leg chained off the
D10 manifest that refills the emptied registry. So without this phase the same dispatch
would derive the base two different ways: the gate from committed config, and the leg
that actually pushes images from a hardcoded literal behind a dead read. Risk 1's
wrong-host hazard has an unaddressed twin on the **write** side.

Convert it to the shared derivation. Keep it **non-fatal** at this site (`|| true` into
the existing fallback shape is not acceptable — instead let the script's own failure
surface, but verify the step already runs under a body that can report it): this leg runs
*after* the destroy, so a new hard abort here strands an empty registry.

Note the action's comment **already states the true fact** the D10 comment denies
("`APP_DOMAIN_BASE` is not in prd"). Cite it in the ADR-096 amendment — the knowledge
existed in the repo and the two comments contradict each other.

`cf-tunnel-ssh-bridge/action.yml` carries the same read for `ssh.${APP_DOMAIN_BASE}` but
is **not** in the recut chain — it stays in D4.

### Phase 5 — Workflow-wiring suite

Add `tests/scripts/test-registry-d10-workflow-wiring.sh`, modelled on
`tests/scripts/test-preapply-entrypoint-gate.sh` (anchors: `_workflow_code()`,
`_gate_step_body()`). Implement as **one loop over both step bodies** asserting the
shared properties, not one row per arm per property.

**Strip comments before every assertion** — the trap
`test-destroy-guard-counter-web-platform.sh` records in its header. **Carry a vacuity
floor**: assert both bodies extract non-empty before asserting anything about content.

Must be a **separate file**, not appended to `test-registry-pull-path-health.sh`: the
mutation battery sandboxes that suite into a tree with no `.github/` directory, so
workflow-reading rows would go red in the battery's baseline and `harness_die` it.

### Phase 6 — Register both suites

Nothing auto-discovers `tests/scripts/test-*.sh`. Hand-add `run_suite` lines in
`scripts/test-all.sh` inside the `if want_scripts; then` block, the wiring suite next to
its D10 siblings (anchor: the existing `run_suite "tests/scripts/registry-pull-path-health" …`
line) with the same orphan-trap comment the neighbours carry.

### Phase 7 — Runbook corrections

`knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`:

7.1 The `registry-pull-path-health: A0 ABORT` row points at a Doppler lookup that
returns nothing. Repoint it at `variables.tf` and at
`bash scripts/derive-app-domain-base.sh`.

7.2 Cold-vehicle check 1 claims running the two suites establishes the `/health` parse
is exercisable; the suites inject the domain. Add a live-input line that resolves the URL
the dispatch will use, **and** an assertion that `TF_VAR_app_domain_base` is still absent
from `prd_terraform` (the standing assumption behind the derivation).

7.3 The residual-blockers section reads as *unblocked*. Record both live blockers — this
bug, and the missing `REGISTRY_LUKS_KEY` (tracked inside `#7316`) — and remove this one
when the fix lands.

### Phase 8 — ADR work

Amend **ADR-096** cold-vehicle item 3; widen **ADR-164**'s applicability by one
sentence; read **ADR-169** and amend only if it asserts the Doppler sourcing.

### Phase 9 — File the deferrals and fix the tracker

Create D1–D7. Verify every label with `gh label list --limit 200` first — verified
available: `deferred-scope-out`, `domain/engineering`, `chore`, `priority/p0-critical`,
`priority/p1-high`, `type/bug`, `type/chore`.

---

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` — both D10 arms; the false comment;
  delete `DOPPLER_TOKEN_PRD` from both steps.
- `scripts/test-all.sh` — register both new suites under `want_scripts`.
- `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` — three
  corrections.
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`
- `knowledge-base/engineering/architecture/decisions/ADR-164-*.md` — one-sentence
  applicability widening.
- `knowledge-base/engineering/architecture/decisions/ADR-169-what-authorizes-destroying-the-sole-pull-path.md`
  — **conditional**; only if it asserts the Doppler sourcing.

## Files to Create

- `scripts/derive-app-domain-base.sh`
- `scripts/derive-app-domain-base.test.sh`
- `tests/scripts/test-registry-d10-workflow-wiring.sh`

## Files deliberately NOT edited

- `scripts/registry-pull-path-health.sh` — byte-fragile mutation anchor (G23).
- `tests/scripts/test-registry-pull-path-health.sh`,
  `tests/scripts/test-registry-gate-mutation-battery.sh` — asserted byte-clean by AC5.
- `apps/web-platform/infra/*.tf` — see D3 and AC8.
- The two sibling call sites — see R10 and D4.

---

## Acceptance Criteria

### Pre-merge (PR)

**AC1 — the dead name is gone from the executable path.** Over the
**comment-stripped** workflow body, `grep -c 'doppler secrets get APP_DOMAIN_BASE'`
returns `0`. Note `grep -c` **exits 1 when the count is zero**, so the AC harness must
not run it bare under `set -e` — capture with `|| true` and compare the number.
*(Verified pre-fix: the same command returns `4`, so the check discriminates. Comment stripping is required — the name survives in the rewritten
prose.)*

**AC2 — the credential is gone.** `DOPPLER_TOKEN_PRD` appears nowhere in the
`registry_pull_path_gate` job, and the PREPARE step has no `env:` block at all.

**AC3 — the call-site assignment form preserves fail-closed.** Both D10 bodies use a
bare `APP_DOMAIN_BASE=$(…)` with `export` on a separate line — never
`export APP_DOMAIN_BASE=$(…)`, which is measured to exit 0 on a failing command and
would silently break the chain.

**AC4 — the derivation is correct, credential-free, and fails closed.** With no Doppler
token present, `bash scripts/derive-app-domain-base.sh` prints `soleur.ai` on stdout and
the resolution line on stderr, and `https://app.soleur.ai/health` returns HTTP 200 with
non-empty `.version` and `.build_sha`. Pointed at a missing file, at a file lacking
`app_domain_base`, and at each malformed shape, it exits non-zero with an `::error::`
naming the file and variable.

**AC5 — the consuming gate is untouched.**
Compare against the **Phase 0.3 recorded hash**, and/or use a three-dot diff
(`git diff --stat origin/main...HEAD -- <paths>`). A two-dot `git diff origin/main`
compares against main's moving tip, so an unrelated merge touching those paths reports
the gate as "touched" — a false block pointing at the wrong cause. The check
produces no output, and `bash tests/scripts/test-registry-gate-mutation-battery.sh` exits
**0** — not 2, which is a harness fault meaning the anchor drifted.

**AC6 — the whole shard is green, run through its own entry point.**
`bash scripts/test-all.sh scripts` exits 0, and `bash scripts/lint-orphan-test-suites.sh`
exits 0.

**AC7 — the false comment is gone.** The workflow contains no assertion that
`APP_DOMAIN_BASE` is a Doppler secret; the replacement names only what was measured
(ADR-166).

**AC8 — the merge does not fire an unplanned production apply.** The workflow lists
**its own path** in `on.push.paths` (anchor: `- ".github/workflows/apply-web-platform-infra.yml"`),
so editing it triggers `push` → the `apply:` job → a production `terraform apply`.
A `.tf`-scoped diff check does **not** establish otherwise. The merge commit message
must therefore contain `[skip-web-platform-apply]` on its own line — the workflow's
documented kill switch (anchor: `Kill switch: include \`[skip-web-platform-apply]\` on its own line`),
consumed by `needs.preflight.outputs.skip != 'true'`. AC asserts the token is present
in the merge commit and that the `apply:` job reports skipped.

**AC9 — the runbook no longer sends the operator to a nonexistent secret**, its
cold-vehicle section carries the live-input and `TF_VAR` checks, and its
residual-blockers section names both live blockers.

**AC10 — ADR-096 names the real provenance** and records that the originally-named
secret never existed; ADR-164's applicability is widened.

**AC11 — the Reversible Mitigation table is complete**, every row carrying a verdict and
measured evidence.

**AC12 — deferrals and tracker corrections are filed.** D1–D7 exist as issues with
verified labels.

### Post-merge (operator/agent)

**AC13 — the dispatch reaches its destroy-guard.** Not verified in this PR. The recut,
the terraform apply, and any infra dispatch are out of scope. **Merging does not
remediate the incident** — see Risk 3.

---

## Test Scenarios

### `scripts/derive-app-domain-base.test.sh`

| # | Fixture `variables.tf` | Expect |
|---|---|---|
| T1 | `app_domain_base` default `soleur.ai` | stdout `soleur.ai`; exit 0; stderr resolution line names the file |
| T2 | default `dev.soleur.ai` | stdout `dev.soleur.ai`; exit 0 (no hardcoded domain anywhere) |
| T3 | file missing | exit non-zero; `::error::` names the path |
| T4 | present, `app_domain_base` absent | exit non-zero; `::error::` names the variable |
| T5 | malformed: `https://soleur.ai` (scheme) | exit non-zero |
| T6 | malformed: `soleur.ai/x` (slash) | exit non-zero |
| T7 | malformed: `sole ur.ai` (whitespace) | exit non-zero |
| T8 | malformed: `soleurai` (no dot) | exit non-zero |
| T9 | malformed: `app.soleur.ai` (would yield `https://app.app.soleur.ai/health`) | exit non-zero |
| T10 | a sibling `app_domain_base_legacy` declared **before** the real one | stdout `soleur.ai` — the anchored match must not select the sibling |
| T11 | valid | stdout carries **only** the base — no annotations, no resolution line |
| T12 | valid, path passed as `$1` | the fixture path is honoured (pins the one parameter) |

### `tests/scripts/test-registry-d10-workflow-wiring.sh`

| # | Assertion |
|---|---|
| W1 | Vacuity floor: both D10 step bodies extract non-empty |
| W2 | Each body (comments stripped) calls `scripts/derive-app-domain-base.sh` exactly once |
| W3 | Each body exports `APP_DOMAIN_BASE` and retains a fail-closed abort on empty |
| W4 | Residual-zero over the comment-stripped **workflow AND `.github/actions/**/action.yml`** — scoping it to the workflow alone leaves a hole the exact shape of the bug, because the recut's own restore leg runs inside a composite action. Excludes `cf-tunnel-ssh-bridge` (deferred to D4) via an explicit, commented allowlist entry so the exclusion is visible rather than accidental |
| W5 | Each body uses the bare-assignment form (no `export APP_DOMAIN_BASE=$(`) and opens with `set -euo pipefail` — together these are what make the script's non-zero exit reach the runner |
| W6 | `DOPPLER_TOKEN_PRD` appears nowhere in the job |
| W7 | The referenced script exists and is executable — a wiring test pointing at a missing file must fail, not vacuously pass |

---

## Alternatives Considered

**A1 — Copy the sibling pattern: `|| echo "soleur.ai"`.** Rejected. A hardcode wearing a
Doppler call as a costume; reproduces the dark read that hid this bug.

**A2 — Read Doppler `APP_DOMAIN` as primary (the task framing's proposal), or as a
cross-check (v1's proposal).** Rejected — see `decision-challenges.md` UC1 and the
Overview. `APP_DOMAIN` is a derived copy of the same Terraform variable, so it verifies
nothing; and any live-credential dependency on this path is what the fix exists to
remove.

**A3 — Create the `APP_DOMAIN_BASE` secret in Doppler via a `doppler_secret` resource.**
Rejected. Adds a 14th independent copy of a committed value; `check-cloudflare-token-drift.sh`'s
header documents what that fan-out costs. Also drags the PR through the IaC gate and the
`infra/*.tf` auto-apply path.

**A4 — Change the consuming script to accept a full host or URL.** Rejected. Would touch
a 60-test suite and a byte-fragile mutation anchor to avoid a one-line derivation.

**A5 — Inline the awk into both `run:` bodies; ship no script.** Rejected, but it is the
closest competitor. A `run:` body is untestable, and that untestability is exactly why
the workflow-side half of this gate had zero coverage (R5). A ~25-line script with a
positional fixture parameter is the minimum that makes the derivation assertable.

**A6 — Compute once in PREPARE, pass via `$GITHUB_ENV`.** Rejected. Couples VERDICT to
PREPARE's state, whereas the workflow deliberately re-derives; and it still leaves the
derivation untestable.

**A7 — Add an AGENTS.md rule requiring workflow Doppler reads to name a verified
secret.** Deferred (D1). Headroom measured at `B_ALWAYS=43776` against the 46000-byte cap
(~2224 bytes free), so a rule would fit — but a mechanical gate beats a prose rule, and
this PR ships one (W4).

**A8 — Mint a new ADR for the destroy-authorizing rule.** Rejected in favour of widening
ADR-164 — see Architecture Decision.

---

## Risks & Mitigations

**Risk 1 — A wrong-host derivation authorizes a destroy against an inadequate restore
set.** *Mitigation:* the source is the committed variable Terraform actually applied and
that defines the registry hostname itself; the shape guard rejects malformed values; A0's
curl independently measures that the chosen host answers with parseable `version` +
`build_sha`. The authorization condition is unchanged.

**Risk 2 — The fail-closed chain breaks silently at a call site.** Measured: `export
X=$(cmd)` exits 0 on failure. *Mitigation:* AC3 and W5 pin the bare-assignment form and
`set -euo pipefail` together; either alone is insufficient.

**Risk 3 — "PR merged" reads as "incident closed".** It does not. This PR makes the
dispatch *fireable*. Two further preconditions stand: the runbook's cold-vehicle
checklist, and the missing `REGISTRY_LUKS_KEY` secret — whose only tracker today is
`#7316`, an auto-filed drift issue whose title gives no hint that it blocks the recut.
*Mitigation:* D5 makes the linkage explicit; Phase 7.3 records both blockers in the
runbook; AC13 states it; the PR body must not imply remediation.

**Risk 4 — Touching the workflow disturbs the mutation battery.** A `harness_die` exit 2
yields *no verdict*. *Mitigation:* AC5 asserts byte-cleanliness and requires exit 0.

**Risk 5 — `variables.tf`'s `default =` is mutable, and a future `TF_VAR` override would
make it stale.** This is the same shape as the bug being fixed, and it is **not
auto-detected**. *Mitigation:* the resolution line names the file so the assumption is in
the run log; Phase 7.2 adds the `TF_VAR` absence check to the cold-vehicle checklist; D3
tracks the `validation` block.

**Risk 6 — An absence-grep AC false-fails on legitimate prose.** *Mitigation:* AC1 and W4
operate on the comment-stripped body; the replacement comment is deliberately short.

---

## Deferrals & Tracking Issues

**D1 — A live Doppler-name existence sweep, plus the `ADR-007` convention.** No
live-Doppler assertion exists anywhere in the repo, and the CI `scripts` shard has no
Doppler credential. Home: `scheduled-terraform-drift.yml`, which already holds tokens and
files issues. The `ADR-007` convention rides along — a convention without a gate is the
weaker half, so they ship together rather than as two issues.

**D3 — *(folded into this PR)*.** v2 deferred a shape-keyed `validation` block on
`app_domain_base` to avoid firing the `infra/*.tf` auto-apply. **That rationale is
falsified:** the workflow lists its own path in `on.push.paths`, so this PR fires the
apply regardless (see AC8) and the deferral buys nothing. Since this change makes the
variable destroy-authorizing, fold the `validation` block in — keyed on **shape, not the
pinned value** — and name the D10 gate in the variable's `description`.

**D4 — The remaining `2>/dev/null || echo "soleur.ai"` instances.** Re-enumerated from a
real grep rather than the plan's recollection: 2 in this workflow's web-host
birth/replace sites, 4 in `.github/workflows/apply-deploy-pipeline-fix.yml`, 1 in
`apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh`, and 1 in
`.github/actions/cf-tunnel-ssh-bridge/action.yml`. Separately,
`plugins/soleur/skills/ship/SKILL.md` carries the read with **no fallback at all**,
which yields a malformed `https://deploy./…` URL — Risk 9's failure mode, already
shipped. `cf-tunnel-registry-bridge` is **not** in this list: it is in the recut's own
chain and is fixed here (Phase 4). One sweep, one PR, when the platform is not down.

**D5 — Track `REGISTRY_LUKS_KEY` as the recut's second precondition.** Link `#7316` (whose
plan body contains `doppler_secret.registry_luks_key will be created`) from `#6929` and
from the runbook, or file a dedicated issue. Today the one thing actually blocking
remediation is invisible behind a generic drift title.

**D6 — Tracker corrections.** `#6929` is labelled `priority/p3-low` + `type/chore` —
stale from when it was a footgun-removal follow-up; it is now the blocking dependency for
a three-day total deploy outage. Relabel to `priority/p1-high` + `type/bug`. `#7287` and
`#7340` sit in **Post-MVP / Later** while their blocker `#6929` is in Phase 4; both are
remediation steps for the live incident and should move to Phase 4.

**D7 — The brand-survival ladder is inverted.** Declaring the *higher* severity
(`aggregate pattern`) silently **drops** both sign-off gates: `plan/SKILL.md` adds no
per-PR sign-off for it, and `ship/SKILL.md`'s auto-label greps `single-user incident`
only. Every future plan that honestly self-reports systemic risk gets a weaker gate. This
is a repo-wide trap, not specific to this plan.

*(D2 from v1 — the standalone `ADR-007` convention — is folded into D1.)*

---

## Review Consolidation

Six reviewers: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer,
CPO. Findings applied as follows.

**v3 additions — two criticals found by architecture/Kieran against v2:** the workflow
**self-triggers a production apply** on its own path (AC8 rewritten around the
`[skip-web-platform-apply]` kill switch; D3's deferral rationale falsified and folded
in), and the recut's **own restore leg** runs the antipattern inside
`cf-tunnel-registry-bridge` where a workflow-scoped residual-zero cannot see it (Phase 4
reinstated with a different target; W4 widened to `.github/actions/**`). Also: the ADR
parent moved from ADR-164 (category error — list-scoping mechanism, no denominator here)
to **ADR-169**'s independence criterion; `TF_VAR` precedence moved from a one-time
Phase 0 check into the script; CWD-independent path resolution; the `read_default`
exit-status caveat; three-dot diffs; `grep -c` exit-1-on-zero; reference count 8 → 7.

**Cut (multi-reviewer consensus):** the Doppler cross-check tier and everything
downstream of it — `--strict-agreement`, the PREPARE/VERDICT asymmetry,
`--doppler-project`/`--doppler-config`, `--explain`, R8, Risk 8, two failure modes, nine
unit rows, and alternatives A2/A5/A6 (DHH + code-simplicity, both panels on one scope →
delete over fix). Phase 4 sibling conversion (DHH + code-simplicity + CPO). The
standalone ADR-166 amendment (DHH + code-simplicity + CPO). The new ADR-171 (DHH;
contested by CPO — resolution recorded in Architecture Decision). D2 folded into D1.

**Added (findings v1 missed):** the call-site assignment-form hazard, now measured
(code-simplicity); deleting `DOPPLER_TOKEN_PRD` entirely (DHH); the anchored awk match
(code-simplicity); the un-rechecked `TF_VAR` runtime assumption (code-simplicity);
`REGISTRY_LUKS_KEY` tracking (CPO); the Reversible Mitigation section (CPO); naming the
user and the hosted platform (CPO); the threshold-ladder inversion (CPO); tracker
corrections (CPO); expanding the malformed-shape cases from one row to five
(code-simplicity).

**Net:** ~55–60% less new code, four fewer artifacts, one fewer credential on the
recovery path.

---

## Sharp Edges

- **`export X=$(cmd)` discards the command's exit status** — measured: it exits 0 and
  continues where `X=$(cmd); export X` exits 1. In a fail-closed derivation this silently
  converts a failed read into an empty-but-"successful" value. This is the single
  highest-risk line in the change.

- **`APP_DOMAIN_BASE` must keep appearing in this workflow's prose.** Any AC or test
  greping for its absence must strip comments first. Keep the replacement comment short —
  long prose is what forced v1's stripping harness.

- **`bash tests/scripts/test-registry-gate-mutation-battery.sh` exiting 2 is not a test
  failure — it is "no verdict".** It means an anchor in
  `scripts/registry-pull-path-health.sh` drifted. Treat exit 2 as a harder stop than
  exit 1.

- **Nothing auto-discovers `tests/scripts/test-*.sh`.** An unregistered suite runs in zero
  runners and is silent and green (#3366). The `scripts/*.test.sh` glob *is* covered by
  `lint-orphan-test-suites.sh`, which is why the unit suite lives there.

- **Do not append workflow-reading assertions to
  `tests/scripts/test-registry-pull-path-health.sh`.** The mutation battery sandboxes that
  file into a tree with no `.github/` directory; such rows would go red in the baseline and
  abort the battery.

- **The derivation trusts that no `TF_VAR_app_domain_base` override exists.** That is
  checked at plan time and re-asserted in the cold-vehicle checklist, but nothing checks
  it at run time. The day someone sets it, a destroy-authorizing gate derives a stale host
  — the same shape as this bug.

- **The recut was designed to move the volume to LUKS, not to free disk.** Using it as a
  capacity remedy is a reuse worth stating; see `## Reversible Mitigation`.

- **Merging this PR does not fix the registry.** It makes the recovery vehicle fireable.
  Two preconditions remain: the cold-vehicle checklist and the missing
  `REGISTRY_LUKS_KEY`.
