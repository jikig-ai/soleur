# Tasks — #6425 web-2 tunnel de-pool + host identity

Derived from [`knowledge-base/project/plans/2026-07-15-fix-web2-tunnel-depool-host-id-plan.md`](../../plans/2026-07-15-fix-web2-tunnel-depool-host-id-plan.md) (post plan-review).
Lane: `cross-domain`. Threshold: `single-user incident` → CPO sign-off obtained (APPROVE-WITH-CONDITIONS, C1–C6 folded in).

Runners: `apps/web-platform/infra/*.test.sh` = plain `bash`. TS = `plugins/soleur/test/`. **No new framework.**

---

## Phase 0 — Preconditions (verify, do not assume)

- [x] 0.1 Re-verify **every** `.sh` line citation in the plan before relying on it (v1/v2 shipped 4 stale ones). Cite function names, not line ranges, in any new comment.
- [x] 0.2 Confirm `terraform` is available to `deploy-script-tests` (`setup-terraform`) — AC5's render authority needs it.
- [x] 0.3 Confirm `${tunnel_token}` still has exactly **one** reference site (`cloud-init.yml:590`). If a second appeared, it must live **inside** the gate.

## Phase 1 — Read-only probes (no diff)

- [x] 1.1 Sentry probe: `op:image-pull` grouped by `host_id`, events after 2026-07-14. Comment the verdict on **#6400** and **#6357**. Do **not** widen this PR. Not an AC.
- [x] 1.2 Carry the recorded baseline census into the PR body (tunnel `6410c1ec-4f01-4a69-ad98-7bb1621f6d37`; clients `8c57fcd5`/fra* = web-2, `a281fb1b`/ams*+hel* = web-1). Do not re-derive.
- [x] 1.3 Confirm the **two delivery paths**: `cat-deploy-state.sh` baked (`server.tf:19`) **and** DPF-pushed (`:878`); `inngest-inventory.sh` DPF-pushed **only** (`:910`). No new files → bake-set/Dockerfile/`.dockerignore` untouched; the hardcoded `28` stays valid.

## Phase 2 — Deliverable 1: gate the connector

- [x] 2.1 **RED first** — add AC5's two-armed render assertion to `cloud-init-inngest-bootstrap.test.sh`; confirm it fails on `main`.
- [x] 2.2 `server.tf` — add **one** templatefile var: `web_tunnel_connector = each.key == "web-1"`. **Leave `:158` alone** (the `tunnel_token` map entry must stay — `MakeTemplateFileFunc` pre-checks both `ConditionalExpr` branches). **No ternary.**
- [x] 2.3 `cloud-init.yml:588-593` — wrap `:590` + `:593` in `%{ if web_tunnel_connector ~}` / `%{ endif ~}` at **column 0** (mirror `:664`/`:728`). Leave `apt-get install -y cloudflared` (`:586`) ungated.
- [x] 2.4 Fix `cloud-init-inngest-bootstrap.test.sh`'s `render_ci()` var map (`:294`) — it breaks on any new map var by design. Consider dropping `2>/dev/null` (`:296`), which swallows the real error.

## Phase 3 — Deliverable 2: host identity

- [x] 3.1 Copy `resolve_host_id()` from **`ci-deploy.sh:137-156`** — the range **must include `:156`**'s `|| true` (both targets run `set -euo pipefail`; a bare assignment aborts the hook → non-200).
- [x] 3.2 Placement: inside `inngest-inventory.sh`'s `BASH_SOURCE` execution guard (`:509`) — a top-level `HOST_ID=` fires `curl` on every source, violating "sourcing must NOT hit the network".
- [x] 3.3 `SOLEUR-DEBT` marker on each copy. Reason = **distribution cost (~11 surfaces + the bake path)**, NOT "no sourcing precedent" (sourcing works — `ci-deploy.sh:703`). Trigger: *a 4th copy **or** any consumer outside `infra/`*. `Tracked: #<6.4>`.
- [x] 3.4 Token drift guard (~8 lines) mirroring `test_durability_drift_guard` (`inngest-inventory.test.sh:345`). Tokens: `SOLEUR_HOST_ID_OVERRIDE`, `SOLEUR_HOST_ID_METADATA_URL`, `hetzner-%s`, `machine-%s`. **Parameterise it** (`extract_fn_body <file> <fn>`) so AC4's negative arm can hand it a `$TMP` fixture.
- [x] 3.5 `cat-deploy-state.sh` — `--arg hid "$HOST_ID"`; `host_id: $hid` in the **outer** literal (last in the merge chain, `:344`). Do not touch `exit_code` (#2205).
- [x] 3.6 `inngest-inventory.sh` — `host_id` on **all four** exit paths **plus** the marker:
  - [x] liveness success `:454` (JSON) · full success `:504` (JSON)
  - [x] **DEGRADED `:433-435`** and **FATAL `:438-440`** (+ `:191`, `:280`, `:294`) — plain-text `exit 1` bodies
  - [x] `SOLEUR_INNGEST_LIVENESS_VERDICT` marker `:431`
  - **These failure paths are the alert surface** (`hooks.json.tmpl:160`) — the operator's real incident was `FATAL __FETCH_FAILED__`.
- [x] 3.7 Tests: `cat-deploy-state.test.sh` (+ hostile-state-file clobber fixture), `inngest-inventory.test.sh` (success × failure axis). `SOLEUR_HOST_ID_OVERRIDE` is **mandatory** in both harnesses (runners have `/etc/machine-id`).

## Phase 4 — Deliverable 3: self-trigger guard

- [x] 4.1 `restart-inngest-server.yml:30` — add `if: github.event_name == 'workflow_dispatch'`, citing the existing idiom (`cutover-inngest.yml:48`). Keep the `push` trigger. Add a test.
- [x] 4.2 Triage `apply-inngest-rls.yml` **with evidence** (the one real unguarded candidate). Fix inline only if it writes prod on self-trigger.
- [x] 4.3 File an issue for the full class sweep. Do **not** re-run it inline. (v1's enumeration was wrong 3 ways.)

## Phase 5 — Observability wiring

- [x] 5.1 Add `CF_API_TOKEN` + `CF_ACCOUNT_ID` to `scheduled-inngest-health.yml`; run the connector census each tick; file an **`action-required`**-labelled issue when `connectors != 1`. Pin the jq: `[.result[] | select((.conns|length) > 0)] | length`.
- [x] 5.2 Emit `SOLEUR_ORIGIN_HOST_CHURN` as a **log breadcrumb** (`diagnostic:`), never as the alert route.

## Phase 6 — ADR / C4 / deferrals

- [x] 6.1 Amend ADR-068 (5 items). **Gate on *designated ingress host*, NOT §(c)** — §(c) is `:566-575` (LB weight only; **not** the A record) and clearing it at GA would re-pool web-2 and regress #6425.
- [x] 6.2 Amend ADR-082 Item 5 (read-surface `host_id`).
- [x] 6.3 `model.c4` — invariant onto the **`tunnel` element description** (`:176-178`), **not** the `tunnel -> coordinator` edge (`:362`, which models the deferred 3.D rewire). Add the missing `tunnel -> hetzner` edge; check whether `views.c4` needs an `include`. Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [x] 6.4 Document web-2 provisioning in-place + **comment on existing #6415/#6416**. **Do not file a new umbrella issue.**
- [x] 6.5 File: host-addressability prerequisite (GA blocker for re-pooling; incl. the re-delivery requirement).
- [x] 6.6 File: unify the 3 host-identity schemes (cited by 3.3's `Tracked:`).
- [x] 6.7 File the 3 tooling defects from `decision-challenges.md` (plan-review sentinel, constitution path, roadmap staleness).

## Phase 7 — Post-merge (automated; `gh` CLI only)

- [ ] 7.0 Engage the merge-freeze (`guardrails.sh`).
- [ ] 7.1 Merge with **`[skip-deploy-fix-apply]` in the merge commit — mandatory**, or step 7.4 is a no-op.
- [ ] 7.2 Wait for the web-1 release digest; confirm `curl -s https://app.soleur.ai/health | jq -r .version` == new semver. **Gates the coherence preflight.**
- [ ] 7.3 `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate -f reason='#6425 …'` → verify **AC1** + **AC6**.
- [ ] 7.4 `gh workflow run apply-deploy-pipeline-fix.yml -f reason='#6425 post-de-pool push'` → verify **AC13/AC14**.
- [ ] 7.5 `gh issue close 6425` **only after AC1 passes**. Release the freeze.
- [ ] 7.6 PR body: `Ref #6425` (**not** `Closes`); include the Phase 1.1 verdict, the baseline census, and the #6413 note.

---

## Exit gate

- [ ] Full suite green (`bash apps/web-platform/infra/<file>.test.sh`; TS per `plugins/soleur/test/`).
- [ ] AC5 both arms + `yaml.safe_load` clean.
- [ ] AC4 negative arm actually goes red.
- [ ] `decision-challenges.md` **UC-1** (two-PR split) surfaced in the PR body by `ship` Phase 6.
