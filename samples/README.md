Samples Using safeguard-bash
============================

Sample scripts based on safeguard-bash. These scripts are meant
to give ideas about how safeguard-bash may be used to solve
problems.

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
  run in a container.

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

  The Dockerfile in the directory also shows how to a docker image could be
  created based on safeguard-bash with additional components.
