#!/bin/bash

PRIVOXY_PROXY="privoxy:8118"
BRIDGE_URL="https://bridges.torproject.org/bridges?transport=obfs4"
BRIDGE_FILE="bridges.json"
NOW=$(date +%s)

join_by_comma() {
    local first=true
    for element in "$@"; do
        if [ "$first" = true ]; then
            first=false
            echo -n "$element"
        else
            echo -n ", $element"
        fi
    done
}

fetch_bridges() {
    bridges=$(curl --silent --proxy $PRIVOXY_PROXY "$BRIDGE_URL" | grep -oP 'obfs4 [^<]+')
    
    declare -A new_bridges
    if [[ -n "$bridges" ]]; then
        while IFS= read -r line; do
            ip_port=$(echo "$line" | awk '{print $2}')
            ip=${ip_port%:*}
            port=${ip_port##*:}
            fingerprint=$(echo "$line" | awk '{print $3}')
            cert=$(echo "$line" | awk -F'cert=' '{print $2}' | awk '{print $1}' | sed 's/&#43;/+/g')
            
            if ! [[ "$port" =~ ^[0-9]+$ ]]; then
                echo "Error: Invalid port '$port' in line: $line"
                continue
            fi
            
            bridge_key=$(echo "$ip:$port:$fingerprint" | sed 's/:/_/g')
            new_bridges["$bridge_key"]="{\"type\":\"obfs4\",\"ip\":\"$ip\",\"port\":$port,\"fingerprint\":\"$fingerprint\",\"cert\":\"$cert\",\"iat-mode\":0,\"last_success\":$NOW,\"failures\":0}"
        done <<< "$bridges"
    fi
    
    declare -A existing_bridges
    if [[ -f "$BRIDGE_FILE" ]]; then
        existing=$(jq -c '.bridges[]' "$BRIDGE_FILE" 2>/dev/null || echo "")
        if [[ -n "$existing" ]]; then
            while IFS= read -r bridge; do
                ip=$(echo "$bridge" | jq -r '.ip')
                port=$(echo "$bridge" | jq -r '.port')
                fingerprint=$(echo "$bridge" | jq -r '.fingerprint')
                bridge_key=$(echo "$ip:$port:$fingerprint" | sed 's/:/_/g')
                existing_bridges["$bridge_key"]="$bridge"
            done <<< "$existing"
        fi
    fi
    
    for key in "${!new_bridges[@]}"; do
        existing_bridges["$key"]="${new_bridges[$key]}"
    done
    
    json="[$(join_by_comma "${existing_bridges[@]}")]"
    echo "{\"bridges\": $json}" | jq . > "$BRIDGE_FILE"
    
    echo "Updated ${#new_bridges[@]} new bridges, total ${#existing_bridges[@]} in $BRIDGE_FILE"
}

if [[ -f $BRIDGE_FILE ]]; then
    echo "$BRIDGE_FILE found, updating bridge list."
else
    echo "$BRIDGE_FILE not found, creating a new one."
fi

fetch_bridges
