# Decision Challenges — feat-one-shot-d10-health-url-derivation

Recorded at plan time under ADR-084 / `decision-principles.md`. This session ran
headless (one-shot pipeline), so challenges are persisted here rather than raised at
an interactive gate. `/ship` renders these into the PR body and files them as an
`action-required` issue.

---

## UC1 — Source precedence for the D10 health-URL derivation (User-Challenge)

**Class:** user-challenge
**Status:** applied in the plan, flagged for operator review

**Operator's stated direction.** From the task framing:

> Prefer deriving from what actually exists rather than hardcoding: read
> `APP_DOMAIN`, and if it already starts with `app.` use it as the host directly;
> otherwise fall back to the `soleur.ai` base the siblings use.

That direction makes the **live Doppler read primary** and the base domain a
fallback.

**What the plan does instead.** It inverts the precedence: the committed
`apps/web-platform/infra/variables.tf` default (`app_domain_base`) becomes the source,
and — after a second review round — the Doppler `APP_DOMAIN` read is **removed
entirely**, not merely demoted. Two further reviewers showed a cross-check against
`APP_DOMAIN` verifies nothing, because it is a *derived copy of the same Terraform
variable* rather than an independent witness. Removing it also lets the PR delete
`DOPPLER_TOKEN_PRD` from both D10 steps, taking a production credential off the recovery
path.

**Why the change was made.** Two independent reviewers — a scoped strong-model
advisor consult and the CTO domain leader — reached the same conclusion without
seeing each other's output, on four grounds that were then live-verified:

1. **`variables.tf` is the causal source, not a parallel copy.**
   `var.app_domain_base` has seven `var.` references across `server.tf` and `tunnel.tf`.
   `tunnel.tf` builds `registry.${var.app_domain_base}` — **the exact registry
   ingress this recut vehicle operates on** — and `server.tf` wires the same
   variable into the prod host's `APP_DOMAIN_BASE`. `TF_VAR_app_domain_base` is
   absent from Doppler `prd_terraform`, so the default is what Terraform actually
   applied. Doppler's `APP_DOMAIN` is a *derived sibling effect* of that same
   variable, and recovering the base from it needs string surgery.

2. **ADR-169's independence criterion applies** — *"a gate on an irreversible destroy
   may not depend on the component whose failure motivates it"*, extended from
   components to authorizing inputs. (An earlier draft cited ADR-164; architecture
   review showed that is a category error — its mechanism is list-scoping and
   denominator co-narrowing, and a single-key GET has neither.) Live-primary lets a misconfigured or compromised `DOPPLER_TOKEN_PRD` redirect
   that measurement, A0 then goes green against the wrong host, and an irreversible
   destroy proceeds.

3. **The bug being fixed is "a recovery gate depends on a live credentialed read."**
   Keeping Doppler primary preserves the shape of the original defect with a softer
   landing, on the critical path of the vehicle that must work during an incident.

4. **Inverting dissolves the plan's central tension.** With committed-primary there
   is no fallback that can go dark, because nothing is being substituted. The
   silent-fallback risk that the operator's ordering would have required a
   `::warning::` to police simply does not arise.

**What is preserved from the operator's direction.** The operator's stated *principle*
— derive from what actually exists, never hardcode a domain, preserve fail-closed — is
fully honoured, and more literally than the proposed mechanism would have: the source is
committed config that exists and is read, no literal domain appears anywhere, and the
fail-closed abort is strengthened rather than softened. What is *not* preserved is the
proposed mechanism itself (`APP_DOMAIN` + `app.` strip), which no longer ships at all.

**If the operator disagrees**, re-adding an `APP_DOMAIN` tier is a contained change to
`scripts/derive-app-domain-base.sh` plus its test matrix — but it would also require
restoring `DOPPLER_TOKEN_PRD` to both D10 steps, which is the part worth weighing.

---

## UC2 — Scope: which dark call sites get converted (taste)

**Class:** taste
**Status:** REVISED after review — web-host siblings cut, restore leg scoped in

The task framing said "Scope is the health-URL derivation only." The plan scopes in
two *additional* health-URL derivations — the web-host birth and web-host replace
sites — which today read the same nonexistent secret behind
`2>/dev/null || echo "soleur.ai"` and have therefore taken the hardcoded fallback on
every execution since they shipped.

Both reviewers recommended converting them in the same PR: they are the reason the
missing secret went unnoticed, and leaving a known-dark read two screens from its own
fix canonises the pattern for the next reader.

The derived value is provably identical either way, so behaviour is unchanged and
only provenance becomes real. The phase is explicitly separable if review disagrees.

**Bounded deliberately:** five further instances of the same antipattern exist
outside this workflow (four in `apply-deploy-pipeline-fix.yml`, one in
`verify-tunnel-ingress-origin.sh`). They are **not** pulled in; they are filed as
deferral D4.


**REVISION (post-review).** Three reviewers (DHH, code-simplicity, CPO) rejected
converting the web-host **birth/replace** sites in this PR. CPO's ground is the
strongest and is a blast-radius objection rather than a scope one: a host *replace* is a
live possibility during this very incident, and the conversion is behaviour-neutral on
the happy path while adding a new abort arm to a fleet-critical vehicle. **Cut.**

But architecture review and Kieran independently found an instance the original scope
boundary drew wrongly: `.github/actions/cf-tunnel-registry-bridge/action.yml` runs the
same dark read to derive `registry.${APP_DOMAIN_BASE}`, and it is invoked by
`registry_store_restore` — **inside this dispatch's own chain**, on the leg that refills
the emptied registry. Leaving it would have the same dispatch derive the base two
different ways, and a workflow-scoped residual-zero assertion would go green while it
ran. **Scoped in as the new Phase 4.**

Net effect on the operator's stated "health-URL derivation only" scope: honoured more
closely than v1 (two unrelated vehicles dropped), with one addition that is inside the
vehicle being fixed rather than adjacent to it.

---

## UC3 — The merge requires a kill-switch token in the commit message (user-challenge)

**Class:** user-challenge
**Status:** applied in the plan, needs operator awareness

`.github/workflows/apply-web-platform-infra.yml` lists **its own path** in
`on.push.paths`. This PR edits that file, so merging it fires `push` → the `apply:` job →
a **production `terraform apply`**, against a registry that is currently crash-looping at
100% disk.

The plan's v2 acceptance criterion asserted the opposite, reasoning from a `.tf`-scoped
diff — a true assertion supporting a false conclusion, since the trigger is not
`.tf`-scoped. Architecture review caught it.

**The plan now requires** the merge commit message to contain `[skip-web-platform-apply]`
on its own line — the workflow's documented kill switch. This is a **merge-procedure
constraint the operator must not lose**: a squash-merge whose message drops that line
silently converts a documentation-and-shell PR into an unplanned production apply during
an active incident.

Flagged as a user-challenge rather than mechanical because it changes how the PR is
merged, not just what it contains.

## Work-phase challenge — AC1 and W4 contradict Phase 4's own scope cut

**Classification:** Taste (user-legible) — resolved at write time, recorded rather than silently applied.

**The contradiction.** AC1 requires `grep -c 'doppler secrets get APP_DOMAIN_BASE'` over the comment-stripped **workflow** to return `0`, and cites `4` as the discriminating pre-fix count. W4 likewise specifies a residual-zero over the workflow and `.github/actions/**`, naming only `cf-tunnel-ssh-bridge` as an exclusion.

But Phase 4 deliberately **cuts** the web-host birth/replace conversion ("three reviewers; a host replace is a live possibility during this incident"). Those two sites live in `apply-web-platform-infra.yml`, in the step `Resolve known-good image digest off-host (freeze $PINNED)`. So AC1's `0` and W4's residual-zero are unreachable *without doing the very work Phase 4 removed for safety*.

Pre-fix `4` decomposes as: 2 D10 arms (converted) + 2 web-host sites (deliberately kept).

**Resolution.** Phase 4 is authoritative on intent; AC1's literal `0` is the erroneous clause. Measured post-fix:

| Scope | Count |
|---|---|
| whole workflow, comment-stripped | **2** (was 4) |
| `registry_pull_path_gate` job | **0** |
| `export APP_DOMAIN_BASE=$(` anywhere | **0** |

W4 is implemented against the **recut chain** with both exclusions enumerated in a commented allowlist, and the allowlist is itself asserted live — if a D4 conversion lands and an entry stops matching a real deferred read, the gate goes RED and the exemption must be deleted. That makes the exclusion visible and self-retiring rather than a permanent silent hole, which is what W4's stated purpose actually asks for.

Had AC1 been implemented literally, the only ways to satisfy it were to convert the web-host sites (reintroducing the risk three reviewers removed) or to weaken the grep until it passed. Both are worse than recording the contradiction.

**Follow-up:** the remaining sites are tracked in the consolidated follow-up issue, with the wiring gate's allowlist as the mechanism that forces their retirement.

## Work-phase challenge — AC10 named the wrong ADR, same class as AC1

**Classification:** Mechanical — corrected, recorded because AC1's twin was recorded.

The v3 consolidation ruled ADR-164 out as a **category error**: its mechanism is silent
list-scoping making a denominator too small, which is not what happened here. The shipped work
complied — it amended ADR-169 and ADR-096, and cited ADR-164 nowhere.

But four earlier passages were never updated, and one of them was an acceptance criterion:

| Line | Read |
|---|---|
| 276 | "Amending **ADR-164** + ADR-096 discharges it" |
| 660 | Phase 8: "widen **ADR-164**'s applicability" |
| **758** | **AC10: "ADR-164's applicability is widened"** |
| 841 | A8: "Rejected in favour of widening **ADR-164**" |

So **AC10 shipped unmet as written** — satisfying it literally would have required amending the
ADR the same plan calls a category error. This is exactly AC1's shape (an acceptance criterion
contradicting a decision made later in the same document), and it went unrecorded because the
contradiction was invisible from the ACs alone: nothing in AC10 flags that ADR-164 had been
ruled out 500 lines above it.

All four corrected to ADR-169. Recorded rather than silently fixed, because "the plan
contradicted itself in a way the ACs could not surface" is the reusable finding, not the
four-line edit.

**Residual, deliberately not fixed here:** `restore-pins.json` carries no provenance — no
health URL, no base, no `version`/`build_sha`. `manifest_sha256` proves the set did not change
between rehearsal and restore; it proves nothing about which host produced it, and the artifact
is consumed post-destroy. Adding the three fields is additive but touches the restore engine's
shape assertion, which is outside this change's scope. Tracked in the consolidated follow-up.
