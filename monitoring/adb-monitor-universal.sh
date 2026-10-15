#!/usr/bin/env bash
set -uo pipefail

: "${PROJECT_DIR:?PROJECT_DIR is required}"
: "${DOCKER_BIN:?DOCKER_BIN is required}"

state_dir=/var/lib/device-farm-adb-monitor-universal
known_file=${state_dir}/known-devices
missing_dir=${state_dir}/missing-since
attempted_dir=${state_dir}/attempted
now=$(date +%s)
grace_seconds=${GRACE_SECONDS:-45}

compose() {
  "${DOCKER_BIN}" compose --project-directory "${PROJECT_DIR}" -f "${PROJECT_DIR}/compose.yaml" "$@"
}

mkdir -p "${state_dir}" "${missing_dir}" "${attempted_dir}"
touch "${known_file}"

# Only the ADB container is authoritative for devices available to STF.
devices=$(compose exec -T adb adb devices 2>/dev/null || true)
online_file=$(mktemp "${state_dir}/online.XXXXXX")
trap 'rm -f "${online_file}"' EXIT
printf '%s\n' "${devices}" | awk '$2 == "device" && $1 !~ /^List$/ { print $1 }' | sort -u > "${online_file}"

# Remember any device that has been successfully available at least once.
while IFS= read -r serial; do
  [[ "${serial}" =~ ^[A-Za-z0-9._:-]+$ ]] || continue
  if ! grep -Fxq -- "${serial}" "${known_file}"; then
    printf '%s\n' "${serial}" >> "${known_file}"
    logger -t device-farm-adb-monitor-universal "Monitoring ADB device ${serial}"
  fi
done < "${online_file}"

offline_recovered=
while IFS= read -r serial; do
  [[ "${serial}" =~ ^[A-Za-z0-9._:-]+$ ]] || continue
  missing_file=${missing_dir}/${serial}
  attempted_file=${attempted_dir}/${serial}

  if grep -Fxq -- "${serial}" "${online_file}"; then
    if [[ -e "${missing_file}" || -e "${attempted_file}" ]]; then
      logger -t device-farm-adb-monitor-universal "ADB device ${serial} is back online"
    fi
    rm -f "${missing_file}" "${attempted_file}"
    continue
  fi

  # Devices are added to known-devices only after ADB has seen them online.
  if [[ ! -e "${missing_file}" ]]; then
    printf '%s\n' "${now}" > "${missing_file}"
    continue
  fi

  if [[ -e "${attempted_file}" ]]; then
    continue
  fi

  missing_since=$(cat "${missing_file}" 2>/dev/null || true)
  if ! [[ "${missing_since}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "${now}" > "${missing_file}"
    continue
  fi

  if (( now - missing_since >= grace_seconds )); then
    offline_recovered+=" ${serial}"
  fi
done < "${known_file}"

[[ -n "${offline_recovered}" ]] || exit 0

logger -t device-farm-adb-monitor-universal "Known ADB device(s) offline for at least ${grace_seconds}s:${offline_recovered}; recreating adb and provider"
if compose up -d --force-recreate adb provider; then
  # Mark all currently missing devices so one outage causes only one restart.
  while IFS= read -r serial; do
    [[ "${serial}" =~ ^[A-Za-z0-9._:-]+$ ]] || continue
    if ! grep -Fxq -- "${serial}" "${online_file}"; then
      : > "${attempted_dir}/${serial}"
    fi
  done < "${known_file}"
else
  logger -t device-farm-adb-monitor-universal "Container recreation failed; it will retry after another persistent-offline interval"
  while IFS= read -r serial; do
    [[ "${serial}" =~ ^[A-Za-z0-9._:-]+$ ]] || continue
    if ! grep -Fxq -- "${serial}" "${online_file}"; then
      printf '%s\n' "${now}" > "${missing_dir}/${serial}"
    fi
  done < "${known_file}"
fi
