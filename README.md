# GPU Monitor

A sleek floating macOS menu bar app (and screen saver) that shows real-time GPU, CPU, RAM, and temperature stats — built for **Apple Silicon M-series Macs**.

![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Chip](https://img.shields.io/badge/chip-Apple%20Silicon-green)

---

## Features

- **GPU Utilization** — live % via IOAccelerator
- **CPU Utilization** — per-core via Mach kernel
- **GPU & CPU Temperature** — in °F via IOHIDEventSystem (works on M4 Max)
- **VRAM & RAM** — used / total with sparkline history
- **LLM Detection** — detects running `ollama` models with name, processor (GPU/CPU), and size
- **Arc gauges** — animated green→orange→red based on load
- **Sparklines** — 60-second history per metric
- **Screen Saver** — full-screen version of the dashboard
- **Floating panel** — stays on top of all windows, draggable, no Dock icon

---

## Screenshots

The dashboard is a 680×280 floating panel that sits in the top-right corner of your screen:

```
┌─ GPU ──┬─ GPU °F ─┬─ CPU ──┬─ CPU °F ─┬─ VRAM ─┬─ RAM ──┐
│  Arc   │   Arc    │  Arc   │   Arc    │  Arc   │  Arc   │
│  42%   │  133°F   │  18%   │  142°F   │ 38.2G  │ 42.1G  │
│  spark │  spark   │  spark │  spark   │ /64G   │ /128G  │
└────────┴──────────┴────────┴──────────┴────────┴────────┘
● llama3.2:latest [100% GPU] 2.0 GB
```

---

## Requirements

- macOS 15.0+
- Apple Silicon Mac (M1/M2/M3/M4 series)
- Xcode 15+

---

## Build

```bash
git clone https://github.com/amiu888/gpu-monitor.git
cd gpu-monitor

# Build the floating panel app
xcodebuild -project GPUMonitor.xcodeproj -target GPUMonitor -configuration Release build

# Build the screen saver
xcodebuild -project GPUMonitor.xcodeproj -target GPUMonitorSaver -configuration Release build
```

### Install Screen Saver

```bash
cp -r build/Release/GPUMonitorSaver.saver ~/Library/Screen\ Savers/
open ~/Library/Screen\ Savers/GPUMonitorSaver.saver
```

Then select **GPU Monitor** in **System Settings → Screen Saver**.

---

## Technical Notes

- **Temperature** — Uses private `IOHIDEventSystemClient` API (client type 1) with `PrimaryUsagePage: 0xFF00`. On M4 Max, `PMU tdie*` sensors = CPU die temp, `PMU tdev*` = GPU temp.
- **GPU stats** — `IOAccelerator` → `PerformanceStatistics["Device Utilization %"]`
- **CPU stats** — `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` with tick deltas
- **RAM** — `host_statistics64(HOST_VM_INFO64)`, active + wired + compressor pages
- **LLM detection** — `sysctl(KERN_PROC_ALL)` for process scan + `ollama ps` for model details
- No App Sandbox (required for IOKit and private APIs)
- `LSUIElement = YES` — no Dock icon

---

## License

MIT
