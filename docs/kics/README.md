# KICS: ไส้ในและหลักฐานการทำงาน

ทุกผลในหน้านี้ได้จากการรันจริงกับ image ตัวเดียวกับที่ pin ไว้ใน `.github/workflows/ansible-ci.yml`
(`checkmarx/kics@sha256:ef29dbac…` = **KICS v2.2.0**) ถ้าจะรันซ้ำเอง:

```bash
bash docs/kics/run-lab.sh
```

ใช้แค่ docker กับ python3 ไฟล์ทดสอบถูกสร้างใน temp dir แล้วลบทิ้ง ไม่มีไฟล์ไหนค้างใน repo

---

## 1. KICS ทำงานยังไง (pipeline ข้างใน)

```
 ไฟล์ใน repo ──► [1] Provider ──► [2] Parser ──► [3] Payload (JSON) ──► [4] Rego engine (OPA) ──► [5] Results ──► [6] Exit code
                 เดินหาไฟล์        YAML/INI       รวมเป็น input.document   query.rego × 287 ตัว       json/sarif         ตาม --fail-on
                 ใช้ .gitignore    → object       1 ไฟล์ = 1 document      CxPolicy[result]
                 + --exclude-paths
```

| ขั้น | เกิดอะไรขึ้น | หลักฐานจาก log (`-v`) |
|---|---|---|
| 1 Provider | เดินหาไฟล์ทั้งโปรเจกต์ ตัดตาม `.gitignore` และ `--exclude-paths` | `Total files in the project: 120` → scan จริงแค่ 20 ไฟล์ (ตัด `collections/` ออก) |
| 2 Parser | แปลง YAML (playbook/role) และ INI (`ansible.cfg`, inventory) เป็น object | `files_parsed: 18` และ `ERR failed to parse … proxy.conf` (ไฟล์ nginx ถูกเดาเป็น INI แล้ว parse ไม่ผ่าน ไม่มีผลต่อ exit code) |
| 3 Payload | ทุกไฟล์รวมเป็น JSON ก้อนเดียว `{"document":[…]}` ดูได้ด้วย `--payload-path` | ดูหัวข้อ 2 |
| 4 Engine | โหลด query ตาม `--type ansible` (226 ตัวของ Ansible + 61 ตัวกลาง เช่น secrets) แล้วรัน Rego กับ payload | `Inspector initialized, number of queries=287` |
| 5 Results | แต่ละ query คืน `documentId` + `searchKey` แล้ว KICS map กลับเป็นไฟล์:บรรทัด | `results.json`, `results.sarif` (upload เป็น artifact ใน CI) |
| 6 Exit code | ดูจาก severity ที่เจอ **เฉพาะที่อยู่ใน `--fail-on`** | `60`=CRITICAL `50`=HIGH `40`=MEDIUM `30`=LOW `20`=INFO `0`=ผ่าน |

query ทั้งหมดอยู่ใน image ที่ `/app/bin/assets/queries/ansible/` และแบ่งตามหมวดแบบนี้:

| หมวด | จำนวน | ใช้กับ repo นี้ไหม |
|---|---|---|
| aws / azure / gcp | 126 / 40 / 49 | ไม่ใช้ (repo นี้ไม่ได้ provision cloud) |
| general | 6 | ใช้ (http, become, file mode, no_log, unpinned package, relative path) |
| config | 4 | ใช้ (`ansible.cfg`) |
| hosts | 1 | ใช้ (inventory) |

> สรุปคือกฎเกือบ 95% เป็นของ cloud ส่วนที่ตรวจ repo แบบนี้จริงๆ มี **แค่ 11 query**

## 2. Payload: สิ่งที่ Rego "เห็น" จริงๆ

`roles/verify/tasks/main.yml` หลัง parse แล้วจะกลายเป็นแบบนี้ (ตัดมาบางส่วน):

```json
{
  "document": [{
    "file": "/src/roles/verify/tasks/main.yml",
    "id": "33084a7b-…",
    "playbooks": [
      {
        "name": "Check nginx is responding",
        "ansible.builtin.uri": { "url": "http://127.0.0.1:82/nginx_status", "status_code": 200 }
      }
    ]
  }]
}
```

จุดสำคัญคือ **ชื่อ module กลายเป็น key ของ object** ดังนั้น `uri:` กับ `ansible.builtin.uri:` เป็นคนละ key กัน

## 3. Query: กฎหนึ่งข้อหน้าตาเป็นยังไง

`queries/ansible/general/communication_over_http/query.rego` (ของจริงใน image):

```rego
CxPolicy[result] {
    task := ansLib.tasks[id][t]              # วนทุก task ทุก document (lib ช่วยแตก block/rescue/always)
    modules := {"ansible.builtin.uri"}       # ← จับแค่ key นี้ key เดียว
    builtin_uri := task[modules[m]]
    ansLib.checkState(builtin_uri)           # ข้ามถ้า state: absent
    startswith(builtin_uri.url, "http://")   # เงื่อนไขจริง
    result := { "documentId": id, "searchKey": "name={{…}}.{{ansible.builtin.uri}}.url", … }
}
```

ทุกเงื่อนไขในบล็อกต้องเป็นจริงทั้งหมด (AND) ถึงจะได้ `result` ออกมา ส่วน severity/CWE ไม่ได้อยู่ใน Rego แต่อยู่ใน `metadata.json` ข้างๆ กัน

## 4. การทดลอง (ผลจริงจาก `run-lab.sh`)

### E1: เจอ HIGH แล้ว pipeline แดง ✅

```
--fail-on high   →  exit 50
HIGH  Passwords And Secrets - Generic Password  ->  secret.yml:7
```

### E2: `--fail-on high` **ไม่** ครอบคลุม CRITICAL ⚠️ (เป็น bug ที่เจอใน workflow เดิม)

| ไฟล์ทดสอบ | flag | exit |
|---|---|---|
| มีทั้ง CRITICAL + HIGH | `--fail-on high` | 50 (แดง แต่แดงเพราะมี HIGH) |
| มีแค่ CRITICAL | `--fail-on high` | **0 (ผ่าน!)** |
| มีแค่ CRITICAL | `--fail-on critical,high` | 60 |

`--fail-on` คือ **รายการ severity** ไม่ใช่ threshold ที่นับ "ตั้งแต่ high ขึ้นไป" → **แก้ workflow แล้วเป็น `--fail-on critical,high`**

### E3: Blind spot เพราะ query จับจากชื่อ key ⚠️

เขียนบั๊กเดียวกัน (HTTP ที่ไม่เข้ารหัส) 6 แบบ:

| task | เขียนยังไง | KICS เจอไหม |
|---|---|---|
| A | `ansible.builtin.uri` + `http://` | ✅ MEDIUM |
| B | `uri` (ชื่อสั้น) | ❌ |
| C | `ansible.legacy.uri` | ❌ |
| D | `ansible.builtin.get_url` + `http://` | ❌ (เจอแค่ INFO เรื่อง file mode) |
| E | url มาจากตัวแปร `{{ base_url }}` | ❌ (KICS ไม่ render Jinja) |
| F | `validate_certs: false` | ❌ (ไม่มี query นี้เลย) |

ฝั่ง AWS กลับกัน: query RDS เขียนไว้ว่า `{"community.aws.rds_instance","rds_instance",…}` แต่ไม่มี `amazon.aws.rds_instance`
ซึ่งเป็น FQCN ปัจจุบันที่ ansible-lint (`fqcn` rule) บังคับให้ใช้ ผลคือ task ที่เขียนถูกตาม lint **ไม่โดนตรวจ**

> แปลว่า "KICS ผ่าน" ไม่ได้แปลว่า "ปลอดภัย" แต่แปลว่า "ไม่ตรง pattern ที่มีใน query" เท่านั้น

### E4: ignore ด้วย comment

```yaml
- name: Ignored by line comment
  ansible.builtin.uri:
    # kics-scan ignore-line
    url: "http://example.com/ignored"     # ← ไม่ถูกรายงาน
```

ใช้ได้ (มีแบบอื่นด้วย เช่น `# kics-scan ignore-block` และ `# kics-scan disable=<query-id>`) ถ้าใช้ควรใส่เหตุผลกำกับทุกครั้ง

### E5: เขียน custom query เองได้

`docs/kics/queries/uri_validate_certs_disabled/` (Rego + metadata ไฟล์ละไม่กี่บรรทัด) ปิดช่องโหว่ข้อ F และครอบคลุมชื่อ module ทั้ง 3 แบบ
โหลดคู่กับ query มาตรฐานด้วย `-q /app/bin/assets/queries -q /custom`

```
lab:   HIGH  TLS Certificate Validation Disabled (lab custom)  ->  http.yml:25 [F validate_certs false]
repo:  HIGH × 13   (portainer_server, portainer_agent, verify, debugs/*)
```

ใน repo จริงเจอ 13 จุด ทั้งหมดเป็นการยิง Portainer API ที่ `https://127.0.0.1:9443` ซึ่งใช้ self-signed cert
**query นี้ยังไม่ได้เปิดใน CI** เพราะถ้าเปิดตอนนี้ CI จะแดงทันที ต้องตัดสินใจกันก่อนว่าจะ (ก) ลดเป็น MEDIUM เพื่อดูเฉยๆ (ข) ignore รายจุดพร้อมเหตุผล หรือ (ค) แก้ให้ validate cert จริง

## 5. ผลกับ repo นี้ตอนนี้ (query มาตรฐาน)

| Severity | Query | ตำแหน่ง | ความเห็น |
|---|---|---|---|
| MEDIUM | Communication Over HTTP | `roles/verify/tasks/main.yml:10` | `http://127.0.0.1:82/nginx_status` เป็น localhost รับได้ |
| LOW | Logging of Sensitive Data In Defaults | `ansible.cfg:1` | ไม่ได้ตั้ง `no_log` เป็น default |

CI ผ่าน (exit 0) เพราะไม่มี CRITICAL/HIGH

## 6. สรุปสำหรับ workflow

- [x] แก้ `--fail-on high` → `--fail-on critical,high`
- [x] pin image ด้วย digest (มีอยู่แล้ว)
- [x] เก็บ `results.json` / `results.sarif` เป็น artifact (มีอยู่แล้ว)
- [ ] ตัดสินใจเรื่อง custom query `validate_certs` (ข้อ E5)
- [ ] (ทางเลือก) upload SARIF เข้า GitHub code scanning ด้วย `github/codeql-action/upload-sarif` ต้องเพิ่ม permission `security-events: write`
- ข้อจำกัดที่ควรรู้: KICS เป็น pattern matcher บน YAML ที่ยังไม่ได้ render ไม่ได้เข้าใจ Jinja, role defaults หรือ module alias ควรใช้คู่กับ ansible-lint และการ review ไม่ใช่ใช้แทน
