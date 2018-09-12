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

for dir in $(find $CurDir -type d); do 
    if [ -d "$dir/certs" -a -d "$dir/issuing-$(basename $dir)" ]; then 
        CaName=$(basename $dir)
        break
    fi
done
if [ -z "$CaName" ]; then
    >&2 echo "Unable to locate the CA subdirectory in this directory!"
    read -p "Enter CA Friendly Name:" CaName
fi

IntermediateCaName="issuing-$(basename $CaName)"

print_usage()
{
    cat <<EOF
USAGE: new-test-cert.sh [-h]
       new-test-cert.sh [client|server]

This script is meant to be run after running new-test-ca.sh.  It should be
run from the same directory where new-test-ca.sh created your test CA.
EOF
    exit 1
}

if [ ! -d "$CurDir/$CaName" ]; then
    >&2 echo "Failed to find root CA!"
    print_usage
fi
if [ ! -d "$CurDir/$CaName/$IntermediateCaName" ]; then
    >&2 echo "Failed to find intermediate CA!"
    print_usage
fi

echo -e "Using intermediate CA found at $CurDir/$CaName/$IntermediateCaName\n"

Type=
Name=
Pass=
CaPass=
SubjAltNames=

if [ ! -z "$1" ]; then
    if [ "$1" = "-h" ]; then
        print_usage
    fi
    Type=$(echo "$1" | tr '[:upper:]' '[:lower:]')
fi
if [ -z "$Type" ]; then
    read -p "Certificate Type [client/server]:" Type
fi
case $Type in
    client|server) ;;
    *) echo "Must specify type of either client or server!"; print_usage ;;
esac

read -p "Friendly Name:" Name
if [ -z "$Name" ]; then
    echo "Must specify a name!"
    exit 1
fi

echo -e "OPTIONAL: Subject Alternative Names\n  <Just enter an empty string for none>"
if [ "$Type" = "client" ]; then
    echo -e "  Ex. 'email:me@foo.baz,URI:http://my.url.here/\n"
else
    echo -e "  Ex. 'DNS:srv.domain.com,DNS:*.foo.baz,IP:1.2.3.4'\n"
fi
read -p "Enter all SANs, comma-delimited:" SubjAltNames

read -s -p "Specify password to protect private key:" Pass

cd $CurDir/$CaName

echo -e "\nGenerating key..."
openssl genrsa -aes256 -out $IntermediateCaName/private/$Name.key.pem -passout file:<(echo $Pass) 2048
chmod 400 $IntermediateCaName/private/$Name.key.pem

echo -e "\nCreating CSR..."
if [ -z "$SubjAltNames" ]; then
    openssl req -config <(sed -e "s<= $IntermediateCaName<= $Name<g" $IntermediateCaName/openssl.cnf) \
        -key $IntermediateCaName/private/$Name.key.pem \
        -new -sha256 -out $IntermediateCaName/csr/$Name.csr.pem -passin file:<(echo $Pass)
else 
    openssl req -reqexts reqexts -config <(sed -e "s<= $IntermediateCaName<= $Name<g" \
            -e "s<\[ req \]<[ reqexts ]\nsubjectAltName=$SubjAltNames\n\n[ req ]<g" $IntermediateCaName/openssl.cnf) \
        -key $IntermediateCaName/private/$Name.key.pem \
        -new -sha256 -out $IntermediateCaName/csr/$Name.csr.pem -passin file:<(echo $Pass)
fi

echo -e "\nSigning CSR..."
read -s -p "$IntermediateCaName private key password:" CaPass
case $Type in
    client)
        if [ -z "$SubjAltNames" ]; then
            openssl ca -extensions usr_cert -config $IntermediateCaName/openssl.cnf -days 730 -notext -md sha256 \
                -in $IntermediateCaName/csr/$Name.csr.pem -out $IntermediateCaName/certs/$Name.cert.pem -passin file:<(echo $CaPass)
        else
            openssl ca -extensions usr_cert -config <(sed -e "s<\[ usr_cert \]<[ usr_cert ]\nsubjectAltName=$SubjAltNames\n<g" \
                    $IntermediateCaName/openssl.cnf) -days 730 -notext -md sha256 \
                -in $IntermediateCaName/csr/$Name.csr.pem -out $IntermediateCaName/certs/$Name.cert.pem -passin file:<(echo $CaPass)
        fi
        ;;
    server)
        if [ -z "$SubjAltNames" ]; then
            openssl ca -extensions usr_cert -config $IntermediateCaName/openssl.cnf -days 730 -notext -md sha256 \
                -in $IntermediateCaName/csr/$Name.csr.pem -out $IntermediateCaName/certs/$Name.cert.pem -passin file:<(echo $CaPass)
        else
            openssl ca -extensions server_cert -config <( sed -e "s<\[ server_cert \]<[ server_cert ]\nsubjectAltName=$SubjAltNames\n<g" \
                    $IntermediateCaName/openssl.cnf) -days 730 -notext -md sha256 \
                -in $IntermediateCaName/csr/$Name.csr.pem -out $IntermediateCaName/certs/$Name.cert.pem -passin file:<(echo $CaPass)
        fi
        ;;
esac
chmod 444 $IntermediateCaName/certs/$Name.cert.pem
openssl verify -CAfile $IntermediateCaName/certs/ca-chain.cert.pem $IntermediateCaName/certs/$Name.cert.pem

echo -e "\nCreating PKCS12 (PFX) file..."
openssl pkcs12 -export -inkey $IntermediateCaName/private/$Name.key.pem -in $IntermediateCaName/certs/$Name.cert.pem -out $IntermediateCaName/private/$Name.p12
echo -e "\n"

read -p "Would you like to copy the PEM files and PKCS12 file to your current directory? [y/n]: " YN
case $YN in
    y|Y)
         cp $IntermediateCaName/private/$Name.key.pem $IntermediateCaName/certs/$Name.cert.pem $IntermediateCaName/private/$Name.p12 $CurDir
         ;;
esac

