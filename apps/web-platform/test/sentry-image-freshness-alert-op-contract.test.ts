import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Cross-artifact contract for the #6428 pre-swap image freshness page, mirroring the sibling
// `sentry-*-alert-op-contract.test.ts` convention.
//
// `image_freshness_mismatch` filters on the single tag `op == image-freshness`, which
// ci-deploy.sh's `image_freshness_event` emits on every aborted deploy. A rename on EITHER side —
// the jq payload literal or the `.tf` filter value — would zero the rule's matches and dark the
// page, while ci-deploy.test.sh (which reads the emitted event, not the rule) stays green. This
// binds the two sides. The filter-side assertions are scoped to THIS resource block so a token in
// a comment or a sibling rule cannot mask its removal from the rule.

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

// The emitter's payload builder: the jq program inside image_freshness_event.
function emitterBody(): string {
  const start = ciDeploy.indexOf("image_freshness_event() {");
  if (start === -1) return "";
  const end = ciDeploy.indexOf("\n}\n", start);
  return ciDeploy.slice(start, end === -1 ? undefined : end);
}

describe("image_freshness_mismatch alert ↔ ci-deploy.sh image_freshness_event contract (#6428)", () => {
  const block = tfBlockFor("image_freshness_mismatch");
  const emitter = emitterBody();

  it("declares the resource and the emitter", () => {
    expect(block).toContain('resource "sentry_alert" "image_freshness_mismatch"');
    expect(emitter).toContain("image_freshness_event() {");
  });

  it("the op literal is emitted as a tag and is the rule's filter value", () => {
    expect(emitter).toMatch(/tags:\s*\{[^}]*op:\s*"image-freshness"/);
    expect(block).toContain('logic_type = "all"');
    expect(block).toMatch(
      /key\s*=\s*"op",\s*match\s*=\s*"eq",\s*value\s*=\s*"image-freshness"/,
    );
  });

  it("every emitted event is level error (each one is an aborted deploy)", () => {
    expect(emitter).toContain('level: "error"');
    expect(emitter).not.toMatch(/level:\s*"warning"/);
  });

  it("pages on the first event and has a unique frequency", () => {
    expect(block).toMatch(/event_frequency_count\s*=\s*\{\s*interval\s*=\s*"1h",\s*value\s*=\s*0\s*\}/);
    const m = block.match(/^\s*frequency_minutes\s*=\s*(\d+)/m);
    expect(m).not.toBeNull();
    const all =
      tf.match(new RegExp(`^\\s*frequency_minutes\\s*=\\s*${m![1]}\\b`, "gm")) ?? [];
    expect(all.length).toBe(1);
  });

  it("the web deploy calls the check on VERIFIED_REF, before the stale-canary cleanup (code, not comments)", () => {
    const call = ciDeploy.indexOf('if ! verify_image_freshness "$VERIFIED_REF" "$TAG"; then');
    const canary = ciDeploy.indexOf("docker stop soleur-web-platform-canary");
    expect(call).toBeGreaterThan(-1);
    expect(canary).toBeGreaterThan(call);
  });
});
