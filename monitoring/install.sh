#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Execute com sudo: sudo bash ./monitoring/install.sh DEVICE_SERIAL" >&2
  exit 1
fi

if [[ $# -ne 1 || ! "${1}" =~ ^[A-Za-z0-9._:-]+$ ]]; then
  echo "Informe o serial ADB do aparelho. Exemplo: sudo bash ./monitoring/install.sh DEVICE_SERIAL" >&2
  exit 1
fi

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
docker_bin=$(command -v docker)
install_dir=/usr/local/libexec/device-farm-adb-monitor

if [[ ! -f "${project_dir}/compose.yaml" || ! -f "${project_dir}/.env" ]]; then
  echo "Não encontrei compose.yaml e .env em ${project_dir}." >&2
  exit 1
fi

install -d -m 0755 "${install_dir}"
install -m 0755 "${project_dir}/monitoring/adb-monitor.sh" "${install_dir}/adb-monitor.sh"
install -m 0644 "${project_dir}/monitoring/device-farm-adb-monitor.service" /etc/systemd/system/
install -m 0644 "${project_dir}/monitoring/device-farm-adb-monitor.timer" /etc/systemd/system/

cat > /etc/default/device-farm-adb-monitor <<EOF
PROJECT_DIR="${project_dir}"
EXPECTED_DEVICE_SERIAL="${1}"
DOCKER_BIN="${docker_bin}"
EOF
chmod 0600 /etc/default/device-farm-adb-monitor

systemctl daemon-reload
systemctl enable --now device-farm-adb-monitor.timer
systemctl start device-farm-adb-monitor.service

echo "Monitoramento instalado. Consulte: sudo systemctl status device-farm-adb-monitor.timer"
