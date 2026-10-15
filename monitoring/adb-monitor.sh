#!/usr/bin/env bash
set -uo pipefail

: "${PROJECT_DIR:?PROJECT_DIR is required}"
: "${EXPECTED_DEVICE_SERIAL:?EXPECTED_DEVICE_SERIAL is required}"
: "${DOCKER_BIN:?DOCKER_BIN is required}"

state_dir=/var/lib/device-farm-adb-monitor
state_file=${state_dir}/state
missing_file=${state_dir}/missing-since
now=$(date +%s)

compose() {
  "${DOCKER_BIN}" compose --project-directory "${PROJECT_DIR}" -f "${PROJECT_DIR}/compose.yaml" "$@"
}

mkdir -p "${state_dir}"

devices=$(compose exec -T adb adb devices 2>/dev/null || true)
device_status=$(printf '%s\n' "${devices}" | awk -v serial="${EXPECTED_DEVICE_SERIAL}" '$1 == serial { print $2; exit }')

if [[ "${device_status}" == device ]]; then
  previous_state=
  [[ ! -r "${state_file}" ]] || previous_state=$(cat "${state_file}")
  if [[ "${previous_state}" == waiting ]]; then
    logger -t device-farm-adb-monitor "ADB device is back online"
  fi
  printf 'connected\n' > "${state_file}"
  rm -f "${missing_file}"
  exit 0
fi

previous_state=
[[ ! -r "${state_file}" ]] || previous_state=$(cat "${state_file}")

# Arm recovery only after this device has been seen online once.
if [[ "${previous_state}" != connected ]]; then
  exit 0
fi

if [[ ! -r "${missing_file}" ]]; then
  printf '%s\n' "${now}" > "${missing_file}"
  exit 0
fi

missing_since=$(cat "${missing_file}")
if ! [[ "${missing_since}" =~ ^[0-9]+$ ]]; then
  printf '%s\n' "${now}" > "${missing_file}"
  exit 0
fi

# Wait for transient USB resets before recreating the ADB/provider containers.
if (( now - missing_since < 45 )); then
  exit 0
fi

logger -t device-farm-adb-monitor "ADB device missing for at least 45 seconds; recreating adb and provider"
if compose up -d --force-recreate adb provider; then
  printf 'waiting\n' > "${state_file}"
  rm -f "${missing_file}"
else
  logger -t device-farm-adb-monitor "Container recreation failed; retrying after another 45 seconds"
  printf '%s\n' "${now}" > "${missing_file}"
fi
