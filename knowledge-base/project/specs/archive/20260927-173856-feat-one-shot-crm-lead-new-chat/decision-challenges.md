# Decision challenges — feat-one-shot-crm-lead-new-chat

Recorded headless by soleur:plan (2026-09-27). Nested review agents were not spawned
(Grok subagent depth 1). Each item keeps the operator's direction.

## User-challenge — embed the chat on the CRM board

- **Operator direction:** from the CRM screen, start a new chat whose purpose is entering a new CRM lead.
- **Dissent considered:** the Routines surface embeds `ChatSurface` on the page. That would avoid a route and a `mode` query.
- **Adopted:** a New lead link to `/dashboard/chat/new` so the thread is a conversation in the rail.
- **Why it stands:** an embedded composer is a different surface than a new chat, and it still needs the same server mode.
- **If wrong, the cost is:** one extra navigation, and the operator leaves the board to type.

## Taste — button label

- **Adopted:** "New lead", matching the operator's words. The plan hedges "lead" as a new `beta_contacts` row because the glossary has no entry.
- **Dissent considered:** "Add contact" matches the table name more closely.
- **If wrong, the cost is:** a label change on one control.
