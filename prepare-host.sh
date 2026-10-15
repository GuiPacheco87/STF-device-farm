#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Não foi possível identificar a distribuição." >&2
  exit 1
fi

. /etc/os-release
if [[ "${ID}" != "ubuntu" || "${VERSION_ID}" != "26.04" ]]; then
  echo "Este preparo foi escrito para Ubuntu 26.04; detectado: ${PRETTY_NAME}." >&2
  exit 1
fi

${SUDO} apt-get update
${SUDO} apt-get install -y ca-certificates curl android-tools-adb
${SUDO} install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | ${SUDO} tee /etc/apt/keyrings/docker.asc >/dev/null
${SUDO} chmod a+r /etc/apt/keyrings/docker.asc

${SUDO} tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-${VERSION_CODENAME}}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

${SUDO} apt-get update
${SUDO} apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
${SUDO} systemctl enable --now docker

cat <<'EOF'

Ferramentas instaladas. Para administrar o Docker, use sudo (acesso ao grupo docker equivale a privilégios de administrador).
Próximos comandos de consulta:
  docker compose version
  adb version
EOF
