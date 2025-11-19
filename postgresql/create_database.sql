\set role_base :applicationName '_' :envTrigram
\set adm_role :role_base '_adm'
\set rw_role :role_base '_rw'
\set ro_role :role_base '_ro'
\set adm_account 'svc' :applicationName 'adm' :envLetter
\set rw_account 'svc' :applicationName 'rw' :envLetter
\set ro_account 'svc' :applicationName 'ro' :envLetter

-- create the groups
CREATE ROLE :"adm_role";
CREATE ROLE :"rw_role";
CREATE ROLE :"ro_role";

-- sets the default schema for groups

ALTER ROLE :"adm_role" SET search_path = public;
ALTER ROLE :"rw_role" SET search_path = public;
ALTER ROLE :"ro_role" SET search_path = public;


-- create the accounts, note that you will have to set the passwords later

CREATE ROLE :"adm_account" LOGIN;
CREATE ROLE :"rw_account" LOGIN;
CREATE ROLE :"ro_account" LOGIN;

-- sets the default schema for users

ALTER ROLE :"adm_account" SET search_path = public;
ALTER ROLE :"rw_account" SET search_path = public;
ALTER ROLE :"ro_account" SET search_path = public;

-- grant the roles

GRANT :"adm_role" TO :"adm_account";
GRANT :"rw_role" TO :"rw_account";
GRANT :"ro_role" TO :"ro_account";

-- create the database and grant full access to user
CREATE DATABASE :"applicationName";

GRANT CONNECT ON DATABASE :"applicationName" TO :"adm_role";
GRANT CONNECT ON DATABASE :"applicationName" TO :"rw_role";
GRANT CONNECT ON DATABASE :"applicationName" TO :"ro_role";

-- further operations are database bound to you need to connect to the database

\c :"applicationName"

-- admin permissions
ALTER SCHEMA public OWNER TO :"adm_role";

-- need to switch to owner role as permissions will apply to objects created by it
SET ROLE :"adm_role";

-- read write permissions
GRANT USAGE ON SCHEMA public TO :"rw_role";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO :"rw_role";
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO :"rw_role";

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"rw_role";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO :"rw_role";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO :"rw_role";

-- read only permissions
GRANT USAGE ON SCHEMA public TO :"ro_role";
GRANT SELECT ON ALL TABLES IN SCHEMA public TO :"ro_role";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO :"ro_role";

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO :"ro_role";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO :"ro_role";

RESET role;

