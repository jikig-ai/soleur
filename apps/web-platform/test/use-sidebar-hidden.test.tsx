import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, act } from "@testing-library/react";
import {
  useSidebarHidden,
  SIDEBAR_HIDDEN_KEY,
} from "@/hooks/use-sidebar-hidden";

const COLLAPSE_KEY = "soleur:sidebar.main.collapsed";

describe("useSidebarHidden", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  afterEach(() => {
    localStorage.clear();
  });

  it("defaults the storage key to soleur:sidebar.main.hidden", () => {
    expect(SIDEBAR_HIDDEN_KEY).toBe("soleur:sidebar.main.hidden");
  });

  it("returns visible (false) by default when no localStorage entry", () => {
    const { result } = renderHook(() => useSidebarHidden());
    expect(result.current[0]).toBe(false);
  });

  it("returns a toggle function as second element", () => {
    const { result } = renderHook(() => useSidebarHidden());
    expect(typeof result.current[1]).toBe("function");
  });

  it("toggles hidden state when toggle is called", () => {
    const { result } = renderHook(() => useSidebarHidden());
    act(() => {
      result.current[1]();
    });
    expect(result.current[0]).toBe(true);
  });

  it("toggles back to visible on second call", () => {
    const { result } = renderHook(() => useSidebarHidden());
    act(() => {
      result.current[1]();
    });
    expect(result.current[0]).toBe(true);
    act(() => {
      result.current[1]();
    });
    expect(result.current[0]).toBe(false);
  });

  it("persists hidden state to localStorage as '1'", () => {
    const { result } = renderHook(() => useSidebarHidden());
    act(() => {
      result.current[1]();
    });
    expect(localStorage.getItem(SIDEBAR_HIDDEN_KEY)).toBe("1");
  });

  it("removes the localStorage entry when visible again (never stores '0')", () => {
    localStorage.setItem(SIDEBAR_HIDDEN_KEY, "1");
    const { result } = renderHook(() => useSidebarHidden());
    // Hydration reads "1" → hidden
    expect(result.current[0]).toBe(true);
    act(() => {
      result.current[1]();
    });
    expect(localStorage.getItem(SIDEBAR_HIDDEN_KEY)).toBeNull();
  });

  it("hydrates from localStorage on mount", () => {
    localStorage.setItem(SIDEBAR_HIDDEN_KEY, "1");
    const { result } = renderHook(() => useSidebarHidden());
    expect(result.current[0]).toBe(true);
  });

  it("accepts an explicit storage key override", () => {
    const customKey = "soleur:sidebar.custom.hidden";
    localStorage.setItem(customKey, "1");
    const { result } = renderHook(() => useSidebarHidden(customKey));
    expect(result.current[0]).toBe(true);
    expect(localStorage.getItem(SIDEBAR_HIDDEN_KEY)).toBeNull();
  });

  // Orthogonality guard: hide and collapse are independent keys. Toggling hide
  // must never read or write the collapse key (and vice-versa) — a regression
  // here would couple the two states and corrupt the collapse boolean contract.
  it("is independent of the collapse key", () => {
    localStorage.setItem(COLLAPSE_KEY, "1");
    const { result } = renderHook(() => useSidebarHidden());
    // Collapse being set does not hide.
    expect(result.current[0]).toBe(false);
    act(() => {
      result.current[1]();
    });
    // Hiding does not disturb the collapse key.
    expect(localStorage.getItem(SIDEBAR_HIDDEN_KEY)).toBe("1");
    expect(localStorage.getItem(COLLAPSE_KEY)).toBe("1");
  });

  it("degrades gracefully when localStorage throws", () => {
    const getItemSpy = vi
      .spyOn(Storage.prototype, "getItem")
      .mockImplementation(() => {
        throw new DOMException("Access denied");
      });
    const setItemSpy = vi
      .spyOn(Storage.prototype, "setItem")
      .mockImplementation(() => {
        throw new DOMException("Access denied");
      });

    const { result } = renderHook(() => useSidebarHidden());
    // Should default to visible without throwing
    expect(result.current[0]).toBe(false);

    // Toggle should still work in-memory
    act(() => {
      result.current[1]();
    });
    expect(result.current[0]).toBe(true);

    getItemSpy.mockRestore();
    setItemSpy.mockRestore();
  });
});
