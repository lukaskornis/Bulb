# Bulb

Menu bar app (light bulb icon) that sets brightness on every screen, built-in and external.

## Use
- Click the bulb: one slider for all screens, then one per screen, left to right as arranged. Hover a row for the screen's name.
- Brightness keys follow the mouse. Pointer on an external screen: only that screen changes, and a small bar shows on it. Pointer on the built-in screen: macOS handles the key as usual.
- Shift+Option+brightness key: quarter steps (1/64).

## How it works
- Built-in screen: private `DisplayServices` framework, loaded with `dlopen`.
- External screens: DDC/CI VCP 0x10 over `IOAVService` (Apple Silicon only). Each external `DCPAVServiceProxy` is paired with the `DisplayAttributes` entry that precedes it in the IORegistry, then matched to a CGDisplay by vendor, model and serial.
- DDC writes go through one serial queue; a slider drag only sends the latest value, since monitors drop writes when flooded.
- Keys: a session `CGEventTap` on system-defined events (subtype 8, key codes 2 and 3). Needs Accessibility; the menu shows "Allow Brightness Keys…" until granted, and the tap starts as soon as the trust list changes.
- Screen plug/unplug: the catalog reloads one second after the screen parameters settle.

## Limits
- Screens without DDC (some TVs, some docks and adapters) show a disabled slider; keys fall through to the built-in screen.
- Private APIs (`DisplayServices`, `IOAVService`) may break with macOS updates.

## Build
`./build.sh` builds and signs with the fixed "Bulb Local Signing" identity (created once in the login keychain). `./build.sh install` copies to /Applications and opens it.
