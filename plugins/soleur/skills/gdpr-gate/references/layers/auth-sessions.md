<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->
# Layer: Auth & Sessions

## When This Layer Loads

Auto-trigger inline when Claude is about to generate:
- A login, logout, signup, or registration flow
- Any JWT creation, signing, or verification code
- Any token (access, refresh, reset, API key) generation or storage
- Any session creation, validation, or invalidation
- OAuth / SSO integration code
- Password reset or MFA / OTP flows
- Any `auth`, `session`, `token`, or `credential` handling

Also loads during full repo scan.

---

## A-01: PII in JWT Payload

What to grep:
```
jwt.sign(
jsonwebtoken.sign(
JWT.encode(
jose.SignJWT(
sign(payload
new SignJWT({
```

Flag when:
- PII fields in JWT payload: `{ email, name, ssn, dob, role, phone }`
- Health or financial data in token
- Full user object signed into JWT

Why it matters: JWT payloads are base64-encoded, not encrypted. Anyone who
intercepts or decodes the token can read every field in the payload.
`atob(token.split('.')[1])` in any browser reveals it all.

Fix pattern:
```javascript
// Wrong
const token = jwt.sign({
  userId: user.id,
  email: user.email,      // PII — readable by anyone
  role: user.role,
  ssn: user.ssn,          // critical — never in JWT
  plan: user.plan
}, secret)

// Right — opaque ID only, look up everything else server-side
const token = jwt.sign({
  sub: user.id,           // subject — opaque ID only
  iat: Date.now(),
  exp: Date.now() + 3600  // always set expiry
}, secret)
// Fetch user.email, user.role from DB on each request using sub
```

Regulation: CCPA, HIPAA (if health data in token), FTC Act

---

## A-02: Token Stored in localStorage

What to grep:
```
localStorage.setItem('token'
localStorage.setItem('jwt'
localStorage.setItem('access_token'
localStorage.setItem('auth'
sessionStorage.setItem('token'
```

Flag when:
- Any auth token stored in localStorage or sessionStorage
- JWT, access token, refresh token, or API key in client-side storage

Why it matters: localStorage is accessible to any JavaScript on the page.
An XSS vulnerability anywhere on the domain exposes all tokens.

Fix pattern:
```javascript
// Wrong
localStorage.setItem('token', accessToken)

// Right — server sets HttpOnly cookie, JS never touches the token
// Server-side:
res.cookie('access_token', token, {
  httpOnly: true,
  secure: true,
  sameSite: 'strict',
  maxAge: 3600000
})
// Client-side: token is sent automatically with requests, JS can't read it
```

Regulation: CCPA, FTC Act, PCI-DSS

---

## A-03: No Token Expiry

What to grep:
```
jwt.sign({           (check for missing exp/expiresIn)
expiresIn:           (check value — flag if > 24h for access tokens)
jwt.sign(payload, secret)   (no options = no expiry)
createToken(         (check implementation)
```

Flag when:
- JWT signed with no `exp` or `expiresIn`
- `expiresIn` set to days/weeks for access tokens (> 24h)
- Refresh tokens with no expiry at all
- Session tokens with no `maxAge` or `expires`

Fix pattern:
```javascript
// Wrong
const token = jwt.sign({ sub: user.id }, secret)  // no expiry — lives forever

// Right
const accessToken = jwt.sign({ sub: user.id }, secret, { expiresIn: '15m' })
const refreshToken = jwt.sign({ sub: user.id }, refreshSecret, { expiresIn: '7d' })
// Refresh tokens stored in DB so they can be revoked
```

Regulation: FTC Act, PCI-DSS (session timeout requirements)

---

## A-04: Password Reset Tokens — Single-Use Not Enforced

What to grep:
```
reset_token
password_reset_token
forgot_password
resetToken
verifyToken(
findOne({ reset_token:
```

Flag when:
- Reset token stored but no `used_at` or `expires_at` field
- Token not invalidated after use (can be reused)
- Token expiry too long (> 1 hour is too long for password reset)
- Token stored as plaintext (should be hashed like a password)

Fix pattern:
```javascript
// Wrong
await User.update({ reset_token: token }, { where: { id: userId } })
// Token never expires, never marked used

// Right
await User.update({
  reset_token_hash: await bcrypt.hash(token, 12),  // hash it
  reset_token_expires_at: new Date(Date.now() + 3600000), // 1 hour
  reset_token_used_at: null
}, { where: { id: userId } })

// On use:
await User.update({
  reset_token_hash: null,
  reset_token_expires_at: null,
  reset_token_used_at: new Date()
}, { where: { id: userId } })
```

Regulation: FTC Act, HIPAA (for health platforms)

---

## A-05: OAuth Scope Over-Request

What to grep:
```
scope:
scopes:
'https://www.googleapis.com/auth/
offline_access
openid profile email
passport.use(
```

Flag when:
- Requesting `offline_access` when refresh tokens aren't needed
- Requesting full profile scope when only email is used
- Google: requesting drive, calendar, or contacts when only email needed
- GitHub: requesting `repo` (full repo access) when only user info needed

Fix pattern:
```javascript
// Wrong
const scopes = ['openid', 'profile', 'email', 'offline_access',
                'https://www.googleapis.com/auth/drive']

// Right — request only what you actually use
const scopes = ['openid', 'email']
```

Regulation: FTC Act (data minimization principle), CCPA

---

## A-06: Session Not Invalidated on Logout

What to grep:
```
app.post('/logout'
router.post('/logout'
def logout(
async logout(
signOut(
```

Flag when:
- Logout only deletes client-side cookie/token without server-side invalidation
- No session store deletion on logout
- JWT-based auth with no token blocklist or short enough expiry

Fix pattern:
```javascript
// Wrong — client-side only logout
app.post('/logout', (req, res) => {
  res.clearCookie('session')  // cookie gone but server doesn't know
  res.json({ success: true })
})

// Right — invalidate server-side too
app.post('/logout', async (req, res) => {
  const token = req.cookies.session
  await SessionStore.delete(token)     // invalidate in DB/Redis
  await TokenBlocklist.add(token)      // blocklist if JWT
  res.clearCookie('session', { httpOnly: true, secure: true })
  res.json({ success: true })
})
```

Regulation: FTC Act, PCI-DSS, HIPAA

---

## A-07: MFA / OTP Codes Stored Plaintext or Without Expiry

What to grep:
```
otp_code
mfa_code
verification_code
two_factor_code
totp_secret
backup_codes
```

Flag when:
- OTP stored as plaintext integer/string without expiry
- TOTP secret stored without encryption
- Backup codes stored plaintext (should be hashed like passwords)
- No `expires_at` on OTP codes

Fix pattern:
```javascript
// Wrong
await User.update({ otp_code: 123456 }, { where: { id: userId } })

// Right
await User.update({
  otp_code_hash: await bcrypt.hash('123456', 12),  // hash it
  otp_expires_at: new Date(Date.now() + 600000),   // 10 min max
  otp_attempts: 0                                   // rate limit attempts
}, { where: { id: userId } })
```

Regulation: FTC Act, HIPAA, PCI-DSS

---

## EU extension — Art. 32(1)(b) confidentiality

A-01..A-07 are Soleur-extended for the EU regime under GDPR Art. 32(1)(b)
("the ability to ensure the ongoing confidentiality, integrity, availability
and resilience of processing systems and services"). Storing PII in JWT
payloads, leaking session tokens to logs, or persisting OTP secrets in plain
text are confidentiality failures under Art. 32 even when no other GDPR
article fires. Treat A-01..A-07 findings as Art. 32 candidates regardless of
whether a separate Art. 6 / Art. 9 / Art. 32 finding has already been raised
on the same diff.
