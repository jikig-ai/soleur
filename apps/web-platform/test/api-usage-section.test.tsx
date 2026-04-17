import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen } from "@testing-library/react";

const { mockLoad } = vi.hoisted(() => ({ mockLoad: vi.fn() }));

vi.mock("@/server/api-usage", async () => {
  const actual =
    await vi.importActual<typeof import("@/server/api-usage")>(
      "@/server/api-usage",
    );
  return {
    ...actual,
    loadApiUsageForUser: mockLoad,
  };
});

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: vi.fn(), push: vi.fn() }),
}));

import { ApiUsageSection } from "@/components/settings/api-usage-section";

const VALID_UUID = "11111111-1111-1111-1111-111111111111";

async function renderSection(userId = VALID_UUID) {
  const element = await ApiUsageSection({ userId });
  render(element);
}

describe("ApiUsageSection", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-17T12:00:00Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  test("populated state: renders rows with [Department] labels, MTD summary", async () => {
    mockLoad.mockResolvedValueOnce({
      mtdTotalUsd: 4.27,
      mtdCount: 2,
      rows: [
        {
          id: "c1",
          domainLabel: "Marketing",
          createdAt: new Date("2026-04-17T10:00:00Z"),
          inputTokens: 1240,
          outputTokens: 3810,
          costUsd: 4.25,
        },
        {
          id: "c2",
          domainLabel: "Engineering",
          createdAt: new Date("2026-04-16T12:00:00Z"),
          inputTokens: 100,
          outputTokens: 200,
          costUsd: 0.02,
        },
      ],
    });

    await renderSection();

    expect(screen.getByText("API Usage")).toBeInTheDocument();
    expect(screen.getByText(/\$4\.27 in April · 2 conversations/)).toBeInTheDocument();
    expect(screen.getByText(/\[Marketing\]/)).toBeInTheDocument();
    expect(screen.getByText(/\[Engineering\]/)).toBeInTheDocument();
    expect(screen.getByText("$4.25")).toBeInTheDocument();
    expect(screen.getByText("$0.02")).toBeInTheDocument();
  });

  test("pure empty state fires only when MTD=0 AND rows empty", async () => {
    mockLoad.mockResolvedValueOnce({
      mtdTotalUsd: 0,
      mtdCount: 0,
      rows: [],
    });

    await renderSection();

    expect(screen.getByText("No API calls yet this month.")).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: /Start a conversation/i }),
    ).toBeInTheDocument();
  });

  test("zero-MTD-with-history: renders copy §2b helper line + prior rows, NOT empty state", async () => {
    mockLoad.mockResolvedValueOnce({
      mtdTotalUsd: 0,
      mtdCount: 0,
      rows: [
        {
          id: "c1",
          domainLabel: "Marketing",
          createdAt: new Date("2026-03-15T10:00:00Z"),
          inputTokens: 100,
          outputTokens: 200,
          costUsd: 0.0042,
        },
      ],
    });

    await renderSection();

    expect(
      screen.getByText(
        /Showing your last 50 conversations with cost\. Nothing billed this month yet\./,
      ),
    ).toBeInTheDocument();
    expect(screen.queryByText("No API calls yet this month.")).not.toBeInTheDocument();
    expect(screen.getByText("$0.0042")).toBeInTheDocument();
  });

  test("helper line does NOT render when MTD > 0", async () => {
    mockLoad.mockResolvedValueOnce({
      mtdTotalUsd: 1.5,
      mtdCount: 1,
      rows: [
        {
          id: "c1",
          domainLabel: "Marketing",
          createdAt: new Date("2026-04-17T10:00:00Z"),
          inputTokens: 100,
          outputTokens: 200,
          costUsd: 1.5,
        },
      ],
    });

    await renderSection();

    expect(
      screen.queryByText(/Nothing billed this month yet\./),
    ).not.toBeInTheDocument();
  });

  test("error state renders when loader returns null (with RetryButton)", async () => {
    mockLoad.mockResolvedValueOnce(null);

    await renderSection();

    expect(screen.getByText("Couldn't load your usage.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Retry/i })).toBeInTheDocument();
  });

  test("no 'estimated', 'approximate', 'around', 'roughly', or '~' in rendered DOM", async () => {
    mockLoad.mockResolvedValueOnce({
      mtdTotalUsd: 0.0042,
      mtdCount: 1,
      rows: [
        {
          id: "c1",
          domainLabel: "Marketing",
          createdAt: new Date("2026-04-17T10:00:00Z"),
          inputTokens: 100,
          outputTokens: 200,
          costUsd: 0.0042,
        },
      ],
    });

    await renderSection();

    const container = screen.getByText("API Usage").closest("section");
    expect(container).not.toBeNull();
    const text = container!.textContent ?? "";
    expect(text).not.toMatch(/estimated/i);
    expect(text).not.toMatch(/approximate/i);
    expect(text).not.toMatch(/around/i);
    expect(text).not.toMatch(/roughly/i);
    expect(text).not.toContain("~");
  });

  test("tooltip summaries render as accessible info triggers", async () => {
    mockLoad.mockResolvedValueOnce({
      mtdTotalUsd: 1.0,
      mtdCount: 1,
      rows: [
        {
          id: "c1",
          domainLabel: "Marketing",
          createdAt: new Date("2026-04-17T10:00:00Z"),
          inputTokens: 100,
          outputTokens: 200,
          costUsd: 1.0,
        },
      ],
    });

    await renderSection();

    expect(
      screen.getByText("What is a token?", { selector: "summary > span" }),
    ).toBeInTheDocument();
    expect(
      screen.getByText("Why does cost vary?", { selector: "summary > span" }),
    ).toBeInTheDocument();
  });

  test("row containers are not interactive (no role=button, no cursor-pointer)", async () => {
    mockLoad.mockResolvedValueOnce({
      mtdTotalUsd: 1.0,
      mtdCount: 1,
      rows: [
        {
          id: "c1",
          domainLabel: "Marketing",
          createdAt: new Date("2026-04-17T10:00:00Z"),
          inputTokens: 100,
          outputTokens: 200,
          costUsd: 1.0,
        },
      ],
    });

    await renderSection();

    // No row should advertise itself as a button
    const buttons = screen.queryAllByRole("button");
    const rowButtons = buttons.filter(
      (b) => b.textContent?.includes("[Marketing]"),
    );
    expect(rowButtons).toHaveLength(0);
  });
});
