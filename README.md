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
* [Usage](#usage)
* [Cost](#cost)
* [Admitting machines to the network](#admitting-machines-to-the-network)
* [Updates](#updates)
* [Advanced configuration and usage](#advanced-configuration-and-usage)
  * [Metrics](#metrics)
  * [Environment variables](#environment-variables)
  * [Configuring OIDC](#configuring-oidc)
  * [Using a custom domain](#using-a-custom-domain)
  * [Highly available Headscale deployment](#highly-available-headscale-deployment)
* [Development](#development)
<!-- end toc -->

## Prerequisites

* An account on [Fly.io]
* The [fly](https://github.com/superfly/flyctl) CLI

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

5. Run `fly deploy --ha=false` to deploy the application. Note that `fly deploy` is sufficient on subsequent runs
as Fly will not scale up the application using this command except for the initial deployment, where high-availability
is the default.

__Important__: You should not run your Fly application with more than one machine unless you have followed the
advanced section on [Configuring OIDC](#configuring-oidc). If you didn't use the `--ha=false` option on initial deploy,
run `fly scale count 1` to ensure that Headscale is only deployed to one machine.

## Cost

The default configuration is to use the cheapested VM size available, `shared-cpu-1x` and `256mb` memory, which will
cost you approx. 1.94 USD/mo (not including miniscule cost for the object storage). This sizing should be sufficient
to support tens if not up to 100 nodes in your VPN.

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

TODO

### Highly available Headscale deployment

TODO (Using LitefS)

### Metrics

Metrics are automatically available through Fly.io's built-in managed Prometheus metrics collection and Grafana
dashboard. Simply click on "Metrics" in your Fly.io account and explore `headscale_*` metrics.

### Environment variables

Many Headscale configuration options can be set vie the `[env]` section in your `fly.toml` configuration file. The
following is a complete list of the environment variables the Headscale-on-Fly.io recognizes, including those that
are expected to be set automatically.

| Variable                                         | Default                           | Description                                                                                                                                                                                                                                                                                        |
|--------------------------------------------------|-----------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `AWS_ACCESS_KEY_ID`                              | (automatic)                       | Access key for the object storage for Litestream SQlite replication. Usually set automatically by Fly.io when enabling the Tigris integration.                                                                                                                                                     |
| `AWS_SECRET_ACCESS_KEY`                          | (automatic)                       | Secret key for the object storage.                                                                                                                                                                                                                                                                 |
| `AWS_REGION`                                     | (automatic)                       |                                                                                                                                                                                                                                                                                                    |
| `AWS_ENDPOINT_URL_S3`                            | (automatic)                       |                                                                                                                                                                                                                                                                                                    |
| `BUCKET_NAME`                                    | (automatic)                       |                                                                                                                                                                                                                                                                                                    |
| `FLY_APP_NAME`                                   | (automatic)                       | Used to determine the Headscale server URL, if `HEADSCALE_SERVER_URL` is not set.                                                                                                                                                                                                                  |
| `HEADSCALE_SERVER_URL`                           | `https://${FLY_APP_NAME}.fly.dev` | URL of the Headscale server.                                                                                                                                                                                                                                                                       |
| `HEADSCALE_DNS_BASE_DOMAIN`                      | `tailnet`                         | Base domain for members in the Tailnet. This **must not** be a part of the `HEADSCALE_SERVER_URL`.                                                                                                                                                                                                 |
| `HEADSCALE_LOG_LEVEL`                            | `info`                            | Log level for the Headscale server.                                                                                                                                                                                                                                                                |
| `HEADSCALE_PREFIXES_V4`                          | `100.64.0.0/10`                   | Prefix for IP-v4 addresses of nodes in the Tailnet.                                                                                                                                                                                                                                                |
| `HEADSCALE_PREFIXES_V6`                          | `fd7a:115c:a1e0::/48`             | Prefix for IP-v6 addresses of nodes in the Tailnet.                                                                                                                                                                                                                                                |
| `HEADSCALE_PREFIXES_ALLOCATION`                  | `random`                          | How IPs are allocated to nodes joining the Tailnet. Can be `random` or `sequential`.                                                                                                                                                                                                               |
| `HEADSCALE_OIDC_ISSUER`                          | n/a                               | If set, enables OIDC configuration. Must be set to the URL of the OIDC issuer. For example, if you use Keycloak, it might look something like `https://mykeycloak.com/realms/main`                                                                                                                 |
| `HEADSCALE_OIDC_CLIENT_ID`                       | n/a, but required                 | The OIDC client ID.                                                                                                                                                                                                                                                                                |
| `HEADSCALE_OIDC_CLIENT_SECRET`                   | n/a, but required                 | The OIDC client secret. **Important:** Configure this through `fly secrets set`.                                                                                                                                                                                                                   |
| `HEADSCALE_OIDC_SCOPES`                          | `openid, profile, email`          | A comma-separated list of OpenID scopes. (The comma-separated list must be valid YAML if placed inside `[ ... ]`.)                                                                                                                                                                                 |
| `HEADSCALE_OIDC_ALLOWED_GROUPS`                  | n/a                               | A comma-separated list of groups to permit. Note that this requires your OIDC client to be configured with a groups claim mapping. In some cases you may need to prefix the group name with a slash (e.g. `/headscale`). (The comma-separated list must be valid YAML if placed inside `[ ... ]`.) |
| `HEADSCALE_OIDC_ALLOWED_DOMAINS`                 | n/a                               | A comma-separated list of email domains to permit. (The comma-separated list must be valid YAML if placed inside `[ ... ]`.)                                                                                                                                                                       |
| `HEADSCALE_OIDC_ALLOWED_USERS`                   | n/a                               | A comma-separated list of users to permit. (The comma-separated list must be valid YAML if placed inside `[ ... ]`.)                                                                                                                                                                               |
| `HEADSCALE_OIDC_STRIP_EMAIL_DOMAIN`              | `true`                            | Whether to strip the email domain for the Headscale user names.                                                                                                                                                                                                                                    |
| `HEADSCALE_OIDC_EXPIRY`                          | `180d`                            | The amount of time from a node is authenticated with OpenID until it expires and needs to reauthenticate. Setting the value to "0" will mean no expiry.                                                                                                                                            |
| `HEADSCALE_OIDC_USE_EXPIRY_FROM_TOKEN`           | `true`                            | Use the expiry from the token received from OpenID when the user logged in, this will typically lead to frequent need to reauthenticate and should only been enabled if you know what you are doing. If enabled, `HEADSCALE_OIDC_EXPIRY` is ignored.                                               |
| `HEADSCALE_OIDC_ONLY_START_IF_OIDC_IS_AVAILABLE` | `true`                            | Fail startup if the OIDC server cannot be reached.                                                                                                                                                                                                                                                 |
| `NOISE_PRIVATE_KEY`                              | n/a, but required                 | Noise private key for Headscale. Generate with `echo privkey:$(openssl rand -hex 32)`. **Important:** Pass this value securely with `fly secrets set`.                                                                                                                                             |
| `ENTRYPOINT_DEBUG`                               | n/a                               | If set to `true`, enables logging of executed commands in the container entrypoint and prints out the Headscale configuration before startup. Use with caution, as it might reveal secret values to stdout (and thus into Fly.io's logging infrastructure).                                        |

## Development

Simply iterating via `fly deploy` works quite well!

To update the ToC in this file, run

    $ uvx mksync -i README.md
