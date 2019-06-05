Event Handling
==============

safeguard-bash includes scripts to help you deal with Safeguard events in
a bash scripting environment. safeguard-bash supports two types of events:
normal events (or just events) and A2A events. Normal events occur for just
about everything that happens in Safeguard, and any connected client that is
authenticated as a user with rights to receive a particular event will be notified
as things happen on the appliance. A2A events are specifically about detecting
password changes so that an automated client can know when it needs to retrieve
the password again. Both types of events are very useful.

safeguard-bash has four utility scripts to help with events:

- `listen-for-event.sh`

  Connects to SignalR and dumps every event received to stdout.

- `handle-event.sh`

  Uses `listen-for-event.sh` and then calls a handler script with
  the relevant event information and an authentication context that can be used to
  take action on that event. This script also contains additional logic to ensure
  that SignalR remains connected even though access tokens may time out or the
  connection may be interrupted.  In most cases, `handle-event.sh` should be used
  to build your integration project.

- `listen-for-a2a-event.sh`

  Connects to SignalR via A2A and dumps every event received to stdout.

- `handle-a2a-password-event.sh`

  Uses `listen-for-a2a-event.sh` and then for each password change event that occurs,
  it pulls the password and calls a handler script that can take action on the new
  password. This script also contains the additional logic to ensure that SignalR
  remains connected via the A2A certificate user even when the connection may have
  been interrupted. In most cases, `handle-a2a-password-event.sh` should be used
  to build your integration project for A2A password retrieval.

## Samples

- **[a2a-event-handling](event-handling/a2a-event-handling)**

  Sample scripts for A2A events. The A2A handler will immediately pull the 
  password and call another script with the new password.

- **[generic-event-handling](event-handling/generic-event-handling)**

  Generic sample script for handling normal events.

