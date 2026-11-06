# PCWork WordPress Plugin 3.8.0

- Added WordPress admin button and form for creating a new repair, including existing or newly-created customer, service location, device details, priority, technician and due date.
- New admin-created repairs and customer-submitted repair requests trigger Google Sheets upsert. Admin edits and status updates also trigger upsert.
- Fixed a double-unslash/lossy-sanitization path: Service Account JSON is validated and stored in its original escaped form without modifying PEM Base64 characters.
- PEM Base64 is strictly decoded and re-encoded canonically before OpenSSL parsing; invalid/truncated keys receive a safe actionable error.
- Google Sheets sends an explicitly URL-encoded POST body so Apps Script receives a real `e.postData.contents`; customer data is not placed in the URL.
