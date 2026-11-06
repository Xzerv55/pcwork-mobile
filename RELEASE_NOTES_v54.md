# PCWork Mobile v54

- Replaced the Material NavigationBar with a six-item custom navigation strip. Each icon-and-label group is vertically centered in a 64 px cell, producing equal free space above and below without reducing the 24 px icon size.
- Kept the six destinations, colors, labels, and tab-switch behavior.
- Flutter SDK was not available in the build environment; run `flutter analyze` and build workflows in GitHub Actions before release.

- Google Sheets webhook upgraded to Security 2.6.0 and the WordPress sender now builds the URL-encoded POST body explicitly; customer repair data stays out of the URL.

- Added transport-only Apps Script diagnostics (content type, body length and parameter names; no customer data or secrets are logged).
