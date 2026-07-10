"use client";

// Device-local "last seen release" tracker (feat-releases-nav-badge). The
// Releases feed is Soleur's OWN web-v* GitHub releases — user-independent — so
// there is no per-account "read" state to hang a badge off. "New version"
// is therefore a per-device signal: we remember the newest tag this browser has
// looked at and dot the nav when a newer one ships. Deliberately localStorage,
// NOT server/account state, mirroring keyboard-shortcuts-toggle's reasoning (a
// per-device affordance, not a synced preference).
//
// First-load contract: a browser with NO record is SEEDED silently to the
// current latest (no dot). The user asked to know when a NEW version is
// published — i.e. one shipped after now — so an existing user is not nagged
// about a release they may already know about. The dot appears only on the
// NEXT publish after the seed.

import { useSyncExternalStore } from "react";

const STORAGE_KEY = "soleur:releases:last-seen-tag";
export const RELEASES_SEEN_CHANGED_EVENT = "soleur:releases-seen-changed";

/** Read the last-seen release tag, or null (no record / SSR / storage blocked). */
export function readLastSeenReleaseTag(): string | null {
  if (typeof window === "undefined") return null;
  try {
    return window.localStorage.getItem(STORAGE_KEY);
  } catch {
    // Private-mode / disabled storage: treat as "no record" rather than throw.
    return null;
  }
}

/**
 * Persist `tag` as the newest release this device has seen and notify any live
 * subscriber in THIS document (storage events do not fire in the same document
 * that wrote the value). No-ops when the value is unchanged so a re-render loop
 * can't churn the store. This is the "clear the dot" primitive — it overwrites
 * ANY prior value, so it must only be called when the user has genuinely seen
 * the feed (never on a passive first-load seed — use seedReleasesSeenIfEmpty).
 */
export function markReleasesSeen(tag: string): void {
  if (typeof window === "undefined" || !tag) return;
  try {
    if (window.localStorage.getItem(STORAGE_KEY) === tag) return;
    window.localStorage.setItem(STORAGE_KEY, tag);
  } catch {
    return;
  }
  window.dispatchEvent(new Event(RELEASES_SEEN_CHANGED_EVENT));
}

/**
 * First-load seed: record `tag` as seen ONLY when this device has no record
 * yet. Distinct from markReleasesSeen so the passive seed can never clobber a
 * real last-seen value (which would silently suppress a legitimate "new version"
 * dot). The "already have a record" check is at WRITE time, so it is robust even
 * if a caller fires it during a transient render where a reactive snapshot still
 * reads null (e.g. if an SSR/SWR fallback for the feed is added later).
 */
export function seedReleasesSeenIfEmpty(tag: string): void {
  if (typeof window === "undefined" || !tag) return;
  try {
    if (window.localStorage.getItem(STORAGE_KEY) !== null) return;
    window.localStorage.setItem(STORAGE_KEY, tag);
  } catch {
    return;
  }
  window.dispatchEvent(new Event(RELEASES_SEEN_CHANGED_EVENT));
}

// Parse a `web-vX.Y.Z` tag to a comparable tuple, or null for anything that
// doesn't match (draft/oddly-tagged releases).
function parseWebVersion(tag: string): [number, number, number] | null {
  const m = /^web-v(\d+)\.(\d+)\.(\d+)/.exec(tag);
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null;
}

/**
 * True when `candidate` is a STRICTLY newer web release than `baseline`. Used to
 * gate the "new version" dot on real forward progress, so a yanked/deleted
 * release regressing the newest tag can't paint a false dot on a rollback. When
 * either tag isn't a parseable `web-v*` version, fall back to plain inequality
 * so a non-standard tag still nudges rather than silently going dark.
 */
export function isNewerReleaseTag(candidate: string, baseline: string): boolean {
  const c = parseWebVersion(candidate);
  const b = parseWebVersion(baseline);
  if (!c || !b) return candidate !== baseline;
  for (let i = 0; i < 3; i++) {
    if (c[i] !== b[i]) return c[i] > b[i];
  }
  return false;
}

function subscribe(onChange: () => void): () => void {
  window.addEventListener(RELEASES_SEEN_CHANGED_EVENT, onChange);
  // Cross-tab: a write in another tab fires `storage` here.
  window.addEventListener("storage", onChange);
  return () => {
    window.removeEventListener(RELEASES_SEEN_CHANGED_EVENT, onChange);
    window.removeEventListener("storage", onChange);
  };
}

/**
 * Reactive read of the last-seen tag. Re-renders when this device (or another
 * tab) marks a release seen. SSR/first-client snapshot is `null` (matches the
 * server render), then the real value resolves post-hydration.
 */
export function useLastSeenReleaseTag(): string | null {
  return useSyncExternalStore(
    subscribe,
    readLastSeenReleaseTag,
    () => null,
  );
}
