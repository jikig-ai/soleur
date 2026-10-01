import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, fireEvent, act } from "@testing-library/react";
import { createRef } from "react";
import { Button } from "@/components/ui/button";
import { PENDING_ENTRY_DELAY_MS } from "@/lib/pending-timing";

afterEach(() => {
  vi.useRealTimers();
});

describe("Button", () => {
  it("defaults to the outlined variant and merges className", () => {
    render(<Button className="extra">Save</Button>);
    const btn = screen.getByRole("button", { name: "Save" });
    expect(btn.className).toContain("border-soleur-border-default");
    expect(btn.className).toContain("extra");
  });

  it("gold variant renders the GOLD_GRADIENT fill and on-accent label", () => {
    render(<Button variant="gold">Upgrade</Button>);
    const btn = screen.getByRole("button", { name: "Upgrade" });
    expect(btn.style.background).toContain("--soleur-accent-gradient-start");
    expect(btn.className).toContain("text-soleur-text-on-accent");
  });

  it("loading disables and sets aria-busy immediately, spinner after the entry delay", () => {
    vi.useFakeTimers();
    const { container } = render(<Button loading>Save</Button>);
    const btn = screen.getByRole("button", { name: "Save" });
    expect(btn).toBeDisabled();
    expect(btn).toHaveAttribute("aria-busy", "true");
    expect(container.querySelector(".animate-spin")).toBeNull();
    act(() => vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS + 10));
    expect(container.querySelector(".animate-spin")).not.toBeNull();
    expect(btn.className).toContain("disabled:opacity-[0.55]");
  });

  it("loading cannot be clicked", () => {
    const onClick = vi.fn();
    render(<Button loading onClick={onClick}>Save</Button>);
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(onClick).not.toHaveBeenCalled();
  });

  it("loadingLabel swaps the label immediately (ellipsis normalized); spinner arrives after the delay", () => {
    vi.useFakeTimers();
    render(<Button loading loadingLabel="Saving">Save</Button>);
    expect(screen.getByRole("button", { name: "Saving…" })).toBeInTheDocument();
    act(() => vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS + 10));
    expect(screen.getByRole("button", { name: "Saving…" })).toBeInTheDocument();
  });

  it("loadingLabel passed with a precomposed ellipsis is not doubled", () => {
    vi.useFakeTimers();
    render(<Button loading loadingLabel="Deleting…">Delete</Button>);
    act(() => vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS + 10));
    expect(screen.getByRole("button", { name: "Deleting…" })).toBeInTheDocument();
  });

  it("spinner color follows the variant token contract", () => {
    vi.useFakeTimers();
    const { container } = render(<Button variant="outlined" loading>Save</Button>);
    act(() => vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS + 10));
    expect(container.querySelector(".animate-spin")?.className).toContain(
      "text-soleur-accent-gold-fg",
    );
  });

  it("modal pending uses the 0.65 opacity floor", () => {
    render(<Button loading modal>Send</Button>);
    expect(screen.getByRole("button").className).toContain("disabled:opacity-[0.65]");
  });

  it("forwards type unchanged — untyped Button keeps implicit submit inside a form", () => {
    const onSubmit = vi.fn((e: React.SyntheticEvent) => e.preventDefault());
    render(
      <form onSubmit={onSubmit}>
        <Button>Go</Button>
      </form>,
    );
    const btn = screen.getByRole("button", { name: "Go" });
    expect(btn.getAttribute("type")).toBeNull();
    expect((btn as HTMLButtonElement).type).toBe("submit");
    fireEvent.click(btn);
    expect(onSubmit).toHaveBeenCalled();
  });

  it("type=\"button\" does not submit the enclosing form", () => {
    const onSubmit = vi.fn((e: React.SyntheticEvent) => e.preventDefault());
    render(
      <form onSubmit={onSubmit}>
        <Button type="button">Go</Button>
      </form>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Go" }));
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it("icon-only button swaps the icon for the spinner inside a pinned-size box", () => {
    vi.useFakeTimers();
    const { container } = render(
      <Button aria-label="Dismiss" loading>
        <svg data-testid="icon-child" />
      </Button>,
    );
    const btn = screen.getByRole("button", { name: "Dismiss" });
    expect(btn).toBeDisabled();
    expect(btn).toHaveAttribute("aria-busy", "true");
    // Before the delay the icon is untouched — no strobe.
    expect(screen.getByTestId("icon-child").className).not.toContain("invisible");
    act(() => vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS + 10));
    const icon = screen.getByTestId("icon-child");
    // Content-replacement: the icon stays mounted (box pinned) but invisible;
    // the spinner is absolutely centered — never appended.
    expect(icon.parentElement?.className).toContain("invisible");
    const spinner = container.querySelector(".animate-spin");
    expect(spinner?.className).toContain("absolute");
    expect(btn.textContent).toBe("");
  });

  it("forwards aria-*/data-*/title and the ref", () => {
    const ref = createRef<HTMLButtonElement>();
    render(
      <Button
        ref={ref}
        data-testid="cta"
        data-tour-id="upgrade"
        aria-describedby="hint"
        title="Upgrade now"
      >
        Upgrade
      </Button>,
    );
    const btn = screen.getByTestId("cta");
    expect(btn).toHaveAttribute("data-tour-id", "upgrade");
    expect(btn).toHaveAttribute("aria-describedby", "hint");
    expect(btn).toHaveAttribute("title", "Upgrade now");
    expect(ref.current).toBe(btn);
  });
});
