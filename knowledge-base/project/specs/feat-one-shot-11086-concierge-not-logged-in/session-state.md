# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-29-fix-concierge-not-logged-in-friendly-error-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=0 in this main context (planning subagent ran 4 CTO rounds, rulings F1-F13 in decision-challenges.md)

### Errors
- Wireframe gate (deepen-plan 4.9) not mechanically satisfied: chat-surface.tsx matches the UI glob, no .pen committed (Pencil Desktop absent). Treated as pure-copy exclusion; recorded as a challengeable taste row. Confirm before ship.
- Operator's stored token not read (secret); shape unverified, plan covers both candidate shapes.

### Decisions
- Root cause reproduced locally: lease prefers operator-only anthropic_oauth row regardless of authMode; /api/keys stores it unvalidated; bundled CLI drops sk- values not matching sk-ant-(oat|sid)NN-<non-space> and replies "Not logged in · Please run /login" without using the value as a credential.
- Part 1: strict allowlist at save boundary (400) + lease guard fails closed (oauth_unusable), no fallback to API key.
- Part 2: both runners rewrite CLI auth-failure text to server-authored copy from closed match_kind + credential scheme; matcher extracted to permanent agent-auth-match.ts; raw message never mutated before matcher.
- PR uses Ref (not Closes) for #11086, #10455, #11085; follow-ups #11524, #11525.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; CTO, CPO, learnings-researcher, dhh/kieran/simplicity/architecture reviewers, spec-flow-analyzer, ux-design-lead.
