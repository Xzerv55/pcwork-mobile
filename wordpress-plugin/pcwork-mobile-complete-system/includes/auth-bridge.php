<?php
if (!defined('ABSPATH')) exit;

final class PCWork_Mobile_Auth_Bridge {
    const NS = 'pcwork/v1';
    const TOKEN_TTL = 86400; // 24 hours.

    public static function init() { add_action('rest_api_init', [__CLASS__, 'routes']); }

    public static function routes() {
        register_rest_route(self::NS, '/auth/register', ['methods'=>'POST','callback'=>[__CLASS__,'register_user'],'permission_callback'=>'__return_true']);
        register_rest_route(self::NS, '/auth/login', ['methods'=>'POST','callback'=>[__CLASS__,'login'],'permission_callback'=>'__return_true']);
        register_rest_route(self::NS, '/auth/me', ['methods'=>'GET','callback'=>[__CLASS__,'me'],'permission_callback'=>[__CLASS__,'authorize']]);
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
            if (is_array($headers)) {
                foreach ($headers as $key => $value) {
                    if (strtolower((string)$key) === 'authorization') { $header = $value; break; }
                }
            }
        }
        if (!$header || !preg_match('/Bearer\s+(.+)/i', $header, $m)) return new WP_Error('pcwork_auth_required','Моля, влезте в профила си.',['status'=>401]);
        $user_id=self::decode(trim($m[1]));
        if (!$user_id || !get_user_by('id',$user_id)) return new WP_Error('pcwork_token_invalid','Сесията е невалидна или изтекла.',['status'=>401]);
        wp_set_current_user($user_id);
        return true;
    }

    private static function rate_keys($identifier = '') {
        $ip = sanitize_text_field($_SERVER['REMOTE_ADDR'] ?? 'unknown');
        $keys = ['pcw_auth_v2_ip_' . md5($ip)];
        if ($identifier !== '') $keys[] = 'pcw_auth_v2_user_' . md5(strtolower(trim($identifier)));
        return $keys;
    }

    /** Check limits without penalizing successful logins. */
    private static function rate_limit($identifier = '') {
        foreach (self::rate_keys($identifier) as $index => $key) {
            $limit = $index === 0 ? 30 : 10;
            if ((int)get_transient($key) >= $limit) {
                return new WP_Error('pcwork_rate_limited','Твърде много неуспешни опити за вход. Опитайте отново след 15 минути.',['status'=>429]);
            }
        }
        return true;
    }

    private static function record_failed_attempt($identifier = '') {
        foreach (self::rate_keys($identifier) as $key) {
            set_transient($key, (int)get_transient($key) + 1, 15 * MINUTE_IN_SECONDS);
        }
    }

    private static function clear_failed_attempts($identifier = '') {
        foreach (self::rate_keys($identifier) as $key) delete_transient($key);
    }

    /**
     * Resolve an email to its WordPress login before authenticating. This keeps
     * the normal wp_authenticate filters (2FA, security plugins, SSO) active,
     * while also supporting sites where email authentication is disabled.
     */
    private static function authenticate_identifier($identifier, $password) {
        // WordPress normally authenticates by user_login. Resolve email first,
        // including mixed-case email addresses, while retaining wp_authenticate
        // so site security/2FA authentication filters remain in effect.
        if (is_email($identifier)) {
            $email = strtolower(trim(sanitize_email($identifier)));
            $by_email = get_user_by('email', $email);
            if (!$by_email instanceof WP_User) {
                global $wpdb;
                $user_id = (int)$wpdb->get_var($wpdb->prepare(
                    'SELECT ID FROM ' . $wpdb->users . ' WHERE LOWER(user_email) = %s LIMIT 1',
                    $email
                ));
                if ($user_id > 0) $by_email = get_user_by('id', $user_id);
            }
            if ($by_email instanceof WP_User) $identifier = $by_email->user_login;
        }
        return wp_authenticate($identifier, $password);
    }

    private static function response($user_id) {
        $u=get_user_by('id',$user_id);
        if (!$u) return new WP_Error('pcwork_user_missing','Потребителският профил не е намерен.',['status'=>404]);
        return rest_ensure_response(['token'=>self::issue($user_id),'token_type'=>'Bearer','expires_in'=>self::TOKEN_TTL,'user'=>['id'=>(int)$u->ID,'name'=>$u->display_name,'email'=>$u->user_email,'roles'=>array_values((array)$u->roles)]]);
    }

    public static function login($request) {
        $identifier = sanitize_text_field((string)(
            $request->get_param('login')
            ?: $request->get_param('identifier')
            ?: $request->get_param('email')
            ?: $request->get_param('user_login')
        ));
        $password = (string)$request->get_param('password');
        if ($identifier === '' || $password === '') return new WP_Error('pcwork_missing_credentials','Въведете имейл/потребителско име и парола.',['status'=>400]);
        $limit = self::rate_limit($identifier);
        if (is_wp_error($limit)) return $limit;

        $user = self::authenticate_identifier($identifier, $password);
        if (is_wp_error($user) || !($user instanceof WP_User)) {
            self::record_failed_attempt($identifier);
            return new WP_Error('pcwork_bad_credentials','Невалидни данни за вход. Проверете имейла/потребителското име и паролата.',['status'=>401]);
        }
        self::clear_failed_attempts($identifier);
        return self::response($user->ID);
    }

    public static function register_user($request) {
        $name=sanitize_text_field((string)$request->get_param('name'));
        $email=sanitize_email((string)$request->get_param('email'));
        $password=(string)$request->get_param('password');
        if (!$name || !is_email($email) || strlen($password)<10) return new WP_Error('pcwork_invalid_registration','Въведете име, валиден имейл и парола с поне 10 символа.',['status'=>400]);
        $limit = self::rate_limit($email);
        if (is_wp_error($limit)) return $limit;
        if (email_exists($email)) { self::record_failed_attempt($email); return new WP_Error('pcwork_email_exists','Този имейл вече има регистрация.',['status'=>409]); }
        $base_login = sanitize_user(str_replace('@', '_', $email), true);
        if ($base_login === '') $base_login = 'pcwork_user';
        $login = $base_login;
        $suffix = 1;
        while (username_exists($login)) {
            $login = $base_login . '_' . $suffix;
            $suffix++;
        }
        $user_id=wp_insert_user(['user_login'=>$login,'user_email'=>$email,'user_pass'=>$password,'display_name'=>$name,'role'=>'subscriber']);
        if (is_wp_error($user_id)) { self::record_failed_attempt($email); return $user_id; }
        self::clear_failed_attempts($email);
        return self::response($user_id);
    }

    public static function me() {
        $u=wp_get_current_user();
        return rest_ensure_response(['id'=>(int)$u->ID,'name'=>$u->display_name,'email'=>$u->user_email,'roles'=>array_values((array)$u->roles)]);
    }
}
PCWork_Mobile_Auth_Bridge::init();
