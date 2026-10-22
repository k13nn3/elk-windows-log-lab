# ELK-Setup: Elasticsearch + Kibana + Fleet (HTTPS) trên Docker

> **English summary:** A self-contained, single-node Elastic Stack (Elasticsearch, Kibana, Fleet Server)
> on Docker Desktop for a Windows host, built to collect **Windows event logs** (Security, System,
> Application, PowerShell, Sysmon) from VMware lab VMs via Elastic Agent. TLS everywhere,
> certificates and Fleet policies are provisioned automatically, logs-only with 7-day retention.
> Documentation is in Vietnamese.

## Giới thiệu

**Mục đích:** dựng nhanh một hệ thống **thu thập và tra cứu event log Windows** cho môi trường lab
(học SOC, thực hành điều tra sự cố, theo dõi máy chủ thử nghiệm). Các máy Windows chạy trong
VMware gửi log về một Elastic Stack chạy bằng Docker trên chính máy host, xem và tìm kiếm trên Kibana.

**Hệ thống làm sẵn những gì:**

- **Elasticsearch + Kibana + Fleet Server** single-node, dùng image tự build kế thừa image chính thức của Elastic.
- **HTTPS/TLS ở mọi kết nối.** CA và chứng chỉ được tự tạo khi khởi động lần đầu, không phải chạy lệnh tay.
- **Fleet được cấu hình sẵn**: output, Fleet host, policy *Windows Servers* với integration `system` + `windows`.
  Agent trên VM chỉ cần **một lệnh cài** là tự gửi log về.
- **Chỉ thu log**, không thu metric. Log được **giữ 7 ngày** rồi tự xoá (có thể chỉnh).
- **Data stream đặt tên gọn** `logs-<dataset>-endpointwindow`, kèm data view **WindowLog-Endpoint** để tra cứu ngay.
- **Tối ưu cho máy cá nhân**: khoảng 3,5 GB RAM cho toàn bộ stack, cluster luôn `green` trên một node.

**Phù hợp với ai:** người cần một SIEM/log lab nhẹ trên Windows + VMware, muốn hiểu và tự vận hành
Elastic Stack có bảo mật, thay vì cài đặt thủ công từng bước.

**Giới hạn:** chỉ có 1 node, nên không có HA và không phù hợp chạy production. Dùng license Basic (miễn phí).
Kịch bản mặc định giả định host Windows có Docker Desktop và VMware Workstation, VM Windows nằm trên một
mạng host-only. Môi trường khác (Linux host, Hyper-V, máy vật lý) vẫn dùng được nếu chỉnh `LAB_IP` và mạng tương ứng.

## Bắt đầu nhanh

Yêu cầu: Docker Desktop (WSL2), Git Bash (hoặc shell bash bất kỳ có `openssl`), và khoảng 6 GB RAM trống.

```bash
git clone <url-repo> ELK-Setup && cd ELK-Setup

# 1. Tạo .env với mật khẩu và khoá ngẫu nhiên
cp .env.example .env
for k in ELASTIC_PASSWORD KIBANA_PASSWORD; do sed -i "s/^$k=.*/$k=$(openssl rand -base64 18 | tr -d '/+=')/" .env; done
for k in KIBANA_SECURITY_KEY KIBANA_SAVEDOBJECTS_KEY KIBANA_REPORTING_KEY; do sed -i "s/^$k=.*/$k=$(openssl rand -hex 16)/" .env; done

# 2. Đặt IP của host trên mạng mà các VM nhìn thấy (vd: adapter VMware host-only)
sed -i "s/^LAB_IP=.*/LAB_IP=10.20.20.1/" .env

# 3. Build + chạy (lần đầu khoảng 3–5 phút)
docker compose up -d --build --wait

# 4. Lấy CA để trình duyệt/curl và agent tin cậy
docker compose cp es01:/usr/share/elasticsearch/config/certs/ca/ca.crt ./ca.crt
```

Mở https://localhost:5601 và đăng nhập `elastic` / giá trị `ELASTIC_PASSWORD` trong `.env`.
Cài agent cho VM: xem [mục 4, bước 4](#4-cài-đặt-lần-đầu) và [fleet/HUONG-DAN-CAI-AGENT.md](fleet/HUONG-DAN-CAI-AGENT.md).

## Bảo mật khi public repo

Repo **chỉ chứa mã nguồn, cấu hình mẫu và tài liệu**. Mọi secret được sinh ra lúc chạy và bị `.gitignore` loại trừ:

| Không bao giờ commit | Chứa gì | Rule trong `.gitignore` |
|---|---|---|
| `.env` | Mật khẩu `elastic`/`kibana_system`, khoá mã hoá Kibana | `.env`, `.env.*` (trừ `.env.example`) |
| `ca.crt`, `fleet/ca.crt`, mọi `*.key`/`*.pem`/`*.p12`… | CA và chứng chỉ | `*.crt`, `*.key`, `*.pem`, `certs/`… |
| `fleet/enrollment-token.txt` | Token để enroll agent vào Fleet | `fleet/enrollment-token.txt` |
| `fleet/elastic-agent-*.zip` | File cài agent (228 MB, tải từ Elastic) | `fleet/elastic-agent-*.zip*` |
| Docker volume (`elk_esdata`, `elk_certs`…) | Dữ liệu, CA, service token | Không nằm trong thư mục repo |

Kiểm tra trước khi push. Lệnh thứ nhất phải **không** liệt kê file bí mật nào; lệnh thứ hai phải liệt kê chúng là `!!`:

```bash
git ls-files
git status --ignored --short | grep '^!!'
```

Nếu lỡ commit secret: **đổi ngay** mật khẩu, khoá hoặc token đó (xem [mục 9](#9-mật-khẩu-và-secrets)), vì xoá commit không thu hồi được bản đã bị đọc.

---

## Mục lục

- [Giới thiệu](#giới-thiệu) · [Bắt đầu nhanh](#bắt-đầu-nhanh) · [Bảo mật khi public repo](#bảo-mật-khi-public-repo)

1. [Kiến trúc](#1-kiến-trúc)
2. [Cấu trúc thư mục](#2-cấu-trúc-thư-mục)
3. [Yêu cầu máy host](#3-yêu-cầu-máy-host)
4. [Cài đặt lần đầu](#4-cài-đặt-lần-đầu)
5. [Truy cập](#5-truy-cập)
6. [Vận hành hằng ngày](#6-vận-hành-hằng-ngày)
7. [Fleet và agent](#7-fleet-và-agent)
8. [Dữ liệu: data stream, data view, lưu trữ](#8-dữ-liệu-data-stream-data-view-lưu-trữ)
9. [Mật khẩu và secrets](#9-mật-khẩu-và-secrets)
10. [Chứng chỉ TLS](#10-chứng-chỉ-tls)
11. [Tài nguyên (RAM)](#11-tài-nguyên-ram)
12. [Sao lưu, nâng cấp, gỡ bỏ](#12-sao-lưu-nâng-cấp-gỡ-bỏ)
13. [Xử lý sự cố](#13-xử-lý-sự-cố)
14. [Tham chiếu cấu hình `.env`](#14-tham-chiếu-cấu-hình-env)

---

## 1. Kiến trúc

```
┌──────────── VM Windows (VMware, adapter "LAB" VMnet3) ───────────┐
│  10.20.20.10   Elastic Agent (policy "Windows Servers")          │
└───────────────┬───────────────────────────────┬──────────────────┘
                │ enroll / check-in :8220       │ gửi log :9200
                ▼                               ▼
┌──────────── Host Windows: 10.20.20.1 (VMnet3) + 127.0.0.1 ───────┐
│  Docker Desktop (WSL2, giới hạn 6 GB)          project: elk      │
│   ┌──────────────┐   ┌──────────┐   ┌────────────┐               │
│   │ fleet-server │──▶│   es01   │◀──│   kibana   │◀── trình duyệt│
│   │ :8220        │   │  :9200   │   │  :5601     │    (localhost)│
│   └──────────────┘   └──────────┘   └────────────┘               │
│   certs (chạy 1 lần) → es01 → setup (chạy 1 lần) → kibana → fleet│
└──────────────────────────────────────────────────────────────────┘
```

| Service | Image | Cổng | Vai trò |
|---|---|---|---|
| `certs` | `elk-setup` (tự build) | — | Chạy 1 lần: tạo CA và chứng chỉ cho `es01`, `kibana`, `fleet-server` |
| `es01` | `elk-elasticsearch` (tự build) | `127.0.0.1:9200`, `10.20.20.1:9200` | Elasticsearch single-node, HTTPS + TLS transport |
| `setup` | `elk-setup` | — | Chạy 1 lần: mật khẩu `kibana_system`, service token Fleet, pipeline chặn metrics |
| `kibana` | `elk-kibana` (tự build) | `127.0.0.1:5601` | Kibana HTTPS; tự cấu hình sẵn Fleet (output, host, policy) |
| `fleet-server` | `elastic-agent` (chính thức) | `127.0.0.1:8220`, `10.20.20.1:8220` | Fleet Server, nơi các agent enroll và nhận policy |

Các quyết định thiết kế chính:

- **Image tự build kế thừa image chính thức** của Elastic (`STACK_VERSION=9.5.5`). Chỉ thêm file cấu hình và script, không build từ đầu.
- **Chỉ thu log, không thu metric, giữ log 7 ngày.** Mọi input metric đều tắt, và metric do Kibana tự ghi bị chặn bằng ingest pipeline.
- **License Basic (miễn phí).** Không đặt được output riêng cho từng policy, nên mọi agent, kể cả Fleet Server, gửi về cùng một output `https://10.20.20.1:9200`.
- **ES/Kibana chỉ mở trên `127.0.0.1`.** Riêng ES và Fleet được mở thêm trên IP mạng LAB để VM truy cập. Không mở ra Wi-Fi/LAN.

---

## 2. Cấu trúc thư mục

```
ELK-Setup/
├── docker-compose.yml            # Định nghĩa 5 service, volume, cổng
├── .env                          # Cấu hình + secrets thật (KHÔNG commit)
├── .env.example                  # Mẫu .env (commit)
├── ca.crt                        # CA đã copy ra host (KHÔNG commit)
├── setup/
│   ├── Dockerfile                # FROM elasticsearch, chứa setup.sh
│   └── setup.sh                  # certs | passwords
├── elasticsearch/
│   ├── Dockerfile                # FROM elasticsearch (+ plugin tuỳ chọn)
│   └── elasticsearch.yml
├── kibana/
│   ├── Dockerfile                # FROM kibana + entrypoint
│   ├── entrypoint.sh             # Nạp CA fingerprint vào biến môi trường
│   └── kibana.yml                # Gồm cấu hình Fleet (xpack.fleet.*)
└── fleet/                        # = bộ cài agent: copy nguyên thư mục vào VM
    ├── HUONG-DAN-CAI-AGENT.md    # Hướng dẫn cài agent trong VM (commit)
    ├── install-agent-windows.ps1 # Script cài agent (commit)
    ├── ca.crt                    # CA của stack (KHÔNG commit)
    ├── enrollment-token.txt      # Token enroll (bí mật, KHÔNG commit)
    └── elastic-agent-9.5.5-windows-x86_64.zip (+ .sha512)   # Tải về (KHÔNG commit)
```

Docker volume (project `elk`):

| Volume | Nội dung | Mất volume thì sao |
|---|---|---|
| `elk_esdata` | Toàn bộ dữ liệu Elasticsearch | **Mất hết log**, user, mật khẩu, cấu hình Fleet |
| `elk_kibanadata` | Dữ liệu cục bộ của Kibana | Ít ảnh hưởng (saved objects nằm trong ES) |
| `elk_certs` | CA, chứng chỉ, service token Fleet | CA mới, nên phải phân phối lại `ca.crt` và enroll lại agent |
| `elk_fleetdata` | Trạng thái agent của Fleet Server | Fleet Server tự bootstrap lại |

---

## 3. Yêu cầu máy host

- Windows 10/11, **Docker Desktop** (WSL2 backend) và Docker Compose v2.
- **VMware Workstation** có mạng host-only **LAB = VMnet3**, subnet `10.20.20.0/24`. Host có IP `10.20.20.1` trên adapter *VMware Network Adapter VMnet3*.
- `vm.max_map_count >= 262144` trong VM của Docker. Mặc định Docker Desktop đã là 1048576. Kiểm tra bằng:

  ```bash
  wsl -d docker-desktop sysctl vm.max_map_count
  ```

- File `%UserProfile%\.wslconfig` giới hạn RAM của WSL (xem mục [11](#11-tài-nguyên-ram)):

  ```ini
  [wsl2]
  memory=6GB

  [experimental]
  autoMemoryReclaim=dropCache
  ```

---

## 4. Cài đặt lần đầu

1. **Tạo `.env`** từ mẫu và điền secrets:

   ```bash
   cp .env.example .env
   ```

   - `ELASTIC_PASSWORD`, `KIBANA_PASSWORD`: mật khẩu mạnh.
   - `KIBANA_SECURITY_KEY`, `KIBANA_SAVEDOBJECTS_KEY`, `KIBANA_REPORTING_KEY`: mỗi khoá là một chuỗi ngẫu nhiên, tạo bằng `openssl rand -hex 16`. **Giữ cố định**: nếu đổi, Kibana mất các saved object đã mã hoá, bao gồm cấu hình Fleet.
   - `LAB_IP`: IP của host trên mạng VMware (mặc định `10.20.20.1`).

2. **Build và khởi động:**

   ```bash
   docker compose up -d --build --wait
   ```

   Lần đầu mất khoảng 3–5 phút. `certs` và `setup` kết thúc với `Exited (0)` là bình thường.

3. **Lấy CA về host** để trình duyệt và curl tin cậy chứng chỉ:

   ```bash
   docker compose cp es01:/usr/share/elasticsearch/config/certs/ca/ca.crt ./ca.crt
   ```

   Để trình duyệt không cảnh báo, import vào Trusted Root của user hiện tại:

   ```bash
   certutil -addstore -user Root ca.crt
   ```

4. **Hoàn thiện bộ cài cho VM** (thư mục `fleet/`, đã có sẵn script và hướng dẫn):

   ```bash
   cp ca.crt fleet/
   ```

   - Enrollment token: lấy trong Kibana → **Fleet → Enrollment tokens** → policy *Windows Servers*, rồi lưu vào `fleet/enrollment-token.txt`.
   - File agent: tải `https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-9.5.5-windows-x86_64.zip` cùng file `.sha512` vào `fleet/`, rồi kiểm tra:

     ```bash
     cd fleet && sha512sum -c elastic-agent-9.5.5-windows-x86_64.zip.sha512
     ```

5. **Cài agent trong VM**: làm theo [fleet/HUONG-DAN-CAI-AGENT.md](fleet/HUONG-DAN-CAI-AGENT.md).

### Những gì được tự động cấu hình

| Thành phần | Ở đâu | Ghi chú |
|---|---|---|
| CA + chứng chỉ (SAN: tên service, `localhost`, `127.0.0.1`, `LAB_IP`) | `setup.sh certs` | Hạn `CERT_DAYS` (mặc định 3 năm) |
| Mật khẩu `kibana_system` | `setup.sh passwords` | Lấy từ `KIBANA_PASSWORD` |
| Service token Fleet Server | `setup.sh passwords` | Lưu ở `certs/fleet-server/service-token` |
| Pipeline chặn `metrics-fleet_server.*` | `setup.sh passwords` | Xem mục [8.4](#84-chặn-dữ-liệu-không-phải-log) |
| ILM `logs-retention` + component template `logs@custom` | `setup.sh passwords` | Giữ log `LOG_RETENTION` (7 ngày) và 0 replica (single-node, cluster luôn `green`). Xem [8.3](#83-thời-gian-lưu-trữ-retention-7-ngày) |
| Package `fleet_server`, `system`, `windows`, `elastic_agent` | `kibana.yml` → `xpack.fleet.packages` | Cài khi Kibana khởi động |
| Fleet host `https://LAB_IP:8220`, output `https://LAB_IP:9200` | `kibana.yml` | Output tin cậy CA qua `ca_trusted_fingerprint` |
| Policy *Fleet Server Policy*, *Windows Servers* | `kibana.yml` → `xpack.fleet.agentPolicies` | **Chỉ áp dụng khi tạo mới** (xem [7.3](#73-thay-đổi-policy)) |

---

## 5. Truy cập

| Dịch vụ | URL | Tài khoản |
|---|---|---|
| Kibana | https://localhost:5601 | `elastic` / `ELASTIC_PASSWORD` |
| Elasticsearch | https://localhost:9200 | `elastic` / `ELASTIC_PASSWORD` |
| Fleet Server (cho agent) | https://10.20.20.1:8220 | enrollment token |

Kiểm tra nhanh từ Git Bash. curl của Git Bash dùng Schannel, nên cần `--ssl-no-revoke` vì CA nội bộ không có CRL:

```bash
set -a; . ./.env; set +a
curl --ssl-no-revoke --cacert ca.crt -u "elastic:$ELASTIC_PASSWORD" "https://localhost:9200/_cluster/health?pretty"
curl --ssl-no-revoke --cacert ca.crt https://10.20.20.1:8220/api/status
```

Kết quả mong đợi: `"status" : "green"` và `{"name":"fleet-server","status":"HEALTHY"}`.

---

## 6. Vận hành hằng ngày

| Việc | Lệnh |
|---|---|
| Xem trạng thái | `docker compose ps -a` |
| Khởi động toàn bộ | `docker compose up -d --wait` |
| Dừng (giữ dữ liệu) | `docker compose stop` |
| Dừng và xoá container (giữ volume) | `docker compose down` |
| Khởi động lại một service | `docker compose restart kibana` |
| Xem log | `docker compose logs -f --tail 100 es01` |
| Lọc lỗi | `docker compose logs kibana \| grep -E "ERROR\|FATAL"` |
| RAM / CPU | `docker stats --no-stream` |
| Tiết kiệm RAM khi không cần UI | `docker compose stop kibana` (agent vẫn gửi log) |

Lưu ý:

- Các container có `restart: unless-stopped`, nên tự chạy lại khi Docker Desktop khởi động. Thứ tự phụ thuộc (`depends_on`) chỉ được áp dụng khi chạy `docker compose up`.
- **Không dùng `docker compose down -v`** trừ khi muốn xoá sạch dữ liệu (xem [12.3](#123-gỡ-bỏ--làm-lại-từ-đầu)).
- Sau khi sửa `.env` hoặc file cấu hình: `docker compose up -d --build --wait`. Compose chỉ tạo lại những service có thay đổi.

### Checklist sức khoẻ

```bash
set -a; . ./.env; set +a
C="curl -s --ssl-no-revoke --cacert ca.crt -u elastic:$ELASTIC_PASSWORD"
docker compose ps --format '{{.Service}}: {{.Status}}'
$C "https://localhost:9200/_cluster/health?filter_path=status"
$C -H kbn-xsrf:true https://localhost:5601/api/status | grep -o '"overall":{"level":"[a-z]*"'
$C -H kbn-xsrf:true "https://localhost:5601/api/fleet/agent_status"
$C "https://localhost:9200/_cat/indices/logs-*-endpointwindow?v&h=index,docs.count,store.size&s=index"
```

---

## 7. Fleet và agent

### 7.1 Policy

| Policy | ID | Namespace | Dùng cho |
|---|---|---|---|
| Fleet Server Policy | `fleet-server-policy` | `default` | Container `fleet-server` |
| Windows Servers | `windows-servers` | `endpointwindow` | Các VM Windows |

Policy **Windows Servers** chỉ bật input `winlog`:

| Integration | Dataset | Nguồn |
|---|---|---|
| system | `system.security` | Security (đăng nhập, user, quyền) |
| system | `system.system` | System |
| system | `system.application` | Application |
| windows | `windows.powershell` | Windows PowerShell |
| windows | `windows.powershell_operational` | PowerShell/Operational |
| windows | `windows.sysmon_operational` | Sysmon (chỉ có dữ liệu khi VM đã cài Sysmon) |
| windows | `windows.forwarded` | Forwarded Events |

Đã tắt: `system/metrics`, `windows/metrics` (perfmon, service), `logfile`/`journald` (log Linux), và metrics tự giám sát của agent (`monitoring_enabled: [logs]`).

### 7.2 Thêm VM mới

1. Gắn VM vào mạng **LAB (VMnet3)**, đặt IP tĩnh `10.20.20.x/24` và **múi giờ đúng** (xem [13](#13-xử-lý-sự-cố)).
2. Copy thư mục `fleet/` vào VM rồi chạy script cài đặt (xem [HUONG-DAN-CAI-AGENT.md](fleet/HUONG-DAN-CAI-AGENT.md)).
3. Kiểm tra trong Kibana → **Fleet → Agents**.

Muốn một nhóm máy có cấu hình khác (ví dụ máy Domain Controller): trong Kibana → Fleet → **Agent policies → Create agent policy**, đặt namespace mới (chữ thường, không có `-`), rồi thêm integration. Lưu ý license Basic chỉ dùng được output mặc định.

### 7.3 Thay đổi policy

Phần `xpack.fleet.agentPolicies` trong `kibana.yml` **chỉ được áp dụng khi policy chưa tồn tại**, tức là khi cài mới. Với policy đang chạy, hãy sửa trong **Kibana UI** (Fleet → Agent policies) hoặc qua Fleet API. Sau đó cập nhật cả `kibana.yml` để lần cài lại ra đúng cấu hình. Agent tự nhận policy mới trong vài giây, không cần cài lại.

Ví dụ: xem các input đang gửi xuống agent.

```bash
curl -s --ssl-no-revoke --cacert ca.crt -u "elastic:$ELASTIC_PASSWORD" -H kbn-xsrf:true \
  https://localhost:5601/api/fleet/agent_policies/windows-servers/full
```

### 7.4 Enrollment token

- Xem, tạo hoặc thu hồi: Kibana → **Fleet → Enrollment tokens**.
- Token đang dùng nằm ở `fleet/enrollment-token.txt`. Đây là **thông tin bí mật**: ai có token đều enroll được máy vào Fleet. Khi lộ token, thu hồi nó rồi tạo token mới.

### 7.5 Gỡ, nâng cấp agent

- Gỡ agent trong VM: `& "C:\Program Files\Elastic\Agent\elastic-agent.exe" uninstall`. Sau đó vào Fleet → Agents → **Unenroll**.
- Nâng cấp: Fleet → Agents → chọn agent → **Upgrade agent**. VM cần tải được bản mới từ `artifacts.elastic.co`. Nếu VM không có internet, gỡ agent rồi cài lại bằng bản zip mới.

---

## 8. Dữ liệu: data stream, data view, lưu trữ

### 8.1 Đặt tên

Tên data stream có dạng `logs-<dataset>-<namespace>`. Log Windows dùng namespace **`endpointwindow`**:

```
logs-system.security-endpointwindow
logs-system.system-endpointwindow
logs-system.application-endpointwindow
logs-windows.powershell-endpointwindow
logs-windows.powershell_operational-endpointwindow
logs-windows.sysmon_operational-endpointwindow
```

Log nội bộ của agent: `logs-elastic_agent*-default` (Fleet Server) và `logs-elastic_agent*-endpointwindow` (agent trên VM). Nên giữ các log này để debug.

### 8.2 Data view

| Data view | Pattern | Ghi chú |
|---|---|---|
| **WindowLog-Endpoint** (mặc định) | `logs-*-endpointwindow,-logs-elastic_agent*` | Chỉ event log Windows, loại log của agent |

Truy vấn mẫu trong Discover (KQL):

```
data_stream.dataset : "system.security" and event.code : 4625          # đăng nhập thất bại
data_stream.dataset : "system.security" and event.code : (4720 or 4726) # tạo / xoá user
data_stream.dataset : "windows.powershell_operational" and event.code : 4104  # script block
host.name : "WIN-SRV01"                       # thay bằng tên máy của bạn
```

### 8.3 Thời gian lưu trữ (retention): 7 ngày

Mọi data stream `logs-*` dùng ILM policy **`logs-retention`** (thay cho `logs@lifecycle` mặc định, vốn không bao giờ xoá):

| Phase | Hành động |
|---|---|
| hot | Rollover **mỗi ngày** (`max_age: 1d`) hoặc khi shard đạt 10 GB |
| delete | **Xoá index 7 ngày sau khi rollover** (`LOG_RETENTION=7d`) |

Vì rollover diễn ra mỗi ngày, mỗi event được giữ khoảng **7–8 ngày** rồi bị xoá cùng index chứa nó.

Cách cấu hình (do `setup.sh` thực hiện mỗi lần service `setup` chạy):
1. Tạo/cập nhật ILM policy `logs-retention` từ biến `LOG_RETENTION`.
2. Component template **`logs@custom`** (mọi template `logs-*`, kể cả của integration, đều dùng) đặt
   `index.number_of_replicas: 0` và `index.lifecycle.name: logs-retention`.
3. Gán `logs-retention` cho các backing index `logs-*` đang có.

**Đổi thời gian lưu**, ví dụ thành 30 ngày:

```bash
sed -i 's/^LOG_RETENTION=.*/LOG_RETENTION=30d/' .env
docker compose run --rm setup
```

Kiểm tra:

```bash
set -a; . ./.env; set +a
C="curl -s --ssl-no-revoke --cacert ca.crt -u elastic:$ELASTIC_PASSWORD"
$C "https://localhost:9200/_ilm/policy/logs-retention?filter_path=**.phases&pretty"
$C "https://localhost:9200/logs-*/_ilm/explain?filter_path=indices.*.policy,indices.*.phase,indices.*.step,indices.*.age&pretty"
```

> Không sửa `logs@custom` bằng tay: `setup.sh` ghi đè nó mỗi lần chạy. Muốn thêm setting chung
> cho `logs-*`, hãy sửa trong `setup/setup.sh` rồi chạy `docker compose build certs && docker compose run --rm setup`.

Xem dung lượng: `_cat/allocation?v` và `_cat/indices/logs-*?v&s=store.size:desc`.

### 8.4 Chặn dữ liệu không phải log

| Nguồn | Cách chặn |
|---|---|
| `metrics-fleet_server.agent_status` / `agent_versions` (Kibana ghi mỗi phút, không có setting tắt) | Pipeline `<data stream>@custom` với processor `drop`, do `setup.sh` tạo |
| `metrics-endpoint.metadata_*` (transform của Elastic Defend) | Đã dừng và xoá 2 transform `endpoint.metadata_*` |
| Metrics của agent và integration | Tắt trong policy (xem [7.1](#71-policy)) |

Kiểm tra định kỳ. Lệnh sau phải không trả về dòng nào:

```bash
curl -s --ssl-no-revoke --cacert ca.crt -u "elastic:$ELASTIC_PASSWORD" \
  "https://localhost:9200/_cat/indices/metrics-*,.metrics-*?expand_wildcards=all"
```

Package `endpoint` do Security app tự cài. Sau khi **nâng cấp Kibana**, transform có thể được tạo lại. Khi đó, xoá như sau:

```bash
for t in $(curl -s --ssl-no-revoke --cacert ca.crt -u "elastic:$ELASTIC_PASSWORD" "https://localhost:9200/_transform/endpoint.*" | grep -oE '"id":"[^"]+"' | cut -d'"' -f4); do
  curl -s --ssl-no-revoke --cacert ca.crt -u "elastic:$ELASTIC_PASSWORD" -X POST "https://localhost:9200/_transform/$t/_stop?force=true"
  curl -s --ssl-no-revoke --cacert ca.crt -u "elastic:$ELASTIC_PASSWORD" -X DELETE "https://localhost:9200/_transform/$t?force=true"
done
```

---

## 9. Mật khẩu và secrets

| Secret | Ở đâu | Dùng cho |
|---|---|---|
| `ELASTIC_PASSWORD` | `.env` | Superuser `elastic`: đăng nhập Kibana và gọi API |
| `KIBANA_PASSWORD` | `.env` | User `kibana_system` (Kibana kết nối tới ES) |
| `KIBANA_*_KEY` | `.env` | Khoá mã hoá của Kibana. **Không được đổi** |
| Service token Fleet | volume `elk_certs` → `fleet-server/service-token` | Fleet Server kết nối tới ES |
| Enrollment token | Kibana và `fleet/enrollment-token.txt` | Enroll agent |

### Đổi mật khẩu `elastic`

`ELASTIC_PASSWORD` chỉ được dùng ở lần khởi tạo đầu tiên. Sau đó, đổi mật khẩu qua API rồi cập nhật lại `.env`:

```bash
set -a; . ./.env; set +a
NEW='mat-khau-moi'
curl -s --ssl-no-revoke --cacert ca.crt -u "elastic:$ELASTIC_PASSWORD" -H Content-Type:application/json \
  -X POST https://localhost:9200/_security/user/elastic/_password -d "{\"password\":\"$NEW\"}"
sed -i "s/^ELASTIC_PASSWORD=.*/ELASTIC_PASSWORD=$NEW/" .env
docker compose up -d --wait
```

Nếu đã quên mật khẩu, đặt lại từ bên trong container:

```bash
docker compose exec es01 bin/elasticsearch-reset-password -u elastic -i
```

### Đổi mật khẩu `kibana_system`

Sửa `KIBANA_PASSWORD` trong `.env`, rồi chạy:

```bash
docker compose run --rm setup && docker compose up -d --wait kibana
```

---

## 10. Chứng chỉ TLS

- CA và chứng chỉ được tạo bằng `elasticsearch-certutil` và lưu trong volume `elk_certs`. Hạn là `CERT_DAYS` (1095 ngày): **CA hiện tại hết hạn ngày 21/10/2029**.
- Mỗi lần chạy, `certs` so sánh danh sách SAN. Nếu `LAB_IP` hoặc `CERT_EXTRA_DNS` thay đổi, các **chứng chỉ lá được tạo lại tự động**, còn **CA giữ nguyên**, nên agent và `ca.crt` trên các máy không bị ảnh hưởng.
- ES và Fleet gửi kèm CA trong chuỗi chứng chỉ (`*-chain.crt`), để agent xác thực được bằng `ca_trusted_fingerprint`.

Kiểm tra hạn:

```bash
docker compose exec es01 sh -c 'jdk/bin/keytool -printcert -file config/certs/ca/ca.crt | grep -m1 until; jdk/bin/keytool -printcert -file config/certs/es01/es01.crt | grep -m1 until'
```

**Gia hạn chứng chỉ lá** (CA giữ nguyên): xoá thư mục của các chứng chỉ lá trong volume, rồi chạy lại:

```bash
docker compose run --rm --entrypoint sh certs -c 'rm -rf config/certs/es01 config/certs/kibana config/certs/fleet-server/*.crt config/certs/fleet-server/*.key config/certs/instances.yml'
docker compose up -d --wait --force-recreate es01 kibana fleet-server
```

**Tạo CA mới** (khi CA sắp hết hạn hoặc bị lộ): tạo CA mới bắt buộc phải **phân phối lại `ca.crt` và enroll lại toàn bộ agent**, vì fingerprint của CA thay đổi.

```bash
docker compose down
docker volume rm elk_certs elk_fleetdata
docker compose up -d --wait
docker compose cp es01:/usr/share/elasticsearch/config/certs/ca/ca.crt ./ca.crt
```

Output `Elasticsearch (LAB)` được cấu hình sẵn trong `kibana.yml`, nên Kibana tự nạp fingerprint mới (từ `config/certs/ca/ca.fingerprint`) khi khởi động lại. Kiểm tra lại ở Kibana → Fleet → **Settings → Outputs**. Cuối cùng, copy `ca.crt` mới vào `fleet/` và cài lại agent trên các VM.

---

## 11. Tài nguyên (RAM)

| Thành phần | Thiết lập | Thực tế khoảng |
|---|---|---|
| Elasticsearch | heap `ES_HEAP=1g`, giới hạn `ES_MEM_LIMIT=2g` | 1,7 GB |
| Kibana | Node heap `KIBANA_NODE_HEAP_MB=1024`, giới hạn `1536m` | 1,2 GB |
| Fleet Server | giới hạn `FLEET_MEM_LIMIT=768m` | 0,5 GB |
| VM WSL (vmmemWSL) | `.wslconfig` `memory=6GB`, `autoMemoryReclaim=dropCache` | ≤ 6 GB |

- **Không đặt Node heap của Kibana dưới 1024 MB**: Kibana sẽ bị OOM (`JavaScript heap out of memory`) khi Fleet cài package.
- Trong Task Manager, **vmmemWSL** chứa cả page cache của Linux. Để giải phóng ngay:

  ```bash
  wsl -d docker-desktop sh -c "sync; echo 3 > /proc/sys/vm/drop_caches"
  ```

- Máy ảo VMware (`vmware-vmx`) cũng chiếm nhiều RAM nhưng không hiện trong cột Memory của Task Manager. Hãy Suspend VM khi không dùng.
- Sau khi sửa `.wslconfig`: thoát Docker Desktop, chạy `wsl --shutdown`, đợi khoảng 8 giây rồi mở lại Docker Desktop.

---

## 12. Sao lưu, nâng cấp, gỡ bỏ

### 12.1 Sao lưu

Snapshot repository chưa được cấu hình. Cách đơn giản nhất là sao lưu các volume khi stack đang **dừng**:

```bash
docker compose stop
mkdir -p backup
for v in esdata certs kibanadata; do
  docker run --rm -v elk_$v:/data -v "$(pwd -W)/backup:/backup" alpine tar czf /backup/elk_$v-$(date +%Y%m%d).tgz -C /data .
done
docker compose start
```

Phục hồi: tạo volume trống, giải nén file `tgz` vào volume (lệnh `tar xzf` tương tự), rồi chạy `docker compose up -d`. Ngoài các volume, hãy sao lưu cả file `.env`.

### 12.2 Nâng cấp phiên bản

1. Sao lưu (12.1) và đọc release notes / breaking changes của Elastic.
2. Đổi `STACK_VERSION` trong `.env`. ES, Kibana và Agent phải **cùng version**.
3. Chạy `docker compose pull fleet-server && docker compose up -d --build --wait`.
4. Kiểm tra theo checklist ở mục 6. Xoá transform `endpoint.*` nếu chúng xuất hiện lại (mục 8.4).
5. Nâng cấp agent trên các VM (mục 7.5), và tải bản zip mới vào `fleet/` (xoá bản zip cũ).

### 12.3 Gỡ bỏ / làm lại từ đầu

```bash
docker compose down            # xoá container, GIỮ dữ liệu
docker compose down -v         # xoá container VÀ TOÀN BỘ dữ liệu, CA, token (không phục hồi được)
docker image rm elk-setup:9.5.5 elk-elasticsearch:9.5.5 elk-kibana:9.5.5
```

Sau khi chạy `down -v`, cần làm lại mục 4: CA mới, vì vậy phải cài lại agent trên các VM.

---

## 13. Xử lý sự cố

| Hiện tượng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `curl: (60) schannel: the revocation status is unknown` | curl trên Windows kiểm tra CRL, mà CA nội bộ không có CRL | Thêm `--ssl-no-revoke` |
| Trình duyệt cảnh báo chứng chỉ | Host chưa tin cậy CA | `certutil -addstore -user Root ca.crt` |
| Kibana restart liên tục, log `JavaScript heap out of memory` | Node heap quá thấp | Đặt `KIBANA_NODE_HEAP_MB >= 1024` và `KIBANA_MEM_LIMIT >= 1536m` |
| `dependency failed to start: ... unhealthy` | Một service khởi động chậm hoặc lỗi | `docker compose ps -a`, `docker compose logs <service>`, rồi `docker compose up -d --wait` lại |
| Kibana log `OutputLicenceError ... platinum licence` | Đặt output riêng cho policy | Không dùng `data_output_id`/`monitoring_output_id` với license Basic |
| Fleet Server `STARTING` mãi, log `dial tcp [::1]:9200` | Chưa có policy `fleet-server-policy` | Kiểm tra log Fleet của Kibana; chạy `docker compose restart kibana fleet-server` |
| Fleet Server log `Failed Elasticsearch output configuration test, using bootstrap values` | Fleet Server tự kiểm tra output | Vô hại. Nó dùng kết nối nội bộ tới `es01` |
| Fleet Server "Up vài giây" | Agent tự khởi động lại tiến trình con | Bình thường nếu `/api/status` trả về `HEALTHY` |
| VM: `Test-NetConnection 10.20.20.1 -Port 8220` False | Sai mạng hoặc firewall | VM phải ở adapter LAB/VMnet3; `docker compose ps`; nếu cần thì thêm rule firewall trên host (xem file hướng dẫn cài agent) |
| Agent `x509: certificate signed by unknown authority` | Sai hoặc thiếu `ca.crt` | Copy lại `ca.crt` vào `C:\ProgramData\Elastic\ca.crt` |
| Agent `x509: ... not yet valid / expired` | Đồng hồ VM sai | Sửa **múi giờ**, đừng chỉnh giờ bằng tay (xem dưới) |
| Đồng hồ VM lệch 14 tiếng (ví dụ 2:53 AM so với 16:53) | VM để múi giờ UTC−7 (mặc định của Windows tiếng Anh) | Chạy `Set-TimeZone -Id "SE Asia Standard Time"` trong VM; bật *Synchronize guest time with host* trong VMware Tools |
| Không thấy log trong Discover | Sai data view hoặc khoảng thời gian | Chọn data view **WindowLog-Endpoint**, mở rộng khoảng thời gian, xem Fleet → Agents |
| Cluster `yellow`, `_cat/shards` có replica `UNASSIGNED` | Index tạo với 1 replica trên cluster 1 node (thường là `.items-*`/`.lists-*` của Security sau khi rollover) | Đặt 0 replica cho các index đó (lệnh ngay dưới bảng) |
| Xuất hiện lại `metrics-*` | Pipeline drop bị xoá, hoặc transform endpoint được tạo lại | Chạy `docker compose run --rm setup`; xoá transform (mục 8.4) |
| vmmemWSL chiếm nhiều RAM | Page cache, hoặc chưa có `.wslconfig` | Mục 11 |

Đưa cluster từ `yellow` về `green` (đặt 0 replica cho mọi index có shard chưa được gán):

```bash
set -a; . ./.env; set +a
C="curl -s --ssl-no-revoke --cacert ca.crt -u elastic:$ELASTIC_PASSWORD -H Content-Type:application/json"
idx=$($C "https://localhost:9200/_cat/shards?h=index,state" | awk '$2=="UNASSIGNED"{print $1}' | sort -u | paste -sd, -)
[ -n "$idx" ] && $C -X PUT "https://localhost:9200/$idx/_settings" -d '{"index.number_of_replicas":0}'
```

Thu thập thông tin chẩn đoán:

```bash
docker compose ps -a
docker compose logs --since 30m > elk-logs.txt
docker stats --no-stream
```

Trong VM: `& "C:\Program Files\Elastic\Agent\elastic-agent.exe" diagnostics`.

---

## 14. Tham chiếu cấu hình `.env`

| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `STACK_VERSION` | `9.5.5` | Version ES/Kibana/Agent (phải giống nhau) |
| `CLUSTER_NAME` | `elk-cluster` | Tên cluster |
| `ELASTIC_PASSWORD` | — | Mật khẩu `elastic` (chỉ dùng lúc khởi tạo, sau đó đổi qua API) |
| `KIBANA_PASSWORD` | — | Mật khẩu `kibana_system` |
| `KIBANA_SECURITY_KEY` / `KIBANA_SAVEDOBJECTS_KEY` / `KIBANA_REPORTING_KEY` | — | Khoá mã hoá ≥ 32 ký tự, **không đổi** |
| `BIND_ADDR` | `127.0.0.1` | IP publish ES/Kibana/Fleet trên host |
| `ES_PORT` / `KIBANA_PORT` / `FLEET_PORT` | `9200` / `5601` / `8220` | Cổng trên host |
| `KIBANA_PUBLIC_URL` | `https://localhost:5601` | URL công khai của Kibana |
| `LAB_IP` | `10.20.20.1` | IP host trên mạng VMware. Được publish ES và Fleet, và tự thêm vào SAN chứng chỉ |
| `CERT_EXTRA_DNS` | (trống) | Hostname thêm vào SAN, cách nhau dấu phẩy |
| `CERT_DAYS` | `1095` | Hạn chứng chỉ (ngày) |
| `LOG_RETENTION` | `7d` | Thời gian giữ log trước khi ILM xoá (`logs-retention`) |
| `ES_PLUGINS` | (trống) | Plugin ES cài lúc build, ví dụ `analysis-icu` |
| `ES_HEAP` / `ES_MEM_LIMIT` | `1g` / `2g` | Heap và giới hạn RAM của ES |
| `KIBANA_NODE_HEAP_MB` / `KIBANA_MEM_LIMIT` | `1024` / `1536m` | Heap Node và giới hạn RAM của Kibana |
| `FLEET_MEM_LIMIT` | `768m` | Giới hạn RAM của Fleet Server |
