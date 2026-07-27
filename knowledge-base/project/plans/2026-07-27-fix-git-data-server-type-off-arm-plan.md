---
date: 2026-07-27
type: fix
issue: 6570
pr: 6974
branch: feat-git-data-server-type-6570
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-07-27-git-data-server-type-off-arm-brainstorm.md
spec: knowledge-base/project/specs/feat-git-data-server-type-6570/spec.md
---

# fix(6570): git-data server type `cax11` → `cpx22` + dual-arch derivation

## Deepen-Plan Revisions (2026-07-27)

Seven agents ran (the panel `/soleur:plan` skipped, plus targeted research). Two independently
**probed the pinned toolchain** rather than reasoning — that empirical evidence reversed one of my
own cuts. **12 revisions; 5 were P0.**

| # | Finding | Resolution |
|---|---|---|
| **R1** | **`-target=` prunes unreferenced data sources.** Probed: `-target` an unrelated resource → data source never read, exit 0; add a `lifecycle.precondition` edge → it reads. Every git-data dispatch is `-target`ed, so FR6 alone fires on **zero** production paths. v1 said reviewers "may cut FR6b as scope creep" — exactly backwards. | **FR6b promoted to MANDATORY**, folded into FR6. Reverses an earlier cut made on the simplicity reviewer's advice, whose two stated reasons were both falsified. |
| **R2** | **Enum mismatch.** `architecture` **exists** on hcloud v1.63.0 (schema-probed — so v1's "verify or drop" gate is satisfied), but its domain is `x86`/`arm` while `local.git_data_arch` is `amd64`/`arm64`. Compared naively → false on every plan forever, wedging the root. | Explicit mapping in Phase 2 + **AC4b** asserting both literals are present and no direct comparison. |
| **R3** | **"Fails closed at boot" is false, three ways.** The checksum is selected **by** the same derived arch, so a mis-derivation verifies the tarball it just chose and passes; the runcmd has no `set -e`, so a failed `sha256sum` does not stop the next `tar xzf`; the real abort is downstream at the LUKS block. | Observability `failure_modes` rewritten; FR6b named as the **only** mis-derivation detector. |
| **R4** | **The silent escaping direction has zero coverage.** `DOPPLER_SHA256="$${doppler_sha256}"` renders a literal that bash expands to empty — and `validate-infra-templates.sh` **skips any `$${key}` by design**, so the render gate is blind. Both v1 ACs passed. | AC2/AC3 replaced with four **positive, syntax-anchored** greps. |
| **R5** | **`templatefile()` accepts extra keys, hard-errors only on missing ones** (probed). v1's "atomic pair" was half right. | Map keys **moved to Phase 2**; map-first is always green, removing the bisect hazard at no cost. |
| **R6** | **AC1 was green on the unmodified tree** — matched `inngest_server_type`'s `cpx22` at `variables.tf:253`. | Block-scoped `awk`. |
| **R7** | **AC5 was unsatisfiable** — both volumes are PHANTOM rows, so a truthful plan shows CREATE before *and* after. | Rewritten as a **differential** before/after plan-JSON diff. Attachments carved out (they legitimately recreate). |
| **R8** | New suite + registration was disproportionate; `git-data-luks.test.sh` **already** opens this cloud-init, is **already** registered, and carries `assert_mutation`. Separately, four of v1's six assertions were diff-tautologies and the set missed inversion/pairing/escaping entirely — v1 copied `inngest-host.test.sh` **§5** while skipping **§9b**, which measured *"5 of 8 such mutations passed the old fragment guard, including bug #6178 itself."* | No new file. **Four behavioral assertions** appended to the existing suite. |
| **R9** | **AC8 was false on day one and named a non-gate** — 9 pre-existing orphans, and `report_orphans()` is *"Advisory, not a failure"*, returning 0 regardless. | Rewritten to "exits 0, adds no **new** orphan". "Registration is mandatory" corrected. |
| **R10** | **AC13 could not fail** (`echo` exits 0) and missed two bare-filename citations. | Rewritten with `exit 1` and a widened pattern. |
| **R11** | **Checksum provenance argument was circular and half false** — git-data has never booted, and both live hosts are amd64. | Retracted in the reconciliation table; **spec TR3 restored** (verify by `curl … \| sha256sum`). |
| **R12** | **ADR boundary** — git-data is ADR-068's element, not ADR-143's. | Split: ADR-143 gets the correction + pointer; **ADR-068 gets the D1–D10 record**. |

**Two new issues filed** (neither previously tracked):

- **#6977** — git-data has **no birth route**. `git-data-host-replace` hard-aborts on a first CREATE
  (its gate requires `delete`+`create`, and ≥6 unprovisioned deps blow `out_of_scope`), and there is
  no `git-data-host-create` target. The only remaining route is an **untargeted** prod-wide apply
  that runs neither the destroy-guard nor the stock preflight. **v1 asserted this dispatch would
  birth the host — a regression I introduced, since the spec and brainstorm both hedged it.**
- **#6975** — the git-data heartbeat OR-masking defect (filed at brainstorm time).

**Still open, carried into `/work` (not yet folded in):** spec **TR5** (verify `stock-preflight-gate.sh`
reads the new type) was silently dropped and must be restored — it is now the *sole* orderability
guard. **G5's sweep is under-scoped**: stale `cax11` claims also survive at
`apply-web-platform-infra.yml:2393` (a CI error string that becomes wrong on both clauses),
`knowledge-base/operations/expenses.md:19`, and `knowledge-base/legal/article-30-register.md:69` (the Art. 30 register records Phase-6 replication
as blocked on the `cax11` pin). Two chain omissions also need spec entries: minted `GIT_*_SSH_PRIVATE_KEY`
never reach the running web container (their `doppler_secret`s are dependents, outside the `-target`
set), and `git-data-cutover.sh`'s `WEB_HOSTS` is hardcoded single-host on a now-false "web-2 retired"
comment.

## Overview

`apps/web-platform/infra/git-data.tf:120` pins `soleur-git-data` to `var.git_data_server_type`
(default `cax11`, ARM64/Ampere). The entire Hetzner `cax` line is orderable in **0 of 3** EU
datacenters, so the host cannot be born on its declared type — and never has been.

This is an **IaC-only** change: flip the default to `cpx22`, derive the host architecture from the
type prefix instead of hardcoding it, add a plan-time type tripwire, update the expense ledger, and
record an ADR-143 addendum. **No host is born here** (NG1) — the birth remains a gated
`workflow_dispatch`.

Decisions D1–D10 are settled in the brainstorm. This plan implements them; it does not re-derive
them.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| "Tests likely touched: `terraform-target-parity.test.ts`" | It enumerates `terraform_data.*` **SSH-provisioned** resources (`MIN_SSH_PROVISIONED = 10`) and `-target=` allow-lists. A `data "hcloud_server_type"` is neither a `terraform_data` resource nor `-target`-able. | **Scope reduction — not edited.** Removed from Files to Edit. |
| "`cloud-init-user-data-size.test.ts` carries a `git_data_volume_id` fixture" | True (`SECRET_LENGTHS` line 142). New template vars are unmodeled and fall through `DEFAULT_REF_LEN = 80`. Budget is `GIT_DATA_BUDGET = 28_000` / `GIT_DATA_FLOOR = 10_000` vs a current ~21.9 KB render. | **Re-run required, edit optional.** +~96 modeled bytes against ~6 KB headroom. Exact entries added for accuracy (FR10). |
| "Mirror the `local.registry_arch` / `local.inngest_arch` pattern" | Stronger than a pattern: **`cloud-init-inngest.yml` is a line-for-line template.** `:192` `DOPPLER_SHA256="${doppler_sha256}"`, `:193` `..._linux_${doppler_arch}.tar.gz`, fed by `inngest-host.tf:286-287`. | Copy the inngest template shape verbatim, including the `doppler_arch` / `doppler_sha256` var names. |
| "Reuse the per-arch sha256 pair at `inngest-host.tf:66`" | The pair appears **three** times: `inngest-host.tf:66`, `zot-registry.tf:86`, and git-data's own hardcoded arm64 literal at `cloud-init-git-data.yml:128` — all byte-identical, all pinned to Doppler `3.75.3`. | Reuse verbatim, but **v1's provenance argument was unsound and is retracted (R11)**. It claimed the arm64 half was "proven by git-data's own current literal" — git-data has **never booted**, which is this plan's founding premise, so an unexecuted literal proves nothing; byte-identity proves shared *provenance*, not correctness. It also claimed "two live hosts" prove the pair — but registry is `cx23` and inngest is `cpx22`, **both amd64**, so only the amd64 half has live evidence. That happens to be the half git-data will use, so the outcome is fine and the reasoning was not. **Restore spec TR3**: verify the amd64 checksum with one command (`curl -sL …_linux_amd64.tar.gz \| sha256sum`) rather than arguing from precedent. |
| (not in spec) | **`inngest-host.test.sh` §5 is a dual-arch guard precedent**, registered at `infra-validation.yml:700`. Five `git-data-*.test.sh` suites exist; **no `git-data-host.test.sh`**. | **New deliverable:** create + register `git-data-host.test.sh` (FR11, Phase 1 — TDD RED). |
| (not in spec) | **ADR-143's closing paragraph asserts** *"`var.registry_server_type` and `var.git_data_server_type` keep their unorderable defaults."* This PR falsifies half of it. | The addendum must **amend** that sentence, not merely append — otherwise the ADR contradicts itself (FR9). |
| (not in spec) | C4: **no git-data element exists**, and **no `cax11`/ARM/Ampere claim appears in any `.c4` file** (the only `arm64` hit is the inngest→Better Stack Vector edge, `model.c4:433`). | **No C4 edit.** Enumeration cited in §Architecture Decision. |
| TR7 rebase risk | `git diff HEAD...origin/main` on all four target files: **empty**. `origin/main` = `f0df12daf`. | No rebase needed now; re-check immediately before editing `variables.tf`. |

## User-Brand Impact

Carried forward from the brainstorm (unchanged).

- **If this lands broken, the user experiences:** nothing immediately — the host is unborn and
  `GIT_DATA_STORE_ENABLED` is absent from Doppler `prd`, so no user request touches this path today.
  The damage is deferred and lands at the birth: a host that boots on the wrong architecture fails
  its Doppler CLI install, never obtains `GIT_DATA_LUKS_KEY`, and cannot open the LUKS volume — the
  bare-repo store is then absent when ADR-068 Phase-3 finally routes workspace git history to it.
- **If this leaks, the user's data is exposed via:** not a new exposure surface. The LUKS
  passphrase resources are explicitly out of scope (TR2), and the passphrase is never in `user_data`
  — it arrives only as a Doppler-injected env at boot. The relevant risk is **loss, not leak**:
  git-data stores per-workspace bare repos, and ADR-068 §(d) records that git-data is authoritative
  for the most-recent per-user worktree tip (a fresh GitHub clone "can be strictly behind").
- **Brand-survival threshold:** `single-user incident`.

CPO sign-off is carried forward from the brainstorm's cross-domain framing; `user-impact-reviewer`
runs at PR review.

## Implementation Phases

Phase order is **load-bearing**: the contract (variables + locals) must land before its consumer
(the cloud-init template + templatefile map), or Phase 3 references locals that do not yet exist.

### Phase 0 — Preconditions (no edits)

1. `git fetch origin main` and re-confirm zero drift on `variables.tf`, `git-data.tf`,
   `cloud-init-git-data.yml`, `knowledge-base/operations/expenses.md` (TR7).
2. Confirm the three Doppler checksum sites still agree and all pin `3.75.3`:
   `grep -n 'doppler_sha256\|DOPPLER_VERSION' apps/web-platform/infra/{zot-registry.tf,inngest-host.tf,cloud-init-*.yml}`
3. **Confirm `hcloud_server.git_data` is absent from Terraform state.** The plan asserts
   `terraform plan` shows a `CREATE` (AC5). Because the resource deliberately omits
   `lifecycle.ignore_changes = [user_data]` (`git-data.tf:182-185`), any edit to
   `cloud-init-git-data.yml` re-renders `user_data` — so if the resource *were* in state, the plan
   would show `delete → create`, not `create`, and AC5's wording would be wrong. The host has never
   been born and is an `OPERATOR_APPLIED_EXCLUSION`, so absence is expected — verify, don't assume.

*(Former step 3 — verifying the `architecture` attribute for FR6b — is removed with FR6b. Former
step 4, an informational stock re-probe, is removed: `stock-preflight-gate.sh` re-probes for real at
dispatch, so a plan-time reading is decoration.)*

### Phase 1 — RED: two anti-regression assertions (`cq-write-failing-tests-before`)

**Revised at deepen time — no new suite.** Append ~8 lines to the existing
`apps/web-platform/infra/git-data-luks.test.sh`, which already defines
`CLOUD_INIT="${DIR}/cloud-init-git-data.yml"` (`:26`), is already registered at
`.github/workflows/infra-validation.yml:748`, and already carries `assert_holds` /
`assert_mutation` helpers (`:172-173`) — the mutation arm makes an assertion non-vacuous, which a
bare grep cannot. Zero new file, zero registration edit, zero orphan surface.

**The v1 assertion set was both too weak and too large, and is replaced.** v1 copied `inngest-host.test.sh` **§5** (bare-fragment `grep -qF`) while skipping **§9b**, which exists in the same file to say why §5 is inadequate — verbatim: *"it certifies that a substring exists SOMEWHERE in a ~500-line YAML, so it stays green while the live regex is mutated into a no-op … **Measured: 5 of 8 such mutations passed the old fragment guard, including bug #6178 itself.**"* Copying the weak half of a precedent that documents its own weakness reproduces the measured failure.

Concretely, v1's assertions all pass against an **inverted ternary**:

```hcl
git_data_arch = startswith(var.git_data_server_type, "cax") ? "amd64" : "arm64"   # INVERTED
```

which ships `cpx22 → arm64`, fails `sha256sum -c -` at boot, and produces exactly the failure this PR exists to prevent.

**Four behavioral assertions replace the six textual ones.** Use the host suite's existing
`assert_holds` / `assert_mutation` pair (`git-data-luks.test.sh:172-173`) — the mutation arm is what
makes an assertion non-vacuous, satisfying `cq-assert-anchor-not-bare-token`.

| # | Assertion | Catches |
|---|---|---|
| A1 | **Escaping guard**, verbatim from `inngest-host.test.sh:177`: `grep -qF 'doppler_$${DOPPLER_VERSION}_linux_${doppler_arch}.tar.gz'` | The plan's own declared top risk — which v1 assigned **zero** assertions |
| A2 | **Cross-file checksum parity** — derive canon from `inngest-host.tf:66` and `zot-registry.tf:86` rather than hardcoding a second literal (the `CANON_WEB_HOSTS` idiom, `inngest-host.test.sh:135-145`); assert git-data's arm64 arm byte-equals theirs, same for amd64 | Checksum↔arch **pairing swap**, and pins each literal to its arm |
| A3 | **Derivation orientation** — extract the ternary's own bytes and replay over `{cax11→arm64, cpx22→amd64, cx23→amd64, ccx13→amd64}`, with §9b's non-vacuity guard (a failed extraction must fail loudly, never silently pass every case) | The inverted ternary above |
| A4 | **Default is not `cax*`** — assert `git_data_server_type`'s default does not start with `cax`, citing the 0-of-3-DC probe | #6570 itself silently regressing. `stock-preflight-gate.sh` covers the live case at dispatch; this covers the **source** case at PR |

**Cut from v1 as diff-tautologies or already-covered:** "locals are declared", "both checksums are
declared", "a `validation` block exists" (each can only fail if someone rewrites the code they just
wrote; `terraform validate` covers malformed HCL), and "the templatefile map passes both vars"
(already enforced by `.github/scripts/validate-infra-templates.sh`, which discovers templates
structurally from `templatefile()` call sites and renders them — a missing map key fails there at
exit 2).

Also **cut the absence-form assertions** (`no linux_arm64`, `no 64-hex literal`): Phase 3.1 rewrites
the very comment containing `linux_arm64`, so an absence grep either spuriously fails on prose or,
once comment-stripped, hides a real hardcode in a commented-out line. A1's positive, syntax-anchored
form is strictly better.

**Use `set -uo pipefail` with a pass/fail counter, not `set -e`** — under `set -e` the first failing
grep aborts and RED reports 1 failure instead of 4, losing the confirmation that every assertion is
genuinely wired (`inngest-host.test.sh:16`).

### Phase 2 — GREEN part 1: the contract

`apps/web-platform/infra/variables.tf`:

- `git_data_server_type` default `cax11` → **`cpx22`** (FR1).
- Rewrite the `description` (shape 2 vCPU x86 / 4 GB; arch is DERIVED from this value; `cpx22` is
  stock-forced, not a sizing decision).
- Add the `validation` block rejecting a prefix outside `^(cax|cpx|cx|ccx)` (FR5), mirroring
  `inngest_server_type:260`.

`apps/web-platform/infra/git-data.tf`:

- Extend the existing `locals` block (`:69-77`) with `git_data_arch` and
  `git_data_doppler_sha256` (FR2, FR3), copying the `inngest-host.tf:57-66` comment shape.
- Add `data "hcloud_server_type" "git_data" { name = var.git_data_server_type }` (FR6), mirroring
  `zot-registry.tf:134`.
- **Add the FR6b `lifecycle.precondition` on `hcloud_server.git_data` — MANDATORY, not optional
  (R1).** Empirically probed: an *unreferenced* data source is **pruned by `-target=`**, and every
  git-data dispatch is `-target`ed, so FR6 without a referent fires on zero production paths. The
  precondition is what creates the surviving graph edge. **Map the enums explicitly** — the
  provider emits `x86`/`arm`, not `amd64`/`arm64`:

  ```hcl
  lifecycle {
    precondition {
      condition = data.hcloud_server_type.git_data.architecture ==
        (local.git_data_arch == "arm64" ? "arm" : "x86")
      error_message = "git_data_server_type=${var.git_data_server_type} derives ${local.git_data_arch}, but Hetzner reports architecture=${data.hcloud_server_type.git_data.architecture} (enum: x86|arm). The Doppler download would be wrong-arch."
    }
  }
  ```

  A naive `local.git_data_arch == ...architecture` is `"amd64" == "x86"` → **false on every plan
  forever**, wedging the whole root. This is the single highest-risk line in the PR.

- **Move the two templatefile map keys here** (`doppler_arch`, `doppler_sha256`) rather than
  Phase 3 (R5). `templatefile()` accepts **extra** map keys and hard-errors only on **missing**
  ones — verified — so map-first is always green and template-first is the order that breaks.
  Moving them up removes the bisect hazard at no cost, since Phase 2 already edits this file.
- Rewrite the void inline comment at `:120` (FR7).

### Phase 3 — GREEN part 2: the consumer

With the map keys already in place from Phase 2, this phase is template-only and every
intermediate commit stays green.

`apps/web-platform/infra/cloud-init-git-data.yml` (`:120-130`):

- Header comment: `Doppler CLI (arm64)` → arch-derived wording.
- `DOPPLER_SHA256="${doppler_sha256}"` (replacing the hardcoded literal).
- URL `..._linux_${doppler_arch}.tar.gz` (replacing `linux_arm64`).
- Keep `$${DOPPLER_VERSION}` double-`$` escaped — it is a **shell** variable, not a Terraform one.
  Getting this wrong is the single most likely mechanical error in this PR.

`apps/web-platform/infra/git-data.tf` templatefile map: add `doppler_arch = local.git_data_arch`
and `doppler_sha256 = local.git_data_doppler_sha256`.

Phase 1's suite should now go GREEN.

### Phase 4 — Ledger

`knowledge-base/operations/expenses.md` row 19 (FR8). **Larger than a type + amount swap** — the
row's prose carries four separate now-false or stale claims, all verified at deepen time:

| Claim in row 19 | Status | Fix |
|---|---|---|
| Title `Hetzner CAX11 (git-data)`, amount `4.10`, `2 vCPU ARM64/Ampere` | Superseded by D1 | → `CPX22`, `~21.05` USD (EUR 19.49 × ~1.08 FX), `2 vCPU AMD x86 / 4 GB` |
| *"cannot be born today at ANY account cap"* | **False** — conflates type-unorderability with the cap, and the cap premise is the stale `5` the brainstorm corrected (live limit is 10 with 5 running) | Drop the cap clause; the blocker was the **type**, which this PR fixes |
| `git_data_server_type = cax11` **(variables.tf:113)** | Stale line citation — the variable is now at `variables.tf:172` | Re-anchor, or cite by content per `cq-cite-content-anchor-not-line-number` |
| *"Also blocked by #6416 and ADR-115's `luksOpen`"* | **#6416 is CLOSED** (`infra: web-2 missing private-net IP → zot mirror push unreachable`) | Drop #6416; re-verify the ADR-115 `luksOpen` half before restating it |

Status **stays** `approved-not-billing` — the host is still unborn. Keep the PHANTOM-ROW note (still
accurate) and carry the identical-net-vs-gross caveat the web-2 row uses.

### Phase 4b — G5 sweep: the voided `cax11` rationale outside the three obvious files (R13)

v1 covered three of six sites. The remaining three all survive the change and all mislead:

1. **`.github/workflows/apply-web-platform-infra.yml:2393`** — a hardcoded CI error string:
   *"cax11 has had no EU stock, so it cannot be born at any account cap."* After this PR it is wrong
   on **both** clauses (the type is `cpx22`; the account-cap framing is the stale `5`). It fires on
   the **exact path an operator will be debugging a failed birth**, which makes it the worst of the
   three. `:2373` carries a matching comment.
2. **`knowledge-base/operations/expenses.md:19`** — covered by Phase 4's table.
3. **`knowledge-base/legal/article-30-register.md:69`** — the GDPR Art. 30 register records Phase-6
   replication as *"externally blocked on shared git-data (#6570, git-data pinned to an unorderable
   `cax11` ARM type)."* **Two** stale claims in one row: the `cax11` pin (this PR), and web-2
   described as **`cx23`** (repinned to `cpx22` by #6966/#6967 — pre-existing drift this PR is
   merely standing next to). Correct the `cax11` clause; flag the `cx23` one.

Touching the Art. 30 register is a regulated-data surface (`hr-gdpr-gate-on-regulated-data-surfaces`),
but this is a **factual correction to a row explicitly marked DRAFTED / NOT-YET-ACTIVE** with no
present-tense processing asserted — no lawful-basis or transfer analysis changes. Note it in the PR
body rather than escalating.

### Phase 5 — ADR record (split across two ADRs, R12)

v1 put everything in ADR-143. That is **half right**, and the split matters:

- **ADR-143 gets the correction only.** Amend its closing "Not changed by this addendum" paragraph,
  which asserts `var.git_data_server_type` keeps its unorderable default — this PR falsifies it, and
  leaving it ships a self-contradictory ADR. Add a one-line forward pointer.
- **ADR-068 gets the D1–D10 decision record.** ADR-143 is scoped to *active-active web ingress and
  drain-gated host lifecycle*; **git-data is ADR-068's element**. Someone reading ADR-068 for the
  git-data host shape would not find the type decision, the dual-arch derivation, or D10's
  born-on-LUKS rejection — which is squarely an ADR-068 topology question, not a web-ingress one.
  v1 over-read its source: ADR-143:149 says the move is *"its own work"* and its tail says *"#6570
  owns that decision"* — both assign **ownership**, neither prescribes a **filing location**, and
  "its own work" reads closer to *not here*. The #6966 precedent does not transfer, because web-2
  **is** ADR-143's subject.

Still no new ordinal (D8, TR8) — both are addenda. If that is ever revisited into a standalone ADR,
re-derive the next free number from a freshly-fetched `origin/main` (highest is currently ADR-147).

### Phase 6 — Verification

**Spec TR3 and TR5 are restored here (R14).** Both exist in the spec but v1 gave neither a phase
step nor an AC, so both would have been silently dropped:

- **TR3** — verify the amd64 checksum against the real artifact, one command, no precedent-argument
  (this is R11's replacement for the retracted provenance claim):
  `curl -sL https://github.com/DopplerHQ/cli/releases/download/3.75.3/doppler_3.75.3_linux_amd64.tar.gz | sha256sum`
  → must equal `9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db`.
- **TR5** — confirm `tests/scripts/lib/stock-preflight-gate.sh` reads the **new** type and that no
  test encodes today's availability (`cq-test-fixtures-synthesized-only`). Load-bearing after R1/R3:
  with FR6 catching only *phantom* types, this gate is now the **sole** orderability guard.


1. `cd apps/web-platform/infra && terraform init -input=false && terraform validate`
2. `terraform plan` — assert **no diff** on `hcloud_volume.git_data*`, `random_password.git_data_luks`,
   `doppler_secret.git_data_luks_key` (TR2). The `hcloud_server.git_data` CREATE is expected and
   **not applied** (NG1).
3. `bash apps/web-platform/infra/git-data-host.test.sh` — GREEN.
4. `./node_modules/.bin/vitest run test/...` for `cloud-init-user-data-size.test.ts` (size budget).
5. `bash apps/web-platform/infra/run-registered-suites.sh` — the authoritative infra gate (~25 min),
   confirms zero orphans (TR6).
6. `bash scripts/test-all.sh`.

## Files to Edit

- `apps/web-platform/infra/variables.tf` — FR1, FR5 *(fetch `origin/main` first, TR7)*
- `apps/web-platform/infra/git-data.tf` — FR2, FR3, FR6, FR6b, FR7 + templatefile map
- `apps/web-platform/infra/cloud-init-git-data.yml` — FR4
- `.github/workflows/infra-validation.yml` — register the new suite (FR11)
- `knowledge-base/operations/expenses.md` — FR8
- `knowledge-base/engineering/architecture/decisions/ADR-143-active-active-web-ingress-drain-gated-host-lifecycle.md` — FR9
- `.github/workflows/apply-web-platform-infra.yml` — FR12 (G5 sweep: the `:2393` CI error string
  + the `:2373` comment)
- `knowledge-base/legal/article-30-register.md` — FR13 (G5 sweep: the `:69` `cax11` clause)
- `apps/web-platform/infra/git-data-luks.test.sh` — FR11 (four behavioral assertions, R8)

**FR10 dropped (R15):** the optional `SECRET_LENGTHS` entries in
`plugins/soleur/test/cloud-init-user-data-size.test.ts`. `DEFAULT_REF_LEN = 80` over-models the two
new args (5 + 64 actual) by ~91 bytes — conservative, against ~6 KB headroom between
`GIT_DATA_FLOOR` and `GIT_DATA_BUDGET`. v1 marked it "optional" and gave it no task, which is how a
requirement silently evaporates; dropping it explicitly is the honest version. The test still runs
in Phase 6.

## Files to Create

- `apps/web-platform/infra/git-data-host.test.sh` — FR11

**Explicitly NOT edited:** `plugins/soleur/test/terraform-target-parity.test.ts` (see Research
Reconciliation), `git-data-luks.tf`, `git-data-cutover.sh`, any volume or LUKS resource (D10, TR2).

## Acceptance Criteria

### Pre-merge (PR)

**Every AC below was run against the UNMODIFIED tree during deepen. Any AC that passed there is not
an acceptance criterion — three did, and are rewritten.**

- **AC1** — *(rewritten, R6 — the v1 form was green on the unmodified tree: `grep -c 'default *=
  *"cpx22"' variables.tf` returns 1, matching `inngest_server_type` at `variables.tf:253`. The
  "within the `git_data_server_type` block" qualifier was prose the command did not express.)*
  Block-scope it:
  ```bash
  awk '/^variable "git_data_server_type"/{i=1} i&&/^[[:space:]]*default[[:space:]]*=/{gsub(/[",]/,"");print $NF;exit} i&&/^}/{exit}' \
    apps/web-platform/infra/variables.tf
  ```
  asserted `== cpx22`.
- **AC2/AC3** — *(rewritten, R4 — v1 used negative token-absence greps, which are both fragile and
  blind.)* Fragile: Phase 3.1 rewrites the very comment containing `linux_arm64`. Blind: the
  **silent** escaping error `DOPPLER_SHA256="$${doppler_sha256}"` (double-`$` on the *Terraform*
  var) renders a literal that bash expands to empty, and **both v1 ACs pass** — as does
  `validate-infra-templates.sh`, which by design skips any key the source escapes as `$${key}`.
  Replace with positive, syntax-anchored counts, all `== 1` unless noted:
  ```
  grep -cF 'DOPPLER_SHA256="${doppler_sha256}"'   cloud-init-git-data.yml
  grep -cF '_linux_${doppler_arch}.tar.gz'        cloud-init-git-data.yml
  grep -cF 'echo "$${DOPPLER_SHA256}'             cloud-init-git-data.yml
  grep -cF '$${DOPPLER_VERSION}'                  cloud-init-git-data.yml   # >= 2
  ```
- **AC4** — the templatefile map passes both keys, anchored on the **assignment**, not a bare token
  (`cq-assert-anchor-not-bare-token`):
  `grep -cE '^[[:space:]]*doppler_arch[[:space:]]*=[[:space:]]*local\.git_data_arch$'` == 1, same
  shape for `doppler_sha256`.
- **AC4b** — the FR6b precondition contains **both** `"arm"` and `"x86"` literals and does **not**
  compare `architecture` directly against `local.git_data_arch`. This is the highest-value
  structural assertion in the PR (R1/R2).
> **AC5/AC6 are credentialed live-prod reads, and v1 did not say so.** This root has **26
> no-default variables** plus an R2 backend, so a bare `terraform plan` fails immediately. The
> repo's own shape is
> `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan …` plus
> `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` exported for the backend. Running it locally holds
> `HCLOUD_TOKEN` — which the workflow describes as carrying *"destroy authority over the whole
> prod fleet"* — and contends for R2 state (`main.tf` sets `use_lockfile = false`; the GH Actions
> concurrency group is the sole serializer). Plan-only is read-only, so this is safe, but it is an
> operator-credentialed step, not a local unit check.

- **AC5** — *(rewritten, R7 — v1 was unsatisfiable.)* Both volumes are **PHANTOM rows, never
  provisioned**, so a truthful plan shows `CREATE` on them before *and* after this PR; "no change"
  can never hold. The invariant TR2 actually wants is **differential**: capture
  `terraform show -json` for a plan before and after the diff, and assert the two are **identical**
  on `hcloud_volume.git_data`, `hcloud_volume.git_data_luks`, `random_password.git_data_luks`,
  `doppler_secret.git_data_luks_key`. Note the two `hcloud_volume_attachment.*` legitimately DO
  change (`server_id` ForceNew) and are inside the replace gate's allow-set — do not assert
  no-change on them.
- **AC6** — a nonexistent type fails at **plan**, not after a destroy. Assert on the **error text**
  (`hcloud_server_type` / "not found"), never on exit status alone — a bare plan aborts on provider
  auth long before any data source is read, so exit-status-only "proves" nothing. Three arms:
  - **AC6a (tripwire)** `TF_VAR_git_data_server_type=cpx99` → stderr matches `/cpx99/` and `/not found/`
  - **AC6b (validation)** `TF_VAR_git_data_server_type=zz11` → stderr matches FR5's `error_message`
  - **AC6c (positive control)** `TF_VAR_git_data_server_type=cpx22` → succeeds past the data-source read
  AC6c is load-bearing: without it you cannot distinguish "tripwire fired" from "plan never got
  there". **Note which FR each arm pins:** `cx99`/`cpx99` passes FR5's `^(cax|cpx|cx|ccx)` regex, so
  AC6a exercises **FR6**, not FR5 — and only because FR6b gives it a referent (R1).
- **AC7** — *(rewritten)* `bash apps/web-platform/infra/git-data-luks.test.sh` exits 0 with the four
  new assertions. No new suite, no registration edit (R8).
- **AC8** — *(rewritten, R9 — v1 was false on day one and named a non-gate.)* `run-registered-suites.sh`
  reports **9 pre-existing orphans** on this tree, and `report_orphans()` is explicitly *"Advisory,
  not a failure"* — it returns 0 regardless. Assert instead: the run **exits 0** and adds **no new**
  orphan versus the `origin/main` baseline. The v1 plan's "Registration is mandatory —
  `run-registered-suites.sh` … reports unregistered suites as orphans" implied an enforcement that
  does not exist; registration still matters (an unregistered suite never runs) but nothing fails
  the build over it.
- **AC9** — `cloud-init-user-data-size.test.ts` passes: render `< GIT_DATA_BUDGET (28_000)` and
  `> GIT_DATA_FLOOR (10_000)`.
- **AC10** — expenses row 19 reads CPX22 / ~21.05 / `approved-not-billing`, with a `verify_by` marker,
  **and** all four stale claims in Phase 4's table are corrected:
  `grep -c 'CAX11\|ANY account cap\|variables.tf:113\|#6416' <row 19>` == 0.
- **AC11** — ADR-143 carries a dated addendum recording D1–D10, **and** its "Not changed by this
  addendum" paragraph no longer claims `git_data_server_type` keeps an unorderable default.
- **AC12** — PR body carries the brainstorm's Premise Corrections table (the falsified account-cap
  and freed-slot claims), so the stale framing is not re-imported downstream.
- **AC13** — *(rewritten, R10 — v1 could not fail.)* `echo` succeeds, so `bash -c` and `xargs` both
  exit 0 with a broken path present: it was an advisory print dressed as a gate. It also missed the
  two **bare-filename** `encryption-posture-audit-2026-07-23.md` citations, which carry no
  `knowledge-base/` prefix. Fix both:
  ```bash
  grep -oE '(knowledge-base/)?[A-Za-z0-9/_.-]+\.md' <plan> | sort -u | while read -r f; do
    [[ -f "$f" || -f "knowledge-base/engineering/architecture/$f" ]] || { echo "BROKEN: $f"; exit 1; }
  done
  ```

### Post-merge (operator)

None. The birth is a separate gated `workflow_dispatch` tracked by the downstream chain in the spec
— it is deliberately **not** an acceptance criterion of this PR.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/variables.tf` (default + validation), `git-data.tf` (2 locals, 1 data
source, 2 templatefile args, 1 comment), `cloud-init-git-data.yml` (2 interpolations). Provider
`hetznercloud/hcloud` v1.63.0 (`~> 1.49`). **No new variable, no new secret, no new
`TF_VAR_*`** — so `hr-tf-variable-no-operator-mint-default` does not fire and there is no
merge-blocking Doppler provisioning precondition.

### Apply path

**None in this PR.** git-data resources are `OPERATOR_APPLIED_EXCLUSIONS` (ADR-103) and excluded
from the per-PR `-target=` list, so the merge-triggered auto-apply does not touch them. Expected
downtime: zero (the host does not exist).

**CORRECTION (deepen, R2).** The v1 plan asserted the change "takes effect at the next
`apply_target=git-data-host-replace` dispatch or at first birth." **That is false, and the
assertion was a regression I introduced** — the spec and brainstorm both hedged it
(*"verify that path rather than assume it"*), and v1 promoted the hedge to a fact.

`git-data-host-replace` **cannot birth an unborn host**, for two independent reasons, neither
bypassable (the gate carries no `[ack-destroy]`):

1. Its gate counts `server_replaced` as `actions ⊇ {delete, create}`. A first birth is
   `["create"]` only → `server_replaced == 0` → **abort**.
2. `out_of_scope` must be `0` over a 5-member allow-set, but the host's dependencies
   (`hcloud_volume.git_data`, `git_data_luks`, the three `tls_private_key`s,
   `doppler_service_token.git_data`, `hcloud_firewall.git_data`) have *also* never been
   provisioned → `out_of_scope ≥ 6` → **abort before the stock preflight is reached**.

And there is no `git-data-host-create` in the `apply_target` enum — only `web-host-create`
(#6730/ADR-145).

<!-- lint-infra-ignore start -->
<!-- DESCRIPTIVE, not prescriptive: this sentence records what the only remaining route WOULD be
     in order to argue that it is NOT a route and must not be taken. The single imperative in the
     surrounding paragraph is a negation ("nothing in it makes the host bornable"), and #6977 was
     filed precisely so that no human runs this. Same posture as ADR-115's authority note. -->
**The only remaining route is an operator-local untargeted `terraform apply` across the whole prod
root**, which runs neither the destroy-guard nor the stock preflight — and a plan taken 2026-07-27
showed that apply carrying **9 destroys**. It is named here to be refused, not followed.
<!-- lint-infra-ignore end -->

**Filed as #6977** (additive birth path, mirroring `web-host-create`'s inverted gate), which now
sits in the downstream chain between this repin and the birth. This PR still merges safely — it
changes declared state only — but nothing in it makes the host bornable, and the plan must not
imply otherwise.

### Distinctness / drift safeguards

No `dev`/`prd` divergence (single infra root). No `lifecycle.ignore_changes` added — git-data
deliberately omits it (`git-data.tf:185`) to preserve a clean replace-to-reprovision path. The new
`data` source is read-only and creates nothing.

### Vendor-tier reality check

`cpx22` is a standard shared-vCPU type, no tier gate. Account limit is 10 servers with 5 running —
five free slots, so the additive birth has headroom (contra the issue's stale "cap is 5").

## Downtime & Cutover

Evaluated because deepen-plan Phase 4.55's infra trigger names a `server_type` change explicitly.
**The gate does not fire, and the reason is worth recording so a reviewer does not re-raise it.**

The trigger is *"a change to a **running** host that the provider applies via power-off or replace."*
`soleur-git-data` is not running — `GET /v1/servers` returns five hosts and none is git-data
(verified 2026-07-26T22:07Z). There is no serving surface to take offline, no drain to sequence, and
no in-flight request to lose.

Reinforcing this: git-data resources are `OPERATOR_APPLIED_EXCLUSIONS` (ADR-103) and excluded from
the per-PR `-target=` list, so the merge-triggered auto-apply cannot touch them even in principle;
and NG1 means this PR performs no apply at all. The `server_type` value changes only in *declared*
state.

**Zero-downtime is therefore structural, not a mitigation** — the first apply of this value is a
birth (`CREATE`), not a replace. The blue-green question arises at the *future* birth and is
governed by the downstream chain in the spec, not here.

## Observability

This PR changes no runtime error path — the affected host does not exist. The declaration below is
the honest current state, not a new instrumentation surface.

```yaml
liveness_signal:
  what: betteruptime_heartbeat.git_data_prd — DECLARED ONLY, NOT armed
  live_verification: ABSENT from Better Stack (live GET /api/v2/heartbeats, 2026-07-27:
    7 heartbeats returned, none is soleur-git-data-prd — not paused, nonexistent).
    Source declares paused=true with ignore_changes=[paused], and the arm_one call in
    apply-web-platform-infra.yml no-ops because the address is not in tfstate (#6548).
  cadence: 60s expected / 180s grace — DESIGNED values; nothing emits a beat today
  alert_target: Better Stack (once #6548 arms it)
  configured_in: apps/web-platform/infra/git-data.tf + apply-web-platform-infra.yml
error_reporting:
  destination: NONE off-host. This corrects the claim that stood here: `sha256sum -c -` does
    NOT abort the Doppler install (that runcmd item carries no `set -e`), and the LUKS block's
    `set -euo pipefail` is inside the heredoc `doppler run` executes, so a missing or wrong-arch
    binary never reaches it. A failed boot exits non-zero inside cloud-init and leaves NO signal
    off the host. git-data-bootstrap.sh does fail loud on an unmet invariant — but on-host only.
  fail_loud: false
failure_modes:
  - mode: wrong-arch Doppler binary selected (the defect this PR structurally prevents)
    detection: FR6b lifecycle.precondition at PLAN time — the ONLY mechanism that catches this.
      NOT the checksum -- see R3, the checksum is selected BY the same derived arch, so it
      verifies the tarball it just chose and passes. Residual runtime symptom is
      "Exec format error" at `doppler run`, on a deny-all host whose heartbeat does not exist
      at all (#6548) and which ships no logs off-box.
    residual_layer: NONE — off-keyboard until #6548 arms the beat and a log shipper lands.
    alert_route: terraform plan fails before apply
  - mode: phantom / nonexistent server type (the cx32-class destroy-before-fail)
    detection: data.hcloud_server_type.git_data catalog lookup at plan (FR6) -- live ONLY
      because FR6b references it; unreferenced it is pruned by -target (R1)
    alert_route: apply aborts before any destroy
  - mode: declared type left the ORDERABLE set (distinct from phantom -- cax11 resolves fine
      in the catalog, so FR6 would never have caught this PR's own defect)
    detection: stock-preflight-gate.sh reads .change.after.server_type from the plan JSON, so it
      picks up cpx22 with no edit. UNREACHABLE ON A BIRTH TODAY: the destroy-guard runs earlier in
      the same step and hard-aborts a pure CREATE, so the preflight below it never executes
      (#6977). It is live on the REPLACE path only, and arms for births once #6977 lands.
    alert_route: apply aborts before any destroy (replace path)
logs:
  where: NONE. cloud-init-git-data.yml installs no log shipper — measured 0 occurrences of
    vector/betterstack/journald, against 31/11/5 in cloud-init-inngest.yml and 14/2/7 in
    cloud-init.yml. Boot failures are readable only in on-host /var/log/cloud-init-output.log,
    over the private net, on a deny-all-public-ingress host. Tracked as a birth blocker.
  retention: n/a
discoverability_test:
  command: cd apps/web-platform/infra && doppler run -p soleur -c prd_terraform
    --name-transformer tf-var -- terraform plan -target=hcloud_server.git_data -no-color
  expected_output: hcloud_server.git_data planned with server_type = "cpx22"
```


**Known gaps, tracked not fixed here:** #6975 (the git-data heartbeat key is unsuffixed, so a
healthy web-1 probe masks a dead web-2 path) and #6548 (`git_data_prd` never unpaused, absent from
live Better Stack). Both gate the **birth**, not this repin. Per §2.9.2 the git-data host is a blind
surface; #6975 is precisely the in-surface discriminating probe that gap calls for.

## Encryption Posture

No store and no cross-component connection is introduced; both volumes are untouched (TR2). Posture
is restated for continuity because the file-pattern trigger fires.

```yaml
at_rest:
  - store: hcloud_volume.git_data_luks
    mechanism: guest-side LUKS2 (cryptsetup, not an hcloud attribute)
    evidence: cloud-init-git-data.yml:159-170; encryption-posture-audit-2026-07-23.md:35 "conforming"
    defends_against: disk seizure / vendor-side media access at rest
    does_not_defend: a live host with the mapper open; anyone holding GIT_DATA_LUKS_KEY
    disclosed_as: encryption-at-rest for user git-data (ADR-068 §3.D, NFR-027)
    live_verification: unmeasured — the host has never existed
  - store: hcloud_volume.git_data (plaintext ext4)
    mechanism: plaintext-exception
    evidence: encryption-posture-audit-2026-07-23.md:37
    defends_against: nothing
    does_not_defend: any at-rest threat
    disclosed_as: cutover source / rollback backstop
    live_verification: n/a — never provisioned
in_transit:
  - connection: web host → git-data bare repos
    tls: SSH (ED25519, private-net only; public ingress deny-all)
    cert_verification: TOFU — tracked by #5914, not changed here
    does_not_defend: a compromised web host with the transport key
    disclosed_as: private-net git transport (ADR-068 §6)
exception:
  justification: >
    The plaintext volume is a cutover artifact that can never hold user data — every git-data write
    path is gated on isGitDataStoreEnabled(), and git-data-cutover.sh preconditions() refuses to run
    unless that flag is OFF, setting it true only as its final step after repoint_luks_mount. This
    was settled as brainstorm D10; born-on-LUKS was considered and rejected.
  tracking_issue: "#6976"
  reevaluate_when: the git-data host is born
  expires_on: 2026-10-31
```

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-143** with a dated addendum (D8 — no new ordinal allocated, TR8). It must record D1–D10
**and** correct the closing paragraph that currently asserts `var.git_data_server_type` keeps its
unorderable default. ADR-143:149 already names #6570 as the owner of this decision, so this is the
handoff that ADR anticipated.

### C4 views

**No C4 change required** — supported by an explicit enumeration against all three
`knowledge-base/engineering/architecture/diagrams/*.c4` files:

- **(a) External human actors:** none added or changed. A server-type repin introduces no actor.
- **(b) External systems / vendors:** none new. Hetzner is already the `hetzner` container's
  `technology`. The Doppler CLI GitHub-release download is pre-existing egress, and is not modeled
  as an edge for *any* host (inngest and registry perform the identical download and carry no such
  element).
- **(c) Containers / data stores touched:** none. `hcloud_volume.git_data*` are untouched (TR2), and
  neither is a C4 element — the only modeled volume is `workspacesVolume`, which is the **web
  host's** `/workspaces`, not git-data's store.
- **(d) Access relationships:** none change.

Additionally verified: **no `cax11`, `Ampere`, or `ARM-native` claim exists in any `.c4` file**, so
this PR falsifies no modeled description. The only `arm64` occurrence is `model.c4:433`, the
inngest→Better Stack Vector edge, which is unrelated. `model.c4:180`'s DR-gap list (web-1 `cx33`,
grok-dogfood `cx33`, registry `cx23`) correctly omits git-data because it names *running* hosts —
and this PR moves git-data's declared type into the orderable set, so that list stays accurate.

## Domain Review

**Domains relevant:** Engineering, Finance, Legal (carried forward from the brainstorm's
`## Domain Assessments`).

**Not spawned.** This session runs under a standing operator instruction against invoking subagents,
so neither the Phase 2.5 domain-leader Tasks nor the Step 4.5 advisor consult nor the plan-review
panel were spawned. The assessments below are the orchestrator's, recorded honestly as such rather
than presented as leader sign-off. **This is the main quality caveat on this plan** — the 3–5 agent
plan-review panel that normally catches phase-ordering and AC-verifiability defects did not run.

### Engineering

**Status:** reviewed (inline). Three files plus a new test suite, with two in-repo precedents copied
verbatim. The only genuinely novel element is FR6's plan-time tripwire. Chief mechanical risk is the
`$${DOPPLER_VERSION}` vs `${doppler_arch}` escaping distinction in the cloud-init.

### Finance

**Status:** reviewed (inline). +€13.50/mo net vs the voided ARM pin (~+$14.60 at ~1.08 FX). Not yet
burn — the row stays `approved-not-billing` until the gated birth. The cheaper `cx23` alternative
was rejected on stock durability, so the increase is a deliberate purchase of orderability.

### Legal

**Status:** reviewed (inline). No new sub-processor; same Hetzner account and DPA. `hel1` preserves
EU residency (CLO T-1). LUKS-at-rest posture unchanged by construction (TR2).

### Product/UX Gate

Not applicable — no path in Files to Edit/Create matches any UI-surface term or glob. Tier: NONE.

## Open Code-Review Overlap

**None.** Queried `gh issue list --label code-review --state open --limit 200` and matched every
planned file path (`infra/variables.tf`, `infra/git-data.tf`, `cloud-init-git-data.yml`,
`knowledge-base/operations/expenses.md`) against issue bodies — zero hits.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `$${DOPPLER_VERSION}` escaping broken while adding `${doppler_arch}` — renders a literal `${...}` or fails templatefile | `terraform validate` + `.github/scripts/validate-infra-templates.sh`, which discovers templates structurally from `templatefile()` calls and renders them. AC2/AC3 greps. |
| amd64 checksum wrong → host boots with no LUKS passphrase access | Reused verbatim from two live hosts; git-data's own current arm64 literal is byte-identical to inngest's, proving same-version provenance. `sha256sum -c -` fails closed at boot. |
| `cpx22` leaves the orderable set before the birth | `stock-preflight-gate.sh` re-probes live at dispatch. `cpx*`/`ccx*` were stably orderable in all 3 DCs across both recorded probes. |
| FR6's data source 403s or the API is unreachable → **every** plan of this root fails | `zot-registry.tf:134` already takes this dependency and is green, so the token demonstrably reads server types. Precedent, not a new risk. |
| Reviewer reads this as authorizing the birth | NG1 in the spec, D9 in the brainstorm, and "Post-merge (operator): None" above. |
| Plan-review panel did not run (no subagents) | Stated plainly in §Domain Review. Offer the panel before `/work` if the operator wants it. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or
  `/work`.
- **Never write the three-letter secure-shell verb inside the `## Observability` section**, not even
  in a comment or a prose caveat. The v1 plan appended `# no s‑s‑h` to
  `discoverability_test.command` to *advertise* that the command needs no remote login; deepen-plan
  Phase 4.7's reject regex `(^|\s|/)ssh(\s|$)` matched the word inside that comment, so a plan that
  is provably remote-login-free **failed** the remote-login-free gate. Caught by running the gate
  against this file rather than assuming it passed. This is the AC-self-reference grep trap applied
  to a section body: state the property by *omission*, and put any commentary about it here in Sharp
  Edges, outside the grepped section.
- **`$${VAR}` vs `${VAR}` in `cloud-init-git-data.yml` is the highest-risk edit in this PR.** Double-`$`
  is a **shell** variable that Terraform must pass through literally; single-`$` is a Terraform
  interpolation that must have a matching templatefile map key. `DOPPLER_VERSION` stays double;
  `doppler_arch` and `doppler_sha256` are single.
- **FR6b is MANDATORY, and v1's Sharp Edge saying reviewers "may cut it as scope creep" was
  exactly backwards.** Two agents probed the pinned toolchain independently and agreed: with
  `-target=`, an **unreferenced** data source is **pruned and never read** (probe: `-target` an
  unrelated resource → no `Reading…`, exit 0; add a `lifecycle.precondition` edge → `Reading…`
  fires). Every git-data dispatch is `-target`ed, so **FR6 without FR6b fires on zero production
  paths** — it is live only in the untargeted PR-time plan job. The zot precedent is not a
  counterexample, it is the proof: its data source feeds `local.registry_memory_cap_mb`, which is
  what makes it an ancestor under `-target`. v1 copied the form and dropped the mechanism. Either
  keep FR6b, or delete FR6 outright and credit `stock-preflight-gate.sh` alone — do not ship FR6
  alone plus an Observability claim the operator will trust.
- **`architecture` is VERIFIED PRESENT on hcloud v1.63.0** (`terraform providers schema -json`
  against the pinned binary), so Phase 0's old "verify or drop" gate is satisfied. **But the value
  domain is the trap:** `hcloud-go`'s enum is `x86` / `arm`, while `local.git_data_arch` is the
  download token `amd64` / `arm64`. A precondition written the way v1 described it in prose —
  comparing the two directly — is `"amd64" == "x86"`, **false on every plan forever**, wedging the
  whole root including unrelated applies. Map explicitly (Phase 2), and let AC4b assert the mapping.
- **`sha256sum -c -` is not the fail-closed point — and NOTHING here is.** Its runcmd item has no
  `set -e`, so a failing checksum does not stop the following `tar xzf`. Corrected at review: the
  boot does **not** fail closed downstream either. The `doppler run` at the LUKS block does carry
  `set -euo pipefail`, but that is line 1 of the heredoc `doppler run` EXECUTES — on a missing or
  wrong-arch binary `doppler run` never execs and the line runs zero times. cloud-init also
  concatenates `runcmd` into one non-`-e` script, so the item merely exits non-zero and boot
  continues, leaving sshd up and the LUKS volume unmounted with no off-host signal. Any runbook must
  name the plan-time precondition as the only guard that fires; credit neither the checksum nor that
  `set -e`.
