# Cài Elastic Agent lên VM Windows trong VMware

Agent trong VM enroll vào Fleet Server và gửi **event log Windows** về Elasticsearch trên host.

```
VM (10.20.20.10, adapter "LAB")  ──8220──▶  Fleet Server  (10.20.20.1)
                                 ──9200──▶  Elasticsearch (10.20.20.1)
```

Policy: **Windows Servers** (namespace `endpointwindow`): Application, System, Security, PowerShell,
PowerShell/Operational, Sysmon/Operational, Forwarded Events. Chỉ thu log, không thu metric.
Dữ liệu vào các data stream `logs-<dataset>-endpointwindow`, xem trên data view **WindowLog-Endpoint**.

Tài liệu vận hành tổng thể: [README.md](../README.md).

## 0. Chuẩn bị

**Trên host:**

- Stack đang chạy: `docker compose ps` → `es01`, `kibana`, `fleet-server` đều Up.
- Thư mục `fleet/` (cũng là bộ cài để copy vào VM) có đủ các file sau:

  | File | Nguồn |
  |---|---|
  | `install-agent-windows.ps1`, `HUONG-DAN-CAI-AGENT.md` | Có sẵn trong repo |
  | `ca.crt` | CA của stack (README mục 4) |
  | `enrollment-token.txt` | Kibana → Fleet → Enrollment tokens → *Windows Servers* |
  | `elastic-agent-9.5.5-windows-x86_64.zip` + `.zip.sha512` | Tải từ artifacts.elastic.co (README mục 4) |

**Trên VM:**

- Card mạng gắn vào **LAB (VMnet3)**, IP tĩnh `10.20.20.x / 255.255.255.0`. Không cần gateway hay DNS.
- **Múi giờ đúng.** Windows tiếng Anh mặc định để UTC−7, khiến đồng hồ lệch 14 tiếng so với host.
  Sửa múi giờ chứ **không chỉnh giờ bằng tay**, rồi kiểm tra bằng `Get-Date` (phải khớp giờ của host):

  ```powershell
  Set-TimeZone -Id "SE Asia Standard Time"
  Get-Date
  ```

  Nên bật thêm: VMware → VM → Settings → Options → VMware Tools → **Synchronize guest time with host**.

## 1. Copy bộ cài vào VM

Chọn một trong các cách sau (cách a và b cần VMware Tools trong VM):

- **a. Kéo thả**: kéo thư mục `fleet` từ Explorer của host vào desktop của VM.
- **b. Shared Folders**: VM → Settings → Options → Shared Folders → *Always enabled* → Add
  `D:\ELK-Setup\fleet`. Trong VM, mở `\\vmware-host\Shared Folders\fleet`.
- **c. Không có VMware Tools**: đóng gói thư mục thành ISO rồi gắn vào CD/DVD của VM.

Copy thư mục vào **`C:\fleet`** trong VM. Không chạy trực tiếp từ shared folder.

## 2. Kiểm tra kết nối từ VM

Mở **PowerShell (Run as Administrator)** trong VM:

```powershell
Test-NetConnection 10.20.20.1 -Port 8220
Test-NetConnection 10.20.20.1 -Port 9200
```

Cả hai phải ra `TcpTestSucceeded : True`. Nếu ra `False`, xem mục Xử lý lỗi bên dưới.

## 3. Cài agent

```powershell
cd C:\fleet
Set-ExecutionPolicy -Scope Process Bypass
.\install-agent-windows.ps1
```

Script sẽ lần lượt:
1. Kiểm tra quyền Administrator và kết nối tới 8220/9200.
2. Copy `ca.crt` vào `C:\ProgramData\Elastic\ca.crt`.
3. Giải nén zip, chạy `elastic-agent.exe install` với URL Fleet, enrollment token và CA.
4. In `elastic-agent status`. Mong đợi: `elastic-agent: Healthy`, `fleet: Connected`.

<details>
<summary>Cài tay (nếu không dùng script)</summary>

```powershell
New-Item -ItemType Directory -Force C:\ProgramData\Elastic | Out-Null
Copy-Item C:\fleet\ca.crt C:\ProgramData\Elastic\ca.crt
Expand-Archive C:\fleet\elastic-agent-9.5.5-windows-x86_64.zip -DestinationPath C:\fleet\agent
cd C:\fleet\agent\elastic-agent-9.5.5-windows-x86_64
.\elastic-agent.exe install --url=https://10.20.20.1:8220 `
  --enrollment-token=(Get-Content C:\fleet\enrollment-token.txt -Raw).Trim() `
  --certificate-authorities=C:\ProgramData\Elastic\ca.crt
```
</details>

## 4. Kiểm tra trên Kibana (host)

1. https://localhost:5601 → **Fleet → Agents**: VM xuất hiện với policy *Windows Servers*, trạng thái **Healthy**.
2. **Discover** → data view **WindowLog-Endpoint** → lọc thử:
   - `data_stream.dataset : "system.security"`: đăng nhập, tạo user...
   - `data_stream.dataset : "system.system"` / `"system.application"`
   - `data_stream.dataset : "windows.powershell_operational"`
3. Tạo thử sự kiện trong VM: `eventcreate /T INFORMATION /ID 100 /L APPLICATION /D "ELK test"`.
   Sau khoảng 10–30 giây, sự kiện sẽ xuất hiện ở dataset `system.application`.

## 5. Xử lý lỗi

| Hiện tượng | Cách xử lý |
|---|---|
| `TcpTestSucceeded : False` | Trên **host**: `docker compose ps` để xem các service còn chạy không. Kiểm tra VM đang dùng adapter **LAB** (VMnet3) với IP `10.20.20.x/24`. Nếu vẫn bị chặn, mở PowerShell Admin trên host và thêm rule firewall: `New-NetFirewallRule -DisplayName "ELK from LAB" -Direction Inbound -Protocol TCP -LocalPort 8220,9200 -RemoteAddress 10.20.20.0/24 -Action Allow` |
| `x509: certificate signed by unknown authority` | Thiếu hoặc sai `ca.crt`. Copy lại từ thư mục `fleet`. CA đúng có SHA-256 trùng với `ca.fingerprint` trên host (`docker compose exec es01 cat config/certs/ca/ca.fingerprint`) |
| `x509: certificate has expired or is not yet valid` | Đồng hồ VM bị lệch. Thường là do sai **múi giờ** (mục 0): `Set-TimeZone -Id "SE Asia Standard Time"` và bật đồng bộ giờ qua VMware Tools |
| `invalid enrollment token` / 401 | Token bị thu hồi. Lấy token mới: Kibana → Fleet → Enrollment tokens → policy *Windows Servers*, ghi đè `enrollment-token.txt` |
| Agent **Unhealthy** / **Offline** | Trong VM: `& "C:\Program Files\Elastic\Agent\elastic-agent.exe" status`, `Restart-Service "Elastic Agent"`. Log nằm ở `C:\Program Files\Elastic\Agent\data\elastic-agent-*\logs\` |
| Không có dữ liệu Sysmon | Cần cài Sysmon trong VM (Sysinternals). Các stream khác không bị ảnh hưởng |

Thu thập thông tin chẩn đoán: `& "C:\Program Files\Elastic\Agent\elastic-agent.exe" diagnostics`.

## 6. Gỡ agent

```powershell
& "C:\Program Files\Elastic\Agent\elastic-agent.exe" uninstall
```

Sau đó vào Kibana → Fleet → Agents → *Unenroll* agent cũ.
