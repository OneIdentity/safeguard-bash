# AGENTS.md — AI Agent Instructions for safeguard-bash

This document provides instructions for AI coding agents working in the
safeguard-bash repository. It covers project structure, conventions, testing
against a live Safeguard appliance, and Safeguard domain knowledge needed to
write correct scripts.

---

## Project Overview

safeguard-bash is a Bash + cURL scripting SDK for the **One Identity Safeguard
for Privileged Passwords (SPP)** REST API. Each script in `src/` is a
self-contained CLI command that wraps one or more Safeguard API operations.

The scripts are designed to run standalone on any system with bash, curl, and
jq, or inside an Alpine-based Docker container.

### Reference: safeguard-ps (PowerShell SDK)

The **[OneIdentity/safeguard-ps](https://github.com/OneIdentity/safeguard-ps)**
repository is the PowerShell equivalent of safeguard-bash. It covers the same
Safeguard API but is significantly more mature and feature-rich.

When working on safeguard-bash, consult safeguard-ps to:

- **Find missing functionality** — safeguard-ps implements many commands that
  safeguard-bash does not yet have. Look for PowerShell cmdlets that have no
  corresponding bash script and consider adding them.
- **Compare implementation techniques** — see how safeguard-ps handles error
  checking, parameter validation, pagination, filtering, and edge cases.
- **Validate API usage patterns** — safeguard-ps is a good reference for
  correct API endpoint usage, required fields, and expected response formats.
- **Adopt testing patterns** — safeguard-ps has a comprehensive test suite
  (in its `test/` directory) that demonstrates thorough assertion strategies
  and cleanup practices. The "Writing Strong Assertions" section below was
  adapted from safeguard-ps.

When proposing new scripts or features, check safeguard-ps first to see if an
equivalent exists and use it as a guide for the bash implementation.

---

## Project Structure

```
safeguard-bash/
├── src/                    # CLI scripts (the SDK)
│   ├── connect-safeguard.sh
│   ├── disconnect-safeguard.sh
│   ├── invoke-safeguard-method.sh
│   ├── ... (35+ scripts)
│   └── utils/              # Shared libraries sourced by scripts
│       ├── loginfile.sh    # Login file management ($HOME/.safeguard_login)
│       ├── a2a.sh          # A2A (app-to-app) HTTP helpers
│       └── common.sh       # Exponential backoff/retry logic
├── test/                   # Integration test framework
│   ├── run-tests.sh        # Test runner entry point
│   ├── framework.sh        # Test framework library
│   ├── suites/             # Test suite scripts (suite-*.sh)
│   └── README.md
├── samples/                # Example integrations
├── pipeline-templates/     # Azure DevOps CI/CD YAML
├── build.sh                # Docker image + ZIP builder
├── run.sh                  # Docker container launcher
├── install-local.sh        # Install scripts to $HOME/scripts
├── Dockerfile              # Alpine container definition
└── AGENTS.md               # This file
```

---

## Setup and Development Workflow

There is no build step. Scripts are pure bash.

```bash
# Install scripts to $HOME/scripts and add to PATH
./install-local.sh
# Source your profile to pick up the PATH change
. ~/.bash_profile   # or . ~/.profile
```

After editing scripts in `src/`, re-run `./install-local.sh` to copy changes
and test them.

`build.sh` and `run.sh` are for Docker packaging only — not part of the normal
development workflow.

There is no linter or formatter for this project.

---

## Testing Against a Live Appliance

### Asking for Appliance Access

**Before running any tests, ask the user for appliance connection details.**

You need these three values:
- **Appliance address** — IP or hostname of a Safeguard appliance
- **Admin username** — typically `Admin`
- **Admin password** — the password for the admin account

Example prompt to the user:

> To run tests I need access to a live Safeguard appliance. Can you provide:
> 1. The appliance network address (IP or hostname)
> 2. An admin username (e.g. Admin)
> 3. The admin password

Do not hardcode credentials anywhere. Pass them only as command-line arguments
to the test runner.

### Running Tests

```bash
# Run all test suites
./test/run-tests.sh -a <appliance> -u <user> -p <password>

# Run a specific suite (substring match on filename)
./test/run-tests.sh -a <appliance> -u <user> -p <password> -s connect

# Run with v3 API
./test/run-tests.sh -a <appliance> -u <user> -p <password> -v 3
```

### Test Framework Architecture

The test framework (`test/framework.sh`) provides:

- **Assertions**: `sg_assert`, `sg_assert_equal`, `sg_assert_not_null`,
  `sg_assert_contains`, `sg_skip`
- **Cleanup registration**: `sg_register_cleanup` (LIFO execution order)
- **Suite lifecycle**: Setup → Execute → Registered Cleanups (LIFO) → Suite Cleanup
- **Helpers**: `sg_connect`, `sg_connect_pkce`, `sg_disconnect`, `sg_invoke`
- **ROG management**: `sg_ensure_rog_enabled`, `sg_restore_rog` — the test
  runner uses these to automatically enable the Resource Owner grant type
  before tests and restore the original setting afterward

### Writing a Test Suite

Create a file `test/suites/suite-<name>.sh` that defines these functions:

```bash
#!/bin/bash

suite_name()
{
    echo "My Feature"
}

suite_setup()
{
    # Create test objects, register cleanups
    # Return non-zero to skip Execute phase
    sg_connect
    return 0
}

suite_execute()
{
    # Run assertions
    local result=$(sg_invoke -s core -m GET -U "Me")
    sg_assert_not_null "GET Me returns data" "$result"

    local name=$(echo "$result" | jq -r '.Name' 2>/dev/null)
    sg_assert_equal "Username is correct" "$name" "$TestUser"
}

suite_cleanup()
{
    sg_disconnect
}
```

### Suite Lifecycle Rules

1. **Setup failure** → Execute phase is skipped, Cleanup still runs
2. **Cleanup always runs** — both registered cleanup actions and the
   `suite_cleanup` function execute regardless of test outcome
3. **Registered cleanups run FIRST, in LIFO order** — they execute while the
   current session is still active (login file exists), then `suite_cleanup`
   runs to restore session state for the next suite
4. **Register cleanup immediately** after creating each test object
5. **Suite functions are unloaded** between suites to prevent leakage
6. **Cannot delete the currently authenticated user** — suites that create
   their own admin user must handle deletion in `suite_cleanup()` by
   reconnecting as the original user first

### Writing Strong Assertions

Follow these principles (adapted from safeguard-ps):

1. **Always readback after create** — don't trust the return value alone; fetch
   the object again via API and verify its properties
2. **Always readback after edit** — confirm the change persisted and other
   fields are intact
3. **Always readback after delete** — verify the object is gone
4. **Assert specific values, not just existence** — prefer
   `sg_assert_equal "name" "$actual" "expected"` over
   `sg_assert_not_null "exists" "$result"`
5. **Test both return value AND readback** — use two separate assertions
6. **Use the SgBashTest prefix** for all test object names so they can be
   identified and cleaned up:
   ```bash
   TestAssetName="${TestPrefix}_MyAsset"
   ```
7. **Register cleanup immediately** after creating each object:
   ```bash
   sg_register_cleanup "Delete test asset" \
       "$ScriptDir/../src/invoke-safeguard-method.sh -s core -m DELETE -U Assets/$asset_id"
   ```

### Test Baseline

The current baseline when all suites pass:

```
Suites: 10 (0 failed)
Tests:  268 passed, 0 failed, 0 skipped
```

| Suite                  | Tests | Description                                       |
|------------------------|-------|---------------------------------------------------|
| A2A Access Req Broker  | 21    | Broker lifecycle: get/set/clear, IP restrictions, cert-auth request |
| A2A                    | 92    | Full A2A workflow: cert, registration, retrieval, credentials, IP restrictions |
| Asset Accounts         | 20    | Account CRUD, passwords, SSH keys, edit, filter    |
| Assets                 | 17    | Asset CRUD, platform validation, edit, filter      |
| Certificates           | 19    | Trusted cert install/uninstall, get, filter, fields |
| Connect & Core         | 16    | Connect, PKCE, login file, API calls, disconnect   |
| Event Discovery        | 25    | Event names, categories, properties, search/filter |
| Event Subscriptions    | 25    | Subscription CRUD, edit, find, SignalR/email types  |
| Platforms              | 17    | Built-in platform validation (Windows, Linux)      |
| Users                  | 16    | User CRUD, roles, edit, filter, delete             |

Update this baseline as you add suites and tests.

---

## Script Conventions

### Script Template

Every script in `src/` follows this structure:

```bash
#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: script-name.sh [-h]
       script-name.sh [-a appliance] [-B cabundle] ...

  -h  Show help and exit
  -a  Network address of the appliance
  ...

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Initialize ALL variables before getopts
Appliance=
CABundle=
CABundleArg=
Version=4

. "$ScriptDir/utils/loginfile.sh"

while getopts ":a:B:v:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    h) print_usage ;;
    esac
done
```

**Key rules:**
- `print_usage()` is always defined first, uses a heredoc, exits 0
- `ScriptDir` is resolved via `${BASH_SOURCE[0]}` (not `$0`) — this is
  critical for scripts that may be sourced
- All variables are initialized before the `getopts` loop
- Utilities are sourced with `. "$ScriptDir/utils/loginfile.sh"`
- Leading `:` in getopts string suppresses built-in error messages
- `-h` always shows help

### Common Option Flags

These flags are consistent across most scripts:

| Flag | Meaning                              |
|------|--------------------------------------|
| `-h` | Show help                           |
| `-a` | Appliance network address           |
| `-B` | CA bundle for SSL validation        |
| `-v` | API version (default: 4)            |
| `-i` | Identity provider                   |
| `-u` | Username                            |
| `-c` | Client certificate file             |
| `-k` | Client private key file             |
| `-t` | Access token                        |
| `-p` | Read password from stdin            |
| `-P` | Use PKCE authentication (connect-safeguard.sh) |
| `-S` | Secondary password / MFA code (with `-P`) |

### Error Handling

```bash
# Write errors to stderr
>&2 echo "Error message"

# Check curl exit codes
if [ $? -ne 0 ]; then
    exit 1
fi

# Detect JSON error responses via jq
Error=$(echo $Result | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    echo $Result    # Success — no error code
else
    echo $Result | jq .
    exit 1
fi

# Check for required tools at script start
if [ -z "$(which jq 2> /dev/null)" ]; then
    >&2 echo "This script requires jq"
    exit 1
fi
```

### Login File Pattern

Scripts share authentication state through `$HOME/.safeguard_login`, a
key=value file created with `umask 0077` (readable only by owner).

The file stores: `Appliance`, `Provider`, `AccessToken`, `CABundleArg`,
optionally `Cert`/`PKey` for certificate auth, and `Pkce=true` when PKCE
authentication was used.

Most scripts call `use_login_file()` from `utils/loginfile.sh`, which
auto-invokes `connect-safeguard.sh` if no login file exists.

**Lifecycle:**
1. `connect-safeguard.sh` creates the login file
2. Other scripts read it via `use_login_file()` (called automatically by
   `require_login_args`)
3. `disconnect-safeguard.sh` invalidates the token and removes the file

The `require_login_args` function in `utils/loginfile.sh` handles the full
auth resolution chain: login file → prompt → connect. Scripts just need to
call `require_login_args` (or define a `require_args()` that calls it) after
the getopts loop. No explicit `use_login_file` call is needed.

A few legacy scripts pass tokens via stdin using `<<<$AccessToken` with
`invoke-safeguard-method.sh -T` (the `-T` flag reads the token from stdin,
and `-N` suppresses automatic login file usage). This is the older calling
convention — new scripts should use `-t "$AccessToken"` instead.

### Sourcing Shared Utilities

Always source relative to `ScriptDir`:

```bash
. "$ScriptDir/utils/loginfile.sh"
. "$ScriptDir/utils/common.sh"
. "$ScriptDir/utils/a2a.sh"
```

---

## Safeguard API Patterns

### API Services

Safeguard hosts multiple services:

| Service      | Description                                    |
|-------------|------------------------------------------------|
| `core`       | Main application API (users, assets, policies) |
| `appliance`  | Appliance operations (status, clustering)      |
| `notification` | SignalR event connections                    |
| `a2a`        | Application-to-application credential retrieval|

### API Versioning

The default API version is **v4** (since safeguard-bash 7.0). Pass `-v 3` to
use the v3 API. Both v3 and v4 are hosted simultaneously on Safeguard 7.x
appliances.

### Authentication Methods

1. **Password (Resource Owner Grant)** — username + password to a local or
   directory identity provider. Requires the Resource Owner grant type to be
   enabled on the appliance (see below).
2. **Certificate** — client certificate + private key, provider set to
   `certificate`
3. **PKCE (Proof Key for Code Exchange)** — non-interactive OAuth2 flow that
   programmatically simulates the browser-based login without launching a
   browser. Use `connect-safeguard.sh -P`. This does **not** require the
   Resource Owner grant type to be enabled, making it the most reliable
   connection method.

For scripting and testing, PKCE authentication (`-P`) with a local admin
account is the recommended approach because it works regardless of the
appliance's grant type configuration. Password authentication is also
supported but requires the Resource Owner grant type to be enabled.

### Resource Owner Grant Type

The Resource Owner password grant (`grant_type=password`) may be disabled on
the appliance by default. The appliance setting "Allowed OAuth2 Grant Types"
controls which grant types are permitted.

To check/modify this setting programmatically:

```bash
# Read current grant types (requires an active session)
invoke-safeguard-method.sh -s core -m GET -U "Settings" \
    | jq '.[] | select(.Name=="Allowed OAuth2 Grant Types") | .Value'

# Enable Resource Owner grant (note: URL-encode the setting name)
invoke-safeguard-method.sh -s core -m PUT \
    -U "Settings/Allowed%20OAuth2%20Grant%20Types" \
    -b '{"Value":"ResourceOwner"}'
```

**Important:** The setting name contains spaces and must be URL-encoded
(`%20`) in the URL path when using `invoke-safeguard-method.sh`.

The test runner automatically handles this: it connects via PKCE, enables
ROG if needed, runs all suites, then restores the original setting.

### SSL/TLS

By default, safeguard-bash disables SSL verification (`-k` flag to curl).
To validate SSL, pass `-B /path/to/ca-bundle.pem` to scripts.

### Common API Endpoints

```bash
# Get current user info
invoke-safeguard-method.sh -s core -m GET -U "Me"

# Get appliance status (anonymous)
get-appliance-status.sh -a <appliance>

# List assets
invoke-safeguard-method.sh -s core -m GET -U "Assets"

# Create a user
invoke-safeguard-method.sh -s core -m POST -U "Users" \
    -b '{"Name":"TestUser","PrimaryAuthenticationProvider":{"Id":-1}}'

# Delete a user
invoke-safeguard-method.sh -s core -m DELETE -U "Users/<id>"
```

### Identity Provider IDs

These magic IDs are used across the API:

| ID   | Meaning                                |
|------|----------------------------------------|
| `-1` | Local identity provider                |
| `-2` | Certificate authentication provider    |

When creating a **local user**, set
`PrimaryAuthenticationProvider.Id` to `-1`. When creating a **certificate
user**, set it to `-2` with the SHA-1 thumbprint as the `Identity`:

```bash
# Local user
{"Name": "MyUser", "PrimaryAuthenticationProvider": {"Id": -1}}

# Certificate user (v4 API)
{"Name": "MyCertUser",
 "IdentityProvider": {"Id": -1},
 "PrimaryAuthenticationProvider": {"Id": -2, "Identity": "<SHA1-THUMBPRINT>"}}
```

### Setting Passwords

Set passwords on users or accounts via PUT with a bare JSON string:

```bash
# Set user password
invoke-safeguard-method.sh -s core -m PUT -U "Users/<id>/Password" \
    -b '"MyNewPassword1!"'

# Set account password
invoke-safeguard-method.sh -s core -m PUT -U "AssetAccounts/<id>/Password" \
    -b '"AccountPass1!"'
```

Note the double quoting: the outer quotes are for bash, the inner quotes make
it a valid JSON string value.

### Role Requirements by Operation

| Operation                           | Required Role(s)     |
|-------------------------------------|----------------------|
| Create/edit/delete Users            | UserAdmin            |
| Create/edit/delete Assets           | AssetAdmin           |
| Create/edit/delete Asset Accounts   | AssetAdmin           |
| Create/edit/delete A2A Registrations| PolicyAdmin          |
| Install Trusted Certificates        | ApplianceAdmin       |
| Create Certificate Users            | UserAdmin            |

The built-in Admin account only has UserAdmin and Authorizer. Tests needing
AssetAdmin, PolicyAdmin, or ApplianceAdmin must create a temporary user with
the appropriate roles.

### User Object Field Names

The v4 API uses `Name` (not `UserName`) for the user's login name. Other key
fields: `DisplayName`, `Id`, `PrimaryAuthenticationProvider`. Always inspect
the actual API response with `jq keys` if unsure about field names.

### Local Provider Usernames

Local provider usernames are **case-insensitive**. The API may return a
different casing than what was provided at login (e.g. you pass `admin` but
`GET Me` returns `Admin`). Always normalize case before comparing usernames
in tests or scripts.

### Built-in Admin Account

The built-in `Admin` account has **Authorizer** and **UserAdmin** roles but
does **not** have **AssetAdmin** or **PolicyAdmin**. These roles cannot be
added to the built-in Admin account (Safeguard returns error 50100).

For tests that need full admin rights, create a temporary user with all roles
and use that for the test run.

### POST-then-PUT Pattern

Some Safeguard API endpoints do not accept all properties during POST (create).
You must create first, then PUT (update) additional properties:

```bash
# Create with minimal properties
Result=$(invoke-safeguard-method.sh -s core -m POST -U "Endpoint" -b "$CreateBody")
Id=$(echo $Result | jq -r '.Id')

# Update with full properties
invoke-safeguard-method.sh -s core -m PUT -U "Endpoint/$Id" -b "$FullBody"
```

### SCIM-style Filtering

Many GET endpoints support server-side filtering via query parameters:

```bash
# Filter platforms by family
invoke-safeguard-method.sh -s core -m GET \
    -U "Platforms?filter=PlatformFamily%20eq%20'Custom'"
```

### CRUD Helper Scripts

safeguard-bash includes purpose-built scripts for common CRUD operations:

| Script                            | Description                              |
|-----------------------------------|------------------------------------------|
| `new-user.sh`                     | Create local user with roles             |
| `remove-user.sh`                  | Delete user by ID                        |
| `new-asset.sh`                    | Create asset with platform/address       |
| `remove-asset.sh`                 | Delete asset by ID                       |
| `new-asset-account.sh`            | Create account on an asset               |
| `remove-asset-account.sh`         | Delete account by ID                     |
| `new-a2a-registration.sh`         | Create A2A registration                  |
| `remove-a2a-registration.sh`      | Delete A2A registration                  |
| `get-a2a-registration.sh`         | List/get A2A registrations               |
| `edit-a2a-registration.sh`        | Edit A2A registration properties         |
| `add-a2a-credential-retrieval.sh` | Add account to A2A retrieval             |
| `remove-a2a-credential-retrieval.sh` | Remove account from A2A retrieval     |
| `get-a2a-credential-retrieval.sh` | List credential retrievals for a registration |
| `get-a2a-credential-retrieval-info.sh` | Summary info across all registrations |
| `get-a2a-apikey.sh`               | Get API key for a credential retrieval   |
| `reset-a2a-apikey.sh`             | Regenerate API key for a credential retrieval |
| `get-a2a-access-request-broker.sh`   | Get access request broker config      |
| `set-a2a-access-request-broker.sh`   | Configure access request broker       |
| `clear-a2a-access-request-broker.sh` | Remove access request broker config   |
| `new-a2a-access-request.sh`       | Broker an access request via A2A (cert auth) |
| `set-a2a-password.sh`             | Set account password via A2A (cert auth) |
| `set-a2a-privatekey.sh`           | Set account SSH key via A2A (cert auth)  |
| `get-a2a-ip-restriction.sh`       | Get IP restrictions on credential retrieval |
| `set-a2a-ip-restriction.sh`       | Set IP restrictions                      |
| `clear-a2a-ip-restriction.sh`     | Clear all IP restrictions                |
| `get-a2a-service-status.sh`       | Get A2A service status (enabled/disabled) |
| `enable-a2a-service.sh`           | Enable the A2A service                   |
| `disable-a2a-service.sh`          | Disable the A2A service                  |
| `install-trusted-certificate.sh`  | Install a trusted certificate            |
| `uninstall-trusted-certificate.sh`| Remove a trusted certificate             |
| `get-trusted-certificate.sh`      | List/get trusted certificates            |
| `new-event-subscription.sh`       | Create event subscription (SignalR/email) |
| `remove-event-subscription.sh`    | Delete event subscription                |
| `get-event-subscription.sh`       | List/get event subscriptions             |
| `edit-event-subscription.sh`      | Edit event subscription properties       |
| `find-event-subscription.sh`      | Search event subscriptions               |
| `get-event-name.sh`               | List subscribable event names            |
| `get-event-category.sh`           | List event categories                    |
| `get-event-property.sh`           | Get notification properties for an event |
| `find-event.sh`                   | Search events by text or SCIM filter     |

### Asset Creation

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

### User Admin Roles

Valid admin roles for Users: `GlobalAdmin`, `Auditor`, `AssetAdmin`,
`ApplianceAdmin`, `PolicyAdmin`, `UserAdmin`, `HelpdeskAdmin`,
`OperationsAdmin`, `ApplicationAuditor`, `SystemAuditor`.

**Note:** `Authorizer` is NOT a valid admin role — it is a request workflow
concept. `GlobalAdmin` automatically implies `HelpdeskAdmin`,
`ApplicationAuditor`, and `SystemAuditor`.

Admin roles ARE accepted during POST (no PUT needed). However, `Description`
is NOT accepted during POST — requires POST-then-PUT.

### A2A (Application-to-Application) Workflow

The full A2A setup flow:

1. Generate a client certificate (key + cert PEM files)
2. Install the certificate as a TrustedCertificate on the appliance
3. Create a certificate user linked to the cert thumbprint
4. Create an A2A registration linked to the certificate user
5. Add accounts for credential retrieval (returns an API key per account)
6. Use `get-a2a-password.sh` with cert + key + API key to retrieve passwords

Example scripted setup:

```bash
# 1. Generate self-signed cert
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
    -days 30 -nodes -subj "/CN=MyA2ACert"

# 2. Install as trusted certificate (requires ApplianceAdmin)
cert_data=$(base64 -w 0 cert.pem)
invoke-safeguard-method.sh -s core -m POST -U "TrustedCertificates" \
    -b "{\"Base64CertificateData\": \"$cert_data\"}"

# 3. Create certificate user (requires UserAdmin)
thumbprint=$(openssl x509 -noout -fingerprint -sha1 -in cert.pem \
    | cut -d= -f2 | tr -d :)
new-certificate-user.sh -n "MyCertUser" -s "$thumbprint"

# 4. Create A2A registration (requires PolicyAdmin)
new-a2a-registration.sh -n "MyApp" -C <certUserId>

# 5. Add account for credential retrieval
add-a2a-credential-retrieval.sh -r <regId> -c <accountId>
# Response contains the ApiKey

# 6. Retrieve password via A2A (uses cert auth, not token)
echo "" | get-a2a-password.sh -a <appliance> -c cert.pem -k key.pem \
    -A <apiKey> -p -r
```

Key API details:
- `TrustedCertificates` uses `Thumbprint` as identifier (no numeric `Id`
  field) — use `jq -r '.Thumbprint'` not `.Id`
- `A2ARegistrations/{id}/RetrievableAccounts` POST uses flat `{"AccountId": N}`
  (not nested — opposite of AssetAccounts!)
- The POST response includes the `ApiKey` needed for credential retrieval
- A2A password retrieval requires PolicyAdmin role to set up, but uses
  certificate auth (not token auth) for actual retrieval
- `get-a2a-password.sh` prompts for "Private Key Password:" — use `-p` flag
  and pipe empty string for passwordless keys: `echo "" | get-a2a-password.sh -p ...`
- The `-r` flag on `get-a2a-password.sh` strips JSON quotes for raw password output
- To delete a trusted certificate: `DELETE TrustedCertificates/<thumbprint>`

### A2A Access Request Brokering

An A2A registration can also be configured as an access request broker, which
allows an application to create access requests on behalf of other users:

1. Create an A2A registration (steps 1-4 of the credential retrieval workflow)
2. Configure the broker with authorized users/groups
3. Use the broker API key with cert auth to create access requests

```bash
# 1. Configure broker on an existing registration (requires PolicyAdmin)
set-a2a-access-request-broker.sh -i <regId> \
    -b '{"Users": [{"UserId": 45}], "Groups": [{"GroupId": 10}]}'
# Response includes the broker ApiKey

# 2. Get current broker configuration
get-a2a-access-request-broker.sh -i <regId>

# 3. Broker an access request via cert auth
echo "" | new-a2a-access-request.sh -a <appliance> -c cert.pem -k key.pem \
    -A <brokerApiKey> -b '{
        "ForUser": "jsmith",
        "AssetName": "linux-server",
        "AccountName": "root",
        "AccessRequestType": "Password"
    }' -p

# 4. Clear broker configuration
clear-a2a-access-request-broker.sh -i <regId>
```

Key details:
- One broker per A2A registration (set replaces existing config)
- Broker body uses nested objects: `{"Users": [{"UserId": N}]}` not flat arrays
- The broker API key is separate from credential retrieval API keys
- `new-a2a-access-request.sh` uses cert auth (same pattern as `get-a2a-password.sh`)
- Supported AccessRequestType values: Password, SSHKey, SSH, RemoteDesktop, Telnet

### Event Subscription Management

Event subscriptions configure how users receive notifications for Safeguard
events. Subscriptions can use SignalR (real-time) or email delivery:

```bash
# Create a SignalR subscription for user events
new-event-subscription.sh -d "User changes" -T Signalr \
    -e "UserCreated,UserModified"

# List all subscriptions
get-event-subscription.sh

# Edit a subscription
edit-event-subscription.sh -i <subId> -d "Updated description" \
    -e "UserCreated"

# Search for subscriptions
find-event-subscription.sh -Q "user"

# Delete a subscription
remove-event-subscription.sh -i <subId>
```

### Event Discovery

Event discovery scripts help find subscribable events and their properties:

```bash
# List all event names
get-event-name.sh

# Filter events by object type or category
get-event-name.sh -T User
get-event-name.sh -C UserAuthentication

# List event categories
get-event-category.sh

# Get notification properties for a specific event
get-event-property.sh -n UserCreated

# Search events by text or SCIM filter
find-event.sh -Q "password"
find-event.sh -q "ObjectType eq 'Asset'"
```

### Well-Known Platform IDs

These built-in platform IDs are stable across Safeguard installations:

| ID  | Platform         |
|-----|------------------|
| 521 | Linux            |
| 547 | Windows Server   |
| 548 | Windows Desktop  |

---

## Dependencies

Scripts require: `bash`, `curl`, `jq` (optional but strongly recommended),
`openssl`, `sed`, `grep`.

The Docker image (Alpine-based) bundles all of these. For local development,
install `jq` separately — it is not installed by default on most systems but
significantly improves the user experience with JSON output.

---

## CI/CD

Azure DevOps Pipelines (`build.yml` + `pipeline-templates/`):

- **PR validation**: builds Docker image
- **Merge to master/release-***: builds, creates GitHub release, pushes to
  Docker Hub

---

## Security Notes

- Never commit secrets, tokens, or credentials
- The login file (`$HOME/.safeguard_login`) contains access tokens — don't
  log or serialize it
- Test credentials are passed only as command-line arguments to the test
  runner, never hardcoded in suites
- `-k` (disable SSL verification) is used by default for development — do not
  recommend for production without explanation
