<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->
# Layer: Frontend / Client-Side Privacy

## When This Layer Loads

Auto-trigger inline when Claude is about to generate:
- A React / Vue / Svelte / Angular component, page, or form
- Any `localStorage`, `sessionStorage`, or `document.cookie` code
- Any third-party script or analytics SDK initialization (GA, Mixpanel, Sentry, Hotjar, LogRocket)
- Client-side routing that puts user data in path or query params
- Cookie-setting code (client or server-side `Set-Cookie`)

Also loads during full repo scan.

---

## F-01: PII in localStorage / sessionStorage

What to grep:
```
localStorage.setItem(
sessionStorage.setItem(
localStorage.setItem('user'
window.localStorage
```

Flag when:
- Full user objects stored: `localStorage.setItem('user', JSON.stringify(user))`
- PII fields stored directly: email, name, phone, dob, token, ssn
- Auth tokens stored in localStorage (XSS-accessible)

Why it matters: localStorage is readable by any JavaScript on the page —
including third-party scripts, browser extensions, and XSS payloads.

Fix pattern:
```javascript
// Wrong
localStorage.setItem('user', JSON.stringify({ email, name, phone, token }))

// Right — store only non-sensitive session state
localStorage.setItem('ui_preferences', JSON.stringify({ theme, language }))
// Auth tokens → HttpOnly cookies (set server-side, not accessible to JS)
```

Regulation: CCPA (PII exposure), FTC Act

---

## F-02: Cookie Flags Missing

What to grep:
```
res.cookie(
document.cookie
Set-Cookie:
cookies.set(
cookie.serialize(
```

Flag when:
- `HttpOnly` flag missing on auth/session cookies
- `Secure` flag missing (cookie sent over HTTP)
- `SameSite` not set (CSRF risk + cross-site tracking)
- PII stored directly in cookie value

Fix pattern:
```javascript
// Wrong
res.cookie('session', token)
res.cookie('user_data', JSON.stringify({ email, name }))

// Right
res.cookie('session', token, {
  httpOnly: true,       // not accessible to JavaScript
  secure: true,         // HTTPS only
  sameSite: 'strict',   // no cross-site sending
  maxAge: 3600000       // 1 hour — always set expiry
})
// Never store PII in cookie value — store only opaque session ID
```

Regulation: CCPA, FTC Act, PCI-DSS (session management)

---

## F-03: Third-Party Scripts Loading Without Consent Gate

What to grep:
```
<script src="https://www.googletagmanager.com
<script src="https://connect.facebook.net
<script src="https://static.hotjar.com
<script src="https://cdn.segment.com
gtag(        fbq(        _hsq.push(
mixpanel.init(    amplitude.init(    analytics.load(
```

Flag when:
- Analytics/tracking scripts load unconditionally on page load
- No consent check before initializing tracking
- Pixel fires on page load without checking consent state

Why it matters: Loading tracking scripts before consent is a CCPA/GDPR violation.
The script starts collecting IP, device data, and behavior immediately on load.

Fix pattern:
```javascript
// Wrong — fires immediately
<script src="https://www.googletagmanager.com/gtm.js"></script>

// Right — load only after consent
function initAnalytics() {
  if (!userHasConsented()) return
  const script = document.createElement('script')
  script.src = 'https://www.googletagmanager.com/gtm.js'
  document.head.appendChild(script)
}
```

Regulation: CCPA, FTC Act

---

## F-04: PII in console.log (Frontend)

What to grep:
```
console.log(user
console.log(response.data
console.log(formData
console.error(user
console.debug(
```

Flag when:
- User objects logged: `console.log('User:', user)`
- Form data logged: `console.log(formData)` (may contain email, password, PII)
- API responses logged: `console.log(response.data)` (may contain PII)

Why it matters: Browser console logs are visible to anyone with DevTools open,
and some monitoring tools forward console output.

Fix pattern:
```javascript
// Wrong
console.log('Login response:', response.data)  // may contain user PII
console.log('Form submitted:', formData)        // may contain password

// Right
console.log('Login successful, userId:', response.data.id)
if (process.env.NODE_ENV === 'development') {
  console.log('Form submitted')  // no payload in any environment
}
```

Regulation: FTC Act, CCPA

---

## F-05: Session Replay / Error Tools Capturing PII

What to grep:
```
LogRocket.init(
Hotjar.init(
FullStory.init(
Sentry.init(
replay:         (in Sentry config)
```

Flag when:
- LogRocket/Hotjar/FullStory initialized without input masking config
- Sentry Session Replay enabled without privacy config
- No `inputMask` or `blockClass` configuration to suppress PII fields

Fix pattern:
```javascript
// Wrong
LogRocket.init('app/id')

// Right
LogRocket.init('app/id', {
  dom: {
    inputSanitizer: true,     // masks all input fields
    textSanitizer: true,      // masks text nodes
  }
})

// Sentry with replay
Sentry.init({
  replaysSessionSampleRate: 0.1,
  integrations: [
    new Sentry.Replay({
      maskAllText: true,       // mask all text
      blockAllMedia: true,     // block images
      maskAllInputs: true,     // mask all form inputs
    })
  ]
})
```

Regulation: HIPAA (if health data visible), CCPA, FTC Act

---

## F-06: PII in URL Parameters

What to grep:
```
?email=
?phone=
?ssn=
?token=
router.push(`/users/${email}
window.location = `/verify?email=
<Link to={`/profile?name=
history.push(`?dob=
```

Flag when:
- PII passed as query parameters: `/reset?email=john@doe.com`
- PII in route path: `/users/john@doe.com/settings`
- Tokens in URLs: `/verify?token=abc123` (shows in browser history + server logs)

Fix pattern:
```javascript
// Wrong
router.push(`/reset-password?email=${email}&token=${token}`)

// Right — POST body or short-lived opaque reference
// Server generates a one-time code, URL contains only that
router.push(`/reset-password?code=${opaqueOneTimeCode}`)
// email resolved server-side from the code — never in URL
```

Regulation: CCPA, HIPAA (if health data), PCI-DSS

---

## EU extension — ePrivacy / TTDSG strict opt-in

F-01..F-06 are Soleur-extended for ePrivacy Directive 2002/58/EC (Art. 5(3))
and the German TTDSG §25, both of which require **strict opt-in consent**
before any non-essential storage or transmission to the user terminal —
including localStorage / sessionStorage writes, third-party SDK loads, and
analytics beacons. Implicit consent ("by using this site you agree…"),
pre-checked boxes, and cookie walls do not satisfy ePrivacy. Findings on
this layer cross-reference LC-01 in `legal-consent.md`; the LC layer carries
the consent-UX contract, this layer carries the frontend code-level traps.
