# JK-BMS to MQTT Bridge (PB2A16S20P)

![Home Assistant](https://shields.io)
![MQTT](https://shields.io)
![Bash](https://shields.io)

## Description

**[FR]** Un petit script shell permettant de récupérer des données du dernier modèle JK BMS PB2A16S20P, de les transmettre via MQTT et de créer des capteurs dans Home Assistant. Installez-le à l'emplacement de votre choix, rendez-le exécutable et configurez-le pour qu'il s'exécute en tant que tâche cron ou service.

**[EN]** A small shell script that retrieves data from the latest JK BMS PB2A16S20P model, transmits it via MQTT, and creates sensors in Home Assistant. Install it in the location of your choice, make it executable, and set it up to run as a cron job or system service.

---

## Prerequisites / Prérequis

You need to install the following packages on your system:
```bash
sudo apt update
sudo apt install mbpoll mosquitto-clients
```

---

## Installation

1. Clone or download `jkbms_mqtt.sh` to your system.
2. Make the script executable:
   ```bash
   chmod +x jkbms_mqtt.sh
   ```
3. Edit the variables inside the script to match your setup (`SERIAL_PORT`, `MQTT_BROKER`, etc.).
4. Run it using a cron job, or as a background service.

---

## Exposed Sensors / Capteurs disponibles

Here is the list of sensors published in the MQTT JSON payload:

### Battery Cells / Cellules (V)
* `cell_01` to `cell_16` — Individual cell voltages

### Telemetry & Measurements / Télémétrie & Mesures
* `total_voltage` — Total pack voltage (V)
* `current` — Charge/Discharge current (A)
* `power` — Real-time power (kW)
* `soc` — State of Charge (%)
* `cap_remaining` — Remaining capacity (Ah)
* `cap_nominal` — Nominal capacity (Ah)

### Temperatures / Températures (°C)
* `temp_mos` — Power MOSFET temperature
* `temp_01` — Temperature probe 1
* `temp_02` — Temperature probe 2

### Diagnostics & Statistics / Diagnostics & Statistiques
* `cycle_count` — Number of charge/discharge cycles
* `cycle_capacity` — Total accumulated capacity (Ah)
* `cell_avg_voltage` — Average cell voltage (V)
* `max_cell_voltage` — Highest cell voltage (V)
* `max_cell_number` — Index of the highest cell
* `min_cell_voltage` — Lowest cell voltage (V)
* `min_cell_number` — Index of the lowest cell
* `delta_cell_voltage` — Voltage difference between highest and lowest cell (V)
* `bms_status` — Connection status (`online`)

---

## MQTT Payload Example / Exemple de Payload

```json
{
  "cell_01": 3.286,
  "cell_02": 3.289,
  ...
  "cell_16": 3.287,
  "total_voltage": 52.62,
  "power": 337.6,
  "current": -6.42,
  "temp_mos": 18.7,
  "temp_01": 19.7,
  "temp_02": 19.2,
  "cell_avg_voltage": 3.289,
  "balance_current": 0.049,
  "cap_remaining": 152.40,
  "cycle_count": 11,
  "cycle_capacity": 3725.2,
  "soc": 49.0,
  "cap_nominal": 314.00,
  "max_cell_voltage": 3.290,
  "max_cell_number": 8,
  "min_cell_voltage": 3.286,
  "min_cell_number": 1,
  "delta_cell_voltage": 0.004,
  "bms_status": "online"
}
```

ENJOY!
