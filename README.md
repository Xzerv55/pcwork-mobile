# PCWork Mobile v47

- Flutter app: `0.47.0+47`
- Unified WordPress plugin: `3.3.0` (`wordpress-plugin/pcwork-mobile-complete-system/`)
- Android package: `com.pcworkbg.pcwork_mobile`
- Languages: Bulgarian and English

## v47 scope
- Passwordless registration and sign-in using six-digit email OTP only; no SMS, Viber, or WhatsApp.
- Registration captures full name, phone, and email; account is created only after successful email verification.
- Customer role `pcwork_customer` with no administrative or repair-management capabilities.
- OTP expiry (5 minutes), maximum 5 verification attempts, 60-second resend cooldown, per-email/IP rate limits, and registration honeypot.
- Customer profile update for own name and phone.
- Server-side customer ownership checks and stricter staff-only route authorization.
- Customer repair requests are linked to the authenticated customer and limited to 3 per account/day and 10 per IP/day.
- Customer-facing repair payloads omit internal notes, staff-only data, and staff-only documents.
- WordPress admin page `PCWork Mobile → Клиенти` for listing and blocking/unblocking customer accounts.

## Important deployment notes
- Email OTP delivery uses WordPress `wp_mail()`. Configure and test a reliable SMTP/mail delivery service on the WordPress site before enabling customer registration.
- Do not configure SMS/Viber fallback.
- OTP rate limits are enforced server-side. A reverse proxy/CDN should preserve the real client IP safely; do not trust arbitrary forwarded headers.
- CAPTCHA is not configured in this build; a honeypot and rate limits are active. For stronger bot defense, connect a CAPTCHA/Turnstile provider before public launch.
- Existing staff accounts remain separate. The legacy password endpoint is retained for compatible staff integrations, but customer accounts must use email OTP.
- ZIP files intentionally exclude real Firebase credentials and service-account private keys. Preserve your own `android/app/google-services.json` and GitHub secrets when updating the repository.

## Validation
PHP syntax, YAML parsing, archive integrity, and sensitive-file checks are run during packaging. Flutter analyze/build and live WordPress email/API tests require the user's build environment and website and must not be inferred from static checks.

See `PCWork_v47_INSTALL_BG.md` and `V47_CHANGELOG_BG.md`.
