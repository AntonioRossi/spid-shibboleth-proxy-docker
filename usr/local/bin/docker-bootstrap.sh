#!/bin/bash

_CERTS_DIR="/opt/shibboleth-sp/certs"
_CERT_FILE="${_CERTS_DIR}/sp-cert.pem"
_KEY_FILE="${_CERTS_DIR}/sp-key.pem"

_METADATA_DIR="/opt/shibboleth-sp/metadata"

_ENTITY_ID="https://auth.example.com/sp"
_HOSTNAME="http://131.1.253.175:8080"
_SPID_ACS=${SPID_ACS:-""}

export LD_LIBRARY_PATH=/opt/shibboleth/lib64:${LD_LIBRARY_PATH}

#
# renew certificates
#
pushd /etc/shibboleth
./keygen.sh -f \
    -e ${_ENTITY_ID} \
    -h ${_HOSTNAME} \
    -o ${_CERTS_DIR}
popd

#
# generate, revise and sign metadata
#
_TMP_METADATA_1=`mktemp`
_TMP_METADATA_2=`mktemp`
_TMP_METADATA_3=`mktemp`

_ID=`cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 43 | head -n 1`

pushd /etc/shibboleth
./metagen.sh \
    -c ${_CERT_FILE} \
    -h ${_HOSTNAME} \
    -e ${_ENTITY_ID} \
    -L \
    -f urn:oasis:names:tc:SAML:2.0:nameid-format:transient \
    > ${_TMP_METADATA_1}
popd

pushd /opt/shibboleth-sp/metadata
echo $_SPID_ACS > acs.xml
xsltproc /opt/spid-metadata/transform.xsl ${_TMP_METADATA_1} > ${_TMP_METADATA_2}
sed \
    -e "s/%ID%/${_ID}/g" \
    -e "s/Shibboleth.sso/iam/g" \
    -f /opt/spid-metadata/sed.rules ${_TMP_METADATA_2} > ${_TMP_METADATA_3}
rm -f acs.xml
popd

pushd /opt/shibboleth-sp/metadata
samlsign \
    -s -k ${_KEY_FILE} -c ${_CERT_FILE} -f ${_TMP_METADATA_3} \
    -alg http://www.w3.org/2001/04/xmldsig-more#rsa-sha256 \
    -dig http://www.w3.org/2001/04/xmlenc#sha256 \
    > metadata.xml
popd

#
# killing existing shibd (if any)
#
shibd_pid=`pgrep shibd`
if [ ${shibd_pid} ]; then
    echo "Killing Shibboleth daemon (${shibd_pid})"
    kill -9 ${shibd_pid}
    rm -vf /var/run/shibboleth/*
fi

#
# run shibd
#
/usr/sbin/shibd

#
# run httpd
#
exec apachectl -DFOREGROUND
