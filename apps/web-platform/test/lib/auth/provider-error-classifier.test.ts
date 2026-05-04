import { describe, it, expect } from "vitest";
import { classifyProviderError } from "@/lib/auth/provider-error-classifier";

/**
 * Provider-error classifier tests. The OAuth 2.0 `error` enum is closed:
 * `access_denied | server_error | temporarily_unavailable | invalid_request | invalid_scope | unauthorized_client | unsupported_response_type`.
 *
 * Map the user-cancel signal (`access_denied`) to `oauth_cancelled` so the
 * `/login` copy can distinguish "I changed my mind" from "the system broke".
 * Map the server-side classes (`server_error`, `temporarily_unavailable`) to
 * `oauth_failed`. Everything else (and missing/empty error) returns null so
 * the route falls through to the existing `callback_no_code` fallback.
 */
describe("classifyProviderError", () => {
  it("maps access_denied to oauth_cancelled", () => {
    expect(
      classifyProviderError(new URLSearchParams("error=access_denied")),
    ).toBe("oauth_cancelled");
  });

  it("maps server_error to oauth_failed", () => {
    expect(
      classifyProviderError(new URLSearchParams("error=server_error")),
    ).toBe("oauth_failed");
  });

  it("maps temporarily_unavailable to oauth_failed", () => {
    expect(
      classifyProviderError(
        new URLSearchParams("error=temporarily_unavailable"),
      ),
    ).toBe("oauth_failed");
  });

  it("returns null when no error key is present", () => {
    expect(classifyProviderError(new URLSearchParams(""))).toBeNull();
  });

  it("returns null when only error_description is present (no error key)", () => {
    expect(
      classifyProviderError(new URLSearchParams("error_description=foo")),
    ).toBeNull();
  });

  it("returns null for empty-string error value", () => {
    // Empty value: get('error') === '', which must NOT map to a hit.
    expect(classifyProviderError(new URLSearchParams("error="))).toBeNull();
  });

  it("returns null for malformed bracketed key (error[]=...)", () => {
    // WHATWG URL semantics: 'error[]' is its own key, distinct from 'error'.
    // get('error') returns null. Verifies the classifier does not normalize
    // or split bracketed forms.
    expect(
      classifyProviderError(
        new URLSearchParams("error[]=access_denied"),
      ),
    ).toBeNull();
  });

  it("returns oauth_failed for unrecognized OAuth 2.0 error codes", () => {
    // `invalid_request`, `invalid_scope`, `unauthorized_client`,
    // `unsupported_response_type` — all classed as `oauth_failed` because
    // the user copy is the same ("temporary problem, try again").
    expect(
      classifyProviderError(new URLSearchParams("error=invalid_scope")),
    ).toBe("oauth_failed");
    expect(
      classifyProviderError(new URLSearchParams("error=unauthorized_client")),
    ).toBe("oauth_failed");
  });

  it("uses get() (first occurrence) when error key is duplicated", () => {
    // Defensive: Supabase doesn't emit duplicates today, but if it ever
    // does, we want deterministic behavior. URLSearchParams.get returns
    // the first occurrence.
    expect(
      classifyProviderError(
        new URLSearchParams("error=access_denied&error=server_error"),
      ),
    ).toBe("oauth_cancelled");
  });

  it("is case-sensitive — 'Access_Denied' is not access_denied", () => {
    // Defensive: WHATWG URLSearchParams keys are case-sensitive on the
    // value side too. The classifier must not lowercase the value.
    expect(
      classifyProviderError(new URLSearchParams("error=Access_Denied")),
    ).toBe("oauth_failed");
  });

  it.each([
    "toString",
    "constructor",
    "hasOwnProperty",
    "__proto__",
    "valueOf",
  ])(
    "prototype-chain key %s does not masquerade as a table entry — falls to oauth_failed",
    (protoKey) => {
      // Without `Object.hasOwn`, `PROVIDER_ERROR_TABLE["toString"]` would
      // return `Object.prototype.toString` (truthy) and the route would
      // emit `/login?error=function toString() { [native code] }`. The
      // hardened classifier MUST default-branch to oauth_failed.
      expect(
        classifyProviderError(new URLSearchParams(`error=${protoKey}`)),
      ).toBe("oauth_failed");
    },
  );
});
