#!/usr/bin/env bash
# certs:     tạo CA (một lần) + chứng chỉ TLS cho es01/kibana/fleet-server
#            (tạo lại chứng chỉ lá khi danh sách hostname/IP thay đổi, CA giữ nguyên)
# passwords: đặt mật khẩu kibana_system + tạo service token cho Fleet Server
set -euo pipefail
MODE="${1:?Cách dùng: setup.sh certs|passwords}"

CERTS=/usr/share/elasticsearch/config/certs
cd /usr/share/elasticsearch

if [ -z "${ELASTIC_PASSWORD:-}" ] || [ -z "${KIBANA_PASSWORD:-}" ]; then
  echo "ELASTIC_PASSWORD và KIBANA_PASSWORD phải được đặt trong .env" >&2
  exit 1
fi

# Chuyển "a, b,c" thành các dòng YAML "      - a"
yaml_list() {
  local out="" item
  IFS=',' read -ra items <<< "${1:-}"
  for item in "${items[@]}"; do
    item="$(echo "$item" | xargs)"
    [ -n "$item" ] && out+="      - ${item}"$'\n'
  done
  printf '%s' "$out"
}

if [ "$MODE" = "certs" ]; then
  if [ ! -f "$CERTS/ca/ca.crt" ]; then
    echo "Tạo CA..."
    bin/elasticsearch-certutil ca --silent --pem --days "${CERT_DAYS}" --out "$CERTS/ca.zip"
    unzip -o -q "$CERTS/ca.zip" -d "$CERTS"
    rm -f "$CERTS/ca.zip"
  fi

  # CERT_EXTRA_DNS / CERT_EXTRA_IP: hostname/IP để máy khác (vd: VM trong VMware) truy cập
  extra_dns="$(yaml_list "${CERT_EXTRA_DNS:-}")"
  extra_ip="$(yaml_list "${CERT_EXTRA_IP:-}")"
  instances=""
  for name in es01 kibana fleet-server; do
    instances+="  - name: ${name}
    dns:
      - ${name}
      - localhost
${extra_dns}
    ip:
      - 127.0.0.1
${extra_ip}
"
  done
  # $(...) cắt mất dấu xuống dòng cuối nên chèn dòng riêng rồi bỏ dòng trống
  printf 'instances:\n%s' "$instances" | sed '/^ *$/d' > "$CERTS/instances.yml.new"

  if [ "$(cat "$CERTS/instances.yml.new")" != "$(cat "$CERTS/instances.yml" 2>/dev/null)" ] \
     || [ ! -f "$CERTS/fleet-server/fleet-server.crt" ]; then
    echo "Tạo chứng chỉ cho es01, kibana, fleet-server..."
    mv "$CERTS/instances.yml.new" "$CERTS/instances.yml"
    bin/elasticsearch-certutil cert --silent --pem --days "${CERT_DAYS}" \
      --in "$CERTS/instances.yml" --out "$CERTS/certs.zip" \
      --ca-cert "$CERTS/ca/ca.crt" --ca-key "$CERTS/ca/ca.key"
    unzip -o -q "$CERTS/certs.zip" -d "$CERTS"
    rm -f "$CERTS/certs.zip"
  else
    rm -f "$CERTS/instances.yml.new"
  fi

  # Chuỗi cert lá + CA, để client chỉ cần biết fingerprint của CA (Fleet/Agent dùng cách này)
  for name in es01 kibana fleet-server; do
    cat "$CERTS/$name/$name.crt" "$CERTS/ca/ca.crt" > "$CERTS/$name/$name-chain.crt"
  done
  # SHA-256 fingerprint của CA (dạng hex) cho ca_trusted_fingerprint của Fleet output
  sed '/-----/d' "$CERTS/ca/ca.crt" | base64 -d | sha256sum | cut -d' ' -f1 > "$CERTS/ca/ca.fingerprint"

  # es01/kibana/fleet-server chạy với uid 1000, có group 0 → cấp quyền đọc cho group root
  chown -R root:root "$CERTS"
  find "$CERTS" -type d -exec chmod 750 {} \;
  find "$CERTS" -type f -exec chmod 640 {} \;
  echo "Chứng chỉ đã sẵn sàng. CA fingerprint: $(cat "$CERTS/ca/ca.fingerprint")"
  exit 0
fi

ES="https://es01:9200"
es() { curl -s --cacert "$CERTS/ca/ca.crt" -u "elastic:${ELASTIC_PASSWORD}" -H 'Content-Type: application/json' "$@"; }

echo "Chờ Elasticsearch sẵn sàng..."
until curl -s --cacert "$CERTS/ca/ca.crt" "$ES" | grep -q 'missing authentication credentials'; do
  sleep 5
done

echo "Đặt mật khẩu cho kibana_system..."
until es -X POST "$ES/_security/user/kibana_system/_password" \
    -d "{\"password\":\"${KIBANA_PASSWORD}\"}" | grep -q '^{}'; do
  sleep 5
done

# Retention: rollover mỗi ngày, xoá index 7 ngày sau rollover (log được giữ khoảng 7–8 ngày)
LOG_RETENTION="${LOG_RETENTION:-7d}"
es -X PUT "$ES/_ilm/policy/logs-retention" -d "{\"policy\":{
  \"_meta\":{\"description\":\"Keep logs ${LOG_RETENTION}: rollover daily, delete ${LOG_RETENTION} after rollover\"},
  \"phases\":{
    \"hot\":{\"actions\":{\"rollover\":{\"max_age\":\"1d\",\"max_primary_shard_size\":\"10gb\"}}},
    \"delete\":{\"min_age\":\"${LOG_RETENTION}\",\"actions\":{\"delete\":{}}}}}}" >/dev/null

# logs@custom được mọi template logs-* (kể cả integration) dùng:
# - 0 replica: single-node không có node thứ 2 cho replica → cluster "green"
# - ILM logs-retention thay cho logs@lifecycle mặc định (không bao giờ xoá)
es -X PUT "$ES/_component_template/logs@custom" \
  -d '{"template":{"settings":{"index.number_of_replicas":0,"index.lifecycle.name":"logs-retention"}}}' >/dev/null
# Index đang có không tự nhận template mới → gán policy trực tiếp
es -X PUT "$ES/logs-*/_settings" -d '{"index.lifecycle.name":"logs-retention"}' >/dev/null

# Chỉ giữ log: bỏ metrics do Kibana Fleet-Metrics-Task ghi mỗi phút (không có setting để tắt)
for ds in metrics-fleet_server.agent_status metrics-fleet_server.agent_versions; do
  es -X PUT "$ES/_ingest/pipeline/$ds@custom" \
    -d '{"description":"Bỏ metrics do Kibana Fleet-Metrics-Task ghi (chỉ giữ log)","processors":[{"drop":{}}]}' >/dev/null
done

TOKEN_FILE="$CERTS/fleet-server/service-token"
if [ ! -s "$TOKEN_FILE" ]; then
  echo "Tạo service token cho Fleet Server..."
  es -X DELETE "$ES/_security/service/elastic/fleet-server/credential/token/fleet-server-token" >/dev/null || true
  es -X POST "$ES/_security/service/elastic/fleet-server/credential/token/fleet-server-token" \
    | sed -n 's/.*"value":"\([^"]*\)".*/\1/p' > "$TOKEN_FILE"
  if [ ! -s "$TOKEN_FILE" ]; then
    echo "Không tạo được service token" >&2
    exit 1
  fi
  chown root:root "$TOKEN_FILE"
  chmod 640 "$TOKEN_FILE"
fi

echo "Setup hoàn tất."
