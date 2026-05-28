Samples Using safeguard-bash
============================

Sample scripts based on safeguard-bash. These scripts are meant
to give ideas about how safeguard-bash may be used to solve
problems.

## Security Notes

The samples in this directory are written for **developer and CI
convenience**, not for production deployment. In particular:

- None of them pass `-B <ca-bundle>` to `connect-safeguard.sh` or
  `invoke-safeguard-method.sh`. Without that flag the underlying
  `curl` and `openssl s_client` invocations fall back to `-k`
  (skip TLS verification), which is appropriate for the self-signed
  certificates that lab and test appliances ship with by default.
- The `-k` fallback is **not safe for production**. A network
  attacker between the runner and the appliance can inject a forged
  certificate, intercept the bearer token, and impersonate the
  caller.
- Before re-using one of these samples against a production
  appliance you must (a) obtain the trusted CA bundle for that
  appliance (see `get-trusted-ca-bundle.sh`), (b) export it as the
  `CABundle` environment variable, and (c) pass `-B "$CABundle"` to
  every SDK script invocation in the sample.

See the project root `README.md` section "TLS Verification" for the
full recipe, including a `curl` / `openssl s_client` workflow for
extracting the certificate from an appliance.

## Sample Scripts
- **[certificate-login](certificate-login)**

  Demonstrate how to set up certificate login by adding the certificate
  trust and creating a certificate user. Then, call connect-safeguard.sh
  with the appropriate parameters.

- **[event-handling](event-handling)**

  Demonstrate how to handle events using safeguard-bash. Safeguard will
  send events to connected clients via SignalR as they occur. There are
  events for all object creation, modification, deletion. There are also
  events for password automation and access request workflow.

  Both of the samples below include a Dockerfile and demonstrate how to
  run in a container, but you probably want to read about [event-handling](event-handling)
  before reading through the samples.

  - **[a2a-event-handling](event-handling/a2a-event-handling)**

    Sample scripts for A2A events. A2A events are password changes, and the
    A2A handler will immediately pull the password and call another script
    with the new password.

  - **[generic-event-handling](event-handling/generic-event-handling)**

    Sample script for generic events.

- **[import-assets-from-tpam](import-assets-from-tpam)**

  Demonstrate how to use an API key from TPAM to do a simplistic import
  of TPAM systems into Safeguard as new assets. This script makes use
  of the batch endpoint.

  The Dockerfile in the directory also shows how a docker image could be
  created based on safeguard-bash with additional components.
