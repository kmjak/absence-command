#!/bin/bash

source "$(dirname "$0")/../.env"
bash "$(dirname "$0")/submit.sh" "$STUDENT_PORTAL_URL" "$STUDENT_PORTAL_PHPSESSID" "$@"