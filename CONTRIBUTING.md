# Contributing to safeguard-bash

Thanks for your interest in improving safeguard-bash, the Bash and cURL
scripting SDK for the One Identity Safeguard Web API.

## Reporting issues

- **Bugs and feature requests:** open a GitHub Issue.
- **Security vulnerabilities:** do **not** open a public issue — follow
  [SECURITY.md](SECURITY.md).

## Prerequisites

- `bash`, [`curl`](https://curl.se), [`jq`](https://stedolan.github.io/jq/),
  and `openssl` available on your `PATH`.
- A live Safeguard for Privileged Passwords appliance for the test suites.

## Building

The scripts are pure bash — there is no compile step. Install locally and
re-run after editing `src/` to keep `$HOME/scripts` in sync:

    ./install-local.sh
    . ~/.bash_profile   # or . ~/.profile

## Testing

The suites run against a live appliance (there are no offline unit tests):

    ./test/run-tests.sh -a <appliance> -u <user> -p <password>

Run a single suite with `-s <name>`.

## Coding conventions

No linter is configured. Follow the existing script structure —
`print_usage()` heredocs, `ScriptDir` resolution, and `getopts` handling.
See [AGENTS.md](AGENTS.md) for the full conventions.

## Submitting changes

1. Fork the repository and create a feature branch.
2. Keep commits focused with clear messages.
3. Verify the affected suites pass against a lab appliance.
4. Open a pull request describing the behavior you changed and how you
   tested it.