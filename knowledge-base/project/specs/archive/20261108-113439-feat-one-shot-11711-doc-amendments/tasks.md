# Tasks — feat-one-shot-11711-doc-amendments

Plan: `knowledge-base/project/plans/2026-11-08-docs-key-rotation-dispatch-ruling-amendments-plan.md`
Issue: #11711 (Ref only — this PR does NOT close the epic; PR body must say `Ref #11711`).

Canonical ruling wording to quote verbatim (never paraphrase):

> An agent may dispatch `key-rotate.yml` / `inngest-key-rotate.yml` `rotate`|`converge` ONLY under a
> fresh, per-command, in-session owner go naming the exact full command; the reviewer click on the
> `key-rotate-approval` environment (approver: deruelle) is NEVER delegated; the approval tap should
> land inside a measured release-quiet stretch — the apply path re-checks in-flight runs itself, so
> a run parked at `approve` CAN still refuse post-approval.

Environment split (live-verified 2026-11-08): `rotate`/`converge` park at `key-rotate-approval`
(required reviewer `deruelle`, main branch policy); `mode=plan` and the apply path
(`apply`/`clear`; `apply1`/`reboot`/`apply2`) bind `infra-privileged` (branch policy, zero required
reviewers, no park). `guard`/`redeploy`/`notify` bind no environment.

## 1. Phase 1 — ADR amendments

- [x] 1.1 Amend `ADR-307-inngest-key-rotation-route.md` Decision item 6 (`:51`) in place — replace
  "agents never dispatch `rotate` or `converge`" with the ruling; keep the retained parts
  (confirm/`quiet_window` are typo-guards, a go on another issue does not count, `S5-A5-DONE`
  never agent-posted). Append a dated 2026-11-08 amendment note under the existing
  `Ruled by CTO agent, 2026-10-29` block.
- [x] 1.2 Amend `ADR-317-…-inngest-route.md` G6/H2 final sentence (`:103`) in place; extend the
  dated `Amendment (2026-11-05, #11923 + #11920)` paragraph with a 2026-11-08 amendment line.
  Leave the PAT-dispatch/PAT-approval residuals untouched.

## 2. Phase 2 — Runbook amendments + environment split

- [x] 2.1 `key-rotation.md`: replace `:36` with the ruling; update `:92` command-shape intro and
  the `:181` `actor_not_owner` next-action cell; in the `key-rotate-approval` section state the
  env split explicitly and add the release-quiet approval-tap + post-approval in-flight re-check
  guidance. KEEP `:243` as-is.
- [x] 2.2 `inngest-server.md`: amend sites `:1713-1714`, `:1717-1718`, `:1757` (A5 row), `:2115`,
  `:2117`, `:2178-2180`, `:2181-2183`, `:2143`, `:2251` per the plan's stale-claim inventory;
  correct the `infra-privileged` "required-reviewer" claim to branch-policy/zero-reviewer; use
  `*Superseded 2026-11-08:*` quoting where the file's convention applies. KEEP `:2130`, `:2238`,
  `:1721` byte-unchanged.
- [x] 2.3 (optional) `model.c4` micro-edit: edge `:596` one-clause note that the parked dispatch
  may be owner- or agent-initiated under the go; edge `:814` "its apply job alone" → "its apply
  and clear jobs". If taken: run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

## 3. Phase 3 — Workflow headers

- [x] 3.1 `.github/workflows/key-rotate.yml` header (lines ~5-15): carry the ruling, the
  never-delegated click, the release-quiet tap; keep `THE ORDER` env naming consistent.
- [x] 3.2 `.github/workflows/inngest-key-rotate.yml` header (lines ~4-10): same amendments.

## 4. Phase 4 — Runtime-prose consistency sweep (inferred scope)

- [x] 4.1 `scripts/inngest-key-rotate.sh`: `:30` comment, `:557` and `:561` stop-sentence `printf`s —
  replace `(no agent runs it…)`; keep "the owner's own per-command go" phrasing load-bearing.
  KEEP `:1137` (DONE-line rule) unchanged.
- [x] 4.2 `scripts/key-rotate.sh`: `:295` comment.
- [x] 4.3 `scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh`: `:6`, `:13` comments and the
  `:310` owner ask — keep "your go in a session that names the exact line"; replace the
  "only you dispatch it / no agent runs it" claim.
- [x] 4.4 `scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh`: update expectations
  `:302`, `:308` to the amended strings.
- [x] 4.5 If `SOURCED_PIN` (key-rotate-workflow.test.sh B27) reddens, re-derive it against the
  edited sourced bodies and update with a note — never hand-edit to silence.

## 5. Phase 5 — Verification

- [x] 5.1 Run the AC1 grep across all amended surfaces; expect zero matches outside
  `*Superseded*` markers.
- [x] 5.2 `bash scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh` — green.
- [x] 5.3 `bash apps/web-platform/infra/key-rotate-workflow.test.sh` and
  `bash apps/web-platform/infra/inngest-key-rotate-workflow.test.sh` — green.
- [x] 5.4 `gh api repos/jikig-ai/soleur/environments/key-rotate-approval` and
  `.../infra-privileged` — confirm the doc env-split claims still match live state.
- [x] 5.5 Verify PR body says `Ref #11711`, never `Closes #11711`.
