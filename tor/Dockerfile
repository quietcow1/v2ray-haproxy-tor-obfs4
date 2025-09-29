FROM alpine:latest

EXPOSE 8118 9050

RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    apk update && \
    apk add --no-cache tor privoxy curl grep gawk bash runit tini lyrebird jq dcron&& \
    rm -fr /etc/service
    
COPY start.sh /start.sh
COPY bridges /bridges
RUN chmod +x /start.sh /bridges/new_bridges.sh /bridges/check_bridges.sh
    
ENTRYPOINT ["tini", "--"]
CMD ["/start.sh"]
