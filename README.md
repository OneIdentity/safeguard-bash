# safeguard-bash
One Identity Safeguard Bash and cURL scripting resources.

## Installation
The easiest way to install safeguard-bash is via Docker; however, you can
also clone this GitHub repository and put the scripts in your path.

### Installing via Docker
This code has been compiled into a Docker image hosted on [DockerHub](https://hub.docker.com/u/oneidentity/dashboard/).
If you have Docker installed, you can simply run:

```Bash
$ docker run -it oneidentity/safeguard-ps
```

It is an extremely light-weight image, and it automatically calls the
`connect-safeguard.sh` script as the image is run.

### Installing from GitHub
After cloning this repository, simply run the `install-local.sh` script.
This will copy the relevant scripts to `$HOME/scripts`. Then, just add
that directory to your `$PATH` environment variable.

These scripts are based on bash, cURL, and jq.  cURL can function slightly
differently on different platforms, and jq is often not installed by default.
Many of the scripts will work without jq, but the user experience is much
better with jq due to the pretty output.

Just use Docker, and you won't have to worry about prerequisites!

## Getting Started
Once safeguard-bash is installed, you can begin by running `connect-safeguard.sh`.
Authentication in Safeguard is based on OAuth2 and `connect-safeguard.sh` uses 
the Resource Owner Grant of OAuth2.

```Bash
$ connect-safeguard.sh 
Appliance network address: 10.5.32.162
Identity Provider (certificate local ad2-dan.vas): local
Appliance Login: Admin
Password: 
A login file has been created.
```

The `connect-safeguard.sh` script will create a login file that includes
your access token and connection information.  This makes it easier to call
other scripts without having to retype connection information.  This login
file is created in your home directory, and can only be read by the your
user.

Client certificate authentication is also available in `connect-safeguard.sh`.

If you do not have rights to access a particular portion of the Web API,
you will be presented with an error message saying authorization is
required.

```Bash
# invoke-safeguard-method.sh -s core -m GET -U Assets
{
  "Code": 60108,
  "Message": "Authorization is required for this request.",
  "InnerError": null
}
```

When you are finished, you can call the `disconnect-safeguard.sh` script
to invalidate and remove your access token.
