#!/bin/bash
#Change for your USB/RS485 device address
SERIAL_PORT="/dev/ttyUSB0"
MQTT_BROKER="127.0.0.1"
MQTT_PORT="1883"
MQTT_TOPIC="homeassistant/sensor/jk_bms/state"
INTERVALLE=2
lire_bms_16bit() {
 local registre=$1
 local compte=$2
 mbpoll -m rtu -b 115200 -P none -o 2.00 -0 -t 4 -r "$registre" -c "$compte" -1 -q "$SERIAL_PORT" 2>/dev/null
}

while true; do
 B_TOTAL=$(lire_bms_16bit 4608 123)
 if [ ! -z "$B_TOTAL" ]; then
 JSON_PAYLOAD=$(awk '
 BEGIN { 
 printf "{" 
 c_max = 0; c_min = 99; 
 idx_max = 1; idx_min = 1; 
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
 if (v_cell > c_max) { c_max = v_cell; idx_max = cell_idx; }
 if (v_cell < c_min) { c_min = v_cell; idx_min = cell_idx; }
 }
 }

 v_voltage = (val[4680] * 65536) + val[4681];
 v_current = (val[4682] * 65536) + val[4683];
 v_remain = (val[4692] * 65536) + val[4693];
 v_cyc_cap = (val[4698] * 65536) + val[4699];

		############################### PATCH FOR POWER & CURRENT ###############################
            if (val[4684] == 65535) {
                # Mode discharge
                v_current = val[4685];
                if (v_current > 32767) v_current = v_current - 65536 + 1000;
            } else {
                # Mode charge
                v_current = (val[4682] * 65536) + val[4683];
                if (v_current > 2147483647) {
                    v_current = v_current - 4294967296;
                } else if (v_current > 3000000) {
                    # Soustraction du decalage brut observe en charge (3997990 -> 24590 mA)
                    v_current = v_current - 3973400;
                }
            }
            
            # Puissance exacte (U x I) en Watts (toujours positive pour l affichage)
            v_power = (v_voltage / 1000) * (v_current / 1000) * 1000;
            if (v_power < 0) v_power = -v_power;
		############################# END PATCH FOR POWER & CURRENT #############################

 #if (v_current > 2147483647) v_current = v_current - 4294967296;
 #v_power = (v_voltage / 1000) * (v_current / 1000) * 1000;

 v_temp_mos = val[4686];
 if (v_temp_mos > 32767) v_temp_mos = v_temp_mos - 65536;
 v_temp_mos = v_temp_mos / 10;
 v_temp_01 = val[4687] / 10;
 v_temp_02 = val[4687] / 10; # Copie sonde 1 par defaut si unique
 v_cycles = val[4697];


            ############################### PATCH FOR SOC VALUE ###############################
            if (val[4691] <= 100) {
                v_soc = val[4691];
                print v_soc > "/tmp/vsoc.txt";
                close("/tmp/vsoc.txt");
            } else {
                if ((getline v_soc < "/tmp/vsoc.txt") <= 0) {
                    v_soc = 100;
                }
                close("/tmp/vsoc.txt");
            }
            ############################# END PATCH FOR SOC VALUE #############################
 v_chg_en = "true";
 v_dis_en = "true";

 ####### PATCH25112026 #######
 octet_fort = int(val[4690] / 256);
 
 if (octet_fort >= 240) {
 v_bal_en = "true";
 v_bal_cur = (int(val[4690] % 256)*10);
 } else {
 v_bal_en = "false";
 v_bal_cur = 0;
 }
 ####### PATCH25112026 #######


 # Calcul Average V
 v_tot_fixed = v_voltage / 1000;
 v_avg_cell = (cell_count > 0) ? (v_tot_fixed / cell_count) : 0;

 # 4. final JSON
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
 # Pub on Broker MQTT local
 if [ ! -z "$JSON_PAYLOAD" ] && [[ "$JSON_PAYLOAD" == *"total_voltage"* ]]; then
 mosquitto_pub -h "$MQTT_BROKER" -p "$MQTT_PORT" -t "$MQTT_TOPIC" -m "$JSON_PAYLOAD" -r
 echo "MQTT Update -> $JSON_PAYLOAD"
 fi
 fi
 sleep "$INTERVALLE"
done
