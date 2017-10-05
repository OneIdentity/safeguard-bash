# Samples Using safeguard-bash
Sample scripts based on safeguard-bash.  These scripts are meant
to give ideas about how safeguard-bash may be used to solve
problems.

## Sample Scripts
- **certificate-login.sh**

  Demonstrate how to set up certificate login by adding the certificate
  trust and creating a certificate user. Then, call connect-safeguard.sh
  with the appropriate parameters.

- **import-assets-from-tpam**

  This script demonstrates how to use an API key from TPAM to do a simplistic
  import of TPAM systems into Safeguard as new assets. This script makes use
  of the batch endpoint.

  The Dockerfile in the directory also shows how to create a docker image
  based on safeguard-bash with additional components.
