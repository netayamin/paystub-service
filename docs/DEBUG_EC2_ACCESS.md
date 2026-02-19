# Can’t access EC2 (SSH or http://IP:8000)

Use this checklist in the **AWS Console** to fix access.

---

## Backend up but “can’t reach RDS” / health fails

If the backend container is running but **http://EC2_IP:8000/health** never loads or errors:

1. **EC2** → **Instances** → click the instance (e.g. 3.19.238.117) → **Security** tab. Note the **Security group ID** (e.g. `sg-06269d5246882d3a7`).
2. **RDS** → **Databases** → click **database-1** → **Connectivity & security**. Under **Security groups**, click the **VPC security group** that is attached to this DB (e.g. `ec2-rds-1` / `sg-07bba4bae26a214a7`). You must edit **the RDS security group**, not the EC2 one.
3. In that RDS security group → **Edit inbound rules** → **Add rule**:
   - **Type:** PostgreSQL
   - **Port:** 5432
   - **Source:** **Custom** → open the dropdown and choose **the EC2 instance’s security group** (the sg-xxx from step 1). Do *not* use the RDS security group here.
4. **Save** the rules. Wait ~10 seconds, then restart the backend:
   ```bash
   ssh -i ~/Downloads/dropfeed.pem ec2-user@3.19.238.117 "sudo docker restart paystub-backend"
   ```

Run from your Mac to test and restart:
```bash
EC2_IP=3.19.238.117 ./scripts/check-ec2-rds.sh
```

---

## 1. Instance is running and you have the right IP

- **EC2** → **Instances**.
- Find your backend instance (e.g. name `paystub-backend` or similar).
- **Instance state** must be **Running**. If it’s **Stopped**, select it → **Instance state** → **Start instance**.
- **Important:** After a stop/start, the **Public IPv4 address** can change unless you use an **Elastic IP**. Note the **current** public IP (e.g. `3.142.49.156` or a new one).

---

## 2. Security group allows SSH and 8000 **from your traffic**

- Click the instance → **Security** tab → click the **Security group** (e.g. `launch-wizard-3` or `sg-xxxxx`).
- Open **Inbound rules**. You should have:

  | Type       | Port | Source     |
  |-----------|------|------------|
  | SSH       | 22   | 0.0.0.0/0 (or your IP) |
  | Custom TCP| 8000 | 0.0.0.0/0 (or your IP) |

- If the instance uses a **different** security group (e.g. only “default”), edit **that** group and add the same rules.
- **Save** the rules.

---

## 3. This instance is using that security group

- On the instance’s **Security** tab, under **Security groups** you see which group(s) are attached.
- The group you edited in step 2 must be one of them. If the instance has only a group that has no SSH/8000 rules, add the correct group:
  - **Actions** → **Security** → **Change security groups** → add the group that has SSH + 8000 → Save.

---

## 4. SSH from your Mac

From Terminal (use the **current** public IP from step 1 and your key path):

```bash
ssh -i ~/Downloads/dropfeed.pem ec2-user@<PUBLIC_IP>
```

- **“Permission denied (publickey)”** → wrong key or wrong user. Use the `.pem` you chose when launching this instance; user is usually `ec2-user` (Amazon Linux) or `ubuntu` (Ubuntu).
- **“Connection timed out”** → port 22 not reachable: recheck step 2 and 3 (SSH rule, correct security group attached). If you’re on a corporate/school network, it may block outbound SSH; try from another network or hotspot.

---

## 5. Once SSH works, check the app on the instance

```bash
# Container running?
sudo docker ps -a

# Start if stopped
sudo docker start paystub-backend

# Health from inside the box
curl -s http://localhost:8000/health
```

If `curl` from inside EC2 returns `{"status":"ok"}` but the browser still can’t open `http://<PUBLIC_IP>:8000/health`, the security group for this instance is still not allowing port 8000 from the internet (recheck step 2 and 3).

---

## Quick recap

| Problem              | What to check |
|----------------------|----------------|
| No SSH, no 8000      | Instance running? Correct public IP? Security group has **22** and **8000** from 0.0.0.0/0? **That** group attached to the instance? |
| SSH works, 8000 no  | Inbound rule **Custom TCP 8000**, source 0.0.0.0/0, on the instance’s security group. |
| “Connection timed out” | Firewall/network blocking outbound 22 or 8000; or wrong security group / missing rules. |
