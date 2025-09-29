#!/bin/bash

rm -fr /etc/tor
rm -fr /var/lib/tor

mkdir -p /etc/tor
mkdir -p /var/lib/tor
mkdir -p /etc/service/privoxy
mkdir -p /etc/service/tor

torrc="/etc/tor/torrc"

cat > "$torrc" <<EOF
SOCKSPort 127.0.0.1:9050
DataDirectory /var/lib/tor
AutomapHostsOnResolve 1
VirtualAddrNetworkIPv4 10.192.0.0/10
UseBridges 1
ExcludeExitNodes {ru}
StrictNodes 1
CircuitBuildTimeout 60
ClientTransportPlugin obfs4 exec /usr/bin/lyrebird
EOF

jq -c '.bridges[]' /bridges/bridges.json | while read -r bridge; do
  ip=$(echo "$bridge" | jq -r '.ip')
  port_b=$(echo "$bridge" | jq -r '.port')
  fingerprint=$(echo "$bridge" | jq -r '.fingerprint')
  cert=$(echo "$bridge" | jq -r '.cert')
  iat=$(echo "$bridge" | jq -r '.["iat-mode"]')

  echo "Bridge obfs4 $ip:$port_b $fingerprint cert=$cert iat-mode=$iat" >> "$torrc"
done

cat > "/etc/service/tor/run" <<EOF
#!/bin/bash
exec tor -f $torrc
EOF
chmod +x /etc/service/tor/run

cat > "/delayed_restart.sh" <<EOF
#!/bin/bash
echo "[INFO] Waiting 1 hour before restarting Tor..." >> /var/log/restart_tor.log
sleep 3600
echo "[INFO] Restarting Tor now..." >> /var/log/restart_tor.log
kill 1
EOF
chmod +x /delayed_restart.sh

CRONTAB_FILE="/etc/crontabs/root"
> "$CRONTAB_FILE"

echo "CRON_TASKS=$CRON_TASKS"
echo "CRON_SCHEDULE=$CRON_SCHEDULE"

IFS=',' read -ra TASKS <<< "$CRON_TASKS"
for task in "${TASKS[@]}"; do
  case "$task" in
    get_bridges)
      printf '%s\n' "$CRON_SCHEDULE /bridges/new_bridges.sh >> /var/log/get_bridges.log 2>&1" >> "$CRONTAB_FILE"
      ;;
    check_bridges)
      printf '%s\n' "$CRON_SCHEDULE /bridges/check_bridges.sh >> /var/log/check_bridges.log 2>&1" >> "$CRONTAB_FILE"
      ;;
    restart_tor)
      printf '%s\n' "$CRON_SCHEDULE /delayed_restart.sh >> /var/log/restart_tor.log 2>&1" >> "$CRONTAB_FILE"
      ;;
  esac
done

mkdir -p /etc/privoxy

cat > /etc/privoxy/config <<EOF
listen-address  0.0.0.0:8118
forward-socks5t / 127.0.0.1:9050 .
toggle 1
enable-remote-toggle 0
enable-remote-http-toggle 0
enable-edit-actions 0
buffer-limit 4096
EOF

cat > /etc/service/privoxy/run <<EOF
#!/bin/bash
exec privoxy --no-daemon /etc/privoxy/config
EOF
chmod +x /etc/service/privoxy/run

crond -f &
exec runsvdir -P /etc/service
