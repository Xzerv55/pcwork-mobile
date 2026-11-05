<?php
if (!defined('ABSPATH')) exit;

final class PCWork_Admin_Integration_Settings {
    const OPTION = 'pcwork_mobile_integrations';
    const GROUP = 'pcwork_mobile_integrations_group';

    public static function init() {
        add_action('admin_menu', [__CLASS__, 'menu'], 99);
        add_action('admin_init', [__CLASS__, 'register']);
        add_action('admin_enqueue_scripts', [__CLASS__, 'styles']);
        add_action('admin_footer', [__CLASS__, 'admin_script']);
        add_action('rest_api_init', [__CLASS__, 'rest_routes']);
        add_action('wp_ajax_pcwork_test_integration', [__CLASS__, 'ajax_test_integration']);
        // Repair module should fire this action whenever a repair status changes.
        add_action('pcwork_repair_status_changed', [__CLASS__, 'on_repair_status_changed'], 10, 4);
    }

    public static function defaults() {
        return [
            'site_url' => home_url(),
            'woocommerce_enabled' => '1', 'woocommerce_consumer_key' => '', 'woocommerce_consumer_secret' => '',
            'bookly_enabled' => '1', 'bookly_api_url' => '', 'bookly_api_key' => '', 'bookly_booking_page_url' => '', 'bookly_shortcode' => '[bookly-form]',
            'chatway_enabled' => '1', 'chatway_widget_id' => '',
            'chaty_enabled' => '1', 'chaty_widget_id' => '',
            'shoplentor_enabled' => '1',
            'sheets_enabled' => '0', 'sheets_webhook_url' => '', 'sheets_webhook_secret' => '',
            'push_enabled' => '0', 'push_provider' => 'firebase', 'firebase_project_id' => '', 'firebase_service_account_json' => '', 'firebase_test_device_token' => '',
            'app_environment' => 'staging', 'support_email' => get_option('admin_email'), 'support_phone' => '',
        ];
    }

    public static function get_settings() {
        return wp_parse_args(get_option(self::OPTION, []), self::defaults());
    }

    public static function menu() {
        add_submenu_page('pcwork-mobile', 'Интеграции', 'Интеграции', 'manage_options', 'pcwork-integrations', [__CLASS__, 'render']);
    }

    public static function register() {
        register_setting(self::GROUP, self::OPTION, ['sanitize_callback' => [__CLASS__, 'sanitize']]);
    }

    public static function sanitize($input) {
        $old = self::get_settings();
        $out = self::defaults();
        $checkboxes = ['woocommerce_enabled','bookly_enabled','chatway_enabled','chaty_enabled','shoplentor_enabled','sheets_enabled','push_enabled'];
        foreach ($checkboxes as $key) $out[$key] = !empty($input[$key]) ? '1' : '0';
        $text = ['site_url','bookly_api_url','bookly_booking_page_url','bookly_shortcode','chatway_widget_id','chaty_widget_id','firebase_project_id','firebase_test_device_token','support_email','support_phone'];
        foreach ($text as $key) {
            $value = isset($input[$key]) ? wp_unslash($input[$key]) : '';
            $out[$key] = $key === 'support_email' ? sanitize_email($value) : ($key === 'site_url' || $key === 'bookly_api_url' ? esc_url_raw($value) : sanitize_text_field($value));
        }
        $secrets = ['woocommerce_consumer_key','woocommerce_consumer_secret','bookly_api_key','sheets_webhook_url','sheets_webhook_secret','firebase_service_account_json'];
        foreach ($secrets as $key) {
            $value = isset($input[$key]) ? trim(wp_unslash($input[$key])) : '';
            // Празно поле означава запазване на вече записаната тайна.
            $out[$key] = $value !== '' ? sanitize_textarea_field($value) : ($old[$key] ?? '');
        }
        $out['push_provider'] = in_array(($input['push_provider'] ?? ''), ['firebase'], true) ? $input['push_provider'] : 'firebase';
        $out['app_environment'] = in_array(($input['app_environment'] ?? ''), ['staging','production'], true) ? $input['app_environment'] : 'staging';
        return $out;
    }

    public static function styles($hook) {
        if (strpos($hook, 'pcwork-integrations') === false) return;
        wp_add_inline_style('common', '.pcw-wrap{max-width:1100px}.pcw-hero{background:#101b2b;color:#fff;padding:22px 26px;border-radius:12px;margin:18px 0}.pcw-hero h1{color:#fff;margin:0 0 6px}.pcw-hero p{margin:0;color:#b9d5df}.pcw-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(310px,1fr));gap:16px}.pcw-card{background:#fff;border:1px solid #dcdcde;border-radius:10px;padding:18px 20px;box-shadow:0 1px 2px #00000008}.pcw-card h2{margin-top:0;font-size:16px}.pcw-card label{display:block;font-weight:600;margin:12px 0 5px}.pcw-card input[type=text],.pcw-card input[type=url],.pcw-card input[type=email],.pcw-card input[type=password],.pcw-card textarea,.pcw-card select{width:100%;max-width:100%}.pcw-card .description{color:#646970}.pcw-toggle{display:flex!important;align-items:center;gap:8px;margin-top:8px!important}.pcw-note{background:#eff8fc;border-left:4px solid #00a6c7;padding:10px 13px;margin:16px 0}.pcw-save{margin-top:20px!important}.pcw-test{margin-top:12px!important}.pcw-result{display:inline-block;margin:12px 0 0 10px;font-weight:600}.pcw-result.ok{color:#16803c}.pcw-result.err{color:#b32d2e}');
    }

    private static function field($key, $label, $type='text', $placeholder='', $help='') {
        $s = self::get_settings(); $value = $s[$key] ?? '';
        echo '<label for="'.esc_attr($key).'">'.esc_html($label).'</label>';
        if ($type === 'textarea') echo '<textarea rows="4" id="'.esc_attr($key).'" name="'.self::OPTION.'['.esc_attr($key).']" placeholder="'.esc_attr($placeholder).'">'.esc_textarea($value).'</textarea>';
        else echo '<input type="'.esc_attr($type).'" id="'.esc_attr($key).'" name="'.self::OPTION.'['.esc_attr($key).']" value="'.esc_attr($type==='password' ? '' : $value).'" placeholder="'.esc_attr($placeholder).'" autocomplete="new-password">';
        if ($type === 'password' && $value !== '') $help = trim($help.' Вече има записана стойност; остави празно, за да я запазиш.');
        if ($help) echo '<p class="description">'.esc_html($help).'</p>';
    }
    private static function toggle($key, $label) {
        $s=self::get_settings(); echo '<label class="pcw-toggle"><input type="checkbox" name="'.self::OPTION.'['.esc_attr($key).']" value="1" '.checked($s[$key] ?? '0','1',false).'> '.esc_html($label).'</label>';
    }
    private static function card_start($title, $desc='') { echo '<section class="pcw-card"><h2>'.esc_html($title).'</h2>'; if($desc) echo '<p class="description">'.esc_html($desc).'</p>'; }

    public static function render() {
        if (!current_user_can('manage_options')) return;
        echo '<div class="wrap pcw-wrap"><div class="pcw-hero"><h1>⚙ PCWork – настройки и интеграции</h1><p>Централно място за свързване на сайта, резервациите, чата, магазина, Google Sheets и push известията.</p></div>';
        if (!class_exists('WooCommerce')) echo '<div class="notice notice-warning"><p>WooCommerce не е активен или не е открит. Настройките могат да бъдат въведени предварително.</p></div>';
        echo '<div class="pcw-note"><strong>Сигурност:</strong> тайните се записват в базата данни на WordPress и са достъпни през администраторския екран. Използвай HTTPS, ограничен администраторски достъп и резервни копия. За production препоръчваме секретите да се преместят в wp-config.php или защитена среда. Празно поле запазва текущата стойност.</div>'; 
        echo '<form method="post" action="options.php">'; settings_fields(self::GROUP); echo '<div class="pcw-grid">';
        self::card_start('Основни настройки','Адрес и среда на приложението.');
        self::field('site_url','WordPress сайт','url');
        echo '<label for="app_environment">Среда</label><select id="app_environment" name="'.self::OPTION.'[app_environment]"><option value="staging" '.selected(self::get_settings()['app_environment'],'staging',false).'>Тестова (Staging)</option><option value="production" '.selected(self::get_settings()['app_environment'],'production',false).'>Работна (Production)</option></select>';
        self::field('support_email','Имейл за поддръжка','email'); self::field('support_phone','Телефон за поддръжка'); echo '</section>';

        self::card_start('WooCommerce','Продукти, услуги, поръчки и клиентски профили.'); self::toggle('woocommerce_enabled','Активирай интеграцията'); self::field('woocommerce_consumer_key','Consumer Key','password'); self::field('woocommerce_consumer_secret','Consumer Secret','password'); echo '<button type="button" class="button pcw-test" data-integration="woocommerce">Провери връзката</button><span class="pcw-result" id="pcw-result-woocommerce"></span>'; echo '</section>'; 
        self::card_start('Bookly','Резервиране на часове и графици.'); self::toggle('bookly_enabled','Активирай интеграцията'); self::field('bookly_api_url','API адрес / endpoint','url','https://...'); self::field('bookly_api_key','API ключ (само ако използваш отделен Bookly REST API add-on)','password'); self::field('bookly_booking_page_url','Страница за резервации в сайта','url','https://pcwork-bg.com/rezervirane/','Това е страницата, в която е поставена стандартната Bookly форма. Приложението ще я отваря в защитен WebView/браузър.'); self::field('bookly_shortcode','Bookly shortcode','text','[bookly-form]','Стандартен shortcode за Bookly. Не се изпълнява от приложението; служи за проверка/документация.'); echo '<button type="button" class="button pcw-test" data-integration="bookly">Провери Bookly</button><span class="pcw-result" id="pcw-result-bookly"></span>'; echo '</section>'; 
        self::card_start('Chatway Live Chat','Връзка към клиентския чат.'); self::toggle('chatway_enabled','Показвай Chatway в приложението'); self::field('chatway_widget_id','Widget ID'); echo '</section>';
        self::card_start('Chaty Pro','Бутони за бърз контакт.'); self::toggle('chaty_enabled','Активирай Chaty'); self::field('chaty_widget_id','Widget ID / идентификатор'); echo '</section>';
        self::card_start('ShopLentor Pro','WooCommerce изгледи и продуктови секции.'); self::toggle('shoplentor_enabled','Използвай ShopLentor съдържание'); echo '</section>';
        self::card_start('Google Sheets – ремонти','Синхронизация на ремонтите към частен Google Sheet чрез Apps Script webhook.'); self::toggle('sheets_enabled','Активирай синхронизацията'); self::field('sheets_webhook_url','Apps Script Web App URL','password'); self::field('sheets_webhook_secret','HMAC Secret','password'); echo '<button type="button" class="button pcw-test" data-integration="sheets">Провери връзката</button><span class="pcw-result" id="pcw-result-sheets"></span>'; echo '</section>'; 
        self::card_start('Push известия','Настройки за Firebase Cloud Messaging (FCM).'); self::toggle('push_enabled','Активирай push известията'); echo '<label for="push_provider">Доставчик</label><select id="push_provider" name="'.self::OPTION.'[push_provider]"><option value="firebase">Firebase Cloud Messaging</option></select>'; self::field('firebase_project_id','Firebase Project ID'); self::field('firebase_service_account_json','Service Account JSON','textarea','','Поставя се само в защитената администраторска среда. Не използвай клиентски Firebase ключ тук.'); self::field('firebase_test_device_token','Тестов FCM device token','password','','Въведи FCM registration token от тестово устройство, запази настройките и изпрати тестово известие.'); echo '<button type="button" class="button pcw-test" data-integration="firebase">Изпрати тестово известие</button><span class="pcw-result" id="pcw-result-firebase"></span>'; echo '</section>';
        self::card_start('Регистрация на устройства','Мобилното приложение трябва да изпраща FCM token след вход. Токенът се свързва с потребителския WordPress профил.'); echo '<p>REST endpoints: <code>POST /wp-json/pcwork/v1/push/register</code> и <code>POST /wp-json/pcwork/v1/push/unregister</code>. Приложението ги извиква с персонален Bearer токен след вход; endpoint-ите използват същата проверка като останалия мобилен API.</p><p><strong>Автоматични известия:</strong> ремонтният модул трябва да извика <code>do_action(\'pcwork_repair_status_changed\', $repair_id, $customer_user_id, $status, $repair_number);</code>. Налични шаблони: received, diagnostics, waiting_approval, in_repair, ready, completed, cancelled.</p></section>';
        echo '</div>'; submit_button('Запази настройките','primary large','submit',true,['class'=>'pcw-save']); echo '</form>';
        echo '<p class="description">Проверките в тази версия валидират WooCommerce REST API и достъпността на Google Sheets webhook. Bookly, Chatway, Chaty, ShopLentor и Firebase изискват допълнителни адаптери според активните им API и конфигурация.</p></div>'; 
    }


    public static function admin_script() {
        $screen = function_exists('get_current_screen') ? get_current_screen() : null;
        if (!$screen || strpos($screen->id, 'pcwork-integrations') === false) return;
        $nonce = wp_create_nonce('pcwork_test_integration');
        echo '<script>(function(){document.querySelectorAll(".pcw-test").forEach(function(btn){btn.addEventListener("click",function(){var type=btn.dataset.integration;var out=document.getElementById("pcw-result-"+type);btn.disabled=true;out.className="pcw-result";out.textContent="Проверка...";var data=new URLSearchParams();data.append("action","pcwork_test_integration");data.append("nonce","'.esc_js($nonce).'");data.append("integration",type);fetch(ajaxurl,{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded; charset=UTF-8"},body:data.toString(),credentials:"same-origin"}).then(function(r){return r.json()}).then(function(r){out.textContent=r.data&&r.data.message?r.data.message:"Няма подробности";out.className="pcw-result "+(r.success?"ok":"err")}).catch(function(){out.textContent="Грешка при заявката";out.className="pcw-result err"}).finally(function(){btn.disabled=false})})})})();</script>';
    }

    public static function ajax_test_integration() {
        if (!current_user_can('manage_options')) wp_send_json_error(['message'=>'Нямаш права за тази операция.'], 403);
        check_ajax_referer('pcwork_test_integration', 'nonce');
        $integration = sanitize_key($_POST['integration'] ?? '');
        $s = self::get_settings();
        if ($integration === 'woocommerce') {
            if (empty($s['woocommerce_consumer_key']) || empty($s['woocommerce_consumer_secret'])) wp_send_json_error(['message'=>'Въведи Consumer Key и Consumer Secret и запази настройките.']);
            $base = untrailingslashit($s['site_url']);
            if (strtolower((string) wp_parse_url($base, PHP_URL_HOST)) !== strtolower((string) wp_parse_url(home_url(), PHP_URL_HOST))) wp_send_json_error(['message'=>'Адресът на сайта трябва да съвпада с домейна на този WordPress.']);
            if (stripos($base, 'https://') !== 0) wp_send_json_error(['message'=>'WooCommerce ключовете се изпращат само през HTTPS.']);
            $url = $base . '/wp-json/wc/v3/products?per_page=1';
            $response = wp_remote_get($url, ['timeout'=>15, 'redirection'=>0, 'headers'=>['Authorization'=>'Basic '.base64_encode($s['woocommerce_consumer_key'].':'.$s['woocommerce_consumer_secret']), 'Accept'=>'application/json']]);
            if (is_wp_error($response)) wp_send_json_error(['message'=>'Грешка: '.$response->get_error_message()]);
            $code = wp_remote_retrieve_response_code($response);
            if ($code >= 200 && $code < 300) wp_send_json_success(['message'=>'Успешна връзка с WooCommerce REST API. HTTP '.$code]);
            wp_send_json_error(['message'=>'WooCommerce върна HTTP '.$code.'. Провери ключовете и REST API правата.']);
        }
        if ($integration === 'bookly') {
            if (($s['bookly_enabled'] ?? '0') !== '1') wp_send_json_error(['message'=>'Bookly интеграцията е изключена.']);
            if (!class_exists('Bookly\Lib\Plugin') && !defined('BOOKLY_VERSION') && !shortcode_exists('bookly-form')) wp_send_json_error(['message'=>'Bookly не е открит. Инсталирай/активирай Bookly и провери shortcode [bookly-form].']);
            if (empty($s['bookly_booking_page_url'])) wp_send_json_error(['message'=>'Bookly е открит. Въведи URL на страницата за резервации и запази настройките.']);
            $url = esc_url_raw($s['bookly_booking_page_url']);
            if (stripos($url, 'https://') !== 0 || strtolower((string)wp_parse_url($url, PHP_URL_HOST)) !== strtolower((string)wp_parse_url(home_url(), PHP_URL_HOST))) wp_send_json_error(['message'=>'Страницата за резервации трябва да е HTTPS и на същия домейн.']);
            $response = wp_remote_get($url, ['timeout'=>15, 'redirection'=>3, 'headers'=>['Accept'=>'text/html']]);
            if (is_wp_error($response)) wp_send_json_error(['message'=>'Bookly е открит, но страницата не се зареди: '.$response->get_error_message()]);
            $code = wp_remote_retrieve_response_code($response);
            if ($code >= 200 && $code < 300) wp_send_json_success(['message'=>'Bookly е открит и страницата за резервации отговаря. HTTP '.$code.'.']);
            wp_send_json_error(['message'=>'Страницата за резервации върна HTTP '.$code.'.']);
        }
        if ($integration === 'firebase') {
            if (($s['push_enabled'] ?? '0') !== '1') wp_send_json_error(['message'=>'Push известията са изключени.']);
            if (empty($s['firebase_project_id']) || empty($s['firebase_service_account_json']) || empty($s['firebase_test_device_token'])) wp_send_json_error(['message'=>'Попълни Project ID, Service Account JSON и тестов device token, след което запази.']);
            $result = self::send_fcm_message($s['firebase_test_device_token'], 'PCWork – тест', 'Push известията са конфигурирани успешно.');
            if (is_wp_error($result)) wp_send_json_error(['message'=>'FCM грешка: '.$result->get_error_message()]);
            wp_send_json_success(['message'=>'Тестовото известие е прието от Firebase.']);
        }
        if ($integration === 'sheets') {
            if (empty($s['sheets_webhook_url']) || empty($s['sheets_webhook_secret'])) wp_send_json_error(['message'=>'Въведи Webhook URL и HMAC Secret и запази настройките.']);
            if (stripos($s['sheets_webhook_url'], 'https://') !== 0) wp_send_json_error(['message'=>'Webhook адресът трябва да използва HTTPS.']);
            $timestamp = (string) time();
            $payload = wp_json_encode(['event'=>'pcwork.integration.ping','timestamp'=>(int)$timestamp,'sent_at'=>gmdate('c')]);
            $signature = hash_hmac('sha256', $timestamp.'.'.$payload, $s['sheets_webhook_secret']);
            $url = add_query_arg(['ts'=>$timestamp,'sig'=>$signature], $s['sheets_webhook_url']);
            $response = wp_remote_post($url, ['timeout'=>20,'headers'=>['Content-Type'=>'application/json'],'body'=>$payload]);
            if (is_wp_error($response)) wp_send_json_error(['message'=>'Грешка: '.$response->get_error_message()]);
            $code = wp_remote_retrieve_response_code($response);
            if ($code >= 200 && $code < 300) wp_send_json_success(['message'=>'Webhook отговори успешно. HTTP '.$code.' (провери Apps Script логовете за потвърждение).']);
            wp_send_json_error(['message'=>'Webhook върна HTTP '.$code.'. Провери URL, достъпа и Apps Script deployment-а.']);
        }
        wp_send_json_error(['message'=>'Няма тест за тази интеграция в текущата версия.']);
    }

    public static function rest_routes() {
        register_rest_route('pcwork/v1','/admin/integrations/status',[ 'methods'=>'GET', 'permission_callback'=>function(){ return current_user_can('manage_options'); }, 'callback'=>[__CLASS__,'status'] ]);
        register_rest_route('pcwork/v1','/booking/config',[ 'methods'=>'GET', 'permission_callback'=>'__return_true', 'callback'=>[__CLASS__,'booking_config'] ]);
        register_rest_route('pcwork/v1','/push/register',[ 'methods'=>'POST', 'permission_callback'=>['PCWork_Mobile_Auth_Bridge','authorize'], 'callback'=>[__CLASS__,'register_device'] ]);
        register_rest_route('pcwork/v1','/push/unregister',[ 'methods'=>'POST', 'permission_callback'=>['PCWork_Mobile_Auth_Bridge','authorize'], 'callback'=>[__CLASS__,'unregister_device'] ]);
    }
    public static function booking_config() {
        $s=self::get_settings();
        if (($s['bookly_enabled'] ?? '0') !== '1' || empty($s['bookly_booking_page_url'])) return new WP_REST_Response(['enabled'=>false], 200);
        $url=esc_url_raw($s['bookly_booking_page_url']);
        if (stripos($url,'https://') !== 0 || strtolower((string)wp_parse_url($url,PHP_URL_HOST)) !== strtolower((string)wp_parse_url(home_url(),PHP_URL_HOST))) return new WP_REST_Response(['enabled'=>false], 200);
        return rest_ensure_response(['enabled'=>true,'provider'=>'bookly','booking_url'=>$url,'display_mode'=>'webview']);
    }


    public static function register_device(WP_REST_Request $request) {
        $token = sanitize_text_field((string)$request->get_param('token'));
        $platform = sanitize_key((string)$request->get_param('platform'));
        if (strlen($token) < 40 || strlen($token) > 4096) return new WP_Error('pcwork_invalid_token','Невалиден FCM token.',['status'=>400]);
        if (!in_array($platform,['android','ios'],true)) return new WP_Error('pcwork_invalid_platform','platform трябва да е android или ios.',['status'=>400]);
        $user_id=get_current_user_id(); $tokens=get_user_meta($user_id,'pcwork_fcm_devices',true); if(!is_array($tokens)) $tokens=[];
        $tokens[$token]=['platform'=>$platform,'updated_at'=>time()];
        if(count($tokens)>10) $tokens=array_slice($tokens,-10,null,true);
        update_user_meta($user_id,'pcwork_fcm_devices',$tokens);
        return rest_ensure_response(['registered'=>true]);
    }
    public static function unregister_device(WP_REST_Request $request) {
        $token=sanitize_text_field((string)$request->get_param('token')); if (strlen($token) < 40 || strlen($token) > 4096) return new WP_Error('pcwork_invalid_token','Невалиден FCM token.',['status'=>400]); $user_id=get_current_user_id(); $tokens=get_user_meta($user_id,'pcwork_fcm_devices',true);
        if(is_array($tokens) && isset($tokens[$token])) { unset($tokens[$token]); update_user_meta($user_id,'pcwork_fcm_devices',$tokens); }
        return rest_ensure_response(['unregistered'=>true]);
    }
    private static function firebase_access_token($settings) {
        $cached=get_transient('pcwork_fcm_access_token'); if(is_array($cached) && !empty($cached['token'])) return $cached['token'];
        $account=json_decode($settings['firebase_service_account_json'] ?? '',true);
        if(!is_array($account) || empty($account['client_email']) || empty($account['private_key']) || empty($account['token_uri'])) return new WP_Error('pcwork_firebase_config','Service Account JSON е невалиден или липсват client_email/private_key/token_uri.');
        if(!empty($account['project_id']) && !hash_equals((string)$settings['firebase_project_id'], (string)$account['project_id'])) return new WP_Error('pcwork_firebase_project','Project ID не съвпада с project_id в Service Account JSON.');
        $now=time(); $b64=function($v){ return rtrim(strtr(base64_encode($v),'+/','-_'),'='); };
        $header=$b64(wp_json_encode(['alg'=>'RS256','typ'=>'JWT']));
        $claims=$b64(wp_json_encode(['iss'=>$account['client_email'],'scope'=>'https://www.googleapis.com/auth/firebase.messaging','aud'=>$account['token_uri'],'iat'=>$now,'exp'=>$now+3600]));
        $unsigned=$header.'.'.$claims; $signature='';
        if(!openssl_sign($unsigned,$signature,$account['private_key'],OPENSSL_ALGO_SHA256)) return new WP_Error('pcwork_firebase_sign','Неуспешно подписване на Firebase JWT.');
        $jwt=$unsigned.'.'.$b64($signature);
        $response=wp_remote_post($account['token_uri'],['timeout'=>20,'headers'=>['Content-Type'=>'application/x-www-form-urlencoded'],'body'=>['grant_type'=>'urn:ietf:params:oauth:grant-type:jwt-bearer','assertion'=>$jwt]]);
        if(is_wp_error($response)) return $response;
        $body=json_decode(wp_remote_retrieve_body($response),true); if(empty($body['access_token'])) return new WP_Error('pcwork_firebase_oauth','Google OAuth не върна access token. HTTP '.wp_remote_retrieve_response_code($response));
        set_transient('pcwork_fcm_access_token',['token'=>$body['access_token']],max(60,(int)($body['expires_in']??3600)-120)); return $body['access_token'];
    }
    private static function send_fcm_message($device_token,$title,$body,$data=[]) {
        $s=self::get_settings(); $access=self::firebase_access_token($s); if(is_wp_error($access)) return $access;
        $url='https://fcm.googleapis.com/v1/projects/'.rawurlencode($s['firebase_project_id']).'/messages:send';
        $safe_data=['source'=>'pcwork']; foreach((array)$data as $key=>$value){ $key=sanitize_key((string)$key); if($key!=='') $safe_data[$key]=substr(sanitize_text_field((string)$value),0,500); }
        $payload=['message'=>['token'=>$device_token,'notification'=>['title'=>$title,'body'=>$body],'data'=>$safe_data]];
        $response=wp_remote_post($url,['timeout'=>20,'headers'=>['Authorization'=>'Bearer '.$access,'Content-Type'=>'application/json'],'body'=>wp_json_encode($payload)]);
        if(is_wp_error($response)) return $response; $code=wp_remote_retrieve_response_code($response);
        if($code<200 || $code>=300) return new WP_Error('pcwork_fcm_send','FCM върна HTTP '.$code.': '.wp_strip_all_tags(wp_remote_retrieve_body($response)));
        return true;
    }

    /**
     * Called by the repair-management module when a repair status changes.
     * Hook contract: do_action('pcwork_repair_status_changed', $repair_id, $customer_user_id, $status, $repair_number).
     */
    public static function on_repair_status_changed($repair_id, $customer_user_id, $status, $repair_number='') {
        $s=self::get_settings();
        if (($s['push_enabled'] ?? '0') !== '1' || empty($s['firebase_project_id']) || empty($s['firebase_service_account_json'])) return;
        $repair_id=absint($repair_id); $customer_user_id=absint($customer_user_id);
        $status=sanitize_key((string)$status); $repair_number=sanitize_text_field((string)$repair_number);
        if (!$repair_id || !$customer_user_id || !$status) return;
        // Prevent duplicate notifications if a status-save hook fires more than once.
        $dedupe='pcw_push_'.md5($repair_id.'|'.$customer_user_id.'|'.$status);
        if (get_transient($dedupe)) return;
        $messages=[
            'received'=>['Ремонтът е приет','Получихме устройството ви и създадохме сервизна поръчка.'],
            'diagnostics'=>['Започна диагностиката','Започнахме диагностиката на вашето устройство.'],
            'waiting_approval'=>['Необходимо е одобрение','Очакваме вашето одобрение за предложен ремонт.'],
            'in_repair'=>['Устройството е в ремонт','Работим по ремонта на вашето устройство.'],
            'ready'=>['Устройството е готово','Ремонтът е приключен. Можете да се свържете със сервиза за получаване.'],
            'completed'=>['Ремонтът е приключен','Устройството е предадено. Благодарим ви!'],
            'cancelled'=>['Ремонтът е отменен','Статусът на сервизната поръчка е променен на отменен.'],
        ];
        if (!isset($messages[$status])) return;
        $title=$messages[$status][0]; $body=$messages[$status][1];
        if ($repair_number !== '') $body .= ' № '.$repair_number.'.';
        $devices=get_user_meta($customer_user_id,'pcwork_fcm_devices',true);
        if (!is_array($devices) || !$devices) return;
        $sent=0; $invalid=[];
        foreach($devices as $token=>$meta) {
            $result=self::send_fcm_message($token,$title,$body,[
                'event'=>'repair_status_changed','repair_id'=>$repair_id,'repair_number'=>$repair_number,'status'=>$status
            ]);
            if (is_wp_error($result)) {
                // Remove tokens rejected as unregistered/invalid by FCM.
                if (strpos($result->get_error_message(),'HTTP 404')!==false || strpos($result->get_error_message(),'UNREGISTERED')!==false) $invalid[]=$token;
            } else $sent++;
        }
        foreach($invalid as $token) unset($devices[$token]);
        if ($invalid) update_user_meta($customer_user_id,'pcwork_fcm_devices',$devices);
        if ($sent > 0) {
            set_transient($dedupe,1,10 * MINUTE_IN_SECONDS);
            update_user_meta($customer_user_id,'pcwork_last_repair_push',[
                'repair_id'=>$repair_id,'status'=>$status,'sent'=>$sent,'sent_at'=>current_time('mysql',true)
            ]);
        }
    }

    public static function status() {
        $s=self::get_settings(); $keys=['woocommerce_enabled','bookly_enabled','chatway_enabled','chaty_enabled','shoplentor_enabled','sheets_enabled','push_enabled']; $out=[];
        foreach($keys as $k) $out[$k]=($s[$k]??'0')==='1';
        $out['configured']=['woocommerce'=>!empty($s['woocommerce_consumer_key'])&&!empty($s['woocommerce_consumer_secret']),'bookly'=>!empty($s['bookly_booking_page_url']),'chatway'=>!empty($s['chatway_widget_id']),'chaty'=>!empty($s['chaty_widget_id']),'sheets'=>!empty($s['sheets_webhook_url'])&&!empty($s['sheets_webhook_secret']),'firebase'=>!empty($s['firebase_project_id'])&&!empty($s['firebase_service_account_json'])];
        return rest_ensure_response($out);
    }
}
PCWork_Admin_Integration_Settings::init();
