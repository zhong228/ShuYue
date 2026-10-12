# Handoff — MoYue Firebase Gateway integration

Session handoff for the next agent. This is a working note, not product
documentation. It captures current state, every bug found, exact commands,
and what is still unverified.

Language preference of the owner: reply in Traditional Chinese; code,
identifiers and commit messages in English.

---

## 1. Mission and current state

Goal: let users in mainland China (no VPN) sign in and use account features by
relaying Firebase through a self-hosted HTTPS Gateway, while keeping the
existing Firebase project, UIDs, providers, subscriptions and Console as the
source of truth.

State as of this handoff:

- Gateway is **deployed and healthy** at `https://gateway.yuedureader.com`.
- Real end-to-end account lifecycle through the Gateway **passes** (see §7).
- A Release build now carries the Gateway URL and uses the existing automatic
  routing; Release never forces the Gateway.
- Still **not** verified: mainland-China no-VPN network test, Apple/Google
  interactive Gateway exchange, real StoreKit purchase/restore, Firebase
  `disabled` user, App Check state, load test.

## 2. Deployment facts

| Item | Value |
| --- | --- |
| Gateway URL | `https://gateway.yuedureader.com` |
| VPS | Tencent Cloud Lighthouse, Hong Kong, IP `43.129.29.13` |
| SSH | user `ubuntu`, passwordless sudo. A session key was added to `~/.ssh/authorized_keys`; it can be removed when integration work ends. Private key used by this session: `/var/folders/cv/0p6b6fyx01bbk8yfty_z1gdc0000gn/T/opencode/yuedu_deploy` |
| Deployment dir | `/home/ubuntu/yuedu-gateway` |
| Topology | single `docker run` container `yuedu-gateway` on `127.0.0.1:8080`; **host** Caddy terminates TLS (`/etc/caddy/Caddyfile`). The compose file in the repo is **not** used on the host. |
| Service account | mounted from `/etc/yuedu-gateway/firebase-service-account.json` (contents never needed in chat) |
| Firebase project | `yuedu-readerr` |
| Functions region | `asia-east1` |

Important quirks:

- `sudo docker` fails with "command not found" because sudo's PATH lacks the
  docker location. Use `D=$(which docker); sudo "$D" ...` or `/usr/bin/docker`.
- The container was started with `docker run`, not compose. `docker restart`
  does **not** reload `--env-file`; recreate the container after env changes.
- Host Caddy now has an explicit block:
  `reverse_proxy 127.0.0.1:8080 { header_up X-Forwarded-For {remote_host} ... }`
  and the container runs with `TRUST_PROXY_HOPS=1` (verified).
- Old image kept for rollback as `yuedu-gateway:previous`.

## 3. Secrets / API key

- The Gateway's `FIREBASE_API_KEY` lives only in
  `/home/ubuntu/yuedu-gateway/.env` (server). It is **not** in the repo.
- Current key is the one the owner supplied in chat and asked to swap in; it
  was verified to work for **Identity Toolkit API and Token Service API** from
  both a local machine and the VPS, and the full live lifecycle passes with it.
- The key appeared in chat, so it is "known"; recommend either adding API +
  IP restrictions in Google Cloud Console or rotating it later. Rotation =
  edit `.env`, recreate the container.
- Do not paste the key into repo files, docs, or commits.

## 4. Repository changes made (for reference)

Gateway service (`gateway/`, standalone TypeScript, Express + firebase-admin):

- `src/` routes: auth (email/idp/refresh/logout/link/unlink/pending),
  account (`/me`, `/delete`, `/deletion-status`), profile, avatar,
  subscription (entitlement/account-token/bind/account-data/testflight),
  health, server, config, errors, identityToolkit, callableProxy, policy,
  rateLimit, auth middleware, deletion jobs, withTimeout.
- `Dockerfile`, `docker-compose.yml`, `Caddyfile`, `.env.example`,
  `.gitignore`, `scripts/smoke-local.sh`, `scripts/integration-auth.mjs`,
  `README.md`, `DEPLOYMENT_RUNBOOK.md`.
- Tests: `test/policy.test.ts`, `test/security.test.ts`, `test/health.test.ts`,
  `test/proxy.test.ts`, `test/gate.test.ts`.

iOS:

- New: `Modules/Services/Account/AccountUser.swift`, `AuthRoutePolicy.swift`,
  `AuthRouteOverride.swift`, `GatewayConfiguration.swift`, `GatewayAPIError.swift`,
  `GatewayAPIClient.swift`, `GatewayKeychain.swift`, `GatewaySessionStore.swift`,
  `GatewayAuthProvider.swift`, `AccountBackend.swift`,
  `FirebaseAccountBackend.swift`, `GatewayAccountBackend.swift`,
  `Modules/Features/Settings/AccountAvatarImage.swift`.
- Modified: `FirebaseAuthManager.swift` (route facade), `FirestoreSyncManager.swift`
  (profile/avatar via backend), `SubscriptionAccountService.swift`,
  `SubscriptionStore.swift`, `GlobalSettings.swift` (`authRouteMode`,
  `applyAccountUser`), `AuthErrorReporter.swift`, `TestFlightApplyView.swift`,
  `UserDetailView.swift`, `Info.plist`, three `Localizable.strings`.
- Tests: `Tests/iOS/yuedu appTests/GatewayAuthTests.swift`,
  `GatewayLiveIntegrationTests.swift`.
- `project.pbxproj`: `GATEWAY_BASE_URL = "https://gateway.yuedureader.com"`
  for **both Debug and Release** (Release previously empty).
- Docs: `Technotes/FirebaseGateway.md`, `Technotes/FirebaseGatewayHandoff.md`
  (this file).

There are many unrelated uncommitted changes in the working tree (Calibre,
RemoteLibrary, reader work). Never revert them. **Never run
`git checkout --`, `git restore`, or `git reset --hard`** (owner rule).

## 5. Routing policy (must not regress)

- There is no user-facing route switch any more (the Settings picker and
  `AuthRouteMode` were removed 2026-09-24); every build runs the automatic
  policy.
- `AuthRoutePolicy.decide`: no Gateway URL → direct; remembered `.gateway` →
  Gateway; no memory + mainland region hint → Gateway; otherwise a 3 s
  `DirectAuthReachability` probe of `identitytoolkit.googleapis.com` picks
  direct (reachable) or Gateway. A remembered `.direct` is probed too. Region is
  only a hint; storefront/language are not used.
- Why the probe: the Firebase Auth SDK sets no request timeout, so a direct
  attempt from a blocked network waited out URLSession's 60 s default before
  the Gateway retry started — the "first sign-in in China fails / second one is
  fast" report. Do not remove it while the Gateway exists.
- Release: **no forced Gateway** (`AuthRouteOverride` is `#if DEBUG`; verified
  the string is absent from the Release binary).
- `AuthRouteFallbackPolicy.isGatewayEligible`: `.signInWithEmail`,
  `.signUpWithEmail` and (since 2026-09-24) `.signInWithApple`. Apple's sheet
  only talks to Apple, which is reachable from the mainland; the Gateway then
  runs `signInWithIdp`. Google is **always direct**: accounts.google.com is
  blocked in the mainland, so there is never a token to relay.
- `allowsAutomaticRouteSwitch`: `.signInWithEmail` and `.signInWithApple`
  (both idempotent — same uid on repeat). Sign-up, link, unlink, delete,
  purchase binding, password reset never auto-retry.
- `AuthRouteErrorClassifier.isRouteFailure`: only Gateway transport /
  `upstream-unavailable`, Firebase `networkError` / `webNetworkRequestFailed`,
  or `NSURLErrorDomain`. Business errors (wrong password, disabled, conflict
  409) never switch routes.
- Gateway unreachable must **not** clear a stored session; only explicit
  `unauthenticated` / `user-disabled` / `user-not-found` does.
- Entitlement query failure must **not** become Pro=false; callers keep the
  cached value ("missing document ≠ not Pro").
- Do not touch local books / iCloud / WebDAV / OPDS in this work.

## 6. Bugs found and fixed during integration (history)

1. `FIREBASE_API_KEY` on the server was the `.env.example` placeholder
   (`AIzaSy...replace-me`, 19 chars) → `API_KEY_INVALID`. Fixed in `.env`.
2. Gateway `refreshSession` called `securetoken.googleapis.com` **without
   `?key=`** → 403 "Method doesn't allow unregistered callers" on every
   refresh. Fixed + `secureTokenURL()` unit test.
3. Gateway account payload returned `displayName: null` for new email users;
   Swift `AccountUser.displayName` is non-optional → `.invalidResponse`.
   Fixed both sides (gateway normalizes to `""`, Swift lenient decoder).
4. Error mapping masked upstream 403 / API-key failures as generic 400. Now maps
   key/provider problems to `permission-denied` and adds
   `details.upstream` (code) + server log `detail` (capped).
5. Deployed container predated hardening (no credential gate, no
   `TRUST_PROXY_HOPS`). Rebuilt/redeployed current revision.
6. A test bug: direct logout request omitted `authenticated: true` → 401. Fixed.
7. Failed test runs left 5 test accounts; deleted via Admin using the service
   account (scanned all users, deleted only test-pattern emails). Always verify
   leftover test accounts = 0 after integration runs.

## 7. Verification evidence

Gateway:

- `cd gateway && npm test` → **44 tests / 0 fail**.
- `npm run smoke` → **11/11 PASS** (compiled artifact, dummy config, no creds).
- `/healthz` 200, `/readyz` `{"status":"ready", credentials/firestore/storage ok}`.

iOS (Debug test host):

- `xcodebuild test ...` (the 14 suites listed in §8) → **68 tests / 0 fail**,
  including `GatewayLiveIntegrationTests` against the real Gateway.
- Live lifecycle route trail on the server (all through the Gateway):
  signup 201 → signin 200 → wrong 401 → duplicate 409 → refresh 200 →
  `/v1/account/me` 200 → profile PUT/GET 200 → avatar PUT/GET 200 →
  entitlement 200 → account-token 200 → bind 400 (invalid JWS rejected) →
  link/email 409 → unlink 409 → logout 200 (revoke) → refresh 401 → me 401 →
  signin 200 → account/delete 200 → signin 401 (account gone).

Release:

- `xcodebuild ... -configuration Release build` → SUCCEEDED; plist
  `GatewayBaseURL = https://gateway.yuedureader.com`.
- `xcodebuild archive -destination 'generic/platform=iOS'` → ARCHIVE SUCCEEDED;
  archived `YueduReader.app/Info.plist` has the URL; `strings` count of
  `gateway-route-forced` in the Release binary = 0.

## 8. Exact commands

iOS regression suites (run from repo root; `xcodebuild` may be busy with the
owner's own builds — if the build DB is locked, wait or use `-derivedDataPath`
only after confirming with the owner):

```bash
xcodebuild test -project "Yuedu-Reader.xcodeproj" -scheme "Yuedu-Reader" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:'yuedu appTests/AuthRoutePolicyTests' \
  -only-testing:'yuedu appTests/AuthRouteErrorClassifierTests' \
  -only-testing:'yuedu appTests/GatewayAPIErrorTests' \
  -only-testing:'yuedu appTests/GatewayProfilePayloadTests' \
  -only-testing:'yuedu appTests/GatewayAvatarURLResolverTests' \
  -only-testing:'yuedu appTests/GatewaySessionStoreTests' \
  -only-testing:'yuedu appTests/AccountUserDecodingTests' \
  -only-testing:'yuedu appTests/AuthRouteOverrideTests' \
  -only-testing:'yuedu appTests/GatewayLiveIntegrationTests' \
  -only-testing:'yuedu appTests/AuthAndICloudConfigurationTests' \
  -only-testing:'yuedu appTests/SubscriptionAccessPolicyTests' \
  -only-testing:'yuedu appTests/SubscriptionEntitlementFilterTests' \
  -only-testing:'yuedu appTests/PremiumFeatureTests' \
  -only-testing:'yuedu appTests/GlobalSettingsLocalizationTests'
```

`GatewayLiveIntegrationTests` creates a throwaway `gateway-it-<uuid>@example.com`
account through the Gateway and deletes it at the end (it exercises deletion,
revocation, profile, avatar, entitlement, account token, invalid bind, and the
link/unlink guards). It only runs when `GatewayConfiguration.isConfigured`.

Gateway local:

```bash
cd gateway
npm install
npm run typecheck
npm test
npm run smoke
npm run integration:auth   # exits 2 "NOT EXECUTED" unless env vars provided
```

Redeploy the gateway after a source change (from the workspace, using this
session's SSH key; note `/usr/bin/docker` for sudo):

```bash
rsync -az --exclude node_modules --exclude lib --exclude .env \
  --exclude gateway.env --exclude .git \
  -e "ssh -i /var/folders/cv/0p6b6fyx01bbk8yfty_z1gdc0000gn/T/opencode/yuedu_deploy -o IdentitiesOnly=yes" \
  <repo>/gateway/ \
  ubuntu@43.129.29.13:/home/ubuntu/yuedu-gateway/

ssh -i /var/folders/cv/0p6b6fyx01bbk8yfty_z1gdc0000gn/T/opencode/yuedu_deploy ubuntu@43.129.29.13 \
  'cd /home/ubuntu/yuedu-gateway && \
   sudo /usr/bin/docker build -q -t yuedu-gateway:local . && \
   sudo /usr/bin/docker rm -f yuedu-gateway && \
   sudo /usr/bin/docker run -d --name yuedu-gateway --restart unless-stopped \
     -p 127.0.0.1:8080:8080 --env-file .env -e TRUST_PROXY_HOPS=1 \
     -v /etc/yuedu-gateway/firebase-service-account.json:/run/secrets/firebase-service-account.json:ro \
     yuedu-gateway:local && sleep 6 && \
   sudo /usr/bin/docker ps --format "{{.Names}} {{.Status}}"'
```

Tail logs / inspect:

```bash
ssh <key> ubuntu@43.129.29.13 'sudo /usr/bin/docker logs yuedu-gateway --since 10m'
```

Delete orphan test accounts (Admin via the service account, deletes only
known test-pattern emails):

```bash
ssh <key> ubuntu@43.129.29.13 'sudo /usr/bin/docker run --rm --entrypoint node \
  -v /etc/yuedu-gateway/firebase-service-account.json:/sa.json:ro \
  -e GOOGLE_APPLICATION_CREDENTIALS=/sa.json yuedu-gateway:local -e "
const {initializeApp, applicationDefault} = require(\"firebase-admin/app\");
const {getAuth} = require(\"firebase-admin/auth\");
initializeApp({credential: applicationDefault()});
(async () => { const auth=getAuth(); let p; const f=[];
  do { const page=await auth.listUsers(1000,p);
    for (const u of page.users){const e=u.email||\"\";
      if (/^(probe-|gateway-it-|diag-|gwtest-|restest-|vpsprobe-|seqprobe-)/.test(e)) f.push(e);}
    p=page.pageToken; } while(p);
  console.log(\"leftover:\", f.length, f.join(\",\")); })();
"'
```

## 9. Rollback

- Server: `docker image tag yuedu-gateway:previous yuedu-gateway:local` then
  recreate the container (or pin the tag). Gateway owns no durable state beyond
  `accountDeletionJobs/{uid}` bookkeeping docs.
- App: set `GATEWAY_BASE_URL` back to `""` in `project.pbxproj` (both configs)
  and rebuild; no code change needed.

## 10. Open items (unverified)

- Mainland-China no-VPN real-device test (record city/carrier/time/latency).
- Apple interactive sign-in through the Gateway on a real device (endpoint
  verified with an invalid token → `INVALID_IDP_RESPONSE` from Firebase).
  Google through the Gateway is intentionally not used.
- Real StoreKit purchase binding and restore purchase (sandbox account).
- Firebase `disabled` user (Console disable); revocation path is verified.
- App Check enforcement state in the Console (status unknown from repo).
- Dedicated server API key (both APIs + IP restriction) instead of the shared
  public client key.
- Load test; sizing/traffic in `gateway/README.md` are assumptions, not measured.
- Privacy disclosure / host-location for App Store review.

## 11. Owner constraints to respect

- Do not modify EPUB layout, CoreText, BrowserLayout, iCloud book sync, WebDAV,
  OPDS, or unrelated UI.
- Do not add a GatewayTest configuration, do not change the bundle id, no
  unrelated refactors.
- Do not touch real user data; integration tests must create/delete only
  throwaway test accounts.
- Do not make Release force the Gateway; automatic routing only.
- Never revert the owner's uncommitted changes (see §4).
