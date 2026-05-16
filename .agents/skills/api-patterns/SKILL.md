---
name: api-patterns
description: >-
  Use when making Safeguard API calls, working with
  invoke-safeguard-method.sh, using SCIM filters or query parameters,
  creating users/assets/accounts, or understanding Safeguard API
  conventions and gotchas.
---

# Safeguard API Patterns

## API Services

Safeguard hosts multiple services, each at a different base URL:

| Service | Description | Example |
|---------|-------------|---------|
| `core` | Main application API (users, assets, policies) | `-s core` |
| `appliance` | Appliance operations (status, clustering) | `-s appliance` |
| `notification` | SignalR event connections | `-s notification` |
| `a2a` | Application-to-application credential retrieval | `-s a2a` |

Swagger UI is available at: `https://<appliance>/service/<service>/swagger`

## API Versioning

The default API version is **v4** (since safeguard-bash 7.0). Pass `-v 3` to
use the v3 API. Both v3 and v4 are hosted simultaneously on Safeguard 7.x
appliances.

---

## Authentication Methods

### 1. Password (Resource Owner Grant)

Username + password to a local or directory identity provider. Requires the
Resource Owner grant type to be enabled on the appliance.

```bash
echo "MyPassword" | connect-safeguard.sh -a <appliance> -i local -u Admin -p
```

### 2. Certificate

Client certificate + private key, provider set to `certificate`.

```bash
connect-safeguard.sh -a <appliance> -i certificate -c cert.pem -k key.pem
```

### 3. PKCE (Proof Key for Code Exchange)

Non-interactive OAuth2 flow that programmatically simulates the browser-based
login without launching a browser. Does **not** require the Resource Owner
grant type to be enabled, making it the most reliable connection method.

```bash
echo "MyPassword" | connect-safeguard.sh -a <appliance> -i local -u Admin -P -p
```

**Recommendation:** For scripting and testing, use PKCE (`-P`) with a local
admin account. It works regardless of appliance grant-type configuration.

### Resource Owner Grant Type

The Resource Owner password grant may be disabled by default. To
check/modify programmatically:

```bash
# Read current grant types (requires an active session)
invoke-safeguard-method.sh -s core -m GET -U "Settings" \
    | jq '.[] | select(.Name=="Allowed OAuth2 Grant Types") | .Value'

# Enable Resource Owner grant (URL-encode the setting name)
invoke-safeguard-method.sh -s core -m PUT \
    -U "Settings/Allowed%20OAuth2%20Grant%20Types" \
    -b '{"Value":"ResourceOwner"}'
```

**Important:** The setting name contains spaces and must be URL-encoded
(`%20`) in the URL path.

### SSL/TLS

By default, safeguard-bash disables SSL verification (`-k` flag to curl).
To validate SSL, pass `-B /path/to/ca-bundle.pem` to scripts.

---

## Common API Endpoints

```bash
# Get current user info
invoke-safeguard-method.sh -s core -m GET -U "Me"

# Get appliance status (anonymous — no login required)
get-appliance-status.sh -a <appliance>

# List assets
invoke-safeguard-method.sh -s core -m GET -U "Assets"

# Create a user
invoke-safeguard-method.sh -s core -m POST -U "Users" \
    -b '{"Name":"TestUser","PrimaryAuthenticationProvider":{"Id":-1}}'

# Delete a user
invoke-safeguard-method.sh -s core -m DELETE -U "Users/<id>"
```

---

## Identity Provider IDs

These magic IDs are used across the API:

| ID   | Meaning                                |
|------|----------------------------------------|
| `-1` | Local identity provider                |
| `-2` | Certificate authentication provider    |

When creating a **local user**, set
`PrimaryAuthenticationProvider.Id` to `-1`:

```json
{"Name": "MyUser", "PrimaryAuthenticationProvider": {"Id": -1}}
```

When creating a **certificate user**, set it to `-2` with the SHA-1
thumbprint as the `Identity`:

```json
{"Name": "MyCertUser",
 "IdentityProvider": {"Id": -1},
 "PrimaryAuthenticationProvider": {"Id": -2, "Identity": "<SHA1-THUMBPRINT>"}}
```

---

## Setting Passwords

Set passwords on users or accounts via PUT with a bare JSON string:

```bash
# Set user password
invoke-safeguard-method.sh -s core -m PUT -U "Users/<id>/Password" \
    -b '"MyNewPassword1!"'

# Set account password
invoke-safeguard-method.sh -s core -m PUT -U "AssetAccounts/<id>/Password" \
    -b '"AccountPass1!"'
```

**Note the double quoting:** the outer quotes are for bash, the inner quotes
make it a valid JSON string value.

---

## Permission Requirements

| Operation                           | Required Permission(s) |
|-------------------------------------|------------------------|
| Create/edit/delete Users            | UserAdmin              |
| Create/edit/delete Assets           | AssetAdmin             |
| Create/edit/delete Asset Accounts   | AssetAdmin             |
| Create/edit/delete A2A Registrations| PolicyAdmin            |
| Configure A2A Access Request Broker | PolicyAdmin            |
| Install Trusted Certificates        | ApplianceAdmin         |
| Create Certificate Users            | UserAdmin              |
| Manage A2A Service (enable/disable) | ApplianceAdmin         |
| Manage Event Subscriptions          | (any authenticated user) |

### Built-in Admin Account

The built-in `Admin` account (Id `-2`, the "Bootstrap Administrator") has:
**GlobalAdmin**, **ApplianceAdmin**, **UserAdmin**, **HelpdeskAdmin**,
**OperationsAdmin**, **SystemAuditor**.

It does **not** have **AssetAdmin** or **PolicyAdmin**, and these permissions
**cannot be added** (Safeguard returns error 50100).

For operations requiring AssetAdmin or PolicyAdmin, create a temporary user
with the needed permissions.

### User Permissions (AdminRoles field)

Valid values: `GlobalAdmin`, `Auditor`, `AssetAdmin`, `ApplianceAdmin`,
`PolicyAdmin`, `UserAdmin`, `HelpdeskAdmin`, `OperationsAdmin`,
`ApplicationAuditor`, `SystemAuditor`.

**Note:** `Authorizer` is NOT a permission — it is a request workflow
concept. `GlobalAdmin` automatically implies `HelpdeskAdmin`,
`ApplicationAuditor`, and `SystemAuditor`.

Permissions ARE accepted during POST (no PUT needed). However, `Description`
is NOT accepted during POST — requires POST-then-PUT.

---

## User Object Field Names

The v4 API uses `Name` (not `UserName`) for the user's login name. Other key
fields: `DisplayName`, `Id`, `PrimaryAuthenticationProvider`. Always inspect
the actual API response with `jq keys` if unsure about field names.

### Local Provider Username Case

Local provider usernames are **case-insensitive**. The API may return a
different casing than what was provided at login (e.g. you pass `admin` but
`GET Me` returns `Admin`). Always normalize case before comparing usernames.

---

## POST-then-PUT Pattern

Some Safeguard API endpoints do not accept all properties during POST (create).
You must create first, then PUT (update) additional properties:

```bash
# Create with minimal properties
Result=$(invoke-safeguard-method.sh -s core -m POST -U "Endpoint" -b "$CreateBody")
Id=$(echo $Result | jq -r '.Id')

# Update with full properties
invoke-safeguard-method.sh -s core -m PUT -U "Endpoint/$Id" -b "$FullBody"
```

---

## SCIM-style Filtering

Many GET endpoints support server-side filtering via query parameters:

```bash
# Filter platforms by family
invoke-safeguard-method.sh -s core -m GET \
    -U "Platforms?filter=PlatformFamily%20eq%20'Custom'"

# Filter users by name
invoke-safeguard-method.sh -s core -m GET \
    -U "Users?filter=Name%20eq%20'Admin'"
```

### URL Encoding Convention

Use `sed 's/ /%20/g'` for spaces in filter strings. Leave single quotes raw.
Do **NOT** use `jq @uri` which over-encodes quotes to `%27` and causes API
errors.

```bash
# Correct
Filter="Name eq 'MyUser'"
EncodedFilter=$(echo "$Filter" | sed 's/ /%20/g')

# Wrong — jq @uri over-encodes quotes
EncodedFilter=$(echo "$Filter" | jq -Rr @uri)
```

---

## Asset Creation

Assets require `AssetPartitionId` (use `-1` for Default Partition) or creation
fails with a validation error. The `new-asset.sh` script defaults to `-1`.

```bash
new-asset.sh -n "MyAsset" -N "10.0.0.1" -P 521   # Linux (platform ID 521)
new-asset.sh -n "MyWin"   -N "10.0.0.2" -P 547   # Windows Server (ID 547)
```

### Asset Account Creation

The AssetAccount API requires a nested `Asset` object, not a flat `AssetId`:

```bash
# Correct: nested Asset.Id
{"Name": "root", "Asset": {"Id": 123}}

# Wrong: flat AssetId (will fail)
{"Name": "root", "AssetId": 123}
```

---

## Well-Known Platform IDs

These built-in platform IDs are stable across Safeguard installations:

| ID  | Platform         |
|-----|------------------|
| 521 | Linux            |
| 547 | Windows Server   |
| 548 | Windows Desktop  |

---

## Common Error Codes

| Code  | Meaning |
|-------|---------|
| 50100 | Cannot modify the built-in Admin account permissions |
| 60657 | Duplicate object (e.g. user or asset name already exists) |
| 70003 | Invalid filter syntax (e.g. using long-form operators) |
| 90001 | Access request overlap (another request already active) |

---

## Script Reference

safeguard-bash includes 77 scripts in `src/`. These are organized by category
below. Use `ls src/` to see all scripts, and `<script> -h` for usage help.

### Connection & Core

| Script | Description |
|--------|-------------|
| `connect-safeguard.sh` | Authenticate and create login file |
| `disconnect-safeguard.sh` | Invalidate token and remove login file |
| `invoke-safeguard-method.sh` | Generic Safeguard API call |
| `show-safeguard-method.sh` | List available API methods |
| `get-logged-in-user.sh` | Get info about the current user |
| `get-appliance-status.sh` | Get appliance status (anonymous) |
| `get-appliance-verification.sh` | Get appliance verification status |

### Users & Assets

| Script | Description |
|--------|-------------|
| `new-user.sh` | Create local user with roles |
| `remove-user.sh` | Delete user by ID |
| `new-certificate-user.sh` | Create certificate auth user |
| `new-asset.sh` | Create asset with platform/address |
| `remove-asset.sh` | Delete asset by ID |
| `new-asset-account.sh` | Create account on an asset |
| `remove-asset-account.sh` | Delete account by ID |
| `set-account-password.sh` | Set password on an asset account |
| `set-account-privatekey.sh` | Set SSH key on an asset account |
| `get-platform.sh` | List/get platforms |

### Access Requests

| Script | Description |
|--------|-------------|
| `new-access-request.sh` | Create an access request |
| `get-access-request.sh` | List/get access requests |
| `edit-access-request.sh` | Edit an access request |
| `close-access-request.sh` | Close an access request |
| `get-actionable-request.sh` | Get requests awaiting action |
| `get-requestable-account.sh` | Get accounts available for request |
| `get-access-request-password.sh` | Get checked-out password |
| `get-access-request-privatekey.sh` | Get checked-out SSH key |
| `get-access-request-favorite.sh` | Get favorite access requests |
| `get-linked-account.sh` | Get linked accounts |
| `start-access-request-ssh-session.sh` | Start an SSH session via access request |

### A2A Registration Management

| Script | Description |
|--------|-------------|
| `new-a2a-registration.sh` | Create A2A registration |
| `remove-a2a-registration.sh` | Delete A2A registration |
| `get-a2a-registration.sh` | List/get A2A registrations |
| `edit-a2a-registration.sh` | Edit A2A registration properties |

### A2A Credential Retrieval (Token Auth — Admin Setup)

| Script | Description |
|--------|-------------|
| `add-a2a-credential-retrieval.sh` | Add account to A2A retrieval |
| `remove-a2a-credential-retrieval.sh` | Remove account from A2A retrieval |
| `get-a2a-credential-retrieval.sh` | List credential retrievals for a registration |
| `get-a2a-credential-retrieval-info.sh` | Summary info across all registrations |
| `get-a2a-retrievable-account.sh` | List accounts retrievable by cert user |
| `get-a2a-apikey.sh` | Get API key for a credential retrieval |
| `reset-a2a-apikey.sh` | Regenerate API key for a credential retrieval |
| `get-a2a-ip-restriction.sh` | Get IP restrictions on credential retrieval |
| `set-a2a-ip-restriction.sh` | Set IP restrictions |
| `clear-a2a-ip-restriction.sh` | Clear all IP restrictions |

### A2A Credential Operations (Cert Auth — Application Use)

| Script | Description |
|--------|-------------|
| `get-a2a-password.sh` | Retrieve password via A2A cert auth |
| `get-a2a-privatekey.sh` | Retrieve SSH key via A2A cert auth |
| `get-a2a-apikeysecret.sh` | Retrieve API key secret via A2A cert auth |
| `set-a2a-password.sh` | Set account password via A2A cert auth |
| `set-a2a-privatekey.sh` | Set account SSH key via A2A cert auth |

### A2A Access Request Brokering

| Script | Description |
|--------|-------------|
| `get-a2a-access-request-broker.sh` | Get access request broker config |
| `set-a2a-access-request-broker.sh` | Configure access request broker |
| `clear-a2a-access-request-broker.sh` | Remove access request broker config |
| `new-a2a-access-request.sh` | Broker an access request via A2A cert auth |

### A2A Service Management

| Script | Description |
|--------|-------------|
| `get-a2a-service-status.sh` | Get A2A service status (enabled/disabled) |
| `enable-a2a-service.sh` | Enable the A2A service |
| `disable-a2a-service.sh` | Disable the A2A service |

### Certificate Management

| Script | Description |
|--------|-------------|
| `install-trusted-certificate.sh` | Install a trusted certificate |
| `uninstall-trusted-certificate.sh` | Remove a trusted certificate |
| `get-trusted-certificate.sh` | List/get trusted certificates |
| `get-trusted-ca-bundle.sh` | Get trusted CA bundle |
| `install-ssl-certificate.sh` | Install SSL certificate on appliance |

### Event Subscriptions

| Script | Description |
|--------|-------------|
| `new-event-subscription.sh` | Create event subscription (SignalR/email) |
| `remove-event-subscription.sh` | Delete event subscription |
| `get-event-subscription.sh` | List/get event subscriptions |
| `edit-event-subscription.sh` | Edit event subscription properties |
| `find-event-subscription.sh` | Search event subscriptions |

### Event Discovery

| Script | Description |
|--------|-------------|
| `get-event.sh` | List all events (legacy) |
| `get-event-name.sh` | List subscribable event names |
| `get-event-category.sh` | List event categories |
| `get-event-property.sh` | Get notification properties for an event |
| `find-event.sh` | Search events by text or SCIM filter |

### Event Listeners & Handlers

| Script | Description |
|--------|-------------|
| `listen-for-event.sh` | Connect to SignalR and dump events |
| `handle-event.sh` | Resilient event listener with handler script |
| `listen-for-a2a-event.sh` | Connect to A2A SignalR events |
| `handle-a2a-password-event.sh` | Handle A2A password change events |
| `handle-a2a-privatekey-event.sh` | Handle A2A SSH key change events |
| `handle-a2a-apikeysecret-event.sh` | Handle A2A API key secret change events |

### Appliance Administration

| Script | Description |
|--------|-------------|
| `install-license.sh` | Install a license on the appliance |
| `get-support-bundle.sh` | Download a support bundle |
