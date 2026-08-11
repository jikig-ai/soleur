# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-10-fix-preflight-check-10-probe-verb-allowlist-plan.md
- Status: complete (plan v2 — v1's authority control was falsified by measurement during the review panel)

### Errors
Two self-inflicted analysis errors, both caught before the plan froze:

1. **Proxy-vs-invariant, twice.** The first credential probe measured `doppler configure get token`'s
   *exit code* (0 even with no token) and read as "credential still reachable". The correction
   measured token length plus a live read — which then measured *credential discovery* and was
   presented as *credential reachability*. Only the review panel's challenge plus a direct
   absolute-path read (`wc -c < ~/.doppler/.doppler.yaml` returns the live 294-byte token
   regardless of `$HOME`) exposed it. An ephemeral `$HOME` changes where a CLI *looks*, not what
   is *readable*.
2. **A circular trust argument.** v1 justified allowlisting `bash <tracked-path>` on the grounds
   that a tracked script "passes the same PR review as the plan file". `git ls-files` interrogates
   the PR-head index — the attacker's own branch — and preflight runs before merge. The oracle was
   dropped entirely.

No tooling or pipeline errors. All five deepen-plan halt gates passed; all cited rule IDs active;
all 12 cited issue/PR numbers resolved live.

### Decisions
- **Authority is a filesystem boundary, not an environment tweak.** bwrap sandbox: repo read-only,
  `/home` `/root` `/run` as tmpfs, resolver bound for DNS, fail-closed to SKIP with no unsandboxed
  fallback. Measured against all four bypass classes (absolute-path read, glob, D-Bus keyring
  socket, `.git/hooks` write-back escalation).
- **The bash crux resolves by removing credentials, not by inspecting scripts.** A static scan of
  wrapped scripts is defeatable and would read complete while being incomplete — the worst property
  for a security control. Under the sandbox, a script that self-wraps `doppler run` fails loudly
  instead of succeeding silently.
- **Allowlist cut from ~40 verbs to 11**, derived from a measured 632-command corpus. `awk`, `sed`,
  `find` excluded after verifying `awk 'BEGIN{system(...)}'` executes arbitrary commands past the
  existing shell-active reject; inline-program flags (`-c`/`-e`) rejected on every runtime.
- **Three declaration fields collapsed to one** (`credentials_required`), deleting a whole FAIL
  state, a fixture, two ACs and two parity keys, and reusing existing placeholder machinery.
- **`--proc /proc` must degrade, not fail.** Without the retry, the fail-closed design would
  silently SKIP Check 10 in every containerized run — including this pipeline's own — while looking
  like correct operation.
- **Declined the recommended PR split**, recorded as DC-1 in `decision-challenges.md`: #7393
  requires both halves, and shipping the sandbox alone would leave credentialed probes failing
  opaquely.

### Components Invoked
- `Skill: soleur:plan`, `Skill: soleur:deepen-plan`
- Review panel (parallel): `kieran-rails-reviewer`, `architecture-strategist`,
  `code-simplicity-reviewer`, `spec-flow-analyzer`
- `Explore` agent (C4 model enumeration across `model.c4` / `views.c4` / `spec.c4`)
- `gh` CLI (issue/PR/label resolution), `git`, `bun test` (83-pass baseline), `bwrap` 0.11.1,
  `strace`, `python3 scripts/lint-agents-rule-budget.py`
- Deepen-plan gates 4.4, 4.6, 4.7, 4.8, 4.9, 4.10

## Collision Gate (re-probe after planning)
- Plan target `issue: 7393` matches the invoked ref — no new target introduced by planning.
- `#7393` OPEN, `closedByPullRequestsReferences` empty.
- PR #7343 surfaces on both `linked:issue` and the body probe, and MERGED mid-session. It closes
  #7278, not #7393, and its diff does not touch `plugins/soleur/skills/preflight/SKILL.md`.
  #7393 is the deferral #7343's ship filed, which is why it remains OPEN. Citation, not collision.
- Merged `origin/main` (post-#7343) into this branch before `/work`; preflight SKILL.md unchanged
  on main since the branch base, so no rebase hazard for this change.
