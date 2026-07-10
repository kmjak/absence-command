#!/bin/bash

source "$(dirname "$0")/../.env"
bash "$(dirname "$0")/login.sh" "$STUDENT_PORTAL_URL" "$STUDENT_PORTAL_USER_ID" "$STUDENT_PORTAL_PASSWORD" "$STUDENT_PORTAL_PHPSESSID"
bash "$(dirname "$0")/submit.sh" "$STUDENT_PORTAL_URL" "$STUDENT_PORTAL_PHPSESSID" "$@"