#!/usr/bin/env bash
# Shared Gmail SMTP alert sender. Source this, then call:
#   send_email "subject" "body"
# Requires GMAIL_USER and GMAIL_APP_PASSWORD in the environment (from
# .env.healthcheck). Used by cron/healthcheck.sh and cron/watchdog_power.sh.
send_email() {
  python3 - "$1" "$2" <<'EOF'
import os, smtplib, sys
from email.mime.text import MIMEText

subject, body = sys.argv[1], sys.argv[2]
user = os.environ["GMAIL_USER"]
password = os.environ["GMAIL_APP_PASSWORD"]

msg = MIMEText(body)
msg["Subject"] = subject
msg["From"] = user
msg["To"] = user

with smtplib.SMTP("smtp.gmail.com", 587) as s:
    s.starttls()
    s.login(user, password)
    s.send_message(msg)
EOF
}
