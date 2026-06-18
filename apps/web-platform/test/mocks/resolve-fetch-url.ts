/**
 * Normalize the first argument of a `fetch(input, init?)` call to a URL string,
 * for URL-aware fetch mocks. Handles the string, `Request`, and `URL`
 * (stringified) forms. Shared by chat-page fetch-routing tests.
 */
export function urlOf(input: unknown): string {
  return typeof input === "string"
    ? input
    : input instanceof Request
      ? input.url
      : String(input);
}
