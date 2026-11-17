/**
 * #12011 PR-C (AC13, AC14): the legal-acceptance pages (server components).
 *   - signed out: sign-in redirect that returns to the same path, and the registry is not consulted first;
 *   - a malformed key and an unknown key are the SAME not-found;
 *   - the text on the card is the registry body, and its hash is the registry hash (what is shown is what is hashed);
 *   - the founder's rows give the state; older rows render as "replaced" cards;
 *   - the surface gate (the configured founder id only; the approval-queue flag is not read, CTO ruling 2026-11-10) runs first; with
 *     the surface off the pages return not-found unless the founder has a recorded row for that key, and a pending card or an
 *     unreleased key never renders;
 *   - a registry text with no declared card kind is a not-found (and one Sentry event, after the gate) on the card page, and is left
 *     out of the index (#12344, CTO ruling 2026-11-07: no default kind);
 *   - a failed or malformed read is reported and throws, never an empty page.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import { createHash } from "node:crypto";
import { LEGAL_COPY, LEGAL_KIND_COPY } from "@/lib/legal-acceptance-copy";

const h = vi.hoisted(() => ({
  user: { value: { id: "00000000-0000-4000-8000-000000000007", email: "dana@example.com" } as { id: string; email: string } | null },
  rows: { value: [] as unknown },
  rowsError: { value: null as unknown },
  flag: vi.fn(),
  report: vi.fn(),
  lookups: [] as string[],
  from: [] as string[],
  secondKey: { value: false },
  noKindKey: { value: false },
  declared: { value: {} as Record<string, "terms" | "acknowledgement"> },
  textFailure: { value: null as unknown },
}));

const USER_ID = "00000000-0000-4000-8000-000000000007";
/** The terms wording: today's strings, moved into the kind map. */
const KC = LEGAL_KIND_COPY.terms;

// `customer-terms` and `other-terms` are not in the real LEGAL_TEXT_KIND (only the committed text is), so the kind lookup the
// pages use reads a per-test map. No fixture key is registered on the real (Readonly) map.
vi.mock("@/lib/legal-acceptance-copy", async (orig) => {
  const real = await orig<typeof import("@/lib/legal-acceptance-copy")>();
  return {
    ...real,
    legalKindCopy: (key: string) => real.legalKindCopy(key, h.declared.value),
    legalTextKind: (key: string) => real.legalTextKind(key, h.declared.value),
  };
});

class NotFound extends Error {}
class Redirect extends Error {
  constructor(public to: string) {
    super(to);
  }
}
vi.mock("next/navigation", () => ({
  notFound: () => {
    throw new NotFound("notFound");
  },
  redirect: (to: string) => {
    throw new Redirect(to);
  },
}));
vi.mock("next/link", () => ({ default: (p: { href: string; children: unknown }) => <a href={p.href}>{p.children as never}</a> }));

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: async () => ({ data: { user: h.user.value } }) },
    from: (table: string) => {
      h.from.push(table);
      const result = async () => ({ data: h.rows.value, error: h.rowsError.value });
      return { select: () => Object.assign(result(), { eq: () => ({ order: result }) }) };
    },
  }),
}));
vi.mock("@/server/approval/flag", () => ({ isApprovalQueueEnabled: (...a: unknown[]) => h.flag(...a) }));
vi.mock("@/server/approval/ops", async (orig) => ({
  ...(await orig<typeof import("@/server/approval/ops")>()),
  reportLegalOp: (...a: unknown[]) => h.report(...a),
}));

const RAW = "---\nversion: 3\nvalid_until: 2099-12-31\n---\nCUSTOMER TERMS\n\n1. Who these terms are between.\n\nEnd of version 3.\n";
const RAW_B = "---\nversion: 9\nvalid_until: 2099-12-31\n---\nOTHER TERMS\n\nEnd of version 9.\n";
const RAW_C = "---\nversion: 5\nvalid_until: 2099-12-31\n---\nNO KIND\n\nEnd of version 5.\n";
vi.mock("@/server/legal-acceptance/canonical", async (orig) => {
  const real = await orig<typeof import("@/server/legal-acceptance/canonical")>();
  return {
    ...real,
    getLegalText: (key: string) => {
      h.lookups.push(key);
      if (h.textFailure.value) throw h.textFailure.value;
      if (key === "no-kind" && h.noKindKey.value) return real.parseLegalText(key, RAW_C);
      if (key === "other-terms" && h.secondKey.value) return real.parseLegalText(key, RAW_B);
      if (key !== "customer-terms") throw new real.LegalTextError("unknown_key", "no such legal text");
      return real.parseLegalText(key, RAW);
    },
    loadLegalTexts: () => {
      if (h.textFailure.value) throw h.textFailure.value;
      const m = new Map([["customer-terms", real.parseLegalText("customer-terms", RAW)]]);
      // A second registry key, only when a test asks for it (keeps the single-key tests above unchanged).
      if (h.secondKey.value) m.set("other-terms", real.parseLegalText("other-terms", RAW_B));
      if (h.noKindKey.value) m.set("no-kind", real.parseLegalText("no-kind", RAW_C));
      return m;
    },
  };
});

import Page from "@/app/(dashboard)/dashboard/approvals/legal/[key]/page";
import IndexPage from "@/app/(dashboard)/dashboard/approvals/legal/page";
import { resetSurfaceConfigReport } from "@/server/legal-acceptance/surface";

const HASH = createHash("sha256").update(RAW).digest("hex");
const OLD = "d".repeat(64);
const row = (over: Record<string, unknown> = {}) => ({
  key: "customer-terms",
  text_hash: HASH,
  version: "3",
  choice: "accept",
  requested_edit: null,
  reauth_at: "2026-11-04T10:42:00Z",
  created_at: "2026-11-04T10:42:10Z",
  ...over,
});
const call = (key: string) => Page({ params: Promise.resolve({ key }) });

beforeEach(() => {
  vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", USER_ID);
  h.declared.value = { "customer-terms": "terms", "other-terms": "terms" };
  h.noKindKey.value = false;
  h.user.value = { id: USER_ID, email: "dana@example.com" };
  h.rows.value = [];
  h.rowsError.value = null;
  h.flag.mockReset(); // the surface does not read the flag; only the P1 case below sets it, and only to false
  h.report.mockReset();
  resetSurfaceConfigReport(); // the once-per-process config report must not leak between tests
  h.lookups.length = 0;
  h.from.length = 0;
  h.secondKey.value = false;
  h.textFailure.value = null;
});
afterEach(() => {
  cleanup();
  vi.unstubAllEnvs();
});

describe("auth gate and key handling", () => {
  it("signed out: redirects to sign-in with this path, reads no registry text and no rows", async () => {
    h.user.value = null;
    await expect(call("customer-terms")).rejects.toMatchObject({ to: "/login?redirectTo=%2Fdashboard%2Fapprovals%2Flegal%2Fcustomer-terms" });
    expect(h.lookups).toEqual([]);
    expect(h.from).toEqual([]);
  });

  it("a malformed key and an unknown key end in the same not-found", async () => {
    await expect(call("Bad Key!")).rejects.toBeInstanceOf(NotFound);
    await expect(call("../etc/passwd")).rejects.toBeInstanceOf(NotFound);
    await expect(call("no-such-text")).rejects.toBeInstanceOf(NotFound);
    expect(h.from).toEqual([]);
  });
});

describe("what the card shows", () => {
  it("renders the registry body and the registry hash is the hash of the raw bytes that end in that body", async () => {
    render(await call("customer-terms"));
    const region = screen.getByRole("region", { name: /exact text/i });
    expect(region.textContent).toBe("CUSTOMER TERMS\n\n1. Who these terms are between.\n\nEnd of version 3.\n");
    expect(RAW.endsWith(region.textContent as string)).toBe(true);
    expect(createHash("sha256").update(RAW).digest("hex")).toBe(HASH);
    expect(screen.getByRole("button", { name: /^Yes/ })).toBeInTheDocument();
    expect(h.from).toEqual(["legal_acceptance"]);
  });

  it("the current row gives the state: accepted", async () => {
    h.rows.value = [row()];
    render(await call("customer-terms"));
    expect(screen.getByText(KC.acceptedBadge)).toBeInTheDocument();
    expect(screen.getByText("Confirmed with an email code, Wed 4 Nov 2026, 10:42 UTC")).toBeInTheDocument();
  });

  it("an older text's row renders as a replaced card next to the current pending card", async () => {
    h.rows.value = [row({ text_hash: OLD, version: "2", choice: "request_changes", requested_edit: "shorter", reauth_at: null })];
    render(await call("customer-terms"));
    expect(screen.getByText(LEGAL_COPY.pending.badge)).toBeInTheDocument();
    expect(screen.getByText(LEGAL_COPY.replaced.badge)).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: LEGAL_COPY.replaced.title("2", "3") })).toBeInTheDocument();
  });

  it("surface off: an existing recorded row still renders (read-only, no actions)", async () => {
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "");
    h.rows.value = [row({ choice: "decline", reauth_at: null })];
    render(await call("customer-terms"));
    expect(screen.getByText(LEGAL_COPY.declined.badge)).toBeInTheDocument();
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("surface off and no recorded row: not-found, and no pending card or registry text is rendered", async () => {
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "");
    h.rows.value = [];
    await expect(call("customer-terms")).rejects.toBeInstanceOf(NotFound);
  });

  it("surface off with only an OLDER text's row: the older answer renders, the current pending text and its link do not", async () => {
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "");
    h.rows.value = [row({ text_hash: OLD, version: "2", choice: "decline", reauth_at: null })];
    const { container } = render(await call("customer-terms"));
    expect(screen.getByText(LEGAL_COPY.replaced.badge)).toBeInTheDocument();
    expect(screen.queryByText(LEGAL_COPY.pending.badge)).toBeNull();
    expect(container.textContent).not.toContain("CUSTOMER TERMS");
    expect(container.querySelector("#current-version")).toBeNull();
    expect(container.querySelector('a[href="#current-version"]')).toBeNull();
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("founder gate: a signed-in user who is not the configured founder gets the same not-found, and no event", async () => {
    h.user.value = { id: "00000000-0000-4000-8000-0000000000bb", email: "other@example.com" };
    await expect(call("customer-terms")).rejects.toBeInstanceOf(NotFound);
    await expect(IndexPage()).rejects.toBeInstanceOf(NotFound);
    expect(h.report).not.toHaveBeenCalled();
    h.user.value = { id: USER_ID, email: "dana@example.com" };
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "");
    await expect(call("customer-terms")).rejects.toBeInstanceOf(NotFound);
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "not-a-uuid");
    await expect(call("customer-terms")).rejects.toBeInstanceOf(NotFound);
    await expect(IndexPage()).rejects.toBeInstanceOf(NotFound);
    // Malformed: exactly one report; unset: none (CTO ruling F1, 2026-11-10: unset is the kill switch). So ONE config report across
    // the three requests above, never a user id or the variable's value, and no kind_undeclared event.
    expect(h.report.mock.calls.map((c) => c[0])).toEqual(["storeFailed"]);
    expect(h.report.mock.calls[0][2]).toEqual({ tags: { stage: "config" }, extra: { step: "config", variables: ["LEGAL_ACCEPTANCE_FOUNDER_ID"] } });
  });

  it("founder configured: the pending card is open for answers", async () => {
    render(await call("customer-terms"));
    expect(screen.getByText(LEGAL_COPY.pending.badge)).toBeInTheDocument();
    expect(screen.queryByText(KC.pendingNotAvailable)).toBeNull();
  });

  it("flag off and the founder configured: the pending card is open (P1, CTO ruling 2026-11-10)", async () => {
    h.flag.mockResolvedValue(false);
    render(await call("customer-terms"));
    expect(screen.getByText(LEGAL_COPY.pending.badge)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /^Yes/ })).toBeInTheDocument();
    expect(h.report).not.toHaveBeenCalled();
  });
});

describe("a registry text with no declared card kind (no default)", () => {
  it("the card page is a not-found and reports kindUndeclared exactly once, before any row is read", async () => {
    h.noKindKey.value = true;
    await expect(call("no-kind")).rejects.toBeInstanceOf(NotFound);
    expect(h.report).toHaveBeenCalledTimes(1);
    expect(h.report).toHaveBeenCalledWith("kindUndeclared", null, expect.objectContaining({ userId: USER_ID, tags: { key: "no-kind" } }));
    expect(h.from).toEqual([]);
  });

  it("an unknown or malformed key is a plain not-found with no Sentry event", async () => {
    h.noKindKey.value = true;
    await expect(call("no-such-text")).rejects.toBeInstanceOf(NotFound);
    await expect(call("Bad Key!")).rejects.toBeInstanceOf(NotFound);
    expect(h.report).not.toHaveBeenCalled();
  });

  it("surface off: the same not-found and no event (the gate runs first)", async () => {
    h.noKindKey.value = true;
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "");
    await expect(call("no-kind")).rejects.toBeInstanceOf(NotFound);
    expect(h.report).not.toHaveBeenCalled();
  });

  it("the index leaves the undeclared key out and reports it once; the declared keys are listed", async () => {
    h.noKindKey.value = true;
    render(await IndexPage());
    expect(screen.getAllByRole("link")).toHaveLength(1);
    expect(screen.queryByText(/No kind|no-kind/i)).toBeNull();
    expect(h.report.mock.calls.filter((c) => c[0] === "kindUndeclared")).toHaveLength(1);
    expect(h.report).toHaveBeenCalledWith("kindUndeclared", null, expect.objectContaining({ tags: { key: "no-kind" } }));
  });

  it("a declared acknowledgement text is labelled by its own first line and uses the acknowledgement wording", async () => {
    h.declared.value = { "customer-terms": "acknowledgement" };
    h.rows.value = [row()];
    const { container } = render(await call("customer-terms"));
    expect(screen.getByText(LEGAL_KIND_COPY.acknowledgement.acceptedBadge)).toBeInTheDocument();
    expect(container.textContent).toContain('You acknowledged "CUSTOMER TERMS"');
  });
});

describe("a failed read is reported and throws", () => {
  it("a read error", async () => {
    h.rowsError.value = { code: "XX000" };
    await expect(call("customer-terms")).rejects.toThrow("legal acceptance read failed");
    expect(h.report).toHaveBeenCalledWith("pageReadFailed", expect.anything(), expect.objectContaining({ extra: { read: "legal_acceptance" } }));
  });

  it("a broken registry (not an unknown key) is reported as pageReadFailed and throws, never an empty page or a not-found", async () => {
    const real = await vi.importActual<typeof import("@/server/legal-acceptance/canonical")>("@/server/legal-acceptance/canonical");
    for (const failure of [new Error("disk gone"), new real.LegalTextError("bad_bytes", "legal text is not valid UTF-8")]) {
      h.report.mockReset();
      h.textFailure.value = failure;
      await expect(call("customer-terms")).rejects.toThrow("legal text read failed");
      expect(h.report).toHaveBeenCalledTimes(1);
      expect(h.report).toHaveBeenCalledWith("pageReadFailed", failure, expect.objectContaining({ extra: { read: "legal_text" } }));
      expect(h.from).toEqual([]);
    }
  });

  it("an unknown key is a not-found and is NOT reported as a failed read", async () => {
    await expect(call("no-such-text")).rejects.toBeInstanceOf(NotFound);
    expect(h.report).not.toHaveBeenCalled();
  });

  it("a malformed row (unknown choice) is not rendered as an empty or pending card", async () => {
    h.rows.value = [row({ choice: "maybe" })];
    await expect(call("customer-terms")).rejects.toThrow("legal acceptance read failed");
    expect(h.report).toHaveBeenCalledTimes(1);
  });
});

describe("index page", () => {
  it("lists each key with its state in plain words and links to its card", async () => {
    render(await IndexPage());
    const link = screen.getByRole("link", { name: /Customer terms, version 3/ });
    expect(link).toHaveAttribute("href", "/dashboard/approvals/legal/customer-terms");
    expect(link).toHaveTextContent(LEGAL_COPY.index.state.pending);
  });

  it("shows the answer once a row exists", async () => {
    h.rows.value = [row({ choice: "decline" })];
    render(await IndexPage());
    expect(screen.getByRole("link")).toHaveTextContent(LEGAL_COPY.index.state.declined);
  });

  it("surface off and no recorded row: not-found, no key is listed", async () => {
    h.rows.value = [];
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "");
    await expect(IndexPage()).rejects.toBeInstanceOf(NotFound);
  });

  it("surface off with a recorded row: only the keys the founder has a row for are listed", async () => {
    h.rows.value = [row({ choice: "accept" })];
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "");
    render(await IndexPage());
    expect(screen.getAllByRole("link")).toHaveLength(1);
    expect(screen.getByRole("link")).toHaveTextContent(KC.indexAccepted);
  });

  it("surface off with a row only for an older text: listed, and the current pending text is 'not available yet'", async () => {
    h.rows.value = [row({ text_hash: OLD, version: "2", choice: "decline" })];
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "");
    render(await IndexPage());
    expect(screen.getByRole("link")).toHaveTextContent(LEGAL_COPY.index.notAvailable);
  });

  it("surface off with a row only for key A: key A is listed and key B (no row) is NOT, even though the registry has it", async () => {
    h.secondKey.value = true;
    h.rows.value = [row({ key: "customer-terms", choice: "accept" })];
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "");
    render(await IndexPage());
    expect(screen.getAllByRole("link")).toHaveLength(1);
    expect(screen.getByRole("link", { name: /Customer terms, version 3/ })).toHaveAttribute("href", "/dashboard/approvals/legal/customer-terms");
    expect(screen.queryByRole("link", { name: /Other terms/ })).toBeNull();
    expect(screen.queryByText(/Other terms/)).toBeNull();
  });

  it("surface off with a row only for key B: key B is listed and key A is not (the filter is per key, not 'any row exists')", async () => {
    h.secondKey.value = true;
    h.rows.value = [row({ key: "other-terms", text_hash: "e".repeat(64), version: "9", choice: "decline" })];
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "");
    render(await IndexPage());
    expect(screen.getAllByRole("link")).toHaveLength(1);
    expect(screen.getByRole("link", { name: /Other terms, version 9/ })).toBeInTheDocument();
    expect(screen.queryByText(/Customer terms/)).toBeNull();
  });

  it("founder configured: both registry keys are listed, with or without rows", async () => {
    h.secondKey.value = true;
    h.rows.value = [row({ key: "customer-terms" })];
    render(await IndexPage());
    expect(screen.getAllByRole("link")).toHaveLength(2);
  });

  it("a broken registry is reported as pageReadFailed and throws, never an empty list or a not-found", async () => {
    const failure = new Error("registry unreadable");
    h.textFailure.value = failure;
    await expect(IndexPage()).rejects.toThrow("legal text read failed");
    expect(h.report).toHaveBeenCalledTimes(1);
    expect(h.report).toHaveBeenCalledWith("pageReadFailed", failure, expect.objectContaining({ extra: { read: "legal_text" } }));
    expect(h.from).toEqual([]);
  });

  it("a malformed row is reported as pageReadFailed (index) and throws", async () => {
    h.rows.value = [row({ choice: "maybe" })];
    await expect(IndexPage()).rejects.toThrow("legal acceptance read failed");
    expect(h.report).toHaveBeenCalledWith("pageReadFailed", null, expect.objectContaining({ extra: { read: "legal_acceptance_index" } }));
  });

  it("signed out redirects; a failed read throws", async () => {
    h.user.value = null;
    await expect(IndexPage()).rejects.toMatchObject({ to: "/login?redirectTo=%2Fdashboard%2Fapprovals%2Flegal" });
    h.user.value = { id: "00000000-0000-4000-8000-000000000007", email: "dana@example.com" };
    h.rowsError.value = { code: "XX000" };
    await expect(IndexPage()).rejects.toThrow("legal acceptance read failed");
    expect(h.report).toHaveBeenCalledWith("pageReadFailed", expect.anything(), expect.objectContaining({ extra: { read: "legal_acceptance_index" } }));
  });
});
