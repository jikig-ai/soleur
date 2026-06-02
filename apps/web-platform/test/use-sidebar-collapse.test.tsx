import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, act } from "@testing-library/react";
import {
  useSidebarCollapse,
  ORPHAN_COLLAPSE_KEYS,
  __resetOrphanCleanupForTests,
} from "@/hooks/use-sidebar-collapse";

const STORAGE_KEY = "soleur:sidebar.test.collapsed";
const MAIN_KEY = "soleur:sidebar.main.collapsed";

describe("useSidebarCollapse", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  afterEach(() => {
    localStorage.clear();
  });

  it("returns expanded (false) by default when no localStorage entry", () => {
    const { result } = renderHook(() => useSidebarCollapse(STORAGE_KEY));
    expect(result.current[0]).toBe(false);
  });

  it("returns a toggle function as second element", () => {
    const { result } = renderHook(() => useSidebarCollapse(STORAGE_KEY));
    expect(typeof result.current[1]).toBe("function");
  });

  it("toggles collapsed state when toggle is called", () => {
    const { result } = renderHook(() => useSidebarCollapse(STORAGE_KEY));
    act(() => {
      result.current[1]();
    });
    expect(result.current[0]).toBe(true);
  });

  it("toggles back to expanded on second call", () => {
    const { result } = renderHook(() => useSidebarCollapse(STORAGE_KEY));
    act(() => {
      result.current[1]();
    });
    expect(result.current[0]).toBe(true);
    act(() => {
      result.current[1]();
    });
    expect(result.current[0]).toBe(false);
  });

  it("persists collapsed state to localStorage", () => {
    const { result } = renderHook(() => useSidebarCollapse(STORAGE_KEY));
    act(() => {
      result.current[1]();
    });
    expect(localStorage.getItem(STORAGE_KEY)).toBe("1");
  });

  it("removes localStorage entry when expanded", () => {
    localStorage.setItem(STORAGE_KEY, "1");
    const { result } = renderHook(() => useSidebarCollapse(STORAGE_KEY));
    // Hydration reads "1" → collapsed
    expect(result.current[0]).toBe(true);
    act(() => {
      result.current[1]();
    });
    expect(localStorage.getItem(STORAGE_KEY)).toBeNull();
  });

  it("hydrates from localStorage on mount", () => {
    localStorage.setItem(STORAGE_KEY, "1");
    const { result } = renderHook(() => useSidebarCollapse(STORAGE_KEY));
    expect(result.current[0]).toBe(true);
  });

  it("uses different keys for different sidebars", () => {
    const keyA = "soleur:sidebar.a.collapsed";
    const keyB = "soleur:sidebar.b.collapsed";
    localStorage.setItem(keyA, "1");

    const { result: resultA } = renderHook(() => useSidebarCollapse(keyA));
    const { result: resultB } = renderHook(() => useSidebarCollapse(keyB));

    expect(resultA.current[0]).toBe(true);
    expect(resultB.current[0]).toBe(false);
  });

  // ADR-047 collapse-key unification (review: data-integrity + pattern-recognition).
  it("never lists the live unified key among the orphan keys to sweep", () => {
    // Regression guard: a future typo adding the main key to the orphan list
    // would make the hook delete the user's live collapse state on every mount.
    expect([...ORPHAN_COLLAPSE_KEYS]).not.toContain(MAIN_KEY);
  });

  it("sweeps the orphaned per-section keys on first mount, keeping the main key", () => {
    __resetOrphanCleanupForTests();
    localStorage.setItem(MAIN_KEY, "1");
    for (const k of ORPHAN_COLLAPSE_KEYS) localStorage.setItem(k, "1");

    renderHook(() => useSidebarCollapse(MAIN_KEY));

    // Orphans swept; the live unified key is untouched.
    for (const k of ORPHAN_COLLAPSE_KEYS) {
      expect(localStorage.getItem(k)).toBeNull();
    }
    expect(localStorage.getItem(MAIN_KEY)).toBe("1");
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

    const { result } = renderHook(() => useSidebarCollapse(STORAGE_KEY));
    // Should default to expanded without throwing
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
