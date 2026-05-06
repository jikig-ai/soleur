/**
 * Spec acceptance criterion (knowledge-base/project/specs/feat-theme-toggle/spec.md):
 * the no-FOUC inline <script> MUST receive the per-request CSP nonce, otherwise
 * a strict `script-src 'nonce-...'` CSP would block it and the page would
 * paint with the default palette regardless of the user's stored choice —
 * defeating the no-FOUC guarantee.
 *
 * This test renders <NoFoucScript> as a Server Component would (with a static
 * nonce) and asserts the rendered <script> carries the nonce attribute. If
 * someone removes the nonce passthrough, this test fails before the bug
 * reaches CSP-protected production traffic.
 */
import { renderToStaticMarkup } from "react-dom/server";
import { describe, it, expect } from "vitest";
import { NoFoucScript } from "@/components/theme/no-fouc-script";

describe("NoFoucScript CSP nonce passthrough", () => {
  it("renders <script nonce='<nonce>'> when a nonce is provided", () => {
    const html = renderToStaticMarkup(<NoFoucScript nonce="test-nonce" />);
    expect(html).toMatch(/<script[^>]*\bnonce="test-nonce"/);
  });

  it("renders without nonce attribute when none is provided", () => {
    // Dev or pre-CSP environments may not have a nonce; the script should
    // still render so behaviour stays consistent. The attribute simply
    // shouldn't be present (rather than an empty/undefined string literal).
    const html = renderToStaticMarkup(<NoFoucScript />);
    expect(html).not.toMatch(/\bnonce="(undefined|null|)"/);
  });

  it("script body still contains the no-FOUC bootstrap (regression on accidental empty render)", () => {
    const html = renderToStaticMarkup(<NoFoucScript nonce="x" />);
    expect(html).toContain("soleur:theme");
    // The bootstrap uses `dataset.theme` (which writes to the data-theme
    // attribute at runtime) — pin the source-string form, not the eventual
    // DOM attribute name.
    expect(html).toContain("dataset.theme");
  });
});
