# AGENTS.md — AI Agent Instructions for safeguard-bash

## Project Overview

safeguard-bash is a Bash + cURL scripting SDK for the **One Identity Safeguard
for Privileged Passwords (SPP)** REST API. Each script in `src/` is a
self-contained CLI command that wraps one or more Safeguard API operations.

Scripts run standalone on any system with bash, curl, and jq, or inside an
Alpine-based Docker container.

### Reference: safeguard-ps (PowerShell SDK)

The **[OneIdentity/safeguard-ps](https://github.com/OneIdentity/safeguard-ps)**
repository is the PowerShell equivalent — significantly more mature and
feature-rich. Consult it for missing functionality, API usage patterns, and
testing strategies.

---

## Project Structure

```
safeguard-bash/
├── src/                    # CLI scripts (the SDK) — 77 scripts
│   └── utils/              # Shared libraries (loginfile.sh, a2a.sh, common.sh)
├── test/                   # Integration test framework
│   ├── run-tests.sh        # Test runner entry point
│   ├── framework.sh        # Test framework library
│   └── suites/             # Test suite scripts (suite-*.sh)
├── samples/                # Example integrations
├── pipeline-templates/     # Azure DevOps CI/CD YAML
├── build.sh / run.sh       # Docker packaging (not dev workflow)
├── install-local.sh        # Install scripts to $HOME/scripts
└── Dockerfile              # Alpine container definition
```

---

## Setup and Development Workflow

There is no build step. Scripts are pure bash.

```bash
./install-local.sh          # Install scripts to $HOME/scripts
. ~/.bash_profile           # Pick up PATH change
```

After editing scripts in `src/`, re-run `./install-local.sh` to copy changes.
There is no linter or formatter for this project.

---

## Script Conventions

### Script Template

Every script in `src/` follows this structure:

```bash
#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: script-name.sh [-h]
       script-name.sh [-a appliance] [-B cabundle] ...

  -h  Show help and exit
  -a  Network address of the appliance
  ...

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
CABundle=
CABundleArg=
Version=4

. "$ScriptDir/utils/loginfile.sh"

while getopts ":a:B:v:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    h) print_usage ;;
    esac
done
```

**Key rules:**
- `print_usage()` is always first, uses a heredoc, exits 0
- `ScriptDir` via `${BASH_SOURCE[0]}` (not `$0`) — critical for sourcing
- All variables initialized before the `getopts` loop
- Utilities sourced with `. "$ScriptDir/utils/loginfile.sh"`
- Leading `:` in getopts string suppresses built-in error messages

### Common Option Flags

| Flag | Meaning |
|------|---------|
| `-h` | Show help |
| `-a` | Appliance network address |
| `-B` | CA bundle for SSL validation |
| `-v` | API version (default: 4) |
| `-i` | Identity provider |
| `-u` | Username |
| `-c` | Client certificate file |
| `-k` | Client private key file |
| `-t` | Access token |
| `-p` | Read password from stdin |
| `-P` | Use PKCE authentication |

### Error Handling

```bash
>&2 echo "Error message"                      # Errors to stderr

if [ $? -ne 0 ]; then exit 1; fi             # Check curl exit codes

Error=$(echo $Result | jq .Code 2> /dev/null) # Detect JSON API errors
if [ -z "$Error" -o "$Error" = "null" ]; then
    echo $Result
else
    echo $Result | jq . ; exit 1
fi
```

### Login File Pattern

Scripts share auth state via `$HOME/.safeguard_login` (key=value, `umask 0077`).
The `require_login_args` function in `utils/loginfile.sh` handles the full
chain: login file → prompt → connect. Call `require_login_args` after getopts.

**Lifecycle:** `connect-safeguard.sh` creates → other scripts read via
`require_login_args` → `disconnect-safeguard.sh` invalidates and removes.

### Sourcing Shared Utilities

```bash
. "$ScriptDir/utils/loginfile.sh"
. "$ScriptDir/utils/common.sh"
. "$ScriptDir/utils/a2a.sh"
```

---

## Dependencies

`bash`, `curl`, `jq` (strongly recommended), `openssl`, `sed`, `grep`.

---

## CI/CD

Azure DevOps Pipelines (`build.yml` + `pipeline-templates/`):
- **PR validation**: builds Docker image
- **Merge to master/release-***: GitHub release + Docker Hub push

---

## Security

- Never commit secrets, tokens, or credentials
- The login file contains access tokens — don't log or serialize it
- Test credentials are passed only as CLI arguments, never hardcoded
- `-k` (disable SSL verification) is the default — don't recommend for production

---

## On-Demand Skills

The following skills contain reference material loaded only when relevant.
Read the `SKILL.md` when your current task matches the trigger.

| Skill | When to read | File |
|-------|-------------|------|
| Testing Guide | Running tests, writing tests, test failures, test setup | `.agents/skills/testing-guide/SKILL.md` |
| API Patterns | Making API calls, SCIM filters, creating users/assets, API gotchas | `.agents/skills/api-patterns/SKILL.md` |
| A2A Workflow | A2A scripts, cert auth, credential retrieval, brokering, events | `.agents/skills/a2a-workflow/SKILL.md` |
| New Script Guide | Creating a new script in src/, adding commands | `.agents/skills/new-script-guide/SKILL.md` |
