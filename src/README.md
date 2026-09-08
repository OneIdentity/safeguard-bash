# safeguard-bash Developer Guide
Bash script development can be done many ways, this is just one way in a linux terminal.

### Requirements
* Install [jq](https://stedolan.github.io/jq/manual/), this is not mandatory, but it is not installed by default and the user experience is better if installed.

* Clone this repository

### Installation
After cloning this repository, run the `install-local.sh` script. This will copy the relevant scripts to `$HOME/scripts`, 
and add that directory to your `$PATH` environment variable. After editing any of the scripts in the src directory simply 
run `install-local.sh` and test your changes.

### TLS and HTTP behavior

SPP 9.0 enables **TLS 1.3**. The scripts force `--http1.1` on all
certificate/A2A curl calls (HTTP/2 forbids the post-handshake client-cert
exchange), and support opt-in TLS version pinning via the `SAFEGUARD_TLS_MIN` /
`SAFEGUARD_TLS_MAX` environment variables.

See the **"TLS Version and HTTP/1.1 (SPP 9.0 / TLS 1.3)"** section of the
[top-level README](../README.md) for the full behavior, the enforcement
variables, and curl-specific TLS 1.3 gotchas (backend support, minimum curl
versions, and the `--tlsv1.3` = *minimum* pitfall).

