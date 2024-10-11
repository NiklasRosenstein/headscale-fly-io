<p align="center">
  <img src=".github/assets/headscale-on-fly.jpg">
</p>

# Headscale on Fly.io

This repository builds a Docker image that can be run as an app on [Fly.io] to create an easy, robust and affordable
deployment of [Headscale] (an open source implementation of the [Tailscale] control plane, allowing you to create your
self-hosted virtual private network using Tailscale clients). It uses [Litestream] to replicate and restore the SQlite
database from an S3 bucket (such as [Tigris] bucket integrated with your Fly.io app).

  [Fly.io]: https://fly.io
  [Headscale]: https://github.com/juanfont/headscale
  [Litestream]: https://litestream.io/
  [Tailscale]: https://tailscale.com/
  [Tigris]: https://fly.io/docs/tigris/

__Contents__

<!-- toc -->
* [Prerequisites](#prerequisites)
* [Cost](#cost)
* [Usage](#usage)
* [Admitting machines to the network](#admitting-machines-to-the-network)
* [Updates](#updates)
* [Advanced configuration and usage](#advanced-configuration-and-usage)
  * [Configuring OIDC](#configuring-oidc)
  * [Using a custom domain](#using-a-custom-domain)
  * [Highly available Headscale deployment](#highly-available-headscale-deployment)
  * [Metrics](#metrics)
  * [Environment variables](#environment-variables)
  * [Migrating to Headscale on Fly.io](#migrating-to-headscale-on-flyio)
  * [Migrating from Postgres](#migrating-from-postgres)
* [Development](#development)
<!-- end toc -->

## Prerequisites

* An account on [Fly.io]
* The [fly](https://github.com/superfly/flyctl) CLI
* The [age](https://github.com/FiloSottile/age) CLI

## Cost

The default configuration is to use the cheapested VM size available, `shared-cpu-1x`, which will cost you approx.
1.94 USD/mo (not including miniscule cost for the object storage). This sizing should be sufficient to support tens
if not up to 100 nodes in your VPN.

## Usage

1. Take the [`fly.example.toml`](./fly.example.toml) as a starting point and update at least the application name and
region. The application name must be globally unique and will be used as the domain name of your Headscale control
plane server (e.g. `https://<app>.fly.dev`). (Read more in the [Advanced configuration](#advanced-configuration) if
you want to configure a custom domain).

2. Run `fly apps create <app>` (using the same app name you've set in `fly.toml`).

3. Run `fly storage create -a <app> -n <app>` to create an S3 object storage bucket that will contain the replication
of the Headscale SQlite database.

4. Run `fly secrets set NOISE_PRIVATE_KEY="privkey:$(openssl rand -hex 32)"` to generate the Noise private key
for your Headscale server (this is a parameter for the secure communication between devices and the control plane).
Note that if you change this secret, devices need to re-authenticate with the Headscale server.

5. Generate an age keypair for encrypting your Litestream SQlite database replication in S3 by running

    ```
    $ age-keygen -o age.privkey 2>&1 | awk '{print $3}' > age.pubkey
    $ fly secrets set AGE_SECRET_KEY="$(tail -n1 age.privkey)"
    $ rm age.{privkey,pubkey}
    ```

5. Run `fly deploy --ha=false` to deploy the application. Note that `fly deploy` is sufficient on subsequent runs
as Fly will not scale up the application using this command except for the initial deployment, where high-availability
is the default.

> __Important__: You should not run your Fly application with more than one machine unless you have followed the
> advanced section on [Highly available Headscale deployment](#highly-available-headscale-deployment). If you didn't use
> the `--ha=false` option on initial deploy, run `fly scale count 1` to ensure that Headscale is only deployed to one
> machine.

## Admitting machines to the network

On a device, run

    $ tailscale up --login-server https://<app>.fly.dev

Following the link that will be displayed in the console will give you the `headscale` command to run to register
the device. You may need to create a user first with the `headscale user create` command.

Shell into your Headscale deployment using

    $ fly ssh console

Note that you can set up OIDC to automatically admit new devices to the VPN if a user successfully authenticates.

## Updates

You should use an immutable tag in your `fly.toml` configuration file's `[build.image]` parameter. Using a mutable tag,
such as `:main` (pointing to the latest version of the `main` branch of this repository), does not guarantee that your
deployment comes up with the latest image version as a prior version may be cached.

Simply run `fly deploy` after updating the `[build.image]`. Note that there will be a brief downtime unless you configured a highly available deployment.

## Advanced configuration and usage

### Configuring OIDC

To enable OIDC, you must at the minimum provide the following environment variables:

* `HEADSCALE_OIDC_ISSUER`
* `HEADSCALE_OIDC_CLIENT_ID`
* `HEADSCALE_OIDC_CLIENT_SECRET`

Please make sure that you pass the client secret using `fly secrets set` instead of via the `[[env]]` section of
your `fly.toml` configuration file.

### Using a custom domain

1. Create a CNAME entry for your Fly.io application
2. Run `fly certs add <custom_domain>`

See also the related documentation on [Fly.io: Custom domains](https://fly.io/docs/networking/custom-domain/).

### Highly available Headscale deployment

TODO (Using LitefS)

### Metrics

Metrics are automatically available through Fly.io's built-in managed Prometheus metrics collection and Grafana
dashboard. Simply click on "Metrics" in your Fly.io account and explore `headscale_*` metrics.

### Environment variables

Many Headscale configuration options can be set vie the `[env]` section in your `fly.toml` configuration file. The
following is a complete list of the environment variables the Headscale-on-Fly.io recognizes, including those that
are expected to be set automatically.

| Variable                                         | Default                           | Description                                                                                                                                                                                                                                                                                                   |
|--------------------------------------------------|-----------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `AWS_ACCESS_KEY_ID`                              | (automatic)                       | Access key for the object storage for Litestream SQlite replication. Usually set automatically by Fly.io when enabling the Tigris integration.                                                                                                                                                                |
| `AWS_SECRET_ACCESS_KEY`                          | (automatic)                       | Secret key for the object storage.                                                                                                                                                                                                                                                                            |
| `AWS_REGION`                                     | (automatic)                       |                                                                                                                                                                                                                                                                                                               |
| `AWS_ENDPOINT_URL_S3`                            | (automatic)                       |                                                                                                                                                                                                                                                                                                               |
| `BUCKET_NAME`                                    | (automatic)                       |                                                                                                                                                                                                                                                                                                               |
| `FLY_APP_NAME`                                   | (automatic)                       | Used to determine the Headscale server URL, if `HEADSCALE_SERVER_URL` is not set.                                                                                                                                                                                                                             |
| `HEADSCALE_SERVER_URL`                           | `https://${FLY_APP_NAME}.fly.dev` | URL of the Headscale server.                                                                                                                                                                                                                                                                                  |
| `HEADSCALE_DNS_BASE_DOMAIN`                      | `tailnet`                         | Base domain for members in the Tailnet. This **must not** be a part of the `HEADSCALE_SERVER_URL`.                                                                                                                                                                                                            |
| `HEADSCALE_LOG_LEVEL`                            | `info`                            | Log level for the Headscale server.                                                                                                                                                                                                                                                                           |
| `HEADSCALE_PREFIXES_V4`                          | `100.64.0.0/10`                   | Prefix for IP-v4 addresses of nodes in the Tailnet.                                                                                                                                                                                                                                                           |
| `HEADSCALE_PREFIXES_V6`                          | `fd7a:115c:a1e0::/48`             | Prefix for IP-v6 addresses of nodes in the Tailnet.                                                                                                                                                                                                                                                           |
| `HEADSCALE_PREFIXES_ALLOCATION`                  | `random`                          | How IPs are allocated to nodes joining the Tailnet. Can be `random` or `sequential`.                                                                                                                                                                                                                          |
| `HEADSCALE_OIDC_ISSUER`                          | n/a                               | If set, enables OIDC configuration. Must be set to the URL of the OIDC issuer. For example, if you use Keycloak, it might look something like `https://mykeycloak.com/realms/main`                                                                                                                            |
| `HEADSCALE_OIDC_CLIENT_ID`                       | n/a, but required                 | The OIDC client ID.                                                                                                                                                                                                                                                                                           |
| `HEADSCALE_OIDC_CLIENT_SECRET`                   | n/a, but required                 | The OIDC client secret. **Important:** Configure this through `fly secrets set`.                                                                                                                                                                                                                              |
| `HEADSCALE_OIDC_SCOPES`                          | `openid, profile, email`          | A comma-separated list of OpenID scopes. (The comma-separated list must be valid YAML if placed inside `[ ... ]`.)                                                                                                                                                                                            |
| `HEADSCALE_OIDC_ALLOWED_GROUPS`                  | n/a                               | A comma-separated list of groups to permit. Note that this requires your OIDC client to be configured with a groups claim mapping. In some cases you may need to prefix the group name with a slash (e.g. `/headscale`). (The comma-separated list must be valid YAML if placed inside `[ ... ]`.)            |
| `HEADSCALE_OIDC_ALLOWED_DOMAINS`                 | n/a                               | A comma-separated list of email domains to permit. (The comma-separated list must be valid YAML if placed inside `[ ... ]`.)                                                                                                                                                                                  |
| `HEADSCALE_OIDC_ALLOWED_USERS`                   | n/a                               | A comma-separated list of users to permit. (The comma-separated list must be valid YAML if placed inside `[ ... ]`.)                                                                                                                                                                                          |
| `HEADSCALE_OIDC_STRIP_EMAIL_DOMAIN`              | `true`                            | Whether to strip the email domain for the Headscale user names.                                                                                                                                                                                                                                               |
| `HEADSCALE_OIDC_EXPIRY`                          | `180d`                            | The amount of time from a node is authenticated with OpenID until it expires and needs to reauthenticate. Setting the value to "0" will mean no expiry.                                                                                                                                                       |
| `HEADSCALE_OIDC_USE_EXPIRY_FROM_TOKEN`           | `true`                            | Use the expiry from the token received from OpenID when the user logged in, this will typically lead to frequent need to reauthenticate and should only been enabled if you know what you are doing. If enabled, `HEADSCALE_OIDC_EXPIRY` is ignored.                                                          |
| `HEADSCALE_OIDC_ONLY_START_IF_OIDC_IS_AVAILABLE` | `true`                            | Fail startup if the OIDC server cannot be reached.                                                                                                                                                                                                                                                            |
| `LITESTREAM_ENABLED`                             | `true`                            | Whether to restore and replicate the SQlite database with Litestream. You likely never want to turn this option off, as you will loose your SQlite database on restarts.                                                                                                                                      |
| `LITESTREAM_RETENTION`                           | `24h`                             | Configure the Litestream retention period. Retention is enforced periodically and can be changed with `LITESTREAM_RETENTION_CHECK_INTERVAL`.                                                                                                                                                                  |
| `LITESTREAM_RETENTION_CHECK_INTERVAL`            | `1h`                              | The interval at which retention should be applied.                                                                                                                                                                                                                                                            |
| `LITESTREAM_VALIDATION_INTERVAL`                 | `12h`                             | The interval at which Litestream does a separate restore of the database and validates the result vs. the current database.                                                                                                                                                                                   |
| `IMPORT_DATABASE`                                | `false`                           | If set to `true`, the entrypoint will check for an `import-db.sqlite` file in the S3 bucket to restore, and use that instead of `litestream restore` if it exists. Note that the file will not be removed, so you should disable this option and remove the file from the bucket once the import is complete. |
| `ENTRYPOINT_DEBUG`                               | n/a                               | If set to `true`, enables logging of executed commands in the container entrypoint and prints out the Headscale configuration before startup. Use with caution, as it might reveal secret values to stdout (and thus into Fly.io's logging infrastructure).                                                   |
| `NOISE_PRIVATE_KEY`                              | n/a, but required                 | Noise private key for Headscale. Generate with `echo privkey:$(openssl rand -hex 32)`. **Important:** Pass this value securely with `fly secrets set`.                                                                                                                                                        |
| `AGE_SECRET_KEY`                                 | n/a, but required                 | [age] Secret key for encryption your Litestream SQLite replication.                                                                                                                                                                                                                                           |

### Migrating to Headscale on Fly.io

To migrate your existing Headscale instance that uses SQlite to Fly.io, you must upload the database to the S3 bucket
under a file named `import-db.sqlite` and temporarily set the `IMPORT_DATABASE=true` environment variable. This will
instruct the application to load this database file instead of attempting a Litestream restore on startup. Once done
and Litestream has finished replicating this database state to S3, you must remove the `IMPORT_DATABASE` environment
variable and re-deploy your application, and you should also consider removing the `import-db.sqlite` file from the
S3 bucket again.

You should also make sure that you set the `NOISE_PRIVATE_KEY` secret variable to the contents of your original
Headscale instance's noise private key.

### Migrating from Postgres

> __Warning__: These steps have been tested on Headscale 0.23.0 only.

  [bigbozza/headscalebacktosqlite]: https://github.com/bigbozza/headscalebacktosqlite/tree/main

If your current Headscale deployment is using a Postgres database, you must convert it to an SQlite database before
you can migrate your instance to Headscale on Fly.io. You can leverage script provided by
[bigbozza/headscalebacktosqlite] for this, and it is more conveniently made available in this repository in
[./headscale-back-to-sqlite](./headscale-back-to-sqlite/).

First, you need to grab an empty SQlite database that was initialized by Headscale (so all the tables exist with the
right schemas). You can do this by grabbing it from an initial Fly.io deployment. If your deployment already has some
data in it because you did some prior testing, you can set the `LITESTREAM_ENABLED=false` environment variable to not
use Litestream and have Headscale start from an empty database (remember to unset this variable again once you have
retrieved the empty SQlite database).

Because Headscale is configured to use SQlite in WAL mode, we must first create a WAL checkpoint to ensure that the
database initialization is committed to the database file.

    $ fly deploy
    $ fly console ssh
    app> $ apk add sqlite
    app> $ sqlite3 /var/lib/headscale/db.sqlite
    app> sqlite3> PRAGMA wal_checkpoint(TRUNCATE);
    app> sqlite3> [Ctrl+D]
    app> $ exit
    $ fly ssh sftp get /var/lib/headscale/db.sqlite

  [UV]: https://github.com/astral-sh/uv

Change into the [./headscale-back-to-sqlite](./headscale-back-to-sqlite/) directory and use [UV] to run the script.

    $ uv run main.py \
        --pg-host db-host.example \
        --pg-port 5432 \
        --pg-db headscale \
        --pg-user headscale \
        --pg-password DBPASSWORD \
        --sqlite-out path/to/db.sqlite

> This will perform read-only operations on the Postgres database so you do not need to worry about creating a separate
> backup of your Postgres database.

  [mc]: https://min.io/docs/minio/linux/reference/minio-mc.html

If all succeeded, upload the database to the S3 bucket that Headscale on Fly.io also uses to replicate the database
to with Litestream. If you're using the Tigris object storage extension in Fly.io, you will likely need to log into
the Tigris console via the Fly.io dashboard and generate some temporary access credentials. The following example uses
the [mc] CLI to upload the file.

    $ mc alias set tigris https://fly.storage.tigris.dev <ACCESS_KEY_ID> <SECRET_ACCESS_KEY>
    $ mc cp path/to/db.sqlite tigris/<YOUR_BUCKET_NAME>/import-db.sqlite

Set the `IMPORT_DATABASE=true` environment variable and re-deploy your application.

    $ fly deploy --env IMPORT_DATABASE=true
    $ fly logs

Wait for the application to start, the database to be imported from S3 and Litestream to have replicated it to the
S3 bucket. Then re-deploy to remove the `IMPORT_DATABASE` variable.

    $ fly deploy

You should be good to go!

## Development

Simply iterating via `fly deploy` works quite well!

To update the ToC in this file, run

    $ uvx mksync -i README.md
