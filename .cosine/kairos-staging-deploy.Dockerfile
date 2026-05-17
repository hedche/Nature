FROM europe-west2-docker.pkg.dev/cosine-cluster-staging/keef-base/ubuntu:latest AS base
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /workspace

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    openssh-client \
    rsync \
    bash \
  && rm -rf /var/lib/apt/lists/*

RUN cat > /usr/local/bin/setup-ai-environment <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ssh_dir="${HOME}/.ssh"
ssh_key_path="${LEAFBIT_STAGING_SSH_KEY_PATH:-$ssh_dir/id_leafbit_staging}"
ssh_port="${LEAFBIT_STAGING_PORT:-22}"
env_file="${KAIROS_ENV_FILE:-/workspace/.env.staging}"

mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"

if [[ -n "${LEAFBIT_STAGING_SSH_PRIVATE_KEY_B64:-}" ]]; then
  printf '%s' "$LEAFBIT_STAGING_SSH_PRIVATE_KEY_B64" | base64 -d > "$ssh_key_path"
  chmod 600 "$ssh_key_path"
elif [[ -n "${LEAFBIT_STAGING_SSH_PRIVATE_KEY:-}" ]]; then
  printf '%s\n' "$LEAFBIT_STAGING_SSH_PRIVATE_KEY" | sed 's/\\n/\n/g' > "$ssh_key_path"
  chmod 600 "$ssh_key_path"
fi

if [[ -n "${LEAFBIT_STAGING_HOST:-}" && -n "${LEAFBIT_STAGING_USER:-}" ]]; then
  cat > "$ssh_dir/config" <<SSHCONFIG
Host leafbit-staging
  HostName ${LEAFBIT_STAGING_HOST}
  User ${LEAFBIT_STAGING_USER}
  Port ${ssh_port}
  IdentityFile ${ssh_key_path}
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  ConnectTimeout 10
SSHCONFIG
  chmod 600 "$ssh_dir/config"
else
  echo "warning: LEAFBIT_STAGING_HOST and LEAFBIT_STAGING_USER are required for the leafbit-staging SSH alias" >&2
fi

write_env_value() {
  local key="$1"
  local value="${!key-}"

  if [[ -z "$value" ]]; then
    return
  fi

  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo "error: $key contains a newline and cannot be written to $env_file" >&2
    exit 1
  fi

  printf '%s=%s\n' "$key" "$value" >> "$env_file"
}

if [[ "${AI_ENV_WRITE_STAGING_ENV:-true}" == "true" ]]; then
  umask 077
  : > "$env_file"

  for key in \
    ACME_EMAIL \
    API_DOMAIN \
    POSTGRES_USER \
    POSTGRES_PASSWORD \
    POSTGRES_DB \
    REDIS_PASSWORD \
    S3_ACCESS_KEY \
    S3_SECRET_KEY \
    S3_BUCKET \
    S3_REGION \
    MAX_MANUAL_IMPORT_BYTES \
    MAX_CHAT_JSON_BYTES \
    TEMPORAL_NAMESPACE \
    TEMPORAL_TASK_QUEUE \
    DEEPGRAM_API_KEY \
    TWITCH_CLIENT_ID \
    TWITCH_CLIENT_SECRET \
    TWITCH_REDIRECT_URI \
    JWT_SECRET \
    API_URL \
    WEB_URL
  do
    write_env_value "$key"
  done

  chmod 600 "$env_file"
fi

exec "$@"
EOF

RUN chmod +x /usr/local/bin/setup-ai-environment

ENTRYPOINT ["/usr/local/bin/setup-ai-environment"]
CMD ["bash"]
