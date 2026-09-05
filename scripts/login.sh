#!/bin/bash

STUDENT_PORTAL_URL="${1}"
STUDENT_PORTAL_USER_ID="${2}"
STUDENT_PORTAL_PASSWORD="${3}"
PHPSESSID_VALUE="${4}"

TS=$(date +%s%3N)

curl -s -X POST "${STUDENT_PORTAL_URL}/PortalManagementWeb/public/login/do?ts=${TS}" \
  --cookie "PHPSESSID=${PHPSESSID_VALUE}" \
  -d "user_id=${STUDENT_PORTAL_USER_ID}&user_pass=${STUDENT_PORTAL_PASSWORD}&login_school_code=OCA"
