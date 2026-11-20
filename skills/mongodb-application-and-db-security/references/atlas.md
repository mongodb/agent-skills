# Atlas: users, roles, and authentication

## What's different on Atlas

- Access control and TLS are always on and can't be turned off. Atlas accepts TLS 1.2 and 1.3.
  `mongodb+srv://` connection strings set `tls=true` and `authSource=admin` automatically.
- There's no `mongod.conf` and no localhost exception. The first database user is created in
  the Atlas UI, the Atlas CLI, or the Admin API.
- Manage database users and custom roles only through the Atlas UI, Atlas CLI, Admin API, or a
  supported integration such as Terraform. `db.createUser()` and `db.createRole()` aren't
  supported, and Atlas rolls back changes made any other way.
- Every Atlas CLI command below changes users, roles, or network access. Present them as steps
  for the user to run; the agent never runs them. The person running them needs Project Owner.
- **Pre-change check for every Atlas step:** the user confirms the target project ID and
  cluster name, for example with `atlas projects list` and `atlas clusters list --projectId
  <PROJECT_ID>`. Every command below passes `--projectId` explicitly, so a CLI profile pointing
  at another project can't redirect it. Database users are always scoped with `--scope`.

## Built-in roles

- **`atlasAdmin`:** `readWriteAnyDatabase` plus administrative privileges. For administrators
  only, never for applications.
- **`readWriteAnyDatabase` / `readAnyDatabase`:** broader than most applications need.
- **Specific privileges:** `read` or `readWrite` on one database or collection. `readWrite` also grants schema-changing actions (`dropCollection`, `createIndex`, `renameCollectionSameDB`). When a user asks for `readWrite`, grant it if they want it, but say this in one sentence and offer a custom role with explicit CRUD actions (`find`, `insert`, `update`, `remove` on the namespace). See `rbac-custom-roles.md`.

## Custom roles

Privileges use uppercase action names in the form `ACTION@db` or `ACTION@db.collection`.
Built-in roles can be inherited with `role@db`. The same reporting example from
`rbac-custom-roles.md`:

```bash
atlas customDbRoles create reportingReadAuditInsert --projectId <PROJECT_ID> \
  --privilege INSERT@reporting.audit_logs \
  --inheritedRole read@reporting
```

- Custom roles support a subset of the server's privilege actions. `FIND`, `INSERT`, `UPDATE`,
  and `REMOVE` are included. If an action isn't in the Atlas custom-role action list, say so;
  don't substitute a broader role.
- A user can hold up to 20 custom roles. A project has a default limit of 100 custom roles.

## Database users by mechanism

Scope each user to the clusters it needs with `--scope <CLUSTER_NAME>`. For short-lived access,
`--deleteAfter <ISO8601_UTC>` sets a deletion date up to 7 days out.

**SCRAM:**

```bash
atlas dbusers create --projectId <PROJECT_ID> --username <APP_USERNAME> \
  --role reportingReadAuditInsert --scope <CLUSTER_NAME>
```

Don't pass the password as a CLI argument. That includes `--password <value>` and command
substitution such as `--password "$(vault read ...)"`, because the expanded value still ends up
in the process's arguments. Arguments can be seen in process listings, CI and automation logs,
and shell telemetry, whether or not shell history is on. The Atlas CLI documents no other way
to pass a password, so for SCRAM users:

1. Add the database user in the Atlas UI with password authentication, and click
   **Autogenerate Secure Password**.
2. Copy the generated password straight into your secret manager.
3. In the same dialog, assign the role and restrict the user to the intended clusters.

Use the CLI command above, without `--password`, only if you've confirmed your Atlas CLI
version prompts for the password interactively. For other mechanisms (x.509, AWS IAM, OIDC,
LDAP) no password is involved.
Custom roles are passed by name alone. Built-in roles
take `roleName@db[.collection]`, for example `--role read@reporting`.

**x.509, Atlas-managed:**

```bash
atlas dbusers create --projectId <PROJECT_ID> --username <APP_USERNAME> \
  --x509Type MANAGED --role <ROLE> --scope <CLUSTER_NAME>
atlas dbusers certs create --projectId <PROJECT_ID> --username <APP_USERNAME> \
  --monthsUntilExpiration <MONTHS>
```

- `--monthsUntilExpiration` defaults to 3.
- Atlas can't revoke a certificate. To cut off access, delete the user.
- Atlas raises an alert 30 days before a user's latest certificate expires.
- Connect with `authMechanism=MONGODB-X509&tlsCertificateKeyFile=<PEM_PATH>`.

**x.509 with your own CA:**

```bash
atlas security customerCerts create --projectId <PROJECT_ID> --casFile <CA_PEM_PATH>
atlas dbusers create --projectId <PROJECT_ID> --username "<CERT_SUBJECT_DN>" \
  --x509Type CUSTOMER --role <ROLE> --scope <CLUSTER_NAME>
```

Saving the CA configuration triggers a rolling restart of the project's clusters. The username
is the certificate's RFC 2253 subject (see `x509.md`).

**AWS IAM** (Atlas only; recommended for applications running on AWS):

```bash
atlas dbusers create --projectId <PROJECT_ID> --username <IAM_ROLE_ARN> \
  --awsIAMType ROLE --role <ROLE> --scope <CLUSTER_NAME>
```

Connect with `authMechanism=MONGODB-AWS&authSource=%24external`. The driver reads AWS
credentials from the environment or from the instance or task role.

**OIDC** (M10+, 7.0.11+):

1. An Organization Owner connects the IdP in **Federation Management** and links it to the
   organization.
2. Create the database user, scoped to the clusters it needs and given a narrow role. For
   example, a workforce group for the reporting team, and one workload identity for the
   reporting service:

   ```bash
   # Workforce: members of the IdP group get read-only access to reporting on one cluster
   atlas dbusers create --projectId <PROJECT_ID> --username "<ATLAS_IDP_ID>/<IDP_GROUP_IDENTIFIER>" \
     --oidcType IDP_GROUP --role read@reporting --scope <CLUSTER_NAME>

   # Workload: one service identity with the custom role from rbac-custom-roles.md
   atlas dbusers create --projectId <PROJECT_ID> --username "<ATLAS_IDP_ID>/<IDP_USER_NAME>" \
     --oidcType USER --role reportingReadAuditInsert --scope <CLUSTER_NAME>
   ```

   Username formats:
   - Workforce group: `--oidcType IDP_GROUP --username "<ATLAS_IDP_ID>/<IDP_GROUP_IDENTIFIER>"`.
     `<ATLAS_IDP_ID>` is shown in the federation settings. The group identifier is the value
     the IdP sends in the groups claim; for Microsoft Entra ID, that's the group's Object ID,
     not its display name.
   - Workload identity: `--oidcType USER --username "<ATLAS_IDP_ID>/<IDP_USER_NAME>"`
     (`IDP_GROUP` also works for workload groups)

   `--oidcType` can't be combined with `--password`.
3. Workload identity works only through supported drivers, not mongosh or Compass.

**LDAP** (deprecated since 8.0; clusters on 7.0+, not Free or Flex):

- Configure the project with `atlas security ldap save`.
- Create users or groups with `atlas dbusers create --ldapType USER|GROUP` and the full DN as
  the username.
- Clients use `authMechanism=PLAIN&authSource=%24external`.
- One database user can't use both LDAP and SCRAM.

## Conflicts to check before recommending LDAP authorization on Atlas

- OIDC connections fail while LDAP authorization is on.
- AWS IAM principals can't be set up while LDAP authorization is on.
- Atlas-managed x.509 users can't connect while LDAP authorization is on.

## Tier limits

Free and Flex clusters support only password authentication (SCRAM-SHA-1), x.509, and AWS
IAM. Don't pin `authMechanism=SCRAM-SHA-256` on those tiers; let the driver negotiate. They also don't support private
endpoints or network peering.

## Network access

- Never recommend `0.0.0.0/0`. Atlas warns that it allows access from anywhere, and emails every
  project member when it's added.
- Add the narrowest entry that works:

  ```bash
  atlas accessLists create <IP_ADDRESS> --projectId <PROJECT_ID> --type ipAddress --comment "<WHY>"
  atlas accessLists create <CIDR_BLOCK> --projectId <PROJECT_ID> --type cidrBlock --comment "<WHY>"
  ```

  Add `--deleteAfter <ISO8601_UTC>` for temporary access.
- On dedicated clusters, private endpoints or VPC/VNet peering remove the need for public
  access-list entries.
