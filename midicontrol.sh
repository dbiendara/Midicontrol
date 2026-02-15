#!/bin/bash

CONFIG_FILE="./config.txt"

# Automatische Erkennung des nanoKONTROL2 Ports
MIDI_OUT_PORT=$(amidi -l | grep "nanoKONTROL2" | awk '{print $2}')

# ---------------------------------------------------------
# Helper Funktionen für LEDs
# ---------------------------------------------------------

# Schaltet eine LED an (Value 7F = 127)
led_on() {
    local ctrl=$1
    if [ -n "$MIDI_OUT_PORT" ]; then
        printf -v HEX "%02X" "$ctrl"
        amidi -p "$MIDI_OUT_PORT" -S "B0 $HEX 7F"
    fi
}

# Schaltet eine LED aus (Value 00)
led_off() {
    local ctrl=$1
    if [ -n "$MIDI_OUT_PORT" ]; then
        printf -v HEX "%02X" "$ctrl"
        amidi -p "$MIDI_OUT_PORT" -S "B0 $HEX 00"
    fi
}

# ---------------------------------------------------------
# Konfiguration & Initialisierung
# ---------------------------------------------------------

# Liest Mapping aus config.txt
get_mapping() {
    local ctrl=$1
    grep -E "^$ctrl=" "$CONFIG_FILE" | cut -d= -f2
}

# LEDs initialisieren (aus config.txt "leds=...")
init_leds() {
    LEDS_LINE=$(grep "^leds=" "$CONFIG_FILE")
    if [ ! -z "$LEDS_LINE" ]; then
        LEDBTNSTR=${LEDS_LINE#leds=}
        IFS=',' read -ra LEDBTNS <<< "$LEDBTNSTR"
        for btn in "${LEDBTNS[@]}"; do
            led_on "$btn"
        done
    fi
}

# Default-Sink Switcher Logik
DEFAULT_SINK_INDEX=0
switch_sink() {
  SINKS=($(pactl list sinks short | cut -f2))
  DEFAULT_SINK_INDEX=$(( (DEFAULT_SINK_INDEX + 1) % ${#SINKS[@]} ))
  pactl set-default-sink "${SINKS[$DEFAULT_SINK_INDEX]}"
  echo "Default Sink: ${SINKS[$DEFAULT_SINK_INDEX]}"
}

# Prüft den Mute-Status und setzt die LED
update_mute_led() {
    local ctrl=$1
    local mapping=$2
    
    local is_muted="no"
    
    # LC_ALL=C erzwingt englische Ausgabe ("Mute: yes" statt "Stumm: ja")
    if [[ "$mapping" == mute_source:* ]]; then
        REAL_SOURCE=${mapping#mute_source:}
        STATUS=$(LC_ALL=C pactl get-source-mute "$REAL_SOURCE" 2>/dev/null)
        if [[ "$STATUS" == *"yes"* ]]; then is_muted="yes"; fi
        
    elif [[ "$mapping" == mute_sink:* ]]; then
        REAL_SINK=${mapping#mute_sink:}
        STATUS=$(LC_ALL=C pactl get-sink-mute "$REAL_SINK" 2>/dev/null)
        if [[ "$STATUS" == *"yes"* ]]; then is_muted="yes"; fi
    fi

    # LED Logik
    if [ "$is_muted" == "yes" ]; then
        led_on "$ctrl"
    else
        led_off "$ctrl"
    fi
}

# Initialisiert alle Mute-LEDs beim Start (synchronisiert Status)
sync_all_mute_leds() {
    while read -r line; do
        if [[ "$line" =~ ^([0-9]+)=mute_(source|sink): ]]; then
            CTRL=${BASH_REMATCH[1]}
            MAPPING=$(echo "$line" | cut -d= -f2)
            update_mute_led "$CTRL" "$MAPPING"
        fi
    done < "$CONFIG_FILE"
}

# ---------------------------------------------------------
# Main Loop
# ---------------------------------------------------------

# 1. Statische LEDs aus Config einschalten
init_leds
# 2. Mute-LEDs basierend auf aktuellem Status setzen
sync_all_mute_leds

echo "MIDI Control gestartet. Port: $MIDI_OUT_PORT"

# MIDI-Events überwachen
aseqdump -p "nanoKONTROL2" | while read LINE; do
    if [[ "$LINE" =~ controller\ ([0-9]+),\ value\ ([0-9]+) ]]; then
        CTRL=${BASH_REMATCH[1]}
        VALUE=${BASH_REMATCH[2]}
        MAPPING=$(get_mapping $CTRL)

        case "$MAPPING" in
            play) [ "$VALUE" -gt 0 ] && xdotool key XF86AudioPlay ;;
            stop) [ "$VALUE" -gt 0 ] && xdotool key XF86AudioStop ;;
            prev) [ "$VALUE" -gt 0 ] && xdotool key XF86AudioPrev ;;
            next) [ "$VALUE" -gt 0 ] && xdotool key XF86AudioNext ;;
            defaultsink) [ "$VALUE" -gt 0 ] && switch_sink ;;
            
            # --- MUTE TOGGLE MIT LED FEEDBACK ---
            mute_source:*)
                if [ "$VALUE" -gt 0 ]; then
                    REAL_SOURCE=${MAPPING#mute_source:}
                    pactl set-source-mute "$REAL_SOURCE" toggle
                    update_mute_led "$CTRL" "$MAPPING"
                    echo "Mute Toggle Source: $REAL_SOURCE"
                fi
                ;;
            mute_sink:*)
                if [ "$VALUE" -gt 0 ]; then
                    REAL_SINK=${MAPPING#mute_sink:}
                    pactl set-sink-mute "$REAL_SINK" toggle
                    update_mute_led "$CTRL" "$MAPPING"
                    echo "Mute Toggle Sink: $REAL_SINK"
                fi
                ;;
            
            # --- SLIDER / VOLUME ---
            *)
                if [ ! -z "$MAPPING" ] && [[ "$VALUE" =~ ^[0-9]+$ ]]; then
                    VOL=$(echo "$VALUE * 100 / 127" | bc)
                    
                    if [[ "$MAPPING" == source:* ]]; then
                        # --- SOURCE (Mikrofon) ---
                        REAL_SOURCE=${MAPPING#source:}
                        pactl set-source-volume "$REAL_SOURCE" "${VOL}%"
                        pactl set-source-mute "$REAL_SOURCE" 0 # Sicherheits-Unmute

                        # NEU: Finde den zugehörigen Mute-Button in der Config und aktualisiere die LED
                        MUTE_CTRL=$(grep "=mute_source:$REAL_SOURCE" "$CONFIG_FILE" | cut -d= -f1)
                        if [ -n "$MUTE_CTRL" ]; then
                            update_mute_led "$MUTE_CTRL" "mute_source:$REAL_SOURCE"
                        fi

                    elif [[ "$MAPPING" == app:* ]]; then
                        # --- APP-GRUPPEN ---
                        APP_SEARCH=${MAPPING#app:}
                        PIDS=$(pactl list sink-inputs | awk -v app="$APP_SEARCH" 'BEGIN {IGNORECASE=1} /^Sink Input/ {id=$3} /application.name/ && $0 ~ app {print id} /media.name/ && $0 ~ app {print id}' | tr -d '#' | sort -u)
                        if [ ! -z "$PIDS" ]; then
                            for PID in $PIDS; do pactl set-sink-input-volume "$PID" "${VOL}%"; done
                        fi

                    else
                        # --- SINK (Lautsprecher) ---
                        pactl set-sink-volume "$MAPPING" "${VOL}%"
                        pactl set-sink-mute "$MAPPING" 0

                        # NEU: Finde den zugehörigen Mute-Button für den Lautsprecher
                        MUTE_CTRL=$(grep "=mute_sink:$MAPPING" "$CONFIG_FILE" | cut -d= -f1)
                        if [ -n "$MUTE_CTRL" ]; then
                            update_mute_led "$MUTE_CTRL" "mute_sink:$MAPPING"
                        fi
                    fi
                fi
                ;;
        esac
    fi
done