# Decision Challenges — feat-one-shot-6415-private-nic-imds-resilience

Headless plan-review consolidation (no TTY → per `plan-review` classifier routing, Mechanical findings
were auto-applied to the plan; Taste / User-Challenge are persisted here for `ship` Phase 6 to render
into the PR body + file as an `action-required` issue).

Panel: `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
`architecture-strategist`, `spec-flow-analyzer` (5-agent escalation — `brand_survival_threshold:
single-user incident`) + named panel `cpo` (relevance-gated; `requires_cpo_signoff: true`).

---

## UC-1 — Phase 3B (off-host probe): required-for-close, or split to a follow-up?

**decisionClass:** `user-challenge` (scope — touches what "done" means for #6415)

**The operator's stated direction is the default.** #6415 asks for a self-heal + a loud marker, and
explicitly says the marker *"Closes the #6405 observability gap for this host class."* It does **not**
ask for the off-host probe. Elevating that probe to required-for-close **adds** scope beyond the issue.

**Panel split (3 keep / 1 split):**

| Agent | Position |
| --- | --- |
| `cpo` | **Keep, required-for-close.** Not new scope — *unfinished ADR-103 scope*; the heartbeat is already provisioned and paid for, `ZOT_HEARTBEAT_URL` has zero consumers. The user-visible property of #6400 is not "the NIC was down" (users don't experience NICs) but "14 days of green while fixes couldn't ship" — an observability failure. L1 fixes *why it broke*; only L3 fixes *why nobody knew*. |
| `dhh-rails-reviewer` | **Keep** — "the highest-value thing in the document"; a cron and a curl. |
| `architecture-strategist` | **Keep, and strengthened**: `model.c4:380` (`hetzner -> ghcr` atomic fallback) means a **web** host booting NIC-less also fails silently. L3 covers that end *incidentally* (probe fails → heartbeat absent → alarm). |
| `code-simplicity-reviewer` | **Split to its own issue.** L2 already closes the 14-day gap **for the observed failure**: #6400's host had **no `10.0.1.30` at all**, so L2's local reading would have been correct and alarmed in ~30 min. L3 covers a *strictly different, never-observed* mode ("private net broken from a consumer's perspective while the host thinks it's fine"). The plan's justification ("L1/L2 ship over public egress") **conflates transport with subject** — L2's transport is public, its *subject* is local NIC state. |

**Resolution applied in the plan (v2): DEFERRED to a follow-up issue.** The 3–1 majority **collapsed
once its factual basis was checked.** `spec-flow` found — and I verified directly against the file —
that the plan's own justification was **false and inverted**:

- v1 claimed *"`apply-web-platform-infra.yml` already names the web-host-driven private-net probe as the
  authoritative liveness pattern for git-data — this follows it."*
- `apply-web-platform-infra.yml:2198-2206` says the **opposite**: git_data_prd is *"paused until #5274
  PR C arms the web-host probe cron"*, *"its probe cron is **unbuilt**"*, and the job uses a
  bounded-poll assert **because the probe does not exist**.
- `ZOT_HEARTBEAT_URL` / `GIT_DATA_HEARTBEAT_URL` have **zero consumers** outside `.tf`, a cutover
  script, and docs (independently confirmed by `cpo` and `code-simplicity`).

**This is an `hr-verify-repo-capability-claim-before-assert` violation by the plan author**, and the
fabricated "the remaining work is small" was the **sole basis** for the elevation. `cpo`'s "keep" was
explicitly grounded on *"not new scope — unfinished ADR-103 scope … the remaining work is small"*;
`dhh`'s on *"a cron and a curl"*. **Both rested on the false claim.** `code-simplicity`'s dissent —
L3 is greenfield and its `paused` flip is a no-op — was **correct**.

**CPO's own condition C3 therefore triggers, at plan time rather than at `/work`:** *"if the delivery
site is not resolved within a bounded budget, 3B splits to an immediate follow-up and L1/L2 ship."*
The site is unresolved **and** the arming is blocked (`ignore_changes=[paused]` ⇒ the flip is a no-op;
the real unpause is a Better Stack **UI** step that contradicts the plan's own `iac-routing-ack`).
So: **L1+L2 ship; L3 → tracking issue** carrying the arming fix, the cadence mismatch
(`period=60/grace=30` vs a 60s cron floor), and the `betterstack_paid_tier=false` email-only caveat.

**What L2 does and does not buy (recorded honestly):** L2 closes the 14-day gap **for the observed
failure** — #6400's host had **no `10.0.1.30` at all**, so L2's local reading is correct and alarms in
~30 min. It does **not** cover "private net broken from a consumer's perspective while the host thinks
it's fine". That residual is documented in the plan's `## Observability`.

**Operator: this is the one scope call to overrule if you disagree.** The counter-argument (`cpo`,
`architecture`) remains substantive on its *merits* even though its *evidence* was wrong: L1/L2 ride
public egress and cannot prove consumer-side reachability, and `model.c4:380` shows web hosts share the
silent-failure property via the GHCR fallback. If you want L3 in this PR, it is **greenfield work on a
different host** — budget it accordingly.

---

## UC-2 — `#6415`'s tracking metadata contradicts the plan's threshold

**decisionClass:** `user-challenge` (operator-owned metadata; the plan is PLAN-ONLY and did not mutate it)

`cpo` condition **C2**, verified against the milestone API and `gh issue view 6415`:

- #6415 sits in **Post-MVP / Later** — a milestone whose own description is *"issues that don't fit in
  any current roadmap phase"* (760 open issues). But it is the **root-cause fix for #6400**, an
  **open P1 on the Phase 4 milestone**.
- Its `priority/p2-medium` label is justified as *"workaround exists"* — **falsified** by #6400's actual
  state: the GHCR fallback was **also** degraded, which is precisely why prod stuck at `0.213.2`.
- It carries `type/chore`.

**CPO's ruling:** *"A plan carrying `single-user incident` cannot hang off a P2 chore in a 760-issue
graveyard. The metadata and the threshold cannot both be right; I ruled the threshold right."*

**Proposed (NOT applied — requires operator action):** move #6415 to the **Phase 4** milestone, raise it
off `priority/p2-medium`, drop `type/chore`.

---

## T-1 — The plan is ~2× longer than the code it specifies

**decisionClass:** `taste`

`dhh-rails-reviewer`: *"738 lines of plan for what is, at bottom, 'the host didn't get its IP, and
nobody noticed'… The plan-to-code ratio is inverted."* `code-simplicity-reviewer` independently
scored complexity **High** on the same ratio (738 plan lines / 17 ACs / 11 risks / 10 scenarios around
~45–50 lines of bash).

**Partially applied (Mechanical portion only):** the v2 rewrite cut the netplan path, Phase 0, and the
LARP ACs — the cuts that follow from *correctness* findings. The residual question — whether a plan of
this density is proportionate to an infra bash guard **at `single-user incident` threshold** — is
taste, and is surfaced rather than auto-resolved. Both DHH and CPO independently praised the
evidentiary discipline that produces the length, so the trade is real in both directions.

---

## Mechanical findings — auto-applied to the plan (recorded for audit)

Applied without a gate (eng-panel correctness/simplification, one right answer):

| # | Finding | Agents | Evidence |
| --- | --- | --- | --- |
| **P0-1** | `paused` flip is a **Terraform no-op** → L3 ships inert; AC16 false-passes | kieran, architecture, code-simplicity (**independent ×3**) | `zot-registry.tf:355` `ignore_changes=[paused]`; `:336` "Unpause via the Better Stack UI"; `heartbeat-reprovision-parity.test.ts:256-257` names `registry_prd` |
| **P0-2** | `last_err` ≠ `zot_last_err` → spoof strip **never fires**; R8/AC8/AC9 mutually incompatible; lib absent from Files to Edit | kieran, code-simplicity (**independent ×2**) | `scripts/lib/zot-telemetry-parse.sh:27` `sed 's/ zot_last_err=.*//'` (literal) |
| **P0-3** | netplan step 5 has **no budget** → re-applies every 5 min indefinitely, bouncing public egress; 25-min absence window never trips → invisible to every alarm | architecture; converges with dhh + code-simplicity "cut netplan" | `registry_disk_prd` period=900/grace=600 |
| **P1-1** | Self-heal has **no alarm consumer**: `converged_by=netplan\|reboot` ⇒ `nic_ok=true` ⇒ no alarm → the race becomes silently self-healed and never reported (**lost ceiling**) | architecture | plan Phase 3.1 fires on `nic_ok=false` only |
| **P1-2** | ADR-113's class-wide `MUST` + LUKS blocker living only in Deferred Items → a future agent applies the reboot to git-data | architecture | ADR outlives the plan/issue |
| **P1-3** | Boot anchor wrong: `DOPPLER_TOKEN` is written at **`:317-318`**, not by the CLI install → `doppler run` resolves nothing, POST dies, `\|\| true` swallows it **silently** | kieran (sharper than architecture's `:305`→`:309`) | `cloud-init-registry.yml:317-318` |
| **P1-4** | **AC5 false-passes on an unmodified file** — `grep -c 'private_ip' zot-registry.tf` returns **2** today (`:40`, `:44`) | kieran | must assert the `templatefile` argument |
| **P1-5** | **AC8 false-passes on an unmodified file** — the alarm already sources the lib | kieran | `scripts/zot-restart-loop-alarm.sh:54` |
| **P1-6** | **"same bytes the host boots" is false** — the guard body is a Terraform template (`$${...}` escaping, unrendered `${private_ip}`); extracted bytes are **not** executable bash. The cited precedent extracts only *scalars* | kieran | `registry-boot-guard.test.sh:38-42`; `:305`, `:369` |
| **P2** | **C4 "nothing falsified" is wrong on 3 counts** (enumerative descriptions) | architecture | `model.c4:264`, `:396`, `:400`; precedent commit `c749e4e6a` edited C4 for a structurally identical change |
| **P2** | `betterstack_paid_tier` defaults **false** → `policy_id = null` → **email-only, no escalation** — undisclosed in L3's `alert_route` | architecture | `variables.tf:301` |
| **P2** | "Registry is the only host with the silent-failure property" is **wrong** — the property belongs to the **zot pull path** and is symmetric; a web host booting NIC-less falls back to GHCR and fails silently too | architecture | `model.c4:380` |
| **P2** | `hr-prod-host-config-change-immutable-redeploy` does **not** "bless" a self-reboot — it acknowledges a reboot may be *needed* during an operator `-replace`; it does not authorize a host to decide to reboot itself | architecture | plan overreach; ADR must earn the authority on its own merits |
| **P2** | R2 **mis-ranked** as highest-severity — structurally impossible under the counter; the mitigation budget was aimed at the wrong risk | architecture | |
| **P2** | Citation drift: `:368`→`:369`; `:345-350`→FATAL at `:351-353`; `:33-34`→`:31`; `:44`→`:40`; `:254`→`:266`; `zot-disk-heartbeat.sh:227` is a `write_files` path, not a repo file; gate real path is `tests/scripts/lib/…` | kieran | |
| **P2** | AC1 measures the **raw template**, not rendered `user_data`; `gzip -9` ≠ Terraform's `base64gzip` (default ≈ `-6`) | kieran | cannot false-pass at 18 KB headroom, but doesn't measure the thing the cap applies to |
| **P2** | Reboot cap **"1–2" unpinned** — T5/T6 unwritable against a range | kieran, code-simplicity | pin to a literal |

**Verified-correct by the panel (no change owed):** ADR-113 ordinal is free (highest ADR-112 on
`origin/main`); the heartbeat-parity manifest claim + AC7 are sound (`bun test plugins/soleur/`
recursion via `scripts/test-all.sh:211`); the `cloud-init clean` rejection is well-founded
(`cloud-init-registry.yml:294` bare `echo >>` vs git-data `:170` guarded); the git-data LUKS safety
ruling holds (`luksOpen` in a `runcmd` heredoc `:163`, zero repo-wide `crypttab` hits, `nofail` `:118`);
AC13 correct (`registry-boot-guard.test.sh` registered at `infra-validation.yml:224`, no glob
auto-discovery); the on-host-layer reasoning and the `OPERATOR_APPLIED_EXCLUSION` argument
(`zot-registry.tf:16-22`) both verified.
