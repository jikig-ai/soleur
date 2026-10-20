---
branch: feat-one-shot-10399-webplat-feature-map
---

# Decision Challenges — feat-one-shot-10399-webplat-feature-map

| Item | Class | Ruling |
|---|---|---|
| Map format: new `apps/web-platform/test/feature-map.md` (markdown, `## \`/route\`` entries) vs extending `ux-audit/references/route-list.yaml` schema | technical | Ruled by CTO agent, 2026-10-20: markdown map — `route-list.yaml` is a ux-audit screenshot-queue config (`{path, auth, fixture_prereqs, viewport}`) whose schema guard (`route-list-prereqs.test.ts`) would break under selectors/expects/gotchas fields, and coupling two consumers' drift rates is worse than a cross-reference - the map links to it instead of re-encoding it. |
| Gate scope: whole-tree coverage check vs changed-only (`--changed` mode) | technical | Ruled by CTO agent, 2026-10-20: whole-tree + in-map exemption registry — matches the repo's fail-closed lint convention (`lint-integration-env-gates.sh`), an exemption is a recorded decision not silent absorption, and "advisory" governs merge-blocking not check completeness - changed-only mode would never flag a pre-existing unmapped route. |
| Guard direction: route→map coverage only vs bidirectional consistency | technical | Ruled by CTO agent, 2026-10-20: bidirectional — a "maintained" map that keeps tombstone entries for deleted routes misleads the very navigation it exists to provide; the staleness arm costs one reverse set-diff - spec-flow analysis flagged the rot shape. |
| Exemption registry location: inside `feature-map.md` vs separate `.allowlist.txt`/in-script | technical | Ruled by CTO agent, 2026-10-20: inside the map (`## Deliberately unmapped` with mandatory reason) — contributors editing routes already look there; a separate file reintroduces the two-artifact drift the gate exists to catch - deviation from the `.allowlist.txt` precedent is deliberate and documented. |
| Deferred: one-line map pointers in `qa`/`ux-audit`/`reproduce-bug` SKILL.md | operator (scope) | pending - out of #10399's AC (only `test-browser` citation required); recorded in plan Dependencies & Risks for post-merge evaluation rather than filed as an issue from the planning subagent. |
