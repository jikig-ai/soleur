import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract for the #6129 cosign verify-failure page, mirroring the sibling
// `sentry-*-alert-op-contract.test.ts` convention.
//
// `image_verify_failed` filters on `op == image-verify` AND `verify_result` not containing
// `reused_local_reload`. ci-deploy.sh's `cosign_verify_event` emits those tags on every verify
// failure, and ALSO on the #6512 same-version local-cache reload breadcrumb. Renaming the op or the
// verify_result tag key on either side would dark the page. Renaming the breadcrumb's result
// value would make the rule page on a non-failure. ci-deploy.test.sh reads the emitted event, not
// the rule, so neither change would red it. This binds the two sides. The filter-side assertions
// are scoped to THIS resource block, so a token in a comment or a sibling rule cannot mask its
// removal from the rule.

const here = dirname(fileURLToPath(import.meta.url));
// Whole-line `#` comments are stripped from both artifacts, so a comment naming a literal cannot
// satisfy an anchor that exists to pin the CODE (cq-assert-anchor-not-bare-token).
const stripComments = (text: string): string =>
  text
    .split("\n")
    .filter((l) => !/^\s*#/.test(l))
    .join("\n");
const tf = stripComments(readFileSync(join(here, "../infra/sentry/issue-alerts.tf"), "utf8"));
const ciDeploy = stripComments(readFileSync(join(here, "../infra/ci-deploy.sh"), "utf8"));

function tfBlockFor(resourceName: string): string {
  const decl = `resource "sentry_alert" "${resourceName}"`;
  const start = tf.indexOf(decl);
  if (start === -1) return "";
  const next = tf.indexOf("\nresource ", start + decl.length);
  return tf.slice(start, next === -1 ? undefined : next);
}

// The emitter's payload builder: the jq program inside cosign_verify_event.
function emitterBody(): string {
  const start = ciDeploy.indexOf("cosign_verify_event() {");
  if (start === -1) return "";
  const end = ciDeploy.indexOf("\n}\n", start);
  return ciDeploy.slice(start, end === -1 ? undefined : end);
}

describe("image_verify_failed alert ↔ ci-deploy.sh cosign_verify_event contract (#6129)", () => {
  const block = tfBlockFor("image_verify_failed");
  const emitter = emitterBody();

  it("declares the resource and the emitter", () => {
    expect(block).toContain('resource "sentry_alert" "image_verify_failed"');
    expect(emitter).toContain("cosign_verify_event() {");
  });

  it("the op literal is emitted as a tag and is the rule's filter value", () => {
    expect(emitter).toMatch(/tags:\s*\{[^}]*op:\s*"image-verify"/);
    expect(block).toContain('logic_type = "all"');
    expect(block).toMatch(/key\s*=\s*"op",\s*match\s*=\s*"eq",\s*value\s*=\s*"image-verify"/);
  });

  it("the verify_result tag key is emitted and the rule excludes exactly the reuse breadcrumb", () => {
    expect(emitter).toMatch(/tags:\s*\{[^}]*verify_result:\s*\$r/);
    expect(block).toMatch(
      /key\s*=\s*"verify_result",\s*match\s*=\s*"nc",\s*value\s*=\s*"reused_local_reload"/,
    );
    // The breadcrumb's result literal must be the excluded value, or the rule pages on it.
    expect(ciDeploy).toMatch(/^\s*cosign_verify_event "reused_local_reload" /m);
  });

  it("pages on the first event and has a unique frequency", () => {
    expect(block).toMatch(/event_frequency_count\s*=\s*\{\s*interval\s*=\s*"1h",\s*value\s*=\s*0\s*\}/);
    const m = block.match(/^\s*frequency_minutes\s*=\s*(\d+)/m);
    expect(m).not.toBeNull();
    const all = tf.match(new RegExp(`^\\s*frequency_minutes\\s*=\\s*${m![1]}\\b`, "gm")) ?? [];
    expect(all.length).toBe(1);
  });
});
