# Decision Challenges — feat-one-shot-6425-web2-tunnel-depool-host-id

Recorded per ADR-084 / `decision-principles.md`. Headless plan session → persisted, **not** auto-applied. `ship` Phase 6 renders this into the PR body and files an `action-required` issue.

---

## UC-1 — Split into two PRs (User-Challenge)

**Class:** `user-challenge` — argues the operator's stated direction should change.
**Operator's stated direction (the default, retained in the plan):** *"implement exactly these two deliverables"* in this PR.
**Raised by:** `dhh-rails-reviewer` (proportionality), `spec-flow-analyzer` (P0-1 + P0-2, independently), reinforced by `architecture-strategist` (P1-1). **3 of 7 reviewers converged on it independently.**
**Counter-signal:** the Step-4.5 advisor consult holds that merge-first is forced anyway and the step-1 race is self-healing — it did **not** call for a split. Per decision-principles.md this is therefore a **single-signal** challenge on the split itself, but the two P0s it dissolves are multiply-confirmed.

### The argument

The two deliverables have **different delivery mechanisms, different lifecycles, and a hard ordering constraint between them** — and the constraint is created by shipping them together:

- **Deliverable 1** (`server.tf` + `cloud-init.yml`) is **provably hash-neutral** — neither file is in `local.host_script_files` (`server.tf:16-65`). Merging it changes nothing on a running host and does not move `local.host_scripts_content_hash`.
- **Deliverable 2** edits `cat-deploy-state.sh`, which **is** member #3 of `host_script_files` (`server.tf:19`) → it **does** move `host_scripts_content_hash` (`server.tf:83-85`).

That single coupling causes both P0s in the single-PR path:

| # | Failure | Mechanism |
|---|---|---|
| **P0-a** | **The de-pool never happens.** | `web-2-recreate`'s coherence preflight (`apply-web-platform-infra.yml:1118-1132` → `scripts/web2-recreate-preflight.sh:97-99`) compares `local.host_scripts_content_hash` (merged checkout) against the hash baked into `PINNED` (web-1's *currently running* image). Deliverable 2 moves the former; the latter still has the old script → **mismatch → `exit 1`, no `-replace`, no de-pool, AC1 unverifiable, #6425 stays open.** |
| **P0-b** | **The "deterministic re-push" is a no-op.** | `apply-deploy-pipeline-fix.yml:288-293` runs `terraform apply -target=terraform_data.deploy_pipeline_fix` with **no `-replace` and no taint**. The provisioner re-runs only when `triggers_replace` changes. The merge-triggered racing run **consumes** the hash change (pushing to a coin-flipped host); a later dispatch then sees identical file contents → **no diff → no-op** → nothing lands on web-1 → AC13/AC14 fail. |

### What each path costs

**Split (recommended by the challenge):**
1. **PR A** — deliverable 1 only. Hash-neutral → the recreate preflight passes immediately against web-1's current image → de-pool → verify AC1. **The P1 is fixed as fast as possible.**
2. **PR B** — deliverable 2. The racing push now lands on web-1 **deterministically, because web-2 is already de-pooled.** No step 3, no kill switch, no no-op.

Splitting makes the plan's own "de-pool first" principle actually *executable*.

**Single PR (the operator's direction — retained as the plan's default):** requires **both** compensations, and both are now mandatory rather than optional:
- Insert a wait: merge → **wait for the release build + web-1 deploy** → confirm `curl https://app.soleur.ai/health | jq -r .version` equals the new semver → *then* dispatch `web-2-recreate`.
- **`[skip-deploy-fix-apply]` in the merge commit is LOAD-BEARING, not optional** — it is the only thing that leaves the `triggers_replace` hash unconsumed so the post-de-pool dispatch actually replaces the `terraform_data` and pushes. (v1/v2 called it "optional"; that was wrong.)

Both compensations are encoded in the plan's Phase 7 so the operator's direction ships correctly as-is. The split is strictly simpler and dissolves both P0s rather than compensating for them.

### Recommendation

**Split.** But the operator's direction is the default and the plan implements it correctly. This needs an operator decision, not an agent's.

### RESOLVED — 2026-07-15: the operator chose the SPLIT

The challenge was surfaced at review time and the operator ruled: **split into two PRs.** The
reviewers were right, and the split did what they said it would — it **dissolved** both P0s
rather than compensating for them:

| | Single PR (the compensated shape) | Split (shipped) |
|---|---|---|
| **P0-a** coherence preflight aborts the de-pool | Wait ~40 min for the release digest to land on web-1 first | **Gone.** PR A touches no `host_script_files` member, so the hash never moves and the preflight passes against the CURRENT image. De-pool runs the moment the merge lands. |
| **P0-b** DPF re-push is a silent no-op | `[skip-deploy-fix-apply]` in the merge commit — mandatory, and easy to forget | **Gone.** PR A changes no deploy-pipeline-fix trigger, so there is no hash for a racing apply to consume. PR B's push lands on web-1 deterministically *because web-2 is already de-pooled*. |

Concretely:

- **PR A** (#6426) — the connector gate + the standing census + the restart-workflow guard +
  ADR-068/ADR-114/C4. **Hash-neutral** (verified: no member of `local.host_script_files` is
  touched). Its post-merge script lost the digest wait, the kill switch, and the DPF stage —
  ~200 lines → ~150, and every remaining line does something.
- **PR B** — host identity on the read surfaces (`cat-deploy-state.sh` is a baked member, so
  **this** is the PR that moves the hash) + ADR-082. **Needs no post-merge script at all.**

The P1 also ships faster: PR A can de-pool immediately instead of waiting on a release.

**The lesson worth keeping:** the plan's own principle was *"de-pool first"*, and the single-PR
shape made that principle unexecutable — the de-pool had to wait on a release that only
existed because of the other deliverable. Three reviewers converged on the split independently;
the counter-signal (the advisor consult) argued only that merge-first was forced anyway, which
was true and beside the point. When a plan needs two mandatory compensations to keep its own
stated ordering legal, that is the shape telling you it is two changes.

---

## UC-2 — `web_tunnel_connector_host` variable vs. hardcoded `each.key == "web-1"` (Taste)

**Class:** `taste` — a design choice with two defensible answers; **resolved in-plan, recorded for visibility.**

- **Advisor (Step 4.5) proposed** making the predicate a variable, so promoting web-2 later doesn't need a code change + PR *during an outage of the only connector*.
- **CTO rejected it**, and the plan follows the CTO: a lone `web_tunnel_connector_host` knob **looks like a promotion switch and isn't**. `each.key == "web-1"` is the in-file idiom (`server.tf:108`, `:188`); `dns.tf` pins `web["web-1"]` in four places, plus the LB weight. Promotion requires moving all of them in lockstep. A lone connector flip mid-outage yields a connector on web-2 while the A record still points at web-1 — an ingress split, at 3am. A partial abstraction implies a capability that does not exist.

**Resolved: hardcoded.** Encoding the coupling in the ADR beats exposing a knob that lets you violate it. No operator action needed unless they disagree.

---

## Non-blocking defects found in the tooling itself (file separately)

1. **`plan-review/workflows/plan-review.workflow.js:40`** matches `THRESHOLD_SENTINEL = 'Brand-survival threshold: single-user incident'` as an **exact string**. Declaring the *higher* tier `aggregate pattern` would silently drop the panel from 5 agents back to 3 — **a higher tier buys less review.** Live gate defect. (Found by `cpo`.)
2. **`MEMORY.md` and several skill prompts cite `knowledge-base/overview/constitution.md`** — the file is at `knowledge-base/project/constitution.md`; `overview/` holds only `vision.md`. (Found by `cpo`.)
3. **Roadmap staleness:** Current State says Phase 4 = 43 open / 160 closed; the milestone API says **48 / 165**. Dated `2026-05-25` under `last_updated: 2026-07-06`. (Found by `cpo`.)
