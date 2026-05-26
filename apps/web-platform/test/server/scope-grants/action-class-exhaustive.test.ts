/**
 * PR-H (#4077) — Action-class registry exhaustiveness + parity + enum-absence.
 *
 * Three complementary gates in ONE file (per plan §Test Strategy + simplicity #7
 * consolidation):
 *
 *   (a) Parity: `ACTION_CLASS_DEFAULTS` and `ACTION_CLASS_CATEGORY` both
 *       cover every member of `ActionClass` (compile-time via `satisfies`).
 *   (b) Exhaustiveness: a switch over `ActionClass` with `_exhaustive: never`
 *       rail (compile-time). Adding a class without updating the switch
 *       fails `tsc --noEmit` per `cq-union-widening-grep-three-patterns`.
 *   (c) Enum-absence regression: at runtime, every `ACTION_CLASSES` entry
 *       must NOT start with `payment.`, `legal.`, or `auth.` — the 5th
 *       (per-command-ack) class is enforced by ABSENCE from the registry
 *       per ADR-034 §2 and `hr-menu-option-ack-not-prod-write-auth`.
 */

import { describe, expect, test } from "vitest";

import {
  ACTION_CLASSES,
  ACTION_CLASS_CATEGORY,
  ACTION_CLASS_DEFAULTS,
  type ActionClass,
  type ActionClassCategory,
  type ActionClassTier,
} from "@/server/scope-grants/action-class-map";
import { ACTION_CLASS_COPY } from "@/lib/messages/action-class-copy";

// (a) Parity gates — compile-time. If a new ActionClass is added without
//     an ACTION_CLASS_DEFAULTS or ACTION_CLASS_CATEGORY entry, `tsc
//     --noEmit` fails before this file runs.
const _defaultsCover: Record<ActionClass, ActionClassTier> =
  ACTION_CLASS_DEFAULTS satisfies Record<ActionClass, ActionClassTier>;
const _categoryCover: Record<ActionClass, ActionClassCategory> =
  ACTION_CLASS_CATEGORY satisfies Record<ActionClass, ActionClassCategory>;
void _defaultsCover;
void _categoryCover;

// (b) Exhaustiveness rail — compile-time. Adding a new ActionClass member
//     without a switch arm here fails `tsc --noEmit` with
//     `TS2322 ... not assignable to type 'never'`.
function assertExhaustive(ac: ActionClass): ActionClassCategory {
  switch (ac) {
    case "finance.payment_failed":
      return "finance";
    case "external.low_stakes.customer_status_update":
    case "external.low_stakes.vendor_support_ticket":
    case "external.low_stakes.bluesky_reply_personal":
    case "external.low_stakes.slack_dm_standard":
      return "external_low_stakes";
    case "external.brand_critical.marketing_email_blast":
    case "external.brand_critical.public_x_thread":
    case "external.brand_critical.bluesky_reply_soleur_handle":
    case "external.brand_critical.slack_dm_enterprise_tier1":
      return "external_brand_critical";
    case "infra.dependency_bump":
    case "infra.log_rotate":
      return "infra";
    case "engineering.pr_review_pending":
    case "engineering.ci_failed":
      return "engineering";
    case "triage.p0p1_issue":
      return "triage";
    case "security.cve_alert":
      return "security";
    case "knowledge.kb_drift":
      return "knowledge";
    default: {
      const _exhaustive: never = ac;
      void _exhaustive;
      return "finance";
    }
  }
}
void assertExhaustive;

describe("action-class registry — runtime gates", () => {
  test("(c) enum-absence: no entry begins with payment./legal./auth.", () => {
    // Per ADR-034 §2: the 5th class (money/legal/credentials) is enforced
    // by ABSENCE from the registry, not by presence with a deny flag.
    // Hard rule lineage: hr-menu-option-ack-not-prod-write-auth.
    const offenders = ACTION_CLASSES.filter((c) =>
      /^(payment|legal|auth)\./.test(c),
    );
    expect(
      offenders,
      "Action classes matching ^(payment|legal|auth)\\. must NOT appear in ACTION_CLASSES — they require per-command-ack and are enforced by enum-absence (ADR-034 §2 / hr-menu-option-ack-not-prod-write-auth).",
    ).toEqual([]);
  });

  test("(d) defaults + category parity at runtime", () => {
    for (const c of ACTION_CLASSES) {
      expect(ACTION_CLASS_DEFAULTS).toHaveProperty(c);
      expect(ACTION_CLASS_CATEGORY).toHaveProperty(c);
    }
  });

  test("(d2) ACTION_CLASS_COPY registry parity at runtime", () => {
    for (const c of ACTION_CLASSES) {
      expect(ACTION_CLASS_COPY).toHaveProperty(c);
    }
  });

  test("(e) registry size sanity — 11 classes per FR1 (#4077 plan)", () => {
    // Locking the cardinality protects against accidental drops or
    // duplicate-entry mistakes during future widens. Bump intentionally
    // when adding a new producer.
    expect(ACTION_CLASSES.length).toBe(16);
  });
});
