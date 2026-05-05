import { describe, test, expect, vi } from "vitest";
import { render } from "@testing-library/react";

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

import { MessageBubble } from "../components/chat/message-bubble";

// Bug 2 (#3225): MessageBubble rendered both `displayName` ("Concierge") AND
// `leader.title` ("Soleur Concierge") side-by-side when showFullTitle=true,
// AND rendered bare "Concierge" on follow-up bubbles (showFullTitle=false).
// Fix: when leader.title.includes(displayName), promote the title into the
// always-rendered first span and suppress the secondary span. Generic
// substring rule — also catches the latent system "System"/"System Process"
// collision.
//
// All assertions scope to the `data-testid="message-bubble-header"` element
// so unrelated chrome (aria-labels, future tooltips, copy buttons) cannot
// drift the negative-space "Concierge" / "System" occurrence counts.

function getHeader(container: HTMLElement): HTMLElement {
  const header = container.querySelector<HTMLElement>(
    '[data-testid="message-bubble-header"]',
  );
  if (!header) throw new Error("message-bubble-header not found in container");
  return header;
}

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
    const header = getHeader(container);
    expect(header.textContent).toContain("Soleur Concierge");
    const concierges = header.textContent?.match(/Concierge/g) ?? [];
    expect(concierges).toHaveLength(1);
  });

  test("cc_router showFullTitle=FALSE (turn-2 / nudge bubble): header reads 'Soleur Concierge', not bare 'Concierge'", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content="hi"
        leaderId="cc_router"
        showFullTitle={false}
        messageState="done"
      />,
    );
    const header = getHeader(container);
    expect(header.textContent).toContain("Soleur Concierge");
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
    const header = getHeader(container);
    expect(header.textContent).toContain("System Process");
    const systems = header.textContent?.match(/System/g) ?? [];
    expect(systems).toHaveLength(1);
  });

  test("system showFullTitle=FALSE: header reads 'System Process', not bare 'System' (symmetric with the cc_router turn-2 case)", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content="health check"
        leaderId="system"
        showFullTitle={false}
        messageState="done"
      />,
    );
    const header = getHeader(container);
    expect(header.textContent).toContain("System Process");
    const systems = header.textContent?.match(/System/g) ?? [];
    expect(systems).toHaveLength(1);
  });

  test("non-prefix leader (cmo) showFullTitle=true: header still renders BOTH 'CMO' AND 'Chief Marketing Officer'", () => {
    const { container } = render(
      <MessageBubble
        role="assistant"
        content="brief"
        leaderId="cmo"
        showFullTitle
        messageState="done"
      />,
    );
    const header = getHeader(container);
    expect(header.textContent).toContain("CMO");
    expect(header.textContent).toContain("Chief Marketing Officer");
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
    const header = getHeader(container);
    expect(header.textContent).toContain("CMO Riley");
    expect(header.textContent).toContain("Chief Marketing Officer");
  });
});
