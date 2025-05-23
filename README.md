# studio-14

## 1. Environment Setup

The environment was provisioned on a remote EC2 instance hosted on Amazon Web Services (AWS). Below are the setup details and steps taken:

### Provisioning Details

* Cloud Provider: AWS
* Instance Type: t2.medium
* Operating System: Ubuntu 22.04 LTS
* Instance Name (Tag): studio-14-devops
* SSH Access: Restricted to key-based authentication only
* Firewall: Configured with a security group allowing HTTP (80), HTTPS (443), and SSH (22) from trusted IPs

### Hostname Configuration

* Public Domain: `https://studio14.danaletordaniela.com/`
* This domain points to the EC2 instance's public IP using A-records configured in Route 53 (or a DNS provider)

### Dokku Installation and Setup

* Dokku was installed using the official installation script:

  ```bash
  wget https://dokku.com/install/v0.30.1/bootstrap.sh
  sudo DOKKU_TAG=v0.30.1 bash bootstrap.sh
  ```
* Global domain was set using:

  ```bash
  dokku domains:set-global studio14.danaletordaniela.com
  ```
* Dokku manages application deployments using Docker as the backend.

### SSL Configuration

* Let's Encrypt was used to secure the domain with HTTPS.
* SSL certificates were generated and installed using:

  ```bash
  dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git
  dokku letsencrypt:enable <app-name>
  ```
* A cron job was also set to renew certificates automatically:

  ```bash
  dokku letsencrypt:cron-job --add
  ```

This completed the setup of a secure, production-ready deployment environment.





## 2. Sample Application Deployment

The sample application deployed is a generic **WordPress** instance, using **Dokku** and **Docker** as the application platform and container engine respectively. Below is the step-by-step deployment process.

### Step 1: Download and Extract WordPress

Download WordPress from the official website:

```bash
wget https://wordpress.org/latest.tar.gz
tar -xzvf latest.tar.gz
cd wordpress
```

### Step 2: Prepare a Git Repository

WordPress is not a Git repository by default. Create one:

```bash
git init
git add .
git commit -m "Initial WordPress commit"
```

### Step 3: Create the Dokku App

Connect to your EC2 instance via SSH, then run:

```bash
dokku apps:create wordpress
```

### Step 4: Set Domain for the App

```bash
dokku domains:add wordpress studio14.danaletordaniela.com
```

### Step 5: Install and Configure MySQL

Create a MySQL container for the WordPress app:

```bash
dokku plugin:install https://github.com/dokku/dokku-mysql.git mysql
dokku mysql:create wordpress-db
dokku mysql:link wordpress-db wordpress
```

This links the MySQL container to the app and sets the required `DATABASE_URL` environment variable.

### Step 6: Deploy WordPress via Git

On your local machine, add the Dokku remote:

```bash
git remote add dokku dokku@studio14.danaletordaniela.com:wordpress
```

Push the code to deploy:

```bash
git push dokku master
```

Dokku will automatically detect the PHP environment, build the Docker image, and run the app.

### Step 7: Enable Let's Encrypt SSL

```bash
dokku letsencrypt:enable wordpress
```

To keep the certificate up-to-date:

```bash
dokku letsencrypt:cron-job --add
```

### Step 8: Verify Deployment

Visit the application in your browser at:

```
https://studio14.danaletordaniela.com
```

You should see the WordPress installation screen. Proceed with the setup (language, site name, admin credentials, etc.).

---

This section confirms that the WordPress app was successfully containerized, deployed with Dokku, connected to a MySQL database, and served securely via HTTPS. 






## 3. CI/CD Pipeline

A GitHub Actions workflow was implemented to automate deployment of the WordPress application to the Dokku server hosted at `studio14.danaletordaniela.com`. This pipeline handles building, deploying on push to the `main` branch, and rolling back automatically in case of a deployment failure.

### Overview of Workflow

* **Trigger**: Pushes to the `main` branch.
* **Environment Variables**:

  * `DOKKU_HOST`: Set to the domain of the Dokku server.
  * `DOKKU_APP`: The name of the app on Dokku (`wordpress`).

---

### Step-by-Step Breakdown

#### 1. **Trigger Configuration**

```yaml
on:
  push:
    branches:
      - main
```

The workflow is triggered automatically whenever a push is made to the `main` branch.

---

#### 2. **Build Job**

```yaml
jobs:
  build:
    name: Build (checkout)
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
```

* This job checks out the repository code so it’s ready for deployment.
* Although the app doesn't require compilation, the checkout step is necessary for later deployment.

---

#### 3. **Deploy Job**

```yaml
  deploy:
    name: Deploy to Dokku
    runs-on: ubuntu-latest
    needs: build
```

* This job runs after the `build` step and pushes the latest code to the Dokku server.

##### Steps:

* **Checkout Repo Again**:
  Ensures the full Git history is available (important for rolling back).

  ```yaml
  with:
    fetch-depth: 0
  ```

* **Set Up SSH Access**:
  Sets up private SSH key from GitHub Secrets for authentication with the remote server.

  ```bash
  mkdir -p ~/.ssh
  echo "${{ secrets.DOKKU_SSH_KEY }}" > ~/.ssh/id_rsa
  chmod 600 ~/.ssh/id_rsa
  ssh-keyscan ${{ env.DOKKU_HOST }} >> ~/.ssh/known_hosts
  ```

* **Push to Dokku**:
  Adds the Dokku remote and pushes the current HEAD to the `main` branch on the server.

  ```bash
  git remote add dokku dokku@${{ env.DOKKU_HOST }}:${{ env.DOKKU_APP }} || true
  git push dokku HEAD:main
  ```

---

#### 4. **Rollback Job**

```yaml
  rollback:
    name: Rollback on Deploy Failure
    if: ${{ failure() }}
```

* This job runs **only if the `deploy` step fails**.
* It attempts to roll back the app on Dokku to the previous stable commit.

##### Steps:

* **Start SSH Agent**:
  Uses the private key again via the `ssh-agent` GitHub Action.

* **Add Host to Known Hosts**:
  Ensures that SSH doesn't prompt for confirmation during connection.

* **Determine Rollback Reference**:
  Attempts to find the previously deployed tag or defaults to `HEAD~1`.

  ```bash
  if [ -n "${{ needs.deploy.outputs.deployed_tag }}" ]; then
    # use the previous tag
  else
    # fallback to HEAD~1
  fi
  ```

* **Perform Rollback**:
  Pushes the fallback Git reference to Dokku using `--force`, effectively rolling back the deployment.

---

### Notes

* **Security**: All SSH communication is handled via encrypted GitHub secrets.
* **Simplicity**: Dokku acts as a lightweight PaaS, so a Dockerfile or custom build step wasn’t necessary.
* **Resilience**: The pipeline includes a simple rollback mechanism that ensures availability if a bad deployment is pushed.





## 4. Monitoring and Alerts

Prometheus and Grafana were installed using standalone Docker containers to monitor the server where the WordPress application is hosted. The setup collects and visualizes metrics such as:

* **CPU Usage**
* **Memory Usage**
* **Disk Usage**
* **Application Uptime**

---

### 🔧 Installation and Setup

#### **1. Node Exporter (System Metrics Collector)**

Node Exporter is used to collect host metrics like CPU, memory, and disk stats.

```bash
docker run -d \
  --name=node-exporter \
  --restart=always \
  -p 9100:9100 \
  -v "/proc:/host/proc:ro" \
  -v "/sys:/host/sys:ro" \
  -v "/:/rootfs:ro" \
  prom/node-exporter \
  --path.procfs=/host/proc \
  --path.rootfs=/rootfs \
  --path.sysfs=/host/sys
```

> Metrics are exposed at: `http://15.236.140.231:9100/metrics`

---

#### **2. Prometheus**

Prometheus scrapes and stores the metrics from Node Exporter.

Create a Prometheus config file on your server at `/root/prometheus.yml` with the following content:

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['15.236.140.231:9100']
```

Then run Prometheus:

```bash
docker run -d \
  --name=prometheus \
  --restart=always \
  -p 9090:9090 \
  -v /root/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus
```

> Prometheus dashboard available at: `http://15.236.140.231:9090`

---

#### **3. Grafana**

Grafana is used to visualize the metrics collected by Prometheus.

```bash
docker run -d \
  --name=grafana \
  --restart=always \
  -p 3000:3000 \
  grafana/grafana
```

> Grafana dashboard: `http://15.236.140.231:3000`
> Default credentials: `admin / admin`

---

### 📈 Dashboard Setup

1. Open Grafana at `http://15.236.140.231:3000`
2. Login and go to **Configuration → Data Sources**
3. Add Prometheus with the URL: `http://15.236.140.231:9090`
4. Import Dashboard ID `1860` ("Node Exporter Full") from Grafana.com
5. You will see:

   * Real-time CPU, memory, disk, and uptime charts

---

### 🚨 Alert Configuration (CPU > 80%)

To configure a CPU alert inside **Prometheus**, modify the `/root/prometheus.yml` and include:

```yaml
groups:
  - name: node_alerts
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100) > 80
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage exceeded 80% for more than 1 minute."
```

Then restart Prometheus:

```bash
docker restart prometheus
```

---

###  Result

* Node Exporter, Prometheus, and Grafana successfully monitor system metrics
* Alert triggers if CPU usage exceeds 80%
* Dashboards are live and accessible via:

  * Prometheus: [http://15.236.140.231:9090](http://15.236.140.231:9090)
  * Grafana: [http://15.236.140.231:3000](http://15.236.140.231:3000)
  * Node Exporter: [http://15.236.140.231:9100/metrics](http://15.236.140.231:9100/metrics)






## 5.Security and Backups

### Automated Daily Backup Script

A `backup.sh` script was created to automate daily backups of both the WordPress application data and its associated MySQL database. The script performs the following:

#### Breakdown of the Script:

1. **Configuration**

   * Defines variables for application name, database plugin, backup directory, and S3 bucket path.

2. **Creates Local Backup Directory**

   * Ensures `/opt/backups/wordpress` exists for storing backups locally.

3. **Backs Up WordPress Files**

   * Archives and compresses the WordPress storage directory (`/var/lib/dokku/data/storage/wordpress`) into a timestamped `.tar.gz` file.

4. **Exports the MySQL Database**

   * Uses `dokku mysql:export` to dump the database, piping it through `gzip` for compression.

5. **Uploads to AWS S3**

   * Uploads both the app files and database dump to the specified S3 bucket (`s3://webserverstudio/wordpress`).

6. **Cleans Up Old Backups**

   * Deletes any local backup files older than 7 days.

7. **Logs Backup Results**

   * Logs the backup operation with timestamps to `/var/log/wordpress_backup.log`.

> Script path: `backup.sh`
> Schedule: Intended to be run via `cron` once per day.

#### Crontab Entry (for daily execution at 2 AM):

```bash
0 2 * * * /bin/bash /path/to/backup.sh
```

---

### Restore Instructions

To restore from a backup:

1. **Download backup files from S3**:

   ```bash
   aws s3 cp s3://webserverstudio/wordpress/files/wordpress_files_<timestamp>.tar.gz /tmp/
   aws s3 cp s3://webserverstudio/wordpress/database/wordpress_db_<timestamp>.sql.gz /tmp/
   ```

2. **Restore WordPress Files**:

   ```bash
   tar -xzf /tmp/wordpress_files_<timestamp>.tar.gz -C /var/lib/dokku/data/storage/wordpress/
   ```

3. **Restore Database**:

   ```bash
   gunzip < /tmp/wordpress_db_<timestamp>.sql.gz | dokku mysql:import mysql
   ```

4. **Restart the application**:

   ```bash
   dokku ps:restart wordpress
   ```

---

### SSH Access Restrictions

The server has been hardened to allow only SSH key-based access:

* Password-based logins have been disabled by modifying `/etc/ssh/sshd_config`:

  ```ini
  PasswordAuthentication no
  PermitRootLogin no
  ```

* SSH access is restricted to known key holders. The SSH daemon was restarted using:

  ```bash
  sudo systemctl restart ssh
  ```

These measures prevent brute-force and unauthorized access.


H**Cloud Processes and Scalability Improvements**:


## What could be Improved for Studio 14 Current Infrastructure Plan.

Studio 14’s current infrastructure runs WordPress on a dedicated server, which involves manual management and operational overhead. To enhance scalability, reduce costs, and simplify operations, I recommend migrating the application to **Azure App Service** and leveraging Azure’s native monitoring and alerting tools. This approach addresses key areas:

1. **Costs**
   Dedicated servers come with ongoing expenses like hardware, bandwidth, and maintenance. Migrating to Azure App Service allows us to eliminate these costs entirely by applying for the **Azure Founders Hub program**, which offers up to **\$150,000 in Azure credits** for qualifying startups. This effectively reduces hosting costs to zero.

2. **Simplicity and Operational Efficiency**
   Managing a server requires manual patching, backups, and scaling efforts. Azure App Service is a fully managed platform that automates infrastructure management, patching, backups, and scaling. This significantly reduces manual effort and operational complexity.

3. **Scalability and High Availability**
   Dedicated servers have limited scalability and require manual upgrades. Azure App Service provides built-in automatic scaling and high availability to ensure the application can handle traffic spikes and maintain uptime seamlessly.

4. **Monitoring, Alerts, and Visualization**
   Using Prometheus and Grafana adds complexity in managing separate tools and configurations. Azure Monitor consolidates metrics, logging, alerting, and dashboards into a single platform integrated with Azure App Service. This streamlines monitoring and alerting, providing real-time notifications via Azure Alerts without additional software overhead.

By adopting Azure App Service and Azure Monitor, Studio 14 will benefit from simplified infrastructure management, zero hosting costs with Azure credits, seamless scalability and high availability, and unified monitoring and alerting—all contributing to a more robust and efficient cloud solution.


















