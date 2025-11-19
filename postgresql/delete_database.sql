-- Note : if you have assigned other users to the provided roles, DROP ROLE will fail.
-- TODO : provide a ROLE grant cleanup

\set role_base :applicationName '_' :envTrigram
\set adm_role :role_base '_adm'
\set rw_role :role_base '_rw'
\set ro_role :role_base '_ro'
\set adm_account 'svc' :applicationName 'adm' :envLetter
\set rw_account 'svc' :applicationName 'rw' :envLetter
\set ro_account 'svc' :applicationName 'ro' :envLetter


DROP DATABASE :"applicationName";
DROP ROLE :"adm_account";
DROP ROLE :"rw_account";
DROP ROLE :"ro_account";
DROP ROLE :"rw_role";
DROP ROLE :"ro_role";
DROP ROLE :"adm_role";

