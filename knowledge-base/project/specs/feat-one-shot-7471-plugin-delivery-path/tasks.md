# Tasks — fix the plugin delivery path (#7471)

Derived from `knowledge-base/project/plans/2026-08-11-fix-plugin-delivery-path-plan.md` after
plan review, and amended 2026-08-12 for the UC-1 resolution. Read two things before starting:
the plan's `## Plan Review — Consolidated` section (several tasks below exist *because* a first
draft got them wrong, and the note says which) and the plan's `## Amendment 2026-08-12`.

**Execution order is not phase order.** Per the plan's phase-ordering note: **1.0 first, always**
→ 1.x → 3.1 → 1.6 → 2.x → **2B.x** → 3.x → 4.x → 5.x → 6.x.

**Numbering:** this file's Phase 1 is the plan's Phase 0, Phase 2 is the plan's Phase 1, and so
on. The plan's new **Phase 1B** appears here as **Phase 2B**, placed so the offset stays intact
and no existing task number moves.

---

## Phase 1 — Falsify before building

- [ ] **1.0** **FALSIFICATION GATE — run this before anything else.** Measure whether a
      `git-subdir` marketplace entry avoids the whole-repo clone. Build a scratch marketplace
      whose single entry is
      `{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"plugins/soleur"}`;
      with a clean `HOME`, run `marketplace add` then `install soleur@<scratch> --scope project`;
      then `du -sb ~/.claude/plugins/marketplaces ~/.claude/plugins/cache`.
      **PASS if the sum is < 50 MiB (52,428,800 B) AND both commands complete with
      `CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS` unset.** Otherwise **STOP the run** — outcome (b) does
      not resolve defect 2, and the operator decides again (plan Phase 0.8, row 0.0). Do not
      degrade to "ship Phase 2 + Phase 4 and call it outcome (a)".
      Also record the resolved `installPath` — Phase 5's ADR-178 amendment consumes it.

- [ ] **1.1** Re-verify the control group. For all **six** plugins (`pr-review-toolkit`,
      `feature-dev`, `commit-commands`, `frontend-design`, `github`, `playwright`),
      `jq 'has("version")' <manifest>` returns `false`. **`github` and `playwright` live under
      `external_plugins/`, not `plugins/`** — the templated path 404s for those two.
- [ ] **1.2** Build the fixture in the **migration** shape (install versioned → remove the key at
      source → refresh → update). This subsumes the greenfield case; do not build both.
      Record: whether the update applies, which cache directory resolves, and the resulting
      `installed_plugins.json` entry.
- [ ] **1.3** Add a third arm: **update N+1 of a migrated record.** After the migration lands, make
      another commit, refresh, update, and assert the SHA advanced. Without this, "delivers
      exactly once" may be literally true.
- [ ] **1.4** Probe the **`--url` install path** (`claude plugin install --url .../tree/main/plugins/soleur`,
      documented in both READMEs). It is a different *source shape*, not a different verb, and the
      control group says nothing about it. Does it record a `gitCommitSha`? Is it affected by the
      deletion? Does it clone only the subtree — in which case it is already a partial P5 answer.
- [ ] **1.5** Grep for version consumers **mechanically** before deleting anything: literal
      `\.version`, bracket access `\["version"\]`, and whole-object reads of either manifest,
      across `plugins/ apps/ scripts/ .claude/ .github/`.
- [ ] **1.6** Rehearse a **real** marketplace refresh of the 373 MiB checkout from the migration
      state, using whichever persistent setting task 3.1 selects.
- [ ] **1.7** Halt gates — each has a defined branch; see the plan's table. Do not stall.
      **1.0 is the exception: its branch is a halt, not a fallback.**
- [ ] **1.8** Sweep the **plugin-ID and marketplace-URL** consumers (plan 0.9), the same
      discipline as 1.5 applied to what the new marketplace changes. Four measured sites:
      `.github/workflows/test-pretooluse-hooks.yml`,
      `plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml`, and
      `plugins/soleur/skills/schedule/SKILL.md` (×2). Decide migrate-or-stay per site **with the
      reason recorded**. Two findings to carry: these runners clone 181 MiB every scheduled run,
      and `plugins/soleur/test/operator-digest-workflow.test.sh` matches
      `plugin_marketplaces:.*jikig-ai/soleur` — a **prefix**, so it passes vacuously against any
      `jikig-ai/soleur-*` repo name.

## Phase 2 — Remove the sentinel

- [ ] **2.1** Delete `"version"` from `plugins/soleur/.claude-plugin/plugin.json`. Leave
      `mcpServers` untouched (consumed by `session-rules-loader.sh` and `agent-runner.ts`).
- [ ] **2.2** Delete `plugins[0].version` from `.claude-plugin/marketplace.json`. **Do not touch
      the top-level `"version": "1.0.0"`** — different field, different meaning.
- [ ] **2.3** Guard `plugins/soleur/docs/_data/plugin.js` (`data.version ?? "unknown"`), **in the
      same commit**. Without it CI is deterministically red. Note this is an *unconditional
      overwrite*, not a fallback tier — the manifest value is gone, so say so precisely.
- [ ] **2.4** Cover all **three** `version: null` paths in `github.js`: the offline hatch, the
      **fetch `catch`**, and the no-release `?? null`. The catch arm means a transient GitHub API
      failure would otherwise kill a *production* docs build.

## Phase 2B — Publish the additive marketplace source (plan Phase 1B)

**Gated on 1.0 passing.** Additive: `jikig-ai/soleur` stays a valid marketplace and existing
installs keep working. The plugin ID changes for **new** installs only.

- [ ] **2B.1** **Confirm the repo name and visibility with the operator** before creating
      anything — the UC-1 resolution authorises the repo, it does not name it. Must be **public**
      or `marketplace add` cannot read it unauthenticated. Create via `/soleur:provision-github`,
      not by hand. Watch the prefix trap from 1.8 when choosing the name.
- [ ] **2B.2** New repo contents, minimal: `.claude-plugin/marketplace.json`, `README.md`
      (pointer back to `jikig-ai/soleur` as source of truth), `LICENSE` (`BUSL-1.1`). Nothing
      else — its size *is* the feature.
- [ ] **2B.3** One `git-subdir` plugin entry. **No `version` key** (this is the third manifest —
      do not reintroduce the sentinel through the back door). **No pinned `ref`/`sha`**, a
      deliberate divergence from the 42crunch/adobe precedent: a constant pin is a frozen
      sentinel wearing different clothes. Record the divergence.
- [ ] **2B.4** Record the **measured** plugin ID and `installPath` from the 1.0 run. The cache
      path is `cache/<marketplace name>/<plugin name>/<version>` and the `@` half comes from the
      manifest's `name` field, **not** the repo name. The third segment is unverified under a
      `git-subdir` source — use the measured string, never the inferred one.
- [ ] **2B.5** Update the documented install path (`README.md`, `plugins/soleur/README.md`,
      `plugins/soleur/docs/pages/getting-started.njk`): new marketplace recommended, existing
      path still works. See the plan's Gate 4.9 scope note — the `.njk` edit is larger than the
      one the operator's wireframe determination was granted against.
- [ ] **2B.6** Write the existing-install migration sequence. **It must contain no
      `marketplace add jikig-ai/soleur` step** — that is what makes it usable. Every command
      carries `--scope project` (live install: `projectPath
      /home/jean/git-repositories/skouer/Skouer`). Include the CLI restart and the `soleur.bak` /
      old-cache reclaim.
- [ ] **2B.7** Apply the 1.8 decisions, and fix `operator-digest-workflow.test.sh`'s
      prefix-matching assertion **whether or not** that workflow migrates — it is wrong either way.

## Phase 3 — Recovery and stopgap (gates Phase 2 being complete)

- [ ] **3.1** Measure whether an `env` block in `~/.claude/settings.json` is honoured by the plugin
      git path **and by the background `autoUpdate` refresh** — those are different claims, and
      the second is the arm the re-scope exists for. Also measure whether `autoUpdate: false`
      survives in `known_marketplaces.json` (no CLI flag sets it).
- [ ] **3.2** Write the recovery entry with the **non-destructive route first** (raise the timeout,
      then `marketplace update`) — that is the route measured to work. Demote
      `remove → re-add → reinstall` to the fallback for a genuinely destroyed checkout. Include
      the `.bak` restore step and **the required CLI restart** (`plugin update --help`: "restart
      required to apply").
- [ ] **3.3** Include the install's **scope** in every command. The live install is
      `scope: project`, `projectPath: /home/jean/git-repositories/skouer/Skouer`; a bare
      `claude plugin update soleur@soleur` targets user scope and finds nothing.
- [ ] **3.4** Put the mitigation **adjacent to the failing command**, not in a footer — a new user
      hits the 120s clone on `marketplace add`, before anything shippable is in their possession.
      Surfaces: `README.md`, `plugins/soleur/README.md`, `getting-started.njk`.
- [ ] **3.5** Correct `changelog.njk`'s upgrade FAQ in **both** the rendered copy and the JSON-LD
      `FAQPage` block. It currently claims the update is automatic — false today, false after.
- [ ] **3.6** Reclaim the **374 MiB `soleur.bak`** orphan; record the marketplace-orphan class
      alongside the cache orphan.
- [ ] **3.7** ~~File the option F issue.~~ **Withdrawn — option F ships as Phase 2B.** Its task 1
      (measure the `git-subdir` premise) became task **1.0**. Instead, file the
      **old-marketplace-deprecation** issue: `jikig-ai/soleur` is retained with `autoUpdate: true`
      and still clones 181 MiB for anyone on it. Keep one line about #1439 in the PR body — it is
      no longer a blocking dependency, but the ordering was deliberate. **#7471 is closed by this
      PR** (`closes:`), conditional on 1.0 passing.
- [ ] **3.8** File the delivery-canary issue, with its auth-feasibility check as task 1.
- [ ] **3.9** File the `action-required` issue carrying the recovery sequence — `operator-digest`
      harvests merged-PR titles and `action-required` issues, never PR bodies.
- [ ] **3.10** Attach this repo's evidence to the upstream defects.

## Phase 4 — Governance corpus (five sites)

- [ ] **4.1** `AGENTS.rules.md` — `wg-never-bump-version-files-in-feature` trailing clause. **The
      id is immutable.** Note the file contains "frozen sentinel" but **not** the literal
      `0.0.0-dev`, so a literal grep cannot verify this edit.
- [ ] **4.2** `plugins/soleur/AGENTS.md` pre-commit checklist bullet.
- [ ] **4.3** `plugins/soleur/skills/ship/SKILL.md` "Never edit version fields".
- [ ] **4.4** `CONTRIBUTING.md` "Plugin changes".
- [ ] **4.5** ADR-178 — the cache-path passage and the "name never changes" sentence. Anchor on
      **content, not line numbers**. It has no `status:` key (uses `- **Status:** Accepted`).
      **Reconcile against the NEW plugin ID, not just the keyless manifest**: the marketplace
      segment changes for new installs and the version segment changes for everyone. Use the
      `installPath` measured in 1.0 / 2B.4 — see the plan's three-column table in Phase 2.5.
- [ ] **4.6** Sweep: two greps, the literal **and** the paraphrase. Do not rewrite historical
      records under `plans/`, `plans/archive/`, `specs/`, `brainstorms/`, `learnings/`.

## Phase 5 — Architecture record

- [ ] **5.1** ADR-017 — add a dated `## Amendment (2026-08-11)` block plus a forward pointer.
      **Do not rewrite `## Decision` in place.** Keep `status: active`.
- [ ] **5.2** New ADR (**refer to it by slug; assign the ordinal at file-creation time** — do not
      pre-claim). **Scope widened by the UC-1 resolution: it carries two coupled decisions** —
      identity by commit SHA, and distribution by a dedicated additive `git-subdir` marketplace
      source. It must state the **real** rollback: `remove → re-add → reinstall`, not "re-add
      the key", because a source-side revert cannot self-deliver through the broken refresh —
      and note that Phase 2B makes that rollback cheap (re-add against ~50 KB, not 181 MiB).
      Record the ≥3 undocumented CLI recording modes, upstream #79950, the measured 1.0 numbers,
      the pinning divergence from the 42crunch/adobe precedent, and the **two-marketplace cost**
      (two IDs, two caches, a documented migration, an old entry still cloning 181 MiB, and a
      third manifest no CI check in this repo can reach). Note that
      `.claude-plugin/marketplace.json` is absent from the release workflow's path filter.
- [ ] **5.3** C4 — see the plan's enumeration, **plus the new marketplace source repo** as a
      distinct external system with two edges of different payload size (installed CLI → repo,
      ~50 KB; repo → `jikig-ai/soleur`, ~17 MiB). **Add `model.likec4.json` and run
      `scripts/regenerate-c4-model.sh`**; it is a committed render artifact byte-diffed by
      `c4-model-freshness.test.sh`, and that suite — not the two tests originally named — is the
      real gate. Add `platform.plugin` to the `context` view's include list alongside the new
      elements, or the edge renders as a disconnected box.
- [ ] **5.4** Amend Art. 30 register PA-32 §(f) for the marketplace-clone channel, **and record
      that a second, narrowed channel now exists alongside it**. **Change no figure** — the "80
      digests" count is correct; an earlier draft's "81" counted a subdirectory. Also add the new
      repo to the in-scope surfaces list and widen the `GitHub Inc` vendor-row scope cell (it
      reads "cc-router in-process MCP tool surface" and covers neither distribution hosting nor a
      second repo). **Do not claim this satisfies #7119's R5** — that routes to `clo`.

## Phase 6 — Verification

- [ ] **6.1** Full suite via the repo's own invocation.
- [ ] **6.2** Re-run the migration fixture against the edited manifests.
- [ ] **6.3** Docs build green on the offline, online, and **API-failure** paths.
- [ ] **6.4** Post-merge: assert delivery on **content** (a file the merge commit changed, present
      in `installPath`), not on `installed_plugins.json` — upstream #76882 means the metadata does
      not reliably follow the content, and it is measurably stale on this machine right now.
      Index the entry as an **array** with a scope selector; it is not an object. **Run it twice,
      once per marketplace**: the new path (which `closes: 7471` rests on) and the retained
      `soleur@soleur` path, which must still work — additive means additive.
- [ ] **6.5** Post-merge: a fresh install from the **published** marketplace materialises
      **< 50 MiB** with the default timeout — the 1.0 threshold re-run against the real repo, not
      the scratch fixture. A pre-merge fixture passing while the shipped article fails is exactly
      the gap this whole plan is about.
- [ ] **6.6** Verify the published third manifest: `jq '.plugins[0]|has("version")'` → `false`,
      `.plugins[0].source.source` → `git-subdir`, `.plugins[0].source.path` → `plugins/soleur`.
      **Read the published file, not the local draft** — it lives outside this repo and no CI
      check here can reach it.
- [ ] **6.7** The outbound to alpha tester #1 carries the **migration sequence** (2B.6), not just
      a notification. At a population of one that outbound *is* the migration mechanism.
