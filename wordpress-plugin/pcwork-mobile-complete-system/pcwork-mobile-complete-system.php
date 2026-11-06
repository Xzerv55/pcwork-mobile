<?php
/**
 * Plugin Name: PCWork Mobile – Complete System
 * Description: Единен модул за мобилно приложение, вход, сервизни ремонти и административни интеграции на PCWork.
 * Version: 2.1.0
 * Author: PCWork
 * Text Domain: pcwork-mobile
 */
if (!defined('ABSPATH')) exit;

define('PCWORK_MOBILE_COMPLETE_VERSION', '2.1.0');
define('PCWORK_MOBILE_COMPLETE_FILE', __FILE__);

require_once __DIR__ . '/includes/auth-bridge.php';
require_once __DIR__ . '/includes/repairs-api.php';
require_once __DIR__ . '/includes/admin-integration-settings.php';

/** Unified admin landing page. */
add_action('admin_menu', function () {
    add_menu_page(
        'PCWork Mobile',
        'PCWork Mobile',
        'manage_options',
        'pcwork-mobile',
        'pcwork_mobile_complete_dashboard',
        'dashicons-smartphone',
        58
    );
}, 58);

function pcwork_mobile_complete_dashboard() {
    if (!current_user_can('manage_options')) return;
    echo '<div class="wrap"><h1>PCWork Mobile – Complete System</h1>';
    echo '<p>Единен административен център за мобилното приложение и сервизната система.</p>';
    echo '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px;max-width:1000px">';
    $cards = [
        ['Интеграции', 'Bookly, WooCommerce, Google Sheets, Firebase, Chatway, Chaty и ShopLentor.', admin_url('admin.php?page=pcwork-integrations')],
        ['Сервизни ремонти', 'Ремонти, история, документи, протоколи и разпределение към техник.', admin_url('admin.php?page=pcwork-mobile')],
        ['REST API', 'Общ API адрес: /wp-json/pcwork/v1/ – използва се от Android и iOS приложението.', rest_url('pcwork/v1/')],
    ];
    foreach ($cards as $card) {
        echo '<section style="background:#fff;border:1px solid #dcdcde;border-radius:10px;padding:18px">';
        echo '<h2 style="margin-top:0">'.esc_html($card[0]).'</h2><p>'.esc_html($card[1]).'</p>';
        echo '<a class="button button-primary" href="'.esc_url($card[2]).'">Отвори</a></section>';
    }
    echo '</div><p style="margin-top:20px;color:#646970">Версия '.esc_html(PCWORK_MOBILE_COMPLETE_VERSION).'. Направете резервно копие преди обновяване и тествайте първо в staging среда.</p></div>';
}

register_activation_hook(__FILE__, function () {
    if (class_exists('PCWork_Mobile_Repairs_API')) PCWork_Mobile_Repairs_API::activate();
});
