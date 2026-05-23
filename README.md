[![Docker Hub](https://img.shields.io/badge/docker-oneidentity%2Fsafeguard--bash-blue.svg)](https://hub.docker.com/r/oneidentity/safeguard-bash/)
[![GitHub](https://img.shields.io/github/license/OneIdentity/safeguard-bash.svg)](https://github.com/OneIdentity/safeguard-bash/blob/master/LICENSE)

# safeguard-bash
One Identity Safeguard Bash and cURL scripting resources.

-----------

<p align="center">
<i>Check out our <a href="samples">sample projects</a> to get started with your own custom integration to Safeguard!</i>
</p>

-----------

## Support

One Identity open source projects are supported through [One Identity GitHub issues](https://github.com/OneIdentity/safeguard-bash/issues) and the [One Identity Community](https://www.oneidentity.com/community/). This includes all scripts, plugins, SDKs, modules, code snippets or other solutions. For assistance with any One Identity GitHub project, please raise a new Issue on the [One Identity GitHub project](https://github.com/OneIdentity/safeguard-bash/issues) page. You may also visit the [One Identity Community](https://www.oneidentity.com/community/) to ask questions.  Requests for assistance made through official One Identity Support will be referred back to GitHub and the One Identity Community forums where those requests can benefit all users.

If you would like to contribute to safeguard-bash, see the [developer guide](https://github.com/OneIdentity/safeguard-bash/blob/master/src/README.md).

## Default API Update

safeguard-bash will use v4 API by default starting with version 7.0. It is
possible to continue using the v3 API by passing in the `-v` parameter
when creating a connection or calling A2A or any of the other scripts.

Safeguard for Privileged Passwords 7.X hosts both the v3 and v4 APIs. New coding
projects should target the v4 API, and existing projects can be migrated over time.
Notification will be given to customers many releases in advance of any plans to
remove the v3 API. There are currently no plans to remove the v3 API.

```Bash
# Use v3 instead of v4 when connecting
$ connect-safeguard.sh -a 192.168.123.123 -i local -u Admin -v 3
Password:
A login file has been created.
# All subsequent script commands will use v3 if they support the login file
```

## Installation
The easiest way to install safeguard-bash is via Docker; however, you can
also download a zip file from
[Releases](https://github.com/OneIdentity/safeguard-bash/releases) or clone
this GitHub repository and copy the scripts from the `src` directory
(including the `utils` subdirectory) to a desired location on your file
system and add them to your `PATH`.

The `install-local.sh` script will copy the scripts to `$HOME/scripts` and
make sure that directory is added to your `PATH` in your `.bash_profile` or
`.profile`. Each time you start Bash, your Safeguard scripting environment
will be ready to use.

```Bash
$ ./install-local.sh
```

### Installing via Docker
This code has been compiled into a Docker image hosted on [DockerHub](https://hub.docker.com/u/oneidentity/dashboard/).
If you have Docker installed, you can simply run:

```Bash
$ docker run -it oneidentity/safeguard-bash
```

It is an extremely light-weight image, and it automatically calls the
`connect-safeguard.sh` script as the image is run.

### Installing from GitHub
After cloning this repository, simply run the `install-local.sh` script.
This will copy the relevant scripts to `$HOME/scripts`. Then, just add
that directory to your `$PATH` environment variable.

These scripts are based on bash, cURL, and jq.  cURL can function slightly
differently on different platforms, and jq is often not installed by default.
Many of the scripts will work without jq, but the user experience is much
better with jq due to the pretty output.

Just use Docker, and you won't have to worry about prerequisites!

## TLS Verification

**Default behaviour.** For backwards compatibility with every existing
customer integration, every safeguard-bash script defaults to
`CABundleArg="-k"` (passes `-k` / `--insecure` to cURL, which skips TLS
certificate verification). This is implemented in
`src/utils/loginfile.sh::handle_ca_bundle_arg` and applies to
`connect-safeguard.sh`, `invoke-safeguard-method.sh`, `get-trusted-ca-bundle.sh`,
the A2A flows in `src/utils/a2a.sh`, and every other script that uses
`-K <(cat <<EOF...)` curl config.

**This default is insecure.** A network attacker between you and the
appliance can intercept the TLS connection and read or modify Safeguard
API traffic (including bearer tokens, A2A API keys, and credential
material). We are not flipping this default in the current release line
because doing so would silently break every shipping integration; the
default flip is tracked for the next major version. **For any production
or shared-network deployment, follow the secure-by-default recipe below.**

### Secure-by-default recipe

1. **Bootstrap the appliance's CA bundle once.** From a workstation with
   network access to the appliance, use the bundled
   `get-trusted-ca-bundle.sh` to download the issuing chain (this script
   ships with safeguard-bash and writes `<appliance-name>.ca-bundle.crt`
   to the current directory):

   ```Bash
   $ connect-safeguard.sh -a 10.5.32.162 -i local -u Admin -P
   $ get-trusted-ca-bundle.sh -a 10.5.32.162
   Saving SSL certificate issuers to spp-prod-01.ca-bundle.crt
   ```

   Alternatively, if the appliance is self-signed and you trust the
   network you are running this initial fetch from, you can extract the
   leaf certificate with OpenSSL:

   ```Bash
   $ openssl s_client -showcerts -connect 10.5.32.162:443 </dev/null \
       2>/dev/null \
       | sed -n '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' \
       > spp-prod-01.ca-bundle.crt
   ```

   Verify the fingerprint of the resulting bundle out-of-band (through
   the appliance web UI, a trusted operator, or an existing certificate
   inventory) before trusting it.

2. **Export `$CABundle` in every shell that runs safeguard-bash
   scripts.** `handle_ca_bundle_arg` consults `$CABundle` before falling
   back to `-k`; setting it to an absolute path causes every subsequent
   call to pass `--cacert <path>` to cURL, which enforces TLS
   verification:

   ```Bash
   $ export CABundle="$PWD/spp-prod-01.ca-bundle.crt"
   $ connect-safeguard.sh -a 10.5.32.162 -i local -u Admin -P
   ```

   You can also pass the bundle per-invocation with `-B`:

   ```Bash
   $ connect-safeguard.sh -a 10.5.32.162 -B "$PWD/spp-prod-01.ca-bundle.crt" \
                          -i local -u Admin -P
   ```

3. **Persist the export** (`.bash_profile`, systemd unit `Environment=`,
   container `ENV CABundle=...`, scheduled-task wrapper, etc.) so every
   shell that invokes a safeguard-bash script picks it up automatically.

### Trust-on-first-use (TOFU) caveat

The bootstrap call to `get-trusted-ca-bundle.sh` (or to
`openssl s_client -showcerts`) itself runs over an unverified TLS
connection, because the CA bundle does not yet exist locally. This is
the standard TOFU pattern. Mitigations:

- Perform the bootstrap from a trusted network segment (an admin
  workstation directly attached to the appliance management VLAN).
- Verify the downloaded certificate fingerprint against the appliance
  web UI ("Certificates → SSL Certificate") or an out-of-band record
  before exporting `$CABundle`.
- Rotate / re-bootstrap whenever the appliance SSL certificate is
  reissued.

After the bundle is in place, all subsequent script invocations validate
the appliance certificate chain and are not subject to MITM.

## Getting Started
Once safeguard-bash is installed, you can begin by running `connect-safeguard.sh`.
Authentication in Safeguard is based on OAuth2. The recommended connection method
is PKCE (Proof Key for Code Exchange), which works regardless of the appliance's
grant type configuration:

```Bash
$ connect-safeguard.sh -a 10.5.32.162 -i local -u Admin -P
Password:
A login file has been created.
```

The `-P` flag uses PKCE authentication, which programmatically simulates the
browser-based OAuth2 flow without launching a browser. This is the most reliable
connection method because it does not require the Resource Owner password grant
type to be enabled on the appliance.

If your appliance has the Resource Owner grant type enabled, you can also use
direct password authentication (the classic method):

```Bash
$ connect-safeguard.sh
Appliance network address: 10.5.32.162
Identity Provider (certificate local ad2-dan.vas): local
Appliance Login: Admin
Password:
A login file has been created.
```

> **Note:** Starting with newer Safeguard versions, the Resource Owner password
> grant type may be disabled by default. If you receive authentication errors
> using the classic method, use `-P` for PKCE authentication instead.

The `connect-safeguard.sh` script will create a login file that includes
your access token and connection information.  This makes it easier to call
other scripts without having to retype connection information.  This login
file is created in your home directory, and can only be read by your
user.

Client certificate authentication is also available in `connect-safeguard.sh`.

```Bash
$ connect-safeguard.sh -a 10.5.32.162 -i certificate -c cert.pem -k key.pem
Password:
A login file has been created.
```

For non-interactive scripting, pipe the password via stdin using `-p`:

```Bash
$ echo "MyPassword" | connect-safeguard.sh -a 10.5.32.162 -i local -u Admin -P -p
A login file has been created.
```

The `invoke-safeguard-method.sh` script will facilitate a call to the Web API.
Safeguard hosts multiple services as part of the Web API:

- core -- the main Safeguard application Web API
- appliance -- Web API for appliance-specific operations
- event -- Connect to SignalR to receive live events (use event scripts for this)
- a2a -- Specific Web API for application to application use cases

A typical call to `invoke-safeguard-method.sh` requires `-s` to specify a service
from the list above, `-m` for the HTTP method to use (GET, PUT, POST, DELETE), and
`-U` for the relative URL of the endpoint.

You may use `show-safeguard-method.sh` to see what methods can be called from
which services.

```Bash
# Get information about the currently authenticated user
$ invoke-safeguard-method.sh -s core -m GET -U "Me"

# Get appliance status (anonymous -- no login required)
$ get-appliance-status.sh -a 10.5.32.162

# Create an object using POST with a JSON body (-b)
$ invoke-safeguard-method.sh -s core -m POST -U "Users" \
    -b '{"Name":"jsmith","PrimaryAuthenticationProvider":{"Id":-1}}'

# Update an object using PUT
$ invoke-safeguard-method.sh -s core -m PUT -U "Users/123" \
    -b '{"Id":123,"Name":"jsmith","Description":"Updated description"}'

# Delete an object
$ invoke-safeguard-method.sh -s core -m DELETE -U "Users/123"

# Filter results using SCIM-style query parameters
$ invoke-safeguard-method.sh -s core -m GET \
    -U "Assets?filter=PlatformId%20eq%20521"
```

If you do not have rights to access a particular portion of the Web API,
you will be presented with an error message saying authorization is
required.

```Bash
$ invoke-safeguard-method.sh -s core -m GET -U Assets
{
  "Code": 60108,
  "Message": "Authorization is required for this request.",
  "InnerError": null
}
```

When you are finished, you can call the `disconnect-safeguard.sh` script
to invalidate and remove your access token.

## Users and Assets

safeguard-bash includes purpose-built scripts for common user and asset
management operations, so you don't always have to construct API calls manually.

### Managing Users

```Bash
# Create a local user with permissions (reads password from stdin via -p)
$ echo "MyP@ssword1" | new-user.sh -n "jsmith" -d "Service account" \
    -R "AssetAdmin,PolicyAdmin" -p

# List all users
$ invoke-safeguard-method.sh -s core -m GET -U "Users"

# Search for a user by name
$ invoke-safeguard-method.sh -s core -m GET \
    -U "Users?filter=Name%20eq%20'jsmith'"

# Set or change a user's password
$ invoke-safeguard-method.sh -s core -m PUT -U "Users/123/Password" \
    -b '"NewP@ssword1"'

# Delete a user by ID
$ remove-user.sh -i 123
```

### Managing Assets and Accounts

```Bash
# Create a Linux asset (platform ID 521)
$ new-asset.sh -n "web-server-01" -N "10.0.0.100" -P 521 -D "Production web server"

# Create a Windows Server asset (platform ID 547)
$ new-asset.sh -n "dc-01" -N "10.0.0.10" -P 547

# Look up a platform ID by name
$ get-platform.sh -n "Linux"

# Create an account on an asset
$ new-asset-account.sh -s <assetId> -n "root" -D "Root account"

# Set an account password
$ invoke-safeguard-method.sh -s core -m PUT -U "AssetAccounts/456/Password" \
    -b '"AccountP@ss1"'

# Delete an account, then the asset
$ remove-asset-account.sh -i 456
$ remove-asset.sh -i 354
```

## Docker

Linux distributions do not always provide a reliable set of components that are
used in the safeguard-bash scripts.  Very small differences in functionality for
Bash, sed, grep, or curl can cause incompatibility.  The easiest way to ensure that
you always have a properly functioning safeguard-bash environment is to run the
scripts from a Docker container.

The `run.sh` script will automatically build a local image for safeguard-bash based
on the sources you have checked out.  This is convenient for when you are making
changes to safeguard-bash scripts and want to test them out in a container.

If you don't want to run `connect-safeguard.sh` automatically when you enter the
container, you can use the `run.sh` script to execute the `docker` binary to run
a different entry point using `-c`.  `run.sh` may also be used to easily mount a
local directory for use inside your running container using `-v`.  This is useful
for when certificate files are needed to connect to Safeguard.  For example:

```Bash
$ ./run.sh -v ~/certs -c bash
```

This will mount my `~/certs` directory inside the container at `/volume` and will
just drop me at a Bash prompt rather than running `connect-safeguard.sh`
automatically.

## Events

Safeguard uses SignalR to provide persistent connections with real-time updates
for events as they happen on the appliance.  The events are sent to connected
clients that have the appropriate rights to receive that notification via SignalR.
An example would be an asset administrator receiving events every time a password
on an asset changes.  Another example would be a receiving an approval required
notification for when a requester asks for access based on a policy where you are
listed as an approver.  Nearly every action that changes data on Safeguard will
generate an event that can be received over SignalR.  The following command line
will give you a list of all of the possible events.

```Bash
$ get-event.sh
```

You can also discover events using the event discovery scripts:

```Bash
$ get-event-name.sh                         # List all subscribable event names
$ get-event-name.sh -T User                 # Filter by object type
$ get-event-category.sh                     # List event categories
$ get-event-property.sh -n UserCreated      # Get properties for a specific event
$ find-event.sh -Q "password"               # Search events by text
```

### Event Subscriptions

Event subscriptions configure how you receive notifications for specific events.
Subscriptions support SignalR (real-time) and email delivery:

```Bash
$ new-event-subscription.sh -d "User changes" -T Signalr -e "UserCreated,UserModified"
$ get-event-subscription.sh                 # List all subscriptions
$ edit-event-subscription.sh -i <id> -d "Updated" -e "UserCreated"
$ find-event-subscription.sh -Q "user"      # Search subscriptions
$ remove-event-subscription.sh -i <id>      # Delete a subscription
```

### Event Handlers

The `listen-for-event.sh` script and the `listen-for-a2a-event.sh` script will
connect to SignalR and dump every event received in that user's context as a JSON
object.  These two scripts are paired with the `handle-event.sh` script and the
`handle-a2a-password-event.sh` script respectively to provide a robust mechanism
for listening for events and calling handler scripts.  These `handle-*` scripts
include additional logic to make sure that SignalR remains connected even through
access token timeouts or connection interruptions.

There are some examples in the sample directory.

```Bash
$ handle-event.sh -a 10.5.32.162 -i local -u user -E UserCreated -S my_event_handler.sh
```

The above command will call the `my_event_handler.sh` script every time a
new user is created and pass information about the event as well as some data
to contact Safeguard using an access token to take action on the event.  See
`handle-event.sh -h` for more details.

Also see the [event-handling](samples/event-handling) samples.

### A2A Password Listener Sample running in Docker

A 5 minute video demonstrating the use of safeguard-bash running in a Docker
container to create a resilient A2A event listener to handle password changes
to execute a script every time the password changes.

This sample demonstrates a technique to securely use a certificate file from
the Docker environment.  The source code is available from the samples directory.

[A2A Password Listener video](https://www.youtube.com/watch?v=UQFcNgYKnTI)

[![A2A Password Listener](https://img.youtube.com/vi/UQFcNgYKnTI/0.jpg)](https://www.youtube.com/watch?v=UQFcNgYKnTI)

## A2A (Application-to-Application)

safeguard-bash provides comprehensive A2A management scripts for configuring
and using application-to-application credential retrieval and access request
brokering.

### A2A Registration Management

```Bash
$ new-a2a-registration.sh -n "MyApp" -C <certUserId> -V   # Create registration
$ get-a2a-registration.sh                                   # List all
$ get-a2a-registration.sh -i <id>                           # Get by ID
$ edit-a2a-registration.sh -i <id> -D "Updated desc"        # Edit
$ remove-a2a-registration.sh -i <id>                        # Delete
```

### Credential Retrieval

```Bash
$ add-a2a-credential-retrieval.sh -r <regId> -c <accountId>  # Add account
$ get-a2a-credential-retrieval.sh -r <regId>                  # List accounts
$ get-a2a-apikey.sh -r <regId> -c <accountId>                 # Get API key
$ reset-a2a-apikey.sh -r <regId> -c <accountId>               # Regenerate key

# Retrieve credentials using cert auth
$ echo "" | get-a2a-password.sh -a <appliance> -c cert.pem -k key.pem -A <apiKey> -p -r
$ echo "" | get-a2a-privatekey.sh -a <appliance> -c cert.pem -k key.pem -A <apiKey> -p
```

### Bidirectional A2A (Set Credentials)

```Bash
$ echo "" | set-a2a-password.sh -a <appliance> -c cert.pem -k key.pem \
    -A <apiKey> -p <<< "NewPassword1!"
$ echo "" | set-a2a-privatekey.sh -a <appliance> -c cert.pem -k key.pem \
    -A <apiKey> -K keyfile.pem -p
```

### Access Request Brokering

A2A registrations can be configured to broker access requests on behalf of
other users:

```Bash
$ set-a2a-access-request-broker.sh -i <regId> \
    -b '{"Users": [{"UserId": 45}]}'                        # Configure broker
$ get-a2a-access-request-broker.sh -i <regId>                # Get broker config
$ echo "" | new-a2a-access-request.sh -a <appliance> -c cert.pem -k key.pem \
    -A <brokerApiKey> -b '{"ForUser":"jsmith","AssetName":"server1","AccessRequestType":"Password"}' -p
$ clear-a2a-access-request-broker.sh -i <regId>              # Remove broker
```

### Certificate Management

```Bash
$ install-trusted-certificate.sh -C cert.pem                 # Install cert
$ get-trusted-certificate.sh                                 # List all certs
$ get-trusted-certificate.sh -s <thumbprint>                 # Get by thumbprint
$ uninstall-trusted-certificate.sh -s <thumbprint>           # Remove cert
```
