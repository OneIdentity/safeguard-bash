Generic Event Handler Sample
============================

## `sample-a2a-listener.sh`

This is a simple script that demonstrates how to interact with
`handle-a2a-password-event.sh`. When you call `handle-a2a-password-event.sh` you
are required to pass it a handler script that will be called each time a password
changes.

This sample is only meant to be run from a docker container.

The included handler script (`a2a-password-event-handler.sh`) just prints the
current password. In your integration you will want to do something much more
meaningful.

## `a2a-password-event-handler.sh`

As demonstrated in `sample-a2a-listener.sh`, when you call `handle-a2a-password-event.sh`
the `-S` option allows you to pass in a handler script. This script will be called
every time the password is changed. `handle-a2a-password-event.sh` does the work to
pull the new password before calling your handler script.

For security reasons, the handler script is passed the new password over stdin.
This prevents the new password from ending up in the process table as a command
line argument.

## Docker

This sample is meant to be executed from a docker container. The following video
was made from a previous version of this sample, but not much has changed. It
provides good instructions on how to use a docker container securely.

[A2A Password Listener video](https://www.youtube.com/watch?v=UQFcNgYKnTI)

[![A2A Password Listener](https://img.youtube.com/vi/UQFcNgYKnTI/0.jpg)](https://www.youtube.com/watch?v=UQFcNgYKnTI)

To run the container use the `run.sh` script in this directory. The `-v` option
allows you to specify a directory with a certificates and private keys to call
the A2A API. For convenience a certificate chain and an A2A client certificate
have been provided in this directory. Run `setup.sh` an A2A user and A2A
registration in Safeguard. `setup.sh` will also create a bogus asset and account
with a bogus password.

## Running This Sample

Follow these steps:

1. Run `setup.sh` and provide the bootstrap admin credential (local\admin). This
   will set everything up for you. Please note the A2A API key that is displayed.
2. Run `run.sh` to build and run the container. It will exit by saying that you
   have not provided the right environment variables.
3. Re-run `run.sh` with the following command line (including the A2A API key from
   step 1).

   ```bash
   $ ./run.sh -v $(pwd)/certs --env-file <(cat <<EOF
   SG_APPLIANCE=<Safeguard address here>
   SG_CERTFILE=A2AUser.cert.pem
   SG_KEYFILE=A2AUser.key.pem
   SG_APIKEY=<ApiKey printed out by setup.sh>
   SG_KEYFILE_PASSWORD=test
   EOF
   )
   ```

   Also, if you want to use a DNS name, insert `--dns <your DNS server>` between
   `-v $(pwd)/certs` and `--env-file`.

4. Open the Safeguard UI and change the password for the safeguard-bash-asset\a2a
   account.
5. You can change the password multiple times.
6. You can unplug the network or reboot Safeguard and the script will re-connect
   as necessary.

