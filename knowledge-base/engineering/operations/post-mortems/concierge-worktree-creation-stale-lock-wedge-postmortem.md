---
title: "Concierge worktree creation permanently wedged by a stale .git/config.lock"
date: 2026-07-01
severity: high
status: resolved
brand_survival_threshold: single-user incident
art_33_notifiable: false
art_33_rationale: "Availability-only incident (worktree creation blocked). No personal data was accessed, altered, lost, or disclosed — the failure was a config-write lock, not a data-plane event. GDPR Art. 33 breach-notification clock does not start."
art_34_notifiable: false
art_34_rationale: "No high-risk to data subjects' rights/freedoms — no personal-data exposure. Art. 34 individual notification not triggered."
originating_incident: knowledge-base/engineering/operations/post-mortems/2026-07-01-concierge-bwrap-seccomp-sdk-0-3-outage-postmortem.md
remediation_pr: 5880
followup_remediation_pr: 5932
followup_tracker: 5912
---

# PIR: Concierge worktree creation wedged by stale `.git/config.lock`

## Summary

After the 2026-07-01 seccomp outage
([postmortem](2026-07-01-concierge-bwrap-seccomp-sdk-0-3-outage-postmortem.md)),
affected Concierge workspaces could no longer create git worktrees. Every attempt
failed with `could not lock config file .git/config: File exists`. Because worktree
creation is the first thing every `/soleur:go` session does, the workspace was
**permanently unusable** — the tenant could do no work at all.

This is a distinct, remediation-worthy failure mode from the originating seccomp
outage: the outage *created* the condition, but the *permanence* was caused by a
separate latent gap — **no stale-git-lock cleanup existed anywhere in the worktree
tooling**, so a lock left by a killed git process persisted on the mounted
`/workspaces` volume indefinitely.

## Impact

- **Scope:** any Concierge workspace whose git process was killed mid-config-write
  during the seccomp outage window (before #5874 restored git).
- **User-facing effect:** worktree creation — the first action of every session —
  failed permanently; the workspace was wedged until an operator manually deleted
  the lock over SSH.
- **Data:** none. Availability-only; no personal data accessed/altered/lost/exposed
  (see Art. 33/34 frontmatter rationale).

## Root Cause

1. The seccomp outage killed every `git config` / `git worktree add` mid-write
   (`unshare` EPERM), leaving `.git/config.lock` on disk.
2. Git's atomic-write protocol (`config.lock` → rename over `config`) treats a
   pre-existing `config.lock` as EEXIST: `could not lock config file … File exists`.
3. **The lock persisted on the mounted volume after git was restored** (#5874), so
   every subsequent config write failed forever.
4. **Latent gap:** no code path swept stale git locks — not `worktree-manager.sh`,
   not the session-start preamble, not the git-data provisioner.

Misdiagnosis note: the in-sandbox agent's debug stream attributed the failure to a
bind-mounted `.git/config`. That was wrong — the sandbox binds the whole workspace
read-write; the cause was the stale lock. Verifying against the sandbox code + git
error semantics found the real cause. Captured in
`knowledge-base/project/learnings/bug-fixes/2026-07-01-git-eexist-file-exists-is-stale-lock-not-mount.md`.

## Resolution

PR #5880 added an age-guarded `sweep_stale_git_locks()` to
`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`, called from
`ensure_bare_config()` before its first config write. It removes `config.lock` /
`config.worktree.lock` older than 60s (age-guard prevents clobbering a live
sub-second writer; clock-skew guard preserves future-dated locks). Because
`ensure_bare_config` runs on every create path AND the session-start
`cleanup-merged` path, an affected workspace **self-heals on its next session** —
no operator SSH required.

## Detection & Prevention

- **Detection (prod):** the original EEXIST error reappears in the `/soleur:go`
  debug stream if the sweep ever fails to clear a lock (it is its own alert — the
  surface has no server-side telemetry, by design).
- **Prevention:** the sweep is now a permanent chokepoint; the
  `stale-lock-sweep.test.sh` suite pins removal, preservation, clock-skew, scope
  (config-locks-only), and the black-box wiring through `ensure_bare_config`.

## Update (2026-07-03): confirmed root cause + targeted fix (#5912, PR #5932)

The #5880 sweep resolved the **stale-regular-lock** class above, but the Concierge
workspace continued to wedge. #5907 instrumented the sweep to self-report the lock's
true nature on a blind surface, and a real wedged `/soleur:go → /soleur:one-shot`
session finally emitted the forensic (recorded on #5912):

```
SOLEUR_GIT_LOCK_UNREMOVABLE file=config.lock type=other errno=none reason=non-regular-lock
```

The wedged session's own `ls -la` resolved `type=other` to a **character device**.

**Confirmed root cause (distinct from, and coexisting with, the stale-lock class):**
`.git/config.lock` in the Concierge agent-sandbox is materialised as a **masked
character-device node** by the sandbox filesystem/masking layer — it is NOT a stale
git lock (git only ever creates `config.lock` as a regular file via
`open(O_CREAT|O_EXCL)`). This **falsifies the seccomp-stale-lock hypothesis for this
environment**: the node is not a leftover from a killed writer, it is a persistent
mount/masking artifact. The #5880 sweep **correctly** refused to remove it
(non-regular → `UNREMOVABLE`) and failed loud — but that left worktree creation wedged
with no in-sandbox self-heal, because every `git config` write still hit `EEXIST`
against the device node.

**Targeted fix (PR #5932):** `ensure_bare_config()` now routes every config mutation
through a new `atomic_git_config()` helper that, when `config.lock` is non-regular
(wedged), writes **losslessly** — `cp -p config <same-dir temp>` → `git config --file
<temp>` (git creates a *clean* `<temp>.lock`, a distinct path the mask does not cover)
→ atomic `mv -f <temp> config`. Setting `extensions.worktreeConfig=true` this way
steers the subsequent `git worktree add` onto per-worktree config, so it never needs
the masked shared `config.lock` (empirically verified on git 2.53). The stale-lock
sweep still runs for diagnostics + stale-regular removal. A new
`SOLEUR_GIT_LOCK_TEMP_WEDGED` sentinel fires if even the clean temp lock cannot be
written — the diagnostic signal that would confirm the sandbox masks `*.lock` as a
**glob** (the fix's one remaining assumption; the durable platform fix is #5934).

## Action Items & Follow-ups

| Issue | Item | Status |
| --- | --- | --- |
| #5934 | Durable platform fix: stop the Concierge sandbox mount/masking layer from materialising a character-device at `.git/config.lock` (removes the provenance; the repo-side lockless writer is the in-session mitigation). | open |
| #5912 | Root-cause PIR + targeted fix (this update + PR #5932). | closing with PR #5932 |
