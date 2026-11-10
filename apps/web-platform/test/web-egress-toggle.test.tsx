// @vitest-environment happy-dom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, expectTypeOf, it, vi } from "vitest";
import type { ReactNode } from "react";

// #9545 PR2 — the Agent web access card: the audit-log link, the "Last recorded request" hint, the
// retention sentence, the recording note and the enable-dialog notice. The recording notice
// is tri-state on the collection flag so an outage can never HIDE the disclosure from an owner.

vi.mock("@/components/ui/nav-link", () => ({
  NavLink: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}));

import { WebEgressToggle } from "@/components/settings/web-egress-toggle";
import type { CollectionState } from "@/lib/egress-audit/summary";

const LINK = "/dashboard/settings/scope-grants/egress-audit";
// Independent literals copied from the CLO ruling (knowledge-base/legal/audits/2026-10-counsel-review-9545.md,
// "verbatim as ruled"); deliberately NOT imported from the component, so a copy edit cannot pass by echo.
const RULED_NOTICE =
  "Hosts your agents contact are recorded as best-effort summary counts: the host, whether the request was allowed, blocked or ended another way, and the number of requests. Every current member of this workspace can view them, including activity from before they joined. No member or session is recorded, some entries may be missing, and counts are minimums. Records are deleted about 30 days after they were recorded. Turning web access off stops new records but does not delete existing ones.";
const RULED_UNKNOWN =
  "We couldn't check whether recording is on for this workspace. If it is, the following applies. " + RULED_NOTICE;
const NOTICE_START = "Hosts your agents contact are recorded as best-effort summary counts: the host, whether the request was allowed, blocked or ended another way, and the number of requests.";
const UNKNOWN_LEAD = "We couldn't check whether recording is on for this workspace. If it is, the following applies.";
const CARD_TRUE = "Activity through web access is recorded for this workspace and visible to every current member.";
const CARD_UNKNOWN = "Activity through web access may be recorded for this workspace and visible to every current member.";
const FORBIDDEN = /\bcomplete\b|every connection|tamper-proof|\bsessions\b/i;

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-26T12:10:00Z"));
});
afterEach(() => {
  cleanup();
  vi.useRealTimers();
});

const card = (over: Partial<Parameters<typeof WebEgressToggle>[0]> = {}) =>
  render(<WebEgressToggle initialWebEgress={false} isOwner lastRequestAt={null} collection={false} {...over} />);

describe("WebEgressToggle — props contract", () => {
  it("collection and lastRequestAt are required (no fail-open default); collection is the lib's CollectionState", () => {
    type P = Parameters<typeof WebEgressToggle>[0];
    expectTypeOf<P["collection"]>().toEqualTypeOf<CollectionState>();
    expectTypeOf<P["lastRequestAt"]>().toEqualTypeOf<string | null>();
    // @ts-expect-error collection must be passed: omitting it would silently hide the recording disclosure
    const missingCollection: P = { initialWebEgress: false, isOwner: true, lastRequestAt: null };
    // @ts-expect-error lastRequestAt must be passed
    const missingLast: P = { initialWebEgress: false, isOwner: true, collection: false };
    expect([missingCollection, missingLast]).toHaveLength(2);
  });
});

describe("WebEgressToggle — audit link and hint", () => {
  it("links to the egress audit log in both toggle states, for owners and non-owners", () => {
    let seen = 0;
    for (const webEgress of [false, true]) {
      for (const isOwner of [true, false]) {
        const { unmount } = card({ initialWebEgress: webEgress, isOwner });
        expect(screen.getByRole("link", { name: /View egress audit log/ }).getAttribute("href")).toBe(LINK);
        seen += 1;
        unmount();
      }
    }
    expect(seen).toBe(4);
  });

  it("shows 'Last recorded request: X ago' (client-rendered, clamped at zero) and nothing when there is no request", () => {
    card({ lastRequestAt: "2026-10-26T12:06:00Z" });
    expect(screen.getByText("Last recorded request: 4 minutes ago")).toBeTruthy();
    cleanup();
    card({ lastRequestAt: "2026-10-26T12:40:00Z" });
    expect(screen.getByText("Last recorded request: just now")).toBeTruthy();
    cleanup();
    card({ lastRequestAt: null });
    expect(screen.queryByText(/Last recorded request/)).toBeNull();
    expect(screen.getByRole("link", { name: /View egress audit log/ })).toBeTruthy();
  });

  it("the Off card states the retention fact only when a record exists; the On card does not", () => {
    const sentence = "Existing records stay visible to members until deleted about 30 days after they were recorded.";
    card({ initialWebEgress: false, lastRequestAt: "2026-10-26T12:06:00Z" });
    expect(screen.getByText(sentence)).toBeTruthy();
    cleanup();
    card({ initialWebEgress: false, lastRequestAt: null });
    expect(screen.queryByText(sentence)).toBeNull();
    cleanup();
    card({ initialWebEgress: true, lastRequestAt: "2026-10-26T12:06:00Z" });
    expect(screen.queryByText(sentence)).toBeNull();
  });

  it("every role sees the card note while collection is on or unknown, and nothing while it is off", () => {
    let seen = 0;
    for (const isOwner of [true, false]) {
      card({ isOwner, collection: true });
      expect(screen.getByText(CARD_TRUE).textContent).toBe(
        "Activity through web access is recorded for this workspace and visible to every current member.",
      );
      expect(screen.getByText(CARD_TRUE)).toBeTruthy();
      expect(screen.queryByText(CARD_UNKNOWN)).toBeNull();
      cleanup();
      card({ isOwner, collection: "unknown" });
      expect(screen.getByText(CARD_UNKNOWN).textContent).toBe(
        "Activity through web access may be recorded for this workspace and visible to every current member.",
      );
      expect(screen.queryByText(CARD_TRUE)).toBeNull();
      cleanup();
      card({ isOwner, collection: false });
      expect(screen.queryByText(CARD_TRUE)).toBeNull();
      expect(screen.queryByText(CARD_UNKNOWN)).toBeNull();
      expect(screen.queryByText(/recorded for this workspace/)).toBeNull();
      cleanup();
      seen += 1;
    }
    expect(seen).toBe(2);
    for (const c of [CARD_TRUE, CARD_UNKNOWN]) expect(c).not.toMatch(FORBIDDEN);
  });
});

describe("WebEgressToggle — enable dialog copy", () => {
  const open = (collection: boolean | "unknown") => {
    card({ collection });
    fireEvent.click(screen.getByRole("switch", { name: "Agent web access" }));
    return screen.getByRole("alertdialog");
  };

  it("never says every outbound request is logged", () => {
    let seen = 0;
    for (const c of [true, false, "unknown"] as const) {
      const dlg = open(c);
      expect(dlg.textContent).not.toMatch(/Every outbound request is logged/i);
      seen += 1;
      cleanup();
    }
    expect(seen).toBe(3);
  });

  it("collection on: shows the ruled best-effort notice (members, pre-join, no member or session, minimums, 30-day deletion, off keeps records)", () => {
    const text = open(true).textContent ?? "";
    expect(text).toContain(NOTICE_START);
    expect(text).toContain("Every current member of this workspace can view them, including activity from before they joined.");
    expect(text).toContain("No member or session is recorded, some entries may be missing, and counts are minimums.");
    expect(text).toContain("Records are deleted about 30 days after they were recorded.");
    expect(text).toContain("Turning web access off stops new records but does not delete existing ones.");
    expect(text).not.toContain(UNKNOWN_LEAD);
    expect(text).not.toMatch(FORBIDDEN);
  });

  it("collection on: the notice paragraph is exactly the CLO-ruled string (whole-string pin)", () => {
    const paras = Array.from(open(true).querySelectorAll("p")).map((p) => p.textContent);
    expect(paras.filter((t) => t === RULED_NOTICE)).toHaveLength(1);
    expect(paras.filter((t) => t?.includes(UNKNOWN_LEAD))).toHaveLength(0);
  });

  it("collection unknown: the notice paragraph is exactly the CLO-ruled composition (whole-string pin)", () => {
    const paras = Array.from(open("unknown").querySelectorAll("p")).map((p) => p.textContent);
    expect(paras.filter((t) => t === RULED_UNKNOWN)).toHaveLength(1);
    expect(paras.filter((t) => t === RULED_NOTICE)).toHaveLength(0);
  });

  it("collection unknown: says it could not check, then shows the full notice so an outage cannot hide the disclosure", () => {
    const text = open("unknown").textContent ?? "";
    expect(text).toContain(`${UNKNOWN_LEAD} ${NOTICE_START}`);
    expect(text).toContain("Turning web access off stops new records but does not delete existing ones.");
    expect(text).not.toMatch(FORBIDDEN);
  });

  it("collection off: no recording text at all", () => {
    const text = open(false).textContent ?? "";
    expect(text).not.toContain(NOTICE_START);
    expect(text).not.toContain(UNKNOWN_LEAD);
    expect(text).not.toMatch(/recorded/i);
  });
});

// #12469 T10 — the toggle must tell the owner what stops working (the command-line `gh`) and what replaces it, in the SAME
// release that ships the replacement. #12197 (CTO ruling F3, CLO W2, CPO W1, 2026-11-10): both sentences are accurate in
// both forwarder states, and the push sentence claims approval only for pushes made through Soleur. Independent literals
// from those rulings (the #12197 leader-rulings plan, Phase 2), deliberately NOT imported from the component, so a copy
// edit cannot pass by echo.
const PUSH_DISCLOSURE =
  "While this is on and a session's web access is running, commands an agent runs in its sandbox have no stored credentials, so they can't push to git remotes or use stored API keys. If web access can't start for a session, that session runs as if this were off: it has no web access, and its commands keep their usual access to your connected repository, which can include pushing. An agent may still ask to push a branch to your connected repository through Soleur; nothing is pushed that way unless the workspace owner approves that push.";
const GH_DISCLOSURE =
  "While this is on and a session's web access is running, the command-line gh tool is unavailable to agents in that session; for public repositories they still read your issues, pull requests, and CI status through Soleur, but can't create or edit them, and private repositories can't be read.";
// The retired hand-written phrases (#12197): absolute claims that are false when a session's web access fails to start.
const RETIRED_PHRASES = [
  "can't push to git remotes or use stored API keys while this is on",
  "agents can't push to git remotes",
];
const norm = (s: string) => s.replace(/\s+/g, " ").trim();
const count = (haystack: string, needle: string) => norm(haystack).split(norm(needle)).length - 1;

describe("WebEgressToggle — push and gh disclosures (#12469, #12197)", () => {
  it("shows each disclosure exactly once in the ON block and exactly once in the enable dialog", () => {
    const { container } = card({ initialWebEgress: true });
    const onText = container.textContent ?? "";
    expect(count(onText, PUSH_DISCLOSURE)).toBe(1);
    expect(count(onText, GH_DISCLOSURE)).toBe(1);
    cleanup();
    card({ initialWebEgress: false });
    fireEvent.click(screen.getByRole("switch", { name: "Agent web access" }));
    const dialogText = screen.getByRole("alertdialog").textContent ?? "";
    expect(count(dialogText, PUSH_DISCLOSURE)).toBe(1);
    expect(count(dialogText, GH_DISCLOSURE)).toBe(1);
    // the OFF card shows no ON block, so the dialog is the only place on the page that carries them
    const bodyText = document.body.textContent ?? "";
    expect(count(bodyText, PUSH_DISCLOSURE)).toBe(1);
    expect(count(bodyText, GH_DISCLOSURE)).toBe(1);
  });

  it("each disclosure is its own paragraph in the ON block and in the dialog", () => {
    const { container } = card({ initialWebEgress: true });
    const onParas = Array.from(container.querySelectorAll("p")).map((p) => norm(p.textContent ?? ""));
    expect(onParas.filter((t) => t === norm(PUSH_DISCLOSURE))).toHaveLength(1);
    expect(onParas.filter((t) => t === norm(GH_DISCLOSURE))).toHaveLength(1);
    cleanup();
    card({ initialWebEgress: false });
    fireEvent.click(screen.getByRole("switch", { name: "Agent web access" }));
    const dlgParas = Array.from(screen.getByRole("alertdialog").querySelectorAll("p")).map((p) => norm(p.textContent ?? ""));
    expect(dlgParas.filter((t) => t === norm(PUSH_DISCLOSURE))).toHaveLength(1);
    expect(dlgParas.filter((t) => t === norm(GH_DISCLOSURE))).toHaveLength(1);
  });

  it("neither the ON block nor the enable dialog carries a retired 'can't push to git remotes' phrase", () => {
    const { container } = card({ initialWebEgress: true });
    const onText = norm(container.textContent ?? "");
    cleanup();
    card({ initialWebEgress: false });
    fireEvent.click(screen.getByRole("switch", { name: "Agent web access" }));
    const dialogText = norm(screen.getByRole("alertdialog").textContent ?? "");
    let seen = 0;
    for (const phrase of RETIRED_PHRASES) {
      expect(onText).not.toContain(phrase);
      expect(dialogText).not.toContain(phrase);
      seen += 1;
    }
    expect(seen).toBe(2);
  });

  it("the gh disclosure names `gh`, public repositories, and that private repositories can't be read", () => {
    expect(GH_DISCLOSURE).toMatch(/gh tool is unavailable/);
    expect(GH_DISCLOSURE).toMatch(/public repositories/);
    expect(GH_DISCLOSURE).toMatch(/private repositories can't be read/);
  });

  it("does not claim a write capability or a scope-grant gate", () => {
    const { container } = card({ initialWebEgress: true });
    expect(container.textContent ?? "").not.toMatch(/scope.grant gate|can create|can edit/i);
  });
});

describe("push and gh disclosures: the Scope Grants page carries the identical strings (#12469, #12197, CPO condition)", () => {
  it("the page renders the SHARED constants (no hand-copied sentence), and the shared constants are the ruled literals", async () => {
    const { readFileSync } = await import("node:fs");
    const { resolve } = await import("node:path");
    const shared = await import("@/lib/web-egress-disclosure");
    expect(norm(shared.GH_DISCLOSURE)).toBe(norm(GH_DISCLOSURE));
    expect(norm(shared.PUSH_DISCLOSURE)).toBe(norm(PUSH_DISCLOSURE));
    const page = readFileSync(resolve(__dirname, "../app/(dashboard)/dashboard/settings/scope-grants/page.tsx"), "utf8");
    // JSX comments and string-literal decoys cannot satisfy this: it needs the import AND the expression containers.
    expect(page).toMatch(/^import \{ GH_DISCLOSURE, PUSH_DISCLOSURE \} from "@\/lib\/web-egress-disclosure";$/m);
    // Strip every comment form (JSX `{/* */}`, block, line) and every double-quoted string, so the bare expression containers
    // must survive in code: `{"" /* {GH_DISCLOSURE} */}` and `{"{GH_DISCLOSURE}"}` both lose them.
    const code = page
      .replace(/\{\/\*[\s\S]*?\*\/\}/g, "")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/(^|[^:])\/\/.*$/gm, "$1")
      .replace(/"[^"\n]*"/g, '""');
    expect(code).toMatch(/\{PUSH_DISCLOSURE\}/);
    expect(code).toMatch(/\{GH_DISCLOSURE\}/);
    // and the page no longer carries its own copy of either sentence, nor any hand-written push claim
    const pageText = norm(page.replace(/&apos;/g, "'"));
    expect(pageText).not.toContain(norm(GH_DISCLOSURE));
    expect(pageText).not.toContain(norm(PUSH_DISCLOSURE));
    expect(pageText).not.toContain("push to git remotes");
  });

  it("AC5: neither the toggle nor the page source holds 'push to git remotes', even wrapped across JSX lines", async () => {
    const { readFileSync } = await import("node:fs");
    const { resolve } = await import("node:path");
    const sources = [
      "../components/settings/web-egress-toggle.tsx",
      "../app/(dashboard)/dashboard/settings/scope-grants/page.tsx",
    ];
    let seen = 0;
    for (const rel of sources) {
      const src = norm(readFileSync(resolve(__dirname, rel), "utf8"));
      expect(src).not.toContain("push to git remotes");
      seen += 1;
    }
    expect(seen).toBe(2);
  });
});
