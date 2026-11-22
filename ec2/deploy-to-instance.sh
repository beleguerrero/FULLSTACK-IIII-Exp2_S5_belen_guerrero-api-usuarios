#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

usage() {
  cat <<'USAGE'
Usage:
  deploy-to-instance.sh INSTANCE_ID REGION SERVICE_ID HOST_SCRIPT [DEPLOY_OPTIONS...]

Deploy options are forwarded to HOST_SCRIPT. For deploy-api.sh, pass options such as
--image, --container-name, --host-port, --container-port, --secret-id,
--secret-env-map, --second-secret-id, --second-secret-env-map, --profile,
--wallet-bucket and --wallet-key.
USAGE
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if (($# == 1)) && [[ "$1" == "--help" ]]; then
  usage
  exit 0
fi

if (($# < 4)); then
  usage >&2
  exit 2
fi

instance_id="$1"
region="$2"
service_id="$3"
host_script="$4"
shift 4

if [[ ! "$instance_id" =~ ^i-[0-9a-f]{8,17}$ \
  || ! "$region" =~ ^[a-z0-9-]+$ ]]; then
  fail "Invalid EC2 instance ID, region or service ID."
fi
[[ "$service_id" == "mi_foro" || "$service_id" == "second" ]] \
  || fail "SERVICE_ID must be mi_foro or second."
[[ -f "$host_script" && -r "$host_script" ]] || fail "Deployment script is not readable: $host_script"

for argument in "$@"; do
  [[ "$argument" != *$'\n'* && "$argument" != *$'\r'* ]] \
    || fail "Deployment arguments cannot contain newlines."
done

for command_name in aws base64 gzip jq mktemp grep; do
  command -v "$command_name" >/dev/null 2>&1 || fail "Required command is unavailable: $command_name"
done

quote_argument() {
  local value="$1"
  value="${value//\'/\'\\\'\'}"
  printf "'%s'" "$value"
}

script_b64="$(gzip -c "$host_script" | base64 -w0)"
quoted_region="$(quote_argument "$region")"
quoted_service="$(quote_argument "$service_id")"
remote_command="set -eu; remote_script=\$(mktemp /tmp/deploy-api.XXXXXX); trap 'rm -f -- \"\$remote_script\"' EXIT; printf '%s' '$script_b64' | base64 --decode | gzip --decompress > \"\$remote_script\"; chmod 700 \"\$remote_script\"; sudo bash \"\$remote_script\" --region $quoted_region --service $quoted_service"
for argument in "$@"; do
  remote_command+=" $(quote_argument "$argument")"
done

parameters_file="$(mktemp)"
invocation_error_file="$(mktemp)"
trap 'rm -f -- "$parameters_file" "$invocation_error_file"' EXIT
jq -n --arg command "$remote_command" '{commands: [$command], executionTimeout: ["900"]}' > "$parameters_file"

command_id="$(aws ssm send-command \
  --instance-ids "$instance_id" \
  --document-name AWS-RunShellScript \
  --comment "Deploy ${service_id} container through SSM" \
  --timeout-seconds 900 \
  --parameters "file://$parameters_file" \
  --region "$region" \
  --query 'Command.CommandId' \
  --output text)"
[[ "$command_id" =~ ^[0-9a-f-]{36}$ ]] || fail "SSM did not return a valid command ID."

for ((attempt = 1; attempt <= 204; attempt++)); do
  if invocation="$(aws ssm get-command-invocation \
    --command-id "$command_id" \
    --instance-id "$instance_id" \
    --region "$region" \
    --output json 2>"$invocation_error_file")"; then
    status="$(jq -er '.Status' <<< "$invocation")"
    case "$status" in
      Success)
        jq -r '.StandardOutputContent // empty' <<< "$invocation"
        jq -r '.StandardErrorContent // empty' <<< "$invocation" >&2
        exit 0
        ;;
      Pending|InProgress|Delayed)
        ;;
      *)
        jq -r '.StandardOutputContent // empty' <<< "$invocation" >&2
        jq -r '.StandardErrorContent // empty' <<< "$invocation" >&2
        printf 'EC2 deployment command ended with SSM status %s.\n' "$status" >&2
        exit 1
        ;;
    esac
  elif grep -q 'InvocationDoesNotExist' "$invocation_error_file"; then
    :
  else
    cat "$invocation_error_file" >&2
    fail "Could not retrieve the SSM command result."
  fi
  sleep 5
done

printf 'Local wait expired for SSM command %s. The command was not cancelled and may still be running. Do not retry until this command reaches a terminal SSM status; the EC2 deployment lock rejects overlapping runs.\n' \
  "$command_id" >&2
exit 1
