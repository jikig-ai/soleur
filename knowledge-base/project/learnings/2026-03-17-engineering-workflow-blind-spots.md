# Learning: Engineering workflows silently skip cross-domain gates

## Problem
Building the web platform MVP (PR #637) exposed three categories of blind spots — all caused by engineering workflows being self-contained with no cross-domain checkpoints:

1. **Deploy without verify**: Shipped WebSocket "fixes" 3 times without testing. Told the user "should be fixed" each time. Root cause was misdiagnosed twice (keepalive → middleware → missing auth token → missing start_session).

2. **Provision without tracking**: Stood up 4 new services (Hetzner CX33, Supabase, Stripe, Cloudflare) without updating the expense ledger or triggering legal/DPA review. The ops-advisor and CLO agents exist but were never invoked.

3. **Build UI without design**: Built 5+ user-facing screens (signup, login, BYOK, dashboard, chat) without invoking ux-design-lead for wireframes or CPO for product validation. The feature was framed as "Cloud CLI Engine" (engineering scope), so product was never consulted.

## Solution
Three constitution rules added:
- Verify fixes end-to-end before reporting success (Playwright + server logs + 10s hold)
- When provisioning vendors, update expenses + trigger legal review before session ends
- When plans include UI, invoke ux-design-lead + spec-flow-analyzer before implementation

Four GitHub issues filed: #667 (BYOK decryption), #668 (test coverage), #670 (ops+legal tracking), #671 (product/UX gate).

## Key Insight
Domain agents exist but are only invoked by user messages or explicit requests. Engineering actions (terraform apply, account signup, page.tsx creation) don't trigger cross-domain routing. The structural fix is detection logic in `/plan` and `/work` that recognizes vendor provisioning, UI creation, and deployment — then auto-routes to ops, legal, and product domains. Constitution rules are prose-based (weakest enforcement) and serve as a bridge until the skill-level gates are implemented.

## Tags
category: logic-errors
module: workflow
