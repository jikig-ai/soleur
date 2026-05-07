import { Suspense } from "react";

import { DevSignInPanel } from "@/components/auth/dev-sign-in-panel";
import { LoginForm } from "@/components/auth/login-form";

export default async function LoginPage() {
  return (
    <>
      {/* Renders only when NODE_ENV === "development" AND FLAG_DEV_SIGNIN=1.
          Non-dev returns null per the panel's inline gate; the runtime
          decision happens server-side, so no client JS bytes ship for it. */}
      <DevSignInPanel />
      <Suspense>
        <LoginForm />
      </Suspense>
    </>
  );
}
