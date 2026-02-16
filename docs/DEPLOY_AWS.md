# Deploy backend to AWS EC2 (cheapest: one server)

Run the backend + Postgres 24/7 on a single EC2 instance using your **$100 credits** (us-east-2 Ohio). This keeps cost minimal.

---

## Do it in 3 steps

**Step 1 – Launch EC2 (in AWS Console)**  
Go to **EC2** → **Launch instance**. Set:
- **Name:** `paystub-backend`
- **AMI:** Amazon Linux 2023
- **Instance type:** t2.micro
- **Key pair:** Create new or choose existing (download the `.pem` file)
- **Network / Security group:** Create security group, allow **SSH (22)** and **Custom TCP 8000** (source: Anywhere 0.0.0.0/0 for testing; restrict later)
- **Storage:** 8 GB  
Click **Launch instance**.

**Step 2 – SSH in**  
When the instance is running, copy its **Public IPv4 address**. From your Mac:

```bash
ssh -i /path/to/your-key.pem ec2-user@<PASTE_PUBLIC_IP_HERE>
```

**Step 3 – One command to deploy**  
Paste and run this on the EC2 (one block):

```bash
git clone https://github.com/netayamin/paystub-service.git && cd paystub-service && bash scripts/ec2-bootstrap.sh
```

Then add your secrets and restart:

```bash
nano backend/.env
# Set OPENAI_API_KEY=..., RESY_API_KEY=..., RESY_AUTH_TOKEN=...
sudo docker compose -f docker-compose.prod.yml restart backend
```

Your API will be at **http://\<EC2_PUBLIC_IP\>:8000** (and the script prints the URL). Use that as the base URL in the iOS app.

---

## Detailed steps (if you prefer)

### 1. Launch EC2 (us-east-2)

1. In AWS Console go to **EC2** → **Launch instance**.
2. **Name:** `paystub-backend` (or any).
3. **AMI:** Amazon Linux 2023 (or Ubuntu 22.04).
4. **Instance type:** **t2.micro** (free tier) or **t3.micro**.
5. **Key pair:** Create or select one; download the `.pem` and keep it safe.
6. **Network:** Allow **SSH (22)** and **HTTP (80)** or **Custom TCP 8000** so you can hit the API.  
   - For iOS/app testing, open **8000** (or put a small reverse proxy on 80 later).
7. **Storage:** 8 GB is enough.
8. Launch.

---

### 2. Connect and install Docker

```bash
# From your Mac (replace with your instance public IP and key path)
ssh -i /path/to/your-key.pem ec2-user@<EC2_PUBLIC_IP>
```

On the EC2 instance:

```bash
# Amazon Linux 2023
sudo dnf update -y
sudo dnf install -y docker
sudo systemctl enable docker && sudo systemctl start docker
sudo usermod -aG docker ec2-user
# Log out and back in so docker runs without sudo, or run next commands with sudo

# Install Docker Compose (plugin)
sudo dnf install -y docker-compose-plugin
# Or: sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && sudo chmod +x /usr/local/bin/docker-compose
```

---

### 3. Deploy the app

**Option A: Clone from Git**

```bash
git clone <your-repo-url> paystub-service
cd paystub-service
```

**Option B: Copy files** (e.g. with `scp -i key.pem -r backend ec2-user@<IP>:~/paystub-service/` and same for root files like `docker-compose.prod.yml`).

Then on the server:

```bash
cd paystub-service

# Create backend/.env with your real values (DB URL will be overridden by compose)
cp backend/.env.example backend/.env
nano backend/.env   # set OPENAI_API_KEY, RESY_API_KEY, RESY_AUTH_TOKEN

# Optional: set a stronger Postgres password for prod
export POSTGRES_PASSWORD=your_secure_password

# Build and run (backend + Postgres)
docker compose -f docker-compose.prod.yml up -d

# Check logs
docker compose -f docker-compose.prod.yml logs -f backend
```

When you see `BACKEND READY` in the logs, the API is up.

---

### 4. Use the API

- From the internet: `http://<EC2_PUBLIC_IP>:8000`
- Health: `http://<EC2_PUBLIC_IP>:8000/health`
- Docs: `http://<EC2_PUBLIC_IP>:8000/docs`

In your **iOS app**, set the base URL to `http://<EC2_PUBLIC_IP>:8000` (or use a domain and point it to this IP later).

---

### 5. Security (recommended soon)

- Prefer **HTTPS**: put Cloudflare in front, or an nginx + Let’s Encrypt on the same EC2.
- Restrict **Security Group**: allow 8000 (or 80/443) only from your IP or from Cloudflare.
- Keep **backend/.env** out of Git; create it only on the server.

---

### 6. Cost (with credits)

- **t2.micro**: free tier 750 h/month for 12 months; after that a few $/month.
- With **$100 credits**, running one t2.micro + a bit of storage and data should stay within credit for months.

To avoid surprise charges: set a **billing alert** in AWS (e.g. alert when forecast &gt; $5).
