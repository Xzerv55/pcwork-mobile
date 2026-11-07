=== PCWork Mobile – Complete System ===
Contributors: PCWork
Requires at least: 6.0
Requires PHP: 7.4
Stable tag: 5.0.0
License: GPLv2 or later

Unified PCWork Mobile backend for authentication, repair management, WooCommerce, Bookly, Google Sheets, Firebase push and the first-party PCWork Chat.

== Features ==
* Auth Bridge and customer profile integration.
* Repair intake, history, documents, worklog, dispatch and staff administration.
* WooCommerce mobile catalogue and orders.
* Bookly booking configuration.
* First-party PCWork Chat with authenticated REST messages, image attachments, admin inbox and FCM notifications.
* Google Sheets webhook with HMAC validation, write/read-back verification and diagnostics.
* Firebase Cloud Messaging device registration and notifications.
* App update manifest endpoint.
* Customer administration and WooCommerce order management, including individual and bulk deletion.

== Installation ==
1. Upload and activate the plugin ZIP.
2. The plugin creates/updates only its required tables using dbDelta. It does not delete existing repair, customer or WooCommerce data.
3. Open PCWork Mobile → Integrations to review existing integrations.
4. Open PCWork Mobile → Chat to manage customer conversations.

== Upgrade notes ==
Version 5.0.0 removes the Chatway widget, its settings, visitor verification, launch page and REST endpoints. Obsolete Chatway options are removed from the integration settings option; unrelated settings are preserved.
