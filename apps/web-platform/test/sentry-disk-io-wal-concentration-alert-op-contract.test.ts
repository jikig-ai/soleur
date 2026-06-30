import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract test (#5736).
//
// The `disk-io-wal-concentration` Sentry issue-alert pages when
// cron-supabase-disk-io.ts emits its WAL-concentration capture. It filters on
// `feature == "cron-supabase-disk-io"` AND `op == "wal-concentration"`. Because
// the alert uses `filter_match = "all"`, a rename of the `feature` tag OR the op
// slug on EITHER side (the emit site in cron-supabase-disk-io.ts, or the filter
// value in issue-alerts.tf) would silently zero the alert's matches — the exact
// silent-paging-loss class this alert exists to prevent. Pin both filter
// dimensions against that drift.

const here = dirname(fileURLToPath(import.meta.url));
const tf = readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8");
const cron = readFileSync(
  join(here, "../server/inngest/functions/cron-supabase-disk-io.ts"),
  "utf8",
);

// Slice to THIS rule's block so a slug lingering elsewhere in the file (a
// comment / sibling rule) cannot make a whole-file match pass vacuously.
const RESOURCE_DECL =
  'resource "sentry_issue_alert" "disk_io_wal_concentration"';
const blockStart = tf.indexOf(RESOURCE_DECL);
const nextResource = tf.indexOf("\nresource ", blockStart + RESOURCE_DECL.length);
const tfBlock =
  blockStart === -1
    ? ""
    : tf.slice(blockStart, nextResource === -1 ? undefined : nextResource);

const FEATURE_TAG = "cron-supabase-disk-io";
const ALERT_OP = "wal-concentration";

describe("disk-io-wal-concentration alert op/feature contract (#5736)", () => {
  it("declares the disk_io_wal_concentration issue alert resource", () => {
    expect(blockStart).toBeGreaterThanOrEqual(0);
    expect(tfBlock).toContain(RESOURCE_DECL);
  });

  it("declares the resource EXACTLY ONCE (Terraform rejects duplicate type+name)", () => {
    // The block-slicing assertions above only inspect the FIRST match, so a
    // duplicated `resource "..." "disk_io_wal_concentration"` block would pass
    // them while making `terraform plan` fail with "Duplicate resource" — which
    // creates NO rule AND blocks every other targeted rule in the apply. Count
    // the whole-file occurrences so the duplicate is caught here, not at apply.
    const occurrences =
      tf.match(
        /resource "sentry_issue_alert" "disk_io_wal_concentration"/g,
      ) ?? [];
    expect(occurrences.length).toBe(1);
  });

  it("the feature tag appears in both the cron emit + the alert filter", () => {
    // Anchored (value-equality / closing-quote) so a suffix rename fails.
    expect(cron).toContain(`feature: "${FEATURE_TAG}"`);
    expect(tfBlock).toMatch(new RegExp(`value\\s*=\\s*"${FEATURE_TAG}"`));
  });

  it("the wal-concentration op appears in both the cron emit + the alert filter", () => {
    expect(cron).toContain(`op: "${ALERT_OP}"`);
    expect(tfBlock).toMatch(new RegExp(`value\\s*=\\s*"${ALERT_OP}"`));
  });

  it("ANDs its filters (filter_match all), both op + feature via EQUAL", () => {
    expect(tfBlock).toContain('filter_match = "all"');
    expect(tfBlock).toMatch(/key\s*=\s*"op"[\s\S]*?match\s*=\s*"EQUAL"/);
    expect(tfBlock).toMatch(/key\s*=\s*"feature"[\s\S]*?match\s*=\s*"EQUAL"/);
  });

  it("the rule's frequency is unique across all issue alerts in the file", () => {
    const freqMatch = tfBlock.match(/^\s*frequency\s*=\s*(\d+)/m);
    expect(freqMatch).not.toBeNull();
    const myFreq = freqMatch![1];
    const all =
      tf.match(new RegExp(`^\\s*frequency\\s*=\\s*${myFreq}\\b`, "gm")) ?? [];
    expect(all.length).toBe(1);
  });
});
