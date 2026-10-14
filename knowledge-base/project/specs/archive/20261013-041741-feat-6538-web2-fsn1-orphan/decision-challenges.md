# Decision challenges — feat-6538-web2-fsn1-orphan

Emergent decisions taken during `/work` that went against my recommendation, or that
the plan did not contemplate. Recorded per ADR-084 so they are auditable outside this
session. `ship` renders this into the PR body.

---

## DC-1 — A false Article 32 encryption claim stays published pending remediation

**Date:** 2026-07-16
**Classification:** User-Challenge (operator overrode my recommendation, twice)
**Status:** **RESOLVED 2026-07-24** — encryption certified, over-claim retracted. See
§Resolution at the end of this entry. *(The reopen trigger below lapsed by one day before
the correction landed — recorded, not elided.)*

### The finding

`docs/legal/privacy-policy.md`, `docs/legal/data-protection-disclosure.md` and their two
Eleventy mirrors (the copies users actually read at soleur.ai) tell data subjects:

> Stored workspace git data is held on a **LUKS-encrypted (encryption-at-rest)** volume;
> traffic between the hosts is **encrypted in transit with TLS**; … membership is
> re-verified when a session is served across hosts.

**This is false.** Verified directly, three ways:

| Evidence | Result |
|---|---|
| `apps/web-platform/infra/server.tf` → `hcloud_volume.workspaces` (the volume holding user worktrees) | `format = "ext4"` — **no encryption** |
| `apps/web-platform/infra/cloud-init.yml` (the web host) | **0** occurrences of `cryptsetup` / `luksFormat` / `luksOpen` |
| `apps/web-platform/infra/git-data-luks.tf` — the LUKS volume that *does* exist | attached to `hcloud_server.git_data`, **never provisioned** |
| `apps/web-platform/server/workspace-resolver.ts` | split gated on `GIT_DATA_STORE_ENABLED`, unset → dark |

User workspace data — their source code — is stored **unencrypted at rest**, while the
published privacy policy states it is LUKS-encrypted. Three independent review agents
(`user-impact-reviewer`, `security-sentinel`, `code-quality-analyst`, later joined by
`pattern-recognition-specialist`) converged on this without prompting; I confirmed it
against the infra myself.

Only **one** of the four clauses can ever be made true:

- *"a dedicated per-workspace git-data host"* — **unachievable.** `cax11` is orderable in
  **0 of 3** EU datacentres (live Hetzner API, 2026-07-16: `nbg1-dc3`, `hel1-dc2`,
  `fsn1-dc14` all `false`). This is #6570's blocker.
- *"traffic between the hosts is encrypted with TLS"* — **unachievable.** There is no
  cross-host git traffic, and PR B destroys web-2.
- *"re-verified when a session is served across hosts"* — **unachievable.** No session has
  ever been served across hosts (no load balancer exists; `app.soleur.ai` is a hard-pinned
  singleton to web-1).
- *"held on a LUKS-encrypted volume"* — **achievable**, but only by encrypting
  `hcloud_volume.workspaces` (a *different* substrate than the git-data LUKS volume the
  sentence was written about), which is a live-data migration, not an in-place change.

### What I recommended

1. **First ask:** retract the false clauses now, keep what is true (per-workspace
   authorization, TLS in transit, EU-only), and file a P1 to encrypt the volume.
   → Operator chose **"encrypt the volume first, then keep the claim."**
2. **Second ask** (after establishing that 3 of 4 clauses are unachievable and that
   encrypting a live volume is a CTO-level migration): temporally qualify the remaining
   clause under the Art. 13(3) precedent this repo already set in PR #4455 —
   *"encryption at rest is being rolled out (Ref #N)"* — so no promise is withdrawn but
   nothing false is asserted.
   → Operator chose **"leave the claim published during the work."**

### The decision

**The claim stays published, as-is, until the encryption work lands.** This is the
controller's risk acceptance to make; the exposure is theirs and they made it with the
evidence above in hand.

### What I did NOT do

PR A does **not** ship the claim in a worse state than `main`. My original edit removed
the git-data host from those sentences and left the LUKS clause **dangling** — which
`pattern-recognition-specialist` correctly flagged as making the claim *worse*: bound to
a named phantom host it reads as describing that host; unbound it reads as describing
**live** workspace storage, which is plain ext4.

So I unwound it. PR A is now purely the **locative** correction. Verified mechanically:
every LUKS-clause count is byte-identical to `main` across all 6 files, and no clause is
left without its antecedent. The #5274-Phase-3 claim family (git-data host + LUKS +
cross-host clauses) is untouched — neither corrected nor exacerbated — and tracked below.

### Standing risk while OPEN

- A published privacy policy asserts an Art. 32 TOM that does not exist (Art. 5(2)
  accuracy; the over-claiming direction, which is the exposed one).
- User source code is unencrypted at rest on `soleur-web-platform-data` (hel1).
- The window is **unbounded** — the remediation has no committed date. It should be
  time-boxed.

### Remediation

- Encryption work + migration design: **#6588** (P1, `type/security`).
- The migration approach (live volume holding user code; format change is ForceNew) is an
  **architecture decision** and routes to the `cto` agent, not to the operator and not to
  `/work`.
- The doc correction lands **with** that work (#6588), not before.

### Reopen trigger

If the encryption work is not scheduled within **7 days** (by 2026-07-23), re-raise the
interim-wording decision — an unbounded window on a false security claim is a different
risk from a short, tracked one, and the second ask above should be re-put.

---

### Resolution — 2026-07-24 (#6588)

**Both halves are now discharged.**

**1. The encryption is real and certified.** web-1 `/mnt/data` runs on the LUKS-encrypted
`hcloud_volume.workspaces_luks` mapper. Certified 2026-07-23 (`workspaces-luks-verify`
run **30040444418**) and independently re-asserted at the time of this correction,
2026-07-24 (run **30130277489**): `device_type=crypto_LUKS`,
`mount_source=/dev/mapper/workspaces`, `escrow=ok`, `header=readable`,
`workspace_count=8 expected=8`. The re-assert was deliberate rather than a citation of the
day-old run — run 29782780158 had held `crypto_LUKS` for ~27 minutes before its own
dead-man timer silently reverted it (#6812), so a stale green is the documented failure
mode on this exact surface.

**2. The three unachievable clauses are retracted, and the achievable one is re-scoped.**
The claim family is removed **whole** across all 6 published files (3 canonical + 3
Eleventy mirrors), which is the specific defect this entry was written about: the
2026-07-16 attempt removed the head and left the LUKS clause dangling, making the false
claim *stronger*. Retracted: cross-host TLS; membership re-verification on sessions served
across hosts; the dedicated per-workspace git-data host. Retained and re-scoped off the
dead multi-host premise: the LUKS encryption-at-rest claim, now standing on the live
single-host topology. The internal Art. 30 register, the DPA scope in
`compliance-posture.md`, and the NFR register are corrected in the same PR — sequencing
them would have left the *internal* record over-claiming relative to the *public* one.

**3. The reopen trigger lapsed — stated plainly.** The trigger above set 2026-07-23. The
correction landed 2026-07-24, **one day late**. The encryption work itself was in fact
scheduled and executing throughout that window (the cutover ran 2026-07-23), so the
substantive risk the trigger guarded against — an *unscheduled*, unbounded window — did
not materialise. But the trigger was written against a date, not against a schedule, and
by its own terms it fired. Recording that rather than eliding it.

**4. What is NOT resolved by this entry.** A full un-wiped copy of every workspace remains
on the superseded pre-cutover plaintext volume `hcloud_volume.workspaces`, retained as the
ADR-119 rollback backstop. The operator was re-asked on 2026-07-24 whether to disclose it
and **reaffirmed the hold** (UC-3, PR #6918), choosing to cure the reality rather than
qualify the wording. That is an **accepted, undisclosed residual**, tracked on **#6808**
(the blocker on the soak, escalated to `priority/p1-high` + `type/security` by this PR) and
recorded in full at
`knowledge-base/project/specs/feat-one-shot-6588-legal-clause-retraction/decision-challenges.md`.
**#6588 does not close on that limb** — this entry closes because its own two asks
(retract the false clauses; make the surviving claim true) are discharged.
