<?php
if (!defined('ABSPATH')) exit;

final class PCWork_Mobile_Auth_Bridge {
    const NS = 'pcwork/v1';
    const TOKEN_TTL = 2592000;
    const OTP_TTL = 300;
    const OTP_RESEND_SECONDS = 60;

    public static function init() {
        add_action('init', [__CLASS__, 'ensure_customer_role']);
        add_action('rest_api_init', [__CLASS__, 'routes']);
        add_action('wp_mail_failed', [__CLASS__, 'capture_mail_error']);
    }

    public static function ensure_customer_role() {
        if (!get_role('pcwork_customer')) add_role('pcwork_customer', 'PCWork Customer', ['read' => true]);
    }

    public static function routes() {
        register_rest_route(self::NS, '/auth/register', ['methods'=>'POST','callback'=>[__CLASS__,'legacy_register_disabled'],'permission_callback'=>'__return_true']);
        register_rest_route(self::NS, '/auth/register/request', ['methods'=>'POST','callback'=>[__CLASS__,'request_registration_code'],'permission_callback'=>'__return_true']);
        register_rest_route(self::NS, '/auth/register/verify', ['methods'=>'POST','callback'=>[__CLASS__,'verify_registration_code'],'permission_callback'=>'__return_true']);
        register_rest_route(self::NS, '/auth/login/request', ['methods'=>'POST','callback'=>[__CLASS__,'request_login_code'],'permission_callback'=>'__return_true']);
        register_rest_route(self::NS, '/auth/login/verify', ['methods'=>'POST','callback'=>[__CLASS__,'verify_login_code'],'permission_callback'=>'__return_true']);
        register_rest_route(self::NS, '/auth/login', ['methods'=>'POST','callback'=>[__CLASS__,'login'],'permission_callback'=>'__return_true']);
        register_rest_route(self::NS, '/auth/me', ['methods'=>'GET','callback'=>[__CLASS__,'me'],'permission_callback'=>[__CLASS__,'authorize']]);
        register_rest_route(self::NS, '/auth/profile', ['methods'=>'PATCH','callback'=>[__CLASS__,'update_profile'],'permission_callback'=>[__CLASS__,'authorize']]);
    }

    public static function capture_mail_error($error) {
        if (is_wp_error($error)) {
            // Keep only a short diagnostic for administrators; never store OTP content.
            set_transient('pcwork_last_mail_error', sanitize_text_field($error->get_error_message()), 30 * MINUTE_IN_SECONDS);
        }
    }
    private static function b64($value) { return rtrim(strtr(base64_encode($value), '+/', '-_'), '='); }
    private static function secret() { return wp_salt('auth') . '|' . wp_salt('secure_auth'); }
    private static function issue($user_id) {
        $header = self::b64(wp_json_encode(['alg'=>'HS256','typ'=>'JWT']));
        $payload = self::b64(wp_json_encode(['iss'=>home_url(),'sub'=>(int)$user_id,'iat'=>time(),'exp'=>time()+self::TOKEN_TTL]));
        $body = $header.'.'.$payload;
        return $body.'.'.self::b64(hash_hmac('sha256',$body,self::secret(),true));
    }
    private static function decode($token) {
        $parts = explode('.', (string)$token);
        if (count($parts)!==3) return 0;
        $body=$parts[0].'.'.$parts[1];
        $sig=self::b64(hash_hmac('sha256',$body,self::secret(),true));
        if (!hash_equals($sig,$parts[2])) return 0;
        $payload=json_decode(base64_decode(strtr($parts[1], '-_', '+/')),true);
        if (!is_array($payload) || empty($payload['sub']) || empty($payload['exp']) || (int)$payload['exp']<time() || ($payload['iss']??'')!==home_url()) return 0;
        return (int)$payload['sub'];
    }
    public static function authorize($request) {
        $header = $request->get_header('authorization');
        if (!$header && !empty($_SERVER['HTTP_AUTHORIZATION'])) $header = wp_unslash($_SERVER['HTTP_AUTHORIZATION']);
        if (!$header && !empty($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) $header = wp_unslash($_SERVER['REDIRECT_HTTP_AUTHORIZATION']);
        if (!$header && function_exists('getallheaders')) {
            $headers = getallheaders();
            if (is_array($headers)) foreach ($headers as $key=>$value) if (strtolower((string)$key)==='authorization') { $header=$value; break; }
        }
        if (!$header || !preg_match('/Bearer\s+(.+)/i', $header, $m)) return new WP_Error('pcwork_auth_required','Моля, влезте в профила си.',['status'=>401]);
        $user_id=self::decode(trim($m[1]));
        $user=$user_id ? get_user_by('id',$user_id) : false;
        if (!$user || !empty($user->user_status) || get_user_meta($user_id,'pcwork_account_blocked',true)) return new WP_Error('pcwork_token_invalid','Сесията е невалидна или изтекла.',['status'=>401]);
        wp_set_current_user($user_id);
        return true;
    }
    private static function ip() {
        $remote=sanitize_text_field($_SERVER['REMOTE_ADDR'] ?? 'unknown');
        // Only honor proxy-provided client IP headers when the immediate proxy is explicitly trusted.
        $trusted=defined('PCWORK_TRUSTED_PROXY_IPS') && is_array(PCWORK_TRUSTED_PROXY_IPS) ? PCWORK_TRUSTED_PROXY_IPS : [];
        if (in_array($remote,$trusted,true)) {
            $forwarded=sanitize_text_field($_SERVER['HTTP_CF_CONNECTING_IP'] ?? $_SERVER['HTTP_X_REAL_IP'] ?? '');
            if (filter_var($forwarded,FILTER_VALIDATE_IP)) return $forwarded;
        }
        return $remote;
    }
    private static function count_key($kind, $value, $window) { return 'pcw_otp_' . $kind . '_' . $window . '_' . md5(strtolower(trim((string)$value))); }
    private static function increment($key, $ttl) { $value=(int)get_transient($key)+1; set_transient($key,$value,$ttl); return $value; }
    private static function rate_check($email, $is_resend = false) {
        $ip_key=self::count_key('ip',self::ip(),'15m');
        if ((int)get_transient($ip_key)>=30) return new WP_Error('pcwork_otp_rate_ip','Твърде много заявки от тази мрежа. Опитайте по-късно.',['status'=>429]);
        $short=self::count_key('email',$email,'15m');
        if ((int)get_transient($short)>=3) return new WP_Error('pcwork_otp_rate_email','Достигнат е лимитът за кодове. Опитайте след 15 минути.',['status'=>429]);
        $daily=self::count_key('email',$email,'day');
        if ((int)get_transient($daily)>=10) return new WP_Error('pcwork_otp_daily_limit','Достигнат е дневният лимит за кодове.',['status'=>429]);
        $cooldown=self::count_key('cooldown',$email,'60s');
        if (get_transient($cooldown)) return new WP_Error('pcwork_otp_cooldown','Изчакайте 60 секунди преди нов код.',['status'=>429]);
        return true;
    }
    private static function issue_code($type, $email, $name = '', $phone = '') {
        $limit=self::rate_check($email);
        if (is_wp_error($limit)) return $limit;
        $code=(string)random_int(100000,999999);
        $challenge=['hash'=>wp_hash_password($code),'attempts'=>0,'type'=>$type,'name'=>$name,'phone'=>$phone,'created'=>time()];
        set_transient(self::count_key('challenge',$type.'|'.$email,'otp'),$challenge,self::OTP_TTL);
        self::increment(self::count_key('ip',self::ip(),'15m'),15*MINUTE_IN_SECONDS);
        self::increment(self::count_key('email',$email,'15m'),15*MINUTE_IN_SECONDS);
        self::increment(self::count_key('email',$email,'day'),DAY_IN_SECONDS);
        set_transient(self::count_key('cooldown',$email,'60s'),1,self::OTP_RESEND_SECONDS);
        $subject='Код за потвърждение – PCWork';
        $message='<div style="font-family:Arial,sans-serif;max-width:520px;margin:auto;color:#17212b"><h2>PCWork</h2><p>Вашият код за потвърждение е:</p><p style="font-size:30px;font-weight:bold;letter-spacing:8px">'.esc_html($code).'</p><p>Кодът е валиден 5 минути и може да бъде използван само веднъж.</p><p>Ако не сте заявили този код, игнорирайте съобщението.</p></div>';
        delete_transient('pcwork_last_mail_error');
        $headers=['Content-Type: text/html; charset=UTF-8'];
        $reply_to=sanitize_email((string)get_option('admin_email'));
        if (is_email($reply_to)) $headers[]='Reply-To: PCWork <'.$reply_to.'>';
        $sent=wp_mail($email,$subject,$message,$headers);
        if (!$sent) {
            delete_transient(self::count_key('challenge',$type.'|'.$email,'otp'));
            $detail=(string)get_transient('pcwork_last_mail_error');
            $message='WordPress не успя да изпрати имейла с кода.';
            if ($detail!=='') $message.=' Причина: '.$detail;
            $message.=' Провери SMTP настройките и тестовия имейл в PCWork Mobile → Интеграции.';
            return new WP_Error('pcwork_email_delivery_failed',$message,['status'=>503]);
        }
        return rest_ensure_response(['ok'=>true,'message'=>'Ако адресът може да получи код, изпратихме имейл с инструкции.','expires_in'=>self::OTP_TTL,'resend_after'=>self::OTP_RESEND_SECONDS]);
    }
    private static function verify_code($type, $email, $code) {
        $key=self::count_key('challenge',$type.'|'.$email,'otp');
        $challenge=get_transient($key);
        if (!is_array($challenge) || empty($challenge['hash']) || !preg_match('/^\d{6}$/',(string)$code)) return new WP_Error('pcwork_otp_invalid','Кодът е невалиден или е изтекъл. Заявете нов код.',['status'=>400]);
        if ((int)($challenge['attempts']??0)>=5) { delete_transient($key); return new WP_Error('pcwork_otp_attempts','Достигнат е лимитът от 5 опита. Заявете нов код.',['status'=>429]); }
        if (!wp_check_password((string)$code,$challenge['hash'])) {
            $challenge['attempts']=(int)$challenge['attempts']+1;
            set_transient($key,$challenge,max(1,self::OTP_TTL-(time()-(int)$challenge['created'])));
            if ($challenge['attempts']>=5) delete_transient($key);
            return new WP_Error('pcwork_otp_invalid','Невалиден код. Проверете имейла и опитайте отново.',['status'=>400]);
        }
        delete_transient($key);
        return $challenge;
    }
    private static function normalized_email($request) { return strtolower(trim(sanitize_email((string)$request->get_param('email')))); }
    public static function request_registration_code($request) {
        $name=sanitize_text_field((string)$request->get_param('name'));
        $phone=sanitize_text_field((string)$request->get_param('phone'));
        $email=self::normalized_email($request);
        // Honeypot field: bots often fill hidden website fields.
        if ((string)$request->get_param('website') !== '') return new WP_Error('pcwork_registration_rejected','Заявката не може да бъде обработена.',['status'=>400]);
        if ($request->get_param('terms_accepted') !== true && $request->get_param('terms_accepted') !== '1') return new WP_Error('pcwork_terms_required','Необходимо е съгласие с общите условия и политиката за поверителност.',['status'=>400]);
        if (strlen($name)<2 || strlen($name)>100 || !is_email($email) || strlen($phone)<6 || strlen($phone)>30) return new WP_Error('pcwork_registration_invalid','Въведете име, телефон и валиден имейл адрес.',['status'=>400]);
        if (email_exists($email)) {
            $ip_key=self::count_key('ip',self::ip(),'15m');
            if ((int)get_transient($ip_key)>=30) return new WP_Error('pcwork_otp_rate_ip','Твърде много заявки от тази мрежа. Опитайте по-късно.',['status'=>429]);
            self::increment($ip_key,15*MINUTE_IN_SECONDS);
            return new WP_Error('pcwork_email_exists','Този имейл вече има профил. Използвайте вход с код.',['status'=>409]);
        }
        return self::issue_code('register',$email,$name,$phone);
    }
    public static function verify_registration_code($request) {
        $email=self::normalized_email($request); $code=sanitize_text_field((string)$request->get_param('code'));
        if (!is_email($email)) return new WP_Error('pcwork_otp_invalid','Невалиден код или имейл.',['status'=>400]);
        $challenge=self::verify_code('register',$email,$code);
        if (is_wp_error($challenge)) return $challenge;
        if (email_exists($email)) return new WP_Error('pcwork_email_exists','Този имейл вече има профил. Използвайте вход с код.',['status'=>409]);
        self::ensure_customer_role();
        $base=sanitize_user(str_replace('@','_',$email),true); if ($base==='') $base='pcwork_customer';
        $login=$base; $suffix=1; while (username_exists($login)) { $login=$base.'_'.$suffix++; }
        $user_id=wp_insert_user(['user_login'=>$login,'user_email'=>$email,'user_pass'=>wp_generate_password(48,true,true),'display_name'=>$challenge['name'],'role'=>'pcwork_customer']);
        if (is_wp_error($user_id)) return $user_id;
        update_user_meta($user_id,'pcwork_phone',$challenge['phone']);
        update_user_meta($user_id,'pcwork_email_verified',1);
        update_user_meta($user_id,'pcwork_terms_accepted_at',current_time('mysql'));
        update_user_meta($user_id,'pcwork_privacy_accepted_at',current_time('mysql'));
        update_user_meta($user_id,'pcwork_terms_version','2026-11');
        update_user_meta($user_id,'pcwork_customer_registered_via','mobile_email_otp');
        return self::response($user_id);
    }
    public static function request_login_code($request) {
        $email=self::normalized_email($request);
        if (!is_email($email)) return new WP_Error('pcwork_email_invalid','Въведете валиден имейл адрес.',['status'=>400]);
        $user=get_user_by('email',$email);
        // Keep the response identical to avoid disclosing which emails have accounts.
        if (!$user || get_user_meta($user->ID,'pcwork_account_blocked',true)) {
            $ip_key=self::count_key('ip',self::ip(),'15m');
            if ((int)get_transient($ip_key)>=30) return new WP_Error('pcwork_otp_rate_ip','Твърде много заявки от тази мрежа. Опитайте по-късно.',['status'=>429]);
            self::increment($ip_key,15*MINUTE_IN_SECONDS);
            return rest_ensure_response(['ok'=>true,'message'=>'Ако има профил с този адрес, ще получите код за вход.','expires_in'=>self::OTP_TTL,'resend_after'=>self::OTP_RESEND_SECONDS]);
        }
        return self::issue_code('login',$email);
    }
    public static function verify_login_code($request) {
        $email=self::normalized_email($request); $code=sanitize_text_field((string)$request->get_param('code'));
        if (!is_email($email)) return new WP_Error('pcwork_otp_invalid','Невалиден код или имейл.',['status'=>400]);
        $challenge=self::verify_code('login',$email,$code);
        if (is_wp_error($challenge)) return $challenge;
        $user=get_user_by('email',$email);
        if (!$user || get_user_meta($user->ID,'pcwork_account_blocked',true)) return new WP_Error('pcwork_otp_invalid','Невалиден код или имейл.',['status'=>400]);
        update_user_meta($user->ID,'pcwork_email_verified',1);
        return self::response($user->ID);
    }
    public static function legacy_register_disabled($request) {
        return new WP_Error('pcwork_registration_flow_updated','Регистрацията вече се потвърждава с код по имейл. Обновете приложението.',['status'=>410]);
    }
    private static function response($user_id) {
        $u=get_user_by('id',$user_id);
        if (!$u) return new WP_Error('pcwork_user_missing','Потребителският профил не е намерен.',['status'=>404]);
        return rest_ensure_response(['token'=>self::issue($user_id),'token_type'=>'Bearer','expires_in'=>self::TOKEN_TTL,'user'=>['id'=>(int)$u->ID,'name'=>$u->display_name,'email'=>$u->user_email,'phone'=>(string)get_user_meta($user_id,'pcwork_phone',true),'roles'=>array_values((array)$u->roles)]]);
    }
    // Legacy password login remains available for existing staff accounts only.
    public static function login($request) {
        $identifier=sanitize_text_field((string)($request->get_param('login') ?: $request->get_param('identifier') ?: $request->get_param('email') ?: $request->get_param('user_login')));
        $password=(string)$request->get_param('password');
        if ($identifier==='' || $password==='') return new WP_Error('pcwork_missing_credentials','Въведете данни за вход.',['status'=>400]);
        // WordPress password authentication remains mandatory. Email is normalized to login name.
        $candidate = is_email($identifier) ? get_user_by('email', sanitize_email($identifier)) : get_user_by('login', $identifier);
        $login_name = ($candidate instanceof WP_User) ? $candidate->user_login : $identifier;
        $user=wp_authenticate($login_name,$password);
        if (is_wp_error($user) || !($user instanceof WP_User)) return new WP_Error('pcwork_bad_credentials','Невалидни данни за вход.',['status'=>401]);
        if (get_user_meta($user->ID, 'pcwork_account_blocked', true)) return new WP_Error('pcwork_account_blocked','Достъпът до профила е ограничен. Свържете се с администратора.',['status'=>403]);
        $otp_bypass = get_user_meta($user->ID, 'pcwork_otp_bypass', true) === '1';
        if ((in_array('pcwork_customer',(array)$user->roles,true) || in_array('subscriber',(array)$user->roles,true) || in_array('customer',(array)$user->roles,true)) && !$otp_bypass) return new WP_Error('pcwork_customer_use_otp','За този профил е задължителен вход с код по имейл.',['status'=>403]);
        if (!in_array('pcwork_customer',(array)$user->roles,true) && !$otp_bypass && !user_can($user, 'read')) return new WP_Error('pcwork_bad_credentials','Невалидни данни за вход.',['status'=>401]);
        return self::response($user->ID);
    }

    /** Clear OTP counters for a user after an administrator-authorized action. */
    public static function clear_user_rate_limits($user_id) {
        $user = get_user_by('id', absint($user_id));
        if (!$user) return false;
        $email = strtolower(trim($user->user_email));
        foreach (['email_15m','email_day','cooldown_60s'] as $kind_window) {
            [$kind,$window] = explode('_', $kind_window, 2);
            delete_transient(self::count_key($kind, $email, $window));
        }
        delete_transient(self::count_key('challenge', 'login|' . $email, 'otp'));
        return true;
    }
    private static function profile_payload($user_id) {
        $u=get_user_by('id',$user_id);
        $billing=[]; $shipping=[];
        $keys=['first_name','last_name','company','address_1','address_2','city','state','postcode','country','email','phone'];
        foreach($keys as $key) {
            $billing[$key]=(string)get_user_meta($user_id,'billing_'.$key,true);
            $shipping[$key]=(string)get_user_meta($user_id,'shipping_'.$key,true);
        }
        if (!$billing['email']) $billing['email']=$u->user_email;
        if (!$billing['first_name'] && $u->first_name) $billing['first_name']=$u->first_name;
        if (!$billing['last_name'] && $u->last_name) $billing['last_name']=$u->last_name;
        if (!$billing['phone']) $billing['phone']=(string)get_user_meta($user_id,'pcwork_phone',true);
        if (!$shipping['first_name']) $shipping['first_name']=$billing['first_name'];
        if (!$shipping['last_name']) $shipping['last_name']=$billing['last_name'];
        return ['id'=>(int)$u->ID,'name'=>$u->display_name,'email'=>$u->user_email,'phone'=>(string)get_user_meta($user_id,'pcwork_phone',true),'billing'=>$billing,'shipping'=>$shipping,'email_verified'=>(bool)get_user_meta($user_id,'pcwork_email_verified',true),'roles'=>array_values((array)$u->roles)];
    }
    public static function me() {
        return rest_ensure_response(self::profile_payload(get_current_user_id()));
    }
    public static function update_profile($request) {
        $user_id=get_current_user_id(); $name=sanitize_text_field((string)$request->get_param('name')); $phone=sanitize_text_field((string)$request->get_param('phone'));
        if (strlen($name)<2 || strlen($name)>100 || strlen($phone)<6 || strlen($phone)>30) return new WP_Error('pcwork_profile_invalid','Въведете валидно име и телефон.',['status'=>400]);
        $updated=wp_update_user(['ID'=>$user_id,'display_name'=>$name]);
        if (is_wp_error($updated)) return $updated;
        update_user_meta($user_id,'pcwork_phone',$phone);
        $billing=$request->get_param('billing'); $shipping=$request->get_param('shipping');
        $keys=['first_name','last_name','company','address_1','address_2','city','state','postcode','country'];
        foreach(['billing'=>$billing,'shipping'=>$shipping] as $kind=>$address) {
            if (!is_array($address)) continue;
            foreach($keys as $key) if (array_key_exists($key,$address)) update_user_meta($user_id,$kind.'_'.$key,sanitize_text_field((string)$address[$key]));
        }
        // Keep standard WordPress and WooCommerce customer fields synchronized.
        $first_name = sanitize_text_field((string)($billing['first_name'] ?? ''));
        $last_name = sanitize_text_field((string)($billing['last_name'] ?? ''));
        update_user_meta($user_id, 'first_name', $first_name);
        update_user_meta($user_id, 'last_name', $last_name);
        // Registration email is intentionally immutable through this endpoint.
        update_user_meta($user_id,'billing_email',get_userdata($user_id)->user_email);
        if (class_exists('WC_Customer')) {
            $customer = new WC_Customer($user_id);
            $customer->set_first_name($first_name);
            $customer->set_last_name($last_name);
            $customer->set_billing_phone($phone);
            foreach (['address_1','address_2','city','state','postcode','country','company'] as $field) {
                if (array_key_exists($field, (array)$billing)) { $method = 'set_billing_' . $field; if (method_exists($customer, $method)) $customer->$method(sanitize_text_field((string)$billing[$field])); }
                if (array_key_exists($field, (array)$shipping)) { $method = 'set_shipping_' . $field; if (method_exists($customer, $method)) $customer->$method(sanitize_text_field((string)$shipping[$field])); }
            }
            if (is_array($shipping)) {
                if (isset($shipping['first_name'])) $customer->set_shipping_first_name(sanitize_text_field((string)$shipping['first_name']));
                if (isset($shipping['last_name'])) $customer->set_shipping_last_name(sanitize_text_field((string)$shipping['last_name']));
            }
            $customer->save();
        }
        return rest_ensure_response(self::profile_payload($user_id));
    }
}
PCWork_Mobile_Auth_Bridge::init();
