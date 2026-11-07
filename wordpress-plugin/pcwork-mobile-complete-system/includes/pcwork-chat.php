<?php
if (!defined('ABSPATH')) exit;

/**
 * Lightweight first-party PCWork support chat.
 * One conversation per WordPress user; messages are stored in a compact indexed table.
 * Attachments are stored in the Media uploads directory, not as database blobs.
 */
final class PCWork_Chat {
    const DB_VERSION = '1.0.0';
    const OPTION_DB_VERSION = 'pcwork_chat_db_version';

    public static function init() {
        add_action('init', [__CLASS__, 'maybe_upgrade'], 5);
        add_action('rest_api_init', [__CLASS__, 'routes']);
        add_action('admin_menu', [__CLASS__, 'menu'], 60);
        add_action('admin_post_pcwork_chat_admin_reply', [__CLASS__, 'admin_reply']);
    }

    private static function table() {
        global $wpdb;
        return $wpdb->prefix . 'pcwork_chat_messages';
    }

    public static function activate() { self::install(); }

    public static function maybe_upgrade() {
        if (get_option(self::OPTION_DB_VERSION) !== self::DB_VERSION) self::install();
    }

    private static function install() {
        global $wpdb;
        require_once ABSPATH . 'wp-admin/includes/upgrade.php';
        $table = self::table();
        $charset = $wpdb->get_charset_collate();
        $sql = "CREATE TABLE {$table} (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            thread_user_id BIGINT UNSIGNED NOT NULL,
            sender_user_id BIGINT UNSIGNED NOT NULL,
            sender_type VARCHAR(12) NOT NULL DEFAULT 'customer',
            message TEXT NOT NULL,
            attachment_url VARCHAR(512) NOT NULL DEFAULT '',
            created_at DATETIME NOT NULL,
            read_at DATETIME NULL DEFAULT NULL,
            PRIMARY KEY  (id),
            KEY thread_id (thread_user_id, id),
            KEY unread (thread_user_id, sender_type, read_at),
            KEY created_at (created_at)
        ) {$charset};";
        dbDelta($sql);
        update_option(self::OPTION_DB_VERSION, self::DB_VERSION, false);
    }

    public static function routes() {
        register_rest_route('pcwork/v1', '/chat/messages', [
            ['methods'=>'GET', 'callback'=>[__CLASS__, 'get_messages'], 'permission_callback'=>['PCWork_Mobile_Auth_Bridge', 'authorize']],
            ['methods'=>'POST', 'callback'=>[__CLASS__, 'send_message'], 'permission_callback'=>['PCWork_Mobile_Auth_Bridge', 'authorize']],
        ]);
    }

    private static function current_user_allowed() {
        $id = get_current_user_id();
        if (!$id) return new WP_Error('pcw_chat_auth', 'Необходим е вход в профила.', ['status'=>401]);
        $user = get_user_by('id', $id);
        if (!$user) return new WP_Error('pcw_chat_user', 'Потребителят не е намерен.', ['status'=>401]);
        return $user;
    }

    public static function get_messages($request) {
        global $wpdb;
        $user = self::current_user_allowed();
        if (is_wp_error($user)) return $user;
        $after = absint($request->get_param('after_id'));
        $table = self::table();
        $rows = $wpdb->get_results($wpdb->prepare(
            "SELECT id, sender_user_id, sender_type, message, attachment_url, created_at
             FROM {$table} WHERE thread_user_id=%d AND id>%d ORDER BY id ASC LIMIT 60",
            $user->ID, $after
        ), ARRAY_A);
        $wpdb->query($wpdb->prepare(
            "UPDATE {$table} SET read_at=%s WHERE thread_user_id=%d AND sender_type='admin' AND read_at IS NULL",
            current_time('mysql', true), $user->ID
        ));
        return rest_ensure_response(['data'=>$rows ?: [], 'last_id'=>$rows ? (int)end($rows)['id'] : $after]);
    }

    public static function send_message($request) {
        global $wpdb;
        $user = self::current_user_allowed();
        if (is_wp_error($user)) return $user;
        $rate_key = 'pcw_chat_rate_' . (int)$user->ID;
        $rate = (int)get_transient($rate_key);
        if ($rate >= 12) return new WP_Error('pcw_chat_rate_limited', 'Изпратихте твърде много съобщения. Изчакайте една минута и опитайте отново.', ['status'=>429]);
        set_transient($rate_key, $rate + 1, MINUTE_IN_SECONDS);
        $message = trim(sanitize_textarea_field((string)$request->get_param('message')));
        $attachment = '';
        $image = (string)$request->get_param('image_base64');
        if ($image !== '') {
            if (strlen($image) > 7 * 1024 * 1024) return new WP_Error('pcw_chat_image_size', 'Снимката е твърде голяма (максимум 5 MB).', ['status'=>413]);
            $mime = sanitize_mime_type((string)$request->get_param('image_mime'));
            $allowed = ['image/jpeg'=>'jpg', 'image/png'=>'png', 'image/webp'=>'webp'];
            if (!isset($allowed[$mime])) return new WP_Error('pcw_chat_image_type', 'Позволени са JPG, PNG и WEBP изображения.', ['status'=>415]);
            $raw = base64_decode(preg_replace('/^data:[^;]+;base64,/', '', $image), true);
            $image_info = $raw !== false ? @getimagesizefromstring($raw) : false;
            if ($raw === false || strlen($raw) > 5 * 1024 * 1024 || $image_info === false || ($image_info['mime'] ?? '') !== $mime) {
                return new WP_Error('pcw_chat_image_invalid', 'Изображението е невалидно, форматът не съвпада или надвишава 5 MB.', ['status'=>400]);
            }
            require_once ABSPATH . 'wp-admin/includes/file.php';
            $filename = 'pcwork-chat-' . (int)$user->ID . '-' . wp_generate_password(8, false, false) . '.' . $allowed[$mime];
            $upload = wp_upload_bits($filename, null, $raw);
            if (!empty($upload['error'])) return new WP_Error('pcw_chat_upload', 'Качването на снимката неуспешно: ' . $upload['error'], ['status'=>500]);
            $attachment = esc_url_raw($upload['url']);
        }
        if ($message === '' && $attachment === '') return new WP_Error('pcw_chat_empty', 'Напишете съобщение или добавете снимка.', ['status'=>400]);
        if (strlen($message) > 4000) return new WP_Error('pcw_chat_length', 'Съобщението е твърде дълго (максимум 4000 символа).', ['status'=>400]);
        $ok = $wpdb->insert(self::table(), [
            'thread_user_id'=>(int)$user->ID,
            'sender_user_id'=>(int)$user->ID,
            'sender_type'=>'customer',
            'message'=>$message,
            'attachment_url'=>$attachment,
            'created_at'=>current_time('mysql', true),
            'read_at'=>null,
        ], ['%d','%d','%s','%s','%s','%s','%s']);
        if (!$ok) return new WP_Error('pcw_chat_save', 'Съобщението не беше записано. Опитайте отново.', ['status'=>500]);
        do_action('pcwork_chat_message_created', (int)$user->ID, 'customer', (int)$wpdb->insert_id);
        return rest_ensure_response(['success'=>true, 'id'=>(int)$wpdb->insert_id]);
    }

    public static function menu() {
        add_submenu_page('pcwork-mobile', 'PCWork Chat', 'Чат', 'manage_options', 'pcwork-chat', [__CLASS__, 'render_admin']);
    }

    private static function can_admin() {
        return current_user_can('manage_options') || current_user_can('manage_woocommerce') || current_user_can('pcwork_manage_repairs');
    }

    public static function render_admin() {
        if (!self::can_admin()) return;
        global $wpdb;
        $table = self::table();
        $threads = $wpdb->get_results(
            "SELECT m.thread_user_id, MAX(m.id) AS last_id, MAX(m.created_at) AS last_at,
             SUM(CASE WHEN m.sender_type='customer' AND m.read_at IS NULL THEN 1 ELSE 0 END) AS unread_count
             FROM {$table} m GROUP BY m.thread_user_id ORDER BY last_id DESC LIMIT 100",
            ARRAY_A
        );
        $selected = absint($_GET['user_id'] ?? ($threads[0]['thread_user_id'] ?? 0));
        echo '<div class="wrap"><h1>PCWork Chat</h1><p>Разговори с клиенти. Обновявайте страницата, за да видите новите съобщения.</p><div style="display:grid;grid-template-columns:minmax(220px,30%) 1fr;gap:18px">';
        echo '<div class="card" style="margin:0;padding:12px"><h2>Разговори</h2>';
        foreach ($threads as $thread) {
            $uid = (int)$thread['thread_user_id']; $u = get_user_by('id', $uid);
            if (!$u) continue;
            $url = add_query_arg(['page'=>'pcwork-chat','user_id'=>$uid], admin_url('admin.php'));
            echo '<p><a href="'.esc_url($url).'"><strong>'.esc_html($u->display_name ?: $u->user_email).'</strong></a><br><small>'.esc_html($u->user_email).' · '.esc_html($thread['last_at']).'</small>';
            if ((int)$thread['unread_count'] > 0) echo ' <span class="count">'.(int)$thread['unread_count'].'</span>';
            echo '</p><hr>';
        }
        echo '</div><div class="card" style="margin:0;padding:12px">';
        if (!$selected || !get_user_by('id', $selected)) {
            echo '<p>Изберете разговор от списъка.</p>';
        } else {
            $u = get_user_by('id', $selected);
            $phone = trim((string)get_user_meta($selected, 'pcwork_phone', true));
            if ($phone === '') $phone = trim((string)get_user_meta($selected, 'billing_phone', true));
            if ($phone === '') $phone = trim((string)get_user_meta($selected, 'shipping_phone', true));
            $rows = $wpdb->get_results($wpdb->prepare("SELECT * FROM {$table} WHERE thread_user_id=%d ORDER BY id DESC LIMIT 60", $selected), ARRAY_A);
            $wpdb->query($wpdb->prepare("UPDATE {$table} SET read_at=%s WHERE thread_user_id=%d AND sender_type='customer' AND read_at IS NULL", current_time('mysql', true), $selected));
            echo '<h2>'.esc_html($u->display_name).' <small>'.esc_html($u->user_email).($phone !== '' ? ' · '.esc_html($phone) : '').'</small></h2><div style="max-height:55vh;overflow:auto;display:flex;flex-direction:column-reverse;gap:10px">';
            foreach (array_reverse($rows ?: []) as $row) {
                $admin = $row['sender_type'] === 'admin';
                echo '<div style="padding:10px 13px;border-radius:10px;max-width:85%;'.($admin?'align-self:flex-end;background:#e4f5f5':'background:#f0f0f1').'"><strong>'.($admin?'PCWork':'Клиент').'</strong><br>'.nl2br(esc_html($row['message']));
                if (!empty($row['attachment_url'])) echo '<br><a target="_blank" rel="noopener" href="'.esc_url($row['attachment_url']).'">Прикачена снимка</a>';
                echo '<br><small>'.esc_html($row['created_at']).'</small></div>';
            }
            echo '</div><form method="post" enctype="multipart/form-data" action="'.esc_url(admin_url('admin-post.php')).'" style="margin-top:14px"><input type="hidden" name="action" value="pcwork_chat_admin_reply"><input type="hidden" name="user_id" value="'.$selected.'">';
            wp_nonce_field('pcwork_chat_reply_'.$selected);
            echo '<textarea name="message" rows="3" maxlength="4000" style="width:100%" placeholder="Напишете отговор..."></textarea><p><label>Снимка (до 5 MB): <input type="file" name="attachment" accept="image/jpeg,image/png,image/webp"></label></p><p><button class="button button-primary">Изпрати отговор</button> <a class="button" href="'.esc_url(add_query_arg(['page'=>'pcwork-chat','user_id'=>$selected],admin_url('admin.php'))).'">Обнови</a></p></form>';
        }
        echo '</div></div></div><script>(function(){setInterval(function(){if(document.visibilityState==="visible"&&!document.querySelector("textarea:focus")&&!document.querySelector("input[type=file]:focus")){window.location.reload();}},15000);})();</script>';
    }

    public static function admin_reply() {
        if (!self::can_admin()) wp_die('Нямате права за тази операция.');
        global $wpdb;
        $uid = absint($_POST['user_id'] ?? 0);
        check_admin_referer('pcwork_chat_reply_'.$uid);
        if (!$uid || !get_user_by('id', $uid)) wp_die('Клиентът не е намерен.');
        $message = trim(sanitize_textarea_field(wp_unslash($_POST['message'] ?? '')));
        if (strlen($message) > 4000) wp_die('Съобщението е твърде дълго.');
        $attachment = '';
        if (!empty($_FILES['attachment']['name'])) {
            if ((int)($_FILES['attachment']['size'] ?? 0) > 5 * 1024 * 1024) wp_die('Снимката трябва да е до 5 MB.');
            $filetype = wp_check_filetype_and_ext($_FILES['attachment']['tmp_name'], $_FILES['attachment']['name']);
            if (!in_array($filetype['type'] ?? '', ['image/jpeg','image/png','image/webp'], true)) wp_die('Позволени са JPG, PNG и WEBP изображения.');
            require_once ABSPATH . 'wp-admin/includes/file.php';
            $upload = wp_handle_upload($_FILES['attachment'], ['test_form'=>false, 'mimes'=>['jpg|jpeg'=>'image/jpeg','png'=>'image/png','webp'=>'image/webp']]);
            if (!empty($upload['error'])) wp_die('Качването на снимката неуспешно: '.esc_html($upload['error']));
            $attachment = esc_url_raw($upload['url'] ?? '');
        }
        if ($message === '' && $attachment === '') wp_die('Напишете съобщение или добавете снимка.');
        $ok = $wpdb->insert(self::table(), [
            'thread_user_id'=>$uid, 'sender_user_id'=>get_current_user_id(),
            'sender_type'=>'admin', 'message'=>$message, 'attachment_url'=>$attachment,
            'created_at'=>current_time('mysql', true), 'read_at'=>null,
        ], ['%d','%d','%s','%s','%s','%s','%s']);
        if (!$ok) wp_die('Съобщението не беше записано.');
        do_action('pcwork_chat_message_created', $uid, 'admin', (int)$wpdb->insert_id);
        wp_safe_redirect(add_query_arg(['page'=>'pcwork-chat','user_id'=>$uid,'sent'=>'1'], admin_url('admin.php')));
        exit;
    }
}
PCWork_Chat::init();
