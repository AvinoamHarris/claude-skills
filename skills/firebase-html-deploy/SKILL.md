---
name: firebase-html-deploy
description: |
  Deploy a self-contained HTML file to Firebase Hosting with HMAC token-gated access.
  Pages are stored in Firebase Storage (GCS) and served by a Cloud Function.
  Access URLs include a derived token so pages aren't publicly indexable.
  Use this skill when asked to: deploy HTML to Firebase, share a page as a live link,
  host an interactive dashboard/page, or set up Firebase HTML hosting.
  Two phases: SETUP (one-time per project) and DEPLOY (per page).
---

# Firebase HTML Deploy Skill

## What this builds

- HTML files deployed to Firebase Storage (GCS)
- Served by a Cloud Function at `/pages/<namespaceToken>/<deployId>/`
- Each URL includes a short HMAC token (`?t=...`) — not secret, just obscures guessability
- Open CSP so pages can call external APIs (Gemini, etc.)
- **Requires the Blaze (pay-as-you-go) plan.** Cloud Functions v2 — what this skill uses — does not deploy on the Spark free tier. Free quotas on Blaze are very generous (2M function invocations/month, 5 GB storage, 1 GB/day egress), so realistic per-project cost is **$0/month** for typical use. Set a $1 budget alert (`Console → Billing → Budgets & alerts`) as a safety net since Blaze has no automatic spending cap.

## Phases

- **SETUP** — Run once per Firebase project. Creates the Cloud Function, Storage rules, Hosting config.
- **DEPLOY** — Run per page. Uploads HTML and returns two URLs (unique + latest).

---

## PHASE 1: SETUP (one-time)

### Prerequisites

```bash
# Check you have these installed:
node --version      # need 20+
firebase --version  # need 13+; install: npm install -g firebase-tools
python --version    # need 3.10+
pip install -r ~/.claude/skills/firebase-html-deploy/files/requirements.txt
# or: uv pip install -r ~/.claude/skills/firebase-html-deploy/files/requirements.txt
```

### Step 1.1 — Create Firebase project

Either via console (https://console.firebase.google.com → "Add project") or CLI:

```bash
firebase login   # one-time, opens browser
firebase projects:create my-html-pages --display-name "My HTML Pages"
```

Project IDs must be globally unique, lowercase, 6–30 chars. Add a random suffix (e.g. `my-html-pages-a1b2`) if the name is taken.

### Step 1.2 — Link Blaze billing

Cloud Functions v2 requires Blaze. List your billing accounts and link one:

```bash
gcloud billing accounts list
gcloud billing projects link <project-id> --billing-account=<ACCOUNT_ID>
```

> **Quota gotcha**: Each Google billing account is limited to 5 projects by default. If `gcloud billing projects link` fails with `Cloud billing quota exceeded`, either: (a) request an increase at https://support.google.com/code/contact/billing_quota_increase (typically approved within hours), (b) unlink an unused project with `gcloud billing projects unlink <other-project>`, or (c) reuse one of your existing billed projects.

### Step 1.3 — Enable required GCP APIs

```bash
gcloud services enable storage.googleapis.com cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com run.googleapis.com eventarc.googleapis.com \
  artifactregistry.googleapis.com firebasestorage.googleapis.com pubsub.googleapis.com \
  --project=<project-id>
```

Takes ~30 seconds. Skipping any of these causes confusing errors during `firebase deploy`.

### Step 1.4 — Create service account + key

```bash
gcloud iam service-accounts create firebase-deploy-sa \
  --display-name="Firebase HTML Deploy SA" --project=<project-id>

gcloud projects add-iam-policy-binding <project-id> \
  --member="serviceAccount:firebase-deploy-sa@<project-id>.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin" --condition=None

gcloud iam service-accounts keys create sa-key.json \
  --iam-account="firebase-deploy-sa@<project-id>.iam.gserviceaccount.com"
```

`Storage Object Admin` is the only role `deploy.py` needs. The Firebase CLI deploy (Step 1.9) uses your own logged-in credentials, not this SA.

Keep `sa-key.json` secret. Never commit it to git.

### Step 1.5 — Create the Storage bucket

Cloud Functions reads HTML from a GCS bucket. The Firebase default bucket name `<project-id>.firebasestorage.app` is owned by Firebase's domain — `gcloud storage buckets create gs://<project-id>.firebasestorage.app` fails with a domain-ownership error. Two options:

**Option A (recommended, fully scriptable):** Use any plain GCS bucket name:

```bash
gcloud storage buckets create gs://<project-id>-html \
  --project=<project-id> --location=us-central1 \
  --uniform-bucket-level-access
```

Use this name (`<project-id>-html`) everywhere `GCS_BUCKET` is referenced below.

**Option B:** Initialize Firebase Storage's default bucket via Firebase Console → Storage → "Get started". This unlocks the `<project-id>.firebasestorage.app` bucket, but requires a browser click.

### Step 1.6 — Generate TOKEN_SALT

```bash
openssl rand -hex 32
# Example output: a3f8c2d9e1b74056f2a8c3e7d9b1f4a80c2e7d3b9a5f8c1e4d7b2a6f9c3e8d1
```

Save this value. It's the master secret — tokens are derived from it. If you change it, all existing URLs break.

### Step 1.7 — Create project directory

```bash
mkdir my-firebase-pages && cd my-firebase-pages
```

Skip `firebase init` — the wizard is interactive and we'll write the files directly in the next steps. Create `.firebaserc` to pin the project:

```json
{ "projects": { "default": "<project-id>" } }
```

### Step 1.8 — Write the project files

Replace `functions/index.js` with:

```javascript
const { onRequest } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const crypto = require("crypto");

admin.initializeApp();
setGlobalOptions({ region: "us-central1" });

const ACCESS_DENIED_HTML = `<!DOCTYPE html>
<html><head><title>Access Denied</title>
<style>body{font-family:sans-serif;display:flex;align-items:center;justify-content:center;
height:100vh;margin:0;background:#f8f8f8}
.box{text-align:center;padding:2rem;background:#fff;border-radius:8px;box-shadow:0 2px 8px rgba(0,0,0,.1)}
h1{color:#d32f2f;margin:0 0 .5rem}p{color:#666}</style></head>
<body><div class="box"><h1>Access Denied</h1><p>Invalid or missing access token.</p></div></body></html>`;

const PATH_RE = /^\/pages\/([a-f0-9]{12})\/([\w-]+)\/?(?:index\.html)?$/;

function validateToken(namespaceToken, accessToken, salt) {
  const expected = crypto
    .createHmac("sha256", salt)
    .update(namespaceToken)
    .digest("hex")
    .slice(0, 16);
  if (expected.length !== accessToken.length) return false;
  return crypto.timingSafeEqual(
    Buffer.from(expected, "utf8"),
    Buffer.from(accessToken, "utf8")
  );
}
module.exports.validateToken = validateToken;

exports.servePage = onRequest(
  { timeoutSeconds: 10, memory: "128MiB" },
  async (req, res) => {
    const match = req.path.match(PATH_RE);
    if (!match) { res.status(404).send("Not found"); return; }

    const [, namespaceToken, deployId] = match;
    const token = req.query.t || "";
    const salt = process.env.TOKEN_SALT;
    if (!salt) { res.status(500).send("Server configuration error"); return; }

    if (!validateToken(namespaceToken, token, salt)) {
      res.status(403).send(ACCESS_DENIED_HTML);
      return;
    }

    const bucketName = process.env.GCS_BUCKET;
    if (!bucketName) { res.status(500).send("Server configuration error"); return; }

    const filePath = `pages/${namespaceToken}/${deployId}/index.html`;
    try {
      const [content] = await admin.storage().bucket(bucketName).file(filePath).download();
      res.set("Content-Type", "text/html; charset=utf-8");
      res.set("X-Robots-Tag", "noindex, nofollow");
      res.set("Cache-Control", "private, no-cache");
      res.set("Referrer-Policy", "no-referrer");
      res.send(content);
    } catch (err) {
      res.status(err.code === 404 ? 404 : 500).send(err.code === 404 ? "Page not found" : "Failed to load page");
    }
  }
);
```

Replace `functions/package.json` with:

```json
{
  "name": "firebase-html-deploy-functions",
  "engines": { "node": "20" },
  "main": "index.js",
  "scripts": { "test": "jest" },
  "dependencies": {
    "firebase-admin": "^12.0.0",
    "firebase-functions": "^6.0.0"
  },
  "devDependencies": { "jest": "^29.0.0" },
  "private": true
}
```

Replace `firebase.json` with:

```json
{
  "hosting": {
    "public": "public",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "headers": [
      {
        "source": "/pages/**",
        "headers": [
          {
            "key": "Content-Security-Policy",
            "value": "default-src * 'unsafe-inline' 'unsafe-eval' data: blob:; connect-src *; img-src * data: blob:; style-src * 'unsafe-inline'; font-src * data:; script-src * 'unsafe-inline' 'unsafe-eval'; frame-src *;"
          }
        ]
      }
    ],
    "rewrites": [
      {
        "source": "/pages/**",
        "function": "servePage",
        "region": "us-central1"
      }
    ]
  },
  "storage": { "rules": "storage.rules" },
  "functions": { "source": "functions" }
}
```

Replace `storage.rules` with:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read, write: if false;
    }
  }
}
```

### Step 1.9 — Create `functions/.env`

Create `functions/.env` (gitignore this file):

```
TOKEN_SALT=<your 64-char hex from Step 1.6>
GCS_BUCKET=<bucket name from Step 1.5, e.g. my-project-html>
```

### Step 1.10 — Install Cloud Function deps and deploy

```bash
cd functions && npm install && cd ..
firebase deploy --only hosting,functions --project=<project-id>
```

`--only hosting,functions` skips deploying `storage.rules`, which fails on a fresh project unless Firebase Storage's default bucket has been initialized via the Console (Option B in Step 1.5). Since we're using a custom bucket gated by the SA's IAM permissions instead of Firebase Storage rules, the storage.rules deploy isn't needed.

First deploy takes ~5 minutes (uploads function source, builds container image, provisions Cloud Run revision).

> **Important:** `functions/.env` must be present in your project directory at deploy time — Firebase bundles it into the function. Do **not** deploy from a fresh clone without restoring this file first, or the function will return 500 ("Server configuration error") because `TOKEN_SALT` will be missing.

After the deploy succeeds, set the Artifact Registry cleanup policy to avoid storage cost creep:

```bash
firebase functions:artifacts:setpolicy --project=<project-id> --force
```

Verify in Firebase Console → Functions: `servePage` should appear with status "Healthy".

### Step 1.11 — Create `config.json` in the skill directory

Create `~/.claude/skills/firebase-html-deploy/config.json` (it's gitignored there):

```json
{
  "project_id": "<your-firebase-project-id>",
  "storage_bucket": "<bucket name from Step 1.5>",
  "token_salt": "<your 64-char hex from Step 1.6>",
  "service_account_json": <paste the full contents of sa-key.json here as an object>
}
```

Add `functions/.env` and `secrets/` to your Firebase project's `.gitignore`:

```
functions/.env
functions/node_modules/
secrets/
.firebase/
```

**SETUP is complete.** From now on, deploying a page is a single command from any project.

---

## PHASE 2: DEPLOY (per page)

### Requirements for the HTML file

- Must be **self-contained**: all CSS and JS inline, no external file references that won't work without the original server
- Data embedded as JS constants: `<script>const DATA = {...}</script>`
- External API calls (OpenWeatherMap, any REST API, etc.) are fine — CSP allows `connect-src *`
- Google Fonts are fine — `font-src *`
- No size limit enforced by the script, but keep under 5MB for reasonable load times

### Deploy command

```bash
python ~/.claude/skills/firebase-html-deploy/files/deploy.py \
  --config ~/.claude/skills/firebase-html-deploy/config.json \
  --namespace myproject \
  --html page.html \
  --title "My Dashboard"
```

Output:
```json
{
  "unique_url": "https://my-project.web.app/pages/a1b2c3d4e5f6/20260428-143022-ff1a2b/?t=6df482d39a6ff92e",
  "latest_url": "https://my-project.web.app/pages/a1b2c3d4e5f6/latest/?t=6df482d39a6ff92e"
}
```

- **`unique_url`** — permanent link to this exact version. Share this if you want a stable snapshot.
- **`latest_url`** — always points to the most recent deploy for this namespace. Share this for "live" updates.

### Namespace

`--namespace` is any string you choose (e.g. `john`, `myproject`, `dashboards`). It determines the URL path component and access token. Everyone using the same namespace + config gets the same token — so it's a lightweight "channel", not per-user auth.

### When to use unique vs latest URL

| Scenario | URL to share |
|----------|-------------|
| Iterating on a page, want recipients to always see newest | `latest_url` |
| Archiving a specific version (weekly report, snapshot) | `unique_url` |
| Both | Share both |

### Troubleshooting

**"Access Denied" page shows:**
- The `?t=` token in the URL was stripped or modified
- Wrong `TOKEN_SALT` in `config.json` vs `functions/.env`
- Verify: `python -c "import sys; sys.path.insert(0,'~/.claude/skills/firebase-html-deploy/files'); import deploy, json; cfg=json.load(open('~/.claude/skills/firebase-html-deploy/config.json',encoding='utf-8')); ns=deploy._namespace_token('myproject', cfg['token_salt']); print(deploy._access_token(ns, cfg['token_salt']))"`

**"Page not found" (404):**
- File wasn't uploaded to GCS. Check `config.json` bucket name matches `functions/.env` `GCS_BUCKET`.
- Check Firebase Console → Storage: the file should be at `pages/<namespaceToken>/<deployId>/index.html`

**Upload fails with auth error:**
- Service account JSON in `config.json` may be expired or missing the Storage Admin role
- Re-download the key from Google Cloud Console → IAM → Service Accounts

**Cloud Function cold start (slow first load):**
- Normal. Firebase Functions v2 cold-starts in ~2-3 seconds. Subsequent requests are fast.

**`<project-id>.web.app` returns "Site Not Found" (404) right after first deploy:**
- Firebase Hosting CDN propagation. New sites take 5–30 minutes to serve, sometimes up to an hour.
- The Cloud Function works immediately at `https://us-central1-<project-id>.cloudfunctions.net/servePage/pages/<ns>/<deploy>/?t=<token>` — useful for smoke testing during the wait.
- If it persists past an hour, check `firebase hosting:sites:list` and `firebase hosting:channel:list` to confirm the live release exists.

---

## Token security model

| Token | How derived | Purpose |
|-------|-------------|---------|
| `namespaceToken` | `sha256(namespace + TOKEN_SALT)[:12]` | Stable, hard-to-guess path component. 12 hex chars = 48 bits of obscurity. |
| `accessToken` | `HMAC-SHA256(TOKEN_SALT, namespaceToken)[:16]` | Required query param. Cloud Function validates with timing-safe compare. |

**This is obscurity, not strong auth.** The URL contains the token, so anyone with the URL can view the page. Don't use this for truly sensitive data. Use it for: educational pages, team dashboards, generated reports shared within a trusted group.

The Cloud Function sets `Referrer-Policy: no-referrer` on every response so browsers won't include the tokenized URL in `Referer` headers when the page loads external resources (images, fonts, APIs). Without this header, the token would leak to third-party servers via the `Referer` header.
