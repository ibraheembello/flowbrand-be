# Deploy guide — FlowBrand BE on AWS EC2

This is the shortest path from a fresh AWS account to your `dev` branch
auto-deploying on every push.

## 1. Provision the EC2 (≈ 3 min in AWS Console)

1. AWS Console → **EC2** → **Launch instance**.
2. Name: `flowbrand-dev`.
3. AMI: **Ubuntu Server 22.04 LTS** (or 24.04).
4. Instance type: `t3.small` (2 vCPU, 2 GB RAM — Free Tier eligible if you
   still have hours left, otherwise ≈ $15/mo).
5. Key pair: **Create new key pair** → name `flowbrand-dev` → RSA → `.pem`
   format → download. Keep this file safe (you'll only use it for the
   one-time setup; CI uses password auth, not the key).
6. Network settings → **Edit**:
   - Allow SSH from **My IP**
   - Add inbound rule: TCP **3008** from **Anywhere (0.0.0.0/0)**
   - Add inbound rule: TCP **80** from **Anywhere** (only if you add nginx later)
7. Storage: 20 GB gp3.
8. **Launch instance.**
9. Wait until the instance is **Running** and note its **Public IPv4 address**
   — this is your `HOST` value.

## 2. First-boot setup on the EC2 (≈ 5 min)

From your laptop:

```bash
# Connect (replace the IP and the .pem path with yours)
chmod 400 ~/Downloads/flowbrand-dev.pem
ssh -i ~/Downloads/flowbrand-dev.pem ubuntu@<EC2_PUBLIC_IP>
```

Once you're on the EC2:

```bash
# Pull the setup script straight from your fork and run it
curl -fsSL https://raw.githubusercontent.com/ibraheembello/flowbrand-be/dev/deploy/server-setup.sh -o /tmp/setup.sh
sudo bash /tmp/setup.sh

# Set the password for the ubuntu user (CI uses sshpass; pick something strong)
sudo passwd ubuntu
```

**Save the Postgres password** printed by the setup script — you'll need it
in the next step.

## 3. Place the env file on the EC2

Still on the EC2:

```bash
# Pull the template and fill it in
curl -fsSL https://raw.githubusercontent.com/ibraheembello/flowbrand-be/dev/deploy/.env.dev.template \
  -o /home/ubuntu/app/.env.dev

nano /home/ubuntu/app/.env.dev
# Replace every <PLACEHOLDER> — most importantly DB_PASSWORD and JWT_SECRET
```

For `JWT_SECRET`, generate one quickly with:

```bash
openssl rand -base64 64 | tr -d '\n'
```

## 4. Configure GitHub Secrets + Variables (≈ 2 min)

In your fork's GitHub page → **Settings**:

### Settings → Secrets and variables → Actions → **Secrets** tab → **New repository secret**

| Secret name | Value |
|---|---|
| `HOST` | The EC2 public IPv4 |
| `USERNAME` | `ubuntu` |
| `PASSWORD` | The password you set with `sudo passwd ubuntu` |

### Same screen → **Variables** tab → **New repository variable**

| Variable name | Value |
|---|---|
| `DEPLOY_DIR` | `/home/ubuntu/app` |
| `NODE_VERSION` | `20` |

### Settings → Environments → **New environment**

Create one named **`dev`**. No protection rules needed. The pipeline already
gates `staging` and `prod` separately so you can add those later.

## 5. Deploy (≈ 0 effort)

```bash
git push origin dev
```

Open your fork → **Actions** tab → watch the `Pipeline` run. The deploy
job will SSH into your EC2, extract the tarball, run migrations, and
restart PM2. End-to-end ≈ 3–5 minutes.

## 6. Test it

| URL | What it is |
|---|---|
| `http://<EC2_PUBLIC_IP>:3008/api/v1/probe` | Liveness probe (200 OK) |
| `http://<EC2_PUBLIC_IP>:3008/health` | Health check |
| `http://<EC2_PUBLIC_IP>:3008/api/docs` | **Swagger UI** — test every endpoint here |
| `http://<EC2_PUBLIC_IP>:3008/api/docs-json` | OpenAPI JSON |

## 7. Future PR merges → auto-deploy

Once Step 4 is configured, **every push to `dev` deploys automatically.**
PRs merged into `dev` just need the merge to happen — pipeline takes
over from there.

## Troubleshooting

| Symptom | Fix |
|---|---|
| CI `Deploy → dev` step fails with "Permission denied" | The `ubuntu` password didn't match. Reset via `sudo passwd ubuntu` and update GitHub `PASSWORD` secret. |
| App starts but DB connection refused | `.env.dev` has wrong DB_PASSWORD. Match the one printed by `server-setup.sh`. |
| Swagger 404 | App is up but global prefix excludes `/api/docs`. Check `main.ts:32` — should already be excluded. |
| `pm2 status` shows `errored` | SSH in, run `pm2 logs team-alpha-dev` to see the actual error. |
| Port 3008 connection refused from outside | EC2 security group missing the inbound rule. Re-add 3008/TCP from 0.0.0.0/0. |

## Costs (estimate, us-east-1)

| Resource | Monthly |
|---|---|
| `t3.small` EC2 (24×7) | ~$15 |
| 20 GB gp3 EBS | ~$1.60 |
| Data egress (light dev use) | < $1 |
| **Total** | **< $20** |

Stop the instance when not in use to drop EC2 cost to $0 (storage still
billed). To stop: AWS Console → EC2 → select instance → Instance state →
Stop. Restarting later gives a new public IP — update GitHub `HOST` secret.
