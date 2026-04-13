/**
 * Client-side push subscription management.
 *
 * subscribeToPush() requests a Web Push subscription from the browser and
 * saves it to the server via /api/push-subscription. unsubscribeFromPush()
 * removes it from both the browser and the server.
 */

function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; i++) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

export async function subscribeToPush(
  registration: ServiceWorkerRegistration,
): Promise<boolean> {
  const vapidPublicKey = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;
  if (!vapidPublicKey) {
    console.warn("NEXT_PUBLIC_VAPID_PUBLIC_KEY not set — push subscription skipped");
    return false;
  }

  try {
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(vapidPublicKey) as BufferSource,
    });

    const json = subscription.toJSON();
    const res = await fetch("/api/push-subscription", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        endpoint: json.endpoint,
        keys: {
          p256dh: json.keys?.p256dh,
          auth: json.keys?.auth,
        },
      }),
    });

    return res.ok;
  } catch (err) {
    console.warn("Push subscription failed:", err);
    return false;
  }
}

export async function unsubscribeFromPush(): Promise<boolean> {
  try {
    const registration = await navigator.serviceWorker.ready;
    const subscription = await registration.pushManager.getSubscription();
    if (!subscription) return true;

    await fetch("/api/push-subscription", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ endpoint: subscription.endpoint }),
    });

    await subscription.unsubscribe();
    return true;
  } catch (err) {
    console.warn("Push unsubscribe failed:", err);
    return false;
  }
}
