#!/bin/bash

# LDAP Admin credentials
CSV_FILE=$1

# Function to add a user to a group
add_user_to_group() {
    local group_name=$1
    local user_id=$2
    local user_type=$3
    local user_dn=""

    # Note: workloads shouldn't have access to LDAP groups, only applicative groups.
    if [[ "$user_type" == "people" ]]; then
        user_dn="uid=$user_id,ou=people,ou=users,$LDAP_BASE"
    elif [[ "$user_type" == "bind" ]]; then
        user_dn="cn=$user_id,ou=bindaccounts,$LDAP_BASE"
    elif [[ "$user_type" == "oper" ]]; then
        user_dn="cn=$user_id,ou=operaccounts,$LDAP_BASE"
    else
        echo "Unknown user type $user_type. Skipping..."
        return 2
    fi

    # Check if the group exists
    local group_dn="cn=$group_name,ou=ldapgroups,$LDAP_BASE"
    local group_exists=$(ldapsearch -x -D "$LDAP_ADMIN" -w "$LDAP_PASSWORD" -b "$group_dn" "(objectclass=*)" | grep "numEntries: 1")

    if [[ -z "$group_exists" ]]; then
        echo "Group $group_name does not exist. Skipping..."
        return 1
    fi

    # Check if the user is already a member
    local member_exists=$(ldapsearch -x -D "$LDAP_ADMIN" -w "$LDAP_PASSWORD" -b "$group_dn" "member=$user_dn" | grep "numEntries: 1")

    if [[ -n "$member_exists" ]]; then
        echo "User $user_id is already a member of $group_name. Skipping..."
        return 0
    fi

    # Add the user to the group
    echo "Adding user $user_id to group $group_name..."
    ldapmodify -x -D "$LDAP_ADMIN" -w "$LDAP_PASSWORD" <<EOF
dn: $group_dn
changetype: modify
add: member
member: $user_dn
EOF

    if [ $? -eq 0 ]; then
        echo "Successfully added $user_uid to $group_name."
    else
        echo "Failed to add $user_uid to $group_name."
    fi
}

# Main execution
while IFS=, read -r group_name user_id user_type; do
    # Skip the header line
    if [[ "$group_name" != "group_name" ]]; then
        add_user_to_group "$group_name" "$user_id" "$user_type"
    fi
done < ${CSV_FILE}

echo "Bulk group membership update completed."
