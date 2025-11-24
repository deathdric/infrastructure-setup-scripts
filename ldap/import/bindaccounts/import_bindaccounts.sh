#!/bin/bash

CSV_FILE=$1

generate_password() {
    slappasswd -s "$1"
}

add_user() {
    local cn=$1
    local description=$2
    local password=$3
    local applicationName=$4
    local environment=$5

    local ldif=$(cat <<EOF
dn: cn=$cn,ou=bindaccounts,$LDAP_BASE
objectClass: applicationProcess
objectClass: simpleSecurityObject
cn: $cn
description: $description
userPassword: $(generate_password "$password")
ou: $applicationName $environment
EOF
    )

    echo "$ldif" | ldapadd -x -D "$LDAP_ADMIN" -w "$LDAP_PASSWORD"
}

# Bulk import users
import_users() {
    while IFS=, read -r cn description password applicationName environment; do
        if [[ "$cn" != "cn" ]]; then
            echo "Adding user: $cn"
            add_user "$cn" "$description" "$password" "$applicationName" "$environment"
        fi
    done < ${CSV_FILE}
}


# Main execution
import_users


echo "Bulk import completed."