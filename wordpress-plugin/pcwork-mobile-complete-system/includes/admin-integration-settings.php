<?php
if (!defined('ABSPATH')) exit;

final class PCWork_Admin_Integration_Settings {
    const OPTION = 'pcwork_mobile_integrations';
    const GROUP = 'pcwork_mobile_integrations_group';

    public static function init() {
        add_action('admin_menu', [__CLASS__, 'menu'], 99);
        add_action('admin_init', [__CLASS__, 'register']);
        add_action('admin_init', [__CLASS__, 'maybe_encrypt_legacy_sheets_secret'], 20);
        add_action('admin_enqueue_scripts', [__CLASS__, 'styles']);
        add_action('admin_footer', [__CLASS__, 'admin_script']);
        add_action('rest_api_init', [__CLASS__, 'rest_routes']);
        add_action('template_redirect', [__CLASS__, 'render_mobile_chat_page'], 0);
        add_action('wp_ajax_pcwork_test_integration', [__CLASS__, 'ajax_test_integration']);
        // Repair module should fire this action whenever a repair status changes.
        add_action('pcwork_repair_status_changed', [__CLASS__, 'on_repair_status_changed'], 10, 4);
    }

    public static function defaults() {
        return [
            'site_url' => home_url(),
            'woocommerce_enabled' => '1', 'woocommerce_consumer_key' => '', 'woocommerce_consumer_secret' => '',
            'bookly_enabled' => '1', 'bookly_api_url' => '', 'bookly_api_key' => '', 'bookly_booking_page_url' => '', 'bookly_shortcode' => '[bookly-form]',
            'chatway_enabled' => '1', 'chatway_widget_id' => '', 'chatway_installation_id' => '', 'chatway_verification_enabled' => '0', 'chatway_verification_secret' => '', 'chatway_verification_identifier' => 'id',
            'chaty_enabled' => '1', 'chaty_widget_id' => '',
            'shoplentor_enabled' => '1',
            'sheets_enabled' => '0', 'sheets_webhook_url' => '', 'sheets_webhook_secret' => '',
            'push_enabled' => '0', 'push_provider' => 'firebase', 'firebase_project_id' => '', 'firebase_service_account_json' => '', 'firebase_test_device_token' => '',
            'app_environment' => 'staging', 'support_email' => get_option('admin_email'), 'support_phone' => '',
        ];
    }

    public static function get_settings() {
        $settings = wp_parse_args(get_option(self::OPTION, []), self::defaults());
        if (!empty($settings['sheets_webhook_secret'])) {
            $settings['sheets_webhook_secret'] = self::decrypt_sheets_secret((string)$settings['sheets_webhook_secret']);
        }
        return $settings;
    }

    /** Encrypt the Sheets HMAC secret at rest using the site's WordPress salts. */
    private static function sheets_secret_key() {
        $material = (function_exists('wp_salt') ? wp_salt('auth') . '|' . wp_salt('secure_auth') : AUTH_KEY . '|' . SECURE_AUTH_KEY);
        return hash('sha256', $material . '|PCWork Google Sheets HMAC v1', true);
    }

    private static function encrypt_sheets_secret($secret) {
        $secret = (string)$secret;
        if ($secret === '' || strpos($secret, 'pcwenc:v1:') === 0 || !function_exists('openssl_encrypt')) return $secret;
        try { $iv = random_bytes(12); } catch (Throwable $e) { return $secret; }
        $tag = '';
        $cipher = openssl_encrypt($secret, 'aes-256-gcm', self::sheets_secret_key(), OPENSSL_RAW_DATA, $iv, $tag, 'pcwork-sheets-secret-v1', 16);
        if ($cipher === false || strlen($tag) !== 16) return $secret;
        return 'pcwenc:v1:' . base64_encode($iv . $tag . $cipher);
    }

    private static function decrypt_sheets_secret($stored) {
        if (strpos($stored, 'pcwenc:v1:') !== 0) return $stored; // legacy plaintext; migrated by admin_init.
        if (!function_exists('openssl_decrypt')) return '';
        $raw = base64_decode(substr($stored, 10), true);
        if ($raw === false || strlen($raw) < 29) return '';
        $iv = substr($raw, 0, 12);
        $tag = substr($raw, 12, 16);
        $cipher = substr($raw, 28);
        $plain = openssl_decrypt($cipher, 'aes-256-gcm', self::sheets_secret_key(), OPENSSL_RAW_DATA, $iv, $tag, 'pcwork-sheets-secret-v1');
        return is_string($plain) ? $plain : '';
    }

    public static function maybe_encrypt_legacy_sheets_secret() {
        if (!current_user_can('manage_options') || !function_exists('openssl_encrypt')) return;
        $stored = get_option(self::OPTION, []);
        if (!is_array($stored) || empty($stored['sheets_webhook_secret'])) return;
        if (strpos((string)$stored['sheets_webhook_secret'], 'pcwenc:v1:') === 0) return;
        $encrypted = self::encrypt_sheets_secret((string)$stored['sheets_webhook_secret']);
        if (strpos($encrypted, 'pcwenc:v1:') === 0) {
            $stored['sheets_webhook_secret'] = $encrypted;
            update_option(self::OPTION, $stored, false);
        }
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
        $checkboxes = ['woocommerce_enabled','bookly_enabled','chatway_enabled','chatway_verification_enabled','chaty_enabled','shoplentor_enabled','sheets_enabled','push_enabled'];
        foreach ($checkboxes as $key) $out[$key] = !empty($input[$key]) ? '1' : '0';
        $text = ['site_url','bookly_api_url','bookly_booking_page_url','bookly_shortcode','chatway_widget_id','chatway_installation_id','chaty_widget_id','firebase_project_id','firebase_test_device_token','support_email','support_phone'];
        foreach ($text as $key) {
            $value = isset($input[$key]) ? wp_unslash($input[$key]) : '';
            $out[$key] = $key === 'support_email' ? sanitize_email($value) : ($key === 'site_url' || $key === 'bookly_api_url' ? esc_url_raw($value) : sanitize_text_field($value));
        }
        $secrets = ['woocommerce_consumer_key','woocommerce_consumer_secret','bookly_api_key','sheets_webhook_url','sheets_webhook_secret','firebase_service_account_json','chatway_verification_secret'];
        foreach ($secrets as $key) {
            $value = isset($input[$key]) ? trim(wp_unslash($input[$key])) : '';
            // Празно поле означава запазване на вече записаната тайна.
            $out[$key] = $value !== '' ? sanitize_textarea_field($value) : ($old[$key] ?? '');
        }
        // Only the Google Sheets HMAC secret is encrypted at rest.
        $out['sheets_webhook_secret'] = self::encrypt_sheets_secret($out['sheets_webhook_secret']);
        $out['chatway_verification_identifier'] = in_array(($input['chatway_verification_identifier'] ?? 'id'), ['id','email'], true) ? $input['chatway_verification_identifier'] : 'id';
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
        echo '<div class="pcw-note"><strong>Сигурност:</strong> Google Sheets HMAC Secret се съхранява криптирано в базата данни чрез AES-256-GCM и WordPress salts (когато OpenSSL е наличен). Пази wp-config.php и не сменяй AUTH_KEY/SECURE_AUTH_KEY без предварително да запазиш HMAC Secret. Използвай HTTPS, ограничен администраторски достъп и резервни копия. Празно поле запазва текущата стойност.</div>'; 
        echo '<form method="post" action="options.php">'; settings_fields(self::GROUP); echo '<div class="pcw-grid">';
        self::card_start('Основни настройки','Адрес и среда на приложението.');
        self::field('site_url','WordPress сайт','url');
        echo '<label for="app_environment">Среда</label><select id="app_environment" name="'.self::OPTION.'[app_environment]"><option value="staging" '.selected(self::get_settings()['app_environment'],'staging',false).'>Тестова (Staging)</option><option value="production" '.selected(self::get_settings()['app_environment'],'production',false).'>Работна (Production)</option></select>';
        self::field('support_email','Имейл за поддръжка','email'); self::field('support_phone','Телефон за поддръжка'); echo '</section>';

        self::card_start('WooCommerce','Продукти, услуги, поръчки и клиентски профили.'); self::toggle('woocommerce_enabled','Активирай интеграцията'); self::field('woocommerce_consumer_key','Consumer Key (по избор за външен REST API)','password'); self::field('woocommerce_consumer_secret','Consumer Secret (по избор за външен REST API)','password'); echo '<p class="description">Мобилният магазин v32 използва защитения сървърен WooCommerce API и не изисква Consumer Key/Secret в приложението. Ключовете са нужни само за външни REST API интеграции и допълнителния тест.</p>';  echo '<button type="button" class="button pcw-test" data-integration="woocommerce">Провери връзката</button><span class="pcw-result" id="pcw-result-woocommerce"></span>'; echo '</section>'; 
        self::card_start('Bookly','Резервиране на часове и графици.'); self::toggle('bookly_enabled','Активирай интеграцията'); self::field('bookly_api_url','API адрес / endpoint','url','https://...'); self::field('bookly_api_key','API ключ (само ако използваш отделен Bookly REST API add-on)','password'); self::field('bookly_booking_page_url','Страница за резервации в сайта','url','https://pcwork-bg.com/rezervirane/','Това е страницата, в която е поставена стандартната Bookly форма. Приложението ще я отваря в защитен WebView/браузър.'); self::field('bookly_shortcode','Bookly shortcode','text','[bookly-form]','Стандартен shortcode за Bookly. Не се изпълнява от приложението; служи за проверка/документация.'); echo '<button type="button" class="button pcw-test" data-integration="bookly">Провери Bookly</button><span class="pcw-result" id="pcw-result-bookly"></span>'; echo '</section>'; 
        self::card_start('Chatway Live Chat','Вграден клиентски чат с опционална сигурна идентификация на влезлите клиенти.'); self::toggle('chatway_enabled','Показвай Chatway в приложението'); self::field('chatway_installation_id','Chatway Installation ID','text','например AbCdEf123456','Вземи ID от кода за инсталиране. Въведи само стойността след id=, не API ключ.'); self::toggle('chatway_verification_enabled','Включи Visitor Verification за влезли клиенти'); echo '<label for="chatway_verification_identifier">Идентификатор за проверка</label><select id="chatway_verification_identifier" name="'.self::OPTION.'[chatway_verification_identifier]"><option value="id" '.selected(self::get_settings()['chatway_verification_identifier'],'id',false).'>WordPress User ID (препоръчително)</option><option value="email" '.selected(self::get_settings()['chatway_verification_identifier'],'email',false).'>Имейл адрес</option></select>'; self::field('chatway_verification_secret','Chatway Visitor Verification Security Key','password','','Копирай ключа от Chatway → Settings → Visitors Verification. Ключът остава само на сървъра и никога не се изпраща към приложението.'); self::field('chatway_widget_id','Widget ID (за бъдеща API синхронизация)'); echo '<button type="button" class="button pcw-test" data-integration="chatway">Провери настройката</button><span class="pcw-result" id="pcw-result-chatway"></span>'; echo '</section>';
        self::card_start('Chaty Pro','Бутони за бърз контакт.'); self::toggle('chaty_enabled','Активирай Chaty'); self::field('chaty_widget_id','Widget ID / идентификатор'); echo '</section>';
        self::card_start('ShopLentor Pro','WooCommerce изгледи и продуктови секции.'); self::toggle('shoplentor_enabled','Използвай ShopLentor съдържание'); echo '</section>';
        self::card_start('Google Sheets – ремонти','Синхронизация на ремонтите към частен Google Sheet чрез Apps Script webhook.'); self::toggle('sheets_enabled','Активирай синхронизацията'); self::field('sheets_webhook_url','Apps Script Web App URL','password'); self::field('sheets_webhook_secret','HMAC Secret','password'); echo '<button type="button" class="button pcw-test" data-integration="sheets">Провери връзката</button><span class="pcw-result" id="pcw-result-sheets"></span>'; echo '</section>'; 
        self::card_start('Push известия','Настройки за Firebase Cloud Messaging (FCM).'); self::toggle('push_enabled','Активирай push известията'); echo '<label for="push_provider">Доставчик</label><select id="push_provider" name="'.self::OPTION.'[push_provider]"><option value="firebase">Firebase Cloud Messaging</option></select>'; self::field('firebase_project_id','Firebase Project ID'); self::field('firebase_service_account_json','Service Account JSON','textarea','','Поставя се само в защитената администраторска среда. Не използвай клиентски Firebase ключ тук.'); self::field('firebase_test_device_token','Тестов FCM device token','password','','Въведи FCM registration token от тестово устройство, запази настройките и изпрати тестово известие.'); echo '<button type="button" class="button pcw-test" data-integration="firebase">Изпрати тестово известие</button><span class="pcw-result" id="pcw-result-firebase"></span>'; echo '</section>';
        self::card_start('Регистрация на устройства','Мобилното приложение трябва да изпраща FCM token след вход. Токенът се свързва с потребителския WordPress профил.'); echo '<p>REST endpoints: <code>POST /wp-json/pcwork/v1/push/register</code> и <code>POST /wp-json/pcwork/v1/push/unregister</code>. Приложението ги извиква с персонален Bearer токен след вход; endpoint-ите използват същата проверка като останалия мобилен API.</p><p><strong>Автоматични известия:</strong> ремонтният модул трябва да извика <code>do_action(\'pcwork_repair_status_changed\', $repair_id, $customer_user_id, $status, $repair_number);</code>. Налични шаблони: received, diagnostics, waiting_approval, in_repair, ready, completed, cancelled.</p></section>';
        echo '</div>'; submit_button('Запази настройките','primary large','submit',true,['class'=>'pcw-save']); echo '</form>';
        echo '<p class="description">Chatway е вградено в приложението чрез официалния widget и защитена HTTPS WebView страница. WooCommerce и Google Sheets имат отделни проверки; Bookly, Chaty, ShopLentor и Firebase използват съответните си конфигурации и адаптери.</p></div>'; 
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
            if (($s['woocommerce_enabled'] ?? '0') !== '1') wp_send_json_error(['message'=>'WooCommerce интеграцията е изключена.']);
            if (!class_exists('WooCommerce') || !function_exists('wc_get_products')) wp_send_json_error(['message'=>'WooCommerce не е инсталиран или активен.']);
            if (empty($s['woocommerce_consumer_key']) || empty($s['woocommerce_consumer_secret'])) wp_send_json_success(['message'=>'WooCommerce е активен. Сървърният мобилен магазин е готов; Consumer Key/Secret не са необходими за v32.']);
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
        if ($integration === 'chatway') {
            if (($s['chatway_enabled'] ?? '0') !== '1') wp_send_json_error(['message'=>'Chatway интеграцията е изключена.']);
            $id = sanitize_text_field((string)($s['chatway_installation_id'] ?? ''));
            if (!preg_match('/^[A-Za-z0-9_-]{6,100}$/', $id)) wp_send_json_error(['message'=>'Въведи валиден Installation ID и запази настройките.']);
            $verification = !empty($s['chatway_verification_enabled']) && !empty($s['chatway_verification_secret']);
            wp_send_json_success(['message'=>'Installation ID е с коректен формат.'.($verification ? ' Visitor Verification е конфигуриран със сървърен ключ.' : ' Чатът ще работи без свързване на историята с профила, докато не включиш Visitor Verification.')]);
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
            $payload = wp_json_encode(['event'=>'pcwork.integration.ping','timestamp'=>time(),'sent_at'=>gmdate('c')]);
            $response = PCWork_Google_Sheets_Sync::post_json(
                $s['sheets_webhook_url'],
                $payload,
                $s['sheets_webhook_secret']
            );
            if (is_wp_error($response)) {
                wp_send_json_error(['message' => 'Грешка при Google Sheets заявката: ' . $response->get_error_message()]);
            }
            $code = (int) wp_remote_retrieve_response_code($response);
            $raw_body = (string) wp_remote_retrieve_body($response);
            $decoded = json_decode($raw_body, true);
            if ($code >= 200 && $code < 300 && is_array($decoded) && !empty($decoded['ok'])) {
                wp_send_json_success(['message' => 'Google Apps Script потвърди връзката. HTTP ' . $code . '.']);
            }
            if ($code >= 200 && $code < 300 && is_array($decoded) && array_key_exists('ok', $decoded) && !$decoded['ok']) {
                $reason = sanitize_text_field((string)($decoded['error'] ?? 'unknown_error'));
                wp_send_json_error(['message' => 'Apps Script получи заявката, но я отхвърли: ' . $reason . '. Провери HMAC Secret, часа на сървъра и Script Properties.']);
            }
            $body_excerpt = trim(wp_strip_all_tags($raw_body));
            if (function_exists('mb_substr')) $body_excerpt = mb_substr($body_excerpt, 0, 500); else $body_excerpt = substr($body_excerpt, 0, 500);
            wp_send_json_error(['message' => 'Webhook върна HTTP ' . $code . '. Отговор: ' . ($body_excerpt !== '' ? $body_excerpt : '[празно тяло]')]);
        }
        wp_send_json_error(['message'=>'Няма тест за тази интеграция в текущата версия.']);
    }

    public static function rest_routes() {
        register_rest_route('pcwork/v1','/admin/integrations/status',[ 'methods'=>'GET', 'permission_callback'=>function(){ return current_user_can('manage_options'); }, 'callback'=>[__CLASS__,'status'] ]);
        register_rest_route('pcwork/v1','/booking/config',[ 'methods'=>'GET', 'permission_callback'=>'__return_true', 'callback'=>[__CLASS__,'booking_config'] ]);
        register_rest_route('pcwork/v1','/chatway/config',[ 'methods'=>'GET', 'permission_callback'=>'__return_true', 'callback'=>[__CLASS__,'chatway_config'] ]);
        register_rest_route('pcwork/v1','/chatway/session',[ 'methods'=>'POST', 'permission_callback'=>['PCWork_Mobile_Auth_Bridge','authorize'], 'callback'=>[__CLASS__,'chatway_session'] ]);
        register_rest_route('pcwork/v1','/push/register',[ 'methods'=>'POST', 'permission_callback'=>['PCWork_Mobile_Auth_Bridge','authorize'], 'callback'=>[__CLASS__,'register_device'] ]);
        register_rest_route('pcwork/v1','/push/unregister',[ 'methods'=>'POST', 'permission_callback'=>['PCWork_Mobile_Auth_Bridge','authorize'], 'callback'=>[__CLASS__,'unregister_device'] ]);
    }

    public static function chatway_config() {
        $s = self::get_settings();
        $installation_id = sanitize_text_field((string)($s['chatway_installation_id'] ?? ''));
        if (($s['chatway_enabled'] ?? '0') !== '1' || !preg_match('/^[A-Za-z0-9_-]{6,100}$/', $installation_id)) {
            return rest_ensure_response(['enabled' => false, 'provider' => 'chatway']);
        }
        return rest_ensure_response(['enabled' => true, 'provider' => 'chatway', 'chat_url' => add_query_arg('pcwork_mobile_chat', '1', home_url('/'))]);
    }

    /** Creates a short-lived, single-use launch ticket; the app never receives the Chatway verification secret. */
    public static function chatway_session(WP_REST_Request $request) {
        $s = self::get_settings();
        $installation_id = sanitize_text_field((string)($s['chatway_installation_id'] ?? ''));
        if (($s['chatway_enabled'] ?? '0') !== '1' || !preg_match('/^[A-Za-z0-9_-]{6,100}$/', $installation_id)) {
            return new WP_Error('pcwork_chatway_disabled', 'Chatway не е конфигуриран.', ['status'=>503]);
        }
        $user_id = get_current_user_id();
        if (!$user_id || !get_user_by('id', $user_id)) return new WP_Error('pcwork_chatway_auth', 'Необходим е активен клиентски профил.', ['status'=>401]);
        try { $ticket = bin2hex(random_bytes(32)); }
        catch (Exception $e) { return new WP_Error('pcwork_chatway_ticket', 'Неуспешно създаване на защитена чат сесия.', ['status'=>500]); }
        set_transient('pcw_chatway_launch_' . hash('sha256', $ticket), ['user_id'=>(int)$user_id, 'created'=>time()], 180);
        return rest_ensure_response(['enabled'=>true, 'provider'=>'chatway', 'chat_url'=>add_query_arg(['pcwork_mobile_chat'=>'1','pcw_chat_ticket'=>$ticket], home_url('/')), 'expires_in'=>180]);
    }

    /** Dedicated Chatway page. A one-time ticket binds the WebView to the authenticated WordPress user. */
    public static function render_mobile_chat_page() {
        if (!isset($_GET['pcwork_mobile_chat'])) return;
        $s = self::get_settings();
        $installation_id = sanitize_text_field((string)($s['chatway_installation_id'] ?? ''));
        $user_id = 0;
        $ticket = isset($_GET['pcw_chat_ticket']) ? sanitize_text_field(wp_unslash($_GET['pcw_chat_ticket'])) : '';
        if ($ticket !== '' && preg_match('/^[a-f0-9]{64}$/', $ticket)) {
            $transient_key = 'pcw_chatway_launch_' . hash('sha256', $ticket);
            $launch = get_transient($transient_key);
            delete_transient($transient_key);
            if (is_array($launch) && !empty($launch['user_id']) && (time() - (int)($launch['created'] ?? 0)) <= 180) {
                $candidate = (int)$launch['user_id'];
                if (get_user_by('id', $candidate)) $user_id = $candidate;
            }
        }
        $valid = ($s['chatway_enabled'] ?? '0') === '1' && preg_match('/^[A-Za-z0-9_-]{6,100}$/', $installation_id);
        if (!$valid || ($ticket !== '' && !$user_id)) {
            status_header($valid ? 403 : 503);
            nocache_headers();
            header('Content-Type: text/html; charset=utf-8');
            echo '<!doctype html><html lang="bg"><meta name="viewport" content="width=device-width,initial-scale=1"><title>PCWork Chat</title><body style="margin:0;background:#0a101a;color:#e8f1fa;font:16px system-ui;display:grid;min-height:100vh;place-items:center"><main style="max-width:420px;padding:28px;text-align:center"><h2>PCWork поддръжка</h2><p>'.esc_html($valid ? 'Защитената чат сесия е изтекла. Върнете се в приложението и отворете чата отново.' : 'Chatway все още не е конфигуриран. Моля, опитайте отново по-късно.').'</p></main></body></html>';
            exit;
        }

        $identity_script = '';
        if ($user_id && !empty($s['chatway_verification_enabled']) && !empty($s['chatway_verification_secret'])) {
            $user = get_user_by('id', $user_id);
            if ($user) {
                $identifier_type = in_array(($s['chatway_verification_identifier'] ?? 'id'), ['id','email'], true) ? $s['chatway_verification_identifier'] : 'id';
                $visitor_id = (string)$user->ID;
                $email = (string)$user->user_email;
                $hmac_base = $identifier_type === 'email' ? $email : $visitor_id;
                $hmac = hash_hmac('sha256', $hmac_base, (string)$s['chatway_verification_secret']);
                $identity = [
                    'visitor'=>['data'=>['id'=>$visitor_id,'email'=>$email],'hmac'=>$hmac],
                    'tags'=>[], 'customFields'=>[],
                ];
                $identity_script = '<script>window.chatwaySettings = '.wp_json_encode($identity, JSON_HEX_TAG | JSON_HEX_APOS | JSON_HEX_AMP | JSON_HEX_QUOT).';</script>';
            }
        }

        $script = 'https://cdn.chatway.app/widget.js?id=' . rawurlencode($installation_id);
        nocache_headers();
        header('Content-Type: text/html; charset=utf-8');
        header('X-Content-Type-Options: nosniff');
        header('Referrer-Policy: no-referrer');
        echo '<!doctype html><html lang="bg"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"><meta name="theme-color" content="#0a101a"><title>PCWork – Онлайн поддръжка</title><style>html,body{margin:0;width:100%;height:100%;background:#0a101a;color:#eaf4ff;font-family:system-ui,-apple-system,sans-serif}body{display:flex;align-items:center;justify-content:center}.hint{max-width:320px;padding:28px;text-align:center;color:#9fb0c4}.orb{width:62px;height:62px;margin:0 auto 18px;border-radius:20px;background:linear-gradient(135deg,#21d4d8,#7d65d9);display:grid;place-items:center;color:#07151b;font-size:28px;font-weight:800;box-shadow:0 12px 40px #21d4d833}h2{color:#fff;font-size:21px;margin:0 0 8px}.hint p{font-size:14px;line-height:1.55;margin:0}</style></head><body><div class="hint"><div class="orb">P</div><h2>PCWork поддръжка</h2><p>Зареждаме защитения чат. Можете да продължите предишния си разговор с екипа.</p></div>'.$identity_script.'<script id="chatway" async src="'.esc_url($script).'"></script><script>window.addEventListener("load",function(){var tries=0;var timer=setInterval(function(){tries++;if(window.$chatway&&typeof window.$chatway.openChatwayWidget==="function"){clearInterval(timer);window.$chatway.openChatwayWidget();}if(tries>40)clearInterval(timer);},250);});</script></body></html>';
        exit;
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
        $out['configured']=['woocommerce'=>!empty($s['woocommerce_consumer_key'])&&!empty($s['woocommerce_consumer_secret']),'bookly'=>!empty($s['bookly_booking_page_url']),'chatway'=>!empty($s['chatway_installation_id']),'chaty'=>!empty($s['chaty_widget_id']),'sheets'=>!empty($s['sheets_webhook_url'])&&!empty($s['sheets_webhook_secret']),'firebase'=>!empty($s['firebase_project_id'])&&!empty($s['firebase_service_account_json'])];
        return rest_ensure_response($out);
    }
}
PCWork_Admin_Integration_Settings::init();
