// PR-I (#4078) — Canonical template registry (code-static).
//
// Mirrors the `as const` + Record + `satisfies` pattern of
// `apps/web-platform/server/scope-grants/action-class-map.ts`. ADR-035
// captures the design rationale: registry rows are source-controlled,
// reviewer-visible, and parity-tested at compile-time. A new template
// requires a code edit + a test pass — registry rows are not
// runtime-mintable to satisfy Art. 7(3) consent specificity.
//
// `getTemplateHash` consumes `messages.template_id` and returns
// sha256(body_template). The `template_authorizations` table keys on
// this hash; producers and consumers must agree on the same registry
// snapshot in any given deploy. The hash is intentionally independent of
// (action_class, owning_domain, tier) — those are dimensions the action_sends
// ledger records separately. See plan §Phase 1 + Sharp Edges.

import { createHash } from "node:crypto";

import { warnSilentFallback } from "@/server/observability";
import type { ActionClass } from "@/server/scope-grants/action-class-map";

export const TEMPLATE_IDS = ["default_legacy"] as const;

export type TemplateId = (typeof TEMPLATE_IDS)[number];

export interface TemplateRegistryEntry {
  id: TemplateId;
  // The canonical pre-personalisation message body. Hashed to derive
  // `template_hash`. Changing this string changes the hash, which
  // changes the partial-UNIQUE bucket in `template_authorizations` —
  // treat as effectively immutable once a template ships.
  body_template: string;
  // The action_class this template applies to. `null` means the
  // template is class-agnostic (today only `default_legacy`). Typed as
  // ActionClass | null (NOT string | null) to honor ADR-035 §Decision (1)
  // "mirroring ADR-034's ACTION_CLASSES pattern" — a new template
  // referencing a non-registry class fails tsc. Surfaced by PR-I
  // multi-agent review (pattern-recognition P1-1).
  action_class: ActionClass | null;
  // The owning domain (e.g., `external`, `engineering`). `null` for
  // class-agnostic templates.
  owning_domain: string | null;
}

export const TEMPLATE_REGISTRY: Record<TemplateId, TemplateRegistryEntry> = {
  // PR-H carry-forward: every existing `messages` row backfills to this
  // entry (mig 053 Part A). PR-I+ templates split this bucket as real
  // per-template body_templates ship; until then, `default_legacy` is
  // the only key on `template_authorizations.template_hash`.
  default_legacy: {
    id: "default_legacy",
    body_template: "default_legacy:v1",
    action_class: null,
    owning_domain: null,
  },
} satisfies Record<TemplateId, TemplateRegistryEntry>;

export function isKnownTemplateId(value: unknown): value is TemplateId {
  return (
    typeof value === "string" &&
    (TEMPLATE_IDS as readonly string[]).includes(value)
  );
}

/**
 * Returns `sha256(body_template)` for the message's `template_id`. For
 * unknown / null / undefined template_id, falls back to `default_legacy`
 * and emits a `warnSilentFallback` for observability (an unknown id
 * reaching the send path is a producer-side bug — a `messages` row
 * landed with an id that has no registry row).
 *
 * The fall-through is fail-OPEN against the *hash* (we always return a
 * deterministic string so the WORM ledger can record the send), but
 * fail-LOUD against the *observability* layer so the producer-side
 * mismatch is visible in pino + Sentry.
 */
export function getTemplateHash(message: {
  template_id?: TemplateId | string | null;
}): string {
  const raw = message.template_id;
  const id: TemplateId = isKnownTemplateId(raw) ? raw : "default_legacy";

  if (raw != null && id !== raw) {
    warnSilentFallback(
      new Error(`unknown template_id; falling back to default_legacy`),
      {
        feature: "template-registry",
        op: "template_hash_unknown_template_id",
        extra: { receivedTemplateId: String(raw) },
      },
    );
  }

  return createHash("sha256")
    .update(TEMPLATE_REGISTRY[id].body_template)
    .digest("hex");
}
