#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Execute com sudo: sudo bash ./monitoring/install-universal.sh" >&2
  exit 1
fi

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
docker_bin=$(command -v docker)
install_dir=/usr/local/libexec/device-farm-adb-monitor-universal

if [[ ! -f "${project_dir}/compose.yaml" || ! -f "${project_dir}/.env" ]]; then
  echo "Não encontrei compose.yaml e .env em ${project_dir}." >&2
  exit 1
fi

install -d -m 0755 "${install_dir}"
install -m 0755 "${project_dir}/monitoring/adb-monitor-universal.sh" "${install_dir}/adb-monitor-universal.sh"
install -m 0644 "${project_dir}/monitoring/device-farm-adb-monitor-universal.service" /etc/systemd/system/
install -m 0644 "${project_dir}/monitoring/device-farm-adb-monitor-universal.timer" /etc/systemd/system/

cat > /etc/default/device-farm-adb-monitor-universal <<EOF
PROJECT_DIR="${project_dir}"
DOCKER_BIN="${docker_bin}"
GRACE_SECONDS="45"
EOF
chmod 0600 /etc/default/device-farm-adb-monitor-universal

systemctl daemon-reload
systemctl enable --now device-farm-adb-monitor-universal.timer
systemctl start device-farm-adb-monitor-universal.service

echo "Monitor universal instalado. Consulte: sudo systemctl status device-farm-adb-monitor-universal.timer"
