# PCWork Mobile – Complete System v5.0.0

- Replaced the external Chatway integration with the first-party PCWork Chat module.
- Added compact indexed message storage and authenticated REST endpoints.
- Added a WordPress administrator chat inbox and reply workflow.
- Removed Chatway widget, visitor verification, settings, launch-ticket page and REST routes.
- Added safe migration that removes only obsolete Chatway integration options.
- Preserved existing WooCommerce, Bookly, Google Sheets, Firebase/FCM, ShopLentor, repairs and app-update integrations.

Database changes are additive: the plugin creates `wp_pcwork_chat_messages` using `dbDelta`; it does not delete existing tables or repair/customer data.
