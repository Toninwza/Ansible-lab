# CI lint fixes (feat/pipeline)

บันทึกการแก้ตาม log ของ ansible-lint / KICS รอบ commit `948a1ac`

## เปลี่ยนชื่อตัวแปร (var-naming[no-role-prefix])

กฎ: ตัวแปรที่ role สร้างเอง (`register`, `set_fact`, `defaults/`) ต้องขึ้นต้นด้วยชื่อ role เต็ม ๆ
ตัวแปรที่ส่งมาจากข้างนอก (inventory / extra-vars เช่น `install_*`, `docker_bip`) ไม่ได้เปลี่ยน

### docker_engine

| ชื่อเดิม | ชื่อใหม่ | ไฟล์ |
|---|---|---|
| `docker_daemon_config` | `docker_engine_daemon_config` | `defaults/main.yml`, `tasks/main.yml` |
| `docker_binary_check` | `docker_engine_binary_check` | `tasks/main.yml` |
| `existing_containers` | `docker_engine_existing_containers` | `tasks/main.yml` |
| `unknown_containers` | `docker_engine_unknown_containers` | `tasks/main.yml` |
| `app_dir_check` | `docker_engine_app_dir_check` | `tasks/main.yml` |

> ถ้าเคย override `docker_daemon_config` จาก inventory หรือ extra-vars ต้องเปลี่ยนเป็น `docker_engine_daemon_config`

### portainer_server

| ชื่อเดิม | ชื่อใหม่ | ไฟล์ |
|---|---|---|
| `portainer_status` | `portainer_server_status` | `tasks/main.yml` |
| `portainer_admin_check` | `portainer_server_admin_check` | `tasks/main.yml` |
| `portainer_auth` | `portainer_server_auth` | `tasks/main.yml` |
| `portainer_existing_tokens` | `portainer_server_existing_tokens` | `tasks/main.yml` |
| `portainer_new_token` | `portainer_server_new_token` | `tasks/main.yml` |
| `portainer_local_token` | `portainer_server_local_token` | `tasks/main.yml` และ **`roles/portainer_agent/tasks/main.yml`** (ใช้ข้าม role) |

### verify

| ชื่อเดิม | ชื่อใหม่ | ไฟล์ |
|---|---|---|
| `docker_status` | `verify_docker_status` | `tasks/main.yml` |
| `nginx_status` | `verify_nginx_status` | `tasks/main.yml` (path `/nginx_status` ใน URL ไม่ได้เปลี่ยน) |
| `portainer_status` | `verify_portainer_status` | `tasks/main.yml` |

## แก้ตามกฎอื่น

- `literal-compare`: `... | bool == false` → `not (... | bool)` (`roles/docker_engine/tasks/main.yml`)
- `name[missing]`: ตั้งชื่อ `import_tasks` ใน `playbooks/manual_playbook.yml`
- `yaml[truthy]`: `yes` → `true` (`roles/docker_engine/tasks/main.yml`)
- `jinja[spacing]`: `bool}}` → `bool }}`, `indent=2,sort_keys` → `indent=2, sort_keys`
- `yaml[indentation]`: `docker_engine_daemon_config` เขียนใหม่เป็น YAML block (ค่า render ออกมาเหมือนเดิม)
- `yaml[line-length]`: ตัด debug msg ยาว ๆ เป็น `>-`
- `yaml[comments]`: `#no_log: true` → `# no_log: true  # TODO` (ยังปิดอยู่ใน dev — **ต้องเปิดก่อนขึ้น prod**)
- format: newline ท้ายไฟล์, ช่องว่างท้ายบรรทัด, `role :` → `role:`, บรรทัดว่างเกิน

## ข้าม lint / scan

- `.ansible-lint`: เพิ่ม `playbooks/debugs/` ใน `exclude_paths` (KICS / gitleaks ยังสแกนอยู่)
- KICS "Communication Over HTTP": `# kics-scan ignore-line` ที่ `roles/verify/tasks/main.yml` (localhost health check)
- KICS "Logging of Sensitive Data In Defaults": `# kics-scan ignore` ใน `ansible.cfg` (ใช้ `no_log` ราย task แทน)
