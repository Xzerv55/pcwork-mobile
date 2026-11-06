# PCWork Mobile v43

- App version: 0.43.0+43
- Unified WordPress plugin: 3.1.0 (`wordpress-plugin/pcwork-mobile-complete-system/`)
- Android package / iOS bundle ID: `com.pcworkbg.pcwork_mobile`
- Languages: Bulgarian and English
- Themes: dark and light, saved on device

## v43 – navigation, account access, service information and appearance

- Added a root `NavigatorState` key. Root-level actions now open modal sheets and routes through the actual `MaterialApp` navigator. This fixes the previous context-above-Navigator issue affecting service locations, settings, repair details, staff screens and sign-in.
- Connected the home-screen “Service locations” and “Warranty and service terms” cards to working actions.
- Warranty card opens a sheet with official PCWork repair terms and FAQ links.
- Sign-in and registration now push through the app navigator key from the profile and repair prompts.
- Added a persistent light/dark theme switch in App settings.
- Added English translations for the Contact hub and Chaty/Chatway app screens; the embedded page document language is set to the selected app language where supported.
- Settings now include both language and theme controls.

## Installation

See `PCWork_v43_INSTALL_BG.md`.
