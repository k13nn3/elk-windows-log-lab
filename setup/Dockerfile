ARG STACK_VERSION=9.5.5
FROM docker.elastic.co/elasticsearch/elasticsearch:${STACK_VERSION}

USER root
COPY --chmod=0755 setup.sh /usr/local/bin/setup.sh
# Phòng trường hợp file bị lưu với CRLF trên Windows
RUN sed -i 's/\r$//' /usr/local/bin/setup.sh

ENTRYPOINT ["/usr/local/bin/setup.sh"]
