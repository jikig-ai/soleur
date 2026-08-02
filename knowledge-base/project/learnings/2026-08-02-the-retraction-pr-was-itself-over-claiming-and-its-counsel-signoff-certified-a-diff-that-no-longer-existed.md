---
title: "The retraction PR was itself over-claiming, and its counsel sign-off certified a diff that no longer existed"
date: 2026-08-02
category: security-issues
module: legal-records
issue: 6588
pr: 6938
tags: [legal, article-32, rebase, attestation, retraction, over-claim, review]
---

# The retraction PR was itself over-claiming

PR #6938 existed to retract three unachievable Article 32 claims from Soleur's published
legal records (#6588: user source code sat unencrypted at rest while the privacy policy
claimed LUKS encryption-at-rest). It arrived described as **"closest to done — re-run one
cancelled check and merge."**

Review found it was shipping **four new** Article 32 misstatements, and that its committed
counsel sign-off certified a diff that no longer existed. The "cancelled check" was a red
herring: a concurrency supersession whose same-SHA rerun had already passed.

## 1. A rebase can reverse a PR's own position and update only half the artifact

The 2026-08-01 rebase moved the **Article 30 register** — DC-2 re-scoped items (14)-(16) /
(18)-(20) to `DRAFTED / NOT-YET-ACTIVE` instead of deleting them — and left the **published
legal text** behind. Twice. Both times with the *public* record stronger than the internal one.

The published docs asserted, present-tense, that a workspace's git data "is authorized per
workspace", while the same PR's register said of that exact measure: *"asserts NO
present-tense measure."* The code agreed with the register, not the policy —
`apps/web-platform/server/git-data-client.ts` returns on `!isGitDataStoreEnabled()` **before**
`authorizeGitDataAccess(...)`, and the flag defaults false.

`data-protection-disclosure.md` had already dropped the claim, so the three published
documents disagreed **with each other**.

> **Generalization:** after a rebase, diff the PR's **claims** against its own registers —
> not just its files against `main`. A file-level merge can be clean while the artifact's
> position is now self-contradictory.

## 2. Retraction has a mirror image: removing a hedge is an over-claim

Before the rebase:

> "**Where the Web Platform spans more than one Hetzner host in the EU region**, stored
> workspace git data sits on a LUKS-encrypted volume…"

Conditional on a false premise — so it asserted nothing. After:

> "Stored workspace git data sits on a **LUKS-encrypted volume (encryption at rest)** on the
> Hetzner host in the EU region that serves the Web Platform…"

Universal, present-tense — while a full **un-wiped plaintext copy of every workspace** sat on
`hcloud_volume.workspaces`, attached via `hcloud_volume_attachment.workspaces` to the very
host the new sentence names.

Nobody decided to accept that. It arrived as a side effect. The operator's standing hold
(DC-1, tracked #6808/#6897) had answered *"may we **add** a disclosure?"* — twice, and it
stands. It was never asked *"may we **strengthen** the claim?"*

The fix narrowed the **referent** (data class → serving volume) rather than adding a
disclosure: it names no volume, states no fact about one, and makes the claim strictly
weaker, so it does not touch the hold.

The CLO later found the narrowing was necessary on a **second independent ground it had
missed when issuing the ruling**: `hcloud_volume.workspaces` is `for_each = var.web_hosts`
while `workspaces_luks` covers web-1 only, so the universal was **also** false as to web-2's
plaintext volume (tracked #6931).

> **Generalization:** when auditing a correction, check both directions. An over-claim
> removed and an under-claim introduced are the same defect class, and a *hedge deleted* is
> an over-claim added without any new sentence to grep for.

## 3. An attestation goes stale silently and reads as authority

The committed counsel review (`status: SIGNED-OFF`, dated 2026-07-24) was wrong in four
load-bearing places against the tree it shipped with:

| Attested | Actual |
|---|---|
| SHAs `e6b00414…` / `dabb5105…` / `85373780…` "CONFIRMED — recomputed independently" | `656f7a59…` / `10bceac9…` / `44d7aaaa…`; the quoted prefixes match **no file and no commit** on the branch |
| "a **new July 24 head** is prepended", "July 16 demoted" | head is **July 31** (#7100); July 24 was demoted |
| Block **B2 CURED** because the register **deletes** items 14/15, 18/19 | DC-2 **retained** them as `DRAFTED / NOT-YET-ACTIVE` |
| "#6570 **OPEN** … can never be born" | #6570 **CLOSED** 2026-07-27 |

Cause is legible: written against the pre-rebase branch, never re-run after the rebase
reversed the PR's own position.

**The remedy that worked was preserve + amend, not re-issue.** A withdrawal notice plus
`Amendment No. 1` — the original attribution and its false rows kept intact. An attestation
that edits its own false rows out of existence is worth less than one that shows them; that
is the same reasoning this PR applies to the July-2 banner entry it annotates rather than
rewrites.

> **Generalization:** an audit/attestation artifact is evidence about a **byte-state**. Any
> rebase, force-push, or conflict resolution after sign-off invalidates it. Treat a sign-off
> older than the branch's last history rewrite as withdrawn until re-verified.

## 4. A published evidence citation falsifiable in one command

All six published surfaces said:

> "verified live (`workspaces-luks-verify`, **device_type crypto_LUKS on /dev/mapper/workspaces**)"

`apps/web-platform/infra/luks-monitor.sh` takes `real_dev` from `cryptsetup status` and runs
`blkid` on the **backing device**. `/dev/mapper/workspaces` is the **decrypted** device —
`blkid` returns `ext4`. If it ever returned `crypto_LUKS`, that would be nested LUKS.

Both internal artifacts had it right, as **two separate fields** (`device_type=crypto_LUKS`,
`mount_source=/dev/mapper/workspaces`). This was a compression error at the public-prose
layer only — the fact was known and got flattened on the way out.

> **Generalization:** a corrections banner *invites* verification. Any evidence citation in
> one must survive the check it invites. Prefer quoting the instrument's own field names over
> a prose compression of them.

## 5. "Marked one block, missed its twin" — and the correction created the contradiction

- `compliance-posture.md:84` was corrected to `hel1` / retired, while `:143` and `:146` kept
  asserting *"web-2 has been `fsn1` since PR #6393"* (retired 2026-07-17). A **uniformly
  stale** file became a **self-contradicting** one.
- The Art. 30 register: the PR **added** a vendor row saying *"A single CX33"* / *"the standby
  second web host is retired"* while **keeping** main's PA-1(d) row describing a running
  `web-2 cpx22`. Art. 30(1)(d) recipients contradicted inside the single record producible
  under Art. 30(4).

Both were PR-introduced. Index the sweep by **claim**, not by file — a file-indexed sweep is
bounded by the diff's file list and structurally cannot see the twin.

## 6. Process notes that paid for themselves

- **A cancelled CI job is not automatically suspicious.** Run `gh run list --workflow=<wf>` and
  look for a **superseding run on the same head SHA** first. Here, `cancel-in-progress: true`
  killed the older run at the exact second the newer one was created; the newer one succeeded.
- **A green exit code was not accepted as the merge-day verification.**
  `workspace_count=8 expected=8` is what proved the fail-closed inventory comparison had a real
  operand — the workflow's own `seed_workspace_count` docs warn that a missing baseline leaves
  it with nothing to compare, which would have been a vacuous green.
- **The CONCUR gate earned its keep.** It DISSENTed on a proposed `deferred-scope-out` filing
  because `legal-doc-consistency.test.ts` already records the mirror history as
  allowed-to-drift legacy — so the "open scoping question" was settled and the fix was ~9
  lines. Fixed inline; **zero issues filed** by this PR.
- **A reduced review slice still found four P1s.** The classification called for 8 agents; a
  focused 3-agent slice ran under the skill's documented deviation with operator approval. The
  evidence trailer honestly records `degraded 5/8 agents` rather than presenting as full
  coverage.

## Session Errors

- **Foreground `sleep 90` blocked by the harness** while waiting on subagents. Recovery:
  Monitor tool + task notifications. **Prevention:** never chain foreground sleeps; use
  Monitor with an until-loop, or rely on task notifications.
- **`vitest --reporter=basic` is not a valid reporter in this version.** The run failed at
  vite config load and *looked* like a config error; the suite never ran. Recovery: re-ran
  without the flag (13/13 pass). **Prevention:** already covered by review/SKILL.md's
  verify-prescribed-CLI-flags rule — it applies to self-authored flags too, not only
  reviewer-prescribed ones.
- **`python splitlines()` and `grep` disagreed on line numbers by 2** in
  `article-30-register.md` (contains U+2028 ×1 and U+2029 ×1, which `splitlines()` treats as
  line breaks and `grep` does not). I read line 427 as a table separator and briefly doubted
  a correct agent finding. Recovery: `sed -n '427p'`. **Prevention:** when resolving a line
  number produced by `grep`, read it back with a `\n`-only tool (`sed`/`awk`), never
  `splitlines()`. Routed to review/SKILL.md Sharp Edges.
- **Two malformed verification greps.** A header check counted every NFR in the file (23)
  instead of NFR-027's, and a multi-file `grep -c` (which emits `file:count`) was piped into
  `bc`. Recovery: re-scoped with `awk`. **Prevention:** scope a verification grep to the
  section under test, and never pipe multi-file `grep -c` into arithmetic.
- **Called a correct finding "overstated" before reading the full line.** The
  `compliance-posture` `fsn1` rows genuinely carried a present-tense assertion, not just a DC
  allowlist. Recovery: read in full, corrected plainly. **Prevention:** already covered by the
  quote-the-comment-in-full rule in review/SKILL.md; it generalises from comments to any
  finding that turns on a line's exact wording.

## Related

- `knowledge-base/legal/audits/2026-07-counsel-review-6588.md` — withdrawal + Amendments 1-3
- `knowledge-base/project/specs/feat-one-shot-6588-legal-clause-retraction/decision-challenges.md` — DC-1 (hold), DC-2 (rebase reversal), DC-3 (banner date)
- #6808 (dead LUKS heartbeat — the claim-decay dependency), #6897, #6931, #6812, #3723
