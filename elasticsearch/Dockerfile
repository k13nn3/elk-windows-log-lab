ARG STACK_VERSION=9.5.5
FROM docker.elastic.co/elasticsearch/elasticsearch:${STACK_VERSION}

# Plugin tuỳ chọn, ví dụ: --build-arg ES_PLUGINS="analysis-icu analysis-phonetic"
ARG ES_PLUGINS=""
RUN if [ -n "$ES_PLUGINS" ]; then \
      for p in $ES_PLUGINS; do bin/elasticsearch-plugin install --batch "$p"; done; \
    fi

COPY --chown=1000:0 --chmod=0660 elasticsearch.yml /usr/share/elasticsearch/config/elasticsearch.yml

HEALTHCHECK --interval=10s --timeout=10s --start-period=60s --retries=30 \
  CMD curl -s --cacert config/certs/ca/ca.crt https://localhost:9200 | grep -q 'missing authentication credentials'
