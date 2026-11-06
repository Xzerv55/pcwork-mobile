<?php
if (!defined('ABSPATH')) exit;

final class PCWork_Mobile_Customer_Management {
    public static function init() {
        add_action('admin_menu', [__CLASS__, 'menu'], 59);
        add_action('admin_post_pcwork_customer_toggle', [__CLASS__, 'toggle_status']);
    }
    public static function menu() {
        add_submenu_page('pcwork-mobile','Клиенти','Клиенти','manage_options','pcwork-customers',[__CLASS__,'render']);
    }
    public static function toggle_status() {
        if (!current_user_can('manage_options')) wp_die('Нямате права за тази операция.');
        $user_id=absint($_GET['user_id']??0);
        check_admin_referer('pcwork_customer_toggle_'.$user_id);
        $user=get_user_by('id',$user_id);
        if (!$user || !in_array('pcwork_customer',(array)$user->roles,true)) wp_die('Клиентският профил не е намерен.');
        if (!empty($_GET['block'])) update_user_meta($user_id,'pcwork_account_blocked',1);
        else delete_user_meta($user_id,'pcwork_account_blocked');
        wp_safe_redirect(admin_url('admin.php?page=pcwork-customers&updated=1'));
        exit;
    }
    public static function render() {
        if (!current_user_can('manage_options')) return;
        $users=get_users(['role'=>'pcwork_customer','number'=>200,'orderby'=>'registered','order'=>'DESC']);
        echo '<div class="wrap"><h1>PCWork Mobile – Клиенти</h1><p>Клиентските профили имат достъп само до собствените си ремонти, поръчки и лични данни. Блокираните профили не могат да използват мобилното API.</p>';
        if (!empty($_GET['updated'])) echo '<div class="notice notice-success is-dismissible"><p>Статусът на клиентския профил е обновен.</p></div>';
        echo '<table class="widefat striped"><thead><tr><th>Клиент</th><th>Имейл</th><th>Телефон</th><th>Имейл потвърден</th><th>Регистрация</th><th>Статус</th><th>Действие</th></tr></thead><tbody>';
        if (!$users) echo '<tr><td colspan="7">Все още няма клиентски профили.</td></tr>';
        foreach ($users as $user) {
            $blocked=(bool)get_user_meta($user->ID,'pcwork_account_blocked',true);
            $verified=(bool)get_user_meta($user->ID,'pcwork_email_verified',true);
            $url=wp_nonce_url(admin_url('admin-post.php?action=pcwork_customer_toggle&user_id='.(int)$user->ID.'&block='.($blocked?'0':'1')),'pcwork_customer_toggle_'.(int)$user->ID);
            echo '<tr><td><strong>'.esc_html($user->display_name).'</strong></td><td>'.esc_html($user->user_email).'</td><td>'.esc_html((string)get_user_meta($user->ID,'pcwork_phone',true)).'</td><td>'.($verified?'<span style="color:green">Потвърден</span>':'<span style="color:#b32d2e">Непотвърден</span>').'</td><td>'.esc_html($user->user_registered).'</td><td>'.($blocked?'<strong style="color:#b32d2e">Блокиран</strong>':'<strong style="color:green">Активен</strong>').'</td><td><a class="button '.($blocked?'':'button-secondary').'" href="'.esc_url($url).'">'.($blocked?'Активирай':'Блокирай').'</a></td></tr>';
        }
        echo '</tbody></table><p class="description">Показани са до 200 последно регистрирани клиентски профила. За масови действия използвайте стандартните инструменти на WordPress.</p></div>';
    }
}
PCWork_Mobile_Customer_Management::init();
