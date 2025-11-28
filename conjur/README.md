# Conjur setup

The goal of this setup is to describe the installation of the open source version
of Cyberark conjur and configure policies and secrets ready to be consumed [by an application](https://github.com/deathdric/spring-boot-sample-application1).

## System used and constraints.

I used Ubuntu Server 24.04.

The opensource version of conjur comes with a docker image. Actually they provide a full
docker-compose setup which includes the conjur server, a postgresql database backend, a nginx
reverse proxy, a conjur client (for interactive mode) and an initializer for the certificates used
by nginx.

I recommend to only keep docker for conjur, mostly because you don't have much choice on that matter,
but use an external postgresql database (which has the merit to have the data survive a restart),
and an external nginx instance (which is not that much harder to setup than the docker version). Same
for the client : I'll use the official binary which I can run from any host.

This setup may be harder to put in place than a 'docker-compose -d up', but it will be more convenient to use
in the long run.

## Install process

### Database setup

First, we need to create a database for conjur. We'll use postgresql for that. Fortunately, we already have
the instructions to [create and configure a database server](../postgresql/README.md).

However, regarding account privileges, conjur will need more than even the public schema owner, so we'll just 
create the database manually and grant all privileges on it (and make it owner of the public schema).
You may still create readonly accounts/roles later.

Run the following command on the database server.
```
sudo su - postgres
```
Run `psql` as `postgres` user, then the following: 

```
CREATE ROLE conjur LOGIN;
CREATE DATABASE conjur;
GRANT ALL PRIVILEGES ON DATABASE conjur TO conjur;
\c conjur
ALTER SCHEMA public OWNER TO conjur;
```

So we have created a `conjur` database and a `conjur` user and granted it all privileges (except DB ownership).
We still need to set a password for the conjur user (I'll use `hunter2` as an example but you should choose a more
complex one ;) ) :

```
ALTER ROLE conjur WITH PASSWORD 'hunter2';
```


Database should now be ready. Time to do some docker stuff ...

### Conjur server setup

**Warning** : below install procedure is not fit for production usage (docker container running as
root, conjur backend running in plain text, ...). If you're planning to run it in production you should
probably look at the enterprise version anyway.

#### Docker install

First we need to install docker (and docker-compose). Run the following on your conjur host:

```
sudo apt install docker.io docker-compose
```

Because using sudo (or worst, opening a root shell) in order to perform docker
operations will quickly become annoying, you should add your user to the `docker`
group in order to be able to run docker commands directly.

```
sudo usermod -a -G docker your_user_login
```
(replace `your_user_login` with the value of your linux login).

Next, we'll pull the docker image. Doing operations such as `docker run` will pull it
automatically anyways, but it's also a good way to check that you can run docker commands
with little impact on your setup :

```
docker pull cyberark/conjur:1.24.0
```

Note that I chose a version tag (which was the latest version by the time I wrote this)
and not `latest`. `latest` is nice for Hello-World-type projects, but in real life you
want more control (especially you want a deterministic behavior).

#### Data key generation

Next step is to generate the key which will be used for encrypting data.
You can do that by running the following command:

```
docker run --rm cyberark/conjur:1.24.0 data-key generate > data_key.txt
```

This will create an ephemeral container, generate the key and save the result to an `data_key.txt` file
(on your host, not on the container fs). You can use your favorite editor to check the key content.

The key content should be a base64-encoded data, for example : `xUA3c/sZkShioDVIFcQi3uTI6ppIeMvK674iDO4rhdc=`
(this is not the one I'm using, don't even try :) ). In any case, keep in mind that you can run the above
command as many times as you like (you can remove the standard output redirect if you want to troubleshoot).
Just make sure that you keep the key you want to use somewhere safe.

#### Conjur server install

Now we can install the server itself. Because we have to use docker, I create a [docker compose file](docker/docker-compose.yml)
which configures the server setup.

Before executing docker compose, you'll need to edit this file :
- the value of `CONJUR_DATA_KEY` should be the value of the data key you generated above.
- the value of `POSTGRES_ACCOUNT_LOGIN` should be the value of your postgresql database account login (in the sample : `conjur`)
- the value of `POSTGRES_ACCOUNT_PASSWORD` should be the value of your postgresql database account password (in the sample : `hunter2` ;) )
- the value of `POSTGRES_DB_HOST` should be the host name of your postgresql database server
- I assumed that your database was named `conjur`. Change the value if it's not the case.
- A ldap authenticator has been set up but not configured yet. If you don't want to use ldap, just set `CONJUR_AUTHENTICATORS: authn` for now.
- I mapped the container HTTP port to host port 25080 (which is less likely to be taken than 8080). If you don't like the value you can change it.

Once you're ready, run the following :
```
docker-compose up -d
```

If you want to check that conjur started sucessfully, run `docker logs conjur` (or `docker logs conjur -f`).
If you have logs like this, it's good news :

```
[11] * Listening on http://0.0.0.0:80
[11] Use Ctrl-C to stop
...
[11] - Worker 0 (PID: 14) booted in 0.01s, phase: 0
[11] - Worker 1 (PID: 16) booted in 0.01s, phase: 0
```

You can also check that it's up and running using `curl http://localhost:25080` (or use a browser for that matter)
and check that you have the conjur welcome page.

#### Nginx setup

Using a reverse proxy may sound overkill, but we'll need it at list in order to expose a TLS endpoint (an HTTPS load balancer
with proper certificates may also do the job). For convenience we'll install it on the same host as conjur (on a production setup
we would have used different hosts).

Let's install nginx :
```
sudo apt install nginx
```

Then, we'll need some configuration. First, get a certificate/private key pair for your host and make sure that the certificate
is signed by a PKI trusted by your computers (an internal one will do). In theory there is an option for force certificate
trust in the conjur command line clients, in practice in doesn't work that well, so have your certificates trusted beforehand ;)

Once you have the certificates, run the following command:
```
cd /etc/nginx
sudo mkdir tls
```
Then :
- copy your PEM encoded certificate chain (you certificate + intermediate authority + root authority) to `/etc/nginx/tls/nginx.crt`
- copy your PEM encoded private key to `/etc/nginx/tls/nginx.key`
- copy [conjur.conf](nginx/conjur.conf) to the `/etc/nginx/sites-available/` folder. **Change the `server_name` value to your host
in this config file**.
- then run the following as root :
```
cd /etc/nginx/sites-enabled
rm default
ln -s ../sites-available/conjur.conf conjur
systemctl reload nginx
```

Now your conjur instance should be reachable from port 443, try with `curl -k https://localhost`.

#### Conjur account creation and admin key setup

Now that you have a running instance of conjur, you need an account in order to perform operations. Let's create one !
Be careful that when what conjur calls `account` is more like an organization or tenant : it's not used for login.

Run the following docker command on the conjur host (in this example the created account is named `deathshadow`, feel
free to change it) :

```
docker exec conjur conjurctl account create deathshadow > admin_data.txt
```

If successful, it should output `Created new account 'deathshadow'`. It will also save the following in `admin_data.txt` (or
whatever you configured in the output redirection) :
- The public key for token signing
- The admin API key

Keep the admin API key safe and do not lose it : you're gonna need it for a while.

#### Install the conjur client

We'll use the command line client for tests and policy setup, so let's install it. You can find the binaries in the [conjur project on GitHub](https://github.com/cyberark/conjur-cli-go),
(go to the releases section and select the binary appropriate to your system. For information I used the version 9.1.0 of the command line.

Run the following command (change `https://conjur` to the URL of your conjur host and `deathshadow` to the name of the account
you created).

```
conjur init -u https://conjur -a deathshadow
```

When asking for the conjur setup, select `Open Source`.

Then login as admin (not like you have other usable logins yet) :

```
conjur login -i admin
```

When asking for the password, enter the admin api key. If successful it should display `Logged in`. 

You can now check the objects/policies you have access by executing `conjur list`. At this point you should have something like :

```
[
  "deathshadow:user:admin"
]
```

Don't worry, we'll create the policies right away !

#### Setting the root policy

Now that conjur is setup and we have an administrator account, we need to bootstrap some policies.
The first policy to create is the root policy (which all other policies will be derived from).

Root policy is defined in a [YAML file](policy/root.yml) which providers :
- An `admin` group which will be used for granting elevated privileges to some users (and stop using the `admin` account).
- An `app` policy which will server at the basis of all application-based policies, owner by the `admin` group
- LDAP-based policies and group (owner by the `admin` group:
  - A `conjur\authn-ldap` policy which will be used to configure LDAP authentication
  - An `all-ldap-users` group which will gather all conjur users who can use LDAP authentication.

In order to apply this policy, user the conjur command line client while being authenticated as `admin` :
```
conjur policy load -b root -f root.yml
```

You can now check the objects/policies you have access by executing `conjur list`. At this point you should have something like :

```
[
  "deathshadow:group:admin",
  "deathshadow:group:all-ldap-users",
  "deathshadow:policy:app",
  "deathshadow:policy:conjur",
  "deathshadow:policy:conjur/authn-ldap",
  "deathshadow:policy:root",
  "deathshadow:user:admin"
]
```

Next step is to configure LDAP authentication and add some users.

#### Configure LDAP authentication

I assume that you have setup an LDAP server following [this procedure](../ldap/README.md) and have created the same people
accounts. In order to make those accounts available on conjur, we need to :

- Create those users in conjur
- Add those users to the `all-ldap-users` group which will be user to enable LDAP authentication.

This is done using [this policy file](policy/ldap_users.yml), which will be an update of the root policy. You can apply it
using the following command :

```
conjur policy load -b root -f ldap_users.yml
```

Note that you will be able to see the api keys created for those users. You don't need to save them because they will authenticate
against LDAP soon and will be able to update their API keys.

Then, we need to configure the connectivity to the LDAP server. This should be defined in a policy which has to be a child
of the `conjur/authn-ldap` policy (this is why we created the former when setting the root policy). The policy name should
be the same as the one you configured in the [docker compose](docker/docker-compose.yml) file (minus the `conjur` part in
the path). Since the sample used `deathshadow-ldap-server` as the policy name, we will stick to it (feel free to change it).

LDAP configuration is defined in the [following policy file](policy/ldap_server_policy.yml). It has 3 main components :

- The LDAP `webservice` defining the connectivity to the LDAP server (save for the bind account password) : host, port, bind
account login, base DN, query template, ...
- Groups and privileges related to which users can call this `webservice`. It basically defines which users can authenticate
against LDAP (hence the `all-ldap-users` group created before).
- A variable which will store the password of the bind account.

In order to apply this configuration, run the following command :

```
conjur policy load -b conjur/authn-ldap -f ldap_server_policy.yml
```

There is still one more step before being able to use LDAP : setting the bind account password. For that you need to update
the created password variable (replace `changeit` with the password you setin LDAP) :
```
conjur variable set -i conjur/authn-ldap/deathshadow-ldap-server/bind-password -v changeit
```

In theory LDAP should now be ready to use. Before testing it we will configure the users who belong to the `admin` group.
The user will be Bob Spade (`userbspade`) and his ownership will be defined in [the following policy file](policy/admin_setup.yml).

To apply this ownership, run the following command :

```
conjur policy load -b root -f admin_setup.yml
```

Now we will try to connect to conjur as Bob Spade. Run `conjur logout` in order to clean your session.

Run the following command in order to be able to use LDAP authentication from the command line client :

```
conjur init -t ldap --service-id deathshadow-ldap-server -u https://conjur -a deathshadow
```

Explanation of the parameters :
- `https://conjur` is the address of your conjur server, replace the value with one you actually use.
- `deathshadow-ldap-server` is the name of your ldap policy (replace if needed)
- `deathshadow` is the name of your account (in the `organisation` sense of the name)

When requesting the Conjur installation, choose `Open Source`.

Finally, login as usrbspade using the following command :

```
conjur login -i usrbspade
```

Input the password of the userbspade account when asked. If you have the `Logged in` message, you won. Good news is :
you won't need to use the `admin` account for a while now.

If you need to use an API key for this used and you don't have it, you can reset the API key by running `conjur user rotate-api-key`.
This will create a new API key ready to use. However it will have one side effect : you will be logged out (you can still
log in afterward using your LDAP credentials).

### Application policies setup

#### Environments and groups

We will not setup the policy for our first application, called `application1`.

All application policies will have the `app` parent policy and will be owned by the `admin` group. We will later define
subpolicies owned by dev and ops users which wil allow them to set and fetch their credentials.

First, let's setup the root `application1` policy defined in [this file](policy/application1.yml). Run the following
command with the `usrbspade` user :

```
conjur policy load -b app -f application1.yml
```

The policy is currently empty, we will fill it from [another file](policy/application-template.yml) which can be applied
for any created application. It will define :

- The `dev`, `stg` and `prd` environment-based sub policies
- The `dev-owners` group, which will have ownership of `dev` credentials
- The `dev-users` group, which will have access to the `dev` credentials
- The `ops-owners` group, which will have ownership of `stg` and `prd` credentials
- The `ops-users` group, which will have access to the `stg` and `prd4` credentials
- Composite groups like `all-dev`, `all-ops` and `all-users`

Note that all groups defined above are local to the application (e.g. : the `dev-owners` group fully qualified name is
`app/application1/dev-owners`). If we create a second application, we will define different groups.

In order to update the policy, run the following :

```
conjur policy load -b app/application1 -f application-template.yml
```

Now that we have defined groups, we need to setup membership. This will be done with [this policy file](policy/application1-users.yml).
Apply it using the following command :

```
conjur policy load -b app/application1 -f application1-users.yml
```

Finally, we will define local groups for dev-based (dev) and ops-based (stg/prd) environment policies. The purpose of defining
local group is to be able to reuse the same policy templates across different applications/environments (we will use relative paths
to groups with the same name when defining ownership and permissions.

We define one [policy file for dev](policy/dev-local-groups.yml) and one [policy file for ops](policy/ops-local-groups.yml). They define :
- A group for workloads which will have read access
- A group for readers (workloads + people) which will have read access
- A group for owners which will have read/write access

`readers` and `owners` groups will contain groups defined in the parent policy file.

You can apply those by running the following :

```
conjur policy load -b app/application1/dev -f dev-local-groups.yml
conjur policy load -b app/application1/stg -f ops-local-groups.yml
conjur policy load -b app/application1/prd -f ops-local-groups.yml
```

Your ACL setup is complete for application1 and you no longer need to run commands as Bob Spade (the administrator).
Next step will be to add credentials.

#### Adding credentials

To be continued ...
