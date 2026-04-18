/**
 * Set a controlled input/textarea's value the way React expects, so the
 * component's onChange fires. Uses the native value descriptor to bypass
 * React's synthetic input tracker. Required for tests that rehydrate or
 * prepopulate textareas before asserting downstream behavior.
 */
export function setControlledValue(
  el: HTMLTextAreaElement | HTMLInputElement,
  value: string,
  cursor?: number,
): void {
  const proto =
    el instanceof HTMLTextAreaElement
      ? window.HTMLTextAreaElement.prototype
      : window.HTMLInputElement.prototype;
  const setter = Object.getOwnPropertyDescriptor(proto, "value")?.set;
  if (!setter) throw new Error("native value setter unavailable");
  setter.call(el, value);
  if (cursor !== undefined) {
    el.selectionStart = cursor;
    el.selectionEnd = cursor;
  }
  el.dispatchEvent(new Event("input", { bubbles: true }));
}
