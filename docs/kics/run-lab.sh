#!/usr/bin/env bash
# KICS lab: พิสูจน์ว่า KICS ทำงานยังไง ด้วยการรันจริงกับ image ตัวเดียวกับใน CI
#
#   bash docs/kics/run-lab.sh
#
# ต้องมี docker + python3 เท่านั้น ไฟล์ทดสอบทั้งหมดสร้างใน temp dir
# (ไม่ได้ commit ไว้ใน repo เพราะจะทำให้ KICS/gitleaks/ansible-lint ใน CI แดง)
set -uo pipefail

KICS_IMAGE="${KICS_IMAGE:-checkmarx/kics@sha256:ef29dbac14b046b1ef65f3280646112e927a61781c5f01bca1aeb723e0b96003}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
CUSTOM_Q="$REPO/docs/kics/queries"
LAB="$(mktemp -d)"
trap 'rm -rf "$LAB"' EXIT
mkdir -p "$LAB"/{e1_high,e2_critical,e3_blindspot,e4_ignore,e6_file_ignore,e6_disable_id,out}

# ---------- fixtures ----------
cat > "$LAB/e1_high/secret.yml" <<'EOF'
- name: E1 hardcoded secret (HIGH)
  hosts: all
  tasks:
    - name: Create db user
      community.mysql.mysql_user:
        name: app
        password: "S3cr3tP@ssw0rd!2026" # gitleaks:allow (fake, lab only)
EOF

cat > "$LAB/e2_critical/rds.yml" <<'EOF'
- name: E2 public RDS (CRITICAL)
  hosts: localhost
  tasks:
    - name: Create RDS FQCN
      amazon.aws.rds_instance:
        db_instance_identifier: demo
        publicly_accessible: true
    - name: Create RDS short name
      rds_instance:
        db_instance_identifier: demo2
        publicly_accessible: true
EOF

cat > "$LAB/e3_blindspot/http.yml" <<'EOF'
- name: E3 same bug, different spelling
  hosts: all
  tasks:
    - name: A FQCN
      ansible.builtin.uri:
        url: "http://example.com/a"
    - name: B short name
      uri:
        url: "http://example.com/b"
    - name: C ansible.legacy
      ansible.legacy.uri:
        url: "http://example.com/c"
    - name: D get_url
      ansible.builtin.get_url:
        url: "http://example.com/d.tar.gz"
        dest: /tmp/d.tar.gz
    - name: E url via variable
      ansible.builtin.uri:
        url: "{{ base_url }}/e"
      vars:
        base_url: "http://example.com"
    - name: F validate_certs false
      ansible.builtin.uri:
        url: "https://example.com/f"
        validate_certs: false
EOF

cat > "$LAB/e4_ignore/http.yml" <<'EOF'
- name: E4 ignore mechanism
  hosts: all
  tasks:
    - name: Ignored by line comment
      ansible.builtin.uri:
        # kics-scan ignore-line
        url: "http://example.com/ignored"
    - name: Not ignored
      ansible.builtin.uri:
        url: "http://example.com/reported"
EOF

# ansible.cfg ที่มี HIGH (allow_unsafe_lookups) + ignore 2 แบบ
printf '# kics-scan ignore\n[defaults]\nallow_unsafe_lookups = True\n' > "$LAB/e6_file_ignore/ansible.cfg"
printf '# kics-scan disable=c6473dae-8477-4119-88b7-b909b435ce7b\n[defaults]\nallow_unsafe_lookups = True\n' > "$LAB/e6_disable_id/ansible.cfg"

# ---------- helpers ----------
# run <ชื่อ> <path ใน container> [args...]  -> พิมพ์ exit code + findings
run() {
  local name=$1 target=$2; shift 2
  docker run --rm -v "$LAB:/lab" -v "$REPO:/src:ro" -v "$CUSTOM_Q:/custom:ro" "$KICS_IMAGE" \
    scan -p "$target" --type ansible --no-progress --no-color \
    -o "/lab/out/$name" --report-formats json "$@" > "$LAB/out/$name.log" 2>&1
  local rc=$?
  echo "### $name  ($*)"
  echo "    exit code = $rc"
  python3 - "$LAB/out/$name/results.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
c = d["severity_counters"]
print("    counters  =", {k: c[k] for k in ("CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO")})
for q in d["queries"]:
    for f in q["files"]:
        print(f"    {q['severity']:<8} {q['query_name']}  ->  {f['file_name'].split('/')[-1]}:{f['line']}  [{f.get('resource_name','')}]")
PY
  echo
}

echo "KICS image: $KICS_IMAGE"
docker run --rm "$KICS_IMAGE" version
echo

echo "===== 0) ข้างในมี query อะไรบ้าง ====="
docker run --rm --entrypoint sh "$KICS_IMAGE" -c '
  for d in /app/bin/assets/queries/ansible/*/; do printf "  %-8s %s queries\n" "$(basename $d)" "$(ls $d | wc -l)"; done
  echo "  --- ตัวอย่าง Rego: communication_over_http ---"
  sed "s/^/  | /" /app/bin/assets/queries/ansible/general/communication_over_http/query.rego'
echo

echo "===== 1) exit code เมื่อเจอ HIGH ====="
run e1_high /lab/e1_high --fail-on high

echo "===== 2) --fail-on high ไม่ได้แปลว่า 'high ขึ้นไป' ====="
run e2_all       /lab/e2_critical --fail-on high
run e2_crit_only /lab/e2_critical --fail-on high --exclude-severities high,medium,low,info
run e2_crit_fix  /lab/e2_critical --fail-on critical,high --exclude-severities high,medium,low,info

echo "===== 3) blind spot: query จับแค่ module key ที่เขียนไว้ใน Rego ====="
run e3 /lab/e3_blindspot --fail-on critical,high

echo "===== 4) ignore ด้วย comment ====="
run e4 /lab/e4_ignore --fail-on critical,high

echo "===== 4b) ignore ทั้งไฟล์ vs disable เฉพาะ query id ====="
run e6_file_ignore /lab/e6_file_ignore --fail-on critical,high
run e6_disable_id  /lab/e6_disable_id  --fail-on critical,high

echo "===== 5) custom query (docs/kics/queries) ====="
run e5_lab  /lab/e3_blindspot -q /app/bin/assets/queries -q /custom --fail-on critical,high
run e5_repo /src --exclude-paths /src/collections/ansible_collections \
  -q /app/bin/assets/queries -q /custom --fail-on critical,high

echo "===== 6) payload: ข้อมูลที่ Rego เห็นจริงๆ (ไฟล์ roles/verify/tasks/main.yml) ====="
docker run --rm -v "$LAB:/lab" -v "$REPO:/src:ro" "$KICS_IMAGE" scan -p /src/roles/verify --type ansible \
  --no-progress --silent -o /lab/out/payload --payload-path /lab/out/payload.json >/dev/null 2>&1
python3 -c "import json,sys; print(json.dumps(json.load(open(sys.argv[1])), indent=2))" "$LAB/out/payload.json"
