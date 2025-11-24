#!/bin/bash

CSV_FILE=$1


# Function to add a group
add_group() {
    local cn=$1
    local description=$2

    local ldif=$(cat <<EOF
dn: cn=$cn,ou=ldapgroups,$LDAP_BASE
objectClass: simpleGroup
cn: $cn
description: $description
EOF
    )

    echo "$ldif" | ldapadd -x -D "$LDAP_ADMIN" -w "$LDAP_PASSWORD"
}


# Bulk import groups
import_groups() {
    while IFS=, read -r cn description; do
        if [[ "$cn" != "cn" ]]; then
            echo "Adding group: $cn"
            add_group "$cn" "$description"
        fi
    done < ${CSV_FILE}
}

# Main execution
import_groups


echo "Bulk import completed."