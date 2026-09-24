# Harness-parity gate map

Which gate owns which property, what a RED usually means, and where the remaining
work is tracked. This table lives here rather than in an ADR (ADR-245) because it
changes every time a gate is added, and an ADR is not the home for a table with
that lifecycle.

Soleur ships ONE plugin tree to four harnesses — Claude Code, Grok Build, Codex and
Devin — each with its own invocation syntax and its own tool vocabulary. Every gate
below exists because some part of that tree is read by an agent on a harness the
author was not using.

**On the `Tracker` column.** It names the issue that OWNS the remaining work, and
says `closes with #8570` where this PR is what discharges it. It deliberately does
not say "closed": an issue closes when the PR merges, so a table written during the
PR that claims a closed state is asserting something that is not true yet, and stays
wrong if the PR is abandoned (`hr-before-asserting-github-issue-status`). Verify with
`gh issue view <n> --json state`, never from this table.

**Paths are given in full** because these gates do not all live in one directory —
`plugin-root-anchoring.test.ts` is under `apps/web-platform/test/`, and one row is a
CI job rather than a file at all.

| Gate | Property | A RED usually means | Tracker |
|---|---|---|---|
| `plugins/soleur/test/grok-harness-invoke.test.ts` | Every `skills/*/SKILL.md` carries exactly one canonical Grok invoke block, before the first heading, outside fences | A new skill shipped without the block. The failure message prints the insertion point and the block to paste; `init_skill.py` carries it so new skills are born compliant | #8390, closes with #8570 |
| `plugins/soleur/test/harness-tool-map.test.ts` | Every Claude Code tool name a doc uses has a row in BOTH the Codex and Devin `## Tools` tables | A doc started naming a tool neither adapter table translates. Add a row per table, or "no equivalent; report the unsupported gate" | #8318, closes with #8570 |
| `plugins/soleur/test/harness-parity-tree.test.ts` + `plugins/soleur/test/harness-parity.test.ts` | Every component reference in agent-read prose is the canonical `soleur:<name>` / registry id — skills, commands, the Codex/Devin shims, `skills/*/references/**` and agent bodies (each agent's own frontmatter `name:` is its one SELF-NAME) | A harness-specific form (`/plan`, `$soleur:plan`) or a bare agent leaf (dead on Grok) entered the corpus. `harness-parity-census.ts --fix` repairs the mechanical shapes on a clean tree | ADR-226. The references half closed with #8570; the agent half closes with #8317 (self-name carve-out, ADR-226 §3 amendment) |
| `apps/web-platform/test/plugin-root-anchoring.test.ts` (command + secret-gate axes) | No customer-facing command or secret-gate script is reached through a CWD-controllable anchor | Zero tolerance — rewrite as `"${CLAUDE_PLUGIN_ROOT}/…"` with no default | #7450 (closed) |
| `apps/web-platform/test/plugin-root-anchoring.test.ts` (skills ratchet axis) | The non-gate CWD-controllable anchors cannot GROW | A NEW anchor, or an existing one gaining occurrences. Do NOT add a baseline row — fix the anchor | #7453 owns migrating the existing rows (open) |
| `plugins/soleur/test/harness-discovery-smoke.test.ts` + the `harness-discovery` job in `.github/workflows/ci.yml` | Codex and Devin, installed hermetically from the checkout, register every skill their manifest's roots declare, with ONE multiplicity mode per run | Exit 1 = a real set or multiplicity mismatch. Exit 3 = UNRESOLVED (CLI absent, install failed, version drift, or a structurally unreadable listing) and is never a pass | ADR-245; #8574 owns promoting the job to required (open) |
| `plugins/soleur/test/components.test.ts` (`ACKED_CROSS_ROOT_DUPES`) | Slash-name uniqueness across harness component namespaces | A new cross-root duplicate. The discovery gate above proves REGISTRATION, not uniqueness — this is where uniqueness lives | ADR-224 decision 5; #8236 (open) |
| `plugins/soleur/test/devin-cloud-mode.test.ts` | The cloud-mode marker fleet is byte-identical across its curated set | A skill's cloud-mode block drifted | ADR-221 |
| `plugins/soleur/test/workflow-fidelity.test.ts` | Grok routing semantics, asserted without reading the invoke block's bytes | The routing contract changed. This is the anchor OUTSIDE the Grok block's own md5 pin | #6320 (closed) |

## What a red `harness-discovery` does and does not block

It blocks **no merge**: the job is absent from the `test` aggregator's `needs:`, so
it is not a required check.

It also does not block a **deploy**, but only because the job carries
`continue-on-error: true`, and that line is load-bearing rather than decoration.
"Non-required" governs the merge gate; it says nothing about
`workflow_run.conclusion`. `web-platform-release.yml` is triggered by
`workflows: ["CI"]` and refuses to deploy when that conclusion is not `success`
(its `ci_not_green` guard). Without `continue-on-error`, an npm hiccup or a 404 on
`static.devin.ai` during a main push would red the CI run and SKIP that SHA's
production deploy — a third-party network flake gating our own releases.

With it, the step still reds visibly on the check list while the run conclusion
stays `success`. **#8574's promotion to a required check MUST remove that line in
the same change**, because a required check that cannot fail the run is worse than
no check.

## Vendor-CLI pins

`harness-discovery` (Codex, Devin) and `grok-fidelity` (Grok) drive third-party
CLIs, pinned exactly and asserted at install time (ADR-245):

| CLI | Pin | Install path | Depth of the pin |
|---|---|---|---|
| Codex | `0.156.1` | `npm i -g @openai/codex@<pin>` | npm resolves the version to immutable published bytes |
| Devin | `3000.11.1` | `https://static.devin.ai/cli/<pin>/setup.sh` — the top-level `install.sh` leaves `PINNED_VERSION` empty and installs latest | A version in a URL is a NAME the vendor can re-serve, so the job also pins the fetched script by `sha256sum -c` and refuses to execute a changed one |
| Grok | `1.0.41` | `https://x.ai/cli/grok-<pin>-linux-x86_64` | xAI publishes no versioned installer URL and no checksum, so the job content-pins the binary itself by `sha256sum -c` (either source) and never runs `install.sh` |

Every arm then asserts the installed binary reports the pin, exiting 3 on drift.

The pins are declared ONCE each, as job-level `env` (`CODEX_PIN`, `DEVIN_PIN`,
`DEVIN_SETUP_SHA256`, `GROK_PIN`, `GROK_SHA256`) — a `--pin` lagging its own install step silently turns the
script's version check into a no-op.

A pin is stale the day the vendor ships. **#8574 owns the freshness criterion**: a
monthly comparison against `npm view @openai/codex version`, Devin's current
release and `curl -fsSL https://x.ai/cli/stable`, before `harness-discovery` is
promoted to a required check (the Grok comparison outlives that promotion). The drift is not
hypothetical — this work was planned against Codex 0.155.1 and npm was at 0.156.1
one day later.

`grok-fidelity`, unlike `harness-discovery`, is a **required** check; since #8615 it
conforms to the pinning rule only (ADR-245 decision 3, amendment).
