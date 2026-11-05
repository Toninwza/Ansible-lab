# Security scan flow (atrium · Ansible)

มี 2 workflow

| workflow | รันเมื่อ | job |
|---|---|---|
| Ansible CI (`ansible-ci.yml`) | ทุก push และ PR เข้า main | 1. Lint, 2. Secrets, 3. IaC scan, 4. Molecule (เฉพาะ role ที่เปลี่ยน) |
| Ansible Full Scan (`full-scan.yml`) | กดรันเองเท่านั้น | 2. Molecule ทุก role, 3. Image CVEs, 4. Python CVEs |

| ชั้น | ตรวจอะไร | อยู่ที่ไหน | ทำ CI แดง? |
|---|---|---|---|
| 1. คุณภาพโค้ด | best practice ของ Ansible, YAML, syntax (ansible-lint ทำ syntax-check ให้ด้วย) | CI › 1. Lint: ansible-lint, yamllint | ✅ |
| 2. ตัว workflow เอง | ช่องโหว่ของ GitHub Actions (token ค้าง, script injection) | CI › 1. Lint: zizmor | ✅ |
| 3. dependency ต้อง pin | pip ต้องเป็น `==`, galaxy collection ต้องเป็น x.y.z | CI › 1. Lint | ✅ |
| 4. secret | password/token ในโค้ดและ git history, vault ที่ลืมเข้ารหัส | CI › 2. Secrets: gitleaks | ✅ |
| 5. config ไม่ปลอดภัย | http, `validate_certs: false`, ลายเซ็นแพ็กเกจ, ค่าใน `ansible.cfg` | CI › 3. IaC scan: KICS + Checkov | ✅ CRITICAL/HIGH |
| 6. ผลหลังรันจริง | role รันผ่านใน container จริง, รันซ้ำแล้วไม่เปลี่ยน (idempotence), ผ่าน role `verify` | CI › 4. Molecule (role ที่เปลี่ยน) · Full Scan › 2. Molecule (ทุก role) | ✅ |
| 7. image ที่ deploy | CVE ใน container image ที่ role ดึงมา | Full Scan › 3. Image CVEs: Trivy | ⚠️ ยังไม่ (แค่ warning + summary) |
| 8. CVE ของ dependency | CVE ใน python package ของ CI | Full Scan › 4. Python CVEs: pip-audit | ✅ |

ผลของ KICS และ Checkov ถูกอัปโหลดเป็น SARIF เข้า **Security > Code scanning** และขึ้นตรงบรรทัดใน PR ด้วย

## Molecule
scenario กลางอยู่ที่ `molecule/default` ใช้กับทุก role โดยบอก role ผ่าน env:

```bash
MOLECULE_ROLE=docker_engine molecule test
```

| ที่ไหน | เทส role ไหน |
|---|---|
| flow หลัก (push) | เฉพาะ role ที่ไฟล์ใน `roles/<role>/` เปลี่ยน เทียบกับ commit ก่อนหน้า |
| flow หลัก (PR) | เฉพาะ role ที่เปลี่ยน เทียบกับ base branch |
| `full-scan.yml` | ทุก role แยก job ละ role |

ถ้าแก้ `molecule/`, `requirements-*.txt` หรือ `collections/requirements.yml` flow หลักจะขึ้น warning ให้ไปกดรัน `full-scan.yml`

- role ที่ต้องมีตัวอื่นรันก่อน (เช่น portainer ต้องมี docker) กำหนดใน `molecule_role_deps` ใน `molecule/default/converge.yml`
- role ที่ยังเทสไม่ได้ใส่ใน `molecule/skip-roles.txt` พร้อมเหตุผล

## การข้าม (exception)
ห้ามปิดกฎทั้ง repo ให้ข้ามเป็นรายจุดพร้อมเหตุผลเสมอ

**กฎของทีม:** การข้ามใหม่ทุกจุดต้องมี เหตุผล, ticket และคนอนุมัติ ในบรรทัดเดียวกัน เช่น

```yaml
# checkov:skip=CKV_ANSIBLE_1:Portainer localhost self-signed cert (ATR-123, approved: <ชื่อ>)
```

ต้องผ่าน review ใน PR ทุกครั้ง ห้ามแอบใส่มากับ commit อื่น

รูปแบบของแต่ละเครื่องมือ:
- Checkov: `# checkov:skip=<ID>:<เหตุผล>` ใต้ `- name:` ของ task
- KICS: `# kics-scan ignore-line` หรือ `# kics-scan disable=<query-id>` (อย่าใช้ `# kics-scan ignore` ทั้งไฟล์)

- ansible-lint: `.ansible-lint-ignore` (ไฟล์ + rule)

ที่ข้ามอยู่ตอนนี้ (baseline ก่อนมีกฎ ยังไม่มี ticket):
- 13 task ที่เรียก Portainer API ผ่าน `localhost:9443` ซึ่งใช้ self-signed cert (`CKV_ANSIBLE_1`)
- 1 task ที่เรียก nginx stub_status ผ่าน `127.0.0.1` (`CKV2_ANSIBLE_1`)

## ต้องจัดการ
- `portainer/agent:2.21.0` มีช่องโหว่ CRITICAL 6 / HIGH 205 ที่มี fix แล้ว (สแกนเมื่อ 2026-11-05) ส่วน server ใช้ `portainer/portainer-ce:lts` ซึ่งเป็น tag ที่เปลี่ยนได้และน่าจะคนละเวอร์ชันกับ agent ควร pin ทั้งคู่ให้เป็นเวอร์ชันเดียวกันที่ใหม่กว่านี้ แล้วเปลี่ยน job `images` เป็น `--exit-code 1` สำหรับ CRITICAL

## เมื่อทำฝั่ง OpenTofu
ใช้เครื่องมือชุดเดิมได้เกือบหมด ต่างกันแค่ flag:

| ชั้น | Ansible (ตอนนี้) | OpenTofu |
|---|---|---|
| คุณภาพโค้ด | ansible-lint | `tofu fmt -check`, `tofu validate`, tflint |
| workflow | zizmor | zizmor (ตัวเดิม) |
| secret | gitleaks | gitleaks (ตัวเดิม) |
| config | KICS `--type ansible`, Checkov `--framework ansible` | KICS `--type terraform`, Checkov `--framework terraform` และสแกน `tofu show -json plan` ด้วย Checkov `--framework terraform_plan` |
| เพิ่ม | | Trivy `config` (กฎของ tfsec เดิม) |
