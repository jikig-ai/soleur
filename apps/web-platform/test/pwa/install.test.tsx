// happy-dom environment (matched by the `.test.tsx` include glob) — install.ts
// is DOM-dependent (window / navigator / matchMedia), so it runs here, not in
// the node `unit` project.
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import {
  isStandalone,
  isIos,
  isIosSafari,
  watchInstallPrompt,
} from "@/lib/pwa/install";

const IPHONE_SAFARI =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
const IPHONE_CHROME =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/120.0 Mobile/15E148 Safari/604.1";
const ANDROID_CHROME =
  "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36";

function setUserAgent(ua: string) {
  Object.defineProperty(window.navigator, "userAgent", {
    value: ua,
    configurable: true,
  });
}

let matchMediaSpy: ReturnType<typeof vi.fn>;

beforeEach(() => {
  matchMediaSpy = vi.fn().mockReturnValue({ matches: false });
  Object.defineProperty(window, "matchMedia", {
    value: matchMediaSpy,
    configurable: true,
    writable: true,
  });
  delete (window.navigator as Navigator & { standalone?: boolean }).standalone;
});

afterEach(() => {
  vi.restoreAllMocks();
  setUserAgent(ANDROID_CHROME);
});

describe("isStandalone", () => {
  test("true when display-mode:standalone matches", () => {
    matchMediaSpy.mockReturnValue({ matches: true });
    expect(isStandalone()).toBe(true);
  });

  test("true when iOS navigator.standalone is set", () => {
    (window.navigator as Navigator & { standalone?: boolean }).standalone = true;
    expect(isStandalone()).toBe(true);
  });

  test("false in a normal browser tab", () => {
    expect(isStandalone()).toBe(false);
  });
});

describe("isIos / isIosSafari", () => {
  test("iPhone Safari is iOS and iOS Safari", () => {
    setUserAgent(IPHONE_SAFARI);
    expect(isIos()).toBe(true);
    expect(isIosSafari()).toBe(true);
  });

  test("iPhone Chrome (CriOS) is iOS but NOT iOS Safari", () => {
    setUserAgent(IPHONE_CHROME);
    expect(isIos()).toBe(true);
    expect(isIosSafari()).toBe(false);
  });

  test("Android Chrome is neither", () => {
    setUserAgent(ANDROID_CHROME);
    expect(isIos()).toBe(false);
    expect(isIosSafari()).toBe(false);
  });
});

describe("watchInstallPrompt", () => {
  test("captures beforeinstallprompt (preventDefault) and fires onCapture", () => {
    const onCapture = vi.fn();
    const onInstalled = vi.fn();
    watchInstallPrompt(onCapture, onInstalled);

    const event = new Event("beforeinstallprompt", { cancelable: true });
    const preventSpy = vi.spyOn(event, "preventDefault");
    window.dispatchEvent(event);

    expect(preventSpy).toHaveBeenCalled();
    expect(onCapture).toHaveBeenCalledWith(event);
    expect(onInstalled).not.toHaveBeenCalled();
  });

  test("fires onInstalled on appinstalled", () => {
    const onCapture = vi.fn();
    const onInstalled = vi.fn();
    watchInstallPrompt(onCapture, onInstalled);

    window.dispatchEvent(new Event("appinstalled"));
    expect(onInstalled).toHaveBeenCalledTimes(1);
  });

  test("unsubscribe detaches both listeners", () => {
    const onCapture = vi.fn();
    const onInstalled = vi.fn();
    const unsub = watchInstallPrompt(onCapture, onInstalled);
    unsub();

    window.dispatchEvent(new Event("beforeinstallprompt", { cancelable: true }));
    window.dispatchEvent(new Event("appinstalled"));

    expect(onCapture).not.toHaveBeenCalled();
    expect(onInstalled).not.toHaveBeenCalled();
  });
});
