#!/bin/bash

CurDir="$(pwd)"
ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

set -e

cleanup()
{
    cd "$CurDir"
    set +e
}

trap cleanup EXIT

if [ ! -z "$1" ]; then
    CaName=$1
else
    read -p "Enter CA friendly name:" CaName
    if [ -z "$CaName" ]; then
        CaName="test-ca"
    fi
fi
IntermediateCaName="issuing-$CaName"

echo -e "CA Name: $CaName\nIntermediate CA Name: $IntermediateCaName"

if [ -d "$CurDir/$CaName" ]; then
    echo "Target directory "$CurDir/$CaName" already exists!"
    read -n1 -p "Would you like to replace it? [y/n]:" Response
    >&2 echo ""
    if [[ $Response == [Yy] ]]; then
        rm -rf $CurDir/$CaName
    else
        exit 1
    fi
fi
echo -e "\nCreating the directory structure ($CurDir/$CaName) and openssl.cnf..."
mkdir $CurDir/$CaName
cd $CurDir/$CaName
mkdir -p certs crl newcerts private
chmod 700 private
touch index.txt
echo 1000 > serial_number.txt

cat <<EOF > openssl.cnf
# OpenSSL root CA configuration file.

[ ca ]
# man ca
default_ca = CA_default

[ CA_default ]
# Directory and file locations.
dir               = $(pwd)
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial_number.txt
RANDFILE          = \$dir/private/.rand

# The root key and root certificate.
private_key       = \$dir/private/$CaName.key.pem
certificate       = \$dir/certs/$CaName.cert.pem

# For certificate revocation lists.
crlnumber         = \$dir/crl_number.txt
crl               = \$dir/crl/$CaName.crl.pem
crl_extensions    = crl_ext
default_crl_days  = 30

# SHA-1 is deprecated, so use SHA-2 instead.
default_md        = sha256

name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_strict

[ policy_strict ]
# The root CA should only sign intermediate certificates that match.
# See the POLICY FORMAT section of ca manpage.
countryName             = match
stateOrProvinceName     = match
localityName            = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied

[ policy_loose ]
# Allow the intermediate CA to sign a more diverse range of certificates.
# See the POLICY FORMAT section of the ca man page.
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied

[ req ]
# Options for the req tool (man req).
default_bits        = 2048
distinguished_name  = req_distinguished_name
string_mask         = utf8only

# SHA-1 is deprecated, so use SHA-2 instead.
default_md          = sha256

# Extension to add when the -x509 option is used.
x509_extensions     = v3_ca

[ req_distinguished_name ]
# See <https://en.wikipedia.org/wiki/Certificate_signing_request>.
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name

# Optionally, specify some defaults.
countryName_default             = US
stateOrProvinceName_default     = Utah
localityName_default            = Pleasant Grove
0.organizationName_default      = One Identity LLC
organizationalUnitName_default  = PAM
commonName_default              = $CaName

[ v3_ca ]
# Extensions for a typical CA (man x509v3_config).
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ v3_intermediate_ca ]
# Extensions for a typical intermediate CA (man x509v3_config).
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ usr_cert ]
# Extensions for client certificates (man x509v3_config).
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "Generated Client Certificate from $CaName"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection

[ server_cert ]
# Extensions for server certificates (man x509v3_config).
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "Generated Server Certificate from $CaName"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[ crl_ext ]
# Extension for CRLs (man x509v3_config).
authorityKeyIdentifier=keyid:always

[ ocsp ]
# Extension for OCSP signing certificates (man ocsp).
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, OCSPSigning
EOF

echo -e "\nGenerating Root CA certificate..."
read -s -p "Specify password to protect private keys: " Pass
>&2 echo ""
openssl genrsa -aes256 -out private/$CaName.key.pem -passout file:<(echo $Pass) 4096
chmod 400 private/$CaName.key.pem
openssl req -config openssl.cnf -key private/$CaName.key.pem -new -x509 -days 3650 -sha256 \
    -extensions v3_ca -out certs/$CaName.cert.pem -passin file:<(echo $Pass)
chmod 444 certs/$CaName.cert.pem
openssl verify -CAfile certs/$CaName.cert.pem certs/$CaName.cert.pem

echo -e "\nCreating the directory structure ($CurDir/$CaName/$IntermediateCaName) and openssl.cnf..."
mkdir $CurDir/$CaName/$IntermediateCaName
cd $CurDir/$CaName/$IntermediateCaName
mkdir -p certs crl csr newcerts private
chmod 700 private
touch index.txt
echo 1000 > serial_number.txt
echo 1000 > crl_number.txt
cat <<EOF > openssl.cnf
# OpenSSL intermediate CA configuration file.

[ ca ]
# man ca
default_ca = CA_default

[ CA_default ]
# Directory and file locations.
dir               = $(pwd)
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial_number.txt
RANDFILE          = \$dir/private/.rand

# The root key and root certificate.
private_key       = \$dir/private/$IntermediateCaName.key.pem
certificate       = \$dir/certs/$IntermediateCaName.cert.pem

# For certificate revocation lists.
crlnumber         = \$dir/crl_number.txt
crl               = \$dir/crl/$IntermediateCaName.crl.pem
crl_extensions    = crl_ext
default_crl_days  = 30

# SHA-1 is deprecated, so use SHA-2 instead.
default_md        = sha256

name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_loose

[ policy_strict ]
# The root CA should only sign intermediate certificates that match.
# See the POLICY FORMAT section of man ca.
countryName             = match
stateOrProvinceName     = match
localityName            = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied

[ policy_loose ]
# Allow the intermediate CA to sign a more diverse range of certificates.
# See the POLICY FORMAT section of the ca man page.
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied

[ req ]
# Options for the req tool (man req).
default_bits        = 2048
distinguished_name  = req_distinguished_name
string_mask         = utf8only

# SHA-1 is deprecated, so use SHA-2 instead.
default_md          = sha256

# Extension to add when the -x509 option is used.
x509_extensions     = v3_ca

[ req_distinguished_name ]
# See <https://en.wikipedia.org/wiki/Certificate_signing_request>.
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name

# Optionally, specify some defaults.
countryName_default             = US
stateOrProvinceName_default     = Utah
localityName_default            = Pleasant Grove
0.organizationName_default      = One Identity LLC
organizationalUnitName_default  = PAM
commonName_default              = $IntermediateCaName

[ v3_ca ]
# Extensions for a typical CA (man x509v3_config).
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ v3_intermediate_ca ]
# Extensions for a typical intermediate CA (man x509v3_config).
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ audit_cert ]
# Extensions for audit certificate (man x509v3_config).
basicConstraints = CA:FALSE
nsComment = "Generated Audit Certificate from $IntermediateCaName"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, nonRepudiation

[ usr_cert ]
# Extensions for client certificates (man x509v3_config).
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "Generated Client Certificate from $IntermediateCaName"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection

[ server_cert ]
# Extensions for server certificates (man x509v3_config).
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "Generated Server Certificate from $IntermediateCaName"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[ crl_ext ]
# Extension for CRLs (man x509v3_config).
authorityKeyIdentifier=keyid:always

[ ocsp ]
# Extension for OCSP signing certificates (man ocsp).
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, OCSPSigning
EOF

echo -e "\nGenerating Issuing CA certificate..."
cd $CurDir/$CaName
openssl genrsa -aes256 -out $IntermediateCaName/private/$IntermediateCaName.key.pem -passout file:<(echo $Pass) 4096
chmod 400 $IntermediateCaName/private/$IntermediateCaName.key.pem
openssl req -config $IntermediateCaName/openssl.cnf -new -sha256 -key $IntermediateCaName/private/$IntermediateCaName.key.pem \
    -out $IntermediateCaName/csr/$IntermediateCaName.csr.pem -passin file:<(echo $Pass)
openssl ca -config openssl.cnf -extensions v3_intermediate_ca -days 1825 -notext -md sha256 -passin file:<(echo $Pass) \
    -in $IntermediateCaName/csr/$IntermediateCaName.csr.pem -out $IntermediateCaName/certs/$IntermediateCaName.cert.pem
chmod 444 $IntermediateCaName/certs/$IntermediateCaName.cert.pem
openssl verify -CAfile certs/$CaName.cert.pem $IntermediateCaName/certs/$IntermediateCaName.cert.pem

echo -e "\nCreating certificate chain file..."
cat $IntermediateCaName/certs/$IntermediateCaName.cert.pem  certs/$CaName.cert.pem \
    > $IntermediateCaName/certs/ca-chain.cert.pem

read -p "Would you like to copy the PEM files for root and intermediate to your current directory? [y/n]: " YN
case $YN in
    y|Y)
         cp certs/$CaName.cert.pem $IntermediateCaName/certs/$IntermediateCaName.cert.pem $CurDir
         ;;
esac
