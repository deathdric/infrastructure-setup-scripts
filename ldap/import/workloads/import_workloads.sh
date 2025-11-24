#!/bin/bash

CSV_FILE=$1

generate_password() {
    slappasswd -s "$1"
}

add_user() {
    local uid=$1
    local description=$2
    local password=$3
    local email=$4
    local applicationName=$5
    local environment=$6

    local ldif=$(cat <<EOF
dn: uid=$uid,ou=workloads,ou=users,$LDAP_BASE
objectClass: inetOrgPerson
uid: $uid
sn: $uid
givenName: Service Account
cn: $uid
displayName: $description
userPassword: $(generate_password "$password")
mail: $email
ou: $applicationName Service Account
title: $applicationName $environment Account
EOF
    )

    echo "$ldif" | ldapadd -x -D "$LDAP_ADMIN" -w "$LDAP_PASSWORD"
}

# Bulk import users
import_users() {
    while IFS=, read -r uid description password email applicationName environment; do
        if [[ "$uid" != "uid" ]]; then
            echo "Adding user: $uid"
            add_user "$uid" "$description" "$password" "$email" "$applicationName" "$environment"
        fi
    done < ${CSV_FILE}
}


# Main execution
import_users


echo "Bulk import completed."