# Tasks — fix the plugin delivery path (#7471)

Derived from `knowledge-base/project/plans/2026-08-11-fix-plugin-delivery-path-plan.md` after
plan review. Read the plan's `## Plan Review — Consolidated` section before starting: several
tasks below exist *because* a first draft got them wrong, and the note says which.

**Execution order is not phase order.** Per the plan's phase-ordering note: 1.x → 3.1 → 1.6 →
2.x → 3.x → 4.x → 5.x → 6.x.

---

## Phase 1 — Falsify before building

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
- [ ] **3.7** File the option F issue (dedicated/additive marketplace source). **Task 1 of that
      issue is measuring whether `git-subdir` actually avoids the full clone** — an unmeasured
      premise that may refute F. Target the roadmap Phase 4 milestone; record the #1439 blocking
      relationship; **make it the closer of #7471**.
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
- [ ] **4.6** Sweep: two greps, the literal **and** the paraphrase. Do not rewrite historical
      records under `plans/`, `plans/archive/`, `specs/`, `brainstorms/`, `learnings/`.

## Phase 5 — Architecture record

- [ ] **5.1** ADR-017 — add a dated `## Amendment (2026-08-11)` block plus a forward pointer.
      **Do not rewrite `## Decision` in place.** Keep `status: active`.
- [ ] **5.2** New ADR (**refer to it by slug; assign the ordinal at file-creation time** — do not
      pre-claim). It must state the **real** rollback: `remove → re-add → reinstall`, not "re-add
      the key", because a source-side revert cannot self-deliver through the broken refresh.
      Record the ≥3 undocumented CLI recording modes and upstream #79950. Note that
      `.claude-plugin/marketplace.json` is absent from the release workflow's path filter.
- [ ] **5.3** C4 — see the plan's enumeration. **Add `model.likec4.json` and run
      `scripts/regenerate-c4-model.sh`**; it is a committed render artifact byte-diffed by
      `c4-model-freshness.test.sh`, and that suite — not the two tests originally named — is the
      real gate. Add `platform.plugin` to the `context` view's include list alongside the new
      elements, or the edge renders as a disconnected box.
- [ ] **5.4** Amend Art. 30 register PA-32 §(f) for the marketplace-clone channel. **Change no
      figure** — the "80 digests" count is correct; an earlier draft's "81" counted a
      subdirectory.

## Phase 6 — Verification

- [ ] **6.1** Full suite via the repo's own invocation.
- [ ] **6.2** Re-run the migration fixture against the edited manifests.
- [ ] **6.3** Docs build green on the offline, online, and **API-failure** paths.
- [ ] **6.4** Post-merge: assert delivery on **content** (a file the merge commit changed, present
      in `installPath`), not on `installed_plugins.json` — upstream #76882 means the metadata does
      not reliably follow the content, and it is measurably stale on this machine right now.
      Index the entry as an **array** with a scope selector; it is not an object.
