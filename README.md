# studio-24

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













