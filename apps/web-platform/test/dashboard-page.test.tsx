import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

// Mock next/navigation
const mockPush = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush }),
  useSearchParams: () => new URLSearchParams(),
}));

describe("DashboardPage", () => {
  beforeEach(() => {
    mockPush.mockClear();
  });

  it("renders 'COMMAND CENTER' label", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);
    expect(screen.getByText("COMMAND CENTER")).toBeInTheDocument();
  });

  it("renders 'What are you building today?' headline", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);
    expect(
      screen.getByText("What are you building today?"),
    ).toBeInTheDocument();
  });

  it("renders subtitle about auto-routing", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);
    expect(
      screen.getByText(/auto-route to the right experts/i),
    ).toBeInTheDocument();
  });

  it("renders a chat input", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);
    expect(
      screen.getByPlaceholderText(/ask your team/i),
    ).toBeInTheDocument();
  });

  it("renders 4 suggested prompt cards", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);
    // Each prompt card should have a title — look for known prompt texts
    const cards = screen.getAllByRole("button", { name: /review|draft|plan|prioritize/i });
    expect(cards.length).toBe(4);
  });

  it("clicking a prompt card fills the input (does NOT auto-submit)", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);
    const card = screen.getAllByRole("button", { name: /review|draft|plan|prioritize/i })[0];
    await userEvent.click(card);
    // Input should be filled but router should NOT have been called (no auto-submit)
    expect(mockPush).not.toHaveBeenCalled();
    const textarea = screen.getByPlaceholderText(/ask your team/i);
    expect((textarea as HTMLTextAreaElement).value).not.toBe("");
  });

  it("renders YOUR ORGANIZATION section with 8 leader abbreviations", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);
    expect(screen.getByText("YOUR ORGANIZATION")).toBeInTheDocument();
    // Should show all 8 leader abbreviations (may appear in multiple places)
    for (const abbr of ["CMO", "CTO", "CFO", "CPO", "CRO", "COO", "CLO", "CCO"]) {
      expect(screen.getAllByText(abbr).length).toBeGreaterThanOrEqual(1);
    }
  });

  it("navigates to chat page on message submit", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);
    const textarea = screen.getByPlaceholderText(/ask your team/i);
    await userEvent.type(textarea, "help with pricing");
    await userEvent.keyboard("{Enter}");
    expect(mockPush).toHaveBeenCalledWith(
      expect.stringContaining("/dashboard/chat/new?msg="),
    );
  });

  it("includes leader param in URL when @-mentioned", async () => {
    const { default: DashboardPage } = await import(
      "@/app/(dashboard)/dashboard/page"
    );
    render(<DashboardPage />);
    const textarea = screen.getByPlaceholderText(/ask your team/i);
    await userEvent.type(textarea, "@cmo help with marketing");
    await userEvent.keyboard("{Enter}");
    expect(mockPush).toHaveBeenCalledWith(
      expect.stringContaining("leader=cmo"),
    );
  });
});
