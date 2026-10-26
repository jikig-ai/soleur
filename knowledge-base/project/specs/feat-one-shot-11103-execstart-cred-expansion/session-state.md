# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-26-fix-inngest-execstart-inner-bash-credential-expansion-plan.md
- Status: complete

### Errors
- Plan/deepen ran in a Devin CLI subagent with no nested-agent tool: all fan-outs executed inline; `git commit` was false-denied (`.cwd` envelope omission) so the parent committed the planning artifacts.
- Technical rulings were written `pending - assumed` during planning, then resolved by ONE batched `soleur:engineering:cto` spawn (cto_spawns=1) — all 9 rows ruled, gate PASS.

### Decisions
- Site 1 (`inngest-redis.service`): aclfile delivery — bound `--only-secrets INNGEST_REDIS_PASSWORD` ExecStartPre runs a refusal-first acl writer (0600 on /mnt/data/redis); ExecStart drops doppler run + bash -c entirely.
- Site 2 (rendered `inngest-server.service`): resolve-after-refusal via rendered `inngest-server-launch.sh`; `@@BACKEND_FLAGS@@` stays on unit argv (durable sentinel for 4 consumers); `@@BACKEND_ENV@@` moves inside the script.
- Corpus stage in `doppler-injection-bound.test.sh`: flags plain `$VAR`/`${VAR}`/`$${VAR}` inside `bash -c` bodies, resolves `@@SENTINEL@@` fragments, excludes `${!...}`.
- Discovered: second expansion site at inngest-bootstrap.sh:1747 (INNGEST_REDIS_URI) now in scope; vinngest pin is v1.1.61 not v1.1.59.

### Components Invoked
- soleur:plan, soleur:deepen-plan (inline in subagent)
- soleur:engineering:cto (binding ruling, one batched spawn)
- technical-ruling-gate.sh --branch: PASS (9 rows)

### Agent ledger
- cto_spawns=1
