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
