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

## Usage

You can take [`fly.example.toml`](./fly.example.toml) as a starting point, make a few adjustments to it, and then
deploy your VPN control plane using the `fly deploy` command.

The default configuration is to use the cheapested VM size available, `shared-cpu-1x` and `256mb` memory, which will
cost you approx. 1.94 USD/mo (not including miniscule cost for the object storage). This sizing should be sufficient
to support tens if not up to 100 nodes in your VPN.

To admit new machines into your VPN (after they use `tailscale up --login-server https://<app>.fly.dev`), either
configure OIDC or connect to your Fly app with `fly ssh console` to run the `headscale user create` and
`headscale node register` commands.

## Advanced configuration

TODO: Metrics

TODO: OIDC

TODO: Custom domain
