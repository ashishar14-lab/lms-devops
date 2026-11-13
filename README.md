# LMS DevOps Test – Step-by-Step Guide (≈60 min)

Everything you need is in this repo:

```
lms-devops/
├── terraform/      VPC, subnets, IGW, route table, SGs, key pair, 2 app + 1 DB EC2, outputs, auto inventory
├── ansible/        db.yml (PostgreSQL), app.yml (Docker + Nginx), deploy.yml (build/run app), jenkins.yml
├── app/            Learning Management Platform (Node.js + PostgreSQL) + Dockerfile
└── Jenkinsfile     7-stage CI/CD pipeline triggered by GitHub webhook
```

📸 = take a screenshot here. Name them `SS-01`, `SS-02` … so they match the checklist at the bottom.

---

## Time plan

| Min | Step |
|---|---|
| 0–5 | Step 0–1: accounts ready, launch Management Server |
| 5–10 | Step 2–3: GitHub repo, install tools |
| 10–18 | Step 4: Terraform |
| 18–30 | Step 5–6: SSH + Ansible (app, DB, deploy) |
| 30–42 | Step 7–9: Jenkins install, credentials, pipeline, first build |
| 42–55 | Step 10–11: webhook + validation (code change → auto deploy) |
| 55–60 | Buffer / screenshots you missed |

> Tip: while a long command runs (apt, terraform apply, ansible), do the next browser task (Docker Hub token, GitHub repo, etc.).

---

## Step 0 – Have these ready (2 min)

1. **Docker Hub**: log in → Account Settings → Personal access tokens → *Generate* (Read & Write). Copy the token.
2. **GitHub**: create a **public** repo named `lms-devops` (public = no Git credentials needed in Jenkins).
3. Unzip `lms-devops.zip` on your laptop → in the new repo click **"uploading an existing file"** → drag *all* contents (`app`, `ansible`, `terraform`, `Jenkinsfile`, `README.md`, `.gitignore`) → **Commit**.

📸 **SS-01** GitHub repo showing the files.

---

## Step 1 – Create the Management Server manually (AWS Console)

1. **IAM → Roles → Create role** → Trusted entity: *AWS service → EC2* → attach **AmazonEC2FullAccess** → name `mgmt-terraform-role` → Create.
2. **EC2 → Launch instance**
   - Name: `management-server`
   - AMI: **Ubuntu Server 24.04 LTS**
   - Type: **t3.medium** (Jenkins needs ≥ 4 GB RAM; t2.medium also fine)
   - Key pair: create/choose one (to SSH from your laptop)
   - Network: default VPC, auto-assign public IP **enabled**
   - Security group: allow **22** and **8080** from `0.0.0.0/0`
   - Storage: **20 GB**
   - Advanced details → IAM instance profile: **mgmt-terraform-role**
3. Launch, then SSH in: `ssh -i yourkey.pem ubuntu@<MGMT_PUBLIC_IP>`

📸 **SS-02** EC2 console: management-server *Running* (show IAM role / SG on details tab).

---

## Step 2 – Install Terraform, Ansible, Git on the Management Server

```bash
sudo apt update && sudo apt install -y gnupg software-properties-common curl unzip git ansible

wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform

terraform -version
ansible --version
```

📸 **SS-03** terminal showing `terraform -version` and `ansible --version`.

## Step 3 – SSH key + clone repo

```bash
# Key used for passwordless SSH to ALL servers (Terraform uploads the public half)
ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa

git clone https://github.com/<YOUR_GITHUB_USER>/lms-devops.git
cd lms-devops
```

---

## Step 4 – Terraform: provision infrastructure

Default region is `us-east-1`. To use Mumbai add `-var region=ap-south-1` to **plan** and **apply** (any region works).

```bash
cd ~/lms-devops/terraform
terraform init
terraform validate
terraform plan -out tfplan
terraform apply tfplan          # ~2 min
terraform output
```

If you see *"instance type not supported in AZ"*, re-run with `-var instance_type=t2.micro`.

📸 **SS-04** `terraform init` success  
📸 **SS-05** `terraform apply` → *Apply complete! Resources: 16 added*  
📸 **SS-06** `terraform output` (instance IDs, public IPs, private IPs)  
📸 **SS-07** AWS console → VPC → *Your VPCs* (lms-vpc), *Subnets* (3), *Internet gateways*, *Route tables*  
📸 **SS-08** AWS console → EC2 Instances: `lms-app-server-1`, `lms-app-server-2`, `lms-db-server` Running  
📸 **SS-09** Security groups → `lms-db-sg` inbound rules (5432 source = `lms-app-sg`)

Terraform also writes `ansible/inventory.ini` automatically. **Note the IPs** – you need them for the Jenkinsfile.

---

## Step 5 – Passwordless SSH + Ansible connectivity

Wait ~1 minute after apply so the instances finish booting.

```bash
cd ~/lms-devops/ansible
cat inventory.ini

# Passwordless SSH test (no password prompt)
ssh -o StrictHostKeyChecking=no ubuntu@<APP1_PUBLIC_IP> hostname
ssh -o StrictHostKeyChecking=no ubuntu@<APP2_PUBLIC_IP> hostname
ssh -o StrictHostKeyChecking=no ubuntu@<DB_PUBLIC_IP>   hostname

ansible all -m ping
```

📸 **SS-10** `inventory.ini` + the 3 ssh commands returning hostnames with no password  
📸 **SS-11** `ansible all -m ping` → 3 × `"ping": "pong"`

---

## Step 6 – Ansible: PostgreSQL, Docker, Nginx, deploy app

```bash
cd ~/lms-devops/ansible
ansible-playbook site.yml        # runs db.yml → app.yml → deploy.yml  (~6–8 min)
```

What it does:
- **db.yml** – installs PostgreSQL, `listen_addresses='*'`, `pg_hba.conf` allows `10.0.0.0/16`, creates DB **lms_db** and user **lms_user**
- **app.yml** – installs Docker + Nginx on both app servers, Nginx reverse proxy `:80 → 127.0.0.1:3000`
- **deploy.yml** – copies `app/`, `docker build`, runs container with DB env vars, checks `/health`, then tests App→DB with `nc` and `psql`

📸 **SS-12** output of *"Show listener"* (PostgreSQL on 5432) and *"Show health result"* (`db: connected`)  
📸 **SS-13** output of *"Test App -> DB connectivity"* (nc succeeded + psql result)  
📸 **SS-14** `PLAY RECAP` with `failed=0` for app1, app2, db1

Open in your browser:
- `http://<APP1_PUBLIC_IP>`
- `http://<APP2_PUBLIC_IP>`

📸 **SS-15** both app pages: title **v1**, Database **CONNECTED**, courses list  
📸 **SS-16** `http://<APP1_PUBLIC_IP>/health` JSON

Optional extra proof (good for "test communication app ↔ DB"):
```bash
ssh ubuntu@<APP1_PUBLIC_IP>
ping -c 3 <DB_PRIVATE_IP>
nc -zv <DB_PRIVATE_IP> 5432
PGPASSWORD=LmsPass2026 psql -h <DB_PRIVATE_IP> -U lms_user -d lms_db -c "select * from courses;"
docker ps
exit
```
📸 **SS-17** that terminal output.

---

## Step 7 – Install Jenkins with Ansible

```bash
cd ~/lms-devops/ansible
ansible-playbook jenkins.yml     # ~3–4 min; prints the initial admin password at the end
```

📸 **SS-18** playbook output showing *Initial admin password* and `failed=0`

Browser → `http://<MGMT_PUBLIC_IP>:8080` → paste password → **Install suggested plugins** → create admin user → Save.

📸 **SS-19** Jenkins dashboard after login

## Step 8 – Jenkins credential for Docker Hub

Manage Jenkins → Credentials → System → Global credentials → **Add Credentials**
- Kind: *Username with password*
- Username: your Docker Hub username
- Password: the Docker Hub **access token**
- ID: **`dockerhub-creds`** (must match exactly)

📸 **SS-20** credential list showing `dockerhub-creds`

## Step 9 – Edit Jenkinsfile + create the pipeline

1. On GitHub open `Jenkinsfile` → ✏️ edit the 4 lines at the top:
   ```
   DOCKERHUB_USER = 'yourdockerhubuser'
   APP_SERVERS    = '3.110.x.x 13.233.x.x'   // APP1 and APP2 PUBLIC IPs, space separated
   DB_HOST        = '10.0.3.x'               // DB PRIVATE IP
   ```
   Commit.
2. Jenkins → **New Item** → name `lms-pipeline` → **Pipeline** → OK
   - Build Triggers: ✅ **GitHub hook trigger for GITScm polling**
   - Pipeline → Definition: **Pipeline script from SCM** → SCM: **Git**
   - Repository URL: `https://github.com/<YOU>/lms-devops.git`
   - Branch: `*/main`   Script Path: `Jenkinsfile`
   - Save → **Build Now**

📸 **SS-21** job configuration (trigger checkbox + SCM section)  
📸 **SS-22** Stage View: all 7 stages green (build #1)  
📸 **SS-23** Console Output end: verification lines + `Finished: SUCCESS`  
📸 **SS-24** Docker Hub → repository `lms-app` showing tags `1` and `latest`

---

## Step 10 – GitHub Webhook

GitHub repo → **Settings → Webhooks → Add webhook**
- Payload URL: `http://<MGMT_PUBLIC_IP>:8080/github-webhook/` (trailing slash required)
- Content type: `application/json`
- Event: *Just the push event* → **Add webhook**

📸 **SS-25** webhook with green ✔ (Recent Deliveries → response 200)

---

## Step 11 – Validation: code change → auto build → auto deploy

1. On GitHub open `app/server.js` → edit line 6:
   ```js
   const APP_TITLE = 'Learning Management Platform - v2';
   ```
   Commit message: `Update title to v2`.

📸 **SS-26** GitHub commit (diff v1 → v2)

2. Jenkins starts build #2 by itself within seconds.

📸 **SS-27** Build #2 page showing **"Started by GitHub push by …"**  
📸 **SS-28** Stage View build #2 all green  
📸 **SS-29** Console output of stage 3 (`docker build … :2`) and stage 4 (push)  
📸 **SS-30** Docker Hub showing new tag `2`

3. Verify both servers run the new image:
```bash
ssh ubuntu@<APP1_PUBLIC_IP> "docker ps --format '{{.Names}} {{.Image}} {{.Status}}'"
ssh ubuntu@<APP2_PUBLIC_IP> "docker ps --format '{{.Names}} {{.Image}} {{.Status}}'"
```
📸 **SS-31** both show `<user>/lms-app:2`

4. Browser `http://<APP1_PUBLIC_IP>` and `http://<APP2_PUBLIC_IP>` (hard refresh Ctrl+F5).

📸 **SS-32** both pages: title **v2**, version **jenkins-build-2**, Database **CONNECTED**

---

## Troubleshooting (fast fixes)

| Problem | Fix |
|---|---|
| Terraform: *No valid credential sources* | IAM role not attached to mgmt server (EC2 → Actions → Security → Modify IAM role), wait 30 s |
| `t3.micro` not supported | `terraform apply -var instance_type=t2.micro` |
| Ansible `UNREACHABLE` | instances still booting – wait 1 min; check you ran `ssh-keygen` *before* terraform |
| App page shows *NOT CONNECTED* | `ansible-playbook db.yml` again; check `lms-db-sg` has 5432 from `lms-app-sg` |
| 502 Bad Gateway | container not running: `ssh ubuntu@IP docker logs lms-app` |
| Jenkins: `docker: permission denied` | `sudo systemctl restart jenkins` |
| Jenkins: `Host key verification failed` / `Permission denied (publickey)` | `sudo ls -l /var/lib/jenkins/.ssh/` – re-run `ansible-playbook jenkins.yml` |
| Push fails: *denied* | Docker Hub token must be Read & Write; `DOCKERHUB_USER` must match your username |
| Webhook red ✖ | port 8080 open in mgmt SG; URL ends with `/github-webhook/`; trigger checkbox ticked |
| Stage 7 fails on `jenkins-build-N` | browser cache only affects you; check `curl http://IP/health` from mgmt server |

## Cleanup (after submitting)

```bash
cd ~/lms-devops/terraform && terraform destroy -auto-approve
```
Then terminate the Management Server and delete the IAM role.

---

## 📸 Screenshot checklist (submit these)

| # | What | Section |
|---|---|---|
| SS-01 | GitHub repo with code | Setup |
| SS-02 | Management Server running (IAM role, SG) | Terraform |
| SS-03 | `terraform -version`, `ansible --version` | Terraform |
| SS-04 | `terraform init` | Terraform |
| SS-05 | `terraform apply` complete | Terraform |
| SS-06 | `terraform output` (IDs, public & private IPs) | Terraform |
| SS-07 | VPC, subnets, IGW, route table in console | Terraform |
| SS-08 | 3 EC2 instances running | Terraform |
| SS-09 | DB security group rules | Terraform |
| SS-10 | Passwordless SSH to 3 servers | Ansible |
| SS-11 | `ansible all -m ping` | Ansible |
| SS-12 | PostgreSQL listening + health = connected | Ansible |
| SS-13 | App → DB test (nc + psql) | Ansible |
| SS-14 | PLAY RECAP failed=0 | Ansible |
| SS-15 | App UI on both public IPs (v1, DB connected) | Ansible |
| SS-16 | `/health` JSON | Ansible |
| SS-17 | Manual ping / nc / psql / docker ps from app server | Validation |
| SS-18 | Jenkins installed via Ansible | Jenkins |
| SS-19 | Jenkins dashboard | Jenkins |
| SS-20 | `dockerhub-creds` credential | Jenkins |
| SS-21 | Pipeline job config (trigger + SCM) | Jenkins |
| SS-22 | Build #1 – 7 green stages | Jenkins |
| SS-23 | Build #1 console – SUCCESS + verification | Jenkins |
| SS-24 | Docker Hub image tags | Jenkins |
| SS-25 | GitHub webhook green ✔ | Jenkins |
| SS-26 | Code change commit (v1 → v2) | Validation |
| SS-27 | Build #2 "Started by GitHub push" | Validation |
| SS-28 | Build #2 stages green | Validation |
| SS-29 | New image build + push logs | Validation |
| SS-30 | Docker Hub new tag | Validation |
| SS-31 | `docker ps` on both app servers shows new tag | Validation |
| SS-32 | Updated app (v2) on both public IPs | Validation |

If you are short on time, the must-haves are: **SS-05, 06, 08, 11, 14, 15, 22, 25, 27, 31, 32**.
