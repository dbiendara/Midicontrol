# Unbenannt

# Midicontrol - Advanced Linux MIDI Volume Mixer

**Midicontrol** is a powerful, lightweight Bash script that turns your MIDI controller (optimized for **Korg nanoKONTROL2**) into a fully functional physical mixer for Linux audio (PulseAudio / PipeWire).

It allows you to control input/output devices, mute states with LED feedback, and even group specific applications onto a single fader using Regex.

## 🚀 Key Features

- 
    
    **🎚️ Hardware Sink Control:** Control system volume or specific output devices.
    
- **🎤 Microphone/Source Control:** Adjust input gain for microphones or virtual devices like **EasyEffects**.
- **📦 App Groups (Regex):** Map multiple apps to one slider using a simple pipe syntax (e.g., `app:spotify|vlc|mpv`).
- **🔇 Bi-directional Mute:**
    - Buttons toggle mute state.
    - **LED Feedback:** The button lights up if the device is muted, syncing with the actual PulseAudio state.
- **🛡️ Safety Unmute:** Moving a volume fader automatically unmutes the target.
- **🧙 Interactive Wizard:** A setup script (`configure.sh`) detects your controller input and lets you map functions without manual editing.
- **⚡ Lightweight:** Runs as a systemd user service with zero GUI overhead.

## 🛠 Prerequisites

You need a Linux system running **PulseAudio** or **PipeWire** (with `pipewire-pulse`).

**Dependencies:**

- `alsa-utils`: Provides `aseqdump` and `amidi`.
- `xdotool`: For media keys like Play/Pause.
- `bc`: For volume math.
- `pulseaudio-utils`: Provides `pactl`.

### Installation on Arch Linux

`sudo pacman -S alsa-utils xdotool bc pulseaudio-utils`

### Installation on Debian / Ubuntu

`sudo apt install alsa-utils xdotool bc pulseaudio-utils`

## 📦 Installation

1. Clone the repository
    
    `git clone https://github.com/dbiendara/Midicontrol.git
    cd Midicontrol`
    
2. Make the scripts executable
    
    `chmod +x midicontrol.sh configure.sh`
    

## ⚙️ Configuration

### Option A: The Wizard (Recommended)

Run the configuration script to map your controller:

`./configure.sh`

1. Move a fader or press a button on your MIDI controller.
2. Select the desired function (Sink, Source, App, or Media Key).
3. The script saves the mapping and automatically restarts the service.

### Option B: Manual Configuration (`config.txt`)

The format is `CONTROLLER_ID=VALUE`.

### 1. Volume Sliders

- **Output (Sink):** `0=alsa_output.pci-0000_0d_00.4.analog-stereo`
- **Input (Source):** `1=source:easyeffects_source`
- **Apps (Regex):** `2=app:spotify|vlc|mpv`

### 2. Buttons

- **Mute Toggle:** `48=mute_source:easyeffects_source` (LED lights up when muted).
- **Media Control:** `41=play`, `42=stop`, `43=prev`, `44=next`.
- **Sink Switch:** `46=defaultsink`.

### 3. Initial LED State

List buttons to be lit at startup: `leds=41,42,43,44`.

## 🖥️ Autostart (Systemd Service)

1. Create the service file:
`nano ~/.config/systemd/user/midicontrol.service`
2. Paste the following (adjust the path!):Ini, TOML
    
    `[Unit]
    Description=MIDI Control Script (nanoKONTROL2)
    After=sound.target
    
    [Service]
    Type=simple
    ExecStart=/home/YOUR_USERNAME/path/to/Midicontrol/midicontrol.sh
    Restart=always
    RestartSec=3
    
    [Install]
    WantedBy=default.target`
    
3. Enable and start:Bash
    
    `systemctl --user daemon-reload
    systemctl --user enable --now midicontrol.service`
    

## 🔍 Troubleshooting

- **Mute LEDs not working:** The script uses `LC_ALL=C` to force English output from `pactl`. If they still don't work, ensure your user has access to `amidi` and the MIDI port is not blocked.
- **App Volume:** App matching is case-insensitive. Use `pactl list sink-inputs` to find the exact `application.name`.
- **Device Busy:** Ensure no other MIDI mappers or DAWs are running that might grab exclusive control of the port.

## 📄 License

MIT License