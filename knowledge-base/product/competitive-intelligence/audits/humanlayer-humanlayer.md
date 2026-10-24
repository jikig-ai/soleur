---
title: Peer-plugin audit — humanlayer/humanlayer (2026-10-24)
target: humanlayer/humanlayer
last_updated: 2026-10-24
publishable: internal
---

# Peer-plugin audit — humanlayer/humanlayer (2026-10-24)

Part of the [Competitive Intelligence index](../../competitive-intelligence.md). Dated record — index links are the live set; this shard is append-only.

### humanlayer/humanlayer

**Repo:** [humanlayer/humanlayer](https://github.com/humanlayer/humanlayer)
**License:** Apache-2.0 (vendored dirs MIT; `NOTICE`). **License-history caveat:** open → closed ("pretty much all deprecated" era) → entire core re-opened 2026-10-23. Third-party reporting indicates active development may have moved to `humanlayer/synclayer`; the audited `main` snapshot (the `apps/riptide-*` tree below) may lag the live codebase.
**Commit SHA at audit:** HEAD @ 2026-10-24 (default branch `main`, last push 2026-10-24)
**Audit date:** 2026-10-24
**Auditor:** soleur:competitive-analysis peer-plugin-audit (targeted single-repo audit; no six-tier rescan, no specialist cascade — Cofounder/Multica/Omnigent precedent)
**Soleur catalog snapshot:** 104 skills / 67 agents / 4 commands
**Stars / forks:** 12,344 / 999 (GitHub API, 2026-10-24)

**Product identification.** The repo is no longer a skill library; it is the **"Riptide" stack** — the product formerly named CodeLayer, now shipped under the HumanLayer brand as "the multiplayer control plane for your software factory." Monorepo (Bun + Turborepo): `apps/riptide-ui` (1,717 files), `apps/riptide-api` (958, oRPC+Hono), `apps/riptide-daemon` (602), `apps/riptide-cloud` (296), `apps/riptide-electron` + `apps/riptide-native` (macOS desktop), `apps/riptide-electric-proxy` (Electric SQL auth proxy), agent-mirroring plugins for Claude Code / OpenCode / Pi, `apps/riptide-rpi-claude-plugin` (the RPI skills), `apps/cli` (`humanlayer` CLI, embeds the daemon), `contracts/` (isomorphic oRPC/Effect RPC), `packages/` (`sync`, `streams`, `y-durable-streams`, `session-sdk-*`, `billing`). 71 `SKILL.md` total; ~49 are internal dogfooding (`.claude/skills/`), ~22 are the shipped RPI plugin.

#### 1. Inventory Summary

- Total SKILL.md: 71 (`.claude/skills/` ~49 dogfooding; `apps/riptide-rpi-claude-plugin/skills/` 22; `apps/riptide-humanlayer-claude-plugin/skills/` 3; `apps/riptide-pi-extension/skills/` ~21 — largely a duplicate RPI set)
- Depth distribution: RPI `create-*`/`iterate-*` skills are substantive artifact-writers with explicit phase contracts (not thin wrappers); `.claude` internals mixed
- Notable tooling: TypeScript/Bun throughout; daemon is Bun (legacy `hld` Go daemon still in tree); contracts generate OpenAPI
- License / ports note: **Apache-2.0 → portable** with attribution; verify `synclayer` provenance for freshest code

#### 2. High-Value Gaps

| Their capability | Path | Purpose | Why-not-duplicated-in-Soleur | Effort-to-adapt | Founder outcome unblocked (CPO gate) |
|---|---|---|---|---|---|
| `review-artifact-comments` | `apps/riptide-rpi-claude-plugin/skills/review-artifact-comments` | Doc comments become an agent-addressable review queue (list/reply/resolve/tombstone via API) | Soleur specs/plans are reviewed via PR threads or session prose; no artifact-native comment queue | medium | Reviewer feedback on specs lands as structured, resolvable items instead of chat scroll |
| Daemon-as-DB-reactor | `apps/riptide-daemon` + `apps/riptide-electric-proxy` | Per-host daemon watches replicated Postgres (Electric SQL) and launches sessions — zero inbound ports | Soleur's control path is session-local + Inngest; no remote-host orchestration | high | Remote/headless hosts become launch targets without SSH/VPN — feeds Concierge multi-host roadmap |
| `automation run` ephemeral daemon | `apps/cli` | PAT-auth CI/cron: ephemeral daemon in the job, one session, stream to cloud, exit-coded | Soleur CI agents run via `claude-code-action` + Inngest; equivalent coverage, different transport | medium | inspire only — parity, not a new outcome |
| `/hl:teleport` + cross-agent handoff | `apps/riptide-humanlayer-claude-plugin/skills/teleport` | Migrate a live session across hosts; Claude↔Codex mid-task handoff with transcript | No session mobility in Soleur (worktree + resume prompt is the handoff unit) | high | Long-running tasks survive host loss / model swaps |
| RPI artifact precedence rules | `apps/riptide-rpi-claude-plugin` convention | Numbered artifacts; "later doc wins; outline > design > research > ticket; live code beats all" | Soleur has spec/plan artifacts but no stated precedence ladder for conflicts | low | Resolves doc-vs-doc conflicts deterministically in long epics |
| Multiplayer steering UX | `apps/riptide-ui` | Real-time diff review, artifact comments, teammate approvals, mobile | Soleur's operator surface is chat + GitHub PRs; no collaborative session UI | very high | Out of scope for solo-founder ICP today; revisit if a team tier ships |
| Time-boxed permission bypass | legacy `hld` permission monitor | `dangerouslySkipPermissions` auto-revoked on a timer | Soleur's envelope is Standing Delegation + per-command approval — stricter already | low | inspire only — pattern noted |
| `show-me` / `describe-pr` | `apps/riptide-humanlayer-claude-plugin/skills/show-me` | Auto diagram + HTML walkthrough artifacts for PRs (32k installs standalone) | Soleur `feature-video` records browser walkthroughs; no static HTML diff-tour artifact | low | PRs carry a reviewer-friendly visual tour — cheap adoption win |

#### 3. Overlap Table

| Their skill | Closest Soleur equivalent(s) | Which looks deeper | Notes |
|---|---|---|---|
| `create-research` (+ research sub-agents) | `deepen-plan` + `engineering:research/*` (5 haiku-pinned researchers) | ours | Theirs is per-task artifact; ours fans out per plan-section with model pinning |
| `create-structure-outline` (vertical slices) | `plan` (spec + tasks) | ours | Their vertical-slice-per-phase is a good convention; ours has Observability/GDPR/user-impact gates they lack |
| `implement-plan` / `implement-outline` | `work` + `one-shot` | ours | Ours carries hooks/gates/TDD machinery; theirs pauses per phase for human review by default |
| `iterate-*` family | (no direct equivalent — revise-in-place is session behavior) | theirs | A named verb per artifact is crisper than implicit "edit the spec" |
| `describe-pr` (+ `pr-walkthrough.html`) | `ship` + `feature-video` | roughly even | Theirs generates a static HTML tour; ours records video — different media |
| RPI pipeline end-to-end | 6-stage lifecycle (brainstorm→plan→work→review→compound→ship→postmerge) | ours | Their pipeline is human-gated by design (their own post-mortem, "Everything We Got Wrong About RPI", drove more gates); ours is enforcement-gated and can run unattended to merge |
| `thoughts/` + `thoughts-locator` | `knowledge-base/` + `kb-search` + compound | ours | Theirs is per-user notes in a side repo; ours is canonical, promoted-to-rules memory |
| `setup-worktree` / workspaces | `git-worktree` (`worktree-manager.sh`) | ours | Theirs is a JSON config + daemon; ours handles leasing/reaping/session safety |
| `orchestrate` (CLI control plane) | `go` router + `schedule` + drains | different | Theirs lets an agent drive the *platform* (tasks/hosts); ours routes within a session. No true equivalent — this is their control-plane advantage |

#### 4. Architectural Patterns + Recommendations

##### Patterns worth examining

| Pattern | Mechanism (1 line) | Soleur fit | Recommendation |
|---|---|---|---|
| Daemon = DB-state reactor | daemon polls synced Postgres, spawns sessions; zero inbound ports | `apps/web-platform` agent-runtime (Inngest → headless claude) | extract — candidate architecture if Concierge gains remote/self-hosted runners |
| Artifact comment queue | comments on artifacts are first-class API objects agents resolve | `resolve-pr-parallel` (PR threads only today) | port — extend to spec/plan docs |
| Numbered-artifact precedence | `NN-<phase>-*.md`, later wins, code beats docs | `spec-templates` / brainstorm archive | port — one convention paragraph |
| Ephemeral daemon per CI job | PAT + launch token + one-shot session | `schedule`/`trigger-cron` + Inngest | inspire only — ours already covers this; note the PAT-auth shape for untrusted-CI use |
| Session mirroring (agent-agnostic) | `session-sdk-*` maps Claude/Codex/OpenCode/Pi events to one model | `lib/harness.ts` (invocation-layer only) | reject for now — Soleur normalizes *invocation*, not *sessions*; revisit if multi-agent sessions ship |
| `iterate-*` verb symmetry | every `create-*` has a paired `iterate-*` | skill corpus | port — cheap convention for artifact-producing skills |
| `show-me` HTML artifact | static diagram + walkthrough doc as deliverable | `feature-video` | port — complementary media, not replacement |

##### Recommendations (ICP-expansion framing per CMO)

- **"Artifact collaboration surface"** — bundles `review-artifact-comments` + numbered-artifact precedence + `iterate-*` symmetry. Founder outcome: spec/plan review becomes structured and resolvable, tightening the brainstorm→plan handoff that is already Soleur's stated moat. Suggested landing PR: "feat(skills): artifact comment queue + precedence convention for spec/plan docs".
- **"Remote-session substrate (deferred-design)"** — daemon-as-DB-reactor + teleport + cross-agent handoff. Founder outcome: Concierge can later offer BYO-host runners without SSH. **Recommend a brainstorm, not implementation** — this is a platform decision (postgres-sync vs. current Inngest control path), not a gap fill.
- **"PR reviewer experience"** — `describe-pr` HTML tour + `show-me` diagrams. Founder outcome: external reviewers get a lower-friction look at what an agent shipped — relevant now that the repo is public. Suggested landing PR: "feat(ship): optional pr-walkthrough.html artifact on large diffs".

##### Attribution

Apache-2.0 → concrete SKILL.md prose may be ported with:
`<!-- Inspired by humanlayer/humanlayer/<path> (Apache-2.0, Copyright (c) 2024 HumanLayer). -->`
`humanlayer/skills` and `humanlayer/fold` are MIT.

#### Convergence risk

- **Medium.** Not a same-ICP threat — they sell a *control plane* to engineering leaders ("CTOs and VPEs driving 99% AI-written code"), not an autonomous org to non-technical founders. But they hold three things Soleur lacks and the market visibly rewards: the **narrative** ("context engineering" coinage, ~5M content views, 12.3k stars), the **multiplayer steering surface**, and **agent-agnostic session mirroring**. Their workflow direction is opposite Soleur's (QRSPI adds human gates; Soleur removes them via enforcement) — the methodology converges *away*, while the *platform* converges *toward* Concierge's territory.
- **Watch items** — signals that would raise the risk:
  - `synclayer` repo surfacing + a third license flip in ~14 months (would be a pattern, not an accident)
  - a shipped **autonomous/unattended** task mode (today's QRSPI gates are the explicit anti-autonomy choice — auto-advance-everything would enter the drains/one-shot arena)
  - `automation run` gaining cron/fleet primitives (ephemeral daemon + remote daemons are one feature from the Inngest-cron substrate)
  - `humanlayer/fold` (their own agent runtime) reaching the skills/plugin layer — would make them a harness, not just a plane
  - enterprise "factory control plane" messaging colliding with any Soleur "agentic software factory" marketing claim — position on *autonomous org + enforced process*, never on "first" (Factory AI, Devin, Warp all claim the factory metaphor)

**Scope note.** Targeted single-repo peer-plugin audit. No full six-tier rescan and no specialist cascade (consistent with Cofounder/Multica/Omnigent/Sutra precedent); `last_reviewed` deliberately left at 2026-07-04 so this does not reset the full-scan clock. Operator's three questions answered in-session 2026-10-24; disposition recommendations are listed in §4 — none filed as issues yet (operator decides which bundles to pursue).

**Sibling shard:** [tier-3-humanlayer.md](../tier-3-humanlayer.md) — the Tier-3 matrix row and 2026-10-24 intake record.

