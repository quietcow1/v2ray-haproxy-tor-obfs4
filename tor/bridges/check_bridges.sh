#!/bin/bash

BRIDGE_FILE="bridges.json"
TMP_FILE="bridges_tmp.json"
MAX_FAILURES=3
NOW=$(date +%s)

echo "Checking bridge availability..."

echo '{ "bridges": [' > "$TMP_FILE"

jq -c '.bridges[]' "$BRIDGE_FILE" | while read -r bridge; do
    ip=$(echo "$bridge" | jq -r '.ip')
    port=$(echo "$bridge" | jq -r '.port')
    failures=$(echo "$bridge" | jq -r '.failures // 0')
    last_success=$(echo "$bridge" | jq -r '.last_success // 0')

    echo -n "Checking $ip:$port..."

    if nc -z -w5 "$ip" "$port"; then
        echo "Available ✅"
        failures=0
        last_success=$NOW
    else
        echo "Unavailable ❌ (consecutive errors: $((failures + 1)))"
        failures=$((failures + 1))
    fi

    if [[ "$failures" -lt "$MAX_FAILURES" ]]; then
        echo "$bridge" | jq --argjson failures "$failures" --argjson last_success "$last_success" \
            '.failures = $failures | .last_success = $last_success' >> "$TMP_FILE"
        echo "," >> "$TMP_FILE"
    else
        echo "МBridge $ip:$port removed after $failures failures ❌"
    fi
done

sed -i '$ s/,$//' "$TMP_FILE"
echo '] }' >> "$TMP_FILE"

mv "$TMP_FILE" "$BRIDGE_FILE"

echo "The updated bridge list has been saved to $BRIDGE_FILE"
