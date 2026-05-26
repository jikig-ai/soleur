<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->
# Layer: API Layer

## When This Layer Loads

Auto-trigger inline when Claude is about to generate:
- Any REST route handler or controller action
- Any GraphQL resolver, query, or mutation
- Any serializer, DTO, or response shaping code
- Any endpoint that fetches, updates, or returns user data
- Any bulk data endpoint or admin panel query
- Any error response handler

Also loads during full repo scan.

---

## AP-01: Full Object Returned in API Response

What to grep:
```
res.json(user)
res.json(req.user)
render json: @user
jsonify(user)
return user
JSON.stringify(user)
res.send(user)
serialize(user)        (check what fields are included)
```

Flag when:
- Full model object returned without field selection
- `password_hash`, `ssn`, `api_key`, or sensitive fields in response
- `SELECT *` used in query that feeds into response
- Serializer includes all fields by default

Fix pattern:
```javascript
// Wrong
app.get('/api/profile', auth, async (req, res) => {
  const user = await User.findById(req.user.id)
  res.json(user)  // returns password_hash, ssn, internal_score, everything
})

// Right — explicit field selection at query AND response level
app.get('/api/profile', auth, async (req, res) => {
  const user = await User.findById(req.user.id)
    .select('id name email createdAt')  // only what client needs
  res.json({
    id: user.id,
    name: user.name,
    email: user.email
    // explicit — nothing slips through accidentally
  })
})
```

Regulation: CCPA, HIPAA (minimum necessary), GLBA

---

## AP-02: Missing Ownership Check (IDOR)

What to grep:
```
req.params.id
req.params.userId
params[:id]
request.GET['id']
findById(req.params.id)
findOne({ id: req.params.id })
User.find(params[:id])
```

Flag when:
- Record fetched by ID from URL param without verifying requester owns it
- No check that `req.user.id === record.userId`
- Admin check missing — non-admins can access any record by guessing ID

Why it matters: IDOR (Insecure Direct Object Reference) lets any authenticated
user access any other user's PII by changing the ID in the URL.
`/api/users/123/profile` → change to `/api/users/124/profile` → other user's data.

Fix pattern:
```javascript
// Wrong
app.get('/api/users/:id', auth, async (req, res) => {
  const user = await User.findById(req.params.id)  // no ownership check
  res.json(user)
})

// Right
app.get('/api/users/:id', auth, async (req, res) => {
  // Verify ownership — requester can only access their own record
  if (req.params.id !== req.user.id && !req.user.isAdmin) {
    return res.status(403).json({ error: 'Forbidden' })
  }
  const user = await User.findById(req.params.id).select('id name email')
  res.json(user)
})
```

Regulation: CCPA, HIPAA, FTC Act

---

## AP-03: GraphQL Introspection Enabled in Production

What to grep:
```
introspection:
introspection: true
NODE_ENV !== 'production'   (check if introspection gated on this)
ApolloServer({
buildSchema(
makeExecutableSchema(
```

Flag when:
- `introspection: true` set unconditionally
- No environment check before enabling introspection
- No query depth limiting (allows deeply nested queries to extract data)

Why it matters: Introspection exposes your full data model — every type,
field name, and relationship — to anyone who can reach the endpoint.
This reveals your PII field names and data structure to attackers.

Fix pattern:
```javascript
// Wrong
const server = new ApolloServer({
  schema,
  introspection: true  // always on
})

// Right
const server = new ApolloServer({
  schema,
  introspection: process.env.NODE_ENV !== 'production',
  plugins: [
    ApolloServerPluginLandingPageDisabledPlugin()  // disable playground in prod
  ]
})

// Also add query depth limiting
import depthLimit from 'graphql-depth-limit'
const server = new ApolloServer({
  schema,
  validationRules: [depthLimit(5)]
})
```

Regulation: FTC Act, CCPA (data exposure risk)

---

## AP-04: Bulk Endpoint Returns All Records Without Scoping

What to grep:
```
User.findAll()
User.all
User.find({})
db.users.find({})
SELECT * FROM users
.findMany()           (without where clause)
Model.objects.all()
```

Flag when:
- Endpoint returns all users/records without auth scoping
- No `WHERE user_id = ?` limiting results to requester's own data
- Admin list endpoints accessible without admin role check
- No pagination (allows full data extraction in one call)

Fix pattern:
```javascript
// Wrong
app.get('/api/users', auth, async (req, res) => {
  const users = await User.findAll()  // returns everyone's data
  res.json(users)
})

// Right
app.get('/api/users', auth, requireAdmin, async (req, res) => {
  const users = await User.findAll({
    attributes: ['id', 'name', 'email', 'createdAt'],  // no sensitive fields
    limit: req.query.limit || 50,    // always paginate
    offset: req.query.offset || 0,
    order: [['createdAt', 'DESC']]
  })
  res.json({ users, total: await User.count() })
})

// For non-admin endpoints — scope to requester only
app.get('/api/my/data', auth, async (req, res) => {
  const records = await Record.findAll({
    where: { userId: req.user.id }  // always scope to current user
  })
  res.json(records)
})
```

Regulation: CCPA, HIPAA, FTC Act

---

## AP-05: PII Returned in Error Messages

What to grep:
```
`User ${email} not found`
`Email ${req.body.email} already exists`
`Invalid password for ${username}`
`Account ${ssn} not found`
res.json({ error: `${email}
res.status(404).json({ message: `User ${
```

Flag when:
- Email or username confirmed in error response (account enumeration)
- PII reflected back in error messages
- Database error messages forwarded to client (may contain field values)

Fix pattern:
```javascript
// Wrong
if (!user) {
  return res.status(404).json({ error: `User ${email} not found` })
}
if (existingUser) {
  return res.status(409).json({ error: `Email ${email} already registered` })
}

// Right — generic messages that don't confirm PII or account existence
if (!user || !validPassword) {
  return res.status(401).json({ error: 'Invalid credentials' })
  // Same message whether user doesn't exist or password is wrong
}
if (existingUser) {
  return res.status(409).json({ error: 'An account with this email already exists' })
  // OK to confirm email taken at registration — but not at login
}
```

Regulation: CCPA, FTC Act, HIPAA

---

## AP-06: Rate Limiting Missing on Auth / PII Endpoints

What to grep:
```
app.post('/login'
app.post('/forgot-password'
app.post('/reset-password'
app.get('/api/users/:id'
app.post('/api/verify'
```

Flag when:
- Login endpoint has no rate limiting (brute force risk)
- Password reset endpoint has no rate limiting (enumeration risk)
- PII lookup endpoints have no rate limiting (scraping risk)
- No `express-rate-limit`, `rack-attack`, `django-ratelimit`, or equivalent

Fix pattern:
```javascript
// Add to auth-sensitive routes
import rateLimit from 'express-rate-limit'

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,  // 15 minutes
  max: 10,                     // 10 attempts per window
  message: { error: 'Too many attempts, please try again later' },
  standardHeaders: true,
  legacyHeaders: false,
})

app.post('/login', authLimiter, loginHandler)
app.post('/forgot-password', authLimiter, forgotPasswordHandler)
app.post('/api/verify', authLimiter, verifyHandler)
```

Regulation: FTC Act, PCI-DSS, HIPAA

---

## AP-07: CORS Misconfiguration

What to grep:
```
origin: '*'
origin: true
cors({ origin: '*'
corsOptions = { origin: '*'
allow_all_origins = True      (Django)
CORS_ALLOW_ALL_ORIGINS = True (Django)
config.allow_origins = ["*"]  (FastAPI)
```

Flag when:
- `origin: '*'` on any API that handles authenticated requests
- `origin: true` (reflects any origin) on credentialed endpoints
- No `credentials: true` check alongside wildcard origin
- Different CORS policy for dev vs prod not enforced

Why it matters: A wildcard CORS origin on an authenticated API allows any
website to make credentialed requests on behalf of your users — reading
their data, performing actions. One of the most common misconfigurations
that leads to data exposure.

Fix pattern:
```javascript
// Wrong
app.use(cors({ origin: '*' }))  // allows any domain

// Wrong — reflects any origin
app.use(cors({ origin: true, credentials: true }))

// Right
const allowedOrigins = [
  'https://app.yourcompany.com',
  'https://www.yourcompany.com',
  ...(process.env.NODE_ENV === 'development' ? ['http://localhost:3000'] : [])
]

app.use(cors({
  origin: (origin, callback) => {
    if (!origin || allowedOrigins.includes(origin)) {
      callback(null, true)
    } else {
      callback(new Error(`CORS blocked: ${origin}`))
    }
  },
  credentials: true
}))
```

```python
# Wrong (FastAPI)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True)

# Right
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://app.yourcompany.com"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["*"],
)
```

Regulation: FTC Act, CCPA (data exposure via cross-origin request)