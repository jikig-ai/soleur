import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor, act, cleanup } from "@testing-library/react";

// Hoisted holders let the mocks stash the callbacks the component registers so
// the test can drive them (simulate a waiting worker / a captured prompt).
const h = vi.hoisted(() => ({
  isStandalone: false,
  isIosSafari: false,
  updateCb: null as ((w: unknown) => void) | null,
  onCapture: null as ((e: unknown) => void) | null,
  onInstalled: null as (() => void) | null,
  postSkipWaiting: vi.fn(),
}));

vi.mock("@/lib/pwa/sw-update", () => ({
  watchForUpdate: (_reg: unknown, cb: (w: unknown) => void) => {
    h.updateCb = cb;
    return () => {};
  },
  postSkipWaiting: h.postSkipWaiting,
  reloadOnControllerChange: () => () => {},
}));

vi.mock("@/lib/pwa/install", () => ({
  isStandalone: () => h.isStandalone,
  isIosSafari: () => h.isIosSafari,
  watchInstallPrompt: (onCapture: (e: unknown) => void, onInstalled: () => void) => {
    h.onCapture = onCapture;
    h.onInstalled = onInstalled;
    return () => {};
  },
}));

import { PwaControls } from "@/components/pwa/pwa-controls";

beforeEach(() => {
  h.isStandalone = false;
  h.isIosSafari = false;
  h.updateCb = null;
  h.onCapture = null;
  h.onInstalled = null;
  h.postSkipWaiting.mockClear();
  sessionStorage.clear();
  Object.defineProperty(navigator, "serviceWorker", {
    value: { ready: Promise.resolve({}) },
    configurable: true,
    writable: true,
  });
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("PwaControls", () => {
  test("renders null when running standalone", () => {
    h.isStandalone = true;
    const { container } = render(<PwaControls />);
    expect(container).toBeEmptyDOMElement();
  });

  test("renders nothing when not standalone and nothing is offerable", () => {
    const { container } = render(<PwaControls />);
    expect(container).toBeEmptyDOMElement();
  });

  test("shows the update pill when a worker is waiting; Reload posts SKIP_WAITING", async () => {
    render(<PwaControls />);
    // Let navigator.serviceWorker.ready resolve so watchForUpdate registers.
    await waitFor(() => expect(h.updateCb).not.toBeNull());

    const worker = { id: "waiting" };
    act(() => h.updateCb!(worker));

    const reload = await screen.findByRole("button", { name: "Reload" });
    expect(screen.getByText("Update available")).toBeTruthy();

    fireEvent.click(reload);
    expect(h.postSkipWaiting).toHaveBeenCalledWith(worker);
  });

  test("update pill is dismissible", async () => {
    render(<PwaControls />);
    await waitFor(() => expect(h.updateCb).not.toBeNull());
    act(() => h.updateCb!({ id: "w" }));

    await screen.findByText("Update available");
    fireEvent.click(screen.getByRole("button", { name: "Dismiss update notice" }));
    expect(screen.queryByText("Update available")).toBeNull();
  });

  test("shows the install button when a prompt is captured; click calls prompt()", async () => {
    render(<PwaControls />);
    await waitFor(() => expect(h.onCapture).not.toBeNull());

    const prompt = vi.fn().mockResolvedValue(undefined);
    act(() => h.onCapture!({ prompt }));

    const button = await screen.findByRole("button", { name: /install app/i });
    fireEvent.click(button);
    expect(prompt).toHaveBeenCalledTimes(1);
  });

  test("shows the iOS guidance card on iOS Safari and persists dismissal", async () => {
    h.isIosSafari = true;
    render(<PwaControls />);

    expect(await screen.findByText(/Add to Home Screen/i)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Dismiss install guidance" }));

    expect(screen.queryByText(/Add to Home Screen/i)).toBeNull();
    expect(sessionStorage.getItem("soleur:pwa-ios-card-dismissed")).toBe("1");
  });

  test("does NOT show the iOS card if already dismissed this session", async () => {
    h.isIosSafari = true;
    sessionStorage.setItem("soleur:pwa-ios-card-dismissed", "1");
    const { container } = render(<PwaControls />);
    // Nothing else offerable → empty.
    await waitFor(() => expect(container).toBeEmptyDOMElement());
  });
});
