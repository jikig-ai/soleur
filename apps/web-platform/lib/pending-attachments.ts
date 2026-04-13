/**
 * Module-level store for File[] that survives client-side SPA navigation.
 * Used to pass files from the Command Center first-run form to the chat page,
 * where they are uploaded after the conversation is created.
 *
 * Files expire after 5 minutes (staleness guard).
 */

const STALENESS_MS = 5 * 60 * 1000;

let pending: { files: File[]; timestamp: number } | null = null;

export function setPendingFiles(files: File[]): void {
  pending = { files, timestamp: Date.now() };
}

export function getPendingFiles(): File[] {
  if (!pending) return [];
  if (Date.now() - pending.timestamp > STALENESS_MS) {
    pending = null;
    return [];
  }
  return pending.files;
}

export function clearPendingFiles(): void {
  pending = null;
}
