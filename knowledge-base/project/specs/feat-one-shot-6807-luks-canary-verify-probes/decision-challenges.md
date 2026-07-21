# Decision Challenges — feat-one-shot-6807-luks-canary-verify-probes

Persisted at plan time because this ran headless (one-shot pipeline, no TTY). `ship` renders these into the PR body and files an `action-required` issue. Each is a place where the plan **diverges from the operator's stated direction**, or where a taste call materially changed the deliverable's shape. The operator's direction is the default — these are surfaced, not silently applied.

---

## 1. User-Challenge — `readyz ready=true` does not answer the question the brief asked it to answer

**Operator's stated direction:** *"verify must additionally assert `/internal/readyz` ready=true … whether the repointed volume is actually populated is currently UNVERIFIED — this fix is what closes that open question."*

**What the code says:** `apps/web-platform/server/readiness.ts:81` —

```ts
const workspaces_populated = countWorkspaceDirsAt(root) > 0;
```

`workspaces_populated` is **"at least one directory exists"**, and `isWorkspacesWritable` (`:54-60`) write+unlinks **one** probe file at the root. A cutover that preserved 1 of 8 workspaces returns `ready=true`. So `readyz ready=true` proves a **floor** (mount present, writable, non-empty) — it does **not** prove the inventory survived, which is what "is the volume actually populated" means in context, and what the User-Brand Impact ("every user's checked-out repository missing") is about.

**What the plan did:** kept the `readyz` assertion exactly as directed, **and added** a host-side workspace-count assertion compared against the cutover's C1 `total` (8 for run `29782780158`), plus `persist_state WORKSPACES_COUNT` so future runs have a machine-checkable expected value. The plan states explicitly which assertion carries which claim.

**Why this is a challenge, not a silent fix:** it expands scope beyond the brief, and it changes what "verify passed" is allowed to mean in the runbook and ADR. Shipping `readyz`-only would have satisfied the brief's literal words while repeating — one hop later — the exact overclaim the brief itself cites (the `/api/health` → `/health` swap being the documented-insufficient fix).

**If the operator disagrees:** drop the count assertion and instead **narrow** the prose in the plan, ADR-119 §(a), the runbook §5, and the PR body so nothing claims inventory. Do not keep the broad prose with the narrow check.

---

## 2. Taste — two proposed artifacts were cut after review contradicted their premises

Both were in the first draft and both were removed. Recording because they were plausible readings of the brief's *"grep for any other `/api/health`-as-200 assertions"* and *"add regression coverage"*.

**(a) A repo-wide `/api/health`-as-200 CI gate — cut.** Review ran the proposed scope and found six live *legitimate* hits that the gate would red-light, including the existing gates' own grep patterns (`workspaces-luks-freeze.test.sh:233,313`), test fixtures, and `plugins/soleur/skills/postmerge/SKILL.md:103` — prose that *warns against* `/api/health`. Flagging the documentation of the fix is the worst false positive available. "As-200" is also a two-token proximity property a token grep cannot express.

*Replaced by:* extending the existing `AC7` grep from `$CUTOVER` to `$CUTOVER $VERIFY_WF` — same real-world coverage, one line, no exclusion machinery.

**(b) A new `workspaces-luks-verify-workflow.test.sh` — cut.** `workspaces-luks-freeze.test.sh:25` already carries a `WORKFLOW=` variable and already runs comment-stripped workflow greps (`:316-325`). The YAML-parse requirement was mis-imported from `workspaces-luks-cutover-workflow.test.sh:9-16`, whose header states its reason plainly: `${{ }}` **operand inversion**, which a grep cannot catch. The verify workflow's risk is a URL literal in a `run:` block — a grep is the correct instrument. Cutting it also removed a new CI wiring point in an at-budget job.

**If the operator disagrees:** both are additive and can be restored without reworking anything else.

---

## 3. Resolved, not open — recorded so it is not re-litigated

The strong-model consult recommended making the daily `luks-monitor` readyz assert **default-ON**, arguing the default-OFF flag "pays the full risk of editing an unattended script while buying zero continuous coverage."

That is sound reasoning from a false premise. `apps/web-platform/infra/luks-monitor.service:5` carries `RequiresMountsFor=/mnt/data`. In the ADR-119:234-240 reboot hazard `/mnt/data` is **not mounted**, so the unit never executes `ExecStart` — a default-ON daily assert would emit nothing in precisely the scenario the argument is about. The verify workflow runs the script as a **bare file** over SSH (`workspaces-luks-verify.yml:98`), with no unit and therefore no `RequiresMountsFor`, so the operator-dispatched path is the only one that can reach the check in that hazard.

Default-OFF stands, now for a stated reason. Captured as Sharp Edge 6 so a future reader does not re-derive the wrong answer from the same plausible premise.

---

# Work-phase divergences (added during `/work`)

Each was verified against code or live evidence rather than assumed, and each is a correctness fix
small enough to make inline rather than an architecture fork.

## 4. `readyz` answers **503** when not ready, not `200 + ready:false`

**Plan text.** The classifier table and task 1.4 specify `200 + "ready":false ⇒ readyz_not_ready`,
and place `503` in the generic RETRYABLE set.

**Code.** `server/readiness.ts` — `res.writeHead(readiness.ready ? 200 : 503, …)`. A not-ready host
answers **503**, so the plan's retryable set contained the exact status carrying the not-ready verdict.

**Why it mattered.** Implemented literally, a genuinely not-ready host would be retried for the whole
budget and then reported as `readyz_unreachable`/deadline — converting a real sole-copy data-loss
signal into a timeout. That is the same confidently-wrong verdict class as the 403-is-valid-JSON
Sharp Edge, one status code over.

**Decision.** readyz retries only while the response is UNCLASSIFIABLE (no response at all). Any
parseable answer, at either status, is terminal. `wl_http_class`'s generic retryable set is unchanged
and still correct for `/health`, where a 503 IS a booting container. Pinned by test T24b2.

## 5. The inventory baseline is written by the shared counter, not the fsck gate's `total`

**Plan text.** Task 5.5: `persist_state WORKSPACES_COUNT "$total"` at the C1 gate.

**Code.** `total` counts fsck-PROBEABLE workspaces — the loop `continue`s past every skipped one
(`worktree_pointer`, `alternates_escape`, `no_git_dir`) before incrementing. 2026-07-20 had
`skipped=0` so `total=8` coincided with the directory count, but `skipped` is explicitly transient
(#6754 records it moving 1 → 0 between rehearsals).

**Why it mattered.** The value STORED would be computed by a different rule than the value COMPARED.
On any future cutover with a nonzero skip the baseline persists LOW, and a later real shrink to that
low baseline certifies green — relocating the counter-parity bug from the counter to the baseline.

**Decision.** One function, `wl_count_workspace_dirs`, used by both the assertion and the persist.

## 6. `model.c4` / ADR-119 record plaintext-at-rest as CURRENT, not as stale

**Plan text.** Task 7.6: correct `model.c4:186`/`:410`, which "are stale; the cutover landed
2026-07-20".

**Measured reality.** The cutover landed and was undone ~27 minutes later by its own dead-man timer
(#6812). `/mnt/data` is mounted from raw `/dev/sdb` as of 2026-07-21.

**Why it mattered.** "Correcting" those descriptions to claim LUKS-encrypted-at-rest would have made
the architecture model **false about a live security property**, in the same direction as the
published privacy policy's existing overclaim. Removing a stale-looking claim that has become true
again is the "removing a false claim can strengthen the false claim" trap.

**Decision.** Both sites updated to state the accurate position — plaintext at rest as of 2026-07-21,
with the 2026-07-20 landing and its auto-revert recorded so the next reader does not mistake the
cutover's success for the current state. ADR-119 keeps `status: adopting`, which is correct.

## 7. Cutover sources the SHIPPED emit helper, not the installed one

**Not in the plan at all.** `workspaces-cutover.sh` resolved `EMIT=/usr/local/bin/…` first and the
shipped copy only as a fallback — the opposite of `luks-monitor.sh:29-30`.

**Why it mattered, specifically for the authorized re-cut.** `app_canary` now calls `wl_probe_http`
and `wl_probe_readyz`. A pre-#6807 installed copy does not define them, so the cutover would have
died on `command not found` at its last gate — reproducing the 2026-07-20 shape with a different
proximate cause. The cutover ships its own code; it must run its own code.

**Decision.** Precedence flipped, with the reasoning recorded at the line.

