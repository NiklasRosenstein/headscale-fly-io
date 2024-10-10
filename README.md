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

### Metrics

Metrics are automatically available through Fly.io's built-in managed Prometheus metrics collection and Grafana
dashboard. Simply click on "Metrics" in your Fly.io account and explore `headscale_*` metrics.

### Configuring OIDC

TODO

### Using a custom domain

TODO

### Highly available Headscale deployment

TODO (Using LitefS)

## Development

Simply iterating via `fly deploy` works quite well!

To update the ToC in this file, run

    $ uvx mksync -i README.md
