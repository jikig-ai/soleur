# Tasks: Inngest dedicated-host liveness discriminators + standalone probe ops

Plan: `knowledge-base/project/plans/2026-07-20-feat-inngest-liveness-marker-discriminators-and-registry-probe-op-plan.md`
Issue: #6617 (`Ref`, not `Closes` — closes on the post-merge replace)

Three PRs, ordered A → B → C. Do not bundle.

---

## PR A — `_pf_scrub` libpq redaction (`Closes #6295`)

### Phase A0: Preconditions

- [x] A0.1 Re-extract the three `_pf_scrub` bodies and confirm byte-identical
      (`inngest-registry-probe.sh:64-69`, `inngest-doublefire-probe.sh:105-110`,
      `inngest-inventory.sh:206-211`)
- [x] A0.2 Confirm #6295 still open

### Phase A1: RED

- [x] A1.1 Failing test: libpq keyword form → synthetic ref absent from **stdout and stderr**
      (fixture synthesized, never a real ref)
- [x] A1.2 Failing test: over-redaction control fed through a **real `_pf_scrub` call site**
      (GraphQL `errors[].message` text) → survives intact
      - [x] A1.2.1 Do NOT build the control from a `SOLEUR_*` marker — markers reach
            `_pf_sanitize` (`:56-59`), never `_pf_scrub`
- [x] A1.3 Failing test: pairwise byte-identity across all three `_pf_scrub` bodies
- [x] A1.4 Confirm all three fail for the right reason

### Phase A2: GREEN

- [x] A2.1 Add a third `sed -E` rule requiring **≥2 co-occurring libpq keywords**
      (a single-keyword rule makes A-AC2 and A-AC3 mutually unsatisfiable)
- [x] A2.2 Apply byte-identically to all three copies
- [x] A2.3 A1 tests green; sibling probe suites green

### Phase A3: Close out

- [x] A3.1 File the `_pf_scrub` shared-library extraction issue, upgrade trigger =
      "a fourth consumer appears"; record the number in the PR body
- [x] A3.2 PR body: `Closes #6295`

---

## PR B — standalone read-only probe ops (`Ref #6617`)

### Phase B1: RED

- [x] B1.1 Four **anchored** assertions (unanchored greps false-pass — `registry-probe`
      already appears 10× as the hook name `inngest-registry-probe`)
      - [x] B1.1.1 `^[[:space:]]+-[[:space:]]*registry-probe$`
      - [x] B1.1.2 `^[[:space:]]+registry-probe\)`
      - [x] B1.1.3 `^[[:space:]]+-[[:space:]]*doublefire-probe$`
      - [x] B1.1.4 `^[[:space:]]+doublefire-probe\)`
- [x] B1.2 Confirm all four return 0 today (fail RED correctly)

### Phase B2: GREEN

- [x] B2.1 Add both ops to the `op` enum
- [x] B2.2 Case arm `registry-probe)` → `$BASE/inngest-registry-probe`, modelled on `enumerate`
- [x] B2.3 Case arm `doublefire-probe)` → `$BASE/inngest-doublefire-probe`
- [x] B2.4 Carry `op=verify` step 2.6's scope caveat verbatim into the doublefire summary
- [x] B2.5 Surface counts + verdict in the run summary in **both** directions

### Phase B3: Constraint verification

- [x] B3.1 `environment:` line byte-identical (pinned at `cutover-inngest-workflow.test.sh:389`)
- [x] B3.2 No `${{ inputs.op … }}` expression in either arm; file-wide count stays **1**
- [x] B3.3 Both curls carry `--max-time` (parity assertion `:55-58`)
- [x] B3.4 No retry loop — `for attempt in 1 2` count stays **3** (`:296-297`)
- [x] B3.5 No reminder capture, quiesce, Doppler secret write, or state transition
- [x] B3.6 Do not write the shell-remote-login word in a comment (AC-NOSSH `:170` is comment-blind)
- [x] B3.7 `cutover-inngest-workflow.test.sh` green

### Phase B4: Close out

- [x] B4.1 File the counting-assertion tracking issue (the suite asserts a character census)
- [x] B4.2 **Dispatch both ops standalone; record the results — this answers H4**
      - [x] B4.2.a `op=registry-probe` dispatched and read (run 29729509511, success):
            `registry_empty=true function_count=0 ids=[]`. Recorded in `session-state.md`.
      - [x] B4.2.b `op=doublefire-probe` — **read taken 2026-07-20, run 29748606817 (success):
            ZERO runs on the dedicated host.** The first dispatch (run 29729623865) surfaced a
            pre-existing defect on the DEFAULT path (`build_request_body` used `printf '%s'`,
            emitting zero bytes for an empty CSV → `jq --argjson fnids ""` aborted). Fixed
            inline on this branch. The host runs the *deployed* copy, so the reading could not
            be taken until the fix reached it via the post-merge infra-config push. It has now
            landed: run 29748606817 was dispatched from `main` (sha `898de92e4`) AFTER the
            merge, so it exercised the shipped fix rather than the branch copy — which is
            precisely what made this item answerable. Annotations:
            `doublefire-probe: 0 run(s) in window; bucketing by (functionID, floor(startedAt / 3600s))`
            and `doublefire-probe: ZERO runs on the dedicated host — its scheduler has executed
            nothing in the window.` Recorded on the tracking issue as `RESULT: PASS`.
- [x] B4.3 Do NOT record an H4 verdict anywhere until B4.2's rows are read
      — **honoured.** The only verdict recorded is the registry one, and it is backed by an
      actual read row (B4.2.a), not by inference. `session-state.md` carries the explicit
      caveat that an empty registry is **not** proof of "no double-scheduler": it shows
      nothing is registered *now*, not that nothing executed earlier.
      **Resolved 2026-07-20:** the doublefire verdict is now recorded, backed by run
      29748606817 (B4.2.b). B4.3's discipline held throughout — the read came first and the
      verdict followed it; no verdict was ever recorded ahead of a row. The registry-alone
      caveat above is thereby **discharged**, not bypassed: the instrument that proves the
      harm itself has now run and returned empty.

---

## PR C — marker discriminators + delivery (`Ref #6617`)

> **CANCELLED — 2026-07-20, by operator decision.**
> PR C is cancelled outright. It was previously HELD by the operator ruling of the same date;
> that hold is now superseded by cancellation. The authoritative ruling and its full rationale
> live in `decision-challenges.md` § "Follow-on ruling — 2026-07-20: PR C is CANCELLED" (the
> parent § "Operator Ruling — 2026-07-20" above it still reads "PR C: HELD, not cancelled" — that
> is the superseded text). The session narrative is § "Closing entry (2026-07-20): PR C cancelled"
> in `knowledge-base/project/specs/feat-one-shot-6617-inngest-liveness-marker-registry-probe/session-state.md`
> — note the full path: a sibling spec dir whose name also ends in `6617` has a same-named file.
>
> In short: PR C's discriminators exist to distinguish states of a **dark** host, so their useful
> life is bounded by the pre-cutover window — and they cannot be delivered inside that window at
> acceptable risk, because delivery force-replaces the sole production Inngest scheduler days
> before the cutover they were built to instrument. The diagnostic question they were built to
> answer is already settled on four independent measures (see the ruling).
>
> **The phase bodies below are retained deliberately as the record of what was designed.** They
> are NOT live work. Do not action them, and in particular do not dispatch
> `apply_target=inngest-host-replace`.

### Phase C0: Preconditions — CANCELLED (2026-07-20)

- [ ] C0.1 Re-run the Better Stack Premise Validation queries; if the probe now returns rows,
      **STOP** — the host was replaced and the marginal-cost argument is void
- [ ] C0.2 Confirm the flip-guard state-file seam (`/run` writable at `ExecStartPre`;
      `GUARD_POSTGRES_URI` / `GUARD_FLIP_FLAG` fixtures usable in CI)
- [ ] C0.3 Resolve the current latest `vinngest-v*` tag — **do not bake a literal**
- [ ] C0.4 Capture the **outgoing** pinned digest as the rollback target; record in the PR body
- [ ] C0.5 Re-verify the C4 enumeration against all three `.c4` files
- [ ] C0.6 Re-run the open code-review overlap query

### Phase C1: RED — CANCELLED (2026-07-20)

- [ ] C1.1 §A4 tests: probe emits `sdk_url=`, `backend_is_prod=`, `registry_count=` in the
      **same** logger call — scoped to the `PROBESCRIPTEOF` heredoc `:459-520`
      (whole-file greps return 2 for the logger call and 35 for `doppler`)
- [ ] C1.2 Purity test: probe body contains **no** `/proc` read and no `INNGEST_POSTGRES_URI`
- [ ] C1.3 Flip-guard tests: writes the state file; still never echoes the URI (AC-NOBODY);
      both prod-marker and dark-ref fixture cases
- [ ] C1.4 Degradation tests: absent file → `unknown`; prior-boot file → `stale`
- [ ] C1.5 Second-channel test: `inngest-boot-phone-home.sh` call at `:517` mirrors all three fields

### Phase C2: GREEN — the marker — CANCELLED (2026-07-20)

- [ ] C2.1 Flip-guard writes `is_prod` to the state file alongside its existing logger line
- [ ] C2.2 Probe reads the state file (same pattern as `image_ref` ←
      `/etc/default/soleur-inngest-image`) → `backend_is_prod=yes|no|stale|unknown`
- [ ] C2.3 `sdk_url` from `systemctl show -p ExecStart` (mirrors `derive_durability_state()`),
      control characters sanitized
- [ ] C2.4 `registry_count` via a second loopback `/v0/gql` curl — `grep -c` on function IDs,
      **never** import jq (the probe is `#!/bin/sh` and deliberately jq-free)
- [ ] C2.5 Extend the **single** logger call; mirror into the second channel
- [ ] C2.6 Confirm no `if` precedes the emit (ADR-117); `LOG_TAG` remains a real assignment
- [ ] C2.7 C1 tests green

### Phase C3: Deliver the artifact (#6539 gate) — CANCELLED (2026-07-20)

- [ ] C3.1 Push the tag resolved in C0.3
- [ ] C3.2 Resolve the published digest; verify from ≥2 independent sources
- [ ] C3.3 Bump **all four** pin sites
      - [ ] C3.3.1 `cloud-init-inngest.yml:390` — tag **and** digest
      - [ ] C3.3.2 `cloud-init.yml:699` (`IREF`)
      - [ ] C3.3.3 `cloud-init.yml:705` (`ZIREF`)
      - [ ] C3.3.4 `inngest-bootstrap.sh:492` (comment literal)
- [ ] C3.4 Note the red-`main` window in the PR body (tag push fails the web-pin assertion at
      `cloud-init-inngest-bootstrap.test.sh:234` until merge — tags are repo-global)
- [ ] C3.5 Assert the pinned image byte-equals the tree: `docker cp … | tar -xOf - | diff -`
      then `docker rm` (not bare `tar -xO`; not `grep -c`)
- [ ] C3.6 Promote C3.5 into `cloud-init-inngest-bootstrap.test.sh` as a **permanent** gate
- [ ] C3.7 Add the **cross-file** pin assertion (existing AC6b binds to `cloud-init.yml` only)

### Phase C4: ADR + full suite — CANCELLED (2026-07-20)

- [ ] C4.1 ADR-100 `## Amendment` — the three-step delivery invariant
- [ ] C4.2 Full infra suite, including the orphan suites: `journald-config.test.sh`,
      `vector-pii-scrub.test.sh`, `cloud-init-inngest-bootstrap.test.sh`

### Phase C5: Post-merge delivery (dark window) — CANCELLED (2026-07-20)

- [ ] C5.1 Verify `INNGEST_HEARTBEAT_URL` absent from `soleur-inngest/prd` (direct check)
      **and** #6348 unmerged (corroborating). If merged → **STOP**, re-plan
- [ ] C5.2 Confirm the flip-FSM tolerates a cold state slot
      (`/var/lock/inngest-cutover-flip.state` dies with the root disk)
- [ ] C5.3 **CANCELLED — DO NOT DISPATCH.** `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason="…"`
- [ ] C5.4 Verify `hcloud_volume.inngest_redis` re-attached
- [ ] C5.5 Verify delivery: probe row expected ~90 s post-boot; **absence at T+10 min is a real
      failure**; query **with the archive arm**; on absence read the Vector-independent
      `inngest-boot-phone-home.sh` channel
- [ ] C5.6 **CANCELLED — DO NOT DISPATCH.** On failure: re-pin to the C0.4 digest and re-dispatch
- [ ] C5.7 Enroll the **delivery** gate in `scripts/followthroughs/` + `follow-through` label
- [ ] C5.8 File the root-debt issue: no in-place redelivery channel for the dedicated host
      (the web host has one via `ci-deploy.sh:2758-2891`)

### Phase C6: Close out #6617 — CANCELLED (2026-07-20)

- [ ] C6.1 Confirm C-AC-D1..D4 hold
- [ ] C6.2 Post the measured row to #6617 as the H4 answer
- [ ] C6.3 Branch: `backend_is_prod=yes` **or** non-empty doublefire → **do not close**,
      escalate to a double-scheduler incident
- [ ] C6.4 Branch: `stale`/`unknown` → **do not close**; fix the state-file path
- [ ] C6.5 Otherwise close #6617
- [ ] C6.6 Verify #6608 separately post-replace (rides along, closed on its own evidence)
- [ ] C6.7 File the companion issue: cron send-path idempotency (see decision-challenges.md T-4)
