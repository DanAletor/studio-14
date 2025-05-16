#!/bin/bash

# === CONFIG ===
APP_NAME="wordpress"
DB_PLUGIN="mysql"
DB_SERVICE_NAME="mysql"  
DB_NAME="mysql"          
BACKUP_DIR="/opt/backups/${APP_NAME}"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
S3_BUCKET="s3://webserverstudio"

# === Create local backup directory if it doesn't exist ===
mkdir -p "${BACKUP_DIR}"

# === Backup WordPress app files (uploads, plugins, etc.) ===
APP_BACKUP_PATH="${BACKUP_DIR}/${APP_NAME}_files_${DATE}.tar.gz"
tar -czf "$APP_BACKUP_PATH" /var/lib/dokku/data/storage/${APP_NAME}

# === Export the database ===
DB_BACKUP_PATH="${BACKUP_DIR}/${APP_NAME}_db_${DATE}.sql.gz"
dokku ${DB_PLUGIN}:export ${DB_SERVICE_NAME} | gzip > "$DB_BACKUP_PATH"

# === Upload backups to S3 ===
aws s3 cp "$APP_BACKUP_PATH" "${S3_BUCKET}/${APP_NAME}/files/"
aws s3 cp "$DB_BACKUP_PATH" "${S3_BUCKET}/${APP_NAME}/database/"

# === Clean up local backups older than 7 days ===
find "${BACKUP_DIR}" -type f -mtime +7 -exec rm {} \;

# === Log the backup ===
echo "[${DATE}] Backup complete and uploaded to S3: ${APP_BACKUP_PATH}, ${DB_BACKUP_PATH}" >> /var/log/${APP_NAME}_backup.log
