# Tasks — fix(sync): make plugin-owned executables reachable from a customer repo

Plan: `knowledge-base/project/plans/2026-08-11-fix-sync-plugin-root-anchoring-plan.md`
Issue: #7442 (`Closes`) · #6222 (`Ref` — **never** `Closes`)

> **Phase 0 is a hard gate.** Every task from Phase 1 onward is conditional on the H7
> measurement. Do not begin Phase 1 until 0.1–0.3 are recorded.

## Phase 0 — Blocking: root resolution + the decisive failing test

- [ ] 0.1 Measure whether `CLAUDE_PLUGIN_ROOT` is exported into the bash env when the
      agent executes a plugin-provided **command** in a marketplace install (not a plain
      session, not `hooks.json` substitution). Record the result verbatim in the PR body.
- [ ] 0.2 Bind the remedy to the plan's decision tree: (A) set → `${CLAUDE_PLUGIN_ROOT:?}`
      fail-closed, no `:-`; (B) unset → escalate, ship fail-closed halts + unsupported-surface
      message, do not ship a cosmetic prefix; (C) mixed → treat customer-facing paths as (B).
      **Invariant under all outcomes: no `:-` fallback into a customer-writable path.**
- [ ] 0.3 Write `tests/commands/test-sync-producer-reachability.sh` with the decisive cell
      FIRST and confirm it goes **RED**: customer CWD + `CLAUDE_PLUGIN_ROOT` unset + decoys
      planted at **both** `scripts/rule-prune.sh` and
      `plugins/soleur/scripts/write-kb-coverage.ts`. (`cq-write-failing-tests-before`)
- [ ] 0.4 Re-derive the 29 anchorable / 21 un-anchorable decomposition in the working tree.
- [ ] 0.5 Hard stop: confirm `scripts/rule-prune.sh:52` shows the `$SCRIPT_DIR/..` derivation.
- [ ] 0.6 Hard stop: confirm `grep -rn 'emit_incident' plugins/soleur/hooks/` prints nothing.
- [ ] 0.7 Confirm the vitest runner and `include:` globs so the guard's path is actually
      collected (`apps/web-platform/vitest.config.ts`); confirm `package.json scripts.test`.

## Phase 1 — Fix all 29 anchorable sites

- [ ] 1.1 Apply the Phase 0 form to the 6 `plugins/…` invocations in `commands/sync.md`.
- [ ] 1.2 Apply it to the remaining 23 sites across the other 18 files (`agent-finder`,
      `community-manager`, `cf-token-scope`, `drain-labeled-backlog`, `drain-prs`,
      `flag-bootstrap`, `flag-create`, `flag-delete`, `flag-list`, `flag-set-role`,
      `frontend-design`, `provision-{cloudflare,doppler,github,hetzner}`, `resolve-debt`,
      `ship`, `user-set-role`).
- [ ] 1.3 Verify zero `plugins/…`-targeted violations remain repo-wide.

## Phase 2 — TS producers: root form, data root, runnability

- [ ] 2.1 Apply the Phase 0 form to the 3 TS invocations in `sync.md` (194, 245, 252).
- [ ] 2.2 `write-kb-coverage.ts` (~:85): default root → git top level, fallback
      `process.cwd()` outside a repo; **preserve `--root`**.
- [ ] 2.3 `generate-c4-from-components.ts` (~:398): same; **preserve the positional arg**.
- [ ] 2.4 Add `--producer-unreachable <class>` to `write-kb-coverage.ts` +
      `plugins/soleur/lib/kb-coverage.ts` so the **same renderer** emits the degraded
      artifact **with a real `SOLEUR_KB_SYNC_PRODUCERS` line**. Do not hand-author it in
      markdown.
- [ ] 2.5 Do NOT regress the existing catch-block degraded write (`:88-112`).
- [ ] 2.6 Add a `command -v bun` precondition in `sync.md`; decide and document the
      `npx likec4` / network-absent behaviour for the `c4` area.

## Phase 3 — Relocate `domain-model-drift.sh`, sweep, fix standalone

- [ ] 3.1 Re-confirm `domain-model-lib.sh` still has exactly one code consumer.
- [ ] 3.2 `git mv scripts/domain-model-drift.sh plugins/soleur/scripts/`
- [ ] 3.3 `git mv scripts/lib/domain-model-lib.sh plugins/soleur/scripts/lib/`
      (never source the lib from repo root — that ships the same defect one level down).
- [ ] 3.4 Repoint executable callers: `preflight/SKILL.md:1338`, `review/SKILL.md:276`,
      `.github/workflows/scheduled-domain-model-drift.yml:11,56`,
      `plugins/soleur/test/domain-model-init.test.sh:26`,
      `plugins/soleur/test/domain-model-headless-append.test.sh:26`,
      `tests/commands/test-sync-domain-model.sh:9`, `scripts/domain-model-drift.test.sh:11`,
      and the 3 sync.md sites (331, 345, 375).
- [ ] 3.5 **Rewrite `tests/commands/test-sync-domain-model.sh`'s anchor-blind assertion** —
      `grep -qE 'scripts/domain-model-drift\.sh drift'` still matches the anchored literal,
      so today it neither breaks nor detects an un-anchoring regression.
- [ ] 3.6 Repoint doc citations: `ADR-076:27,28,96`, `ADR-129:22,68`,
      `domain-model.md:20`, `cron-domain-model-drift.ts:9` (comment),
      `audit-bot-codeql-coverage.sh:278`, `learning-retrieval-bench.sh:632`,
      `skill-freshness-aggregate.sh:186`. Exclude point-in-time records
      (`project/{learnings,plans,specs,brainstorms}/`, `**/archive/**`).
- [ ] 3.7 Wire `init` into the **standalone** `domain-model` contract (`sync.md:359-362`)
      so a fresh customer repo produces a register instead of `exit 2`.
- [ ] 3.8 Verify `cron-domain-model-drift.ts` is dispatch-only — verify, do not edit.

## Phase 4 — The guard

- [ ] 4.1 Create `apps/web-platform/test/plugin-root-anchoring.test.ts` modelled on
      `plugin-root-list-carveout-coupling.test.ts` (reuse `walkMarkdown()` + vacuity floor).
- [ ] 4.2 Predicate **constrains the fallback form**, not token presence — a closed set of
      sanctioned forms fixed by Phase 0.
- [ ] 4.3 Detection covers fenced blocks (**indent-aware** `^[[:space:]]*```) **and inline
      code spans**.
- [ ] 4.4 Vacuity floor tied to the expected site count, not `> 0`.
- [ ] 4.5 Mutation test (a): delete an anchor → RED.
- [ ] 4.6 Mutation test (b): replace an anchor with a `:-`-wrapped bare path → RED.
- [ ] 4.7 Document stated blind spots in-file: line continuations,
      `cd plugins/soleur && bash …`, unrecognised verbs, and shipped `.sh`/`.ts` being
      out of scope (axis 3/4 → deferral 6).

## Phase 5 — rule-prune: fail closed and de-advertise

- [ ] 5.1 Make the halt **executable in the emitted shell** (monorepo sentinel gate), not a
      prose instruction the model may skip.
- [ ] 5.2 Cover `sync.md:303` (`rule-metrics-aggregate.sh`) — it is instructed **first** and
      is the same collision class.
- [ ] 5.3 Specify the halt message literal so it is AC-checkable.
- [ ] 5.4 Remove `rule-prune` from `argument-hint` and `**Valid areas:**` (`sync.md:4,20`)
      and from `/soleur:help`.
- [ ] 5.5 Update `tests/commands/test-sync-rule-prune.sh` to assert the halt.
- [ ] 5.6 Decide + document standalone-area durability (extend the durable surface, or state
      standalone is stdout-only by design and route to `all`).
- [ ] 5.7 Leave `scripts/rule-prune.sh`, `rule-metrics-constants.sh`, `retired-rule-ids.txt`,
      `cron-rule-prune.ts` untouched.

## Phase 6 — ADR, principles register, C4

- [ ] 6.1 Mint the new ADR (payload boundary + root resolution on the self-hosted CLI);
      cross-reference ADR-093 §Consequences and #6222; add a one-line pointer in ADR-093.
- [ ] 6.2 Derive the ordinal with `scripts/check-adr-ordinals.sh` across **all `origin/*`
      refs**; **re-derive immediately before merge**; sweep plan + tasks + ACs on renumber.
- [ ] 6.3 Add an `AP-0NN` row to `knowledge-base/engineering/architecture/principles-register.md`.
- [ ] 6.4 Add a `selfHostedCli` element + producer-execution edge to `model.c4`.
- [ ] 6.5 **Check both edge endpoints are in the rendering view's include list** before
      adding the edge (`connectedRepoPlugin` is in `containers` not `components`; `sync` is
      in `components` not `containers`).
- [ ] 6.6 Run `c4-code-syntax.test.ts` + `c4-render.test.ts`; then
      `bash scripts/regenerate-c4-model.sh` and stage `model.likec4.json`.

## Phase 7 — Verification + close-out

- [ ] 7.1 `bash tests/commands/test-sync-producer-reachability.sh` — all cells green,
      including T0 (which was red at 0.3) and the subdirectory case.
- [ ] 7.2 `bash scripts/domain-model-drift.test.sh` green.
- [ ] 7.3 `bash scripts/test-all.sh` green — the authoritative exit gate.
- [ ] 7.4 Run every AC command in the plan's Acceptance Criteria; record outputs.
- [ ] 7.5 File the 7 deferral issues; comment the 21-site inventory on **#6222** (do not
      file a duplicate) noting the 29 anchorable sites are closed.
- [ ] 7.6 PR body: `Closes #7442`, `Ref #6222`, the H7 measurement, and the rendered
      `decision-challenges.md` (DC-1, DC-2).
