#!/bin/sh

set -eu

#
# Utility functions
#

info() {
  >&2 echo "[$0 |  INFO]:" "$@"
}

error() {
  >&2 echo "[$0 | ERROR]:" "$@"
}

info_run() {
  info "$@"
  "$@"
}

assert_is_set() {
  eval "val=\${$1+x}"
  if [ -z "$val" ]; then
    error "missing expected environment variable \"$1\""
    exit 1
  fi
}

maybe_idle() {
  if [ "${ENTRYPOINT_IDLE:-false}" = "true" ]; then
    info "ENTRYPOINT_IDLE=true, entering idle state"
    sleep infinity
  fi
}

on_error() {
  [ $? -eq 0 ] && exit
  error "an unexpected error occurred."
  maybe_idle
}

trap 'on_error' EXIT

#
# Business logic
#

write_noise_private_key() {
  # This file must be configured through a secret and mounted via the fly.toml configuration.
  assert_is_set NOISE_PRIVATE_KEY
  NOISE_PRIVATE_KEY_FILE=/var/lib/headscale/noise_private.key
  info "writing $NOISE_PRIVATE_KEY_FILE"
  echo "$NOISE_PRIVATE_KEY" > /$NOISE_PRIVATE_KEY_FILE
}

write_config() {
  HEADSCALE_CONFIG_PATH=/etc/headscale/config.yaml

  # The HEADSCALE_SERVER_URL variable was removed.
  if [ -n "${HEADSCALE_SERVER_URL:-}" ]; then
    error "HEADSCALE_SERVER_URL is no longer supported, set HEADSCALE_DOMAIN_NAME instead"
    exit 1
  fi

  # Set default values for configuration variables for use with envsubst.
  export HEADSCALE_DOMAIN_NAME="${HEADSCALE_DOMAIN_NAME:-${FLY_APP_NAME}.fly.dev}"
  export HEADSCALE_DNS_BASE_DOMAIN="${HEADSCALE_DNS_BASE_DOMAIN:-tailnet}"
  export HEADSCALE_DNS_MAGIC_DNS="${HEADSCALE_DNS_MAGIC_DNS:-true}"
  export HEADSCALE_DNS_NAMESERVERS_GLOBAL="${HEADSCALE_DNS_NAMESERVERS_GLOBAL:-1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001}"
  export HEADSCALE_DNS_SEARCH_DOMAINS="${HEADSCALE_DNS_SEARCH_DOMAINS:-}"
  export HEADSCALE_LOG_LEVEL="${HEADSCALE_LOG_LEVEL:-info}"
  export HEADSCALE_PREFIXES_V4="${HEADSCALE_PREFIXES_V4:-100.64.0.0/10}"
  export HEADSCALE_PREFIXES_V6="${HEADSCALE_PREFIXES_V6:-fd7a:115c:a1e0::/48}"
  export HEADSCALE_PREFIXES_ALLOCATION="${HEADSCALE_PREFIXES_ALLOCATION:-random}"
  export HEADSCALE_EPHEMERAL_NODE_INACTIVITY_TIMEOUT="${HEADSCALE_EPHEMERAL_NODE_INACTIVITY_TIMEOUT:-30m}"

  # Generate the Headscale configuration file by substituting environment variables.
  info "writing $HEADSCALE_CONFIG_PATH"
  # shellcheck disable=SC3060
  envsubst < "${HEADSCALE_CONFIG_PATH/.yaml/.template.yaml}" > $HEADSCALE_CONFIG_PATH

  # Append OIDC configuration if enabled.
  if [ -n "${HEADSCALE_OIDC_ISSUER:-}" ]; then
    assert_is_set HEADSCALE_OIDC_CLIENT_ID
    assert_is_set HEADSCALE_OIDC_CLIENT_SECRET
    export HEADSCALE_OIDC_SCOPES="${HEADSCALE_OIDC_SCOPES:-openid, profile, email}"
    export HEADSCALE_OIDC_STRIP_EMAIL_DOMAIN="${HEADSCALE_OIDC_STRIP_EMAIL_DOMAIN:-true}"
    export HEADSCALE_OIDC_EXPIRY="${HEADSCALE_OIDC_EXPIRY:-180d}"
    export HEADSCALE_OIDC_USE_EXPIRY_FROM_TOKEN="${HEADSCALE_OIDC_USE_EXPIRY_FROM_TOKEN:-false}"
    export HEADSCALE_OIDC_ONLY_START_IF_OIDC_IS_AVAILABLE="${HEADSCALE_OIDC_ONLY_START_IF_OIDC_IS_AVAILABLE:-true}"
    info "generating OIDC appendix for $HEADSCALE_CONFIG_PATH"
    # shellcheck disable=SC3060
    envsubst < "${HEADSCALE_CONFIG_PATH/.yaml/-oidc.template.yaml}" >> $HEADSCALE_CONFIG_PATH
  fi
}

main() {
  write_noise_private_key
  write_config
  maybe_idle
  export BUCKET_PATH="headscale.db"
  export LITESTREAM_DATABASE_PATH=/var/lib/headscale/db.sqlite
  info_run exec /etc/headscale/litestream-entrypoint.sh "headscale serve"
}

main "$@"