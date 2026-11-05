# Ansible-lab

Ansible สำหรับ provision เครื่องของ atrium: Docker, Nginx proxy, Portainer (server/agent), NVM, .NET

```
roles/            role ที่ใช้จริง
playbooks/        main.yml (deploy), provision.yml, debugs/
molecule/         scenario กลางสำหรับเทสทุก role
docs/             security-scan.md (รายละเอียด), kics/ (lab ศึกษา KICS)
.github/          workflow และสคริปต์ของ CI
```

## CI

มี 2 workflow

| workflow | รันเมื่อ | หน้าที่ |
|---|---|---|
| **Ansible CI** (`ansible-ci.yml`) | ทุก push และ PR เข้า `main` | ด่านที่ต้องผ่านก่อน merge |
| **Ansible Full Scan** (`full-scan.yml`) | กดรันเองเท่านั้น: Actions › Ansible Full Scan › Run workflow | สแกนเต็มและงานที่ใช้เวลานาน |

> `full-scan.yml` จะกดรันได้ก็ต่อเมื่อไฟล์นี้อยู่บน branch `main` แล้ว (ข้อจำกัดของ GitHub)

### Ansible CI

| job | ทำอะไร | ล้มเมื่อ |
|---|---|---|
| **1. Lint** | **yamllint**: ไฟล์ YAML ของ workflow และ molecule<br>**zizmor**: ช่องโหว่ใน GitHub Actions เช่น token ค้าง, script injection<br>**ansible-lint**: best practice ของ Ansible (รวม syntax-check)<br>**Dependencies pinned**: pip ต้องเป็น `==`, galaxy collection ต้องเป็นเวอร์ชัน x.y.z ตรงตัว | เจอ error ข้อใดข้อหนึ่ง |
| **2. Secrets** | **gitleaks**: password/token ในโค้ดและใน git history ทั้งหมด<br>**Vault files encrypted**: ไฟล์ชื่อ `*vault*.yml` ต้องเข้ารหัสด้วย ansible-vault | เจอ secret หรือ vault ที่ไม่ได้เข้ารหัส |
| **3. IaC scan (KICS + Checkov)** | ตรวจ config ที่ไม่ปลอดภัย เช่น http, `validate_certs: false`, ลายเซ็นแพ็กเกจ, ค่าใน `ansible.cfg`<br>ผลขึ้นใน **Security › Code scanning** และตรงบรรทัดใน PR<br>สรุปแยกเป็นส่วน KICS กับ Checkov ในหน้า run | KICS: เจอ CRITICAL/HIGH<br>Checkov: เจอข้อที่ไม่ได้ skip |
| **4. Molecule** | รัน role ใน container จริง → รันซ้ำแล้วต้องไม่มีอะไรเปลี่ยน (idempotence) → ตรวจผลด้วย role `verify`<br>**เทสเฉพาะ role ที่เปลี่ยน** (push: เทียบกับ commit ก่อนหน้า, PR: เทียบกับ base branch) ถ้าไม่มี role เปลี่ยนก็จบเลย | role ใดล้ม |

### Ansible Full Scan

| job | ทำอะไร | ล้มเมื่อ |
|---|---|---|
| **1. List roles** | หา role ทั้งหมด ลบตัวที่อยู่ใน `molecule/skip-roles.txt` | – |
| **2. Molecule (\<role\>)** | molecule ทุก role แยก job ละ role ให้รันพร้อมกัน | role นั้นล้ม |
| **3. Image CVEs (Trivy)** | ช่องโหว่ใน container image ที่ role ใช้ (เช่น portainer) | ยังไม่ล้ม: ขึ้น warning และตารางใน summary |
| **4. Python CVEs (pip-audit)** | ช่องโหว่ใน python package ของ CI (`requirements-molecule.txt`) | เจอ CVE |

### ชื่อ step
ทุก step ขึ้นต้นด้วยขั้นตอน: `Setup ›` เตรียมเครื่อง, `Check ›` / `Scan ›` / `Test ›` ตัวตรวจ, `Report ›` สรุปผล
step ที่ขึ้นต้นด้วย `Post …` GitHub ใส่ให้เองตอนจบ job (เช่น ลบ credential ของ git)

## รัน Molecule เอง

```bash
pip install -r requirements-molecule.txt
ansible-galaxy collection install -r collections/requirements.yml -p collections
MOLECULE_ROLE=docker_engine molecule test
```

- role ที่ต้องมีตัวอื่นก่อน (เช่น portainer ต้องมี docker) กำหนดใน `molecule_role_deps` ใน `molecule/default/converge.yml`
- role ที่ยังเทสไม่ได้ใส่ใน `molecule/skip-roles.txt` พร้อมเหตุผล

## ข้ามกฎ (exception)

ห้ามปิดกฎทั้ง repo ให้ข้ามเป็นรายจุด และทุกจุดต้องมีเหตุผล, ticket และคนอนุมัติ

```yaml
# checkov:skip=CKV_ANSIBLE_1:Portainer localhost self-signed cert (ATR-123, approved: <ชื่อ>)
# kics-scan ignore-line
# kics-scan disable=<query-id>   ← ใช้แทน "# kics-scan ignore" ซึ่งข้ามทั้งไฟล์
```

ansible-lint ใช้ `.ansible-lint-ignore` รายละเอียดเพิ่มเติมอยู่ใน [docs/security-scan.md](docs/security-scan.md)
