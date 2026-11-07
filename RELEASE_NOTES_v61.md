# PCWork Mobile v61.0

- Version updated to 0.61.0+61.
- Added persistent Android release signing via GitHub Actions secrets; release builds fail safely if signing secrets are missing rather than silently using an ephemeral debug key.
- Preserved Android application ID: com.pcworkbg.pcwork_mobile.
- Updated DropdownButtonFormField to use initialValue in repair work log screen.
- GitHub Actions artifact renamed to pcwork-android-v61-apks.

Before running the release workflow, follow SIGNING_SETUP_BG.md and add the four repository secrets. Do not commit the keystore or credentials to the repository.

Compatibility note: the previously distributed v60 APK was signed with a different temporary Android Debug certificate. A v61 APK signed with this permanent release key cannot update that v60 installation in place. Back up any locally stored information first; a one-time uninstall/reinstall may be required. The WordPress account and server-side repair records remain on the server.
