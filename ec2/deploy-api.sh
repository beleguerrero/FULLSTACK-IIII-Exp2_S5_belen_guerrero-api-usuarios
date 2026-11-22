#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

usage() {
  cat <<'USAGE'
Usage:
  deploy-api.sh --region REGION --service ID --image ECR_IMAGE \
    --host-port PORT --container-port PORT [options]

Required options:
  --region REGION                 AWS region containing ECR, S3 and Secrets Manager
  --service ID                    Stable deployment ID used to isolate this service
  --image ECR_IMAGE               ECR image URI with a tag or sha256 digest
  --host-port PORT                Port Nginx uses on the EC2 host
  --container-port PORT           Port listened to inside the container

Optional options:
  --container-name NAME           Defaults to the service ID
  --secret-id ID                  Secrets Manager name or ARN
  --secret-env-map MAP            Comma-separated ENV_NAME=JSON_KEY mappings
  --second-secret-id ID           Optional second Secrets Manager name or ARN
  --second-secret-env-map MAP     Comma-separated mappings for the second secret
  --profile PROFILE               Sets SPRING_PROFILES_ACTIVE
  --wallet-bucket BUCKET          S3 bucket containing the Oracle Wallet ZIP
  --wallet-key KEY                S3 object key for the Oracle Wallet ZIP
  --wallet-mount-path PATH        Container TNS_ADMIN path (default: /run/oracle-wallet)
  --wallet-group-id GID           Container-readable group (default: 10001)
  --db-url-env-key NAME           URL variable to append TNS_ADMIN to (default: DB_URL)
  --help                          Show this help

Both secret mapping options must be paired with their corresponding secret ID.
Environment variable names must be unique across both mappings. Wallet options
are per deployment; the combined mappings must include the configured DB URL.
USAGE
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

region=""
service_id=""
image_uri=""
container_name=""
host_port=""
container_port=""
secret_id=""
secret_env_map=""
second_secret_id=""
second_secret_env_map=""
spring_profile=""
wallet_bucket=""
wallet_key=""
wallet_mount_path="/run/oracle-wallet"
wallet_group_id="10001"
db_url_env_key="DB_URL"

while (($#)); do
  case "$1" in
    --region)
      (($# >= 2)) || fail "--region requires a value."
      region="$2"
      shift 2
      ;;
    --service)
      (($# >= 2)) || fail "--service requires a value."
      service_id="$2"
      shift 2
      ;;
    --image)
      (($# >= 2)) || fail "--image requires a value."
      image_uri="$2"
      shift 2
      ;;
    --container-name)
      (($# >= 2)) || fail "--container-name requires a value."
      container_name="$2"
      shift 2
      ;;
    --host-port)
      (($# >= 2)) || fail "--host-port requires a value."
      host_port="$2"
      shift 2
      ;;
    --container-port)
      (($# >= 2)) || fail "--container-port requires a value."
      container_port="$2"
      shift 2
      ;;
    --secret-id)
      (($# >= 2)) || fail "--secret-id requires a value."
      secret_id="$2"
      shift 2
      ;;
    --secret-env-map)
      (($# >= 2)) || fail "--secret-env-map requires a value."
      secret_env_map="$2"
      shift 2
      ;;
    --second-secret-id)
      (($# >= 2)) || fail "--second-secret-id requires a value."
      second_secret_id="$2"
      shift 2
      ;;
    --second-secret-env-map)
      (($# >= 2)) || fail "--second-secret-env-map requires a value."
      second_secret_env_map="$2"
      shift 2
      ;;
    --profile)
      (($# >= 2)) || fail "--profile requires a value."
      spring_profile="$2"
      shift 2
      ;;
    --wallet-bucket)
      (($# >= 2)) || fail "--wallet-bucket requires a value."
      wallet_bucket="$2"
      shift 2
      ;;
    --wallet-key)
      (($# >= 2)) || fail "--wallet-key requires a value."
      wallet_key="$2"
      shift 2
      ;;
    --wallet-mount-path)
      (($# >= 2)) || fail "--wallet-mount-path requires a value."
      wallet_mount_path="$2"
      shift 2
      ;;
    --wallet-group-id)
      (($# >= 2)) || fail "--wallet-group-id requires a value."
      wallet_group_id="$2"
      shift 2
      ;;
    --db-url-env-key)
      (($# >= 2)) || fail "--db-url-env-key requires a value."
      db_url_env_key="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

[[ "$region" =~ ^[a-z0-9-]+$ ]] || fail "A valid --region is required."
[[ "$service_id" == "mi_foro" || "$service_id" == "second" ]] \
  || fail "--service must be mi_foro or second."
[[ "$image_uri" == */* ]] || fail "A valid --image ECR URI is required."
[[ "$host_port" =~ ^[0-9]{1,5}$ ]] || fail "A valid --host-port is required."
[[ "$container_port" =~ ^[0-9]{1,5}$ ]] || fail "A valid --container-port is required."
(( 10#$host_port >= 1 && 10#$host_port <= 65535 )) || fail "--host-port must be between 1 and 65535."
(( 10#$container_port >= 1 && 10#$container_port <= 65535 )) || fail "--container-port must be between 1 and 65535."

if [[ -z "$container_name" ]]; then
  container_name="$service_id"
fi
[[ "$container_name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ ]] || fail "A valid --container-name is required."

registry="${image_uri%%/*}"
image_ref="${image_uri#*/}"
[[ "$registry" =~ ^[0-9]{12}\.dkr\.ecr\.${region}\.amazonaws\.com$ ]] \
  || fail "The image registry must be an ECR registry in --region."
[[ "$image_ref" =~ ^[a-z0-9][a-z0-9._/-]*(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}|@sha256:[a-f0-9]{64})$ ]] \
  || fail "The image must specify a valid ECR repository and tag or sha256 digest."

if [[ -n "$secret_id" && -z "$secret_env_map" ]] \
  || [[ -z "$secret_id" && -n "$secret_env_map" ]]; then
  fail "--secret-id and --secret-env-map must be supplied together."
fi
if [[ -n "$second_secret_id" && -z "$second_secret_env_map" ]] \
  || [[ -z "$second_secret_id" && -n "$second_secret_env_map" ]]; then
  fail "--second-secret-id and --second-secret-env-map must be supplied together."
fi
if [[ -n "$spring_profile" && ! "$spring_profile" =~ ^[A-Za-z0-9._-]+$ ]]; then
  fail "A valid --profile is required."
fi
if [[ -n "$wallet_bucket" && -z "$wallet_key" ]] \
  || [[ -z "$wallet_bucket" && -n "$wallet_key" ]]; then
  fail "--wallet-bucket and --wallet-key must be supplied together."
fi
if [[ -n "$wallet_bucket" ]]; then
  [[ "$wallet_bucket" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || fail "Invalid S3 bucket name."
  [[ "$wallet_key" != *$'\n'* && "$wallet_key" != *$'\r'* ]] || fail "Invalid S3 object key."
  [[ "$wallet_key" != "" ]] || fail "The S3 wallet key cannot be empty."
  [[ "$wallet_mount_path" =~ ^/[A-Za-z0-9._/-]+$ ]] || fail "Invalid --wallet-mount-path."
  case "/$wallet_mount_path/" in
    *"/../"*|*"/./"*) fail "The wallet mount path cannot contain dot segments." ;;
  esac
  [[ "$wallet_group_id" =~ ^[0-9]{1,10}$ ]] || fail "Invalid --wallet-group-id."
  (( 10#$wallet_group_id <= 4294967294 )) || fail "Invalid --wallet-group-id."
  [[ -n "$secret_id" || -n "$second_secret_id" ]] \
    || fail "An Oracle Wallet deployment requires a Secrets Manager DB URL."
  [[ "$db_url_env_key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fail "Invalid --db-url-env-key."
fi
if [[ "$service_id" == "mi_foro" ]]; then
  [[ -n "$secret_id" && -n "$wallet_bucket" ]] \
    || fail "mi_foro requires its own secret and Oracle Wallet S3 object."
fi

for command_name in aws docker python3 flock timeout; do
  command -v "$command_name" >/dev/null 2>&1 || fail "Required command is unavailable: $command_name"
done

exec 9>/run/lock/mi-foro-api-deploy.lock
flock -n 9 || fail "Another API deployment is still running; this deployment was not started."

deployment_id="$(date -u +%Y%m%d%H%M%S)-$$"
backup_name=""
new_container_attempted=false
deployment_committed=false
wallet_service_root="/opt/oracle-wallets/$service_id"
wallet_release_dir=""
wallet_archive=""
env_file=""
docker_config=""
old_wallet_dir=""

container_is_service() {
  local name="$1"
  local owner
  owner="$(docker inspect --format '{{ index .Config.Labels "com.mi-foro.service" }}' "$name" 2>/dev/null)" || return 1
  [[ "$owner" == "$service_id" ]]
}

wallet_mount_source() {
  local name="$1"
  local sources source
  sources="$(docker inspect --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' "$name")" || return 1
  while IFS= read -r source; do
    case "$source" in
      "$wallet_service_root"/*)
        printf '%s\n' "$source"
        return 0
        ;;
    esac
  done <<< "$sources"
  return 0
}

wallet_is_referenced() {
  local wallet_dir="$1"
  local container_ids container_id sources source

  container_ids="$(docker ps -aq)" || return 2
  [[ -n "$container_ids" ]] || return 1
  while IFS= read -r container_id; do
    [[ -n "$container_id" ]] || continue
    sources="$(docker inspect --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' "$container_id")" \
      || return 2
    while IFS= read -r source; do
      [[ "$source" == "$wallet_dir" || "$source" == "$wallet_dir/"* ]] && return 0
    done <<< "$sources"
  done <<< "$container_ids"
  return 1
}

cleanup() {
  local status=$?
  local reference_status
  local failed_container_name
  trap - EXIT

  if (( status != 0 )) && [[ "$deployment_committed" != true ]]; then
    if [[ "$new_container_attempted" == true ]] && container_is_service "$container_name"; then
      if ! docker rm -f "$container_name" >/dev/null 2>&1; then
        failed_container_name="${container_name}.failed.${deployment_id}"
        if ! docker stop "$container_name" >/dev/null 2>&1; then
          printf 'WARNING: Could not stop failed container %s before rollback.\n' "$container_name" >&2
        fi
        if docker rename "$container_name" "$failed_container_name"; then
          printf 'WARNING: Failed container was retained as %s.\n' "$failed_container_name" >&2
        else
          printf 'ERROR: Failed container %s could not be removed or renamed.\n' "$container_name" >&2
        fi
      fi
    fi
    if [[ -n "$backup_name" ]] && docker inspect "$backup_name" >/dev/null 2>&1; then
      if docker inspect "$container_name" >/dev/null 2>&1; then
        printf 'ERROR: Previous container remains available as %s; name %s is still occupied.\n' \
          "$backup_name" "$container_name" >&2
      elif docker rename "$backup_name" "$container_name"; then
        backup_name=""
        if docker start "$container_name" >/dev/null; then
          printf 'Deployment failed; previous %s container was restored.\n' "$service_id" >&2
        else
          printf 'ERROR: Previous container %s was restored but could not be started; its wallet was retained.\n' \
            "$container_name" >&2
        fi
      else
        printf 'ERROR: Rollback could not restore the previous container. Backup remains as %s.\n' "$backup_name" >&2
      fi
    fi
  fi

  if [[ -n "$env_file" ]] && ! rm -f -- "$env_file"; then
    printf 'WARNING: Could not remove temporary environment file %s.\n' "$env_file" >&2
  fi
  if [[ -n "$wallet_archive" ]] && ! rm -f -- "$wallet_archive"; then
    printf 'WARNING: Could not remove temporary wallet archive %s.\n' "$wallet_archive" >&2
  fi
  if [[ -n "$wallet_release_dir" && "$deployment_committed" != true ]]; then
    if wallet_is_referenced "$wallet_release_dir"; then
      printf 'WARNING: Keeping the downloaded wallet because a container still references it.\n' >&2
    else
      reference_status=$?
      if (( reference_status == 1 )); then
        if ! rm -rf -- "$wallet_release_dir"; then
          printf 'WARNING: Could not remove unused wallet directory %s.\n' "$wallet_release_dir" >&2
        fi
      else
        printf 'WARNING: Keeping the downloaded wallet because container mounts could not be checked.\n' >&2
      fi
    fi
  fi
  if [[ -n "$docker_config" ]] && ! rm -rf -- "$docker_config"; then
    printf 'WARNING: Could not remove temporary Docker configuration directory.\n' >&2
  fi
  exit "$status"
}
trap cleanup EXIT

docker_config="$(mktemp -d /tmp/deploy-api-docker.XXXXXX)"
chmod 700 "$docker_config"
export DOCKER_CONFIG="$docker_config"

aws ecr get-login-password --region "$region" \
  | docker login --username AWS --password-stdin "$registry" >/dev/null
docker pull "$image_uri"
rm -f -- "$docker_config/config.json"

append_secret_to_env() {
  local current_secret_id="$1"
  local current_secret_env_map="$2"

  aws secretsmanager get-secret-value \
    --secret-id "$current_secret_id" \
    --query SecretString \
    --output text \
    --region "$region" \
    | python3 -c '
import json
import re
import sys

env_path, mapping_text = sys.argv[1:]
secret = json.load(sys.stdin)
if not isinstance(secret, dict):
    raise SystemExit("The selected secret must contain a JSON object.")

existing_names = set()
with open(env_path, "r", encoding="utf-8") as existing_file:
    for line in existing_file:
        name, separator, _ = line.rstrip("\n").partition("=")
        if not separator or not name:
            raise SystemExit("The temporary environment file is malformed.")
        existing_names.add(name)

values = {}
for entry in mapping_text.split(","):
    if "=" not in entry:
        raise SystemExit("Invalid secret environment mapping.")
    env_name, json_key = entry.split("=", 1)
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", env_name):
        raise SystemExit("Invalid environment variable name in secret mapping.")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", json_key):
        raise SystemExit("Invalid JSON key in secret environment mapping.")
    if env_name in existing_names or env_name in values:
        raise SystemExit(f"Duplicate environment variable mapping: {env_name}.")
    value = secret.get(json_key)
    if not isinstance(value, str) or not value or any(char in value for char in ("\n", "\r", "\0")):
        raise SystemExit(f"Secret field for {env_name} is missing or not a single-line string.")
    values[env_name] = value

with open(env_path, "a", encoding="utf-8", newline="\n") as output:
    for env_name, value in values.items():
        output.write(f"{env_name}={value}\n")
' "$env_file" "$current_secret_env_map"
}

if [[ -n "$secret_id" || -n "$second_secret_id" || -n "$spring_profile" ]]; then
  env_file="$(mktemp /tmp/deploy-api-env.XXXXXX)"
  if [[ -n "$secret_id" ]]; then
    append_secret_to_env "$secret_id" "$secret_env_map"
  fi
  if [[ -n "$second_secret_id" ]]; then
    append_secret_to_env "$second_secret_id" "$second_secret_env_map"
  fi

  tns_admin_path=""
  if [[ -n "$wallet_bucket" ]]; then
    tns_admin_path="$wallet_mount_path"
  fi
  python3 - "$env_file" "$db_url_env_key" "$tns_admin_path" "$spring_profile" <<'PY'
import sys
from urllib.parse import unquote_plus, quote

env_path, db_url_key, tns_admin_path, profile = sys.argv[1:]
values = {}
with open(env_path, "r", encoding="utf-8") as environment_file:
    for line in environment_file:
        name, separator, value = line.rstrip("\n").partition("=")
        if not separator or not name or name in values:
            raise SystemExit("The combined environment mapping is invalid.")
        values[name] = value

if tns_admin_path:
    if db_url_key not in values:
        raise SystemExit("The combined secret mappings must include the configured DB URL variable when using a wallet.")
    base, separator, query = values[db_url_key].partition("?")
    preserved = []
    for pair in (query.split("&") if separator else []):
        key = unquote_plus(pair.split("=", 1)[0])
        if key.lower() != "tns_admin":
            preserved.append(pair)
    preserved.append("TNS_ADMIN=" + quote(tns_admin_path, safe="/"))
    values[db_url_key] = base + "?" + "&".join(preserved)
    if "TNS_ADMIN" in values and values["TNS_ADMIN"] != tns_admin_path:
        raise SystemExit("Secret TNS_ADMIN conflicts with the configured wallet mount path.")
    values["TNS_ADMIN"] = tns_admin_path

if profile:
    if "SPRING_PROFILES_ACTIVE" in values:
        raise SystemExit("Do not map SPRING_PROFILES_ACTIVE from a secret when using --profile.")
    values["SPRING_PROFILES_ACTIVE"] = profile

with open(env_path, "w", encoding="utf-8", newline="\n") as output:
    for env_name, value in values.items():
        output.write(f"{env_name}={value}\n")
PY
fi

if [[ -n "$wallet_bucket" ]]; then
  if [[ -L /opt/oracle-wallets || -L "$wallet_service_root" ]]; then
    fail "Wallet storage path must not be a symbolic link."
  fi
  install -d -m 0700 "$wallet_service_root"
  wallet_release_dir="$wallet_service_root/$deployment_id"
  install -d -m 0700 "$wallet_release_dir"
  wallet_archive="$(mktemp "$wallet_service_root/.wallet-${deployment_id}.XXXXXX")"

  aws s3api get-object \
    --region "$region" \
    --bucket "$wallet_bucket" \
    --key "$wallet_key" \
    "$wallet_archive" >/dev/null

  python3 - "$wallet_archive" "$wallet_release_dir" <<'PY'
import shutil
import stat
import sys
import zipfile
from pathlib import Path, PurePosixPath

archive_path, destination = sys.argv[1:]
root = Path(destination).resolve()
max_uncompressed_bytes = 128 * 1024 * 1024

with zipfile.ZipFile(archive_path) as archive:
    entries = archive.infolist()
    if len(entries) > 2048 or sum(entry.file_size for entry in entries) > max_uncompressed_bytes:
        raise SystemExit("Oracle Wallet archive exceeds the safe extraction limits.")

    for entry in entries:
        name = entry.filename
        relative = PurePosixPath(name)
        if (
            not name
            or "\\" in name
            or relative.is_absolute()
            or not relative.parts
            or any(part in ("", ".", "..") for part in relative.parts)
            or ":" in relative.parts[0]
        ):
            raise SystemExit("Oracle Wallet archive contains an unsafe path.")

        mode = (entry.external_attr >> 16) & 0xFFFF
        kind = stat.S_IFMT(mode)
        if kind not in (0, stat.S_IFREG, stat.S_IFDIR):
            raise SystemExit("Oracle Wallet archive contains a non-regular file.")

        target = root.joinpath(*relative.parts)
        if entry.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue

        target.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(entry) as source, target.open("xb") as output:
            shutil.copyfileobj(source, output)

# Accept a flat wallet or an enclosing wallet directory identified by both required files.
files = [path for path in root.rglob("*") if path.is_file()]
tnsnames_files = [path for path in files if path.name == "tnsnames.ora"]
sqlnet_files = [path for path in files if path.name == "sqlnet.ora"]
if len(tnsnames_files) != 1 or len(sqlnet_files) != 1:
    raise SystemExit("Oracle Wallet ZIP must contain exactly one tnsnames.ora and one sqlnet.ora.")

wallet_root = tnsnames_files[0].parent
if sqlnet_files[0].parent != wallet_root:
    raise SystemExit("Oracle Wallet ZIP files tnsnames.ora and sqlnet.ora must be in the same directory.")

if wallet_root != root:
    if any(wallet_root not in path.parents for path in files):
        raise SystemExit("Oracle Wallet ZIP contains files outside its enclosing wallet directory.")

    for child in wallet_root.iterdir():
        target = root / child.name
        if target.exists():
            raise SystemExit("Oracle Wallet ZIP has conflicting paths while removing its enclosing directory.")
        shutil.move(str(child), str(target))

    wrapper_directories = [wallet_root]
    wrapper_directories.extend(
        path for path in wallet_root.parents if path != root and root in path.parents
    )
    for directory in sorted(
        wrapper_directories,
        key=lambda path: len(path.parts),
        reverse=True,
    ):
        directory.rmdir()

if not (root / "tnsnames.ora").is_file() or not (root / "sqlnet.ora").is_file():
    raise SystemExit("Oracle Wallet ZIP did not place tnsnames.ora and sqlnet.ora in TNS_ADMIN.")
PY

  chown -R "0:${wallet_group_id}" "$wallet_release_dir"
  find "$wallet_release_dir" -type d -exec chmod 0750 {} +
  find "$wallet_release_dir" -type f -exec chmod 0440 {} +
  rm -f -- "$wallet_archive"
  wallet_archive=""
fi

if docker inspect "$container_name" >/dev/null 2>&1; then
  container_is_service "$container_name" \
    || fail "Container name $container_name is already owned by a different or unmanaged container."
  backup_name="${container_name}.rollback.${deployment_id}"
  docker rename "$container_name" "$backup_name"
  old_wallet_dir="$(wallet_mount_source "$backup_name")"
  docker stop "$backup_name" >/dev/null
fi

run_args=(
  docker run --detach
  --name "$container_name"
  --restart unless-stopped
  --publish "127.0.0.1:${host_port}:${container_port}"
  --label "com.mi-foro.service=${service_id}"
)
if [[ -n "$env_file" ]]; then
  run_args+=(--env-file "$env_file")
fi
if [[ -n "$wallet_release_dir" ]]; then
  run_args+=(
    --mount "type=bind,source=${wallet_release_dir},target=${wallet_mount_path},readonly"
    --group-add "$wallet_group_id"
  )
fi
run_args+=("$image_uri")

new_container_attempted=true
"${run_args[@]}" >/dev/null
if [[ -n "$env_file" ]]; then
  rm -f -- "$env_file"
  env_file=""
fi

stable_checks=0
ready=false
for ((attempt = 1; attempt <= 60; attempt++)); do
  container_status="$(docker inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null || true)"
  if [[ "$container_status" == "running" ]] \
    && timeout 3 bash -c 'exec 3<>"/dev/tcp/127.0.0.1/$1"' _ "$host_port" 2>/dev/null; then
    ((stable_checks += 1))
    if (( stable_checks >= 3 )); then
      ready=true
      break
    fi
  else
    stable_checks=0
    if [[ "$container_status" != "running" ]]; then
      break
    fi
  fi
  sleep 5
done

if [[ "$ready" != true ]]; then
  state="$(docker inspect --format 'status={{.State.Status}} exit={{.State.ExitCode}}' "$container_name" 2>/dev/null || printf 'container not found')"
  fail "The new container did not remain running with TCP port 127.0.0.1:${host_port} available ($state). This check does not confirm Spring Boot initialization or Oracle connectivity."
fi

printf 'Container is running and TCP port 127.0.0.1:%s is accepting connections. This confirms port availability only; it does not confirm Spring Boot initialization or Oracle connectivity.\n' \
  "$host_port"
deployment_committed=true

if [[ -n "$backup_name" ]]; then
  if docker rm "$backup_name" >/dev/null; then
    backup_name=""
    if [[ -n "$old_wallet_dir" ]]; then
      case "$old_wallet_dir" in
        "$wallet_service_root"/*)
          if [[ "$old_wallet_dir" != "$wallet_release_dir" ]]; then
            if wallet_is_referenced "$old_wallet_dir"; then
              printf 'WARNING: Keeping previous wallet directory because a container still references it.\n' >&2
            else
              reference_status=$?
              if (( reference_status == 1 )); then
                if ! rm -rf -- "$old_wallet_dir"; then
                  printf 'WARNING: Could not remove previous wallet directory %s.\n' "$old_wallet_dir" >&2
                fi
              else
                printf 'WARNING: Keeping previous wallet directory because container mounts could not be checked.\n' >&2
              fi
            fi
          fi
          ;;
      esac
    fi
  else
    printf 'WARNING: Previous container remains available as %s; its wallet was retained.\n' "$backup_name" >&2
  fi
fi

printf 'Deployment completed: service=%s image=%s container=%s\n' \
  "$service_id" "$image_uri" "$container_name"
