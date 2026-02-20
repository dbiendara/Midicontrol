#!/bin/bash

CONFIG_FILE="./config.txt"
SERVICE_NAME="midicontrol.service"
MIDI_NAME="nanoKONTROL2"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

touch "$CONFIG_FILE"

# Funktion zum Neustarten des Dienstes
restart_service() {
    echo -e "${YELLOW}Initialisiere LEDs und starte Service neu...${NC}"
    systemctl --user restart "$SERVICE_NAME"
}

# Funktion zum Verwalten der statischen LEDs (leds=)
manage_static_leds() {
    # Wir löschen den Tastatur-Puffer vorab, damit alte Eingaben nicht stören
    flush_input() {
        local junk
        while read -r -t 0.1 junk; do :; done
    }
    
    flush_input
    
    while true; do
        echo -e "\n${CYAN}--- Statische LEDs verwalten (Toggle-Modus) ---${NC}"
        
        # Aktuelle Liste auslesen
        LEDS_LINE=$(grep "^leds=" "$CONFIG_FILE")
        if [ -z "$LEDS_LINE" ]; then
            echo "leds=" >> "$CONFIG_FILE"
            CURRENT_LEDS=""
        else
            CURRENT_LEDS=${LEDS_LINE#leds=}
        fi

        echo -e "Aktuell leuchtende IDs: ${YELLOW}${CURRENT_LEDS:-Keine}${NC}"
        echo "-----------------------------------------------------"
        echo " >> Drücke einen Button am Controller zum Togglen."
        echo " >> Drücke 'q' auf der Tastatur zum Beenden."
        echo "-----------------------------------------------------"

        # 1. Tastatur-Check (0.2 Sekunden warten)
        read -t 0.2 -n 1 KBD_INPUT
        if [[ "$KBD_INPUT" == "q" ]]; then 
            echo -e "\n${GREEN}LED-Konfiguration beendet.${NC}"
            break 
        fi

        # 2. MIDI-Check mit kurzem Timeout (0.5s)
        # Wir unterdrücken Fehlermeldungen vom Timeout
        EVENT=$(timeout 0.5s aseqdump -p "$MIDI_NAME" | grep -m 1 "controller" 2>/dev/null)
        
        if [[ "$EVENT" =~ controller\ ([0-9]+), ]]; then
            CTRL_ID=${BASH_REMATCH[1]}
            echo -e "\rErkannter Button: ${GREEN}$CTRL_ID${NC}"

            if [[ ",$CURRENT_LEDS," == *",$CTRL_ID,"* ]]; then
                # ID entfernen
                NEW_LEDS=$(echo "$CURRENT_LEDS" | sed -E "s/(^|,)$CTRL_ID($|,)/,/g; s/^,//; s/,$//; s/,,/,/g")
                echo "-> ID $CTRL_ID entfernt."
            else
                # ID hinzufügen
                if [ -z "$CURRENT_LEDS" ]; then NEW_LEDS="$CTRL_ID"
                else NEW_LEDS="$CURRENT_LEDS,$CTRL_ID"; fi
                echo "-> ID $CTRL_ID hinzugefügt."
            fi

            # Speichern und Neustart
            sed -i "s/^leds=.*/leds=$NEW_LEDS/" "$CONFIG_FILE"
            restart_service
            # Puffer nach MIDI-Aktion leeren
            flush_input
        fi
    done
}

echo -e "${CYAN}-----------------------------------------------------"
echo -e " MIDI Controller Setup Wizard für $MIDI_NAME"
echo -e "-----------------------------------------------------${NC}"

PORT=$(amidi -l | grep "$MIDI_NAME" | awk '{print $2}')
if [ -z "$PORT" ]; then echo -e "${RED}Fehler: $MIDI_NAME nicht gefunden.${NC}"; exit 1; fi

while true; do
    echo -e "\n${CYAN}HAUPTMENÜ${NC}"
    echo "1) Volume: Ausgang / Lautsprecher"
    echo "2) Volume: Eingang / Mikrofon"
    echo "3) Volume: Anwendung (App)"
    echo "4) Media Buttons (Play, Stop...)"
    echo "5) MUTE / TOGGLE (für Buttons)"
    echo "6) Abbrechen (Scan überspringen)"
    echo "7) Dauerhaft leuchtende Buttons verwalten (leds=)"
    echo "q) Beenden"
    
    read -p "Auswahl: " MAIN_CHOICE

    if [[ "$MAIN_CHOICE" == "q" ]]; then exit 0; fi
    if [[ "$MAIN_CHOICE" == "7" ]]; then manage_static_leds; continue; fi
    if [[ "$MAIN_CHOICE" == "6" ]]; then continue; fi

    echo -e "\n${YELLOW}Bitte bewege einen Regler oder drücke einen Knopf...${NC}"
    EVENT=$(aseqdump -p "$MIDI_NAME" | grep -m 1 "controller")
    if [[ "$EVENT" =~ controller\ ([0-9]+), ]]; then
        CTRL_ID=${BASH_REMATCH[1]}
    else continue; fi

    echo -e ">> ${GREEN}ERKANNT: ID $CTRL_ID${NC} <<"

    # Check Existing
    EXISTING_ENTRY=$(grep "^$CTRL_ID=" "$CONFIG_FILE" | cut -d'=' -f2-)
    if [ -n "$EXISTING_ENTRY" ]; then
        echo -e "${RED}⚠️  Belegt mit: ${YELLOW}$EXISTING_ENTRY${NC}"
        read -p "   (ü)berschreiben oder (b)ehalten? " DECISION
        [[ "$DECISION" != "ü" ]] && continue
    fi

    ENTRY=""
    case "$MAIN_CHOICE" in
        1) # SINK
            mapfile -t SINKS < <(pactl list sinks short | cut -f2)
            select SINK in "${SINKS[@]}"; do [ -n "$SINK" ] && ENTRY="$SINK" && break; done ;;
        2) # SOURCE
            mapfile -t SOURCES < <(pactl list sources short | cut -f2 | grep -v "\.monitor")
            select SRC in "${SOURCES[@]}"; do [ -n "$SRC" ] && ENTRY="source:$SRC" && break; done ;;
        3) # APP
            mapfile -t APPS < <(pactl list sink-inputs | grep "application.name" | cut -d '"' -f2 | sort -u)
            APPS+=("Custom (Manuell)")
            select APP in "${APPS[@]}"; do
                if [ "$APP" == "Custom (Manuell)" ]; then read -p "Regex: " C; ENTRY="app:$C"; break
                elif [ -n "$APP" ]; then ENTRY="app:$APP"; break; fi
            done ;;
        4) # CMD
            select CMD in "play" "stop" "prev" "next" "defaultsink"; do [ -n "$CMD" ] && ENTRY="$CMD" && break; done ;;
        5) # MUTE
            echo "1) Mikro (Source) 2) Lautsprecher (Sink)"
            read -p ": " MC
            if [ "$MC" == "1" ]; then
                mapfile -t SOURCES < <(pactl list sources short | cut -f2 | grep -v "\.monitor")
                select SRC in "${SOURCES[@]}"; do [ -n "$SRC" ] && ENTRY="mute_source:$SRC" && break; done
            else
                mapfile -t SINKS < <(pactl list sinks short | cut -f2)
                select SINK in "${SINKS[@]}"; do [ -n "$SINK" ] && ENTRY="mute_sink:$SINK" && break; done
            fi ;;
    esac

    if [ -n "$ENTRY" ]; then
        sed -i "/^$CTRL_ID=/d" "$CONFIG_FILE"
        echo "$CTRL_ID=$ENTRY" >> "$CONFIG_FILE"
        echo -e "✅ ${GREEN}GESPEICHERT${NC}"
        restart_service
    fi
done