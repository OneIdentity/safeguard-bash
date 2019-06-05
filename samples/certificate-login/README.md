Certificate Login Sample
========================

`certificate-login.sh`

This is a simple script that demonstrates how to set up a certificate user
in Safeguard for certificate authentication. The reason this sample is included
is because certificate authentication is the preferred method for authenticating
to Safeguard from an automated process.

The steps are as follows, and the script illustrates all of the steps except
PKI generation:

0. Generate a PKI that Safeguard can be configured to trust and issue a
   certificate for client authentication. This sample script uses the certificates
   that are checked in, but you could use the `new-test-ca.sh` and `new-test-cert.sh`
   scripts to create your own test PKI to experiment on your own.

1. Connect to Safeguard as a user admin using the `connect-safeguard.sh` script.
   This user must also have appliance admin permissions in order to upload
   trusted certificates. (It is easiest to use the bootstrap admin--local\Admin).

2. Upload the CA certificates from your PKI to Safeguard's TrustedCertificates
   endpoint using the `install-trusted-certificate.sh` script.

3. Create a new user in Safeguard using the Users endpoint passing values for
   the certificate identity provider and the thumbprint from the client 
   authentication certificate. In this sample, we use the `invoke-safeguard-method.sh`
   script to create the user, but this is also now possible using the 
   `new-certificate-user.sh` script.

4. Connect as the new certificate user via the `connect-safeguard.sh` script. You
   will notice that this sample hardcodes the certificate password which is NOT
   what you would do in production. The A2A events sample shows secure methods
   for dealing with passwords in automated processes.

## Docker

This sample can be run inside a Docker container.  Use `run.sh` to build an image
and run it as a container.  The `Dockerfile` in this directory has some comments
about how the image is built.  When run from a container, the default entrypoint
calls `certificate-login.sh` with no parameters.  You will be prompted for the
IP address of the target appliance, and it will use the PEM files in this directory
to set up and authenticate the certificate user.

