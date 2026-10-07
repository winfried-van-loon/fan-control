# Fan Control

A macOS menu bar app that shows your MacBook's live temperature and lets you control the fans.

- **Menu bar:** a fan icon plus the live temperature. The icon fills in when the fans are under manual control.
  - **Left-click** opens a popover with presets, an all-fans slider, per-fan sliders, and Auto/Max buttons. It also has *Open Fan Control* and *Quit*.
  - **Right-click** opens a quick menu with the presets, Open and Quit.
- **Window:** shows every fan with a live gauge, Auto/Manual switch, slider and Min/50%/Max buttons.
  - An all-fans slider with **Auto** and **Full Speed** buttons.
  - **Target temperature**: pick a temperature (40–90 °C, default 60 °C) and a sensor (default CPU Package). The app then adjusts all fans continuously to hold it. It ramps up quickly when the sensor goes over the target and slows down gently below it. Touching any preset or slider turns it off.
  - Presets: *Auto, Silent, Balanced, Boost, Full*, plus your own. Use *Save Current Setting as Preset…* to add one, and right-click a custom preset to delete it.
  - Every temperature sensor, grouped (CPU, GPU, memory, storage, battery, mainboard, airflow, enclosure). Hover a sensor and click the pin to show it in the menu bar.
  - A 10-minute history of temperature and fan speed.
  - Settings (gear icon): menu bar sensor, °C/°F, refresh rate, return to Auto on quit, reapply at launch, thermal safety, start at login, and helper install/uninstall.
- **Start at login:** a checkbox in the popover, an item in the right-click menu, and a toggle in Settings. It registers the app under System Settings → General → Login Items. Run the app from `/Applications` (`./build.sh --install`) so the login item points there. Combine it with *Reapply last fan setting at launch* to restore your fan mode (including target temperature) after a restart.

## Build & run

Requires the Xcode Command Line Tools (no full Xcode needed).

```bash
./build.sh            # builds build/Fan Control.app
./build.sh --install  # also copies it to /Applications
open "build/Fan Control.app"
```

## The helper (why the admin prompt)

Reading temperatures and fan speeds needs no special rights. **Changing fan speeds requires root**, because the SMC rejects writes from normal processes.

The first time, click **Install** in the app. macOS asks for your admin password once. The app then installs a tiny setuid-root helper at `/Library/PrivilegedHelperTools/com.fancontrol.helper`.

The helper only understands three commands:

```
fanhelper version
fanhelper set  <fan|all> <rpm>   # forced mode; rpm is clamped to the fan's own min…max
fanhelper auto <fan|all>         # hand the fan back to macOS
```

Because it's setuid, any local user account on this Mac can run it, but only to set fan speeds within Apple's min/max range. You can remove it under Settings → Helper → Uninstall.

## Safety

- Speeds are always clamped to the fan's own SMC minimum/maximum.
- **Return fans to Auto when quitting** is on by default.
- **Thermal safety** is on by default: if any CPU/GPU sensor reaches 95 °C while fans are manually set below maximum, the app returns them to Auto.
- Target mode can only raise fans to their maximum. If the load is too high to reach the target, the fans stay at 100%, and thermal safety still applies.
- If macOS takes a fan back (e.g. after sleep), the app reapplies your manual setting.

## Layout

```
Sources/CSMC        C bridge to AppleSMC (IOKit)
Sources/FanKit      SMC value decoding, sensor catalog, fan read/write
Sources/FanHelper   the privileged CLI helper
Sources/FanControl  the menu bar app (AppKit status item + SwiftUI views)
Sources/smcprobe    dev tool: dumps all fan & temperature SMC keys
```

Built and tested on a MacBookPro16,1 (Intel, T2) running macOS 26. Fan control uses the T2-era `F<n>Md` / `F<n>Tg` keys. Apple Silicon Macs use different keys and are not supported for writing yet, although temperature reading may partially work there.
