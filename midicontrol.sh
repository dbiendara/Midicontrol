#!/bin/bash

CONFIG_FILE="./config.txt"

# Automatische Erkennung des nanoKONTROL2 Ports
MIDI_OUT_PORT=$(amidi -l | grep "nanoKONTROL2" | awk '{print $2}')

# ---------------------------------------------------------
# Helper Funktionen für LEDs
# ---------------------------------------------------------

led_on() {
    local ctrl=$1
    if [ -n "$MIDI_OUT_PORT" ]; then
        printf -v HEX "%02X" "$ctrl"
        amidi -p "$MIDI_OUT_PORT" -S "B0 $HEX 7F"
    fi
}

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

get_mapping() {
    local ctrl=$1
    grep -E "^$ctrl=" "$CONFIG_FILE" | cut -d= -f2
}

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

update_mute_led() {
    local ctrl=$1
    local mapping=$2
    local is_muted="no"
    
    if [[ "$mapping" == mute_source:* ]]; then
        REAL_SOURCE=${mapping#mute_source:}
        STATUS=$(LC_ALL=C pactl get-source-mute "$REAL_SOURCE" 2>/dev/null)
        [[ "$STATUS" == *"yes"* ]] && is_muted="yes"
    elif [[ "$mapping" == mute_sink:* ]]; then
        REAL_SINK=${mapping#mute_sink:}
        STATUS=$(LC_ALL=C pactl get-sink-mute "$REAL_SINK" 2>/dev/null)
        [[ "$STATUS" == *"yes"* ]] && is_muted="yes"
    fi

    if [ "$is_muted" == "yes" ]; then led_on "$ctrl"; else led_off "$ctrl"; fi
}

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

init_leds
sync_all_mute_leds


# --- NEU: Wake-up Listener ---
# Lauscht auf das D-Bus Signal für das Ende des Standbys
(
    # Wir warten auf PrepareForSleep(false)
    dbus-monitor --system "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" | while read line; do
        if [[ "$line" == *"boolean false"* ]]; then
            # Kurz warten, bis USB-Hardware wieder komplett initialisiert ist
            sleep 2
            echo "System wake-up erkannt. Synchronisiere LEDs..."
            # Port neu erkennen, falls er sich geändert hat
            MIDI_OUT_PORT=$(amidi -l | grep "nanoKONTROL2" | awk '{print $2}')
            # Funktionen aus dem bestehenden Skript aufrufen
            init_leds
            sync_all_mute_leds
        fi
    done
) &
WAKE_PID=$!

# Cleanup: Falls das Hauptskript beendet wird, auch den Listener killen
trap "kill $WAKE_PID 2>/dev/null; exit" EXIT
# ------------------------------


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
            
            mute_source:*)
                if [ "$VALUE" -gt 0 ]; then
                    REAL_SOURCE=${MAPPING#mute_source:}
                    pactl set-source-mute "$REAL_SOURCE" toggle
                    update_mute_led "$CTRL" "$MAPPING"
                fi
                ;;
            mute_sink:*)
                if [ "$VALUE" -gt 0 ]; then
                    REAL_SINK=${MAPPING#mute_sink:}
                    pactl set-sink-mute "$REAL_SINK" toggle
                    update_mute_led "$CTRL" "$MAPPING"
                fi
                ;;
            
            *)
                if [ ! -z "$MAPPING" ] && [[ "$VALUE" =~ ^[0-9]+$ ]]; then
                    VOL=$(echo "$VALUE * 100 / 127" | bc)
                    
                    if [[ "$MAPPING" == source:* ]]; then
                        REAL_SOURCE=${MAPPING#source:}
                        pactl set-source-volume "$REAL_SOURCE" "${VOL}%"
                        pactl set-source-mute "$REAL_SOURCE" 0 
                        MUTE_CTRL=$(grep "=mute_source:$REAL_SOURCE" "$CONFIG_FILE" | cut -d= -f1)
                        [ -n "$MUTE_CTRL" ] && update_mute_led "$MUTE_CTRL" "mute_source:$REAL_SOURCE"

                    elif [[ "$MAPPING" == app:* ]]; then
                        APP_SEARCH=${MAPPING#app:}
                        PIDS=$(pactl list sink-inputs | awk -v app="$APP_SEARCH" 'BEGIN {IGNORECASE=1} /^Sink Input/ {id=$3} /application.name/ && $0 ~ app {print id} /media.name/ && $0 ~ app {print id}' | tr -d '#' | sort -u)
                        if [ ! -z "$PIDS" ]; then
                            for PID in $PIDS; do pactl set-sink-input-volume "$PID" "${VOL}%"; done
                        fi

                    else
                        pactl set-sink-volume "$MAPPING" "${VOL}%"
                        pactl set-sink-mute "$MAPPING" 0
                        MUTE_CTRL=$(grep "=mute_sink:$MAPPING" "$CONFIG_FILE" | cut -d= -f1)
                        [ -n "$MUTE_CTRL" ] && update_mute_led "$MUTE_CTRL" "mute_sink:$MAPPING"
                    fi
                fi
                ;;
        esac
    fi
done