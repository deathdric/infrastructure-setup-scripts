# LDAP setup

**WORK IN PROGRESS !**

The goal of this setup is to have a simple ldap server which can be used for users
and workloads authentication.

We will use this server as the golden source identity provider for other tools.

It's manual scripts for now, sorry ...

## System used

I used Ubuntu Server 24.04. LDAP server will be openldap (slapd).

## Organization hierarchy

The root organization name in this setup will be `deathshadow.org`, which translates in ldap terms to
`dc=deathshadow,dc=org`.

It will then have the following hierarchy :

```
dc=deathshadow,dc=org
|
|- ou=users
|   |- ou=people
|   |   |- uid=usrldeathdric
|   |- ou=workloads
|   |   |- uid=svcapplication1d
|- ou=bindaccounts
|   |- cn=bndapplication1d   
|- ou=operaccounts
|   |- cn=oprcustominfra
|- ou=groups
|   |- ou=application1
|        |- cn=application1_users
|- ou=ldapgroups
   |- cn=ldap_admins
   |- cn=ldap_bind_accounts
```

Let me explain why I organized the accounts the following way.

There are 3 main use cases when interacting with the ldap server:

- Use the account credentials for LDAP-based authentication to other services, this is what the `users`
organizational unit is for. This organizational unit is split in two groups gathering the personal accounts (`ou=people`)
and the workload service accounts (`ou=workloads`) respectively.
- Use the account for credential binding (the server-side part of LDAP-based authentication) and user/group search.
Those accounts belong to the `ou=bindaccounts` organizational unit.
- Use the account for privileged (i.e. : non-readonly) operations on LDAP when using a personal account is not feasible
  (e.g. scripting, or monitored privileged access management). Those accounts belong to the `ou=operaccounts` organizational unit.

With this organization, the user DN to setup when performing an LDAP bind will be : `ou=users,dc=deathshadow,dc=org`,
which will look only for personal accounts and workload accounts.

For groups, we separated the groups used for LDAP management `ou=groups` and the groups used for applications `ou=ldapgroups`.

## Installation and setup

### Server install

To install the binary, use the good old `apt` command :

```
sudo apt install slapd
```

During the installation, it will prompt for the password of the `admin` account.
Enter a password (choose wisely), then enter it again for confirmation.

Then, run the following command :
```
sudo dpkg-reconfigure slapd
```

- Answer `no` on the first question (skip configuration)
- It will ask for your domain name. In this sample I used `deathshadow.org`. You can either settle
for that or choose one which fits you better :)
- It will then ask for the name of your entity. I entered `Deathshadow Inc`. Put whatever you like.
- 2 next prompts are the administrator password. Unless you changed your mind, put the same values as
the one you chose during the installation.
- Answer `no` when asking for database deletion on package removal
- Answer `yes` when asking for moving the old database files

Now you should have your organization created. In order to check that everything is working, run
the following command, and input the admin password when requested :
```
ldapsearch -x -H ldap://localhost -D "cn=admin,dc=deathshadow,dc=org" -W -b "dc=deathshadow,dc=org" "(objectClass=organization)"
```
(note: replace `dc=deathshadow,dc=org` with the values you set in your domain name).

You should have an output like this :
```
# extended LDIF
#
# LDAPv3
# base <dc=deathshadow,dc=org> with scope subtree
# filter: (objectClass=organization)
# requesting: ALL
#

# deathshadow.org
dn: dc=deathshadow,dc=org
objectClass: top
objectClass: dcObject
objectClass: organization
o: Deathshadow Inc
dc: deathshadow

# search result
search: 2
result: 0 Success

# numResponses: 2
# numEntries: 1
```

### Configuration

** Important ** Further scripts and files will assume that you ldap root is `dc=deathdhadow,dc=org`.
If you have customized this values (well, you should anyways), do not forget to replace them with the ones you
set. It would be too cumbersome to remind that each time, so this is the last time I'll say it.

First, we need to setup the organization hierarchy.
The [base.ldif](base.ldif) file provides the organization units described earlier.
Run the following command in the ldap server :
```
ldapadd -x -H ldap://localhost -D cn=admin,dc=deathshadow,dc=org -W -f base.ldif
```

It should create those entries. You can look for them using the following command (here for `users`) :
```
ldapsearch -x -H ldap://localhost -D "cn=admin,dc=deathshadow,dc=org" -W -b "dc=deathshadow,dc=org" "(&(objectClass=organizationalUnit)(ou=users))"
```

### Importing accounts

Let's setup a bunch of accounts in order to test different user profiles. Because creating ldif files by hand is bit
of a PITA, we'll use import scripts in order to create them in bulk.

Before running the import scripts, you'll need to set the 3 following environment variables :
- `LDAP_BASE` : the ldap root organization (e.g. : `dc=deathshadow,dc=org`).
- `LDAP_ADMIN` : the fully qualified name of your administrator account (e.g.: `cn=admin,dc=deathshadow,dc=org`)
- `LDAP_PASSWORD` : the password of your administrator account

Import scripts basically reads a CSV file containing account information and tries to create the account in LDAP.
For now they are not idempotent (won't update an existing user).

All scripts and CSV files are in the [import](import) folder.

**Warning** : account passwords have been hardcoded to `changeit` in the import files. No need to tell that
you should update the values to more complex ones :)

#### People accounts

The [people import file](import/people/people.csv) contains data about physical persons (ok, they do not exist really ...) having
different profiles :

* An infrastructure admin user, which I will grant privileged operations on several systems later.
* 2 developers of the application 'Application1', one junior and one senior
* 2 application production members, one junior and one senior

**Disclaimer** : the people in that list are purely fictional.

I may add more users later depending on the profiles I need.

It is read by the [people import script](import/people/import_people.sh).

In order to create the users, run the following :
```
chmod +x import_people.sh
./import_people.sh people.csv
```
Then you can check the existence of a user with the following command (here for Bob Spade) :

```
ldapsearch -x -H ldap://localhost -D "cn=admin,dc=deathshadow,dc=org" -W -b "ou=users,dc=deathshadow,dc=org" "(&(objectClass=person)(uid=usrbspade))"
```

#### Workload accounts

The [workload import file](import/workloads/workloads.csv) contains data about service accounts which can be
authenticated against LDAP. It is read by the [workloads import script](import/workloads/import_workloads.sh).

Here I defined one account per environment and per application.

In order to create the users, run the following :
```
chmod +x import_workloads.sh
./import_workloads.sh workloads.csv
```
Then you can check the existence of a user with the following command (here for application1 dev account) :

```
ldapsearch -x -H ldap://localhost -D "cn=admin,dc=deathshadow,dc=org" -W -b "ou=users,dc=deathshadow,dc=org" "(&(objectClass=person)(uid=svcapplication1d))"
```

#### Bind accounts

The [bind accounts import file](import/bindaccounts/bindaccounts.csv) contains data about technical accounts which may be use
to query LDAP. It is read by the [bind accounts import script](import/bindaccounts/import_bindaccounts.sh).

Here I defined one account per environment and per application. While the cardinality is similar to workload accounts, note
that an application may have only a workload account without a bind account, and vice versa.

In order to create the users, run the following :
```
chmod +x import_bindaccounts.sh
./import_bindaccounts.sh bindaccounts.csv
```
Then you can check the existence of a user with the following command (here for application1 dev account) :

```
ldapsearch -x -H ldap://localhost -D "cn=admin,dc=deathshadow,dc=org" -W -b "ou=bindaccounts,dc=deathshadow,dc=org" "(cn=bndapplication1d)"
```

#### Operator accounts

I will add a script later once I provide different use cases for operator accounts. Script should be similar to the
one for adding bind accounts, except for the parent organizational unit.

### Groups

Unfortunately, no builtin group type was really suitable (some requires at least one member, others like `posixGroup` have unneeded mandatory attributes).
As a consequence, I registered my own group schema called `simpleGroup` using [the following schema](schemas/simpleGroup.ldif).

In order to create the type, run the following command (**do not try to use the standard admin account for this, it won't work**) :

```
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f simpleGroup.ldif
```

#### LDAP groups

For now, we'll create 2 groups : an administrators group and a group used for bind accounts.
Both accounts are provided in the [import file](import/ldapgroups/ldapgroups.csv) which is used in [a dedicated script](import/ldapgroups/import_ldapgroups.sh).

In order to create the groups, run the following :
```
chmod +x import_ldapgroups.sh
./import_ldapgroups.sh ldapgroups.csv
```

Now that we have some groups, let's add members. Members of those groups can be either people (LDAP operators), bind accounts
or operator accounts. Workload accounts shouldn't belong to those groups because they are meant to be used by business applications.

The following [import file](import/ldapgroups/membership/ldapgroupmembership.csv) associates existing bind accounts to the
associated group, and the Bob Spade account to the administrator group. Import is done using a [provided script](import/ldapgroups/membership/import_ldapgroupmembership.sh).
Unlike for user/group creation, this script is idempotent.

In order to apply group membership, run the following :
```
chmod +x import_ldapgroupmembership.sh
./import_ldapgroupmembership.sh ldapgroupmembership.csv
```

You can search for a group (which will also display its members) by using the following command :

```
ldapsearch -x -H ldap://localhost -D "cn=admin,dc=deathshadow,dc=org" -W -b "ou=ldapgroups,dc=deathshadow,dc=org" "(&(objectClass=simpleGroup)(cn=ldap_bind_accounts))"
```

#### Applicative groups

Applicative groups will be added once use cases will be needed.

### ACLs

TODO ;)

