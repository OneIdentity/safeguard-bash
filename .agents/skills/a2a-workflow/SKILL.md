---
name: a2a-workflow
description: >-
  Use when working on A2A (application-to-application) scripts, certificate
  authentication, credential retrieval, access request brokering, A2A
  service management, event subscriptions, or event discovery.
---

# A2A Workflow & Events

## A2A (Application-to-Application) Overview

A2A allows applications to retrieve credentials (passwords, SSH keys, API key
secrets) from Safeguard without human interaction. The application
authenticates with a client certificate, not a user token.

### Full A2A Setup Flow

1. Generate a client certificate (key + cert PEM files)
2. Install the certificate as a TrustedCertificate on the appliance
3. Create a certificate user linked to the cert thumbprint
4. Create an A2A registration linked to the certificate user
5. Add accounts for credential retrieval (returns an API key per account)
6. Use `get-a2a-password.sh` with cert + key + API key to retrieve passwords

### Scripted Example

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

---

## Key API Details

### TrustedCertificates

- Uses `Thumbprint` as identifier (no numeric `Id` field) — use
  `jq -r '.Thumbprint'` not `.Id`
- To delete: `DELETE TrustedCertificates/<thumbprint>`
- Certificate data must be base64-encoded (no line wraps): `base64 -w 0`

### A2A Registrations

- `A2ARegistrations/{id}/RetrievableAccounts` POST uses flat
  `{"AccountId": N}` — **not** nested (opposite of AssetAccounts!)
- The POST response includes the `ApiKey` needed for credential retrieval
- A2A password retrieval requires **PolicyAdmin** role to set up, but uses
  **certificate auth** (not token auth) for actual retrieval

### VisibleToCertificateUsers

A2A registrations need `VisibleToCertificateUsers=true` for cert-auth
listing via `core/A2ARegistrations`. Use the `-V` flag with
`new-a2a-registration.sh`. Without it, cert auth returns empty `[]`.

```bash
new-a2a-registration.sh -n "MyApp" -C <certUserId> -V
```

### Certificate Auth Stdin Pattern

`get-a2a-password.sh` and similar cert-auth scripts prompt for "Private Key
Password:". For passwordless keys, use `-p` and pipe an empty string:

```bash
echo "" | get-a2a-password.sh -a <appliance> -c cert.pem -k key.pem \
    -A <apiKey> -p -r
```

The `-r` flag strips JSON quotes for raw password output.

### Known Issue: PassStdin Not Used

Several cert-auth A2A scripts (e.g., `get-a2a-password.sh`,
`get-a2a-privatekey.sh`, `set-a2a-password.sh`) advertise `-p` for reading
the key password from stdin, but the parsed `PassStdin` variable is never
used in the curl command. They still prompt interactively. The `echo "" |`
workaround satisfies the prompt for passwordless keys.

### A2A Service Must Be Enabled

The A2A service must be enabled before credential retrieval works:

```bash
enable-a2a-service.sh
get-a2a-service-status.sh   # Verify: should show enabled
```

### utils/a2a.sh Internals

The `utils/a2a.sh` library provides HTTP helpers for A2A cert-auth calls.
It includes an openssl fallback for systems where curl is linked against
GnuTLS (which has different cert handling than OpenSSL). The helper
constructs raw HTTPS requests via `openssl s_client` when needed.

### Certificate Utility Scripts

These scripts in `src/utils/` help with certificate generation and
conversion for A2A setup:

| Script | Description |
|--------|-------------|
| `new-test-ca.sh` | Generate a self-signed CA certificate + key |
| `new-test-cert.sh` | Generate a certificate signed by a test CA |
| `convert-pfx-to-pem.sh` | Convert PFX/PKCS12 to separate PEM files |
| `add-pem-password.sh` | Add a password to a PEM private key |
| `remove-pem-password.sh` | Remove a password from a PEM private key |

---

## A2A Access Request Brokering

An A2A registration can also be configured as an access request broker, which
allows an application to create access requests on behalf of other users.

### Setup Flow

1. Create an A2A registration (steps 1-4 of the credential retrieval workflow)
2. Configure the broker with authorized users/groups
3. Use the broker API key with cert auth to create access requests

### Example

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

### Key Details

- One broker per A2A registration (set replaces existing config)
- Broker body uses nested objects: `{"Users": [{"UserId": N}]}` not flat arrays
- The broker API key is **separate** from credential retrieval API keys
- `new-a2a-access-request.sh` uses cert auth (same pattern as `get-a2a-password.sh`)
- Supported AccessRequestType values: `Password`, `SSHKey`, `SSH`,
  `RemoteDesktop`, `Telnet`

---

## Event Subscription Management

Event subscriptions configure how users receive notifications for Safeguard
events. Subscriptions can use SignalR (real-time) or email delivery.

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

---

## Event Discovery

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

---

## Event Listeners & Handlers

For real-time event processing, safeguard-bash provides listener and handler
scripts that connect to Safeguard's SignalR endpoints:

| Script | Description |
|--------|-------------|
| `listen-for-event.sh` | Connect to SignalR and dump events to stdout |
| `handle-event.sh` | Resilient event listener that invokes a handler script |
| `listen-for-a2a-event.sh` | Connect to A2A SignalR events |
| `handle-a2a-password-event.sh` | Handle A2A password change events |
| `handle-a2a-privatekey-event.sh` | Handle A2A SSH key change events |
| `handle-a2a-apikeysecret-event.sh` | Handle A2A API key secret change events |

`handle-event.sh` provides automatic reconnection with exponential backoff
(via `utils/common.sh`) for long-running event processing.
