#!/bin/bash
#Change for your USB/RS485 device address
SERIAL_PORT="/dev/ttyUSB0"
MQTT_BROKER="127.0.0.1"
MQTT_PORT="1883"
MQTT_TOPIC="homeassistant/sensor/jk_bms/state"
INTERVALLE=2

# ==============================================================================
# CALIBRATION PARAMETERS
# ==============================================================================
ch_adjust_value=1.0728
disch_adjust_value=1000
last_valid_soc=""
# ==============================================================================

lire_bms_16bit() {
    local registre=$1
    local compte=$2
    mbpoll -m rtu -b 115200 -P none -o 2.00 -0 -t 4 -r "$registre" -c "$compte" -1 -q "$SERIAL_PORT" 2>/dev/null
}

while true; do
    B_TOTAL=$(lire_bms_16bit 4608 123)
    if [ ! -z "$B_TOTAL" ]; then
        
        soc_brut=$(echo "$B_TOTAL" | grep "\[4691\]" | awk '{print $2}')
        if [ ! -z "$soc_brut" ] && [ "$soc_brut" -ge 0 ] && [ "$soc_brut" -le 100 ]; then
            last_valid_soc=$soc_brut
        fi

        if [ ! -z "$last_valid_soc" ]; then
            JSON_PAYLOAD=$(awk \
                -v ch_adjust_value="$ch_adjust_value" \
                -v disch_adjust_value="$disch_adjust_value" \
                -v final_soc="$last_valid_soc" '
            BEGIN { 
                printf "{" 
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
                for (i = 4608; i <= 4623; i++) {
                    if (i in val) {
                        cell_idx = i - 4607;
                        v_cell = val[i] / 1000;
                        printf "\"cell_%02d\":%.3f,", cell_idx, v_cell;
                        cell_count++;
                        if (v_cell > c_max) { 
                            c_max = v_cell; 
                            idx_max = cell_idx; 
                        }
                        if (v_cell < c_min) { 
                            c_min = v_cell; 
                            idx_min = cell_idx; 
                        }
                    }
                }
                
                v_voltage = (val[4680] * 65536) + val[4681];
                v_current = (val[4682] * 65536) + val[4683];
                v_remain = (val[4692] * 65536) + val[4693];
                v_cyc_cap = (val[4698] * 65536) + val[4699];

                ############################### PATCH FOR POWER & CURRENT ###############################
                v_current = (val[4684] * 65536) + val[4685];
                if (v_current > 2147483647) {
                    v_current = v_current - 4294967296;
                }

                if (v_current > 0) {
                    v_current = v_current * ch_adjust_value;
                } else if (v_current < 0) {
                    v_current = v_current + disch_adjust_value;
                } else {
                    v_current = 0;
                }

                v_power = (val[4682] * 65536) + val[4683];
                if (v_power > 2147483647) {
                    v_power = v_power - 4294967296;
                }
                if (v_power < 0) {
                    v_power = -v_power;
                }
                ############################# END PATCH FOR POWER & CURRENT #============================

                v_temp_mos = val[4686];
                if (v_temp_mos > 32767) {
                    v_temp_mos = v_temp_mos - 65536;
                }
                v_temp_mos = v_temp_mos / 10;
                v_temp_01 = val[4687] / 10;
                v_temp_02 = val[4687] / 10;
                v_cycles = val[4697];

                ############################### PATCH FOR SOC VALUE ###############################
                v_soc = final_soc;
                ############################# END PATCH FOR SOC VALUE #============================

                v_chg_en = "true";
                v_dis_en = "true";
                octet_fort = int(val[4690] / 256);
     
                if (octet_fort >= 240) {
                    v_bal_en = "true";
                    v_bal_cur = (int(val[4690] % 256) * 10);
                } else {
                    v_bal_en = "false";
                    v_bal_cur = 0;
                }
                
                v_tot_fixed = v_voltage / 1000;
                v_avg_cell = (cell_count > 0) ? (v_tot_fixed / cell_count) : 0;

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
                printf "\"balancing_enabled\":%s,", v_bal_en;
                printf "\"charging_enabled\":%s,", v_chg_en;
                printf "\"discharging_enabled\":%s,", v_dis_en;
                printf "\"bms_status\":\"online\"}"
            }
            ' <<EOF
$B_TOTAL
EOF
)
            if [ ! -z "$JSON_PAYLOAD" ] && [[ "$JSON_PAYLOAD" == *"total_voltage"* ]]; then
                mosquitto_pub -h "$MQTT_BROKER" -p "$MQTT_PORT" -t "$MQTT_TOPIC" -m "$JSON_PAYLOAD" -r
                echo "MQTT Update -> $JSON_PAYLOAD"
            fi
        fi
    fi
    sleep "$INTERVALLE"
done
