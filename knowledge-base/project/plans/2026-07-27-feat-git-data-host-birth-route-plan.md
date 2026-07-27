---
date: 2026-07-27
issue: 6977
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff: conditional (5 conditions, all folded in — see Domain Review)
status: reviewed-v2
branch: feat-one-shot-6977-git-data-birth-route
---

# feat(6977): give `git-data` an executable birth route

> **SCOPE FENCE.** This PR ships the **ROUTE**, not the **dispatch**. No step creates
> `hcloud_server.git_data`. The hold on dispatching is mechanical (§Birth-readiness interlock),
> not prose.

**v2 after a 7-agent review panel.** Three reviewers independently found the same P0 in v1's gate
contract. Two found a blocking unverified precondition. Kieran found two false measurements in v1 —
one of which I copied from the task brief without checking. All fixed below; v1's reasoning is
retained only where it survived. Open scope questions live in
`knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md`.

## Overview

`soleur-git-data` is declared in IaC and has never existed. Authenticated `terraform state list`
(201 addresses) returns **one** `git_data`-matching member: `terraform_data.git_data_probe_install`
— which provisions **web-1**, not git-data. All ~19 git-data addresses are absent.

No automated route can create it. `git-data-host-replace` hard-aborts on a first CREATE three ways
(`server_replaced` requires `actions ⊇ {delete,create}`; `luks_passphrase_touched == 0` fires on
**create** too; `out_of_scope == 0` over a 5-member allow-set vs an 18-address birth fan-out), and
there is no `git-data-host-create` in the `apply_target` enum. The only remaining route is an
untargeted apply from a laptop — no destroy-guard, no stock preflight, and a 2026-07-27 plan of that
shape carried **9 destroys**. That is a standing `hr-all-infrastructure-provisioning-servers` and
`hr-fresh-host-provisioning-reachable-from-terraform-apply` violation.

This mirrors `web-host-create` (ADR-145) — additive, stock-preflighted, **inverted** gate — with
four evidenced deltas: singleton not `for_each`; no container image so no digest pin; a LUKS boot
dependency the web host lacks; and **no off-host emitter at all**.

**Why the bar is `single-user incident`:** git-data is the shared bare-repo store — the workflow
calls it *"the fleet's most irreplaceable data store."* Per ADR-145, **a new dispatch job inherits
nothing**: the per-PR HALT is a separate inline copy in the `apply` job whose `if:` is mutually
exclusive with every dispatch job. For this path the new gate is the **only** check.

**One affirmative structural finding (architecture-strategist, verified):** the upstream transitive
closure of the targets adds exactly `hcloud_ssh_key.default`, `hcloud_network.private`,
`hcloud_network_subnet.private` (all pre-existing → `no-op`) and `data.hcloud_server_type.git_data`
(a `read`, filtered by the positive-verb selector). `hcloud_server.web`, `hcloud_firewall.web` and
`hcloud_firewall_attachment.web` are **not** in the closure — git-data's firewall attachment is
single-host, unlike the web fleet singleton. **No birth dispatch can mutate a live serving
resource.** This is a genuine advantage over the web precedent, and it is why several ADR-145 arms
are backstops here rather than live coverage.

---

## Premise Validation

Checked against live state and `origin/main`. **The brief was wrong four times; v1 was wrong four
more.** Per `hr-verify-repo-capability-claim-before-assert`.

| # | Claim | Verdict | Evidence | Response |
|---|---|---|---|---|
| P1 | Brief: *"no `web-host-create-gate.sh` … the birth gate is INLINE in the workflow YAML"* | **FALSE** | `tests/scripts/lib/web-host-birth-gate.sh` (293 lines) is `source`d in the `web_host_create` plan step; its suite is 34/0; ADR-145 names it. The brief searched the wrong *filename* (`-create-` vs `-birth-`). | Gate is a **sourced file**, not inline YAML. Inline would be untestable and would fail the parity job⇄gate pairing. |
| P2 | Brief: enum has 10 options. **v1 said 13.** | **BOTH WRONG — it is 12** | Parsed `options:`: `manual-rerun, inngest-host, inngest-host-replace, registry-host-replace, registry-region-migrate, registry-luks-recut, git-data-host-replace, workspaces-luks-cutover, workspaces-luks-recut, web-host-create, web-host-replace, entrypoint-audit`. | Do not restate a count — it rots, and has now rotted twice. Phase 3 adds a parity assertion instead. |
| P3 | Brief: *"register in `run-registered-suites.sh` (79 steps)"* | **FALSE, both halves** | That runner **derives** its list by grepping `infra-validation.yml` for `run: bash apps/web-platform/infra/<name>.test.sh`; a `tests/scripts/` suite is structurally invisible. `--list` prints **72**. | Register in **`scripts/test-all.sh`**. Registering where the brief said would have been a silent no-op — the exact failure it was trying to prevent. |
| P4 | `hcloud_server.git_data` absent from state | **CONFIRMED, wider than stated** | 201 addresses; zero git-data resources of any kind. | Confirms `out_of_scope ≥ 6`. No import/adopt hazard — ADR-136's whole-list class does not apply. |
| P5 | `git_data_server_type` default `cpx22` | CONFIRMED | `variables.tf`. | Stock preflight is meaningful (x86, orderable). |
| P6 | `GIT_DATA_STORE_ENABLED` absent from `prd` | CONFIRMED | `doppler secrets get` → not found. | Feature stays dark; the birth does not flip it. |
| **P7** | **`prd_git_data` Doppler config exists** — *never checked by v1* | **FALSE — IT DOES NOT EXIST** | `doppler configs -p soleur` → `prd`, `prd_cla`, `prd_ghcr`, `prd_kb_drift_walker`, `prd_scheduled`, `prd_terraform`, `prd_workspaces_luks`. No `prd_git_data`. `git-data-luks.tf`'s OPERATOR NOTE says it *"must exist … BEFORE `terraform apply`"* and points at a browser click-path. | **BLOCKING — and that OPERATOR NOTE is obsolete.** Two of the targets write into it. **`doppler_config` is a real resource in the installed provider (dopplerhq/doppler v1.21.2, verified against `terraform providers schema`)**, and `zot-registry.tf` already provisions Doppler project structure in Terraform *"REQUIRED for zero-operator provisioning"*. So this becomes an **18th target**, not a human step. |
| **P8** | **The heartbeat feeder is unshipped** (v1's Alternatives (e) rationale) | **FALSE** | `heartbeat-manifest.ts` git_data_prd row is `feeder: {kind:"timer"}` — *"#5274 PR C (#6548) SHIPPED the web-host probe."* | The **feeder exists**; the monitor and `GIT_DATA_HEARTBEAT_URL` do not. Exclusion stands, its *reason* changes — and it falsifies architecture-strategist's proposed interlock mechanism (DC-2). |
| **P9** | v1: *"the provisioner grep returns **zero** matches"* | **FALSE — returns 1** | `git-data.tf:9`, a **comment**: *"Apply-path note: cloud-init-only (NO remote-exec provisioner)."* | Conclusion holds; the measurement did not. Restated as an anchored assertion — a bare-token match is the shape `cq-assert-anchor-not-bare-token` bans. |
| **P10** | v1 (copied from the brief): *"`web-git-data-probe.sh:13` cites `git-data.tf:338-341`; TODO at 342-345"* | **FALSE on both sides** | Line 13 cites **`git-data.tf:270-273`**; the TODO is at **`git-data.tf:348`**. | v1 propagated the brief's numbers unverified — the exact defect class this plan is about. Corrected in Sharp Edges; the *decision* (leave it alone) is unchanged. |
| **P11** | v1: *"the four `*-host-replace` jobs carry no `environment:`"* | **FALSE** | Only `inngest`/`registry`/`git_data_host_replace` lack it; **`web_host_replace` carries `environment: web-platform-infra-apply`** (*"REUSED, never re-declared"*). | Not a divergence — it is the majority pattern for gated dispatch. Removed from the ADR framing. |

### Two dependency facts that drive the `-target` set

- **P12 — the LUKS secret pair is a *sibling*, not an ancestor.** `doppler_service_token.git_data`
  **is** upstream (`.key` is baked into `user_data`), but `random_password.git_data_luks` and
  `doppler_secret.git_data_luks_key` are not. A server-only target hands the host a read-only token
  for a config containing **no `GIT_DATA_LUKS_KEY`** → `luksOpen` fails, and per Sharp Edge #2
  **nothing aborts**: the boot "succeeds" with the volume unmounted. *The issue does not list this.*
- **P13 — nothing orders the LUKS secret *before* the server.** There is no edge in **either**
  direction between `hcloud_server.git_data` and `doppler_secret.git_data_luks_key`, so Terraform may
  create the host first; it boots, reads an empty config, and silently never opens the volume.
  `runcmd` is once-per-instance so no reboot repairs it, and **ADR-115 bars git-data from the reboot
  primitive** anyway. Low probability, unrecoverable, no signal. Fixed in §Infrastructure.

---

## The `-target` set

Eighteen addresses, derived from measured dependency direction. `def allow:` must equal this set
exactly; the parity test asserts three-way equality.

| # | Address | Direction | Why |
|---|---|---|---|
| 1 | `hcloud_server.git_data` | — | The birth. Also keeps `data.hcloud_server_type.git_data` **referenced**, so the arch precondition is not pruned under `-target`. |
| 2–3 | `hcloud_volume.git_data`, `.git_data_luks` | upstream | `.id`s are in `user_data`. |
| 4 | `doppler_service_token.git_data` | upstream | `.key` baked into `user_data`. |
| 5–7 | `tls_private_key.git_{transport,provision,remove}` | upstream | Public halves → `authorized_keys`. |
| 8 | `hcloud_server_network.git_data` | downstream | Omit → **no private IP** (#6416), unrepairable by reboot. |
| 9–10 | `hcloud_volume_attachment.git_data`, `.git_data_luks` | downstream | Omit → store boots **unmounted**; at-rest encryption absent while artifacts claim it. |
| 11 | `hcloud_firewall.git_data` | **upstream of #12** | Zero-rule deny-all. *(v1 said "independent, nothing pulls it" — **wrong**: `-target` is transitive upstream and #12 references `.id`.)* |
| 12 | `hcloud_firewall_attachment.git_data` | downstream | The only binding of #11 to the host. Omit → store boots **naked on public IPv4/IPv6**. |
| 13–15 | `doppler_secret.git_{transport,provision,remove}_ssh_private_key` | sibling | **Issue AC4.** Not in the server's graph. Omit → private halves live only in tfstate. |
| 16–17 | `random_password.git_data_luks`, `doppler_secret.git_data_luks_key` | sibling | **P12.** Omit → silent `luksOpen` failure. |
| **18** | **`doppler_config.git_data_prd`** (NEW) | **upstream of #4, #17** | **P7.** The `prd_git_data` branch config does not exist. Provisioned in Terraform — see §Infrastructure. |

**REFUSED** (gate aborts if they appear as a mutation):

| Address | Why |
|---|---|
| `betteruptime_heartbeat.git_data_prd`, `doppler_secret.git_data_heartbeat_url_prd` | The feeder is web-host-resident and already shipped (P8); the monitor + URL are #6548/#6982's. Creating a monitor this route cannot arm reproduces the #6537 fed-but-paused shape. **Not upstream of any target → unreachable today; a backstop, not live coverage.** |
| `terraform_data.git_data_probe_install` | **SSH-provisions web-1.** Also not reachable from the set — but this arm **is** load-bearing if someone adds the address by hand, because `remote-exec` runs at apply, not plan. |

**TOLERATED as `no-op`** (must NOT be refused — refusing them aborts on legitimate shared drift):
`hcloud_ssh_key.default`, `hcloud_network.private`, `hcloud_network_subnet.private`.
`hcloud_ssh_key.default` is safe **because `server.tf`'s `hcloud_ssh_key.default` carries
`lifecycle { ignore_changes = [public_key] }`** (*"CI drift checks use a dummy key"*) — without it
the job's ephemeral `ssh-keygen` key would ForceNew-replace the SSH key shared by web-1, registry,
inngest and grok-dogfood. *(v1's "it exists so it's a no-op" was the right conclusion from the wrong
reason.)*

---

## Gate contract

Sourced file `tests/scripts/lib/git-data-host-birth-gate.sh`, signature
`git_data_host_birth_gate <plan-json>` — **singleton, no key argument**, so `def allow:` (not
`def allow($k):`) and the parity test's simpler extractor applies.

**Fail-closed preamble.** Every counter validated `^[0-9]+$` **before** any arithmetic: with `set -e`
disabled a failed `jq` yields `""`, and `[[ "" -gt 0 ]]` is FALSE under bash coercion — silently
passing a destructive plan (a recorded defect). Unparseable plan ⇒ ABORT, never PASS.

> **cto F1, measured:** only `web-host-birth-gate.sh` and `web-host-replace-gate.sh` carry the
> `has("resource_changes")` and `actions | type == "array"` arms. The other five shipped gates —
> including `git-data-host-replace-gate.sh` — carry **neither**. The copy-the-sibling pattern has
> already produced a two-tier safety floor. Phase 1 extracts the preamble to
> `tests/scripts/lib/plan-gate-preamble.sh`; a retrofit issue covers the five.

**Prohibition arms:** cardinality (`hcloud_server` creates `== 1`, distinct 0-vs->1 messages) ·
identity (the created address is `hcloud_server.git_data`) · destroys `== 0` counting `delete`
**and** `forget`, type-unscoped · named volume-destroy arm reporting the offending address
(**issue AC2**) · reboot-forcing in-place update · out-of-scope via `IN(.address; allow[])` for
**exact** membership (never `contains`/`inside`, which substring-match `git_data` into
`git_data_luks`).

**Two arms v1 omitted, both closing real holes:**

- **Firewall-content arm.** v1 moved `hcloud_firewall.git_data` **into** the allow-set, where
  `update` is permitted and no arm inspects it — a **relaxation** of the replace gate on the one
  address carrying the entire public-exposure defense. An `update` adding inbound rules to the
  zero-rule deny-all firewall passed every v1 arm. Assert `.change.after.rule | length == 0`. Same
  for `update` on either `hcloud_volume.git_data*` (a resize riding a birth is a mis-scope signal).
- **LUKS-passphrase catastrophe arm.** `random_password.git_data_luks` /
  `doppler_secret.git_data_luks_key` must show **no `delete`/`forget`/`update`** — the replace gate's
  `luks_passphrase_touched` invariant, which v1 dropped. A rotated passphrase `luksOpen`s a **new**
  header and strands existing at-rest data (ADR-115's second normative blocker).

### REQUIREMENT ARM — split by entailment (the v1 P0)

Three reviewers found this independently. v1 required `creates == 1` on five/six **siblings**.
`web-host-birth-gate.sh` states the rule verbatim under `WHY THESE TWO AND NOT ALL NINE`:

> *"the rule is not 'require the fan-out', it is 'require exactly those members whose existence the
> server's own creation entails'. **Anything looser breaks a legitimate retry**; anything tighter is
> unenforceable."*

v1 broke it in both directions:

- **False negative — permanent wedge.** `random_password.git_data_luks` is dependency-free and lands
  in the first wave. On a dispatch whose server create fails it is in state; the re-dispatch re-plans
  it `no-op` → `creates == 0` → **ABORT forever**. Meanwhile v1 said re-dispatch *"is safe and is the
  normal remedy."* Both dispatch routes then refuse (the replace gate needs `actions ⊇ {delete,create}`
  on an absent resource), leaving only the laptop apply this work exists to eliminate.
- **False positive — authorizes the ADR-115 catastrophe.** Host born, data written, host destroyed
  outside Terraform (a console or quota action), volumes retained, passphrase absent from state:
  v1's arm **mandates** a fresh passphrase, `isLuks` declines to reformat, `luksOpen` fails silently,
  data permanently unopenable — and the gate PASSes.

**Corrected contract:**

- `creates == 1` **only** for the four addresses referencing `hcloud_server.git_data.id`:
  `hcloud_server_network.git_data`, both `hcloud_volume_attachment.*`,
  `hcloud_firewall_attachment.git_data`. Entailment holds by construction.
- All other required members: assert **presence** — the address appears in `resource_changes` with
  actions ⊆ `{create, no-op}`. Still catches a typo'd `-target` (absent from the closure ⇒ presence
  fails), still satisfies AC4's intent, does not poison the retry.
- Add a **partial-birth resume fixture** whose plan mixes `create` and `no-op` across the set.

---

## Birth-readiness interlock

`cloud-init-git-data.yml` emits nothing off-host: measured **0** for `sentry_dsn`, `sentry`,
`vector`, `betterstack`, `journald`, `heartbeat`, `STAGE=`, `trap on_err`. The web host scores
9 / — / 14 / 2 / 7 / 4 / 1. ADR-145's gates #1 (`SENTRY_DSN` non-empty) and #3 (R2–R5 boot poll) both
presuppose the host emits. **A green `terraform apply` and a dark host are indistinguishable for
git-data.** The route therefore refuses to apply until an emitter exists.

**Revised after review** (v1 shipped this inline — the plan's own rejected Alternative (c) applied to
its riskiest control):

- Implemented as a **sourced, suite-covered gate** `tests/scripts/lib/git-data-birth-readiness-gate.sh`,
  so it inherits the mutation battery and the parity job⇄gate pairing.
- Sentinel is the **interpolated `${sentry_dsn}`** in the `templatefile` vars block, not a bare word
  — `templatefile` fails on an undefined var, making the marker self-enforcing and immune to a
  comment satisfying it.
- Its **failure message is the #6982 handoff**, and its text is mandated, not merely its existence:
  name #6982, the sentinel, the runbook banner to clear, and the ADR.
- **Release condition is a checklist in the ADR**, so #6982 inherits it mechanically: sentinel
  present **and** the emitter's credential reachable within `doppler_service_token.git_data`'s
  single-config scope (an emitter reading a DSN from Doppler is dark **by construction** today)
  **and** any new address added to the `-target` set + allow-set + const **and** a post-apply signal
  replacing ADR-145's dropped R2–R5 poll.
- **Scope-honest claim:** the interlock makes dark-boot unreachable **from this route**. The
  break-glass laptop apply is unaffected. v1's ADR said "impossible"; that overstated it.

> `architecture-strategist` proposed reading `heartbeat-manifest.ts`'s feeder declaration instead.
> **Falsified by P8** — that row is already `kind: "timer"`, so such a sentinel would release
> immediately. Recorded in DC-2.

---

## Two coupled defects — resolution

**Defect 1 — minted transport keys never reach the running container.** The three `tls_private_key`
are upstream (public halves → `user_data`); their `doppler_secret` siblings are not. A server-only
target writes public halves into `authorized_keys` while private halves live only in tfstate.

- `-target` membership (**AC4**).
- Requirement-arm **presence** assertion (not `creates == 1` — see above).
- **Container remediation:** a `ci-deploy` redeploy. There is **no `soleur-web.service`** unit at all
  — `ci-deploy.sh`'s `resolve_env_file()` runs `doppler secrets download … --format docker` and
  passes `--env-file` to `docker run`, so the env is baked at container start. The release pipeline
  already redeploys on any merge touching `apps/web-platform/**`. v1 prescribed a service-unit
  restart, which would have sent the reader to a command that does not exist.

**Defect 2 — `GIT_REMOVE_SSH_PRIVATE_KEY` decouples from the store's existence.** `removeGitDataRepo`
is deliberately **not** gated on `isGitDataStoreEnabled()` (flag-gating erasure would strand a user's
PII across a rollback window — an Art. 17 gap). It gates on the remove key being present: **the key's
presence is the arming switch.**

- **`depends_on = [hcloud_server.git_data]` on the three SSH `doppler_secret`s.** The only mechanism
  that survives a partial apply. No cycle: the server reaches `tls_private_key.git_remove` via
  `local.git_remove_pubkey`; nothing reaches the `doppler_secret`. Verified independently by two
  reviewers.
- **CUT: `doppler_secret.git_data_ssh_host` (v1's 2b).** Adding it makes
  `terraform-target-parity.test.ts` RED on landing, and the natural remedy — a per-PR `-target` line
  — drags `hcloud_server.git_data` into the per-merge plan via upstream closure, tripping
  `host_creates > 0` and **wedging every merge to main**. Moved to #6982. Rationale + the CPO dissent
  in **DC-3**.
- **CUT: v1's 2c gate arm** — a plan creating the remove key without the server has `hcloud_server`
  creates `== 0`, already rejected by the cardinality arm.
- **Residuals, honestly recorded:** `depends_on` anchors on the **server object**, not on
  **reachability** — a birth where the server lands but the NIC does not still arms the key against
  an unroutable `10.0.1.20`. And post-birth/pre-cutover the store is empty, so `git-data-remove.sh`
  (idempotent) exits 0 and Art. 17 records **success** for a repo the store never held. Neither is
  closed here. §GDPR Gate records them as **accepted residuals** — v1 claimed "fixed" and was wrong.

---

## Architecture Decision (ADR/C4)

**ADR-149** (ordinal **provisional** — `ADR-148` is highest on `origin/main`; `/ship`'s collision
gate re-verifies, and a renumber must sweep plan + tasks + ACs, not just the ADR body).

Records: the three ADR-145 deltas (singleton; no digest pin — git-data has no image var or
`host_scripts_content_hash`; the LUKS boot dependency); the **birth-readiness interlock** and its
release checklist; and two residuals ADR-145's shape does not cover — the **ADR-115
guest-convergence gap** (a tfplan `nic_recreated` assertion proves Terraform *planned* the attach,
never that the guest configured it; git-data is barred from ADR-115's remedy) and the **empty-store
Art. 17** window. Also amend ADR-145's `## Consequences` with a pointer.

### C4 views — completeness enumeration (all three model files read, not grepped)

External human actors (`founder`), external systems (`hetzner`, `betterstack`, `github`, Doppler),
containers (`gitDataStore`) — **all already modeled; no new element, no `views.c4` change**
(`gitDataStore` is already included). What changes is **description accuracy**:

- `model.c4` `gitDataStore` — records at-rest posture but never that the host has **never been
  born**, so a reader concludes the store exists. Precedent for exactly this disclosure already
  exists on web-2 (*"remains single-host until web-2 is provisioned by the gated web-host-create
  dispatch"*).
- `model.c4` `betterstack -> founder` — asserts *"the git-data heartbeat does NOT [alert] — it is
  **unfed** and absent live"*. **Falsified by P8**: the feeder shipped. *(v1's sweep missed this edge
  entirely.)*
- Re-read the `hetzner -> gitDataStore` and `claude -> gitDataStore` edges for the same class.

Run `c4-code-syntax.test.ts` + `c4-render.test.ts`; regenerate `model.likec4.json`.

---

## Infrastructure (IaC)

| File | Change | Why |
|---|---|---|
| `git-data-luks.tf` | **NEW `resource "doppler_config" "git_data_prd"`** — project `soleur`, environment `prd`, name `prd_git_data`; `doppler_secret.git_data_luks_key` and `doppler_service_token.git_data` reference it instead of the string literal | **P7.** The config does not exist, and the birth writes into it. `doppler_config` is in the installed provider (v1.21.2, verified against `terraform providers schema`), and `zot-registry.tf` already provisions Doppler project structure in Terraform *"REQUIRED for zero-operator provisioning"* — created *"BARE … so without this the host secrets below fail at apply with `Doppler Error: Could not find requested config`"*, which is verbatim the failure this prevents. **Retire `git-data-luks.tf`'s now-obsolete OPERATOR NOTE** and point it at the resource. `var.doppler_token_tf` is a workplace-scope token already creating `doppler_project` + `doppler_environment` for the registry, so the scope class is proven — but /work must still run an ADR-130-style scope probe before the first apply, since a branch config is a distinct API surface from an environment. |
| `git-data.tf` | `depends_on = [hcloud_server.git_data]` on the three `doppler_secret.git_*_ssh_private_key` | Defect 2 |
| `git-data.tf` | **`depends_on = [doppler_secret.git_data_luks_key]` on `hcloud_server.git_data`** | **P13** — orders the LUKS key **before** the host boots. Cross-path check: this makes the pair upstream of the server, so it enters the *replace* job's closure as `no-op`; `luks_passphrase_touched` filters on the four mutating verbs so a `no-op` does not trip it — **assert as a regression arm** in `test-git-data-host-replace-gate.sh`. §Test Strategy's "replace gate unchanged" is no longer sufficient. |

No provider changes, **no new root variable** (`hr-tf-variable-no-operator-mint-default` not
engaged). **Blast-radius cleared:** `git-data.tf` / `git-data-luks.tf` are not hashed into any
`triggers_replace` (Terraform never hashes `.tf`); all 18 addresses are (or will be) in
`OPERATOR_APPLIED_EXCLUSIONS` — the 17 existing ones each verified individually, and
`doppler_config.git_data_prd` must be **added to that set, never given a per-PR `-target` line** (a
`-target` on it would drag the server into the per-merge plan and wedge main, the same mechanism
that killed v1's 2b). So **merging applies nothing to git-data**.

**Apply path:** cloud-init-only via gated `workflow_dispatch`, **not executed by this PR**.

**Drift safeguards:** add no `lifecycle.ignore_changes` — `hcloud_server.git_data` deliberately
carries a `precondition`-only lifecycle block, and adding `ignore_changes=[user_data]` would silently
break `git-data-host-replace`. Keep the arch `precondition` **referenced**: under `-target` an
unreferenced data source is **pruned and never read**, so deleting it silently disarms the
phantom-type guard. Per trap #4 that precondition is the **only** guard that fires — neither the
Doppler checksum nor the LUKS `set -euo pipefail` fails closed.

**Vendor-tier reality check:** branch configs under `prd` are already in use on the current tier
(`prd_cla`, `prd_ghcr`, `prd_kb_drift_walker`, `prd_scheduled`, `prd_terraform`,
`prd_workspaces_luks` all exist), so no paid-tier gate is needed. This is distinct from the *config
inheritance* feature `zot-registry.tf` calls out as paid (#6067), which this does not use.

---

## Observability

```yaml
liveness_signal:
  what: The dispatch job. A route never dispatched has no runtime; the terminal signal is the
        GitHub Actions job conclusion + $GITHUB_STEP_SUMMARY, both off-host.
  cadence: per-dispatch
  alert_target: >-
    GitHub Actions job failure on `git_data_host_create`. NOT betteruptime_heartbeat.git_data_prd:
    its feeder is web-host-resident and already shipped (P8), so it measures the web-to-git-data
    path, not the birth. heartbeat-manifest.ts records the exemption.
  configured_in: .github/workflows/apply-web-platform-infra.yml (job `git_data_host_create`)
  live_verification: gh run list --workflow=apply-web-platform-infra.yml --json conclusion
error_reporting:
  destination: GitHub Actions step log + `::error::` annotations; each abort arm names WHICH arm refused.
  fail_loud: YES, and fail-CLOSED on unreadable input (see Gate contract preamble).
failure_modes:
  - mode: Plan is not the exact scoped birth (extra creates, any destroy, out-of-scope address)
    detection: git_data_host_birth_gate returns 1; offending addresses printed
    alert_route: job fails BEFORE apply; nothing created
  - mode: prd_git_data config missing, or the Doppler token lacks config-create scope
    detection: >-
      The config is now a Terraform resource, so a missing config is a planned CREATE the gate
      admits, and a scope failure surfaces as a terraform apply error naming the resource — not as a
      silent half-apply. /work runs an ADR-130-style scope probe before the first dispatch.
    alert_route: job fails at apply with the resource address named
  - mode: server_type not orderable in its location
    detection: >-
      stock_preflight_gate returns 1. Sourced AFTER the birth gate: the birth gate proves the plan
      IS the scoped birth, the preflight proves it is FEASIBLE, and terraform creates the volumes
      before the server, so a stock miss otherwise strands them.
    alert_route: job fails before apply
  - mode: >-
      A required sibling write is requested but not created (typo'd -target — no CI net for
      hcloud_*/doppler_secret.* addresses)
    detection: requirement-arm presence assertion
    alert_route: job fails before apply
  - mode: Birth would land a host that emits nothing off-host
    detection: birth-readiness gate; the sentinel measures 0 today, so the route refuses
    alert_route: job fails at the interlock, before plan
  - mode: Apply succeeds, host boots dark (LUKS unmounted, runcmd failed silently)
    detection: >-
      NOT DETECTABLE TODAY — and that is the point. Zero emitter occurrences measured; ADR-145's
      R2-R5 poll has no analogue because there is nothing to poll. The interlock makes this
      unreachable FROM THIS ROUTE (not absolutely — break-glass is unaffected) until #6982 lands.
    alert_route: none exists; converted from undetectable to route-unreachable
logs:
  where: >-
    GitHub Actions run logs + $GITHUB_STEP_SUMMARY. NOT on-host /var/log/cloud-init-output.log,
    which is unreachable without SSH on a deny-all host (hr-no-ssh-fallback-in-runbooks).
  retention: 90 days (GitHub Actions default)
discoverability_test:
  command: gh run list --workflow=apply-web-platform-infra.yml --limit 5 --json conclusion,displayTitle
  expected_output: JSON array with non-null `conclusion`. Contains no `ssh `.
```

**Soak follow-through: not triggered** — no time-gated close criterion; there is no deploy.

---

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.git_data (plaintext ext4, /mnt/git-data)
    mechanism: plaintext-exception
    evidence: >-
      `format = "ext4"`, no LUKS apparatus; bound via hcloud_volume_attachment.git_data; mount from
      user_data. Recorded identically in model.c4.
    defends_against: nothing at rest
    does_not_defend: >-
      Hypervisor disk access, snapshot exfiltration, decommissioned-disk paths. Contents are every
      connected user's source code.
    disclosed_as: >-
      Existing encryption-posture-ledger.json row, tracking #6897 — pre-existing; neither created
      nor widened here.
    live_verification: N/A pre-birth (volume absent, P4)
  - store: hcloud_volume.git_data_luks (LUKS2, /mnt/git-data-luks)
    mechanism: LUKS2 (dm-crypt), passphrase from random_password.git_data_luks
    evidence: >-
      luksFormat/luksOpen in cloud-init-git-data.yml with an idempotent isLuks skip; bound via
      hcloud_volume_attachment.git_data_luks.
    defends_against: at-rest recovery without the passphrase
    does_not_defend: >-
      Anything while OPEN; and nothing at all if GIT_DATA_LUKS_KEY never reaches the host
      (P12/P13) — which fails SILENTLY.
    disclosed_as: target state of the #5274 Phase-3 cutover; not yet the live store
    live_verification: N/A pre-birth (volume absent, P4)
in_transit:
  - connection: web host to git-data (transport / provision / erasure)
    tls: N/A — SSH, ED25519, private halves in Doppler prd
    cert_verification: on; private net (10.0.1.20), never traverses the public internet
    does_not_defend: >-
      A compromised web host holds all three private halves; blast radius bounded by three SEPARATE
      keypairs rather than one.
    disclosed_as: ADR-068 transport model, unchanged
exception:
  - store: hcloud_volume.git_data
    justification: >-
      Pre-existing ledgered plaintext store. This work makes the volume creatable by a gated route
      instead of an untargeted laptop apply — a strict containment improvement. NOTE: this route is
      what makes the exception LIVE for the first time, since every wrapper mounts /mnt/git-data
      until the cutover.
    tracking_issue: "#6897"
    reevaluate_when: the #5274 Phase-3 cutover flips the live store to git_data_luks
    expires_on: >-
      VERIFY the key exists in the ledger row before instructing /work not to re-date it — it may
      not be present.
```

---

## Domain Review

**Domains relevant:** Engineering, Operations, Legal/Compliance. **Product/UX Gate skipped** — the
mechanical UI-surface scan finds zero matches for `components/**/*.tsx`, `app/**/page.tsx`,
`app/**/layout.tsx` or any UI term in Files to Create/Edit. `ux-design-lead` correctly not invoked;
`wg-ui-feature-requires-pen-wireframe` not engaged.

**Engineering (CTO):** reviewed. Highest risks: gate vacuity (mitigated by SOLE-GUARD/LAYERED
contracts + non-vacuity floors + an **independent** reviewer), a `-target` typo having no CI net
(mitigated by the requirement arm), and the per-target-gate pattern's maintenance cost (F1 — the
preamble extraction addresses the cheap half; a retrofit issue covers the rest).

**Operations (COO):** reviewed. No new vendor, no new recurring expense from this PR. **Correction to
v1 — twice over:** v1 claimed nothing was deferred while a hand-created Doppler config was silently
required (P7). The resolution is **not** to document that step but to delete it: `doppler_config`
makes it a Terraform resource, so `hr-all-infrastructure-provisioning-servers` and
`hr-never-label-any-step-as-manual-without` are satisfied by construction and Post-merge is genuinely
empty. This also retires the obsolete OPERATOR NOTE in `git-data-luks.tf` that has been pointing
readers at a browser click-path.

**Legal/Compliance (CLO):** reviewed. See §GDPR Gate — two residuals now recorded honestly rather
than claimed fixed.

**Product (CPO) — SIGN-OFF WITH CONDITIONS.** All five folded in: (C1) threshold stays `single-user
incident`; (C2) the interlock's failure message is the #6982 handoff; (C3) 2b — **overruled on a
feasibility regression** (ADR-084's sanctioned exception), recorded in DC-3; (C4) the runbook must
state what the operator has *after* a green apply; (C5) the partial-birth dead end is closed by the
requirement-arm rewrite.

---

## GDPR / Compliance Gate

Advisory only — not legal advice; requires professional review. Triggered by threshold `single-user
incident` + the Art. 17 control path (the canonical regex does not match).

| Finding | Disposition |
|---|---|
| **F1 — Art. 17 arming order.** The remove key's presence is the arming switch. | **Partly fixed** — `depends_on` closes the "key lands without the server" window. **v1 claimed "Fixed in-plan"; that was wrong.** Two residuals remain. |
| **F1a — residual: reachability ≠ existence.** Server lands, NIC does not → key armed against an unroutable address. | **Accepted residual**, recorded in ADR-149. |
| **F1b — residual: empty-store silent success.** Pre-cutover the store is empty and `git-data-remove.sh` is idempotent → exit 0 → Art. 17 records **success** for a repo the store never held. | **Accepted residual.** Closing it needs a birth-completion marker the app can read — #6982/#5274 scope. |
| **F2 — do NOT gate `removeGitDataRepo` on `isGitDataStoreEnabled()`.** | **Scoped out with intent.** `git-data-replication.ts` is NOT in Files to Edit. Named so a reviewer does not propose it as a simplification — it would strand a user's PII across a rollback window. |
| **F3 — Art. 30.** No new processing activity (no data is processed until a birth). | **No new PA row.** A register entry for an activity that cannot occur is a false attestation. |
| **F4 — new secret material in tfstate** (3 ED25519 keys + LUKS passphrase). | Pre-existing posture, unchanged. |

---

## Open Code-Review Overlap

**None.** 60 open `code-review` issues queried; zero reference any file in Files to Create/Edit.

---

## Implementation Phases

Contract before consumer; tests before implementation. **No phase dispatches the workflow.**

### Phase 1 — Gate contracts (RED first)

1.1 Extract `tests/scripts/lib/plan-gate-preamble.sh` (~40 lines lifted from
    `web-host-birth-gate.sh`) + a small suite (cto F1).
1.2 Write `tests/scripts/test-git-data-host-birth-gate.sh` **first**, mirroring the sibling harness
    (self-contained, `mktemp -d` + `trap`, `mk_plan`/`rc_entry` synthesizers using `jq -R .`,
    `check <name> <want_rc> <needle> <plan>` pinning **both** rc and a message substring). Fixtures
    **synthesized only** (`cq-test-fixtures-synthesized-only`) — a captured `terraform show -json`
    embeds `.variables` verbatim. Cover every arm in §Gate contract, plus the **partial-birth resume
    fixture** (mixed `create`/`no-op`).
1.3 Implement `tests/scripts/lib/git-data-host-birth-gate.sh`; source the preamble.
1.4 Mutation battery: **SOLE-GUARD** (neuter ⇒ accepted) for destroy / out-of-scope / requirement /
    firewall-content / LUKS-passphrase arms; **LAYERED** (neuter ⇒ still rc 1 via out-of-scope, with
    a control proving the unmutated gate rejects via *that* arm) for identity / cardinality / reboot.
    **Non-vacuity floor on every mutation** (`cmp -s "$mutated" "$GATE"` ⇒ fail): `sed` exits 0 when
    it matches nothing.
1.5 Write `tests/scripts/lib/git-data-birth-readiness-gate.sh` + suite, asserting **behavior against
    synthesized fixtures** (sentinel present ⇒ pass, absent ⇒ refuse), **never the live count** — a
    test whose passing condition is "the feature isn't ready" gets deleted, not maintained.
1.6 Register both suites in `scripts/test-all.sh`. **Nothing enforces this** —
    `lint-orphan-test-suites.sh` scans only `scripts/*.test.sh`, and `run-registered-suites.sh` scans
    only `apps/web-platform/infra/**` — so it needs its own AC.

### Phase 2 — Workflow job + IaC

2.1 Add `- git-data-host-create` to the enum; extend `confirm` with `BIRTH-GIT-DATA`. Fix the
    field-label drift: the `description:` names **`registry-ruleset-entrypoint-audit`**, which is
    **not selectable** (the option is `entrypoint-audit`). Fix the stale `# NOTE on the input budget`
    comment (**7** inputs used, not 5) — it governs whether the next target gets a dedicated
    workflow. Do **not** restate an option count (P2). Per cto F3, replace the accreting
    `confirm.description` with a runbook pointer and move token literals into job headers.
2.2 Add `git_data_host_create:` — `environment: web-platform-infra-apply` (required reviewers **and**
    a `deployment_branch_policy` pinning `main`; the branch pin is load-bearing because the gate is
    sourced from `${GITHUB_WORKSPACE}`, so a branch dispatch could otherwise source a neutered gate).
    `concurrency:` **shared with `git_data_host_replace`** so a birth and a replace cannot race the
    same state. `permissions: { contents: read }`.
2.3 Step order: checkout → setup-terraform → Doppler CLI → validate confirm → ephemeral SSH pubkey →
    verify `DOPPLER_TOKEN` → extract backend creds + assert `SENTRY_DSN` non-empty →
    `terraform init` → **birth-readiness gate** → plan + birth gate + stock preflight → apply →
    summary (`if: always()`).
    - `SENTRY_DSN` read uses `|| rc=$?`, **never** `; rc=$?` — under `set -euo pipefail` an assignment
      whose substitution fails kills the step before the capture. Distinct messages for *unreadable*
      vs *empty*; never print the value.
    - `export HCLOUD_TOKEN` from Doppler **before** sourcing the stock gate — the gate runs outside
      the `doppler run` wrapper and the step `env:` is `DOPPLER_TOKEN` only.
      `stock-preflight-coverage.test.ts` asserts this per job; a gated job without it fails closed on
      **every** dispatch — an outage, not a tripwire.
    - No `-var="image_name=…"` — git-data has no image var.
2.4 Plan step opens `set +e; set -uo pipefail` (GitHub inherits `-e`), captures `rc=$?` on the **very
    next line**, then `set -e` before `terraform show`.
2.5 Apply-failure message: additive, so a re-dispatch is normally safe — **and now actually is**,
    because the requirement arm accepts `no-op` on non-entailed members. State the one exception
    (server landed, later address did not): `runcmd` is once-per-instance and has already finished,
    so the host must be **replaced**, not completed. Do not assert both halves at once — that
    self-refuting wording sent an operator to the wrong remedy on the web path.
2.6 IaC: `doppler_config.git_data_prd` + the two `depends_on` edits (§Infrastructure, incl. **P13**),
    and retire the obsolete OPERATOR NOTE in `git-data-luks.tf`.

### Phase 3 — Registries + parity

3.1 `terraform-target-parity.test.ts`: add `"git_data_host_create"` to `stripDispatchJobs`; add
    `GIT_DATA_BIRTH_TARGET_BASES`; add `"doppler_config.git_data_prd"` to
    `OPERATOR_APPLIED_EXCLUSIONS`; add a `describe` block mirroring the web one **minus** the
    keyed-interpolation and pinned-digest tests (no analogue — drop rather than fake). Assert the job
    sources both gates via a `^\s*source\s+` **command anchor** (a bare filename `.includes` is a
    recorded false-green), borrows no sibling gate (explicitly `git-data-host-replace-gate.sh`),
    carries the environment, and that `def allow:` == the `-target` set == the const.
3.2 Add the **enum ⇄ description parity assertion** (cto F2): split `apply_target.description` on
    `|`, assert every target-shaped token is an enum member. Retires a rot class the repo has now
    paid for twice.
3.3 `export TMPDIR="${TMPDIR:-/var/tmp}"` at the top of `scripts/test-all.sh` — removes the
    Sharp-Edge footgun by construction instead of documenting it a seventh time (cto F5).
3.4 Add the replace-gate **regression arm** for P13's new upstream `no-op`.

### Phase 4 — Runbook, ADR, C4

4.1 `knowledge-base/engineering/operations/runbooks/git-data-birth.md`, modelled on
    `web-host-birth.md`: **DO-NOT-DISPATCH banner** naming #6982 + the interlock; the dispatch
    invocation; **the post-birth `ci-deploy` remediation (issue AC5)**; **what the operator has after
    a green apply and what it is not** (empty store, `GIT_DATA_STORE_ENABLED` still absent, no
    monitor, plaintext-backed until the cutover) with a pointer to `git-data-luks-cutover-5274.md`;
    the partial-birth decision tree; **non-SSH verification only**. Note what the environment
    approver can actually verify — approval happens **before any step runs**, so they approve blind.
4.2 ADR-149 + the ADR-145 `## Consequences` pointer.
4.3 `model.c4` edits (§C4 views, including the `betterstack -> founder` correction); run both C4
    tests; regenerate `model.likec4.json`.
4.4 File the follow-on issue: retrofit the fail-closed preamble into the five gates lacking it.
4.5 Full gate run, then **route the vacuity question to an INDEPENDENT reviewer** at `/review`:
    *"find the vacuity this mutation battery missed — do not re-run its mutations."* Do not
    self-certify.

---

## Acceptance Criteria

### Pre-merge (PR)

**Issue #6977's five:**

- [ ] **AC1** A `git-data-host-create` target exists and its gate accepts a create-only plan. Verify
      by **parsed enum membership + the job `if:` needle** (as `jobFor()` does) — *not*
      `grep -c … ≥ 3`, which three comment lines satisfy and which
      `stock-preflight-coverage.test.ts` documents as a real false-green. Plus the happy-path fixture
      returning rc 0.
- [ ] **AC2** The gate rejects a plan destroying either data volume — two arms, each naming the
      offending address.
- [ ] **AC3** `stock-preflight-gate.sh` is sourced before the apply and **after** the birth gate;
      `stock-preflight-coverage.test.ts` resolves `git-data-host-create` to the new job as *gated*
      (not allowlisted) and detects the `export HCLOUD_TOKEN` read.
- [ ] **AC4** All three `doppler_secret.git_*_ssh_private_key` appear in `-target`, `def allow:` and
      the const, asserted equal three ways.
- [ ] **AC5** `git-data-birth.md` documents the post-birth `ci-deploy` remediation and contains
      **zero** occurrences of `soleur-web.service` (no such unit exists).

**Extensions, each traced to a review finding:**

- [ ] **AC6** Requirement arm is **split by entailment**: `creates == 1` for exactly the four
      id-referencing addresses; **presence** (`create`∨`no-op`) for the rest. A partial-birth fixture
      (mixed `create`/`no-op`) **PASSES**. *(v1's P0 — three reviewers.)*
- [ ] **AC7** Gate REFUSES: an `update` adding rules to `hcloud_firewall.git_data`; any
      `delete`/`forget`/`update` on the LUKS passphrase pair; a create of
      `betteruptime_heartbeat.git_data_prd` or `terraform_data.git_data_probe_install`. *(The last two
      are backstops — not reachable from the set today; stated, not over-claimed.)*
- [ ] **AC8** `hcloud_server.git_data` carries `depends_on = [doppler_secret.git_data_luks_key]`
      (P13) and the three SSH secrets carry `depends_on = [hcloud_server.git_data]`;
      `terraform validate` passes; the replace-gate regression arm passes.
- [ ] **AC9** `doppler_config.git_data_prd` exists in `git-data-luks.tf`, is referenced by
      `doppler_secret.git_data_luks_key` + `doppler_service_token.git_data` (no string literal), is
      in the `-target` set, allow-set, const **and** `OPERATOR_APPLIED_EXCLUSIONS`, and the obsolete
      OPERATOR NOTE is gone. **(P7.)**
- [ ] **AC10** The birth-readiness gate is a **sourced file** with its own suite, asserting behavior
      against synthesized fixtures (**not** the live sentinel count), and its failure message names
      #6982, the sentinel, the runbook banner and ADR-149.
- [ ] **AC11** Every mutation is SOLE-GUARD or LAYERED, each with a `cmp -s` non-vacuity floor; every
      LAYERED mutation runs its control.
- [ ] **AC12** Both new suites are registered in `scripts/test-all.sh` and execute there (nothing else
      enforces this).
- [ ] **AC13** `git diff --stat origin/main` shows **zero** changes to `web-git-data-probe.sh`, its
      unit/timer, or any `local.host_script_files` member — no SSH re-provision, no coherence-hash
      perturbation.
- [ ] **AC14** The enum ⇄ `description` parity assertion passes, and
      `registry-ruleset-entrypoint-audit` no longer appears.
- [ ] **AC15** All gates green (**≥** the baselines recorded in the PR body — do **not** pin absolute
      counts here; that has now rotted twice): `git-data-luks.test.sh`,
      `test-stock-preflight-gate.sh`, `validate-infra-templates.sh`, `run-registered-suites.sh`,
      `terraform test`, `scripts/test-all.sh`, both bun parity suites, both C4 tests.
- [ ] **AC16** ADR-149 exists (ordinal re-verified at ship); `model.c4`'s `gitDataStore` **and**
      `betterstack -> founder` descriptions corrected; C4 tests pass; `model.likec4.json`
      regenerated.

*Cut from v1 as ceremony or unverifiable:* the independent-review AC (a claim that the process ran,
already covered by Phase 4.5 + `rf-never-skip-qa-review-before-merging`), and the
`terraform state list` AC (needs prod backend creds, so it cannot run in the PR pipeline).

### Post-merge (operator)

**None.** The one candidate — creating the `prd_git_data` Doppler config — is provisioned by
`doppler_config.git_data_prd` (P7), so nothing is deferred and
`wg-block-pr-ready-on-undeferred-operator-steps` is satisfied. The dispatch itself is out of scope by
design, gated behind #6982 and the interlock.

---

## Files to Create

- `tests/scripts/lib/plan-gate-preamble.sh` + `tests/scripts/test-plan-gate-preamble.sh`
- `tests/scripts/lib/git-data-host-birth-gate.sh` + `tests/scripts/test-git-data-host-birth-gate.sh`
- `tests/scripts/lib/git-data-birth-readiness-gate.sh` + `tests/scripts/test-git-data-birth-readiness-gate.sh`
- `knowledge-base/engineering/operations/runbooks/git-data-birth.md`
- `knowledge-base/engineering/architecture/decisions/ADR-149-*.md` *(ordinal provisional)*
- `knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/tasks.md`

## Files to Edit

`.github/workflows/apply-web-platform-infra.yml` · `apps/web-platform/infra/git-data.tf` ·
`apps/web-platform/infra/git-data-luks.tf` · `plugins/soleur/test/terraform-target-parity.test.ts` ·
`scripts/test-all.sh` · `tests/scripts/test-git-data-host-replace-gate.sh` (P13 regression arm) ·
`knowledge-base/engineering/architecture/diagrams/model.c4` · ADR-145 (`## Consequences` pointer)

**Explicitly NOT edited:** `web-git-data-probe.sh` (double-hashed → root-SSHes web-1 **and** perturbs
the coherence hash) · `apps/web-platform/server/git-data-replication.ts` (F2 — flag-gating erasure is
an Art. 17 gap) · `cloud-init-git-data.yml` (#6982 owns it; a non-comment edit would self-satisfy the
interlock — a **comment-only** back-reference marker is permitted and desirable per cto F4, with a
suite arm proving it does not satisfy the sentinel).

---

## Test Strategy

| Layer | Command | Proves |
|---|---|---|
| New gates + mutation | `bash tests/scripts/test-git-data-host-birth-gate.sh`, `…-birth-readiness-gate.sh`, `…-plan-gate-preamble.sh` | Every arm fires; every arm is non-vacuous |
| Replace regression | `bash tests/scripts/test-git-data-host-replace-gate.sh` | P13's new upstream `no-op` does not trip `luks_passphrase_touched` |
| Stock / LUKS / templates | `test-stock-preflight-gate.sh`, `git-data-luks.test.sh`, `validate-infra-templates.sh apps/web-platform/infra` | Baselines hold |
| Registered infra | `bash apps/web-platform/infra/run-registered-suites.sh` | Derived suites pass |
| Terraform | `cd apps/web-platform/infra && terraform test` | **`test`, not `validate`** |
| Parity / coverage / C4 | `bun test plugins/soleur/test/{terraform-target-parity,stock-preflight-coverage}.test.ts apps/web-platform/test/c4-*.test.ts` | Pairing, set equality, enum⇄description, model renders |
| Repo-wide | `bash scripts/test-all.sh` | New suites actually execute |

`TMPDIR` is handled by Phase 3.3 rather than hand-typed. `scripts/test-all.sh` green is **not** infra
evidence and `run-registered-suites.sh` green is **not** gate-suite evidence — both required, neither
substitutes.

---

## Risks & Mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | Gate vacuously green (a 35/35 battery hid 7 P1s on 2026-07-27) | SOLE-GUARD/LAYERED + `cmp -s` floors + **independent** vacuity review (AC11, Phase 4.5) |
| R2 | A `-target` typo has no CI net. *(Precisely: the parity test covers **all** managed resources resource→target; the uncovered direction is target→resource — nothing asserts a `-target=` string names a declared address. v1 stated this imprecisely.)* | Requirement-arm presence assertion + three-way set equality |
| R3 | Interlock sentinel too narrow (permanent block) or too broad (self-disarms) | Sentinel is the interpolated `${sentry_dsn}`, so `templatefile` enforces it; behavior asserted against fixtures; release checklist in ADR-149. **Contested — DC-2.** |
| R4 | `depends_on` cycle | Verified independently by two reviewers: no back-edge in either direction |
| R5 | `doppler_config` needs scope the Terraform token lacks | `var.doppler_token_tf` is workplace-scope and already creates `doppler_project` + `doppler_environment` for the registry. /work runs an ADR-130-style scope probe before the first dispatch — a branch config is a distinct API surface from an environment, so capability is *probed*, not assumed. |
| R6 | `terraform test` red from `mock_provider` random computed attributes | No new `hcloud_server_type` assertion planned. If /work adds one, extend `override_data` in `tests/web-hosts-eu-pin.tftest.hcl` **and** verify the override does not *disable* the guard (`-var git_data_server_type=cax11` must still red) |
| R7 | Premature dispatch | Interlock (mechanical) + required reviewer & branch policy (human) + runbook banner (procedural) |
| R8 | ADR-149 ordinal collision | `/ship` re-verifies; a renumber sweeps plan + tasks + ACs, not just the ADR body |

---

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| **(a) Widen `git-data-host-replace`** | **Rejected.** Its `server_replaced` arm *requires* `delete`; its `luks_passphrase_touched` arm fires on **create**. Its 5-member allow-set rests on "preserved by **omission**", an argument that **inverts** on a birth: an omitted address is then a *missing* resource, not a protected one. ADR-145(d) records the same rejection for web. |
| **(b) Keep the untargeted laptop apply** | **Rejected** — the violation this work closes (a plan of that shape carried 9 destroys). |
| **(c) Inline the gate in YAML** | **Rejected on evidence** (P1) — untestable, and fails the parity pairing. *v1 then shipped the interlock inline, contradicting itself; v2 fixes that.* |
| **(d) Ship the route with no interlock, hold by convention** | **Rejected.** A capability held only by prose is held until the first person who reads the runbook and not the plan — and #6982 contains items ADR-115 makes unfixable after birth. |
| **(e) Target the heartbeat too** | **Rejected**, on corrected grounds (P8): the feeder already shipped; what is missing is the monitor + `GIT_DATA_HEARTBEAT_URL`. Creating a monitor this route cannot arm is the #6537 shape. Residual (the probe pings into nothing) recorded in ADR-149; #6548 owns it. |
| **(f) Gate `removeGitDataRepo` on the store flag** | **Rejected — actively harmful.** Would strand a user's PII across a rollback window. |
| **(g) Include `doppler_secret.git_data_ssh_host`** | **Cut** — feasibility regression (would wedge main). **DC-3**, over CPO's advice. |
| **(h) Document `prd_git_data` as a human precondition** | **Rejected** — `doppler_config` exists in the installed provider and `zot-registry.tf` sets the precedent, so the step is automatable and therefore must be automated (`hr-exhaust-all-automated-options-before`). |
| **(i) Isolated `soleur-git-data` Doppler project** (full registry mirror) | **Rejected as scope.** Stronger isolation, but it would re-point the existing LUKS secret + service token and the #5274 cutover runbook. The branch config is the minimal change that removes the human step; revisit with #5274. |
| **(j) Generic gate + per-target config table** | **Rejected for now** — the per-target *predicates* genuinely differ and are not config. Only the shared **preamble** is extracted (Phase 1.1); a retrofit issue covers the rest. |
| **(k) Ship gate+suite now, enum+job in #6982** | **Open — DC-1.** Would delete the interlock entirely, but #6977 would no longer deliver an executable route. Operator's call. |

---

## Sharp Edges

1. **`web-git-data-probe.sh` is double-hashed and NOT in scope.** Editing it — even a comment —
   re-fires `terraform_data.git_data_probe_install`'s SSH provisioner into **web-1** on a per-merge
   step with no destroy-guard, and perturbs `local.host_scripts_content_hash`. Its stale citation
   (line 13 cites **`git-data.tf:270-273`**; the TODO is at **`git-data.tf:348`** — *not* the
   338-341 / 342-345 the brief asserted and v1 repeated) rides with #6982.
2. **Nothing in the git-data boot path fails closed.** The Doppler `runcmd` has no `set -e`, and the
   LUKS block's `set -euo pipefail` is line 1 of the heredoc `doppler run` *executes* — so on a
   missing/wrong-arch binary it never runs. The boot "succeeds" with the volume unmounted. The
   plan-time `lifecycle.precondition` is the only guard that fires; keep it **referenced** or
   `-target` prunes its data source.
3. **`run-registered-suites.sh` will not run these suites** — it derives only
   `apps/web-platform/infra/*.test.sh` from `infra-validation.yml`. Register in `scripts/test-all.sh`,
   which **nothing** lints for orphans (AC12 exists for that reason).
4. **Run `terraform test`, not just `validate`.** `mock_provider` synthesizes a random string for
   computed attributes, so an assertion on `data.hcloud_server_type.*.architecture` fails every run
   block with a message naming a Hetzner anomaly that never happened.
5. **Use `IN(...)` for allow-set membership**, never `contains`/`inside` — they substring-match, so a
   bare `hcloud_volume.git_data` would satisfy `git_data_luks`.
6. **Capture `$?` on the very next line** — any command substitution in between clobbers it.
7. **A green mutation battery is evidence about the battery, not the tests.** Ask of each assertion:
   *what SET does this quantify over, and how many distinct members does the fixture instantiate?*
   Then have **someone else** look for the vacuity you did not imagine.
8. **Cite content anchors, not line numbers** for `.ts`/`.sh` (`cq-cite-content-anchor-not-line-number`).
   This plan's own line citations rotted twice in one review cycle, and Phase 2.6 is about to shift
   `git-data.tf`'s numbering.

---

## References

#6977 · #6982 (interlock release condition) · #6548, #6975, #6976 · #6983 ·
ADR-145 (precedent), ADR-148, ADR-128, ADR-130 (scope probe), ADR-068, ADR-103, ADR-115, ADR-143,
ADR-136, ADR-140 ·
`knowledge-base/project/learnings/2026-07-27-my-battery-was-green-because-it-only-tested-the-two-endpoints-not-the-wire.md` ·
`knowledge-base/project/learnings/2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md` ·
`knowledge-base/engineering/operations/runbooks/web-host-birth.md` (runbook template) ·
`knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md`
