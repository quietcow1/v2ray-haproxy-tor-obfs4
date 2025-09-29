FROM alpine:latest

EXPOSE 8118

RUN apk update && \
    apk add --no-cache privoxy runit tini && \
    mkdir -p /etc/service/privoxy

RUN echo '#!/bin/sh' > /etc/service/privoxy/run && \
    echo 'privoxy --no-daemon /etc/privoxy/config' >> /etc/service/privoxy/run && \
    chmod +x /etc/service/privoxy/run

RUN mkdir -p /etc/privoxy && \
    echo "listen-address 0.0.0.0:8118" > /etc/privoxy/config && \
    echo "forward / haproxy:8119" >> /etc/privoxy/config

ENTRYPOINT ["tini", "--"]
CMD ["runsvdir", "/etc/service"]