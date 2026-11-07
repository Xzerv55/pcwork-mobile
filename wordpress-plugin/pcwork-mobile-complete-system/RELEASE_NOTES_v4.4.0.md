# PCWork Mobile WordPress Plugin v4.4.0

- Added authenticated `/push/status` endpoint for device/Firebase/marketing diagnostics.
- Corrected Chatway Visitor Verification payload to documented `visitor.hmac` + `visitor.data` shape and sends name/email/phone through Chatway custom-data API after widget initialization.
- Queued Google Sheets synchronization and push delivery through WordPress Cron so third-party network calls do not block customer repair/order requests.
- Added operational notifications to authorized staff for new customer repair requests and WooCommerce orders, independent of marketing opt-in.
- Expanded the marketing customer audience to `customer`, `pcwork_customer`, and `subscriber` roles while retaining explicit opt-in.
- Enforced the same 15 meaningful-character repair-problem validation on the server.
