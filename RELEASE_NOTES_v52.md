# PCWork Mobile v52 / WordPress plugin 3.6.1

## Mobile app
- Phone and TikTok home contact cards now display only their service names and icons. Phone number and TikTok profile remain configured as tap destinations.
- Bottom navigation bar height and icon vertical placement adjusted; existing icon glyphs and their size are retained.
- Main-tab switching continues to dismiss transient routes and discard unsaved overlay state.

## WordPress plugin
- Firebase JWT signing now explicitly parses the PEM private key with OpenSSL before signing.
- Handles escaped PEM line breaks as well as standard CRLF/LF line endings.
- Returns safe, actionable diagnostics for missing OpenSSL, malformed PEM keys and RSA-SHA256 signing failures; private key material is never included in diagnostics.
- Clears cached OAuth access tokens when integration settings are saved.

## Version alignment
- Flutter: `0.52.0+52`
- WordPress plugin: `3.6.1`
- Android and iOS workflow artifact labels: `v52`
