<?php
if (!defined('ABSPATH')) exit;

final class PCWork_Mobile_Auth_Bridge {
    const NS = 'pcwork/v1';
    const TOKEN_TTL = 86400; // 24 hours; users can sign in again after expiry.
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
    private static function rate_limit() {
        $ip=$_SERVER['REMOTE_ADDR']??'unknown'; $key='pcw_auth_'.md5($ip); $count=(int)get_transient($key);
        if ($count>=12) return new WP_Error('pcwork_rate_limited','Твърде много опити. Опитайте отново след 15 минути.',['status'=>429]);
        set_transient($key,$count+1,15*MINUTE_IN_SECONDS); return true;
    }
    private static function response($user_id) {
        $u=get_user_by('id',$user_id);
        return rest_ensure_response(['token'=>self::issue($user_id),'token_type'=>'Bearer','expires_in'=>self::TOKEN_TTL,'user'=>['id'=>(int)$u->ID,'name'=>$u->display_name,'email'=>$u->user_email,'roles'=>$u->roles]]);
    }
    public static function login($request) {
        $limit=self::rate_limit(); if (is_wp_error($limit)) return $limit;
        $email=sanitize_email($request->get_param('email')); $password=(string)$request->get_param('password');
        if (!$email || !$password) return new WP_Error('pcwork_missing_credentials','Въведете имейл и парола.',['status'=>400]);
        $user=get_user_by('email',$email);
        if (!$user || !wp_check_password($password,$user->user_pass,$user->ID)) return new WP_Error('pcwork_bad_credentials','Невалиден имейл или парола.',['status'=>401]);
        return self::response($user->ID);
    }
    public static function register_user($request) {
        $limit=self::rate_limit(); if (is_wp_error($limit)) return $limit;
        $name=sanitize_text_field($request->get_param('name')); $email=sanitize_email($request->get_param('email')); $password=(string)$request->get_param('password');
        if (!$name || !is_email($email) || strlen($password)<10) return new WP_Error('pcwork_invalid_registration','Въведете име, валиден имейл и парола с поне 10 символа.',['status'=>400]);
        if (email_exists($email)) return new WP_Error('pcwork_email_exists','Този имейл вече има регистрация.',['status'=>409]);
        $user_id=wp_insert_user(['user_login'=>$email,'user_email'=>$email,'user_pass'=>$password,'display_name'=>$name,'role'=>'subscriber']);
        if (is_wp_error($user_id)) return $user_id;
        return self::response($user_id);
    }
    public static function me() {
        $u=wp_get_current_user();
        return rest_ensure_response(['id'=>(int)$u->ID,'name'=>$u->display_name,'email'=>$u->user_email,'roles'=>$u->roles]);
    }
}
PCWork_Mobile_Auth_Bridge::init();
