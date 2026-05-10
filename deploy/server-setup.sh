#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
#  EC2 first-boot setup — Ubuntu 22.04 / 24.04
#
#  Run ONCE on a freshly-launched EC2 instance as the `ubuntu` user:
#    curl -fsSL https://raw.githubusercontent.com/ibraheembello/flowbrand-be/dev/deploy/server-setup.sh | sudo bash
#  or:
#    scp this file to the instance, then `sudo bash server-setup.sh`
#
#  After this completes, you still need to:
#    1. Set a password for the `ubuntu` user      → sudo passwd ubuntu
#    2. Create the runtime env file                → see deploy/.env.dev.template
#    3. Add HOST / USERNAME / PASSWORD to GitHub Secrets on your fork
#    4. git push origin dev  → CI deploys automatically
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-ubuntu}"
DEPLOY_DIR="${DEPLOY_DIR:-/home/${DEPLOY_USER}/app}"
PG_DB="${PG_DB:-flowbrand_dev}"
PG_USER="${PG_USER:-flowbrand}"
PG_PASSWORD="${PG_PASSWORD:-$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)}"
NODE_MAJOR=20

echo "════════════════════════════════════════════════════════════"
echo "  FlowBrand BE — EC2 setup"
echo "  Deploy user : ${DEPLOY_USER}"
echo "  Deploy dir  : ${DEPLOY_DIR}"
echo "  Postgres DB : ${PG_DB}"
echo "  Postgres user: ${PG_USER}"
echo "  Node.js     : v${NODE_MAJOR}"
echo "════════════════════════════════════════════════════════════"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root (use sudo)." >&2
  exit 1
fi

# ── System base ────────────────────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y curl ca-certificates gnupg lsb-release build-essential \
                   ufw fail2ban git unzip

# ── Node.js (NodeSource) ───────────────────────────────────────────────────────
curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
apt-get install -y nodejs
npm install -g pm2 yarn

# ── Postgres 15+ ───────────────────────────────────────────────────────────────
apt-get install -y postgresql postgresql-contrib
systemctl enable --now postgresql

sudo -u postgres psql <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${PG_USER}') THEN
    CREATE ROLE ${PG_USER} LOGIN PASSWORD '${PG_PASSWORD}';
  END IF;
END
\$\$;

SELECT 'CREATE DATABASE ${PG_DB} OWNER ${PG_USER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${PG_DB}')\gexec

GRANT ALL PRIVILEGES ON DATABASE ${PG_DB} TO ${PG_USER};
SQL

echo "Postgres user '${PG_USER}' / db '${PG_DB}' ready."

# ── Redis ─────────────────────────────────────────────────────────────────────
apt-get install -y redis-server
systemctl enable --now redis-server

# ── Enable password SSH auth (required by the CI pipeline's sshpass) ──────────
sed -ri 's/^#?\s*PasswordAuthentication\s+.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
mkdir -p /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/99-password-auth.conf <<'EOF'
PasswordAuthentication yes
PubkeyAuthentication yes
EOF
systemctl reload ssh || systemctl reload sshd

# ── Deploy directory + runtime layout ─────────────────────────────────────────
install -d -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "${DEPLOY_DIR}"
install -d -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "/home/${DEPLOY_USER}/tmp/nestjs"

# ── Firewall ──────────────────────────────────────────────────────────────────
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 3008/tcp comment "FlowBrand API"
ufw --force enable

# ── PM2 boot ──────────────────────────────────────────────────────────────────
sudo -u "${DEPLOY_USER}" -H bash -c "pm2 startup systemd -u ${DEPLOY_USER} --hp /home/${DEPLOY_USER}" \
  | tail -n 1 | bash || true

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo "════════════════════════════════════════════════════════════"
echo "  ✅  Setup complete."
echo
echo "  Postgres credentials (save these in your env file):"
echo "    DB_USERNAME=${PG_USER}"
echo "    DB_PASSWORD=${PG_PASSWORD}"
echo "    DB_NAME=${PG_DB}"
echo
echo "  Next steps:"
echo "    1. sudo passwd ${DEPLOY_USER}   # set an SSH password"
echo "    2. cp deploy/.env.dev.template ${DEPLOY_DIR}/.env.dev"
echo "       and fill it in with the Postgres password above"
echo "    3. Add GitHub Secrets HOST, USERNAME (${DEPLOY_USER}), PASSWORD"
echo "    4. Add GitHub Variable DEPLOY_DIR = ${DEPLOY_DIR}"
echo "    5. git push origin dev  → CI deploys"
echo "════════════════════════════════════════════════════════════"
