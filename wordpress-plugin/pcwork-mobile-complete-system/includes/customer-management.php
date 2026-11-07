<?php
if (!defined('ABSPATH')) exit;

final class PCWork_Mobile_Customer_Management {
    public static function init() {
        add_action('admin_menu', [__CLASS__, 'menu'], 59);
        add_action('admin_post_pcwork_customer_save', [__CLASS__, 'save']);
        add_action('admin_post_pcwork_customer_delete', [__CLASS__, 'delete']);
        add_action('admin_post_pcwork_order_delete', [__CLASS__, 'delete_order']);
        add_action('admin_post_pcwork_orders_bulk_delete', [__CLASS__, 'bulk_delete_orders']);
    }
    public static function menu() {
        add_submenu_page('pcwork-mobile','Клиенти','Клиенти','manage_options','pcwork-customers',[__CLASS__,'render']);
    }
    private static function customer_user($id) {
        $user=get_user_by('id',absint($id));
        if (!$user || !array_intersect(['customer','pcwork_customer','subscriber'],(array)$user->roles)) return false;
        return $user;
    }
    public static function save() {
        if (!current_user_can('manage_options')) wp_die('Нямате права за тази операция.');
        $id=absint($_POST['user_id']??0); check_admin_referer('pcwork_customer_save_'.$id);
        $user=self::customer_user($id); if (!$user) wp_die('Клиентът не е намерен.');
        $name=sanitize_text_field(wp_unslash($_POST['display_name']??''));
        $phone=sanitize_text_field(wp_unslash($_POST['phone']??''));
        $billing=sanitize_textarea_field(wp_unslash($_POST['billing_address']??''));
        $shipping=sanitize_textarea_field(wp_unslash($_POST['shipping_address']??''));
        if ($name==='') wp_die('Името е задължително.');
        $result=wp_update_user(['ID'=>$id,'display_name'=>$name]);
        if (is_wp_error($result)) wp_die(esc_html($result->get_error_message()));
        update_user_meta($id,'pcwork_phone',$phone);
        update_user_meta($id,'billing_phone',$phone);
        update_user_meta($id,'billing_address_1',$billing);
        update_user_meta($id,'shipping_address_1',$shipping);
        wp_safe_redirect(add_query_arg(['page'=>'pcwork-customers','tab'=>'edit','user_id'=>$id,'saved'=>'1'],admin_url('admin.php'))); exit;
    }
    public static function delete() {
        if (!current_user_can('manage_options')) wp_die('Нямате права за тази операция.');
        $id=absint($_POST['user_id']??0); check_admin_referer('pcwork_customer_delete_'.$id);
        $user=self::customer_user($id); if (!$user) wp_die('Клиентът не е намерен или няма право да бъде изтрит.');
        if ($id===get_current_user_id()) wp_die('Не можете да изтриете собствения си профил.');
        global $wpdb;
        $repairs= $wpdb->prefix.'pcwork_repairs';
        $repair_ids=$wpdb->get_col($wpdb->prepare("SELECT id FROM $repairs WHERE customer_user_id=%d",$id));
        if ($repair_ids) {
            $ids=implode(',',array_map('absint',$repair_ids));
            foreach (['pcwork_repair_history','pcwork_repair_documents','pcwork_repair_worklog'] as $suffix) {
                $table=$wpdb->prefix.$suffix;
                if ($wpdb->get_var($wpdb->prepare('SHOW TABLES LIKE %s',$table))===$table) $wpdb->query("DELETE FROM $table WHERE repair_id IN ($ids)");
            }
            $wpdb->delete($repairs,['customer_user_id'=>$id],['%d']);
        }
        require_once ABSPATH.'wp-admin/includes/user.php';
        $deleted=wp_delete_user($id);
        if (!$deleted) wp_die('Потребителят не беше изтрит. Проверете дали WordPress позволява изтриването.');
        wp_safe_redirect(add_query_arg(['page'=>'pcwork-customers','deleted'=>'1','repairs_deleted'=>count($repair_ids)],admin_url('admin.php'))); exit;
    }
    public static function toggle_status() {
        if (!current_user_can('manage_options')) wp_die('Нямате права за тази операция.');
        $user_id=absint($_GET['user_id']??0); check_admin_referer('pcwork_customer_toggle_'.$user_id);
        $user=self::customer_user($user_id); if (!$user) wp_die('Клиентският профил не е намерен.');
        if (!empty($_GET['block'])) update_user_meta($user_id,'pcwork_account_blocked',1); else delete_user_meta($user_id,'pcwork_account_blocked');
        wp_safe_redirect(admin_url('admin.php?page=pcwork-customers&updated=1')); exit;
    }
    public static function delete_order() {
        if (!current_user_can('manage_options')) wp_die('Нямате права за тази операция.');
        $order_id = absint($_REQUEST['order_id'] ?? 0);
        check_admin_referer('pcwork_order_delete_' . $order_id);
        if (!function_exists('wc_get_order')) wp_die('WooCommerce не е активен.');
        $order = wc_get_order($order_id);
        if (!$order) wp_die('Поръчката не е намерена.');
        $deleted = $order->delete(true); // WooCommerce CRUD supports both posts and HPOS storage.
        if (!$deleted) wp_die('WooCommerce не успя да изтрие поръчката.');
        wp_safe_redirect(admin_url('admin.php?page=pcwork-customers&tab=orders&order_deleted=1'));
        exit;
    }

    public static function bulk_delete_orders() {
        if (!current_user_can('manage_options')) wp_die('Нямате права за тази операция.');
        check_admin_referer('pcwork_orders_bulk_delete');
        if (!function_exists('wc_get_order')) wp_die('WooCommerce не е активен.');
        $ids = isset($_POST['order_ids']) && is_array($_POST['order_ids']) ? array_slice(array_unique(array_filter(array_map('absint', $_POST['order_ids']))), 0, 100) : [];
        if (!$ids) {
            wp_safe_redirect(admin_url('admin.php?page=pcwork-customers&tab=orders&bulk_deleted=0'));
            exit;
        }
        $deleted = 0; $failed = 0;
        foreach ($ids as $id) {
            $order = wc_get_order($id);
            if ($order && $order->delete(true)) $deleted++; else $failed++;
        }
        wp_safe_redirect(add_query_arg(['page'=>'pcwork-customers','tab'=>'orders','bulk_deleted'=>$deleted,'bulk_failed'=>$failed], admin_url('admin.php')));
        exit;
    }

    private static function render_orders() {
        if (!function_exists('wc_get_orders')) {
            echo '<div class="notice notice-warning inline"><p>WooCommerce не е активен. Поръчките не могат да бъдат показани.</p></div>';
            return;
        }
        if (!empty($_GET['order_deleted'])) echo '<div class="notice notice-success inline"><p>Поръчката е изтрита окончателно.</p></div>';
        if (isset($_GET['bulk_deleted'])) echo '<div class="notice notice-success inline"><p>Изтрити поръчки: '.absint($_GET['bulk_deleted']).'. Неуспешни: '.absint($_GET['bulk_failed'] ?? 0).'.</p></div>';
        echo '<h2>WooCommerce поръчки</h2><p class="description">Показани са последните 100 поръчки. Изтриването е окончателно и се извършва през WooCommerce CRUD, включително при HPOS.</p>';
        $orders = wc_get_orders(['limit'=>100,'orderby'=>'date','order'=>'DESC','status'=>array_keys(wc_get_order_statuses()),'return'=>'objects']);
        echo '<form method="post" action="'.esc_url(admin_url('admin-post.php')).'" onsubmit="return confirm(\'Сигурни ли сте, че искате окончателно да изтриете избраните поръчки?\')"><input type="hidden" name="action" value="pcwork_orders_bulk_delete">';
        wp_nonce_field('pcwork_orders_bulk_delete');
        echo '<p><button type="submit" class="button button-link-delete">Изтрий избраните</button></p><table class="widefat striped"><thead><tr><th><input type="checkbox" onclick="document.querySelectorAll(\'.pcw-order-select\').forEach(function(c){c.checked=this.checked}.bind(this))"></th><th>Поръчка</th><th>Дата</th><th>Клиент</th><th>Имейл</th><th>Статус</th><th>Общо</th><th>Действие</th></tr></thead><tbody>';
        if (!$orders) echo '<tr><td colspan="8">Няма намерени поръчки.</td></tr>';
        foreach ($orders as $order) {
            if (!$order) continue;
            $id = (int)$order->get_id();
            $customer = trim($order->get_billing_first_name() . ' ' . $order->get_billing_last_name());
            if ($customer === '') $customer = '—';
            $date = $order->get_date_created();
            $date_text = $date ? wc_format_datetime($date, 'd.m.Y H:i') : '—';
            $edit_url = get_edit_post_link($id, 'raw');
            if (!$edit_url) $edit_url = admin_url('admin.php?page=wc-orders&action=edit&id='.$id);
            $delete_url = wp_nonce_url(add_query_arg(['action'=>'pcwork_order_delete','order_id'=>$id], admin_url('admin-post.php')), 'pcwork_order_delete_' . $id);
            echo '<tr><td><input class="pcw-order-select" type="checkbox" name="order_ids[]" value="'.$id.'"></td><td><strong>#'.esc_html($order->get_order_number()).'</strong><br><small>ID: '.$id.'</small></td><td>'.esc_html($date_text).'</td><td>'.esc_html($customer).'</td><td>'.esc_html($order->get_billing_email()).'</td><td>'.esc_html(wc_get_order_status_name($order->get_status())).'</td><td>'.wp_kses_post($order->get_formatted_order_total()).'</td><td><a class="button button-small" href="'.esc_url($edit_url).'">Редактирай</a> <a class="button button-link-delete" href="'.esc_url($delete_url).'" onclick="return confirm(\'Сигурни ли сте, че искате окончателно да изтриете тази WooCommerce поръчка? Действието не може да бъде отменено.\')">Изтрий</a></td></tr>';
        }
        echo '</tbody></table></form>';
    }

    public static function render() {
        if (!current_user_can('manage_options')) return;
        $tab=sanitize_key($_GET['tab']??'list');
        echo '<div class="wrap"><h1>PCWork Mobile – Клиенти</h1><nav class="nav-tab-wrapper">';
        $tabs=['list'=>'Клиенти','access'=>'Достъп без код','campaigns'=>'Реклами и кампании','orders'=>'Поръчки'];
        foreach($tabs as $key=>$label) echo '<a class="nav-tab '.($tab===$key?'nav-tab-active':'').'" href="'.esc_url(add_query_arg(['page'=>'pcwork-customers','tab'=>$key],admin_url('admin.php'))).'">'.esc_html($label).'</a>';
        echo '</nav>';
        if ($tab==='access') { PCWork_Mobile_Auth_Access_Admin::render(); echo '</div>'; return; }
        if ($tab==='campaigns') { if (!empty($_GET['campaign_deleted'])) echo '<div class="notice notice-success inline"><p>Кампанията е изтрита от историята. Вече изпратени push известия не могат да бъдат отменени.</p></div>'; PCWork_Admin_Integration_Settings::render_marketing(true); echo '</div>'; return; }
        if ($tab==='orders') { self::render_orders(); echo '</div>'; return; }
        if (!empty($_GET['saved'])) echo '<div class="notice notice-success"><p>Клиентският профил е обновен. Регистрационният имейл не е променян.</p></div>';
        if (!empty($_GET['deleted'])) echo '<div class="notice notice-success"><p>Клиентът е изтрит. Премахнати са и '.absint($_GET['repairs_deleted']??0).' свързани сервизни заявки и техните записи в историята/документите/работния дневник.</p></div>';
        if (!empty($_GET['updated'])) echo '<div class="notice notice-success"><p>Статусът на клиентския профил е обновен.</p></div>';
        $edit_id=absint($_GET['user_id']??0);
        if ($tab==='edit' && $edit_id) {
            $u=self::customer_user($edit_id);
            if (!$u) echo '<div class="notice notice-error"><p>Клиентът не е намерен.</p></div>';
            else {
                echo '<h2>Редактиране на клиент</h2><form method="post" action="'.esc_url(admin_url('admin-post.php')).'" style="max-width:650px">';
                echo '<input type="hidden" name="action" value="pcwork_customer_save"><input type="hidden" name="user_id" value="'.(int)$u->ID.'">'; wp_nonce_field('pcwork_customer_save_'.$u->ID);
                echo '<table class="form-table"><tr><th>Име</th><td><input class="regular-text" required name="display_name" value="'.esc_attr($u->display_name).'"></td></tr><tr><th>Регистрационен имейл</th><td><input class="regular-text" type="email" value="'.esc_attr($u->user_email).'" disabled><p class="description">Имейлът за вход е заключен и не се променя от тази форма.</p></td></tr><tr><th>Телефон</th><td><input class="regular-text" name="phone" value="'.esc_attr(get_user_meta($u->ID,'pcwork_phone',true)).'"></td></tr><tr><th>Адрес за фактуриране</th><td><textarea class="large-text" rows="2" name="billing_address">'.esc_textarea(get_user_meta($u->ID,'billing_address_1',true)).'</textarea></td></tr><tr><th>Адрес за доставка</th><td><textarea class="large-text" rows="2" name="shipping_address">'.esc_textarea(get_user_meta($u->ID,'shipping_address_1',true)).'</textarea></td></tr></table><p><button class="button button-primary">Запази профила</button> <a class="button" href="'.esc_url(admin_url('admin.php?page=pcwork-customers')).'">Назад</a></p></form>';
                echo '<hr><h2>Изтриване на клиент</h2><p class="description">Изтриването премахва WP профила, свързаните заявки и техните история/документи/работен дневник. Действието е необратимо. Архивирайте базата предварително.</p><form method="post" action="'.esc_url(admin_url('admin-post.php')).'" onsubmit="return confirm(\'Сигурни ли сте? Профилът и всички свързани ремонти ще бъдат изтрити необратимо.\')"><input type="hidden" name="action" value="pcwork_customer_delete"><input type="hidden" name="user_id" value="'.(int)$u->ID.'">'; wp_nonce_field('pcwork_customer_delete_'.$u->ID); echo '<button class="button button-link-delete">Изтрий клиента и свързаните данни</button></form>';
            }
            echo '</div>'; return;
        }
        $search=sanitize_text_field(wp_unslash($_GET['s']??''));
        $args=['role__in'=>['customer','pcwork_customer','subscriber'],'number'=>200,'orderby'=>'registered','order'=>'DESC'];
        if ($search!=='') { $args['search']='*'.$search.'*'; $args['search_columns']=['user_login','user_email','display_name']; }
        $users=get_users($args);
        echo '<form method="get" style="margin:16px 0"><input type="hidden" name="page" value="pcwork-customers"><input type="search" name="s" value="'.esc_attr($search).'" placeholder="Име, имейл или потребителско име"> <button class="button">Търси</button></form>';
        echo '<table class="widefat striped"><thead><tr><th>Клиент</th><th>Имейл</th><th>Телефон</th><th>Вход без код</th><th>Статус</th><th>Действия</th></tr></thead><tbody>';
        if (!$users) echo '<tr><td colspan="6">Няма намерени клиенти.</td></tr>';
        foreach($users as $u) {
            $blocked=(bool)get_user_meta($u->ID,'pcwork_account_blocked',true); $bypass=get_user_meta($u->ID,'pcwork_otp_bypass',true)==='1';
            $toggle=wp_nonce_url(admin_url('admin-post.php?action=pcwork_customer_toggle&user_id='.(int)$u->ID.'&block='.($blocked?'0':'1')),'pcwork_customer_toggle_'.(int)$u->ID);
            $edit=add_query_arg(['page'=>'pcwork-customers','tab'=>'edit','user_id'=>(int)$u->ID],admin_url('admin.php'));
            $phone = (string)get_user_meta($u->ID,'pcwork_phone',true); if ($phone === '') $phone = (string)get_user_meta($u->ID,'billing_phone',true);
            echo '<tr><td><strong>'.esc_html($u->display_name).'</strong><br><small>ID: '.(int)$u->ID.'</small></td><td>'.esc_html($u->user_email).'</td><td>'.esc_html($phone).'</td><td>'.($bypass?'<span style="color:#008a20">Разрешен</span>':'Не е разрешен').'</td><td>'.($blocked?'<strong style="color:#b32d2e">Блокиран</strong>':'<strong style="color:green">Активен</strong>').'</td><td><a class="button" href="'.esc_url($edit).'">Редактирай</a> <a class="button" href="'.esc_url($toggle).'">'.($blocked?'Активирай':'Блокирай').'</a></td></tr>';
        }
        echo '</tbody></table><p class="description">Показани са до 200 профила. Управлението на входа без OTP е в раздела „Достъп без код“ по-горе.</p></div>';
    }
}
PCWork_Mobile_Customer_Management::init();
