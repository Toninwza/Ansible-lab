# Security scan flow (atrium · Ansible)

แต่ละ job ตรวจคนละเรื่อง ถ้าตัวไหนตรวจซ้ำกับอีกตัว จะเขียนบอกไว้ในตาราง

| ชั้น | ตรวจอะไร | job / เครื่องมือ | ทำ CI แดง? |
|---|---|---|---|
| 1. คุณภาพโค้ด | best practice ของ Ansible, YAML, syntax | `lint`: ansible-lint, yamllint, syntax-check | ✅ |
| 2. ตัว workflow เอง | ช่องโหว่ของ GitHub Actions (เช่น token ค้าง, script injection) | `lint`: zizmor · `checkov`: github_actions | ✅ |
| 3. secret | password/token ในโค้ดและ git history, vault ที่ลืมเข้ารหัส | `secrets`: gitleaks | ✅ |
| 4. config ไม่ปลอดภัย | http, `validate_certs: false`, ลายเซ็นแพ็กเกจ, ค่าใน `ansible.cfg` | `kics` + `checkov` (ansible) | ✅ CRITICAL/HIGH |
| 5. image ที่ deploy | CVE ใน container image ที่ role ดึงมา | `images`: Trivy | ⚠️ ยังไม่ (แค่ warning + summary) |
| 6. dependency ของ CI | CVE ใน python package, เวอร์ชันต้อง pin ตรงตัว (pip และ galaxy collection) | `deps`: pip-audit + สคริปต์เช็ก pin | ✅ |
| 7. ผลหลังรันจริง | role รันผ่านใน container จริง, รันซ้ำแล้วไม่มีอะไรเปลี่ยน (idempotence), ผ่าน role `verify` | `molecule-plan` + `molecule` | ✅ |

ผลของ KICS และ Checkov ถูกอัปโหลดเป็น SARIF เข้า **Security > Code scanning** และขึ้นตรงบรรทัดใน PR ด้วย

## ทำไมมีทั้ง KICS และ Checkov
ผลจากการรันกับ repo นี้ (ดู `docs/kics/`):

| | KICS | Checkov |
|---|---|---|
| ไฟล์ทดสอบ HTTP 6 แบบ | จับได้ 1 | จับได้ 5 |
| repo จริง (ก่อน skip) | 0 | 14 |
| ตรวจ `ansible.cfg` (เช่น `allow_unsafe_lookups`) | ✅ | ❌ |
| ใช้ต่อกับ OpenTofu | ✅ (กฎ cloud เยอะ) | ✅ |

สองตัวนี้ทับกันบางส่วน แต่ต่างตัวต่างมีจุดที่อีกตัวจับไม่ได้ และทั้งคู่ใช้ต่อกับ OpenTofu ได้

## Molecule
scenario กลางอยู่ที่ `molecule/default` ใช้กับทุก role โดยบอก role ผ่าน env:

```bash
MOLECULE_ROLE=docker_engine molecule test
```

| เหตุการณ์ | เทส role ไหน |
|---|---|
| push | เฉพาะ role ที่ไฟล์ใน `roles/<role>/` เปลี่ยนใน commit นั้น |
| pull request เข้า main, กดรันเอง (workflow_dispatch) | ทุก role |
| push ที่แก้ `molecule/`, workflow, `requirements-*.txt` หรือ `collections/requirements.yml` | ทุก role |

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
