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
        $header=$request->get_header('authorization');
        if (!$header || !preg_match('/Bearer\s+(.+)/i',$header,$m)) return new WP_Error('pcwork_auth_required','Моля, влезте в профила си.',['status'=>401]);
        $user_id=self::decode(trim($m[1]));
        if (!$user_id || !get_user_by('id',$user_id)) return new WP_Error('pcwork_token_invalid','Сесията е невалидна или изтекла.',['status'=>401]);
        wp_set_current_user($user_id);
        return true;
    }

    private static function rate_limit($identifier = '') {
        $ip = sanitize_text_field($_SERVER['REMOTE_ADDR'] ?? 'unknown');
        $keys = [
            'pcw_auth_ip_' . md5($ip),
        ];
        if ($identifier !== '') $keys[] = 'pcw_auth_user_' . md5(strtolower(trim($identifier)));
        foreach ($keys as $index => $key) {
            $count = (int)get_transient($key);
            $limit = $index === 0 ? 20 : 8;
            if ($count >= $limit) return new WP_Error('pcwork_rate_limited','Твърде много опити за вход. Опитайте отново след 15 минути.',['status'=>429]);
        }
        foreach ($keys as $key) set_transient($key, (int)get_transient($key) + 1, 15 * MINUTE_IN_SECONDS);
        return true;
    }

    private static function response($user_id) {
        $u=get_user_by('id',$user_id);
        if (!$u) return new WP_Error('pcwork_user_missing','Потребителският профил не е намерен.',['status'=>404]);
        return rest_ensure_response(['token'=>self::issue($user_id),'token_type'=>'Bearer','expires_in'=>self::TOKEN_TTL,'user'=>['id'=>(int)$u->ID,'name'=>$u->display_name,'email'=>$u->user_email,'roles'=>array_values((array)$u->roles)]]);
    }

    public static function login($request) {
        $identifier = sanitize_text_field((string)($request->get_param('login') ?: $request->get_param('email')));
        $password = (string)$request->get_param('password');
        if ($identifier === '' || $password === '') return new WP_Error('pcwork_missing_credentials','Въведете имейл/потребителско име и парола.',['status'=>400]);
        $limit = self::rate_limit($identifier);
        if (is_wp_error($limit)) return $limit;

        // wp_authenticate supports both WordPress usernames and email addresses
        // and preserves the site's normal authentication filters.
        $user = wp_authenticate($identifier, $password);
        if (is_wp_error($user) || !($user instanceof WP_User)) {
            return new WP_Error('pcwork_bad_credentials','Невалидни данни за вход. Проверете имейла/потребителското име и паролата.',['status'=>401]);
        }
        return self::response($user->ID);
    }

    public static function register_user($request) {
        $name=sanitize_text_field((string)$request->get_param('name'));
        $email=sanitize_email((string)$request->get_param('email'));
        $password=(string)$request->get_param('password');
        if (!$name || !is_email($email) || strlen($password)<10) return new WP_Error('pcwork_invalid_registration','Въведете име, валиден имейл и парола с поне 10 символа.',['status'=>400]);
        $limit = self::rate_limit($email);
        if (is_wp_error($limit)) return $limit;
        if (email_exists($email)) return new WP_Error('pcwork_email_exists','Този имейл вече има регистрация.',['status'=>409]);
        $user_id=wp_insert_user(['user_login'=>$email,'user_email'=>$email,'user_pass'=>$password,'display_name'=>$name,'role'=>'subscriber']);
        if (is_wp_error($user_id)) return $user_id;
        return self::response($user_id);
    }

    public static function me() {
        $u=wp_get_current_user();
        return rest_ensure_response(['id'=>(int)$u->ID,'name'=>$u->display_name,'email'=>$u->user_email,'roles'=>array_values((array)$u->roles)]);
    }
}
PCWork_Mobile_Auth_Bridge::init();
