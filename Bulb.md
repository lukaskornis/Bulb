# Bulb

Menu bar app (light bulb icon) that sets brightness on every screen, built-in and external.

## Use
- Click the bulb: one slider for all screens, then one per screen, left to right as arranged. Hover a row for the screen's name.
- Keys Change All Screens (on by default): brightness keys move every screen together, with a small bar on each external screen.
  - Keep Brightness Ratios (only in that mode): match the screens by eye with their own sliders, then the keys and the All slider dim them together, keeping that ratio. The brightest screen is the level; the others scale with it.
- With Keys Change All Screens off, the keys change the laptop screen only, as macOS normally does.
- Sliders follow changes made elsewhere live: keys, Control Center, auto-brightness.
- Shift+Option+brightness key: quarter steps (1/64).

## How it works
- Built-in screen: private `DisplayServices` framework, loaded with `dlopen`.
- External screens: DDC/CI VCP 0x10 over `IOAVService` (Apple Silicon only). Each external `DCPAVServiceProxy` is matched to a CGDisplay by vendor, model and serial read from its EDID (`IOAVServiceCopyEDID`).
- Keys: Apple Silicon laptops handle the brightness keys inside the keyboard driver. No CGEvent reaches any tap (session or HID), and `hidutil` UserKeyMapping does not catch them (tested on M1 Air, macOS 15). So Bulb never sees the key; it sees the built-in screen change through `DisplayServicesRegisterForBrightnessChangeNotifications` and passes the step on. A per-screen "follow the mouse" mode was tried and dropped: it had to undo the laptop's fade and stalled at the laptop's limits.
- Bulb's own writes update the model before the hardware, so their notifications match the model and are ignored.
- `ScreenGroup` holds the all-screens logic. Ratios are captured whenever one screen is changed on its own (its slider, or the keys with Keys Change All Screens off) and when the screen list loads.
- DDC writes go through one serial queue; a slider drag only sends the latest value, since monitors drop writes when flooded.
- Screen plug/unplug: the catalog reloads one second after the screen parameters settle.

## Privileges
- App Sandbox and hardened runtime. No TCC permissions (no Accessibility, no Input Monitoring).
- Two sandbox exceptions, both needed: IOKit user client `DCPAVServiceProxyUserClient` (DDC), mach-lookup `com.apple.backlightd` (built-in brightness).
- The sandbox denies reading the registry's `DisplayAttributes`, hence EDID matching.

## Limits
- Screens without DDC (some TVs, some docks and adapters) show a disabled slider and do not follow the keys.
- Keys do nothing extra once the built-in screen is at its limit (no change means no notification).
- Any change to the built-in screen counts, including Control Center and auto-brightness.
- Private APIs (`DisplayServices`, `IOAVService`) may break with macOS updates.

## Build
`./build.sh` builds and signs with the fixed "Bulb Local Signing" identity (created once in the login keychain). `./build.sh install` copies to /Applications and opens it.
