#!/bin/bash

### CUSTOM VARIABLES HERE /dev/ttyUSB0 or /dev/ttyUSB1 or /dev/ttyUSB0 ###
MODPOLL="/usr/bin/mbpoll"
SERIAL_PORT="/dev/ttyUSB0"
MQTT_BROKER="127.0.0.1"
MQTT_PORT="1883"
MQTT_TOPIC="homeassistant/sensor/jk_bms/state"
INTERVALLE=2

lire_bms_16bit() {
    local registre=$1
    local compte=$2
    $MODPOLL -m rtu -b 115200 -P none -o 2.00 -0 -t 4 -r "$registre" -c "$compte" -1 -q "$SERIAL_PORT" 2>/dev/null
}

while true; do
    B1=$(lire_bms_16bit 4608 16)
    B2=$(lire_bms_16bit 4752 26)
    B3=$(lire_bms_16bit 4772 2)
    B4=$(lire_bms_16bit 4746 1)

    if [ ! -z "$B1" ] && [ ! -z "$B2" ] && [ ! -z "$B3" ] && [ ! -z "$B4" ]; then
        JSON_PAYLOAD=$(awk '
        BEGIN {
            printf "{";
            c_max = 0;
            c_min = 99;
            idx_max = 1;
            idx_min = 1;
            cell_count = 0;
        }
        /^[[:space:]]*\[[0-9]+\]:/ {
            clean_reg = $1;
            gsub(/[\[\]:]/, "", clean_reg);
            val[clean_reg] = $2;
        }
        END {
            # 1. Extraction and calculation of Individual Cells (4608 to 4623)
            for (i = 4608; i <= 4623; i++) {
                if (i in val) {
                    cell_idx = i - 4607;
                    v_cell = val[i] / 1000;
                    printf "\"cell_%02d\":%.3f,", cell_idx, v_cell;
                    cell_count++;
                    if (v_cell > c_max) { c_max = v_cell; idx_max = cell_idx; }
                    if (v_cell < c_min) { c_min = v_cell; idx_min = cell_idx; }
                }
            }

            # 2. Reconstitution of 32-bit blocks
            v_voltage = (val[4752] * 65536) + val[4753];
            v_power = (val[4754] * 65536) + val[4755];
            v_current = (val[4756] * 65536) + val[4757];
            v_bal_cur = (val[4762] * 65536) + val[4763];
            v_remain = (val[4764] * 65536) + val[4765];
            v_cyc_cap = (val[4770] * 65536) + val[4771];

            # 32-bit signed integers management
            if (v_current > 2147483647) v_current = v_current - 4294967296;
            if (v_power > 2147483647) v_power = v_power - 4294967296;

            # 3. Extraction of 16-bit values
            # AUTHENTIC EXTRACTION FROM ISOLATED READ OF REGISTER 4746
            v_temp_mos = val[4746];
            if (v_temp_mos > 32767) v_temp_mos = v_temp_mos - 65536;
            v_temp_mos = v_temp_mos / 10;
            v_temp_01 = val[4758] / 10;
            v_temp_02 = val[4759] / 10;

            # Cycles count JKBMS
            v_cycles = val[4769];

            # SOC from B3 block
            v_soc = val[4773];

            # Average V calculation
            v_tot_fixed = v_voltage / 1000;
            v_avg_cell = (cell_count > 0) ? (v_tot_fixed / cell_count) : 0;

            # 4. Final JSON
            printf "\"total_voltage\":%.2f,", v_tot_fixed;
            printf "\"power\":%.1f,", v_power / 1000;
            printf "\"current\":%.2f,", v_current / 1000;
            printf "\"temp_mos\":%.1f,", v_temp_mos;
            printf "\"temp_01\":%.1f,", v_temp_01;
            printf "\"temp_02\":%.1f,", v_temp_02;
            printf "\"cell_avg_voltage\":%.3f,", v_avg_cell;
            printf "\"balance_current\":%.3f,", v_bal_cur / 1000;
            printf "\"cap_remaining\":%.2f,", v_remain / 1000;
            printf "\"cycle_count\":%d,", v_cycles;
            printf "\"cycle_capacity\":%.1f,", v_cyc_cap / 1000;
            printf "\"soc\":%.1f,", v_soc;
            printf "\"cap_nominal\":314.00,";
            printf "\"max_cell_voltage\":%.3f,", c_max;
            printf "\"max_cell_number\":%d,", idx_max;
            printf "\"min_cell_voltage\":%.3f,", c_min;
            printf "\"min_cell_number\":%d,", idx_min;
            printf "\"delta_cell_voltage\":%.3f,", c_max - c_min;
            printf "\"bms_status\":\"online\"}"
        }
        ' <<EOF
$B1
$B2
$B3
$B4
EOF
        )

        # Pub on local MQTT Broker
        if [ ! -z "$JSON_PAYLOAD" ] && [[ "$JSON_PAYLOAD" == *"total_voltage"* ]]; then
            mosquitto_pub -h "$MQTT_BROKER" -p "$MQTT_PORT" -t "$MQTT_TOPIC" -m "$JSON_PAYLOAD" -r
            echo "MQTT Update -> $JSON_PAYLOAD"
        fi
    fi

    sleep "$INTERVALLE"
done
