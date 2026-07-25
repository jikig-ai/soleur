---
title: "fix-constraints recovery: two-stage pull_request→workflow_run privileged split"
status: accepted
date: 2026-07-01
supersedes_pr: 5804
amends: ADR-071
---

# ADR-074: fix-constraints recovery — two-stage `pull_request`→`workflow_run` privileged split

## Context

ADR-071 promised an agent-owned, founder-zero-touch recovery for a tripped L1 constraint-gate.
The first implementation (#5791, held in draft PR #5804) was `fix-constraints.yml`: an
`issue_comment`-triggered job that held `ANTHROPIC_API_KEY` + `contents: write`, checked out the
PR head (`gh pr checkout`), and **executed it** — `bun install --frozen-lockfile` (postinstall
scripts), the api-spend script, and `apps/web-platform/scripts/constraint-gates.sh`, all from the
PR head.

That workflow tripped **3 critical CodeQL `actions/untrusted-checkout-toctou` alerts**. The
author-association + collaborator-permission + head==base gates bounded *who* could trigger it, but
CodeQL keys on the **structural** sink: a privileged trigger that holds secrets/write executes
untrusted-PR-derived code. Targeted hardening (SHA-pin the checkout, `bun install --ignore-scripts`,
run the base-branch gate) does not clear it — as long as *any* `run:` executes head code with
secrets present, the rule stays red, and running the base gate defeats the feature (the gate logic
may be exactly what changed). The operator decision (2026-06-30) was **hold + redesign**, not
dismiss-and-merge: the gate is still informational (not a required check), so the founder-deadlock
is latent and there was no urgency.

The target user is a non-technical founder who can never hand-author or unblock a CI gate, so
recovery must stay automatic. The fix must be architectural.

## Decision

**PRIMARY DECISION — split the workflow so the write-capable stage never co-locates with untrusted
code execution.** This is the invariant a future reader must not break.

- **Stage A — `fix-constraints-stage-a.yml` (`pull_request`, UNTRUSTED, `contents: read` only).**
  Runs `bun install --frozen-lockfile --ignore-scripts` + the full `constraint-gates.sh` in the PR
  context with **no write token**. `pull_request` is CodeQL's designated *untrusted* context —
  running PR-head code here is the expected, safe thing. If the gate is red and a key is present
  (same-repo PR), it dispatches the **fix-only** agent, re-verifies the gate green, and uploads a
  **patch artifact** (full post-image file contents + per-file `sha256` + `meta.json`). No commit,
  no push, no repo-write scope.
- **Stage B — `fix-constraints-stage-b.yml` (`workflow_run`, PRIVILEGED, `contents: write` +
  `pull-requests: write` + `actions: read`).** Triggered by Stage A completion. GitHub **always runs
  this file from the default branch**, so its logic is trusted even when Stage A ran fork-controlled
  code. It downloads the artifact, validates it, builds the commit via the **Git Data API**, and
  opens a **draft follow-up PR**. It **never** `actions/checkout`s the untrusted tree, **never**
  `git apply`s, **never** runs `bun install` or any PR script.

**ENABLING MECHANISM — the Git Data API data-plane.** Stage A uploads the *full post-image contents*
of the changed allowlisted files (NOT a unified diff). Stage B reconstructs the commit purely from
those bytes: `POST /git/blobs` (`encoding: base64` of raw bytes) → `POST /git/trees` (with mandatory
`base_tree` at `head_sha`, every entry mode-pinned `100644`) → `POST /git/commits` (parent =
`head_sha`) → `POST /git/refs` (`soleur/fix-constraints/<pr>`). Because there is **no checkout step
to flag**, the `untrusted-checkout-toctou` sink is **structurally absent**, and the entire
hostile-diff-parser attack class (rename/symlink/`..` in a unified diff) dissolves. Frame the trigger
split as the decision; the Git Data API is *how it is realized*.

### The artifact is 100% attacker-controlled (load-bearing)

`pull_request` runs the **fork's own** Stage A definition from the PR head (unlike
`pull_request_target`, which runs the base's). A fork can therefore delete the agent/gate steps and
upload a hand-crafted artifact while keeping Stage A's `name:` so this stage still fires. **"Forks
get no key" protects spend/agent-execution only, NOT artifact integrity.** Stage B must treat the
artifact — contents AND `meta.json` — as fully untrusted. Its defenses:

1. **Explicit same-repo gate (the real fork defense).** Resolve the PR from the trusted
   `github.event.workflow_run.head_sha`; require `isCrossRepository == false` **and exactly one
   matching open PR** before any write. Fork / 0 / ≥2 matches → one comment + no-op.
2. **Routing identity from the EVENT, never the artifact.** `head_sha` comes from the event
   (validated `^[0-9a-f]{40}$`); `pr_number` (validated numeric) + `head_ref` are resolved by API;
   `meta.json` is cross-checked and any mismatch rejects.
3. **Positive-charset path allowlist, fail-closed.** Allow only
   `apps/web-platform/{app,components,server}/**` matching `[A-Za-z0-9._/-]`; reject `.github/**`,
   `*.cjs`, the runner, the baseline JSON, absolute/`..` paths, control chars, and symlink
   (`120000`)/gitlink (`160000`) modes. Any unmatched path rejects the WHOLE artifact.
4. **Resource bounds** (file-count / per-file / total size) before the blob loop (CWE-400).
5. **Byte-round-trip integrity.** Each blob's bytes are verified against the per-file `sha256` in
   `meta.json` before committing — "Stage A verified green" only holds for the committed tree if the
   bytes round-trip exactly, and there is no CI re-run to catch a drifted tree.

> "0 CodeQL alerts" proves the checkout sink is gone. It does **not** prove artifact-data-trust
> safety — the explicit gates above are what close that.

### Artifact schema (pinned — this IS an ADR-074 decision)

```
fix-constraints-patch-<pr>/
  meta.json   { pr_number:int, head_sha:string(40hex), head_ref:string,
                files:[{path:string, sha256:string(64hex)}], touches_baseline:false }
  files/<repo-relative-path>   # full post-image bytes of each changed allowlisted file
```

`touches_baseline` is **derived server-side** in Stage B and used as telemetry only — never read
from `meta.json` to gate anything.

### Auto-recovery is FIX-ONLY (baseline prohibition)

The agent can green a tripped gate two ways: genuinely fix the offending import, OR append the
violating edge to the suppression baseline (`--refresh-baseline`), which **whitelists a real
client→server-secret leak**. Baseline growth is the agent's path of least resistance, and a
label/banner is a no-op for a non-technical founder, so an auto-recovery that could grow the
baseline would routinely manufacture security-regression PRs routed to the least-able reviewer.
Therefore `.dependency-cruiser-known-violations.json` is excluded from **both** the Stage A artifact
allowlist AND the Stage B path allowlist. A baseline-mutating recovery produces an out-of-allowlist
path → Stage A aborts the artifact → Stage B no-ops → the deadlock persists, surfaced as "this gate
needs a maintainer — possible real leak." Failure asymmetry favors this: over-blocking costs the
status-quo deadlock; under-blocking ships a secret to the browser bundle. Baseline growth stays a
maintainer-only local `constraint-scaffold --refresh-baseline`.

### No terminal state is silent — the give-up marker

The founder must never be left silently deadlocked (a red gate with no PR feedback is the exact
failure this feature exists to prevent). Stage A produces a recovery patch *only* when it ships an
in-scope fix, so the give-up cases (no key, agent made no edit, still red after the attempt, or
greened via an out-of-scope path) would otherwise leave Stage B with nothing to comment on. Stage A
therefore emits a **second artifact type** — `fix-constraints-giveup-<pr>` (`meta.json` =
`{pr_number, head_sha, reason}`) — whenever the gate was RED but no recovery patch shipped. Stage B,
seeing a give-up marker and no recovery patch, resolves identity from the trusted `head_sha` and
posts exactly one deterministic "a maintainer needs to review this gate" comment (or the fork
message for a cross-repo PR). No marker is emitted when the gate was already green (nothing tripped →
no comment, no spam on healthy PRs). This give-up path only reads + comments — it never touches the
write token.

### Concurrency keying (accepted bounded staleness)

Stage B's `concurrency.group` is keyed on `github.event.workflow_run.head_sha`, not `pr_number` —
`pr_number` is resolved by an in-job API call and is not available at workflow-level `concurrency`
evaluation. Consequence: two Stage A completions on the *same PR* at *different* head SHAs can both
force-update the single `soleur/fix-constraints/<pr>` bot branch, so a slower stale-SHA run may leave
it at an older fix. Bounded and non-security: the branch is a human-reviewed **draft** PR, each Stage
B commit is rebuilt fresh on `base_tree` = its own `head_sha` (no stale accumulation), and Stage B
refuses to force-overwrite a branch whose tip is a **non-bot** commit (a maintainer's review commits
are never silently clobbered — it comments `branch-has-manual-commits` instead).

### UX change — comment trigger dropped; recovery is zero-touch

The `/soleur fix constraints` comment trigger is **removed**. Recovery becomes automatic on any PR
whose gate is red and auto-fixable, delivered as a draft follow-up PR. This is strictly better for
the #5791 founder-deadlock target and removes the entire comment-parse + author-association +
exact-match-command surface CodeQL flagged. Manual retry is preserved: `workflow_dispatch` on the
read-only Stage A, or simply push a commit to the PR.

### Follow-up PR delivery (no false provenance, no CI re-trigger dependency)

The fix lands as a **draft** follow-up PR (`soleur/fix-constraints/<pr>` → the original PR's head
ref), carrying `Ref #<pr>` (not `Closes`), no auto-merge label, and a human merge gate. A PR opened
via `GITHUB_TOKEN` triggers no CI (by design, anti-loop) — acceptable, because Stage A already
re-ran and verified the gate green and Stage B byte-verified the tree; the PR is a delivery vehicle,
not a green attestation. The body claims only what Stage B can attest (it applied an allowlisted,
byte-verified, same-repo artifact) — **never** "pre-verified green" (Stage B never ran the gate).
All Stage B output strings (PR body, comments, `::error::`) are sanitized as escape sequences
(`\x00-\x1f\x7f\x85`, U+2028, U+2029), never literal chars.

### Credential containment (accepted residual)

`ANTHROPIC_API_KEY` must run over untrusted code in Stage A by necessity (`--ignore-scripts` kills
the postinstall vector but does NOT stop the gate's own `.dependency-cruiser.cjs` from executing).
This is contained by a **capped, rotatable per-tenant Anthropic key with a hard spend cap** — the
exfil residual is bounded to spend. This credential surface is intentionally **outside the TF-only
provisioning principle (AP-001)**: there is no Terraform provider for Anthropic API-key minting, and
the Admin API cannot create keys (Console-only) or set regular-tier spend limits, so the mint is a
Console/Playwright or operator-with-evidence surface (see #5814 acceptance). **Distinct-SHA key-burn
vector:** Stage A's `concurrency` collapses only same-head-SHA runs; a multi-SHA push-storm can fan
out N agent dispatches, so the **spend cap — not concurrency — is the bound** on a push-storm.

## Alternatives Considered

| Approach | Verdict |
|---|---|
| Single-job `issue_comment` with job-level `permissions: {}` on the agent job | **Rejected.** CodeQL keys on the *trigger* being privileged (issue_comment carries secrets + grants write), not job-perm downscoping. Untrusted-checkout-in-privileged-trigger stays red. |
| SHA-pin + `--ignore-scripts` + base-branch gate (targeted hardening) | **Rejected.** Closes TOCTOU + postinstall but leaves untrusted-code-with-secrets execution → CodeQL stays red; the base gate defeats the feature. (SHA-pin + `--ignore-scripts` adopted as defense-in-depth in Stage A.) |
| Checkout head + `git apply` a diff in Stage B | **Rejected as primary.** Hostile diff-parser surface (rename/symlink/`..`); checkout-in-privileged-`workflow_run` may trip `untrusted-checkout-high` independent of execution. Git Data API (full post-image contents, no checkout) is the chosen primary — sink structurally absent. |
| Keep auto-recovery able to grow the baseline (segregate + heightened review) | **Rejected.** A label is a no-op for a non-technical founder; baseline-growth is the agent's path of least resistance → routine security-regression PRs. Auto-recovery is fix-only. |
| Egress-restricted self-hosted runner for Stage A | **Deferred** (Soleur-only, heavy). The capped key is the v1 containment. → tracking issue. |
| Comment→label→`pull_request:[labeled]` hybrid (preserves on-demand `/soleur fix constraints`) | **Deferred.** Preserves the #5791 comment UX with a CodeQL-clean labeling workflow, but adds a 3rd workflow. v1 ships zero-touch auto-recovery. → tracking issue. |

## Consequences

- The `untrusted-checkout-toctou` sink is structurally absent from the redesigned workflows; the
  post-merge 0-alerts query is the proof (requires CodeQL `actions` scanning, confirmed enabled).
- #5814 **supersedes #5804** — the held dispatcher + template + test exist only on that branch, so
  #5804 is closed (not merged) when #5814 merges.
- ADR-071's promote-to-required blocker drops the satisfied #5791 half; only #5778 remains.
- The two-stage split, artifact passing, data-only Git Data API commit, bot-branch follow-up PR,
  SHA-pin, `--ignore-scripts`, and path allowlist are vanilla GitHub primitives → emitted via
  `constraint-scaffold` for tenants. The capped per-tenant key + any egress-restricted runner are
  tenant-config / Soleur-only.
- **Novel pattern — scrutinize on change:** the Git Data API commit-creation (blob→tree→commit→ref,
  no checkout) has no prior in-repo precedent. `workflow_run` + `conclusion=='success'` does
  (`deploy-docs.yml`, `post-merge-monitor.yml`).
