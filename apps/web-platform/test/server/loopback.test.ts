import { describe, expect, it } from "vitest";
import { hasProxyMarkers, isLoopbackHost, PROXY_MARKER_HEADERS } from "../../server/loopback";

describe("hasProxyMarkers (the second clause of the internal-endpoint gate)", () => {
  it("is false for an on-host caller (resource-monitor.sh sends only Host and a UA)", () => {
    expect(hasProxyMarkers({ host: "127.0.0.1:3000", "user-agent": "curl/8" })).toBe(false);
  });

  it.each([...PROXY_MARKER_HEADERS, "x-forwarded-for"])("is true when %s is present", (h) => {
    expect(hasProxyMarkers({ host: "127.0.0.1", [h]: "1.2.3.4" })).toBe(true);
  });

  it("is true even for an empty-string value (presence, not content, is the signal)", () => {
    expect(hasProxyMarkers({ host: "127.0.0.1", "cf-ray": "" })).toBe(true);
  });

  it("a loopback Host header alone still satisfies isLoopbackHost: the marker clause is what refuses it", () => {
    expect(isLoopbackHost("127.0.0.1")).toBe(true);
    expect(hasProxyMarkers({ host: "127.0.0.1", "cf-ray": "abc-LHR" })).toBe(true);
  });
});
