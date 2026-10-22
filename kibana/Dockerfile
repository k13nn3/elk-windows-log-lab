ARG STACK_VERSION=9.5.5
FROM docker.elastic.co/kibana/kibana:${STACK_VERSION}

COPY --chown=1000:0 --chmod=0660 kibana.yml /usr/share/kibana/config/kibana.yml
COPY --chmod=0755 entrypoint.sh /usr/local/bin/kibana-entrypoint.sh
USER root
# Phòng trường hợp file bị lưu với CRLF trên Windows
RUN sed -i 's/\r$//' /usr/local/bin/kibana-entrypoint.sh
USER 1000

ENTRYPOINT ["/bin/tini", "--", "/usr/local/bin/kibana-entrypoint.sh"]

HEALTHCHECK --interval=10s --timeout=10s --start-period=60s --retries=60 \
  CMD curl -s -I --cacert config/certs/ca/ca.crt https://localhost:5601 | grep -qE '^HTTP/[0-9.]+ 302'
