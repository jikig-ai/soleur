# Decision Challenges — feat-one-shot-6594-infra-config-freshness-gate

Persisted headless per ADR-084 / plan-review classifier routing. `ship` Phase 6 renders these into
the PR body and files an `action-required` issue. **These are NOT decided — they need the operator.**

---

## UC-1 — `image_pull_failed`: the request said "Fix this too", the plan says "don't fix it yet"

**decisionClass:** `user-challenge` (dropping operator-requested scope is never-Mechanical)

**Operator's stated direction:** *"Separately: the `image_pull_failed` ... Fix this too — it is in
scope for this request."*

**What the plan proposes instead:** do not fix it in this PR; hand the measured datum to #6565.

**Why (measured, not argued):**
1. It is not one bug. `image_pull_failed` is a **pull** failure (#6525/#6400/#6560);
   `class=cred_store` is a **login** failure (#6497/#6565). Different code paths
   (`pull_image_with_fallback` vs the login gate). The request's framing chains them; the evidence
   does not.
2. **The login instrument is already live.** The host's `ci-deploy.sh` (`2208300a`) already contains
   `_docker_login_failure_class` (×6) and `LOGIN_ERR` (×19) from #6528 (**MERGED**). #6565's stated
   blocker is #6528, **not** #6577 — so #6565 is blocked on nothing.
3. **I already pulled the datum #6565 was waiting for** (Better Stack, 2026-07-17):
   `class=cred_store rc=1 stderr_chars=97|96|94 stdout_chars=0 kw=errsaving tok=error
   docker_ver=29.3.0 (registry=ghcr)` — on `host_name=soleur-inngest-prd`.
4. Fixing the pull failure now, without reading the instrument, is a **guess** — and #6497's
   htpasswd retraction is the scar tissue showing what that costs.

**The honest cost of the plan's choice:** the operator asked for a fix and gets a handover instead.
The counter-argument is that the handover is *worth more*: #6565 becomes actionable **today**
rather than after a delivery-chain fix.

**Options for the operator:**
- **(a)** Accept the split: this PR fixes the gate; the login datum goes to #6565; the pull mechanics
  go to #6525. Both become small follow-up PRs. *(plan's recommendation)*
- **(b)** Fold the **login** repair into this PR now, using the datum above (`kw=errsaving` =>
  docker credential-store write failure). Bigger PR, and it targets the inngest host — a different
  host from the one this PR's delivery chain reaches.
- **(c)** Fold the **pull** repair (#6525) in. **Not recommended** — no instrument names it yet; this
  is the guess.

---

## UC-2 — the inngest steer: RETRACTED TWICE. Final answer: not actionable, and the reason matters

**decisionClass:** `user-challenge` (it concerns the operator's own steer)

**Operator's stated direction:** *"If we don't want to take risks with web-1 we could consider
testing it against inngest host?"*

**Final answer: the steer is not actionable — but not for the reason the plan first gave, and the
investigation it forced surfaced two real defects.** This entry records the full flip-flop because
the reasoning error is the lesson.

### The three-step correction

1. **v1 said "not possible"** — the inngest host has no cloudflared connector and no
   webhook/infra-config surface. *True, but it checked the wrong property.*
2. **Telemetry appeared to overturn that.** All 34 `ci-deploy` rows in 72h — including every
   `class=cred_store` login failure #6577 targets — carry
   `_MACHINE_ID=3f07b65531ab48b9b02d013c6b08feba` / `host_name=soleur-inngest-prd`. I concluded the
   errno target lives on the inngest host and **that the operator was right.**
3. **That conclusion was wrong.** `host_name` is a **Vector-rendered string literal**
   (`vector.toml`'s `@@HOST_NAME@@` sentinel), `sed`-substituted to the constant
   `soleur-inngest-prd` by `inngest-bootstrap.sh` — **which also runs on a *colocated* web host** via
   `ci-deploy.sh`'s `case "inngest")` arm. A colocated web host therefore emits ci-deploy rows, runs
   `inngest-server.service`, and self-labels as inngest — **all on one `_MACHINE_ID`**, reproducing
   every fact I had. `soleur-host-bootstrap.sh` (#6396) documents this exact state verbatim.

### The discriminator that settled it

`_MACHINE_ID` is real but says nothing about *which* host. The decisive field was the running
process's own argv:

| Source | `--sdk-url` |
|---|---|
| **Dedicated** inngest host (`inngest-host.tf:234`) | `http://10.0.1.10:3000/api/inngest` (the web backend's **private IP**) |
| **Measured, live** (`inngest-server.service` `_CMDLINE`) | `http://127.0.0.1:3000/api/inngest` (**localhost**) |

`127.0.0.1` is only correct if inngest and the web app share a box. `inngest-bootstrap.sh:435`:
*"the server polls the **co-located** web-platform"*.

⇒ **Machine `3f07b655` is a WEB host running a colocated inngest, mislabelled `soleur-inngest-prd`.**

### What this means for the round

- **The `class=cred_store` failure is a WEB-host problem.** The issue body's Evidence #1 attribution
  was **correct**; my step-2 challenge to it is withdrawn.
- **The plan's recovery delivers the errno instrument to exactly the right host.** web-1 via the
  infra-config push. No retarget needed. **The plan gets stronger, not weaker.**
- **The operator's steer is not actionable** — there is no delivery path for `ci-deploy.sh` to the
  dedicated inngest host, and it was never designed to have one (the `inngest-bootstrap` OCI image
  does not contain `ci-deploy.sh`; `cloud-init-inngest.yml` does not write it; `inngest.tf` has zero
  provisioners; no workflow `-target`s an inngest resource). **v1's D3 stands.**
- **The operator's underlying concern is still honored** — the enabling change is a Cloudflare
  config edit with zero host writes, the test runs offline against a real captured payload, and the
  only prod write is the precedented nonce, not a `-replace`.

### Two real defects this flip-flop surfaced — both need their own issues

- **D-A: `host_name` telemetry is actively lying.** A web host reports itself as
  `soleur-inngest-prd`. **Every attribution built on `host_name` is suspect** — including #6425's
  reading that false `inngest-down` alarms came from web-2. This is the same
  "conflicting attribution" #6594's body flags as UNVERIFIED and is now **explained**: it is a
  mislabel, not a routing artifact. #6396 knew and chose not to clobber it.
- **D-B: the dedicated inngest host is DARK.** `soleur-inngest` (`cpx22`, `10.0.1.40`) is **running**
  (Hetzner API) yet **exactly one `_MACHINE_ID` ships journald** to Better Stack — and it is the
  colocated web host, not `10.0.1.40`. Zero rows from any dedicated-host-only unit
  (`inngest-redis`, `inngest-nftables`, `inngest-boot-phone-home`). Consistent with #6536's
  "the host was dark" class. **If a colocated inngest AND the dedicated inngest are both live, that
  is a double-scheduler condition and it is an escalation, not a footnote.**

**Nothing here is asserted beyond the measurement.** Whether web-1 *still* runs a colocated
scheduler concurrently with `10.0.1.40` is **UNKNOWN** from off-host evidence and is precisely what
D-A/D-B must resolve.

### Options

- **(a)** Keep the plan as-is (gate + web-1 recovery — the correct target), and file **D-A** and
  **D-B** as new issues. *(recommendation)*
- **(b)** Also fold a `host_name` fix into this PR. **Not recommended** — it edits the Vector config
  on a running host and is a separate blast radius.
- **(c)** Treat D-B (possible double scheduler) as a P1 incident and triage before this PR ships.

