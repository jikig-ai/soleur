# Session State

## Plan Phase

- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-pdf-concurrency-tmpfs/knowledge-base/project/plans/2026-04-18-perf-pdf-concurrency-gate-and-tmpfs-plan.md
- Status: complete

### Errors

None. One plan-breaking issue was caught during deepen pass (Docker `--tmpfs` applies `noexec` by default, which would silently break git credential helpers at `/tmp/git-cred-<uuid>`). Fixed in the plan before implementation: flag set corrected to `rw,nosuid,nodev,size=256m` and a negative test assertion added in `ci-deploy.test.sh`.

### Decisions

- Package both issues (#2472 concurrency gate, #2473 tmpfs) into a single PR — same mental surface (PDF linearization path × /tmp pressure).
- Concurrency gate implemented as inline async semaphore in `server/pdf-linearize.ts` (no `p-limit`/`p-queue` dep) — aligns with `mapWithConcurrency` precedent in `server/kb-reader.ts`.
- tmpfs flags: `rw,nosuid,nodev,size=256m`; `noexec` deliberately OMITTED (git credential-helper `!` prefix form requires exec).
- Three `docker run` insertion sites: ci-deploy.sh canary + production swap, plus cloud-init.yml bootstrap for fresh-provisioned servers.
- Pool size default 2, env-overridable via `PDF_LINEARIZE_CONCURRENCY` clamped to [1, 16]; slot acquired around `writeFile + runQpdf + readFile` only.

### Components Invoked

- `soleur:plan` (Phase 1 — plan creation)
- `soleur:deepen-plan` (Phase 2 — research, live-Docker validation)
- Live Docker 29.4.0 verification of tmpfs flag semantics
- `gh issue view` for #2472 / #2473 / PR #2457 context
- `markdownlint-cli2 --fix`
