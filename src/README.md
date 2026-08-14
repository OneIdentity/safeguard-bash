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

Safeguard for Privileged Passwords (SPP) 9.0 enables **TLS 1.3**. These scripts
work against 9.0 with no extra configuration; libcurl/OpenSSL negotiates the
protocol automatically.

**HTTP/1.1 for certificate authentication.** Client-certificate authentication
(the RSTS certificate grant used by `connect-safeguard.sh -i certificate`, and
all A2A credential-retrieval and A2A event calls) requires HTTP/1.1. HTTP/2
forbids the post-handshake certificate exchange these flows rely on, so the
scripts force `--http1.1` on every certificate/A2A `curl` call whenever the
installed curl supports it (curl >= 7.33). Requests that authenticate with a
bearer access token are unaffected and continue to use the negotiated HTTP
version.

**Optional TLS version enforcement.** By default the TLS version is negotiated
(including TLS 1.3). To pin the allowed range, export either of these
environment variables before running any script; both are opt-in and accept
`1.0`, `1.1`, `1.2`, or `1.3`:

| Variable | Effect | curl flag |
|----------|--------|-----------|
| `SAFEGUARD_TLS_MIN` | Minimum acceptable TLS version (floor) | `--tlsvX.Y` |
| `SAFEGUARD_TLS_MAX` | Maximum acceptable TLS version (ceiling) | `--tls-max X.Y` |

Examples:

```bash
# Require TLS 1.3 (reject anything lower)
export SAFEGUARD_TLS_MIN=1.3

# Pin to exactly TLS 1.3
export SAFEGUARD_TLS_MIN=1.3
export SAFEGUARD_TLS_MAX=1.3

# Allow TLS 1.2 or 1.3 only
export SAFEGUARD_TLS_MIN=1.2
export SAFEGUARD_TLS_MAX=1.3
```

Notes:
* `SAFEGUARD_TLS_MAX` requires curl >= 7.54 (`--tls-max`); on older curl it is
  ignored with a warning.
* An invalid value causes the script to exit with an error before connecting.
* When the `openssl s_client` fallback is used (the `-O` option, for platforms
  where curl's TLS backend mishandles client certificates), the same min/max is
  applied on a best-effort basis via `-min_protocol` / `-max_protocol`.

