# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-inngest-oauth-probe-jwt-decode/knowledge-base/project/plans/2026-05-29-fix-probe-octokit-jwt-decode-pkcs8-canonicalization-plan.md
- Status: complete

### Errors
None. CWD verified at step 0 (matched the worktree). All deepen-plan hard gates passed (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shaped). All KB citations, rule-ids, commit attributions, and line refs verified live.

### Decisions
- Root cause (verified against primary source, not memory): the probe path delegates JWT signing to `universal-github-app-jwt@2.2.2`, whose Web-Crypto `getDERfromPEM` + `importKey("pkcs8", …)` is fragile to CRLF line endings and rejects PKCS#1 — producing GitHub's opaque "could not be decoded". Sibling `github-app.ts` works because it uses Node's format-tolerant `crypto.createSign`.
- Rejected the framing's leading hypothesis as sole cause: the `\n`-normalization divergence is real but the lib already does `replace(/\\n/g,'\n')` internally; the fix subsumes it.
- Fix is canonicalization-before-handoff: a `normalizeAppPrivateKey()` helper using `createPrivateKey(pem).export({type:"pkcs8",format:"pem"})` to emit a clean LF PKCS#8 PEM before `new App()` — minimal, stdlib-only, no library fork.
- Explicitly avoided repeating prior diagnostics-only work (#4568 c02cd36e) and the wrong-path margin tweak (#4565 c43da45b); both preserved as fallback signal, not removed.
- Blast radius widened: the shared `createProbeOctokit` factory feeds `cron-bug-fixer`, `_cron-shared`, and roadmap/strategy crons, so the single-site fix covers all App-JWT-minting crons.

### Components Invoked
- Skill: soleur:plan, soleur:deepen-plan
- WebFetch (verified universal-github-app-jwt@2.2.2 source from npm)
