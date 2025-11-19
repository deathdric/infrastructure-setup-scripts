# Postgresql setup

The goal is to setup a postgresql database server with a standard account
policy.

For now I will provide only manual setup scripts (gotta start somewhere). I'll eventually look for more
automated solutions like Ansible or Terraform.

## System used

I used Ubuntu Server 24.04. It will install Postgresql 16.

## Account policy

First, I'll assume that the server will host multiple independent databases, and
each database uses a single schema (the 'public' one). While there may be many valid
use cases for using multiple schemas in the same database, I'm not really fan of this
concept in practice as it can lead to confusing setups (e.g. misconfigurations of the
default schema to use, ...). So let's keep things simple, and really isolated ;)

For each database, the public schema ownership will belong to a role without login. Note
that it won't have the ownership of the database itself, as we want to keep privileged
operations to DBA-related roles (not covered here). This role can then be granted to one or
more login-based roles which can be used :
- By workloads for database migration scripts (flyway, liquibase, ...)
- For interactive usage if needed

Aside of the ownership role, 2 other roles will be created :
- A role with read/write access to the schema (e.g. : CRUD operations + procedure execution)
- A role with read-only access to the schema (e.g. : SELECT only)

### Naming conventions

(They will be used in scripts and in the sample applications)

Role naming is based on the following variables :
- Environment (development = `dev`/`d`, staging = `stg`/`s`, production = `prd`/`p`)
- Role (owner = `adm`, read/write = `rw`, read/only = `ro`)
- Application name

Naming convention will be : `%appname%_%envTrigram%_%role%`. For example, the readwrite role of the
`application1` database in development environment will be `application1_dev_rw`

We can use a similar convention for static workload accounts. In the samples we'll use the following
convention : `svc%appname%%role%%envLetter`. For example the default workload read/write account for
`application1` database on dev environment will be `svcapplication1rwd`.

## Server install

### Binary install

Since it's a Debian-based system, we will use good old apt tool :
```
sudo apt install postgresql
```

It will install the binaries, create the systemd `postgresql` service and create the `postgres` local
Unix account. That's nice but you still need some setup before being able to use the database server for real.

### Enabling remote connections

By default, it will only accept connections from the local host. since we're planning to install our
applications on a different host, you need to allow connections from your local network. For that you
will need to modify 2 files.

First is the `postgresql.conf` file :

```
sudo vi /etc/postgresql/16/main/postgresql.conf
```
(Note : I use `vi` personally, but any other text editor will do. Use whatever you're familiar with ;) )

You should find the following section :

```
# - Connection Settings -
#listen_addresses = 'localhost'         # what IP address(es) to listen on;
                                        # comma-separated list of addresses;
                                        # defaults to 'localhost'; use '*' for all
```

Follow what the comment says and set the following :

```
listen_addresses = '*'
```

With that, the server will listen to all network interfaces configured on the host.
You may think that it's not a good idea for a security point of view, however please take into account the following :
- Depending on how you configured your systemd service (aka lest the default configuration), postgresql may start before some network interfaces are ready.
If you have hardcoded the ip of the listen address it may not listen to the related network interface in this case until
postgres service is restarted.
- You can still customize allowed authentication methods based on the ip range (we will need to do that below).
- If you're serious about network security you should already have firewall rules put in place and segregated your hosts in different
VLANs based on purpose/constraints. If your postgresql instance is on an internet-facing host, you'll deserve what you'll get ^^

Now that remote connections are available, you'll need to allow some form of authentication which can be used by
remote hosts.

Find the `pg_hba.conf` file :

```
sudo vi /etc/postgresql/16/main/pg_hba.conf
```

You need to allow the password-based authentication (scram-sha-256) by adding the following line :

```
host    all             all             192.168.0.0/24          scram-sha-256
```

Regarding the IP range part, you'll need to adapt the value based on your network topology (it also
applies to ipv6).

Once all files are saved, time for a restart :

```
sudo systemctl restart postgresql
```

### Creating the database

Now time to create the database. I have provided a template script for its creation. See [create_database.sql](create_database.sql).

Copy this script to your database host in a folder where the `postgres` user has read access.

It needs the following parameters :
- `applicationName` : name of the application. Use alphanumeric characters only, and no spaces, and a reasonable length (<16). 
- `envTrigram`: trigram of the environment (e.g.: `dev` for development environment, `prd` for production)
- `envLetter`: letter associated to the environment (e.g.: `d` for development environment, `p` for production)

You will need to execute this script as a privileged account. For now let's use the `postgres` account. In order to do that,
run the following on the database host :

```
sudo su - postgres
```

Then go to the folder where you put `create_database.sql`

Then run the following :

```
psql -v applicationName=application1 -v envTrigram=dev -v envLetter=d -f create_database.sql
```

The database, roles and privileges should be operational, except for the workload account passwords which are not set.
I could have put them in the script but I wanted to avoid default passwords, so you'll set them manually for now.
In order to do that, execute the `psql` command as the `postgres` user, then :

```
ALTER ROLE svcapplication1admd WITH PASSWORD 'changeit';
ALTER ROLE svcapplication1rwd WITH PASSWORD 'changeit';
ALTER ROLE svcapplication1rod WITH PASSWORD 'changeit';
```
(of course replace the password values with a more complex one, and adapt the account names to the one which where created).

Now you should have as setup ready.

## Use the database

You can use [the following spring boot application](https://github.com/deathdric/spring-boot-sample-application1) as an
example of how you can use an owner account for migrations and a read-write account for CRUD operations.

What is important is that, when creating tables/..., you create them using the non-login owner role (e.g. : `application1_dev_adm`).
The reason for that is that default privileges on those objets assume that this role has the ownership. If you don't do that,
you're up to grant privileges explicitly, and trust me you don't want to do that.

Fortunately, the role can be set in the JDBC connection string, so you won't need boilerplate stuff.
If you are using a psql client in order to create your tables, execute the following command first :
```
SET ROLE application1_dev_adm;
```
(replace the role name by the one you created for your application as schema owner).

With this, further commands will be executed as this role (like for `su` in Linux or `runas` in Windows), and it will have ownership
or any objects created by those commands.

## Delete the database

I have provided a simple cleanup script [delete_database.sql](delete_database.sql) which will drop the database and associated roles
(variables to use are the same as the creation script). Note that it does not revoke grants on the created roles, so it may
fail to drop some roles if they have been granted to other users.
