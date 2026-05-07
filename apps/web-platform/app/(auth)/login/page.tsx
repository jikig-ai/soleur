import { Suspense } from "react";

import { LoginForm } from "@/components/auth/login-form";

export default async function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  );
}
