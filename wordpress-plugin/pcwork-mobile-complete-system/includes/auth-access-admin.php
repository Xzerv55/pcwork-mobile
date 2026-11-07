<?php
if (!defined('ABSPATH')) exit;

final class PCWork_Mobile_Auth_Access_Admin {
    public static function init() {
        add_action('admin_post_pcwork_auth_access', [__CLASS__, 'handle']);
    }
    public static function handle() {
        if (!current_user_can('manage_options')) wp_die('Нямате права за тази операция.');
        check_admin_referer('pcwork_auth_access_action');
        $user_id = absint($_POST['user_id'] ?? 0);
        $user = get_user_by('id', $user_id);
        if (!$user) { wp_safe_redirect(add_query_arg('pcw_auth_msg','missing',admin_url('admin.php?page=pcwork-customers&tab=access'))); exit; }
        $action = sanitize_key($_POST['pcw_action'] ?? '');
        $admin_id = get_current_user_id();
        if ($action === 'grant' || $action === 'revoke') {
            $enabled = $action === 'grant';
            update_user_meta($user_id, 'pcwork_otp_bypass', $enabled ? '1' : '0');
            update_user_meta($user_id, 'pcwork_otp_bypass_changed_at', current_time('mysql'));
            update_user_meta($user_id, 'pcwork_otp_bypass_changed_by', $admin_id);
            self::append_audit($user_id, [
                'action' => $enabled ? 'granted' : 'revoked',
                'admin_id' => $admin_id,
                'admin_login' => wp_get_current_user()->user_login,
                'at' => current_time('mysql'),
            ]);
            $msg = $enabled ? 'granted' : 'revoked';
        } elseif ($action === 'reset_limit') {
            PCWork_Mobile_Auth_Bridge::clear_user_rate_limits($user_id);
            update_user_meta($user_id, 'pcwork_otp_limit_reset_at', current_time('mysql'));
            update_user_meta($user_id, 'pcwork_otp_limit_reset_by', $admin_id);
            self::append_audit($user_id, ['action'=>'otp_limit_reset','admin_id'=>$admin_id,'admin_login'=>wp_get_current_user()->user_login,'at'=>current_time('mysql')]);
            $msg = 'reset';
        } else { $msg = 'invalid'; }
        wp_safe_redirect(add_query_arg('pcw_auth_msg', $msg, admin_url('admin.php?page=pcwork-customers&tab=access')));
        exit;
    }
    private static function append_audit($user_id, $entry) {
        $log = get_user_meta($user_id, 'pcwork_auth_access_log', true);
        if (!is_array($log)) $log = [];
        $log[] = $entry;
        if (count($log) > 50) $log = array_slice($log, -50);
        update_user_meta($user_id, 'pcwork_auth_access_log', $log);
    }
    public static function render() {
        if (!current_user_can('manage_options')) return;
        $search = sanitize_text_field(wp_unslash($_GET['s'] ?? ''));
        $args = ['number'=>50, 'orderby'=>'display_name', 'order'=>'ASC'];
        if ($search !== '') { $args['search'] = '*' . $search . '*'; $args['search_columns'] = ['user_login','user_email','display_name']; }
        $users = get_users($args);
        echo '<h2>Достъп без код</h2>'; 
        echo '<p>За избран потребител се разрешава вход с <strong>имейл/потребителско име и WordPress парола</strong>, без еднократен имейл код. Само имейл адресът не е достатъчен. За всички останали потребители OTP остава задължителен.</p>';
        $messages = ['granted'=>'Правото за вход с парола е разрешено.','revoked'=>'Правото за вход с парола е отнето.','reset'=>'Лимитът за кодове на потребителя е нулиран.','missing'=>'Потребителят не е намерен.','invalid'=>'Невалидна операция.'];
        $msg = sanitize_key($_GET['pcw_auth_msg'] ?? '');
        if (isset($messages[$msg])) echo '<div class="notice notice-success is-dismissible"><p>'.esc_html($messages[$msg]).'</p></div>';
        echo '<form method="get" style="margin:16px 0"><input type="hidden" name="page" value="pcwork-customers"><input type="hidden" name="tab" value="access"><input type="search" name="s" value="'.esc_attr($search).'" placeholder="Имейл, потребителско име или име"><button class="button">Търси</button></form>';
        echo '<table class="widefat striped"><thead><tr><th>Потребител</th><th>Имейл</th><th>Роля</th><th>Вход с парола без код</th><th>Последна промяна</th><th>Действия</th></tr></thead><tbody>';
        if (!$users) echo '<tr><td colspan="6">Няма намерени потребители.</td></tr>';
        foreach ($users as $u) {
            $enabled = get_user_meta($u->ID, 'pcwork_otp_bypass', true) === '1';
            $changed = (string)get_user_meta($u->ID, 'pcwork_otp_bypass_changed_at', true);
            $audit = get_user_meta($u->ID, 'pcwork_auth_access_log', true);
            $last_audit = is_array($audit) && $audit ? end($audit) : [];
            $audit_label = is_array($last_audit) ? (($last_audit['action'] ?? '') . ' · ' . ($last_audit['at'] ?? '') . ' · ' . ($last_audit['admin_login'] ?? '')) : '';
            $roles = implode(', ', array_map('translate_user_role', (array)$u->roles));
            echo '<tr><td><strong>'.esc_html($u->display_name).'</strong><br><small>ID: '.(int)$u->ID.' · '.esc_html($u->user_login).'</small></td><td>'.esc_html($u->user_email).'</td><td>'.esc_html($roles).'</td><td>'.($enabled ? '<span style="color:#008a20;font-weight:600">Разрешен</span>' : 'Не е разрешен').'</td><td>'.esc_html($changed ?: '—').'<br><small>'.esc_html($audit_label).'</small></td><td><div style="display:flex;gap:6px;flex-wrap:wrap">';
            echo '<form method="post" action="'.esc_url(admin_url('admin-post.php')).'">';
            wp_nonce_field('pcwork_auth_access_action');
            echo '<input type="hidden" name="action" value="pcwork_auth_access"><input type="hidden" name="user_id" value="'.(int)$u->ID.'">';
            if ($enabled) echo '<button class="button" name="pcw_action" value="revoke" onclick="return confirm(\'Да отнема ли достъпа без код?\')">Отнеми достъпа</button>';
            else echo '<button class="button button-primary" name="pcw_action" value="grant" onclick="return confirm(\'Разрешавате вход с WordPress парола за този потребител. Продължаваме ли?\')">Разреши вход с парола</button>';
            echo '<button class="button" name="pcw_action" value="reset_limit">Нулирай лимита</button></form></div></td></tr>';
        }
        echo '</tbody></table><p class="description">Показват се до 50 потребители. Всяка промяна се записва с администратор и час. Не се изпраща парола и администраторът не може да я види.</p>';
    }
}
PCWork_Mobile_Auth_Access_Admin::init();
