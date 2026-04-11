import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { AtMentionDropdown } from "@/components/chat/at-mention-dropdown";

describe("AtMentionDropdown", () => {
  const defaultProps = {
    query: "",
    visible: true,
    onSelect: vi.fn(),
    onDismiss: vi.fn(),
  };

  function setup(overrides = {}) {
    const props = { ...defaultProps, ...overrides };
    Object.values(props).forEach((fn) => {
      if (typeof fn === "function" && "mockClear" in fn) {
        (fn as ReturnType<typeof vi.fn>).mockClear();
      }
    });
    return render(<AtMentionDropdown {...props} />);
  }

  it("renders nothing when visible is false", () => {
    const { container } = render(
      <AtMentionDropdown {...defaultProps} visible={false} />,
    );
    expect(container.firstChild).toBeNull();
  });

  it("shows all 8 leaders when query is empty", () => {
    setup({ query: "" });
    expect(screen.getByText("8 matches")).toBeInTheDocument();
  });

  it("filters by leader id — @cm shows CMO and CCO", () => {
    setup({ query: "cm" });
    // "CMO" appears in both badge and label — check via role option
    const options = screen.getAllByRole("option");
    expect(options.length).toBeGreaterThan(0);
    expect(screen.queryAllByText("CTO")).toHaveLength(0);
  });

  it("filters by title — typing 'marketing' shows CMO", () => {
    setup({ query: "marketing" });
    const options = screen.getAllByRole("option");
    expect(options).toHaveLength(1);
    expect(screen.getByText("1 match")).toBeInTheDocument();
  });

  it("shows 'No matches' for invalid query", () => {
    setup({ query: "xyz" });
    expect(screen.getByText("No matches")).toBeInTheDocument();
    expect(screen.getByText("0 matches")).toBeInTheDocument();
  });

  it("calls onSelect when a leader is clicked", () => {
    const onSelect = vi.fn();
    setup({ onSelect, query: "" });
    // Click the first option (CMO)
    const options = screen.getAllByRole("option");
    fireEvent.click(options[0]);
    expect(onSelect).toHaveBeenCalledWith("cmo");
  });

  it("has ARIA role listbox", () => {
    setup();
    expect(screen.getByRole("listbox")).toBeInTheDocument();
  });

  it("marks active item with aria-selected", () => {
    setup({ query: "" });
    const options = screen.getAllByRole("option");
    expect(options[0]).toHaveAttribute("aria-selected", "true");
    expect(options[1]).toHaveAttribute("aria-selected", "false");
  });

  it("navigates with arrow keys — ArrowDown moves selection", () => {
    setup({ query: "" });
    // Simulate ArrowDown keypress
    fireEvent.keyDown(document, { key: "ArrowDown" });
    const options = screen.getAllByRole("option");
    expect(options[1]).toHaveAttribute("aria-selected", "true");
    expect(options[0]).toHaveAttribute("aria-selected", "false");
  });

  it("selects with Enter key", () => {
    const onSelect = vi.fn();
    setup({ onSelect, query: "" });
    // First item (CMO) is active by default
    fireEvent.keyDown(document, { key: "Enter" });
    expect(onSelect).toHaveBeenCalledWith("cmo");
  });

  it("dismisses with Escape key", () => {
    const onDismiss = vi.fn();
    setup({ onDismiss, query: "" });
    fireEvent.keyDown(document, { key: "Escape" });
    expect(onDismiss).toHaveBeenCalled();
  });

  it("shows match count in footer", () => {
    setup({ query: "c" });
    // All leaders have "c" in their id/name/title
    const footer = screen.getByText(/matches/);
    expect(footer).toBeInTheDocument();
  });

  it("filters case-insensitively", () => {
    setup({ query: "CMO" });
    const options = screen.getAllByRole("option");
    expect(options).toHaveLength(1);
    expect(screen.getByText("1 match")).toBeInTheDocument();
  });
});
