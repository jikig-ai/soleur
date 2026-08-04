import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test (#7144 finding 7) — mirrors the container-restart-burst
// and inbox-action-required precedents.
//
// The `inngest-dispatch-failure` Sentry issue-alert is the CTO's limb (c): the alarm for
// the failure mode that ran for ~3 days with nothing paging. It filters on
// `op == "inngest-send"`, which is emitted by sendInngestWithRetry's terminal branch.
//
// This alert was un-shippable until #7144 finding 5 landed. Before it, the only
// `op:inngest-send` capture sites were in route handlers, immediately after a
// `logger.error({ err })` that had already mirrored the SAME Error instance to Sentry via
// the pino hook — which marks it caught, so the tagged call early-returned and the tag
// never landed. A `tagged_event` filter on it would have matched exactly nothing, which
// is worse than no alert: it looks like coverage.
//
// So both sides are pinned here. A rename of the op slug on EITHER side — the emit in
// send-with-retry.ts, or the filter value in issue-alerts.tf — silently zeroes the
// alert's matches, which is the precise silent-paging-loss class it exists to prevent.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
const sender = readFileSync(
  join(here, "../server/inngest/send-with-retry.ts"),
  "utf8",
);

// Slice to THIS rule's block so a slug lingering elsewhere in the file (a comment, a
// sibling rule) cannot make a whole-file match pass vacuously.
const RESOURCE_DECL = 'resource "sentry_issue_alert" "inngest_dispatch_failure"';
const blockStart = tf.indexOf(RESOURCE_DECL);
const nextResource = tf.indexOf("\nresource ", blockStart + RESOURCE_DECL.length);
const tfBlock =
  blockStart === -1
    ? ""
    : tf.slice(blockStart, nextResource === -1 ? undefined : nextResource);

const OP_TAG = "inngest-send";

describe("inngest-dispatch-failure alert op contract (#7144 finding 7)", () => {
  it("declares the inngest_dispatch_failure issue alert resource", () => {
    expect(blockStart).toBeGreaterThanOrEqual(0);
  });

  it("filters on the op tag the sender actually emits", () => {
    // Anchored on the key/value pair inside a tagged_event, not a bare token: the slug
    // also appears in this file's own explanatory comments, and a bare grep would pass
    // against a rule whose filter had been deleted entirely.
    expect(tfBlock).toMatch(
      /tagged_event\s*=\s*\{[^}]*key\s*=\s*"op"[^}]*value\s*=\s*"inngest-send"[^}]*\}/s,
    );
  });

  it("routes somewhere — an alert with no action pages nobody", () => {
    expect(tfBlock).toMatch(/actions_v2\s*=\s*\[/);
    expect(tfBlock).toMatch(/notify_email/);
  });

  it("fires on regression and reappearance, not only first-seen", () => {
    // The #7144 outage recurred across deploys. An alert that only fires on first_seen
    // goes quiet exactly when the incident resumes.
    expect(tfBlock).toMatch(/reappeared_event/);
    expect(tfBlock).toMatch(/regression_event/);
  });

  it("the sender emits that exact op slug", () => {
    expect(sender).toMatch(/op:\s*"inngest-send"/);
  });

  it("the sender's capture is reachable — it is NOT the already-captured instance", () => {
    // The defect finding 5 fixed. Capturing the thrown instance is swallowed once
    // anything has mirrored it, so the tag never lands and this alert matches nothing.
    // A wrapper carrying `cause` is what survives; assert the shape rather than trusting it.
    expect(sender).toMatch(/captureException\(\s*new Error\([^)]*\{\s*cause:/s);
  });
});
