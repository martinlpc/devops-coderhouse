#!/bin/bash
set -euo pipefail

# La instancia exige IMDSv2: primero se pide un token y luego se consulta con él
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4)

# Instala k3s desde el canal estable y agrega la IP pública al certificado de la API
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -s - \
  --write-kubeconfig-mode 600 \
  --tls-san "$PUBLIC_IP"