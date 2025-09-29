#!/bin/bash

read -p "Сколько экземпляров Tor Вы хотите запустить? // How many Tor instances do you want to run? (Default: 3): " COUNT
COUNT=${COUNT:-3}

read -p "Вам нужен V2Ray? // Do you need V2Ray? (Y/n): " V2RAY_CHOICE
V2RAY_CHOICE=$(echo "${V2RAY_CHOICE:-y}" | tr '[:upper:]' '[:lower:]')

USE_V2RAY=false
if [[ "$V2RAY_CHOICE" == "y" || "$V2RAY_CHOICE" == "yes" ]]; then
  USE_V2RAY=true
fi

read -p "Вам нужен Caddy? // Do you need Caddy? (Y/n): " CADDY_CHOICE
CADDY_CHOICE=$(echo "${CADDY_CHOICE:-y}" | tr '[:upper:]' '[:lower:]')

USE_CADDY=false
if [[ "$CADDY_CHOICE" == "y" || "$CADDY_CHOICE" == "yes" ]]; then
  USE_CADDY=true
fi

DOCKER_COMPOSE="docker-compose.yml"
cat > "$DOCKER_COMPOSE" <<EOF
services:
EOF

for ((i = 1; i <= COUNT; i++)); do
  if [ "$i" -eq 1 ]; then
    CRON_SCHEDULE="0 3 * * *"
    CRON_TASKS="get_bridges,check_bridges,restart_tor"
    VOLUME_MODE="rw"
  else
    offset=$(( (i - 1) * 3 ))
    CRON_SCHEDULE="$((offset % 60)) $((3 + (offset / 60))) * * *"
    CRON_TASKS="restart_tor"
    VOLUME_MODE="ro"
  fi

cat >> "$DOCKER_COMPOSE" <<EOF
  tor$i:
    build: ./tor
    container_name: tor$i
    volumes:
      - ./tor/bridges:/bridges:$VOLUME_MODE
    environment:
      - CRON_SCHEDULE=$CRON_SCHEDULE
      - CRON_TASKS=$CRON_TASKS
    restart: unless-stopped
    networks:
      - tor_net

EOF
done

cat >> "$DOCKER_COMPOSE" <<EOF
  haproxy:
    image: haproxy:latest
    container_name: haproxy
    volumes:
      - ./haproxy:/usr/local/etc/haproxy:ro
    sysctls:
      net.ipv4.ip_unprivileged_port_start: 0
    ports:
      - "8119:8119"
    restart: unless-stopped
    networks:
      - tor_net

EOF

cat >> "$DOCKER_COMPOSE" <<EOF
  privoxy:
    build: ./privoxy
    container_name: privoxy
    ports:
      - "8118:8118"
    restart: unless-stopped
    networks:
      - tor_net

EOF

if [ "$USE_V2RAY" = true ]; then
cat >> "$DOCKER_COMPOSE" <<EOF
  v2ray:
    image: v2fly/v2fly-core
    container_name: v2ray
    restart: unless-stopped
    ports:
      - "10086:10086"
    volumes:
      - ./v2ray/config.json:/etc/v2ray/config.json
    command: run -c /etc/v2ray/config.json
    environment:
      - v2ray.vmess.aead.forced=false
    networks:
      - tor_net

EOF
fi

HAPROXY_CFG="./haproxy/haproxy.cfg"
mkdir -p ./haproxy

cat > "$HAPROXY_CFG" <<EOF
defaults
  mode http
  timeout client 10s
  timeout connect 5s
  timeout server 10s 
  timeout http-request 10s
  option http-server-close

frontend myfrontend
  bind *:8119
  default_backend myservers

backend myservers
  balance roundrobin
EOF

for ((i = 1; i <= COUNT; i++)); do
  echo "  server tor$i tor$i:8118 check" >> "$HAPROXY_CFG"
done

echo "✅ Конфигурация HAProxy сгенерированы. // HAProxy configuration has been updated."

if [ "$USE_V2RAY" = true ]; then
    read -p "🔧 Введите ваш UUID (оставьте пустым для автоматической генерации) // Enter your UUID (leave blank to auto-generate): " CUSTOM_UUID
    UUID=${CUSTOM_UUID:-$(uuidgen)}
  
    CONFIG_PATH="./v2ray/config.json"
    mkdir -p "$(dirname "$CONFIG_PATH")"

    cat > "$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": 10086,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/v2ray"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "http",
      "settings": {
        "servers": [
          {
            "address": "privoxy",
            "port": 8118
          }
        ]
      },
      "streamSettings": {
        "network": "tcp"
      }
    }
  ]
}
EOF

    echo "✅ Конфигурация V2Ray сгенерированы // V2Ray config generated at $CONFIG_PATH"
    echo "🆔 Итоговый UUID клиента // Final client UUID: $UUID"
fi

if [ "$USE_CADDY" = true ]; then
  read -p "🌐 Введите Ваш домен для Caddy // Enter your domain for Caddy (e.g., example.com): " DOMAIN
  DOMAIN=${DOMAIN,,}

  CONFIG_PATH="./caddy/conf/Caddyfile"
  mkdir -p ./caddy/conf
  mkdir -p ./caddy/site
  cat > "$CONFIG_PATH" <<EOF
$DOMAIN {
  reverse_proxy v2ray:10086 {
    header_up Host {host}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Proto {scheme}
    }
}
EOF

  echo "✅ Конфигурация Caddy сгенерированы // Caddyfile generated at $CONFIG_PATH for domain: $DOMAIN"
fi

if [ "$USE_CADDY" = true ]; then
  cat >> "$DOCKER_COMPOSE" <<EOF
  caddy:
    image: caddy:alpine
    container_name: caddy
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./caddy/conf:/etc/caddy
      - ./caddy/site:/srv
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - tor_net

volumes:
  caddy_data:
  caddy_config:
  
EOF
fi

cat >> "$DOCKER_COMPOSE" <<EOF
networks:
  tor_net:
    driver: bridge
EOF

echo "✅ Файл docker-compose.yml создан. // The docker-compose.yml file has been created."

read -p "Запустить контейнеры сейчас с пересборкой образов? // Start the containers now with image rebuild? (Y/n): " RUN_NOW
RUN_NOW=$(echo "${RUN_NOW:-y}" | tr '[:upper:]' '[:lower:]')

if [[ "$RUN_NOW" == "y" || "$RUN_NOW" == "yes" ]]; then
  docker compose up -d --build
  echo "🚀 Контейнеры были пересобраны и запущены. // Containers have been rebuilt and started."
  else
  echo "📝 Контейнеры не были запущены. Запустите их вручную с помощью команды:
docker compose up -d --build // Containers were not started. Start them manually with: docker compose up -d --build"
fi