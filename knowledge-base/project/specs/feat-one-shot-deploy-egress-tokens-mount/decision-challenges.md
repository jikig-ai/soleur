# Decision Classes - feat-one-shot-deploy-egress-tokens-mount

| Item | Class | Ruling |
|------|-------|--------|
| Does the canary docker run need the egress-tokens mount and/or SOLEUR_EGRESS_REAPER? | technical | Ruled by CTO agent, 2026-10-19: neither - canary serves probes only, runs beside live prod so a canary reaper would mass-revoke live tokens (server/index.ts gate, ADR-278 canary isolation); the closed set then pins canary absence. |
| Presence pinning design in docker-run-tuple.py (per-tuple required_* fields vs exact declared sets), and whether ports are included | technical | Ruled by CTO agent, 2026-10-19: make the declared volumes, env names and ports EXACT with one new arm and token MISSING_DECLARED; a second parallel spec would drift; keep the arm a separate function registered in one line to stay localized against draft PR 10501. |
| Should ci-deploy.sh ensure or verify the host token dir (sudo install or stat marker)? | technical | Ruled by CTO agent, 2026-10-19: no - server.tf owns the dir (mkdir, chown 1001:1001, chmod 0711), spawn failure is already mirrored to Sentry, a new sudo grant needs the root bridge and is out of scope. |
| Amend ADR-278 canary-isolation bullet in this PR? | technical | Ruled by CTO agent, 2026-10-19: yes, one sentence, no new ADR; the current wording calls the canary a second consumer of the token dir. |
| Brand-survival threshold for this change | technical | Ruled by CTO agent, 2026-10-19: single-user incident - the mount exposes live per-session gateway bearer credentials inside the multi-tenant container, the denyRead has never been live against a real mount, and a cross-tenant read hits one named user; require a sandboxed read/list-denied proof and run user-impact-reviewer at review. |
