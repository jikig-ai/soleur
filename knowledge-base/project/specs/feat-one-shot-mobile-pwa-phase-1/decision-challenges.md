# Decision Challenges — feat-one-shot-mobile-pwa-phase-1

These are plan-review findings that would **change the operator's explicit audit change-list**. Per decision-principles (ADR-084) the operator's stated direction is the default, so in this headless one-shot they are recorded (not silently applied). `ship` renders this into the PR body and files an `action-required` issue for operator adjudication. Each includes a clear recommendation.

---

## Challenge 1 — Split the chat scroll-guard (audit item 5b) into its own PR

**Raised by:** dhh-rails-reviewer, code-simplicity-reviewer
**Operator's direction (audit):** item 5 bundles the near-bottom scroll guard + "Jump to latest" affordance into this Phase 1 PR.
**Challenge:** every other change in this PR is a mechanical className/attribute swap; 5b is a stateful chat feature (new `nearBottom` state/ref, `onScroll`/`visualViewport` handlers, and a net-new interactive "Jump to latest" control with its own hit-area and show/hide logic). Bundling a feature into a 23-file mechanical sweep makes the diff harder to review with confidence, and the net-new control is what makes the ADVISORY (not BLOCKING) UX-gate call debatable (see Challenge 3-adjacent note below).
**Recommendation:** keep 5a (the `h-full` height fix — a genuine bug, composer below fold) in this PR; move 5b (scroll guard + Jump-to-latest) to a small immediate follow-up PR where a reviewer can eyeball the interaction. **This is a scope/sequencing preference, not a correctness blocker** — 5b as specified (with the spec-flow G1–G7 fixes folded in) is correct if kept.
**Default if no operator response:** keep 5b in this PR as the audit specifies.

## Challenge 2 — Drop the redundant "16px only" per-input rows (audit item 4)

**Raised by:** dhh-rails-reviewer, code-simplicity-reviewer
**Operator's direction (audit):** item 4 sets `text-base md:text-sm` on all 13 hot inputs, including rows whose ONLY change is the 16px font (setup-key, key-rotation, the three new-issue-dialog fields, naming-modal).
**Challenge:** the Phase-3.1 global `@media (max-width:767px)` 16px floor already prevents iOS zoom on every input, so on those rows `text-base md:text-sm` is belt-and-suspenders. Kieran verified it is **harmless** (utilities beat the base-layer floor; outcome is identical 16px-mobile / 14px-desktop), so this is a minor tidiness point, not dead CSS.
**Recommendation:** optional — either keep per the audit (harmless, explicit) or drop the font-only swaps and let the global floor carry them, keeping Phase 4 only for rows that add real value (`inputMode`/`enterKeyHint`/`autoComplete`/`type="search"`). Low stakes either way.
**Default if no operator response:** keep per the audit.

## Challenge 3 — PWA `scope: "/dashboard"` ejects users to the system browser (audit item 2)

**Raised by:** dhh-rails-reviewer (highest-signal manifest finding)
**Operator's direction (audit):** item 2 sets `scope: "/dashboard"` (matching `start_url: "/dashboard"`).
**Challenge:** `scope` defines the installed standalone app's navigation boundary. `/login`, `/signup`, `/setup-key`, `/connect-repo`, and marketing routes all sit **outside** `/dashboard`. The moment a session expires and the user is redirected to `/login` — the single most common boundary — the navigation falls **out of the installed PWA window into the system browser**, breaking the "installed app" experience. For a PR whose thesis is "correctly installable," this is a real UX cliff only visible after installing and letting a session lapse.
**Recommendation:** set `scope: "/"` while keeping `start_url: "/dashboard"`. This preserves the launch target (opens to the dashboard) but keeps the whole origin inside the app window, so auth bounces stay in-app. This is a strictly-safer superset scope with no downside for an installable dashboard. **This is the one genuine product/correctness judgment in the manifest** and is worth adjudicating before ship.
**Default if no operator response:** ship with `scope: "/dashboard"` as the audit specifies, but this is the challenge most worth an explicit operator decision.
