# Tasks — per-config Doppler read tokens for the token-drift scan

Derived from `knowledge-base/project/plans/2026-08-03-fix-per-config-doppler-read-tokens-token-drift-plan.md` (v2, post-review).
Closes #7234. `Ref #7159`, `Ref #7175` — **never `Closes`/`Resolves`** for those two.

Phase order is dependency-directed, not file-grouped. Do not reorder.

---

## Phase 0 — Preconditions (probes only, no edits)

- [ ] **0.1** Confirm `access = "read"` and the `.key` attribute against a sibling
      `doppler_service_token` (`apps/web-platform/infra/kb-drift.tf`). Read one; no network.
- [ ] **0.2** `terraform validate` on `apps/web-platform/infra/` with the new file present.
      Provider `ExactlyOneOf`-class validation is invisible to `terraform providers schema -json`
      (ADR-164), so `validate` is the authority. Note that it will **not** catch an API-side
      token-name rejection — `token-drift-ci-tf-prd_workspaces_luks` is 37 chars vs siblings of
      13-19; that surfaces only at apply.
- [ ] **0.3** **The conditional-adoption probe.** Against an existing config-scoped credential:
  - [ ] **0.3.1** Does a config-scoped token self-identify, and via **which field**? Try
        `doppler me --json` (pinned CLI v3.75.3, alias `whoami`), then
        `doppler configs -p soleur --json`. **Hard constraint: the field must be one Doppler
        DERIVES from the config binding — never one echoing the Terraform-supplied `name`.**
  - [ ] **0.3.2** Does `doppler secrets -c <WRONG-config>` **error**, or silently serve the bound
        config? Decides whether `-p`/`-c` stay on argv (FR7) and whether the script's "the config
        is named EXPLICITLY on every read" comment has inverted into a false guarantee.
  - [ ] **0.3.3** Confirm on a **branch**-scoped credential. The parse is already recorded at
        `apps/web-platform/infra/kb-drift.tf:94-96` (one entry, `success: true`) — this is
        confirmation, not discovery.
  - [ ] **0.3.4** Confirm a non-empty identity for the configs ADR-164's census called vacuous
        (`cli`, `cli_ops`).
  - [ ] **0.3.5** **Decision gate.** If 0.3.1 or 0.3.3 fails, control **C-c is DROPPED**. Record
        that in the plan/spec and in ADR-166. Do NOT improvise a substitute mid-build — C-a
        (static, pre-merge) carries the class and C-d (`sort -u`) is required regardless.
- [ ] **0.4** Re-measure the inventory against live Doppler
      (`doppler configs -p soleur --json | jq -r '.[].name' | sort`). This is the **only**
      pre-merge control on the new apply coupling: `infra-validation.yml`'s plan job is
      `continue-on-error: true` (`:1178`) and its other infra job runs `-backend=false validate`.

*(`-target=` on a `for_each` resource is already measured — R1 — and the CI Terraform pin is
identical to the probe host. Nothing to re-run.)*

---

## Phase 1 — Terraform (RED → GREEN)

- [ ] **1.1 RED** Write the **C-a** static test in `plugins/soleur/test/token-drift-workflow-causes.test.sh`:
      the `token_drift` resource block sets `config = each.key`, contains no `config = "` literal,
      and the map's key and value come from the same iteration variable. Anchor on the call form,
      not a bare token (`cq-assert-anchor-not-bare-token`). Confirm it fails now.
- [ ] **1.2 RED** Write **F5**: `local.token_drift_configs` is **set-equal** to the inventory's
      name lines; plus two source greps — the `.tf` contains the literal `^[a-z0-9_]+$` and
      contains no `trimspace(`/`trim(`/`chomp(`.
- [ ] **1.3 GREEN** Create `apps/web-platform/infra/token-drift-read-tokens.tf` per plan §D1:
      `distinct()`-wrapped `local.token_drift_configs` from `file()` + `can(regex(...))` over raw
      `split("\n")` lines (**no `trimspace()`**); `doppler_service_token.token_drift` with
      `for_each = toset(...)`, `config = each.key`, `name = "token-drift-ci-tf-${each.key}"`,
      `access = "read"`, no `lifecycle`, no `expires_at`;
      `github_actions_secret.doppler_token_drift_map` publishing `DOPPLER_TOKEN_DRIFT_MAP` as
      `jsonencode({for _cfg, _t in ... : _cfg => _t.key})` (**`.key`**, not `.api_key`).
- [ ] **1.4** Delete `apps/web-platform/infra/token-drift-service-account.tf` (all four resources).
- [ ] **1.5** Fix `apps/web-platform/infra/kb-drift.tf:100-101` — the "one `doppler_service_account`"
      count and the `token-drift-service-account.tf` cross-reference.
- [ ] **1.6** `.github/workflows/apply-web-platform-infra.yml`: **add** two legs
      (`-target=doppler_service_token.token_drift`, one leg covers all 13 instances;
      `-target=github_actions_secret.doppler_token_drift_map`) to the default per-merge allow-list
      (`:461-577`). **KEEP** the four existing legs at `:523-526` — they carry the destroy.
- [ ] **1.7** `terraform fmt`, `terraform validate`, `plugins/soleur/test/terraform-target-parity.test.ts`.

---

## Phase 2 — Detector (RED → GREEN)

- [ ] **2.1 RED** Teach the `doppler` stub in `scripts/check-cloudflare-token-drift.test.sh:72-154`
      a token→config binding fixture so P3's per-config argv assertions gain teeth.
- [ ] **2.2 RED** Author `n5'` — the **producible** mis-binding: 13 **distinct** tokens all bound
      to one config (it passes shape validation, which is the point). Confirm it fails now.
- [ ] **2.3 RED** Author `n4'` (one revoked token → `configs: 12`, `degraded`, `configs_unread`
      naming exactly it), the malformed-map case (`unknown`, `0/13`, verdict published before
      exit 2, **zero** doppler calls), the masking-order case, and the single-mode regression case
      driving the **real** argv of all five legacy call sites — **none of which passes
      `--configs-floor`**.
- [ ] **2.4 GREEN — `sort -u` (control C-d).** `scripts/check-cloudflare-token-drift.sh:569` is
      currently plain `sort`. Add `-u`. Without it, N assertions of one config still length-N the
      array and print `N/13`. Mutation-test: removing `-u` must red `n5'`.
- [ ] **2.5 GREEN** Replace the `DOPPLER_CRED` snapshot (`:425-449`) with a `CRED_FOR[<config>]`
      map per plan §D3. Mode selection on **non-emptiness** (`[[ -n … ]]`), pinned — an empty
      `DOPPLER_TOKEN_MAP` must land in the "neither" arm so the merge→apply window reads
      `degraded 0/13`, not `unknown`. Map-shape validation (C-b) before any network call. **Unset
      `DOPPLER_TOKEN_MAP` after the parse**, mirroring the discipline the replaced block states.
- [ ] **2.6 GREEN** Single-credential mode (FR5b): 1-entry map from the existing
      `doppler configs -p soleur --json` (`:479-480`) restricted to exactly-one-result. Byte-for-byte
      today's behaviour; must NOT depend on the new self-identification surface.
- [ ] **2.7 GREEN** Retain `:479-480` with its new meaning; the fatal guard at `:481-485` becomes
      a per-credential failure that counts the config UNREAD.
- [ ] **2.8 GREEN — control C-c, ONLY IF task 0.3.5 admitted it.** Per-credential
      self-identification; a mismatch counts the config **UNREAD** (that is what gives it a
      channel) and emits `::error::token_drift_config_binding_mismatch`. **Capture the probe's
      exit status**: non-zero → `token_drift_identify_unreachable`, empty answer →
      `token_drift_identify_empty`, distinct from a mismatch.
- [ ] **2.9 GREEN** Point the four read sites (`:536`, `:714`, `:741`, `:742`) at
      `${CRED_FOR[$cfg]}`. Whether `-p`/`-c` stay is decided by task 0.3.2; if they go, test P3
      and the "named EXPLICITLY on every read" comment move with them.
- [ ] **2.10 GREEN** `compute_coverage` (`:260-296`): add a **map-shape** failure as a second
      `unknown` trigger, evaluated first. An absent/empty credential keeps publishing `degraded`.
      Nothing else changes.
- [ ] **2.11 GREEN** `coverage_ratio` on any fail-closed path is `<successful reads>/<inventory count>`
      — `0/13`, never `-/-`.
- [ ] **2.12 GREEN — NFR1.** Mask each credential the instant it is parsed out of the map and
      **BEFORE the first `doppler` invocation of any kind**. **Rewrite the comment at `:454-456`**
      — it currently forbids exactly this (*"The credential itself is deliberately NOT masked
      here"*) and its reasoning was written for a whole-secret credential GitHub masks
      automatically. Record why the prohibition is overturned.
- [ ] **2.13** `shellcheck` + `bash scripts/check-cloudflare-token-drift.test.sh`.

---

## Phase 3 — Workflow

- [ ] **3.1** `.github/workflows/scheduled-terraform-drift.yml` `env:` (`:153-198`): drop
      `DOPPLER_TOKEN`, add `DOPPLER_TOKEN_MAP: ${{ secrets.DOPPLER_TOKEN_DRIFT_MAP }}`.
      `DOPPLER_PROJECT` and `DOPPLER_CONFIGS_FLOOR: 13` unchanged; `DOPPLER_CONFIG` still absent.
      **This lands before 3.2** so no intermediate commit has new prose over an old credential.
- [ ] **3.2** Rewrite the `env:` comment block (`:154-197`) from the interim narration to the map
      shape, keeping the "three places move together" floor note in substance.
- [ ] **3.3 — the stale-prose sweep. Start from the grep, not from this list:**
      `git grep -n 'doppler_service_account' .github/workflows/scheduled-terraform-drift.yml`
      returns **6** lines.
  - [ ] **3.3.1** **`:422`** — the `degraded`-path `::warning::` in the token_drift step's own
        `run:` body. It fires on **every degraded run** and says the credential *"is a
        `doppler_service_account` holding a viewer membership … nothing left to widen"*. Both
        clauses become false. **This is the site the first sweep missed.**
  - [ ] **3.3.2** **`:660-667`** — the **`unknown`** branch of the coverage-issue body: *"a
        DETECTOR fault, not a credential fault … Do not touch the Doppler identity."* Rewrite.
  - [ ] **3.3.3** **`:668-692`** — the `CONFIGS == 1` interim branch: **delete**.
  - [ ] **3.3.4** **`:693-748`** — the `else` branch. Replace `N1`/`N2`/`N3` with plan §D5's rows.
        The service-account paragraph (`:694-702`), the `environments` paragraph (`:724-726`), the
        `doppler_service_token`-repoint-as-fault paragraph (`:727-731`) and the
        `-replace=doppler_service_account_token.token_drift` recipe (`:739`) all go. The
        `>=`-growth paragraph (`:743-748`) survives. **The step's `env:` (`:548-560`) carries no
        cause channel** — enumerate the possible causes and point at the run's annotations; never
        claim to have diagnosed one.
  - [ ] **3.3.5** `:156`, `:681-699`, `:710`, `:727-739`, `:1552`, `:1790-1795` — remaining
        resource/file references.
  - [ ] **3.3.6** `:1551-1555` and `:1790-1801` — the rung-2 prose asserting that repointing that
        job at the token-drift credential *"would satisfy the predicate"*. False under the new
        shape too; the reason becomes structural. `RUNG2_CONFIGS_FLOOR: 13` (`:1500`) unchanged.
  - [ ] **3.3.7** `:802-829` — the close arm's comment justifying the `configs_unread` conjunct
        via ephemeral configs padding the count. That route is structurally closed; the conjunct
        stays load-bearing for a different reason (C-d).
- [ ] **3.4** Widen the coverage-issue filer's gate so `at-floor` + `configs_unread == '-'` +
      `verdict == 'unavailable'` files/refreshes #7175 instead of falling between filer and
      closer. Reachable via the non-vacuity gate (`:278-281`, `:718-723`); today it strands #7175
      with a stale body and pins the follow-through TRANSIENT forever.
- [ ] **3.5** `lint-workflows`; `bash -c` each edited `run:` snippet.

---

## Phase 4 — Guards, sweep, probe

- [ ] **4.1** `plugins/soleur/test/token-drift-workflow-causes.test.sh` **C1** (`:1163`):
      re-point to `env.DOPPLER_TOKEN_MAP == '${{ secrets.DOPPLER_TOKEN_DRIFT_MAP }}'` and assert
      `env.DOPPLER_TOKEN` absent. Update the fail message to name Phase-0 probe 0.3 as the
      re-measurement it demands.
- [ ] **4.2** **C2** (`:1188`): keep `env.DOPPLER_CONFIG` absent; bare-token count **1 → 0**; add
      a positive pin of exactly one `secrets.DOPPLER_TOKEN_DRIFT_MAP` reference over the whole
      step YAML. Use `grep -Eo … | wc -l` (occurrences), **not** `grep -Ec` (lines).
- [ ] **4.3** **DO NOT EDIT** `FLOOR_MINIMUM=13` (`:1050`), the run-time
      `(( 10#$cfg_floor < 13 ))` (`:391`), or `RUNG2_CONFIGS_FLOOR: 13` (`:1500`). The C-a test
      and F5 are **additive**. F3 is an equality pin and cannot be the ratchet.
- [ ] **4.4** Raise both anti-vacuity floors: `>= 57` (`:1396`) and `>= 80`
      (`scripts/check-cloudflare-token-drift.test.sh:1806`) by the net-new case count. Never down.
- [ ] **4.5** `scripts/followthroughs/token-drift-coverage-7159.sh`:
  - [ ] delete the `1/*` TRANSIENT arm (`:96-106`);
  - [ ] keep the `0/*` arm (`:92-95`);
  - [ ] add an **unparseable-ratio** arm (`-/-`, `-`, empty) → TRANSIENT, not FAIL;
  - [ ] rewrite the FAIL remedy (`:107`), which names a service-account membership that will not
        exist;
  - [ ] fix `:8-9` and `:93`, which assert a `web-platform-infra-apply` **required-reviewer gate
        that no longer exists** (removed by PR #4220, `apply-web-platform-infra.yml:341`);
  - [ ] rename the `DOPPLER_TOKEN_DRIFT` reference at `:8` to `DOPPLER_TOKEN_DRIFT_MAP`.
- [ ] **4.6** `scripts/check-cloudflare-token-drift.test.sh:1268` — the N3 comment.
- [ ] **4.7** `scripts/encryption-posture-ledger.json` — remove the three now-dead
      `non_store_types` entries (verified harmless to leave; removed for hygiene).
- [ ] **4.8** `apps/web-platform/infra/doppler-config-inventory.txt` header: rewrite the
      "REPORTS; GATES NOTHING" claim for the dual role (it now determines the credential's reach;
      it still gates no verdict **threshold**). Add to the "THREE `13`s" block: the **destroy
      guard** as the fourth ratchet layer, and the **`prd_git_data` `depends_on` trap** (SE-4) —
      the floor-raiser reads this block, not the plan.
- [ ] **4.9** Fix `plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh` — it hard-codes
      `scheduled-content-vendor-drift.yml`, which no longer exists (the job moved to
      `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts`). One line, fixed
      inline rather than filed (`rf-review-finding-default-fix-inline`).
- [ ] **4.10** File **two** follow-up issues: (a) the `rung2-rehearsal-orphan-sweep` scratch probe
      is `unsatisfiable` by construction, together with the new standing blind spot (a
      Doppler-side config addition is now undetectable); (b) prune the four dead `-target=` legs,
      **gated on `terraform state list | grep -c doppler_service_account` returning 0**, not on a
      green apply.
- [ ] **4.11** **Mutation-test every new/changed assertion** — delete it and confirm the suite
      reds. Specifically: removing `-u` from `:569` must make `n5'` report `13/13`.

---

## Phase 5 — ADR, C4, closure artifacts

- [ ] **5.1** Re-derive the ADR ordinal against **freshly-fetched `origin/main`** (166 at plan
      time; ADR-164 moved five times in one pipeline). Sweep this branch's own artifacts only.
- [ ] **5.2** Create `ADR-<n>-per-config-read-tokens-for-the-token-drift-scan.md`, header
      `**Supersedes (in part):** ADR-164`. Record: the service-account measurement; why ADR-164's
      `for_each` rejection is void; the measured cost corrections; the mis-binding hazard and the
      C-a/C-b/C-c/C-d set including that C-c is conditional; rotation cost; the new standing
      blind spot.
- [ ] **5.3** Edit ADR-164: status → `Accepted — Decision 1 superseded by ADR-<n> (2026-08-03);
      Decision 2 amended in one bullet, otherwise in force`; add the reciprocal marker; add the
      falsified-premise note to the `for_each` row of Alternatives; **amend Decision 2's "The
      committed inventory reports, and gates NOTHING … changes no state" bullet** to "gates no
      verdict threshold". Do not rewrite the rest of the body — it is the record.
- [ ] **5.4** Add a **single-line** `github -> doppler` relationship to
      `knowledge-base/engineering/architecture/diagrams/model.c4`, beside the other `github -> *`
      edges, carrying **no numeric count** (`plugins/soleur/test/c4-count-parity.test.sh` exists
      because prose counts went unchecked). Rationale lives in the ADR, not the diagram.
- [ ] **5.5** `bash scripts/regenerate-c4-model.sh` and **commit `model.likec4.json`** —
      `plugins/soleur/test/c4-model-freshness.test.sh` byte-diffs it and runs in the required
      `test-scripts` shard; the pre-commit hook is `--no-verify`-bypassable.
- [ ] **5.6** Run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`, and
      `plugins/soleur/test/c4-model-freshness.test.sh`.

---

## Phase 6 — Verify and ship

- [ ] **6.1** Full suite. Then, each in **CI's exact form**:
  - [ ] `terraform fmt -check` + `terraform validate` (`apps/web-platform/infra/`)
  - [ ] `shellcheck` on every edited shell file
  - [ ] `bash scripts/check-cloudflare-token-drift.test.sh`
  - [ ] `bash plugins/soleur/test/token-drift-workflow-causes.test.sh`
  - [ ] `bun test plugins/soleur/test/`
  - [ ] `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` —
        **no explicit path list**; a hand-enumerated subset verifies a different set than CI does
  - [ ] `python3 scripts/lint-encryption-posture.py --repo-sweep`
- [ ] **6.2** **`[ack-destroy]` on its own line in a BRANCH COMMIT MESSAGE BODY**, verified with
      `git log origin/main..HEAD --format=%B | grep -Fxq '[ack-destroy]'`. This repo is
      `squash_merge_commit_message: COMMIT_MESSAGES` (measured), so the merge commit is built from
      branch commit messages — **a PR-body-only ack never reaches the gate**, and the apply then
      HALTs on 4 planned deletes with the step already repointed at an unpublished secret.
- [ ] **6.3** PR body: `Closes #7234`, **`Ref #7159`**, **`Ref #7175`** (never `Closes`/`Resolves`
      for the latter two); the four expected destroy addresses named for reviewer diffing; the
      removed→replacement assertion table; links to both follow-ups.
- [ ] **6.4** Post-merge, **automated, no operator step**: verify the apply (13 token creates, 1
      secret create, 4 destroys) via `gh run view`; then the next scheduled drift run at
      `coverage: at-floor`, `ratio: 13/13`, `configs_unread=-` (read via `gh run view --json` —
      the verdict log line does **not** carry `configs_unread`); then #7175 auto-closes; then
      `bash scripts/followthroughs/token-drift-coverage-7159.sh` returns PASS.
- [ ] **6.5** Close #7234 and #7159 **only after 6.4 fully holds against a real scheduled run.**
      A green CI run is not sufficient — #7162 was green on CI while reading zero configs.
