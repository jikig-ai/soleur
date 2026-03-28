import * as Sentry from "@sentry/nextjs";

export async function register() {
  // NOTE: register() is NOT called by Next.js when using a custom server.
  // Server-side Sentry.init() happens via direct import in server/index.ts.
  // This function is a no-op for our setup.
}

// Captures Next.js server component rendering errors
export const onRequestError = Sentry.captureRequestError;
