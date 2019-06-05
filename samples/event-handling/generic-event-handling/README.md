Generic Event Handler Sample
============================

`generic-event-handler.sh`

This is a simple script that demonstrates how to interact with `handle-event.sh`.

When you call `handle-event.sh` the `-S` option allows you to pass in an handler
script. This script will be called every time the event with the event name you
passed to the `-E` option occurs.

In order for you to do something useful with the event, `handle-event.sh` passes
authentication context information to the handler script. The handler script can
then react to the event by sending an authenticated request (using the current
access token) to Safeguard.

For security reasons, the handler script is passed the authentication context
information over stdin. Each time the script is called for an event it can expect
to receive four lines of output.

1. Line 1 has the appliance network address
2. Line 2 has the access token currently in use.
3. Line 3 has the path to the CA bundle file to use for trusted connections
4. Line 4 has the event data JSON minified to a single line of output

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

