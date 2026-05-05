import { describe, test, expect, vi } from "vitest";
import { render } from "@testing-library/react";

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

import { MessageBubble } from "../components/chat/message-bubble";

// ---------------------------------------------------------------------------
// Bug 2 (#3225): the assistant bubble header rendered both the bare
// `displayName` ("Concierge") AND `leader.title` ("Soleur Concierge")
// side-by-side when `showFullTitle=true`, producing the duplicated
// "Concierge   Soleur Concierge" label users saw on the kb-concierge
// thread. The fix uses a generic substring rule: when
// `leader.title.includes(displayName)`, render `leader.title` ONLY (in the
// always-rendered first span) and suppress the showFullTitle title-span.
// Generic across leaders so the latent `system` collision (name "System" /
// title "System Process") is also handled.
// ---------------------------------------------------------------------------

describe("MessageBubble header substring suppression (Bug 2 #3225)", () => {
  test("cc_router showFullTitle=true: header reads 'Soleur Concierge' exactly once (no bare 'Concierge')", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content="hi"
        leaderId="cc_router"
        showFullTitle
        messageState="done"
      />,
    );
    const text = container.textContent ?? "";
    expect(text).toContain("Soleur Concierge");
    // Negative-space: under the bug the header rendered "Concierge" + "Soleur
    // Concierge" side-by-side, producing TWO occurrences of "Concierge". After
    // the fix it appears exactly once (inside "Soleur Concierge"). DOM
    // textContent concatenates adjacent spans without whitespace so a regex
    // gate with `\s+` misses the bug — count occurrences instead.
    const concierges = text.match(/Concierge/g) ?? [];
    expect(concierges).toHaveLength(1);
  });

  test("cc_router showFullTitle=FALSE (turn-2 / nudge bubble): header reads 'Soleur Concierge', not bare 'Concierge'", () => {
    // Real user evidence 2026-05-05: nudging a failed concierge bubble
    // produced a second assistant bubble whose header rendered just
    // "Concierge" — `showFullTitle` is false on follow-up bubbles per
    // chat-surface.tsx (`showFullTitle={!!isFirst}`). The substring rule
    // must promote `leader.title` into the always-rendered first span so
    // every concierge bubble shows the brand title.
    const { container } = render(
      <MessageBubble
        role="assistant"
        content="hi"
        leaderId="cc_router"
        showFullTitle={false}
        messageState="done"
      />,
    );
    const text = container.textContent ?? "";
    expect(text).toContain("Soleur Concierge");
    // The header should NOT be bare "Concierge" with no "Soleur " prefix.
    // We test by asserting the substring "Soleur" precedes "Concierge".
    const idx = text.indexOf("Concierge");
    expect(idx).toBeGreaterThanOrEqual(6);
    expect(text.slice(idx - 7, idx)).toBe("Soleur ");
  });

  test("system showFullTitle=true: header reads 'System Process' exactly once (regression guard for latent prefix collision)", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content="health check"
        leaderId="system"
        showFullTitle
        messageState="done"
      />,
    );
    const text = container.textContent ?? "";
    expect(text).toContain("System Process");
    // Negative-space: under the bug the header rendered "System" + "System
    // Process" side-by-side. Count "System" occurrences — exactly one (inside
    // "System Process").
    const systems = text.match(/System/g) ?? [];
    expect(systems).toHaveLength(1);
  });

  test("non-prefix leader (cmo) showFullTitle=true: header still renders BOTH 'CMO' AND 'Chief Marketing Officer' — substring rule must NOT fire when displayName is not contained in title", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content="brief"
        leaderId="cmo"
        showFullTitle
        messageState="done"
      />,
    );
    const text = container.textContent ?? "";
    expect(text).toContain("CMO");
    expect(text).toContain("Chief Marketing Officer");
  });

  test("getDisplayName-supplied team name + cmo: still renders both (e.g., 'CMO Riley' AND 'Chief Marketing Officer')", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content="brief"
        leaderId="cmo"
        showFullTitle
        messageState="done"
        getDisplayName={(id) => (id === "cmo" ? "CMO Riley" : id)}
      />,
    );
    const text = container.textContent ?? "";
    expect(text).toContain("CMO Riley");
    expect(text).toContain("Chief Marketing Officer");
  });
});
