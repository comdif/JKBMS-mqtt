#!/bin/bash
### CUSTOM VARIABLES HERE /dev/ttyUSB0 or /dev/ttyUSB1 or ..
SERIAL_PORT="/dev/ttyUSB0"
MQTT_BROKER="127.0.0.1"
MQTT_PORT="1883"
MQTT_TOPIC="homeassistant/sensor/jkbms/state"
INTERVALLE=2

lire_bms() {
    local registre=$1
    local compte=$2
    local tentative=1
    local max_tentatives=3
    local resultat=""

    while [ $tentative -le $max_tentatives ]; do
        resultat=$(mbpoll -m rtu -b 115200 -P none -o 2.00 -0 -t 4 -r "$registre" -c "$compte" -1 -q "$SERIAL_PORT" 2>/dev/null)
        
        if [ ! -z "$resultat" ] && [[ "$resultat" == *"["* ]]; then
            echo "$resultat"
            return 0
        fi
        
        echo "Echec lecture registre $registre (Tentative $tentative/$max_tentatives)... Nouvelle tentative." >&2
        sleep 0.05
        ((tentative++))
    done

    return 1
}

while true; do
    B1=$(lire_bms 4608 12)
    B2=$(lire_bms 4620 4)
    B3=$(lire_bms 4752 8)
    B4=$(lire_bms 4770 5)

    if [ ! -z "$B1" ] && [ ! -z "$B2" ] && [ ! -z "$B3" ] && [ ! -z "$B4" ]; then
        JSON_PAYLOAD=$(awk '
        BEGIN {
            printf "{"
        }
        $1 ~ /\[[0-9]+\]/ {
            reg = $1; val = $2;
            gsub(/[\[\]:]/, "", reg);
            
            if (reg >= 4608 && reg <= 4619) {
                printf "\"cell_%02d\":%.3f,", reg - 4607, val/1000;
            } else if (reg >= 4620 && reg <= 4623) {
                printf "\"cell_%02d\":%.3f,", reg - 4607, val/1000;
            } else if (reg == 4753) {
                printf "\"total_voltage\":%.2f,", val/1000;
            } else if (reg == 4755) {
                if (val > 32767) val = val - 65536;
                printf "\"current\":%.2f,", val/1000;
            } else if (reg == 4758) {
                printf "\"temp_01\":%.1f,", val/10;
            } else if (reg == 4772) {
                soc_val = and(val, 255);
                printf "\"soc\":%d,", soc_val;
            }
        }
        END {
            printf "\"bms_status\":\"online\"}"
        }
        ' <<EOF
$B1
$B2
$B3
$B4
EOF
)
        if [ ! -z "$JSON_PAYLOAD" ] && [[ "$JSON_PAYLOAD" == *"total_voltage"* ]]; then
            mosquitto_pub -h "$MQTT_BROKER" -p "$MQTT_PORT" -t "$MQTT_TOPIC" -m "$JSON_PAYLOAD" -r
            echo "MQTT Pro -> $JSON_PAYLOAD"
        fi
    fi
    sleep "$INTERVALLE"
done
