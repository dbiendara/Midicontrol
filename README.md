# Midicontrol - Advanced Linux MIDI Volume Mixer

**Midicontrol** is a powerful, lightweight Bash script that turns your MIDI controller (specifically **Korg nanoKONTROL2**) into a physical audio mixer for Linux (PulseAudio / PipeWire).

It provides tactile control over hardware devices, application groups, and mute states with full visual feedback.

## 🚀 Key Features

- **🎚️ Hardware Control:** Adjust volume for any Sink (Output) or Source (Input/Mic).
- **📦 Regex App Groups:** Control multiple applications with one fader (e.g., `app:spotify|vlc|mpv`).
- **🔇 Bi-directional Mute:** Buttons toggle mute with **LED Feedback** that stays in sync with the system.
- **🛡️ Safety Unmute:** Moving a fader automatically unmutes the device to prevent "silent" input.
- **📺 Native KDE OSD:** Shows the original KDE Plasma On-Screen-Display for volume and microphone changes.
- **💤 Standby Recovery:** Automatically restores all LED states after system wake-up via D-Bus monitoring.
- **🧙 Interactive Wizard:** Use `configure.sh` to map your controller without editing files.
- **⚡ Service Integration:** Runs as a lightweight `systemd --user` service.

## 🛠 Prerequisites

Ensure the following packages are installed:

- **alsa-utils** (`aseqdump`, `amidi`)
- **pulseaudio-utils** (`pactl`)
- **xdotool** (Media keys)
- **bc** (Calculations)
- **dbus** (Standby listener)
- **qt6-tools** (for KDE OSD support via `qdbus`)

### Install (Arch/CachyOS)

Bash

`sudo pacman -S alsa-utils pulseaudio-utils xdotool bc dbus qt6-tools`

## 📦 Installation & Setup

1. **Clone & Permissions:**Bash
    
    `git clone https://github.com/dbiendara/Midicontrol.git
    cd Midicontrol
    chmod +x *.sh`
    
2. **Run the Wizard:**Bash
    
    `./configure.sh`
    
    Follow the on-screen instructions to map your faders and buttons.
    
3. **Install the Service:**
Create `~/.config/systemd/user/midicontrol.service`:Ini, TOML
    
    `[Unit]
    Description=MIDI Control Service
    After=sound.target
    
    [Service]
    Type=simple
    ExecStart=/home/YOUR_USER/path/to/midicontrol.sh
    Restart=always
    
    [Install]
    WantedBy=default.target`
    
    Enable it: `systemctl --user enable --now midicontrol.service`
    

## ⚙️ Manual Configuration (`config.txt`)

Syntax: `CONTROLLER_ID=TYPE:TARGET`

- **Sinks:** `16=alsa_output.pci-0000_00_1f.3.analog-stereo`
- **Sources:** `0=source:easyeffects_source`
- **Apps:** `2=app:discord|teams|zoom`
- **Mute:** `48=mute_source:easyeffects_source`
- **Media:** `41=play`, `42=stop`, `43=prev`, `44=next`
- **LEDs:** `leds=41,42,43,44` (Statische LEDs an)

## 🔍 Troubleshooting

- **AccessDenied (D-Bus):** This is normal for `dbus-monitor`. The script handles this by falling back to eavesdropping mode automatically.
- **OSD not showing:** Ensure you are in a KDE Plasma session and `qdbus` is available.
- **MIDI Port:** If your device is not a nanoKONTROL2, change the `MIDI_NAME` variable in the scripts.

## 📄 License

MIT