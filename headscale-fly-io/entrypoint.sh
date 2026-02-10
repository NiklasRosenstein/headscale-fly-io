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
    export HEADSCALE_OIDC_EXPIRY="${HEADSCALE_OIDC_EXPIRY:-180d}"
    export HEADSCALE_OIDC_USE_EXPIRY_FROM_TOKEN="${HEADSCALE_OIDC_USE_EXPIRY_FROM_TOKEN:-false}"
    export HEADSCALE_OIDC_ONLY_START_IF_OIDC_IS_AVAILABLE="${HEADSCALE_OIDC_ONLY_START_IF_OIDC_IS_AVAILABLE:-true}"
    # Export HEADSCALE_OIDC_ALLOWED_USERS_YAML with the value of: HEADSCALE_OIDC_ALLOWED_USERS_FLY if exists, or try HEADSCALE_OIDC_ALLOWED_USERS otherwise.
    if [ -n "${HEADSCALE_OIDC_ALLOWED_USERS_FLY:-}" ]; then
      export HEADSCALE_OIDC_ALLOWED_USERS_YAML="${HEADSCALE_OIDC_ALLOWED_USERS_FLY}"
    else
      export HEADSCALE_OIDC_ALLOWED_USERS_YAML="${HEADSCALE_OIDC_ALLOWED_USERS:-}"
    fi
    info "generating OIDC appendix for $HEADSCALE_CONFIG_PATH"
    # shellcheck disable=SC3060
    envsubst < "${HEADSCALE_CONFIG_PATH/.yaml/-oidc.template.yaml}" >> $HEADSCALE_CONFIG_PATH
  fi
}

write_headplane_config() {
  HEADPLANE_CONFIG_PATH=/etc/headscale/config-headplane.yaml

  # Generate a cookie secret if not provided (must be exactly 32 characters)
  if [ -z "${HEADPLANE_COOKIE_SECRET:-}" ]; then
    info "generating random HEADPLANE_COOKIE_SECRET"
    export HEADPLANE_COOKIE_SECRET=$(head -c 16 /dev/urandom | od -A n -t x1 | tr -d ' \n')
  fi

  # Set default values for headplane configuration (envsubst doesn't support :- syntax)
  export HEADPLANE_PROC_ENABLED="${HEADPLANE_PROC_ENABLED:-true}"
  
  # Set the base URL for Headplane (needed for OIDC callback URLs)
  # Use HEADPLANE_BASE_URL if set, otherwise construct from HEADSCALE_DOMAIN_NAME
  if [ -z "${HEADPLANE_BASE_URL:-}" ]; then
    export HEADPLANE_BASE_URL="https://${HEADSCALE_DOMAIN_NAME}"
  fi

  # Generate OIDC configuration if enabled
  if [ -n "${HEADPLANE_OIDC_ISSUER:-}" ]; then
    info "enabling OIDC configuration for Headplane"
    assert_is_set HEADPLANE_OIDC_CLIENT_ID
    assert_is_set HEADPLANE_OIDC_CLIENT_SECRET
    assert_is_set HEADPLANE_OIDC_HEADSCALE_API_KEY
    
    export HEADPLANE_OIDC_SCOPE="${HEADPLANE_OIDC_SCOPE:-openid email profile}"
    export HEADPLANE_OIDC_USE_PKCE="${HEADPLANE_OIDC_USE_PKCE:-true}"
    export HEADPLANE_OIDC_DISABLE_API_KEY_LOGIN="${HEADPLANE_OIDC_DISABLE_API_KEY_LOGIN:-false}"
    export HEADPLANE_OIDC_TOKEN_ENDPOINT_AUTH_METHOD="${HEADPLANE_OIDC_TOKEN_ENDPOINT_AUTH_METHOD:-client_secret_basic}"
    
    export HEADPLANE_OIDC_CONFIG="oidc:
  issuer: ${HEADPLANE_OIDC_ISSUER}
  client_id: ${HEADPLANE_OIDC_CLIENT_ID}
  client_secret: ${HEADPLANE_OIDC_CLIENT_SECRET}
  headscale_api_key: ${HEADPLANE_OIDC_HEADSCALE_API_KEY}
  scope: ${HEADPLANE_OIDC_SCOPE}
  use_pkce: ${HEADPLANE_OIDC_USE_PKCE}
  disable_api_key_login: ${HEADPLANE_OIDC_DISABLE_API_KEY_LOGIN}
  token_endpoint_auth_method: ${HEADPLANE_OIDC_TOKEN_ENDPOINT_AUTH_METHOD}"
  else
    export HEADPLANE_OIDC_CONFIG="# oidc: not configured"
  fi

  # Generate the Headplane configuration file by substituting environment variables.
  info "writing $HEADPLANE_CONFIG_PATH"
  # shellcheck disable=SC3060
  envsubst < "${HEADPLANE_CONFIG_PATH/.yaml/.template.yaml}" > $HEADPLANE_CONFIG_PATH
}

write_litestream_append_config() {
  LITESTREAM_ENABLED="${LITESTREAM_ENABLED:-true}"
  if [ "$LITESTREAM_ENABLED" != "true" ]; then
    info "LITESTREAM_ENABLED=false, skipping Litestream append config"
    return
  fi

  if [ "${HEADPLANE_ENABLED:-false}" != "true" ]; then
    return
  fi

  assert_is_set AWS_ACCESS_KEY_ID
  assert_is_set AWS_SECRET_ACCESS_KEY
  assert_is_set AWS_REGION
  assert_is_set AWS_ENDPOINT_URL_S3
  assert_is_set BUCKET_NAME
  assert_is_set AGE_SECRET_KEY

  if [ -z "${AGE_PUBLIC_KEY:-}" ]; then
    info "deriving AGE_PUBLIC_KEY"
    AGE_PUBLIC_KEY="$(echo "$AGE_SECRET_KEY" | age-keygen -y)"
    export AGE_PUBLIC_KEY
  fi

  # Export Litestream config variables with defaults for envsubst
  export LITESTREAM_SYNC_INTERVAL="${LITESTREAM_SYNC_INTERVAL:-10s}"
  export LITESTREAM_RETENTION="${LITESTREAM_RETENTION:-24h}"
  export LITESTREAM_RETENTION_CHECK_INTERVAL="${LITESTREAM_RETENTION_CHECK_INTERVAL:-1h}"
  export LITESTREAM_VALIDATION_INTERVAL="${LITESTREAM_VALIDATION_INTERVAL:-12h}"

  export LITESTREAM_APPEND_CONFIG_PATH=/etc/headscale/litestream-append.yml
  info "writing $LITESTREAM_APPEND_CONFIG_PATH"
  # shellcheck disable=SC3060
  envsubst < /etc/headscale/litestream-headplane.template.yaml > $LITESTREAM_APPEND_CONFIG_PATH
}

start_headplane() {
  # Only start headplane if explicitly enabled
  if [ "${HEADPLANE_ENABLED:-false}" != "true" ]; then
    info "HEADPLANE_ENABLED not set to true, skipping headplane startup"
    return
  fi

  info "starting headplane in background (logs to stdout/stderr)"
  cd /opt/headplane
  HEADPLANE_CONFIG_PATH=/etc/headscale/config-headplane.yaml NODE_PATH=/opt/headplane/node_modules node /opt/headplane/build/server/index.js 2>&1 &
  HEADPLANE_PID=$!
  info "headplane started with PID $HEADPLANE_PID"
}

start_nginx() {
  info "starting nginx reverse proxy in background"
  nginx -c /etc/headscale/nginx.conf &
  NGINX_PID=$!
  info "nginx started with PID $NGINX_PID"
}

main() {
  write_noise_private_key
  write_config
  write_headplane_config
  write_litestream_append_config
  maybe_idle
  
  # Start headplane and nginx before headscale
  start_headplane
  start_nginx
  
  export BUCKET_PATH="headscale.db"
  export LITESTREAM_DATABASE_PATH=/var/lib/headscale/db.sqlite
  info_run exec /etc/headscale/litestream-entrypoint.sh "headscale serve"
}

main "$@"