#!/usr/bin/env bash
# เลือก scenario ของ molecule ที่ต้องรัน จากไฟล์ที่เปลี่ยนใน commit / PR
#
# ใช้: detect-molecule-scenarios.sh <base-sha>
#   base-sha ว่าง / 0000... / หาไม่เจอ  -> รันทุก scenario
# พิมพ์ JSON array ของชื่อ scenario ออก stdout เช่น ["docker_engine"]
# เหตุผลของการเลือกพิมพ์ออก stderr
#
# กติกา (scenario ใช้ชื่อเดียวกับ role: molecule/<role>/molecule.yml)
#   roles/<role>/** หรือ molecule/<role>/**   -> scenario <role>
#   roles/docker_engine/**, molecule/docker_engine/**
#                                             -> ทุก scenario (ทุก role ต้องลง Docker ก่อน)
#   ไฟล์ที่กระทบสภาพแวดล้อมทดสอบ (ดู RUN_ALL_FILES) -> ทุก scenario
#   อย่างอื่น (playbooks/, docs/, README ...)  -> ไม่รัน
set -euo pipefail

base="${1:-}"

RUN_ALL_FILES=(
  .github/workflows/molecule.yml
  .github/scripts/detect-molecule-scenarios.sh
  requirements-ci.txt
  requirements-molecule.txt
  collections/requirements.yml
  molecule/requirements.yml
  ansible.cfg
)

all=$(find molecule -mindepth 2 -maxdepth 2 -name molecule.yml -printf '%h\n' | xargs -rn1 basename | sort -u)

to_json() { grep -v '^$' | sort -u | jq -R . | jq -sc .; }

if [[ -z "$base" || "$base" =~ ^0+$ ]] || ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
  echo "ไม่มี commit ให้เทียบ (${base:-ว่าง}) -> รันทุก scenario" >&2
  printf '%s\n' "$all" | to_json
  exit 0
fi

changed=$(git diff --name-only "$base" HEAD)
echo "ไฟล์ที่เปลี่ยนเทียบกับ ${base:0:7}:" >&2
printf '  %s\n' $changed >&2

selected=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  for g in "${RUN_ALL_FILES[@]}"; do
    if [[ "$f" == "$g" ]]; then
      echo "$f กระทบสภาพแวดล้อมทดสอบ -> รันทุก scenario" >&2
      printf '%s\n' "$all" | to_json
      exit 0
    fi
  done
  case "$f" in
    roles/docker_engine/* | molecule/docker_engine/*)
      echo "$f เป็นของ docker_engine ซึ่งทุก role พึ่ง -> รันทุก scenario" >&2
      printf '%s\n' "$all" | to_json
      exit 0
      ;;
    roles/*/* | molecule/*/*)
      selected+="$(cut -d/ -f2 <<<"$f")"$'\n'
      ;;
  esac
done <<<"$changed"

# เก็บเฉพาะ role ที่มี scenario จริง
result=$(printf '%s' "$selected" | sort -u | grep -Fx -f <(printf '%s\n' "$all") || true)
echo "scenario ที่จะรัน: ${result:-ไม่มี}" | tr '\n' ' ' >&2
echo >&2
printf '%s\n' "$result" | to_json
