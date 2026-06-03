# UI-Surface Term List (shared)

Single source of truth for "does this feature touch a UI surface?" — cited by the wireframe gate
(`wg-ui-feature-requires-pen-wireframe`) and consumed by **all four** enforcement layers so they
agree on what "UI" means:

- brainstorm Phase 3.55 (Visual Design trigger)
- plan Phase 2.5 (mechanical UI-surface override + tier escalation)
- deepen-plan Phase 4.9 (UI-Wireframe Artifact Halt)
- work Check-9 (UX-skip-on-UI-plan hard gate)

A feature touches a UI surface when it creates or changes any of:

- **Pages / routes** — `app/**/page.tsx`, `app/**/layout.tsx`, `app/**/template.tsx`, `pages/**`,
  `routes/**`, `+page.svelte`, Eleventy/Nunjucks pages (`*.njk`), `*.html`, `*.vue`, `*.svelte`,
  `*.astro`
- **Components** — `components/**/*.{tsx,jsx,vue,svelte}`, shared UI primitives
- **Interstitials / overlays** — modals, dialogs, drawers, banners, toasts, popups, confirmation
  and persuasive-copy screens
- **Navigation / layout / chrome** — nav rails, sidebars, headers, footers, tab bars, layout
  shells, redesigns of existing chrome
- **Flows** — multi-step user journeys (signup, onboarding, checkout, cancel, chat)
- **Email templates** — transactional/marketing email markup

## Excluded (no wireframe required)

- Pure copy or style tweaks with no structural/layout change
- Backend-only work (APIs, migrations, jobs, infra, CI)
- Docs / knowledge-base / orchestration changes (SKILL.md, AGENTS.md, plans, specs)

## Glob superset (mechanical escalation)

Layers that need a mechanical check use this glob set as a superset of the prose list:

```
components/**/*.{tsx,jsx,vue,svelte}
app/**/page.tsx  app/**/layout.tsx  app/**/template.tsx
pages/**/*.{tsx,jsx,vue,svelte}  routes/**  +page.svelte
**/*.{njk,html,vue,svelte,astro}
```

Any match forces the UI-surface determination true regardless of subjective assessment.
