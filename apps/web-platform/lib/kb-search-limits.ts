/**
 * Single source of truth for the KB search query cap.
 *
 * `searchKb` throws `KbValidationError` above this, which the route turns into a
 * 400 — so any client that lets a longer query through produces a request that
 * cannot succeed. Shared so the input's `maxLength` and the server's validation
 * cannot drift: a client-side cap that is LOOSER than the server's is worse than
 * none, because `search-overlay`'s fetch only replaces results on `res.ok`, so
 * the 400 leaves the previous query's results rendered under the new query's
 * label with no error shown.
 */
export const MAX_KB_QUERY_LENGTH = 200;
