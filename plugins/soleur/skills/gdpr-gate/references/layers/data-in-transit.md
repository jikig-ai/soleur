<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->
# Layer: Data in Transit

## When This Layer Loads

Auto-trigger inline when Claude is about to generate:
- Any `fetch`, `axios`, `requests`, `http` or similar HTTP client code
- Any middleware, interceptor, or request/response logger
- Any webhook handler or inbound HTTP endpoint
- Any internal service-to-service API call
- Any URL construction that includes user data
- Any request logging or monitoring setup

Also loads during full repo scan.

---

## T-01: PII in URL Query Parameters

What to grep:
```
?email=
?phone=
?ssn=
?token=          (in URL, not header)
?key=
`/api/users?email=${
`/search?phone=${
req.query.email
req.query.ssn
params[:email]
request.GET['email']
```

Flag when:
- PII passed as query parameter in any HTTP call
- Auth tokens in query strings: `?token=abc123`, `?api_key=xyz`
- Email used as query param for lookup: `/verify?email=john@doe.com`

Why it matters: Query parameters appear in:
- Server access logs (stored indefinitely by default)
- Browser history
- HTTP Referer headers sent to third parties
- CDN and proxy logs
- Analytics tools that capture full URLs

Fix pattern:
```javascript
// Wrong
await fetch(`/api/users?email=${email}&dob=${dob}`)
await fetch(`/api/verify?token=${resetToken}`)

// Right — POST body for PII, opaque IDs in URLs
await fetch('/api/users/lookup', {
  method: 'POST',
  body: JSON.stringify({ email, dob }),
  headers: { 'Content-Type': 'application/json' }
})

// For tokens — use short path param that's opaque, not the PII itself
await fetch(`/api/verify/${opaqueCode}`)
// Server resolves opaqueCode to user server-side — email never in URL
```

Regulation: CCPA, HIPAA, PCI-DSS

---

## T-02: Hardcoded HTTP (Not HTTPS) for Internal Calls

What to grep:
```
http://          (in fetch, axios, requests, etc — not localhost)
'http://api.
"http://service.
http://internal.
http://microservice.
requests.get('http://
axios.get('http://
fetch('http://
RestClient.get('http://
```

Flag when:
- Internal service-to-service calls over HTTP (not HTTPS)
- Hardcoded `http://` to non-localhost URLs in API clients
- Database connection strings using unencrypted protocol

Note: `http://localhost` is acceptable in development. Flag all others.

Fix pattern:
```javascript
// Wrong
const response = await axios.get('http://user-service.internal/api/users')
const data = await fetch('http://payments-api/charge')

// Right
const response = await axios.get('https://user-service.internal/api/users')
// Also: enforce via environment variables, never hardcode protocol+host
const API_BASE = process.env.USER_SERVICE_URL  // set to https:// in env
```

Regulation: HIPAA (transmission security), PCI-DSS, GLBA

---

## T-03: Webhook Signature Not Verified

What to grep:
```
app.post('/webhook'
router.post('/webhook'
app.post('/hooks/
def webhook(
async webhook(
stripe.webhooks.      (check if constructEvent is used)
```

Flag when:
- Webhook endpoint processes payload without verifying signature
- No `x-signature`, `x-hub-signature`, or vendor-specific header check
- Signature present but not validated before payload is processed

Why it matters: Unverified webhooks allow anyone to POST fake events
to your endpoint — including fake payment confirmations or user data.

Fix pattern:
```javascript
// Wrong
app.post('/webhook/stripe', express.json(), async (req, res) => {
  const event = req.body  // trusting payload blindly
  await processEvent(event)
})

// Right
app.post('/webhook/stripe',
  express.raw({ type: 'application/json' }),  // raw body needed for sig check
  async (req, res) => {
    const sig = req.headers['stripe-signature']
    let event
    try {
      event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET)
    } catch (err) {
      return res.status(400).send('Webhook signature verification failed')
    }
    await processEvent(event)
  }
)
```

Regulation: PCI-DSS, FTC Act

---

## T-04: PII in HTTP Headers (Non-Auth)

What to grep:
```
req.headers['x-user-email'
res.setHeader('x-user-
headers: { 'x-email':
'X-User-Data':
'X-Customer-Info':
```

Flag when:
- PII passed in custom HTTP headers between services
- Full user object serialized into a custom header
- Email, phone, or SSN in a forwarded header

Why it matters: Headers appear in proxy logs, CDN logs, and load balancer logs.
Custom headers with PII create unintended log exposure across your infrastructure.

Fix pattern:
```javascript
// Wrong
await fetch('/api/process', {
  headers: {
    'X-User-Email': user.email,
    'X-User-Phone': user.phone,
    'X-User-Data': JSON.stringify(user)
  }
})

// Right — pass opaque user ID only, resolve server-side
await fetch('/api/process', {
  headers: {
    'X-User-Id': user.id,           // opaque ID only
    'Authorization': `Bearer ${token}`
  }
})
```

Regulation: CCPA, HIPAA

---

## T-05: Sensitive Data in Request Logging Middleware

What to grep:
```
morgan(
app.use(logger(
expressWinston.logger(
requestLogger
logRequests
before_action :log
rack middleware
```

Flag when:
- Request logging middleware logs full request body
- No body sanitization before logging
- Response body logged (may contain PII from DB)

Fix pattern:
```javascript
// Wrong
app.use(morgan('combined'))  // logs full URL including query params with PII
app.use((req, res, next) => {
  console.log(req.body)  // logs passwords, PII
  next()
})

// Right
app.use(morgan(':method :url :status :response-time ms'))
// Custom sanitizing middleware
app.use((req, res, next) => {
  const safeBody = sanitizeForLog(req.body, ['password', 'ssn', 'card_number', 'cvv'])
  req.log = { method: req.method, path: req.path, body: safeBody }
  next()
})

function sanitizeForLog(body, sensitiveFields) {
  const safe = { ...body }
  sensitiveFields.forEach(f => { if (safe[f]) safe[f] = '[REDACTED]' })
  return safe
}
```

Regulation: CCPA, HIPAA, PCI-DSS

---

## T-06: HTTPS Not Enforced

What to grep:
```
http://             (non-localhost hardcoded URLs in server config)
HSTS
helmet(             (check if hsts is configured)
Strict-Transport-Security
force_ssl
config.force_ssl
SECURE_SSL_REDIRECT (Django)
```

Flag when:
- No HSTS header configured in production middleware
- No HTTP → HTTPS redirect middleware
- `http://` hardcoded in allowed origins or callback URLs
- `helmet()` used without HSTS config
- Django `SECURE_SSL_REDIRECT = False` or not set

Fix pattern:
```javascript
// Wrong — no HTTPS enforcement
app.use(helmet())  // helmet defaults don't include HSTS

// Right
app.use(helmet({
  hsts: {
    maxAge: 31536000,       // 1 year
    includeSubDomains: true,
    preload: true
  }
}))

// HTTP → HTTPS redirect middleware
app.use((req, res, next) => {
  if (process.env.NODE_ENV === 'production' && !req.secure) {
    return res.redirect(301, `https://${req.headers.host}${req.url}`)
  }
  next()
})
```

```python
# Django settings.py
SECURE_SSL_REDIRECT = True          # redirect HTTP → HTTPS
SECURE_HSTS_SECONDS = 31536000      # 1 year
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
```

```ruby
# Rails config/environments/production.rb
config.force_ssl = true
```

Regulation: HIPAA (transmission security), PCI-DSS, GLBA

---

## DT-EU-CB: Cross-Border Transfer (GDPR Chapter V)

EU extension (not in upstream Sprinto). Chapter V (Articles 44-49) restricts personal-data transfers outside the EEA / countries lacking an adequacy decision.

What to grep:
```
fetch("https://api.<vendor>.com/...
process.env.STRIPE_API_KEY
process.env.OPENAI_API_KEY
process.env.ANTHROPIC_API_KEY
process.env.SENDGRID_API_KEY
new <Vendor>Client(...)
```

Flag when:
- A new third-party vendor environment variable or SDK is introduced AND the vendor's data-processing locale is outside the EEA AND the vendor is not present in `knowledge-base/legal/compliance-posture.md` Vendor DPAs
- A request handler forwards request bodies, headers, or any user-derived field to a non-EEA endpoint

Why it matters: Each new non-EEA processor is a Chapter V transfer. Without a Standard Contractual Clauses (SCC) or adequacy basis recorded in `compliance-posture.md`, the transfer lacks a lawful basis and is a regulator-complaint-shaped failure surface.

Adequacy short-list (2026): EU/EEA, UK, Switzerland, Canada (commercial), Japan, South Korea, New Zealand, Argentina. US transfers require Data Privacy Framework participation OR SCCs.

Fix pattern: every new non-EEA vendor MUST land a Vendor DPA row in `compliance-posture.md` (operator-managed, gate never writes the row). The gate emits `Important` severity on detection so the row gap is visible at design time.

Regulation: GDPR Chapter V (Art. 44-49), UK GDPR, Swiss FADP
