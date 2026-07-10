#!/bin/bash

STUDENT_PORTAL_URL="${1}"
PHPSESSID_VALUE="${2}"
REASON="${3}"
DATE1="${4}"
PERIODS1="${5}"
DATE2="${6}"
PERIODS2="${7}"
DATE3="${8}"
PERIODS3="${9}"
DATE4="${10}"
PERIODS4="${11}"
DATE5="${12}"
PERIODS5="${13}"
IMAGE_NAME="${14}"
IMAGE_PATH="${15}"

TS=$(date +%s%3N)
URL="${STUDENT_PORTAL_URL}/PortalManagementWeb/public/studentapplicationdetail/regist?ts=${TS}"

MIME_TYPE=$(file --mime-type -b "${IMAGE_PATH}")
TMPFILE=$(mktemp)
echo -n "data:${MIME_TYPE};base64,$(base64 < "${IMAGE_PATH}" | tr -d '\n')" > "${TMPFILE}"

curl -X POST "${URL}" \
  -H "Referer: ${STUDENT_PORTAL_URL}" \
  -H "Referrer-Policy: strict-origin-when-cross-origin" \
  -H "Content-Type: multipart/form-data" \
  --cookie "PHPSESSID=${PHPSESSID_VALUE}" \
  -F "text_application_remarks=${REASON}" \
  -F "flex_free_item1=${DATE1}" \
  -F "flex_free_item2=${PERIODS1}" \
  -F "flex_free_item3=${DATE2}" \
  -F "flex_free_item4=${PERIODS2}" \
  -F "flex_free_item5=${DATE3}" \
  -F "flex_free_item6=${PERIODS3}" \
  -F "flex_free_item7=${DATE4}" \
  -F "flex_free_item8=${PERIODS4}" \
  -F "flex_free_item9=${DATE5}" \
  -F "flex_free_item10=${PERIODS5}" \
  -F "text_attached_image_file_name=${IMAGE_NAME}" \
  -F "studen_upload_image_inputlable_uploadfile=" \
  -F "x1=" \
  -F "y1=" \
  -F "w=" \
  -F "h=" \
  -F "hidden_exif_orientation=" \
  -F "mode=0" \
  -F "ad_sid=" \
  -F "application_code=8" \
  -F "upload_attached_image_base64=<${TMPFILE}"

rm -f "${TMPFILE}"
