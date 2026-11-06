<?php
if (!defined('ABSPATH')) exit;

/**
 * Server-to-server Google Sheets synchronization.
 * Apps Script verifies HMAC over "<timestamp>.<nonce>.<raw JSON body>".
 */
final class PCWork_Google_Sheets_Sync {
    /**
     * Send a signed JSON POST to Apps Script and explicitly consume its
     * ContentService redirect. Google serves the final response from the
     * one-time script.googleusercontent.com URL.
     *
     * The POST is never replayed. Only the Google ContentService HTTPS host
     * is followed, and the redirect target is fetched as GET.
     */
    public static function post_json($webhook_url, $payload, $secret) {
        $parts = wp_parse_url($webhook_url);
        if (!is_array($parts) || strtolower((string)($parts['scheme'] ?? '')) !== 'https'
            || strtolower((string)($parts['host'] ?? '')) !== 'script.google.com'
            || strpos((string)($parts['path'] ?? ''), '/macros/s/') !== 0
            || substr((string)($parts['path'] ?? ''), -5) !== '/exec') {
            return new WP_Error('pcwork_sheets_webhook_url', 'Webhook адресът трябва да е HTTPS Google Apps Script /macros/s/.../exec адрес.');
        }
        $timestamp = (string) time();
        try { $nonce = bin2hex(random_bytes(16)); }
        catch (Throwable $e) { return new WP_Error('pcwork_sheets_nonce', 'Неуспешно генериране на защитен идентификатор на заявката.'); }
        // Signature v2 binds timestamp, one-time nonce and the exact raw JSON body.
        $signature = hash_hmac('sha256', $timestamp . '.' . $nonce . '.' . $payload, $secret);
        $url = add_query_arg(['ts' => $timestamp, 'nonce' => $nonce, 'sig' => $signature], $webhook_url);

        $response = wp_remote_post($url, [
            'timeout' => 30,
            'redirection' => 0,
            'httpversion' => '1.1',
            'blocking' => true,
            'headers' => [
                'Content-Type' => 'application/json; charset=utf-8',
                'Accept' => 'application/json',
            ],
            'body' => $payload,
        ]);

        if (is_wp_error($response)) return $response;

        $redirect_count = 0;
        while (in_array((int) wp_remote_retrieve_response_code($response), [301, 302, 303], true)) {
            if (++$redirect_count > 3) {
                return new WP_Error('pcwork_sheets_redirect_limit', 'Google Apps Script пренасочи заявката твърде много пъти.');
            }

            $location = wp_remote_retrieve_header($response, 'location');
            if (is_array($location)) $location = end($location);
            $location = is_string($location) ? trim($location) : '';
            if ($location === '') {
                return new WP_Error('pcwork_sheets_redirect_missing', 'Google Apps Script върна пренасочване без Location адрес.');
            }

            $target = wp_parse_url($location);
            if (!is_array($target) || strtolower((string)($target['scheme'] ?? '')) !== 'https'
                || strtolower((string)($target['host'] ?? '')) !== 'script.googleusercontent.com') {
                return new WP_Error('pcwork_sheets_redirect_host', 'Отказано е пренасочване към непознат адрес.');
            }

            // ContentService uses a one-time URL; follow it with GET.
            $response = wp_remote_get($location, [
                'timeout' => 30,
                'redirection' => 0,
                'httpversion' => '1.1',
                'blocking' => true,
                'headers' => ['Accept' => 'application/json'],
            ]);
            if (is_wp_error($response)) return $response;
        }

        return $response;
    }
    public static function init() {
        add_action('pcwork_repair_status_changed', [__CLASS__, 'sync_repair'], 5, 4);
    }

    public static function sync_repair($repair_id, $customer_user_id, $status, $repair_number = '') {
        $settings = PCWork_Admin_Integration_Settings::get_settings();
        if (($settings['sheets_enabled'] ?? '0') !== '1') return;
        if (empty($settings['sheets_webhook_url']) || empty($settings['sheets_webhook_secret'])) {
            error_log('PCWork Sheets: integration enabled but URL/secret is missing.');
            return;
        }

        global $wpdb;
        $table = PCWork_Mobile_Repairs_API::repairs_table();
        $row = $wpdb->get_row($wpdb->prepare("SELECT * FROM {$table} WHERE id = %d", absint($repair_id)), ARRAY_A);
        if (!$row) {
            error_log('PCWork Sheets: repair not found: ' . absint($repair_id));
            return;
        }

        $payload_data = [
            'event' => 'pcwork.repair.upsert',
            'sent_at' => gmdate('c'),
            'repair' => [
                'repair_id' => (int)($row['id'] ?? 0),
                'repair_number' => (string)($row['repair_number'] ?? $repair_number),
                'customer_name' => (string)($row['customer_name'] ?? ''),
                'customer_email' => (string)($row['customer_email'] ?? ''),
                'customer_phone' => (string)($row['customer_phone'] ?? ''),
                'location_code' => (string)($row['location_code'] ?? ''),
                'location_name' => (string)($row['location_name'] ?? ''),
                'device_type' => (string)($row['device_type'] ?? ''),
                'device_model' => (string)($row['device_model'] ?? ''),
                'serial_number' => (string)($row['serial_number'] ?? ''),
                'problem_description' => (string)($row['problem_description'] ?? ''),
                'external_condition' => (string)($row['external_condition'] ?? ''),
                'accessories' => (string)($row['accessories'] ?? ''),
                'status' => (string)($row['status'] ?? $status),
                'assigned_technician_id' => (int)($row['assigned_technician_id'] ?? 0),
                'priority' => (string)($row['priority'] ?? 'normal'),
                'due_at' => (string)($row['due_at'] ?? ''),
                'created_at' => (string)($row['created_at'] ?? ''),
                'updated_at' => (string)($row['updated_at'] ?? ''),
            ],
        ];

        $payload = wp_json_encode($payload_data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if (!$payload) {
            error_log('PCWork Sheets: JSON encoding failed.');
            return;
        }
        $response = self::post_json(
            $settings['sheets_webhook_url'],
            $payload,
            $settings['sheets_webhook_secret']
        );
        if (is_wp_error($response)) {
            error_log('PCWork Sheets sync error: ' . $response->get_error_message());
            return;
        }
        $code = (int) wp_remote_retrieve_response_code($response);
        $raw_body = (string) wp_remote_retrieve_body($response);
        $response_body = json_decode($raw_body, true);
        if ($code < 200 || $code >= 300 || !is_array($response_body) || empty($response_body['ok'])) {
            $excerpt = trim(wp_strip_all_tags($raw_body));
            if (function_exists('mb_substr')) $excerpt = mb_substr($excerpt, 0, 400); else $excerpt = substr($excerpt, 0, 400);
            error_log('PCWork Sheets sync failed (HTTP ' . $code . '): ' . ($excerpt !== '' ? $excerpt : '[empty response]'));
        }
    }
}
PCWork_Google_Sheets_Sync::init();
