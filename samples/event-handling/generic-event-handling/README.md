Generic Event Handler Sample
============================

## `sample-event-listener.sh`

This is a simple script that demonstrates how to interact with `handle-event.sh`.
When you call `handle-event.sh` you are required to pass it a handler script that
will be called each time the event occurs. A generic handler script is provided
in this sample and is described below.

A simple way to see this sample in action is to run `sample-event-listener.sh`
from this directory:

```bash
$ ./sample-event-listener.sh -E UserUpdated
```

Then, log into Safeguard via the UI and change the description of a user.

The output will look like this:

```json
{
  "DirectoryId": null,
  "DirectoryName": null,
  "DomainName": null,
  "UserId": 30,
  "UserIdentityProviderId": -1,
  "UserIdentityProviderName": "Local",
  "UserName": "BlueAutomation",
  "UserPrimaryAuthenticationIdentity": "70E45112BC03447AD96DCDA019C34E3F82BDCB35",
  "UserPrimaryAuthenticationProviderId": -2,
  "UserPrimaryAuthenticationProviderName": "Certificate",
  "EventName": "UserUpdated",
  "EventDescription": "A user has been updated",
  "EventTimestamp": "2019-06-18T17:08:52.4472318Z",
  "ApplianceId": "18B1694CF1C0",
  "EventUserId": 29,
  "EventUserDisplayName": "Guber Admin",
  "EventUserDomainName": null
}
```

`UserId` is the ID of the user that was updated.  `EventUserId` is the ID of the
user that made the change. Some basic information is included in the event itself
but the `UserId` can be used to pull the full information about the user that
recently changed.

Different types of events have different information. Sometimes the information
included in the event itself will be sufficient for what you are trying to do.
Other times you will want to query Safeguard in the event handler script for more
information before reacting to the event.

## `generic-event-handler.sh`

As demonstrated in `sample-event-listener.sh`, when you call `handle-event.sh`
the `-S` option allows you to pass in a handler script. This script will be called
every time the event with the name you passed to the `-E` option occurs.

In order for you to do something useful with the event, `handle-event.sh` passes
the current authentication context information to the handler script. This allows
your handler script to call back to Safeguard if necessary to react to the event.
The handler script can make an authenticated request to Safeguard using the
current access token.

For security reasons, the handler script is passed the authentication context
information over stdin. This prevents the access token from ending up in the
process table as a command line argument. Each time the script is called for an
event it can expect to receive four lines of output.

- Line 1 has the appliance network address
- Line 2 has the access token currently in use.
- Line 3 has the path to the CA bundle file to use for trusted connections
- Line 4 has the event data JSON minified to a single line of output

The `generic-event-handler.sh` shows how to parse this data from stdin without
causing a potential hang via the bash read builtin.

When calling `invoke-safeguard-method.sh` from the handler script, the best
practice is to use the `-T` option to hide the access token from the process
table.

For example:

```bash
invoke-safeguard-method.sh -a $Appliance -B $CABundle -T ... <<<$AccessToken
```

Where, the `...` is replaced with whatever command you would like to send.

Your handler script may call Safeguard as many times as is necessary to
accomplish whatever you'd like to do to react to the event.

