#!/bin/bash

CONFIG_FILE="./config.txt"
# Port Autoerkennung für nanoKONTROL2
MIDI_OUT_PORT=$(amidi -l | grep "nanoKONTROL2" | awk '{print $2}')

# Liest Mapping aus config.txt je Controller
get_mapping() {
    local ctrl=$1
    grep -E "^$ctrl=" "$CONFIG_FILE" | cut -d= -f2
}

# LEDs bei Dienststart initialisieren
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

# LED-Steuerung via amidi
led_on() {
    local ctrl=$1
    printf -v HEX "%02X" "$ctrl"
    amidi -p "$MIDI_OUT_PORT" -S "B0 $HEX 7F"
}

led_off() {
    local ctrl=$1
    printf -v HEX "%02X" "$ctrl"
    amidi -p "$MIDI_OUT_PORT" -S "B0 $HEX 00"
}

# Default-Sinks-Liste
DEFAULT_SINK_INDEX=0
switch_sink() {
  SINKS=($(pactl list sinks short | cut -f2))
  DEFAULT_SINK_INDEX=$(( (DEFAULT_SINK_INDEX + 1) % ${#SINKS[@]} ))
  pactl set-default-sink "${SINKS[$DEFAULT_SINK_INDEX]}"
  echo "Default sink switched to: ${SINKS[$DEFAULT_SINK_INDEX]}"
}

# Initialisierung
init_leds

# MIDI-Loop
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
            *)
                # Volumesteuerung
                if [ ! -z "$MAPPING" ] && [[ "$VALUE" =~ ^[0-9]+$ ]]; then
                    VOL=$(echo "$VALUE * 100 / 127" | bc)
                    
                    if [[ "$MAPPING" == source:* ]]; then
                        # --- SOURCE (Mikrofon) ---
                        REAL_SOURCE=${MAPPING#source:}
                        pactl set-source-volume "$REAL_SOURCE" "${VOL}%"
                        # echo "Source $REAL_SOURCE -> $VOL%"

                    elif [[ "$MAPPING" == app:* ]]; then
                        # --- APP GROUP (Sink Inputs) ---
                        APP_SEARCH=${MAPPING#app:}
                        
                        # AWK sucht IDs anhand des Regex-Strings (Case-Insensitive)
                        PIDS=$(pactl list sink-inputs | awk -v app="$APP_SEARCH" '
                            BEGIN {IGNORECASE=1} 
                            /^Sink Input/ {id=$3} 
                            /application.name/ && $0 ~ app {print id}
                            /media.name/ && $0 ~ app {print id}
                        ' | tr -d '#' | sort -u)  # <--- sort -u verhindert Duplikate

                        if [ ! -z "$PIDS" ]; then
                            # Loop über alle gefundenen IDs (z.B. Firefox UND MPV)
                            for PID in $PIDS; do
                                pactl set-sink-input-volume "$PID" "${VOL}%"
                            done
                            # Debug-Output gekürzt
                            echo "Apps ($APP_SEARCH) -> IDs $PIDS auf $VOL%"
                        fi

                    else
                        # --- SINK (Lautsprecher) ---
                        pactl set-sink-volume "$MAPPING" "${VOL}%"
                        # echo "Sink $MAPPING -> $VOL%"
                    fi
                fi
                ;;
        esac
    fi
done