#!/usr/bin/env bash
# เขียนสรุปผล KICS และ Checkov ลง GitHub step summary แยกส่วนกัน
# ใช้ใน job "3. IaC scan" ของ ansible-ci.yml
#   KICS_OUTCOME / CHECKOV_OUTCOME = outcome ของ step (success | failure | skipped)
#   ไฟล์ผล: scan-results/kics/results.json, scan-results/checkov.sarif
set -uo pipefail

out="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
kics_json="scan-results/kics/results.json"
checkov_sarif="scan-results/checkov.sarif"

status() {
  case "$1" in
    success) echo "✅ ผ่าน" ;;
    failure) echo "❌ ไม่ผ่าน" ;;
    *) echo "⏭️ ไม่ได้รัน" ;;
  esac
}

{
  # ---------- KICS ----------
  echo "## KICS"
  if [ -f "$kics_json" ]; then
    found=$(jq '.total_counter // 0' "$kics_json")
    skipped=$(grep -rhoE '# kics-scan (ignore-line|ignore-block|disable=[^ ]+)' roles playbooks tasks ansible.cfg 2>/dev/null | wc -l)
    echo "$(status "${KICS_OUTCOME:-}") · พบ $found · ข้าม $skipped"
    echo
    if [ "$found" -gt 0 ]; then
      echo "| ระดับ | ปัญหา | ไฟล์:บรรทัด |"
      echo "|---|---|---|"
      jq -r '
        (.queries // [])
        | sort_by({"CRITICAL":0,"HIGH":1,"MEDIUM":2,"LOW":3,"INFO":4}[.severity])
        | .[] | . as $q | .files[]
        | "| \($q.severity) | \($q.query_name) | `\(.file_name | sub("^(\\.\\./)*/?src/"; "")):\(.line)` |"
      ' "$kics_json"
    else
      echo "ไม่มีปัญหา"
    fi
  else
    echo "$(status "${KICS_OUTCOME:-}") · ไม่มีไฟล์ผล"
  fi

  echo
  echo "---"
  echo

  # ---------- Checkov ----------
  echo "## Checkov"
  if [ -f "$checkov_sarif" ]; then
    found=$(jq '[.runs[].results[] | select((.suppressions // []) | length == 0)] | length' "$checkov_sarif")
    skipped=$(jq '[.runs[].results[] | select((.suppressions // []) | length > 0)] | length' "$checkov_sarif")
    echo "$(status "${CHECKOV_OUTCOME:-}") · พบ $found · ข้าม $skipped"
    echo
    if [ "$found" -gt 0 ]; then
      echo "| Check ID | ปัญหา | ไฟล์:บรรทัด |"
      echo "|---|---|---|"
      jq -r '
        .runs[].results[]
        | select((.suppressions // []) | length == 0)
        | .locations[0].physicalLocation as $l
        | "| \(.ruleId) | \(.message.text) | `\($l.artifactLocation.uri):\($l.region.startLine)` |"
      ' "$checkov_sarif"
    else
      echo "ไม่มีปัญหา"
    fi
  else
    echo "$(status "${CHECKOV_OUTCOME:-}") · ไม่มีไฟล์ผล"
  fi
} >> "$out"
