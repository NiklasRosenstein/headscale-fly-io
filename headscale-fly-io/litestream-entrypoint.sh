#!/bin/sh
#
# requirements:
#   - litestream (optional, if LITESTREAM_ENABLED is set to true)
#   - age-keygen (optional, if AGE_PUBLIC_KEY is not set)
#   - mc (optional, if IMPORT_DATABASE is used)
#
# variables:
#   - AWS_ACCESS_KEY_ID
#   - AWS_SECRET_ACCESS_KEY
#   - AWS_REGION
#   - AWS_ENDPOINT_URL_S3
#   - BUCKET_NAME
#
#   - BUCKET_PATH
#     The path in the S3 bucket to replicate the database to.
#
#   - AGE_SECRET_KEY
#     Private key generated with the age-keygen command for encrypting the Litestream replication,
#
#   - AGE_PUBLIC_KEY [optional]
#     If set, it must be the public key matching AGE_SECRET_KEY. If not set, the age-keygen tool must be
#     available so it can be derived from the AGE_SECRET_KEY.
#
#   - LITESTREAM_DATABASE_PATH
#     The full path to the SQlite database to restore/replicate.
#
#   - LITESTREAM_ENABLED [default: true]
#     If set to false, Litestream will not restore/replicate. If your application starts from an ephemeral disk,
#     it will effectively start from nothing.
#
#   - LITESTREAM_RETENTION [default: 24h]
#   - LITESTREAM_SYNC_INTERVAL [default: 1s]
#   - LITESTREAM_RETENTION_CHECK_INTERVAL [default: 1h]
#   - LITESTREAM_VALIDATION_INTERVAL [default: 12h]
#
#   - IMPORT_DATABASE [optional]
#     If set, must be the path to an SQlite database in the S3 bucket (not a Litestream replication). It will be
#     downloaded and placed in the LITESTREAM_DATABASE_PATH instead of restoring it with Litestream on startup.
#     Replication will continue as usual. Should be unset once the import is complete.
#
# usage: litestream-entrypoint.sh <exec_command>

set -eu

#
# Utility functions
#

info() {
  >&2 echo "[$0 |  INFO]" "$@"
}

error() {
  >&2 echo "[$0 | ERROR]" "$@"
}

info_run() {
  info '$' "$@"
  "$@"
}

assert_is_set() {
  eval "val=\${$1+x}"
  if [ -z "$val" ]; then
    error "missing expected environment variable \"$1\"."
    exit 1
  fi
}

#
# This means business
#

write_config() {
  assert_is_set AWS_ACCESS_KEY_ID
  assert_is_set AWS_SECRET_ACCESS_KEY
  assert_is_set AWS_REGION
  assert_is_set AWS_ENDPOINT_URL_S3
  assert_is_set BUCKET_NAME
  assert_is_set AGE_SECRET_KEY
  assert_is_set LITESTREAM_DATABASE_PATH

  export LITESTREAM_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
  export LITESTREAM_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
  AGE_PUBLIC_KEY="$(echo "$AGE_SECRET_KEY" | age-keygen -y)"

  info "writing /etc/litestream.yml"
  cat <<EOF >/etc/litestream.yml
dbs:
- path: "${LITESTREAM_DATABASE_PATH}"
  replicas:
  # See https://litestream.io/reference/config/#s3-replica
  - type: s3
    bucket: $BUCKET_NAME
    path: headscale.db
    region: $AWS_REGION
    endpoint: $AWS_ENDPOINT_URL_S3
    # See https://litestream.io/reference/config/#replica-settings
    sync-interval: "${LITESTREAM_SYNC_INTERVAL:-10s}"
    # See https://litestream.io/reference/config/#encryption
    age:
      identities:
      - "$AGE_SECRET_KEY"
      recipients:
      - "$AGE_PUBLIC_KEY"
    # See https://litestream.io/reference/config/#retention-period
    retention: "${LITESTREAM_RETENTION:-24h}"
    retention-check-interval: "${LITESTREAM_RETENTION_CHECK_INTERVAL:-1h}"
    # https://litestream.io/reference/config/#validation-interval
    validation-interval: "${LITESTREAM_VALIDATION_INTERVAL:-12h}"
EOF
}

maybe_import_database() {
  IMPORT_DATABASE="${IMPORT_DATABASE:-}"
  if [ -z "${IMPORT_DATABASE}" ]; then
    return 1
  fi

  assert_is_set AWS_ACCESS_KEY_ID
  assert_is_set AWS_SECRET_ACCESS_KEY
  assert_is_set AWS_ENDPOINT_URL_S3

  info "configuring mc"
  mc alias set s3 "$AWS_ENDPOINT_URL_S3" "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY"

  if ! mc find "s3/$BUCKET_NAME/$IMPORT_DATABASE"; then
    error "could not find file \"$IMPORT_DATABASE\" in S3 bucket \"$BUCKET_NAME\"."
    exit 1
  fi

  info "importing database file \"$IMPORT_DATABASE\" from S3 bucket \"$BUCKET_NAME\"."
  info "remember to unset the IMPORT_DATABASE variable once the import is complete."
  mc cp "s3/$BUCKET_NAME/$IMPORT_DATABASE" "$LITESTREAM_DATABASE_PATH"
  return 0
}

main() {
  LITESTREAM_ENABLED="${LITESTREAM_ACCESS_KEY_ID:-true}"
  write_config
  if ! maybe_import_database && [ "$LITESTREAM_ENABLED" = "true" ]; then
    info_run litestream restore -if-db-not-exists -if-replica-exists -replica s3 "$LITESTREAM_DATABASE_PATH"
  fi

  if [ "${LITESTREAM_ENABLED:-true}" = "true" ]; then
    info_run exec litestream replicate -exec "$1"
  else
    # shellcheck disable=SC2086
    info_run exec $1
  fi
}

main "$@"