#!/bin/bash

CSV_FILE=$1

generate_password() {
    slappasswd -s "$1"
}

add_user() {
    local uid=$1
    local firstName=$2
    local lastName=$3
    local password=$4
    local email=$5
    local teamName=$6
    local profession=$7

    local ldif=$(cat <<EOF
dn: uid=$uid,ou=people,ou=users,$LDAP_BASE
objectClass: inetOrgPerson
uid: $uid
sn: $lastName
givenName: $firstName
cn: $firstName $lastName
displayName: $firstName $lastName
userPassword: $(generate_password "$password")
mail: $email
ou: $teamName
title: $profession
EOF
    )

    echo "$ldif" | ldapadd -x -D "$LDAP_ADMIN" -w "$LDAP_PASSWORD"
}

# Bulk import users
import_users() {
    while IFS=, read -r uid firstName lastName password email teamName profession; do
        if [[ "$uid" != "uid" ]]; then
            echo "Adding user: $uid"
            add_user "$uid" "$firstName" "$lastName" "$password" "$email" "$teamName" "$profession"
        fi
    done < ${CSV_FILE}
}


# Main execution
import_users


echo "Bulk import completed."