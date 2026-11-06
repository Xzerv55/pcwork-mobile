<?php
if (!defined('ABSPATH')) exit;

final class PCWork_Mobile_Repairs_API {
    const NS = 'pcwork/v1';
    public static function repairs_table() { global $wpdb; return $wpdb->prefix . 'pcwork_repairs'; }
    public static function history_table() { global $wpdb; return $wpdb->prefix . 'pcwork_repair_history'; }
    public static function documents_table() { global $wpdb; return $wpdb->prefix . 'pcwork_repair_documents'; }
    public static function locations_table() { global $wpdb; return $wpdb->prefix . 'pcwork_locations'; }

    public static function activate() {
        global $wpdb;
        require_once ABSPATH . 'wp-admin/includes/upgrade.php';
        $charset = $wpdb->get_charset_collate();
        $repairs = self::repairs_table();
        $history = self::history_table();
        dbDelta("CREATE TABLE $repairs (
            id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
            repair_number varchar(64) NOT NULL,
            client_request_id varchar(64) NULL DEFAULT NULL,
            customer_user_id bigint(20) unsigned NOT NULL,
            customer_name varchar(190) NOT NULL DEFAULT '',
            customer_email varchar(190) NOT NULL DEFAULT '',
            customer_phone varchar(50) NOT NULL DEFAULT '',
            location_code varchar(64) NOT NULL DEFAULT '',
            location_name varchar(190) NOT NULL DEFAULT '',
            device_type varchar(100) NOT NULL DEFAULT '',
            device_model varchar(190) NOT NULL DEFAULT '',
            serial_number varchar(190) NOT NULL DEFAULT '',
            problem_description text NULL,
            external_condition text NULL,
            accessories text NULL,
            intake_notes text NULL,
            status varchar(40) NOT NULL DEFAULT 'received',
            assigned_technician_id bigint(20) unsigned NOT NULL DEFAULT 0,
            priority varchar(20) NOT NULL DEFAULT 'normal',
            due_at datetime NULL,
            created_by bigint(20) unsigned NOT NULL DEFAULT 0,
            created_at datetime NOT NULL,
            updated_at datetime NOT NULL,
            PRIMARY KEY  (id),
            UNIQUE KEY repair_number (repair_number),
            UNIQUE KEY client_request_id (client_request_id),
            KEY customer_user_id (customer_user_id),
            KEY location_code (location_code),
            KEY status (status)
        ) $charset;");
        dbDelta("CREATE TABLE $history (
            id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
            repair_id bigint(20) unsigned NOT NULL,
            status varchar(40) NOT NULL DEFAULT '',
            note text NULL,
            client_request_id varchar(64) NULL DEFAULT NULL,
            created_at datetime NOT NULL,
            PRIMARY KEY  (id),
            KEY repair_id (repair_id),
            UNIQUE KEY client_request_id (client_request_id)
        ) $charset;");
        $locations = self::locations_table();
        dbDelta("CREATE TABLE $locations (
            id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
            code varchar(64) NOT NULL,
            name varchar(190) NOT NULL,
            address varchar(255) NOT NULL DEFAULT '',
            phone varchar(50) NOT NULL DEFAULT '',
            active tinyint(1) NOT NULL DEFAULT 1,
            PRIMARY KEY  (id),
            UNIQUE KEY code (code)
        ) $charset;");
        $seed_locations = [
            ['sofia-lyulin','София – Люлин'], ['sofia-lyulin-2','София, Люлин - 2'],
            ['sofia-industrialna-11','София – Индустриална 11'], ['sofia-simeonovsko','София – Симеоновско шосе'],
            ['varna','Варна'], ['varna-center','Варна, Център'], ['plovdiv','Пловдив'], ['plovdiv-center','Пловдив, Център'],
            ['plovdiv-veliko-tarnovo','Пловдив, Велико Търново'], ['burgas','Бургас'], ['burgas-center','Бургас, Център'],
            ['veliko-tarnovo','Велико Търново'], ['shumen','Шумен'], ['shumen-center','Шумен, Център']
        ];
        foreach ($seed_locations as $loc) {
            $exists = $wpdb->get_var($wpdb->prepare("SELECT id FROM $locations WHERE code=%s", $loc[0]));
            if (!$exists) $wpdb->insert($locations, ['code'=>$loc[0], 'name'=>$loc[1], 'active'=>1]);
        }
        $attendance = $wpdb->prefix . 'pcwork_staff_attendance';
        dbDelta("CREATE TABLE $attendance (
            id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
            user_id bigint(20) unsigned NOT NULL,
            check_in datetime NOT NULL,
            check_out datetime NULL,
            created_at datetime NOT NULL,
            PRIMARY KEY  (id),
            KEY user_id (user_id),
            KEY check_in (check_in)
        ) $charset;");
        $leave = $wpdb->prefix . 'pcwork_staff_leave';
        dbDelta("CREATE TABLE $leave (
            id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
            user_id bigint(20) unsigned NOT NULL,
            start_date date NOT NULL,
            end_date date NOT NULL,
            reason text NULL,
            status varchar(20) NOT NULL DEFAULT 'pending',
            reviewed_by bigint(20) unsigned NOT NULL DEFAULT 0,
            reviewed_at datetime NULL,
            created_at datetime NOT NULL,
            PRIMARY KEY  (id),
            KEY user_id (user_id),
            KEY status (status)
        ) $charset;");
        $documents = self::documents_table();
        dbDelta("CREATE TABLE $documents (
            id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
            repair_id bigint(20) unsigned NOT NULL,
            kind varchar(40) NOT NULL,
            attachment_id bigint(20) unsigned NOT NULL DEFAULT 0,
            storage_key varchar(190) NOT NULL DEFAULT '',
            mime_type varchar(100) NOT NULL DEFAULT '',
            original_name varchar(190) NOT NULL DEFAULT '',
            file_size bigint(20) unsigned NOT NULL DEFAULT 0,
            actor_user_id bigint(20) unsigned NOT NULL DEFAULT 0,
            created_at datetime NOT NULL,
            PRIMARY KEY  (id),
            KEY repair_id (repair_id),
            KEY kind (kind)
        ) $charset;");
        update_option('pcwork_repairs_api_db_version', '1.8.0', false);
    }

    public static function maybe_upgrade() {
        if (get_option('pcwork_repairs_api_db_version') !== '1.8.0') self::activate();
    }

    public static function init() { add_action('init', [__CLASS__, 'maybe_upgrade'], 1); add_action('rest_api_init', [__CLASS__, 'routes']); }
    public static function routes() {
        $auth = [__CLASS__, 'authorize'];
        register_rest_route(self::NS, '/health', ['methods'=>'GET','callback'=>function(){ return rest_ensure_response(['ok'=>true,'plugin'=>'PCWork Mobile Complete System','version'=>'2.7.0']); },'permission_callback'=>'__return_true']);
        register_rest_route(self::NS, '/locations', ['methods'=>'GET','callback'=>[__CLASS__,'list_locations'],'permission_callback'=>'__return_true']);
        register_rest_route(self::NS, '/repairs', ['methods'=>'GET','callback'=>[__CLASS__,'list_repairs'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/repairs', ['methods'=>'POST','callback'=>[__CLASS__,'create_repair'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/repairs/(?P<id>\d+)', ['methods'=>'GET','callback'=>[__CLASS__,'get_repair'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/repairs/(?P<id>\d+)/status', ['methods'=>'PATCH','callback'=>[__CLASS__,'update_status'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/repairs/(?P<id>\d+)/assignment', ['methods'=>'PATCH','callback'=>[__CLASS__,'update_assignment'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/staff/technicians', ['methods'=>'GET','callback'=>[__CLASS__,'list_technicians'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/staff/schedule', ['methods'=>'GET','callback'=>[__CLASS__,'get_staff_schedules'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/staff/schedule', ['methods'=>'POST','callback'=>[__CLASS__,'save_staff_schedule'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/staff/overview', ['methods'=>'GET','callback'=>[__CLASS__,'staff_overview'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/staff/attendance', ['methods'=>'GET','callback'=>[__CLASS__,'get_attendance'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/staff/attendance', ['methods'=>'POST','callback'=>[__CLASS__,'record_attendance'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/staff/leave', ['methods'=>'GET','callback'=>[__CLASS__,'list_leave_requests'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/staff/leave', ['methods'=>'POST','callback'=>[__CLASS__,'create_leave_request'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/staff/leave/(?P<id>\d+)', ['methods'=>'PATCH','callback'=>[__CLASS__,'review_leave_request'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/repairs/(?P<id>\d+)/evidence', ['methods'=>'POST','callback'=>[__CLASS__,'upload_evidence'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/repairs/(?P<id>\d+)/protocol', ['methods'=>'POST','callback'=>[__CLASS__,'upload_protocol_pdf'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/repairs/(?P<id>\d+)/documents', ['methods'=>'GET','callback'=>[__CLASS__,'list_documents'],'permission_callback'=>$auth]);
        register_rest_route(self::NS, '/repairs/(?P<id>\d+)/documents/(?P<document_id>\d+)/download', ['methods'=>'GET','callback'=>[__CLASS__,'download_document'],'permission_callback'=>$auth]);
    }
    public static function list_locations($request) {
        // Mirrors every card currently published on pcwork-bg.com/kontakti/.
        // Only the first four cards are not marked as upcoming on the source page.
        $hours = 'Понеделник – Неделя · 09:00–21:00';
        $website = home_url('/kontakti/');
        $entries = [
            ['sofia-lyulin', 'София, Люлин - 5', 'PS4 и PS5', false, 'гр. София, Люлин - 5', 'Lulin.webp'],
            ['sofia-lyulin-2', 'София, Люлин - 2', 'Изграждане AI системи', false, 'гр. София, Люлин - 2', 'Lulin.webp'],
            ['sofia-simeonovsko', 'София, Симеоновско шосе', 'Изграждане AI системи', false, 'гр. София, Симеоновско шосе', 'Simeonovsko.webp'],
            ['sofia-industrialna-11', 'София, Индустриална 11', 'Изграждане AI системи', false, 'гр. София, Индустриална 11', 'Sofia11.webp'],
            ['varna-center', 'Варна, Център', 'Предстоящо откриване', true, 'гр. Варна, Център', 'Varna.webp'],
            ['burgas-center', 'Бургас, Център', 'Предстоящо откриване', true, 'гр. Бургас, Център', 'Burgas.webp'],
            ['plovdiv-veliko-tarnovo', 'Пловдив, Велико Търново', 'Предстоящо откриване', true, 'Пловдив, Велико Търново', 'VelikoTurnovo.webp'],
            ['plovdiv-center', 'Пловдив, Център', 'Предстоящо откриване', true, 'гр. Пловдив, Център', 'Plovdiv.webp'],
            ['shumen-center', 'Шумен, Център', 'Предстоящо откриване', true, 'гр. Шумен, Център', 'Shumen.webp'],
        ];
        $rows = [];
        foreach ($entries as $entry) {
            [$code, $name, $description, $upcoming, $map_query, $image] = $entry;
            $image_url = $image ? 'https://pcwork-bg.com/wp-content/uploads/2026/11/' . $image : '';
            $rows[] = [
                'code' => $code,
                'name' => $name,
                'address' => $map_query,
                'phone' => '',
                'description' => $description,
                'availability' => $upcoming ? 'upcoming' : 'listed',
                'availability_label' => $description,
                'is_upcoming' => $upcoming,
                'can_select' => !$upcoming,
                'hours' => $hours,
                'image_url' => $image_url,
                'image_caption' => $image_url ? 'Визуализация от страницата Контакти, не е снимка на фасадата.' : '',
                'maps_url' => 'https://www.google.com/maps/search/?api=1&query=' . rawurlencode($map_query),
                'website_url' => $website,
            ];
        }
        return rest_ensure_response(['data' => $rows]);
    }
    public static function authorize($request) {
        if (!class_exists('PCWork_Mobile_Auth_Bridge')) return new WP_Error('pcwork_auth_bridge_missing','Модулът за вход PCWork Mobile Auth Bridge не е активен.',['status'=>503]);
        return PCWork_Mobile_Auth_Bridge::authorize($request);
    }
    private static function is_staff($user_id) { return user_can($user_id, 'manage_options') || user_can($user_id, 'pcwork_manage_repairs'); }
    private static function can_access($row, $user_id) {
        if ((int)$row->customer_user_id === (int)$user_id) return true;
        if (!self::is_staff($user_id)) return false;
        if (user_can($user_id, 'manage_options')) return true;
        $codes = get_user_meta($user_id, 'pcwork_location_codes', true);
        if (!is_array($codes)) $codes = [];
        return in_array((string)$row->location_code, array_map('strval', $codes), true);
    }
    private static function history($repair_id) {
        global $wpdb;
        $rows = $wpdb->get_results($wpdb->prepare('SELECT status,note,created_at FROM ' . self::history_table() . ' WHERE repair_id=%d ORDER BY id ASC', $repair_id), ARRAY_A);
        return is_array($rows) ? $rows : [];
    }
    private static function present($row, $include_history = false) {
        $data = [
            'id'=>(int)$row->id, 'repair_number'=>$row->repair_number,
            'customer_name'=>$row->customer_name, 'customer_email'=>$row->customer_email,
            'customer_phone'=>$row->customer_phone, 'location_code'=>$row->location_code, 'location_name'=>$row->location_name,
            'device_type'=>$row->device_type, 'device_model'=>$row->device_model, 'serial_number'=>$row->serial_number,
            'problem_description'=>$row->problem_description, 'external_condition'=>$row->external_condition,
            'accessories'=>$row->accessories, 'intake_notes'=>$row->intake_notes, 'status'=>$row->status,
            'assigned_technician_id'=>(int)($row->assigned_technician_id ?? 0), 'priority'=>$row->priority ?? 'normal', 'due_at'=>$row->due_at ?? null,
            'created_at'=>mysql2date('c', $row->created_at, false), 'updated_at'=>mysql2date('c', $row->updated_at, false),
        ];
        if (!empty($row->assigned_technician_id)) { $tech = get_user_by('id', (int)$row->assigned_technician_id); $data['assigned_technician_name'] = $tech ? $tech->display_name : ''; } else { $data['assigned_technician_name'] = ''; }
        if ($include_history) { $data['history'] = self::history($row->id); $data['documents'] = self::documents($row->id); }
        return $data;
    }
    public static function list_repairs($request) {
        global $wpdb;
        $user_id = get_current_user_id(); $table = self::repairs_table();
        if (self::is_staff($user_id)) {
            if (user_can($user_id, 'manage_options')) $rows = $wpdb->get_results("SELECT * FROM $table ORDER BY updated_at DESC LIMIT 100");
            else {
                $codes = get_user_meta($user_id, 'pcwork_location_codes', true);
                if (!is_array($codes) || !$codes) $rows = [];
                else { $placeholders = implode(',', array_fill(0, count($codes), '%s')); $sql = $wpdb->prepare("SELECT * FROM $table WHERE location_code IN ($placeholders) ORDER BY updated_at DESC LIMIT 100", ...array_map('strval', $codes)); $rows = $wpdb->get_results($sql); }
            }
        } else $rows = $wpdb->get_results($wpdb->prepare("SELECT * FROM $table WHERE customer_user_id=%d ORDER BY updated_at DESC LIMIT 100", $user_id));
        return rest_ensure_response(['data'=>array_map(function($row){ return self::present($row); }, $rows ?: [])]);
    }
    public static function create_repair($request) {
        global $wpdb;
        $staff_id = get_current_user_id();
        if (!self::is_staff($staff_id)) return new WP_Error('pcwork_staff_required','Само оторизиран служител може да регистрира прием.',['status'=>403]);
        $p = $request->get_json_params(); if (!is_array($p)) $p = [];
        $client_request_id = sanitize_text_field($p['client_request_id'] ?? '');
        if ($client_request_id !== '') {
            $existing = $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . self::repairs_table() . ' WHERE client_request_id=%s', $client_request_id));
            if ($existing) {
                if (!self::can_access($existing, $staff_id)) return new WP_Error('pcwork_repair_forbidden','Нямате права за този ремонт.',['status'=>403]);
                return new WP_REST_Response(['data'=>self::present($existing, true),'message'=>'Заявката вече е обработена.'], 200);
            }
        }
        $email = sanitize_email($p['customer_email'] ?? '');
        $customer = $email ? get_user_by('email', $email) : false;
        if (!$customer) return new WP_Error('pcwork_customer_not_found','Не е намерен клиент с този имейл. Първо създайте клиентски профил.',['status'=>400]);
        $location_code = sanitize_text_field($p['location_code'] ?? '');
        if (!$location_code) return new WP_Error('pcwork_location_required','Изберете сервизен обект.',['status'=>400]);
        if (!user_can($staff_id, 'manage_options')) {
            $allowed = get_user_meta($staff_id, 'pcwork_location_codes', true); if (!is_array($allowed)) $allowed = [];
            if (!in_array($location_code, array_map('strval', $allowed), true)) return new WP_Error('pcwork_location_forbidden','Нямате права за този сервизен обект.',['status'=>403]);
        }
        $required = ['device_type'=>'Тип устройство','device_model'=>'Модел','problem_description'=>'Описание на проблема'];
        foreach ($required as $key=>$label) if (empty($p[$key])) return new WP_Error('pcwork_field_required','Попълнете поле: '.$label,['status'=>400]);
        $location_name = sanitize_text_field($p['location_name'] ?? $location_code);
        $now = current_time('mysql'); $number = 'PCW-' . wp_date('ymd') . '-' . strtoupper(wp_generate_password(6, false, false));
        $ok = $wpdb->insert(self::repairs_table(), [
            'repair_number'=>$number, 'client_request_id'=>$client_request_id !== '' ? $client_request_id : null, 'customer_user_id'=>(int)$customer->ID,
            'customer_name'=>sanitize_text_field($p['customer_name'] ?? $customer->display_name),
            'customer_email'=>$email, 'customer_phone'=>sanitize_text_field($p['customer_phone'] ?? ''),
            'location_code'=>$location_code, 'location_name'=>$location_name,
            'device_type'=>sanitize_text_field($p['device_type']), 'device_model'=>sanitize_text_field($p['device_model']),
            'serial_number'=>sanitize_text_field($p['serial_number'] ?? ''),
            'problem_description'=>sanitize_textarea_field($p['problem_description']),
            'external_condition'=>sanitize_textarea_field($p['external_condition'] ?? ''),
            'accessories'=>sanitize_textarea_field($p['accessories'] ?? ''), 'intake_notes'=>sanitize_textarea_field($p['intake_notes'] ?? ''),
            'status'=>'received', 'created_by'=>$staff_id, 'created_at'=>$now, 'updated_at'=>$now,
        ]);
        if (!$ok) {
            if ($client_request_id !== '') {
                $existing = $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . self::repairs_table() . ' WHERE client_request_id=%s', $client_request_id));
                if ($existing) {
                    if (!self::can_access($existing, $staff_id)) return new WP_Error('pcwork_repair_forbidden','Нямате права за този ремонт.',['status'=>403]);
                    return new WP_REST_Response(['data'=>self::present($existing, true),'message'=>'Заявката вече е обработена.'], 200);
                }
            }
            return new WP_Error('pcwork_repair_insert_failed','Ремонтът не беше записан. Опитайте отново.',['status'=>500]);
        }
        $id = (int)$wpdb->insert_id;
        $wpdb->insert(self::history_table(), ['repair_id'=>$id,'status'=>'received','note'=>'Устройството е прието в сервиза.','created_at'=>$now]);
        do_action('pcwork_repair_status_changed', $id, (int)$customer->ID, 'received', $number);
        $row = $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . self::repairs_table() . ' WHERE id=%d', $id));
        return new WP_REST_Response(['data'=>self::present($row, true),'message'=>'Ремонтът е регистриран.'], 201);
    }
    /** Private evidence storage MUST be outside the public web root. Configure PCWORK_PRIVATE_DIR in wp-config.php. */
    private static function private_dir() {
        if (!defined('PCWORK_PRIVATE_DIR') || !is_string(PCWORK_PRIVATE_DIR) || PCWORK_PRIVATE_DIR === '') {
            return new WP_Error('pcwork_private_storage_unconfigured', 'Защитеното хранилище не е конфигурирано. Добавете PCWORK_PRIVATE_DIR в wp-config.php.', ['status'=>503]);
        }
        $dir = rtrim(PCWORK_PRIVATE_DIR, '/\\');
        $real = realpath($dir);
        $webroot = realpath(ABSPATH);
        if ($real && $webroot && strpos($real . DIRECTORY_SEPARATOR, $webroot . DIRECTORY_SEPARATOR) === 0) {
            return new WP_Error('pcwork_private_storage_public', 'PCWORK_PRIVATE_DIR трябва да бъде извън публичната директория на сайта.', ['status'=>500]);
        }
        if (!$real) {
            if (!wp_mkdir_p($dir)) return new WP_Error('pcwork_private_storage_unwritable', 'Не може да се създаде защитената директория.', ['status'=>500]);
            $real = realpath($dir);
        }
        // Re-check after directory creation too, including symlink resolution.
        $webroot = realpath(ABSPATH);
        if (!$real || ($webroot && strpos($real . DIRECTORY_SEPARATOR, $webroot . DIRECTORY_SEPARATOR) === 0)) {
            return new WP_Error('pcwork_private_storage_public', 'PCWORK_PRIVATE_DIR трябва да бъде извън публичната директория на сайта.', ['status'=>500]);
        }
        if (!is_dir($real) || !is_writable($real)) return new WP_Error('pcwork_private_storage_unwritable', 'Защитената директория не е достъпна за запис.', ['status'=>500]);
        return $real;
    }
    private static function documents($repair_id) {
        global $wpdb;
        $rows = $wpdb->get_results($wpdb->prepare('SELECT id,kind,actor_user_id,created_at,mime_type,original_name,file_size,storage_key FROM ' . self::documents_table() . ' WHERE repair_id=%d ORDER BY id ASC', $repair_id), ARRAY_A);
        foreach ($rows ?: [] as &$row) {
            $row['id']=(int)$row['id']; $row['actor_user_id']=(int)$row['actor_user_id']; $row['file_size']=(int)$row['file_size'];
            // Legacy v1.2 attachments are intentionally not exposed as public URLs.
            $row['available'] = !empty($row['storage_key']);
            unset($row['storage_key']);
            $row['download_path'] = $row['available'] ? rest_url(self::NS . '/repairs/' . absint($repair_id) . '/documents/' . $row['id'] . '/download') : '';
        }
        return $rows ?: [];
    }
    private static function save_private_file($tmp_path, $kind, $repair_id, $actor_id, $original_name, $max_bytes) {
        global $wpdb;
        $dir = self::private_dir(); if (is_wp_error($dir)) return $dir;
        if (!is_file($tmp_path) || !is_readable($tmp_path)) return new WP_Error('pcwork_file_missing','Файлът не е достъпен.',['status'=>400]);
        $size = filesize($tmp_path); if (!$size || $size > $max_bytes) return new WP_Error('pcwork_file_size','Файлът е празен или надвишава разрешения размер.',['status'=>400]);
        $finfo = function_exists('finfo_open') ? finfo_open(FILEINFO_MIME_TYPE) : false;
        $mime = $finfo ? finfo_file($finfo, $tmp_path) : ''; if ($finfo) finfo_close($finfo);
        $allowed = ['image/png'=>'png','image/jpeg'=>'jpg','image/webp'=>'webp'];
        if (!isset($allowed[$mime])) return new WP_Error('pcwork_file_type','Позволени са само PNG, JPEG и WebP изображения.',['status'=>400]);
        $image = @getimagesize($tmp_path); if (!$image || empty($image['mime']) || $image['mime'] !== $mime) return new WP_Error('pcwork_file_invalid','Файлът не е валидно изображение.',['status'=>400]);
        $key = wp_generate_uuid4() . '.' . $allowed[$mime]; $target = trailingslashit($dir) . $key;
        if (!@rename($tmp_path, $target)) {
            if (!@copy($tmp_path, $target)) return new WP_Error('pcwork_file_store','Неуспешно записване в защитеното хранилище.',['status'=>500]);
            @unlink($tmp_path);
        }
        @chmod($target, 0640);
        $safe_name = sanitize_file_name(wp_basename($original_name));
        $ok = $wpdb->insert(self::documents_table(), [
            'repair_id'=>$repair_id, 'kind'=>$kind, 'attachment_id'=>0, 'storage_key'=>$key,
            'mime_type'=>$mime, 'original_name'=>$safe_name, 'file_size'=>$size,
            'actor_user_id'=>$actor_id, 'created_at'=>current_time('mysql')
        ]);
        if (!$ok) { @unlink($target); return new WP_Error('pcwork_document_db','Файлът е записан, но метаданните не бяха съхранени.',['status'=>500]); }
        return (int)$wpdb->insert_id;
    }
    private static function store_png_signature($data_uri, $repair_id, $kind, $actor_id) {
        if (!is_string($data_uri) || !preg_match('#^data:image/png;base64,#', $data_uri)) return new WP_Error('pcwork_signature_format','Подписът трябва да бъде PNG изображение.',['status'=>400]);
        $raw = base64_decode(substr($data_uri, strpos($data_uri, ',') + 1), true);
        if (!$raw || strlen($raw) > 2 * 1024 * 1024) return new WP_Error('pcwork_signature_size','Невалиден или прекалено голям подпис.',['status'=>400]);
        $tmp = tempnam(sys_get_temp_dir(), 'pcw'); if (!$tmp || file_put_contents($tmp, $raw) === false) return new WP_Error('pcwork_signature_temp','Неуспешна обработка на подписа.',['status'=>500]);
        $id = self::save_private_file($tmp, $kind, $repair_id, $actor_id, $kind . '.png', 2 * 1024 * 1024); if (file_exists($tmp)) @unlink($tmp); return $id;
    }
    public static function upload_evidence($request) {
        global $wpdb;
        $repair_id = absint($request['id']); $user_id = get_current_user_id();
        $repair = $wpdb->get_row($wpdb->prepare('SELECT * FROM '.self::repairs_table().' WHERE id=%d', $repair_id));
        if (!$repair) return new WP_Error('pcwork_repair_not_found','Ремонтът не е намерен.',['status'=>404]);
        if (!self::can_access($repair, $user_id)) return new WP_Error('pcwork_repair_forbidden','Нямате достъп до този ремонт.',['status'=>403]);
        $staff = self::is_staff($user_id); $saved = [];
        $params = $request->get_body_params(); if (!is_array($params)) $params = [];
        if (!empty($params['customer_signature'])) {
            $id = self::store_png_signature($params['customer_signature'], $repair_id, 'customer_signature', $user_id);
            if (is_wp_error($id)) return $id; $saved[] = ['kind'=>'customer_signature','document_id'=>$id];
        }
        if (!empty($params['staff_signature'])) {
            if (!$staff) return new WP_Error('pcwork_staff_signature_forbidden','Подписът на служителя може да бъде добавен само от служител.',['status'=>403]);
            $id = self::store_png_signature($params['staff_signature'], $repair_id, 'staff_signature', $user_id);
            if (is_wp_error($id)) return $id; $saved[] = ['kind'=>'staff_signature','document_id'=>$id];
        }
        if (!empty($_FILES['photos'])) {
            if (!$staff) return new WP_Error('pcwork_photo_forbidden','Снимки към приемния протокол може да добавя само служител.',['status'=>403]);
            $files = $_FILES['photos']; $count = is_array($files['name']) ? count($files['name']) : 1;
            if ($count > 6) return new WP_Error('pcwork_photo_limit','Може да качите до 6 снимки наведнъж.',['status'=>400]);
            for ($i=0; $i<$count; $i++) {
                $file = ['name'=>is_array($files['name'])?$files['name'][$i]:$files['name'],'type'=>is_array($files['type'])?$files['type'][$i]:$files['type'],'tmp_name'=>is_array($files['tmp_name'])?$files['tmp_name'][$i]:$files['tmp_name'],'error'=>is_array($files['error'])?$files['error'][$i]:$files['error'],'size'=>is_array($files['size'])?$files['size'][$i]:$files['size']];
                if ($file['error'] !== UPLOAD_ERR_OK || $file['size'] > 8*1024*1024) return new WP_Error('pcwork_photo_invalid','Снимката е невалидна или над 8 MB.',['status'=>400]);
                $id = self::save_private_file($file['tmp_name'], 'photo', $repair_id, $user_id, $file['name'], 8*1024*1024);
                if (is_wp_error($id)) return $id; $saved[] = ['kind'=>'photo','document_id'=>$id];
            }
        }
        if (!$saved) return new WP_Error('pcwork_evidence_empty','Няма подадени снимки или подписи.',['status'=>400]);
        return new WP_REST_Response(['data'=>['saved'=>$saved,'documents'=>self::documents($repair_id)],'message'=>'Документите са записани в защитеното хранилище.'], 201);
    }
    /** Store a generated PDF protocol in the private directory, never in public uploads. */
    public static function upload_protocol_pdf($request) {
        global $wpdb;
        $repair_id = absint($request['id']);
        $user_id = get_current_user_id();
        $repair = $wpdb->get_row($wpdb->prepare('SELECT * FROM '.self::repairs_table().' WHERE id=%d', $repair_id));
        if (!$repair) return new WP_Error('pcwork_repair_not_found','Ремонтът не е намерен.',['status'=>404]);
        if (!self::can_access($repair, $user_id)) return new WP_Error('pcwork_repair_forbidden','Нямате достъп до този ремонт.',['status'=>403]);
        $email_requested = !empty($request->get_param('send_email'));
        if ($email_requested && !self::is_staff($user_id)) return new WP_Error('pcwork_protocol_email_forbidden','Само служител може да изпрати протокола по имейл.',['status'=>403]);
        if ($email_requested && (!is_email($repair->customer_email))) return new WP_Error('pcwork_protocol_email_missing','За ремонта няма валиден имейл на клиента.',['status'=>400]);
        $files = $request->get_file_params();
        $file = $files['protocol_pdf'] ?? null;
        if (!$file || !is_array($file) || ($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
            return new WP_Error('pcwork_protocol_missing','Липсва PDF файл на протокола.',['status'=>400]);
        }
        if ((int)$file['size'] < 8 || (int)$file['size'] > 12 * 1024 * 1024) return new WP_Error('pcwork_protocol_size','PDF протоколът трябва да е до 12 MB.',['status'=>400]);
        $tmp = $file['tmp_name'];
        $head = @file_get_contents($tmp, false, null, 0, 5);
        if ($head !== '%PDF-') return new WP_Error('pcwork_protocol_type','Подаденият файл не е валиден PDF.',['status'=>400]);
        $dir = self::private_dir(); if (is_wp_error($dir)) return $dir;
        $key = wp_generate_uuid4() . '.pdf';
        $target = trailingslashit($dir) . $key;
        if (!@move_uploaded_file($tmp, $target) && !@copy($tmp, $target)) return new WP_Error('pcwork_protocol_store','Неуспешно записване на PDF протокола.',['status'=>500]);
        @chmod($target, 0640);
        $name = sanitize_file_name('PCWork_' . $repair->repair_number . '.pdf');
        $ok = $wpdb->insert(self::documents_table(), [
            'repair_id'=>$repair_id, 'kind'=>'protocol_pdf', 'attachment_id'=>0, 'storage_key'=>$key,
            'mime_type'=>'application/pdf', 'original_name'=>$name, 'file_size'=>filesize($target),
            'actor_user_id'=>$user_id, 'created_at'=>current_time('mysql')
        ]);
        if (!$ok) { @unlink($target); return new WP_Error('pcwork_protocol_db','PDF е записан, но не успяхме да запишем данните му.',['status'=>500]); }
        $document_id = (int)$wpdb->insert_id;
        $email_sent = false;
        if ($email_requested) {
            $to = sanitize_email($repair->customer_email);
            $subject = 'Сервизен протокол ' . $repair->repair_number . ' · PCWork';
            $message = '<p>Здравейте,</p><p>Прикачен е сервизният протокол за ремонт <strong>' . esc_html($repair->repair_number) . '</strong>.</p><p>PCWork · <a href="https://pcwork-bg.com">pcwork-bg.com</a></p>';
            $email_sent = wp_mail($to, $subject, $message, ['Content-Type: text/html; charset=UTF-8'], [$target]);
        }
        return new WP_REST_Response(['data'=>['document_id'=>$document_id,'documents'=>self::documents($repair_id),'email_requested'=>$email_requested,'email_sent'=>$email_sent], 'message'=>$email_requested ? ($email_sent ? 'PDF е записан и изпратен по имейл.' : 'PDF е записан, но изпращането на имейл не беше потвърдено.') : 'PDF протоколът е записан в защитеното хранилище.'], 201);
    }

    private static function accessible_repair($repair_id, $user_id) {
        global $wpdb; $row = $wpdb->get_row($wpdb->prepare('SELECT * FROM '.self::repairs_table().' WHERE id=%d', $repair_id));
        if (!$row) return new WP_Error('pcwork_repair_not_found','Ремонтът не е намерен.',['status'=>404]);
        if (!self::can_access($row, $user_id)) return new WP_Error('pcwork_repair_forbidden','Нямате достъп до този ремонт.',['status'=>403]);
        return $row;
    }
    public static function list_documents($request) {
        $repair = self::accessible_repair(absint($request['id']), get_current_user_id()); if (is_wp_error($repair)) return $repair;
        return rest_ensure_response(['data'=>self::documents($repair->id)]);
    }
    public static function download_document($request) {
        global $wpdb;
        $repair_id = absint($request['id']); $doc_id = absint($request['document_id']);
        $repair = self::accessible_repair($repair_id, get_current_user_id()); if (is_wp_error($repair)) return $repair;
        $doc = $wpdb->get_row($wpdb->prepare('SELECT * FROM '.self::documents_table().' WHERE id=%d AND repair_id=%d', $doc_id, $repair_id));
        if (!$doc) return new WP_Error('pcwork_document_not_found','Документът не е намерен.',['status'=>404]);
        if (empty($doc->storage_key)) return new WP_Error('pcwork_document_legacy','Този стар файл не е преместен в защитеното хранилище.',['status'=>410]);
        $dir = self::private_dir(); if (is_wp_error($dir)) return $dir;
        $key = wp_basename($doc->storage_key); $path = trailingslashit($dir) . $key;
        if (!is_file($path) || !is_readable($path)) return new WP_Error('pcwork_document_missing','Файлът липсва от защитеното хранилище.',['status'=>404]);
        $mime = in_array($doc->mime_type, ['image/png','image/jpeg','image/webp'], true) ? $doc->mime_type : 'application/octet-stream';
        $filename = sanitize_file_name($doc->original_name ?: ('pcwork-document-' . $doc_id));
        nocache_headers(); header('Content-Type: '.$mime); header('Content-Length: '.filesize($path)); header('Content-Disposition: attachment; filename="'.$filename.'"'); header('X-Content-Type-Options: nosniff');
        readfile($path); exit;
    }

    public static function update_status($request) {
        global $wpdb;
        $user_id = get_current_user_id();
        if (!self::is_staff($user_id)) return new WP_Error('pcwork_staff_required','Само оторизиран служител може да променя статуса.',['status'=>403]);
        $id = absint($request['id']);
        $row = $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . self::repairs_table() . ' WHERE id=%d', $id));
        if (!$row) return new WP_Error('pcwork_repair_not_found','Ремонтът не е намерен.',['status'=>404]);
        if (!self::can_access($row, $user_id) || (int)$row->customer_user_id === $user_id) return new WP_Error('pcwork_repair_forbidden','Нямате права за промяна на този ремонт.',['status'=>403]);
        $payload = $request->get_json_params(); if (!is_array($payload)) $payload = [];
        $client_request_id = sanitize_text_field($payload['client_request_id'] ?? '');
        if ($client_request_id !== '') {
            $already = $wpdb->get_var($wpdb->prepare('SELECT repair_id FROM ' . self::history_table() . ' WHERE client_request_id=%s LIMIT 1', $client_request_id));
            if ($already && (int)$already !== $id) return new WP_Error('pcwork_request_id_conflict','Идентификаторът на заявката вече е използван.',['status'=>409]);
            if ($already) {
                $fresh = $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . self::repairs_table() . ' WHERE id=%d', $id));
                return new WP_REST_Response(['data'=>self::present($fresh, true),'message'=>'Заявката вече е обработена.'], 200);
            }
        }
        $allowed = ['received','diagnostics','waiting_approval','in_repair','ready','completed','cancelled'];
        $status = sanitize_key($payload['status'] ?? '');
        if (!in_array($status, $allowed, true)) return new WP_Error('pcwork_invalid_status','Невалиден статус на ремонта.',['status'=>400]);
        $note = sanitize_textarea_field($payload['note'] ?? '');
        $now = current_time('mysql');
        $updated = $wpdb->update(self::repairs_table(), ['status'=>$status,'updated_at'=>$now], ['id'=>$id], ['%s','%s'], ['%d']);
        if ($updated === false) return new WP_Error('pcwork_status_update_failed','Статусът не беше записан.',['status'=>500]);
        $history_data = ['repair_id'=>$id,'status'=>$status,'note'=>$note,'created_at'=>$now];
        if ($client_request_id !== '') $history_data['client_request_id'] = $client_request_id;
        $history_inserted = $wpdb->insert(self::history_table(), $history_data);
        if ($client_request_id !== '' && $history_inserted === false) {
            $fresh = $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . self::repairs_table() . ' WHERE id=%d', $id));
            return new WP_REST_Response(['data'=>self::present($fresh, true),'message'=>'Заявката вече е обработена.'], 200);
        }
        do_action('pcwork_repair_status_changed', $id, (int)$row->customer_user_id, $status, (string)$row->repair_number);
        $fresh = $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . self::repairs_table() . ' WHERE id=%d', $id));
        return new WP_REST_Response(['data'=>self::present($fresh, true)], 200);
    }

    public static function list_technicians($request) {
        $user_id = get_current_user_id();
        if (!self::is_staff($user_id)) return new WP_Error('pcwork_staff_required','Само служители могат да преглеждат техници.',['status'=>403]);
        $location = sanitize_text_field($request->get_param('location_code') ?: '');
        if (!$location && !user_can($user_id, 'manage_options')) return new WP_Error('pcwork_location_required','Посочете сервизен обект.',['status'=>400]);
        if ($location && !user_can($user_id, 'manage_options')) {
            $allowed = get_user_meta($user_id, 'pcwork_location_codes', true); if (!is_array($allowed) || !in_array($location, array_map('strval',$allowed), true)) return new WP_Error('pcwork_location_forbidden','Нямате достъп до този обект.',['status'=>403]);
        }
        $users = get_users(['fields'=>['ID','display_name','user_email'],'number'=>200,'meta_key'=>'pcwork_location_codes']);
        $out=[];
        foreach ($users as $u) {
            if (!user_can($u->ID,'pcwork_manage_repairs') && !user_can($u->ID,'manage_options')) continue;
            $codes=get_user_meta($u->ID,'pcwork_location_codes',true); if (!is_array($codes)) $codes=[];
            if ($location && !user_can($u->ID,'manage_options') && !in_array($location,array_map('strval',$codes),true)) continue;
            $out[]=['id'=>(int)$u->ID,'name'=>$u->display_name,'email'=>$u->user_email];
        }
        return rest_ensure_response(['data'=>$out]);
    }

    public static function get_staff_schedules($request) {
        $actor = get_current_user_id();
        if (!self::is_staff($actor)) return new WP_Error('pcwork_staff_required','Само служители могат да преглеждат графици.',['status'=>403]);
        $all = get_option('pcwork_technician_schedules', []);
        if (!is_array($all)) $all = [];
        if (!user_can($actor, 'manage_options')) {
            $own = get_user_meta($actor, 'pcwork_location_codes', true); if (!is_array($own)) $own = [];
            $visible = [];
            foreach ($all as $id => $schedule) {
                $codes = get_user_meta((int)$id, 'pcwork_location_codes', true); if (!is_array($codes)) $codes = [];
                if ((int)$id === $actor || array_intersect(array_map('strval',$own), array_map('strval',$codes))) $visible[(string)$id] = $schedule;
            }
            $all = $visible;
        }
        return rest_ensure_response(['data'=>$all]);
    }

    public static function save_staff_schedule($request) {
        $actor = get_current_user_id();
        if (!user_can($actor, 'manage_options')) return new WP_Error('pcwork_admin_required','Само администратор може да променя работни графици и отсъствия.',['status'=>403]);
        $payload = $request->get_json_params(); if (!is_array($payload)) $payload = [];
        $technician = absint($payload['technician_id'] ?? 0);
        $user = get_user_by('id', $technician);
        if (!$technician || !$user || (!user_can($technician,'pcwork_manage_repairs') && !user_can($technician,'manage_options'))) return new WP_Error('pcwork_technician_invalid','Невалиден техник.',['status'=>400]);
        $input = is_array($payload['schedule'] ?? null) ? $payload['schedule'] : [];
        $days = array_values(array_unique(array_filter(array_map('intval', (array)($input['working_days'] ?? [1,2,3,4,5])), static function($d){ return $d >= 1 && $d <= 7; })));
        sort($days);
        $start = sanitize_text_field($input['start_time'] ?? '09:00');
        $end = sanitize_text_field($input['end_time'] ?? '18:00');
        if (!preg_match('/^(?:[01]\d|2[0-3]):[0-5]\d$/', $start) || !preg_match('/^(?:[01]\d|2[0-3]):[0-5]\d$/', $end) || $start >= $end) return new WP_Error('pcwork_schedule_time_invalid','Невалиден часови диапазон.',['status'=>400]);
        $absences = array_values(array_unique(array_filter(array_map('sanitize_text_field', (array)($input['absences'] ?? [])), static function($date){ return (bool)preg_match('/^\d{4}-\d{2}-\d{2}$/', $date); })));
        $all = get_option('pcwork_technician_schedules', []); if (!is_array($all)) $all = [];
        $all[(string)$technician] = ['working_days'=>$days, 'start_time'=>$start, 'end_time'=>$end, 'absences'=>$absences, 'updated_at'=>current_time('mysql')];
        update_option('pcwork_technician_schedules', $all, false);
        return rest_ensure_response(['success'=>true, 'data'=>$all[(string)$technician]]);
    }

    private static function staff_table($suffix) { global $wpdb; return $wpdb->prefix . 'pcwork_staff_' . $suffix; }

    public static function staff_overview($request) {
        global $wpdb;
        $actor=get_current_user_id(); if (!self::is_staff($actor)) return new WP_Error('pcwork_staff_required','Само служители могат да преглеждат статистиката.',['status'=>403]);
        $repairs=self::repairs_table(); $attendance=self::staff_table('attendance'); $leave=self::staff_table('leave');
        $today=current_time('Y-m-d'); $since=wp_date('Y-m-d H:i:s', current_time('timestamp')-30*DAY_IN_SECONDS);
        $where=''; $params=[];
        if (!user_can($actor,'manage_options')) {
            $codes=get_user_meta($actor,'pcwork_location_codes',true); if (!is_array($codes)) $codes=[];
            if (!$codes) return rest_ensure_response(['data'=>['active_repairs'=>0,'completed_30d'=>0,'attendance_today'=>[],'pending_leave'=>0,'technician_stats'=>[]]]);
            $marks=implode(',',array_fill(0,count($codes),'%s')); $where=" AND location_code IN ($marks)"; $params=array_map('strval',$codes);
        }
        $active_sql="SELECT COUNT(*) FROM $repairs WHERE status NOT IN ('completed','cancelled','ready') $where";
        $active=(int)($params ? $wpdb->get_var($wpdb->prepare($active_sql,$params)) : $wpdb->get_var($active_sql));
        $completed_sql="SELECT COUNT(*) FROM $repairs WHERE status='completed' AND updated_at >= %s $where";
        $completed=(int)$wpdb->get_var($wpdb->prepare($completed_sql,array_merge([$since],$params)));
        $attendance_today=$wpdb->get_results($wpdb->prepare("SELECT a.id,a.user_id,a.check_in,a.check_out,u.display_name FROM $attendance a LEFT JOIN {$wpdb->users} u ON u.ID=a.user_id WHERE DATE(a.check_in)=%s ORDER BY a.check_in DESC",$today),ARRAY_A);
        $pending=(int)$wpdb->get_var("SELECT COUNT(*) FROM $leave WHERE status='pending'");
        $stats_sql="SELECT assigned_technician_id AS technician_id, COUNT(*) AS completed_count FROM $repairs WHERE status='completed' AND updated_at >= %s AND assigned_technician_id>0 $where GROUP BY assigned_technician_id ORDER BY completed_count DESC";
        $stats=$wpdb->get_results($wpdb->prepare($stats_sql,array_merge([$since],$params)),ARRAY_A);
        if (!user_can($actor,'manage_options')) {
            $visible=[];
            foreach ((array)$attendance_today as $entry) { $codes=get_user_meta((int)$entry['user_id'],'pcwork_location_codes',true); if (is_array($codes) && array_intersect(array_map('strval',$codes),array_map('strval',$params))) $visible[]=$entry; }
            $attendance_today=$visible;
        }
        foreach ($stats as &$row) { $u=get_user_by('id',(int)$row['technician_id']); $row['technician_name']=$u?$u->display_name:'#'.$row['technician_id']; $row['completed_count']=(int)$row['completed_count']; } unset($row);
        return rest_ensure_response(['data'=>['active_repairs'=>$active,'completed_30d'=>$completed,'attendance_today'=>$attendance_today?:[],'pending_leave'=>$pending,'is_admin'=>user_can($actor,'manage_options'),'technician_stats'=>$stats?:[]]]);
    }

    public static function get_attendance($request) {
        global $wpdb; $actor=get_current_user_id(); if (!self::is_staff($actor)) return new WP_Error('pcwork_staff_required','Само служители могат да преглеждат присъствия.',['status'=>403]);
        $row=$wpdb->get_row($wpdb->prepare('SELECT * FROM '.self::staff_table('attendance').' WHERE user_id=%d AND check_out IS NULL ORDER BY id DESC LIMIT 1',$actor),ARRAY_A);
        return rest_ensure_response(['data'=>['active'=>$row?:null]]);
    }

    public static function record_attendance($request) {
        global $wpdb; $actor=get_current_user_id(); if (!self::is_staff($actor)) return new WP_Error('pcwork_staff_required','Само служители могат да записват присъствие.',['status'=>403]);
        $p=$request->get_json_params(); $action=sanitize_key($p['action']??''); $table=self::staff_table('attendance'); $now=current_time('mysql');
        $active=$wpdb->get_row($wpdb->prepare("SELECT * FROM $table WHERE user_id=%d AND check_out IS NULL ORDER BY id DESC LIMIT 1",$actor));
        if ($action==='check_in') {
            if ($active) return new WP_Error('pcwork_already_checked_in','Имате вече активна смяна.',['status'=>409]);
            $ok=$wpdb->insert($table,['user_id'=>$actor,'check_in'=>$now,'created_at'=>$now],['%d','%s','%s']);
            if (!$ok) return new WP_Error('pcwork_attendance_failed','Неуспешен запис на началото на смяната.',['status'=>500]);
        } elseif ($action==='check_out') {
            if (!$active) return new WP_Error('pcwork_not_checked_in','Няма активна смяна за приключване.',['status'=>409]);
            $ok=$wpdb->update($table,['check_out'=>$now],['id'=>(int)$active->id],['%s'],['%d']);
            if ($ok===false) return new WP_Error('pcwork_attendance_failed','Неуспешен запис на края на смяната.',['status'=>500]);
        } else return new WP_Error('pcwork_attendance_action','Невалидно действие.',['status'=>400]);
        return rest_ensure_response(['success'=>true,'message'=>$action==='check_in'?'Смяната е започната.':'Смяната е приключена.']);
    }

    public static function list_leave_requests($request) {
        global $wpdb; $actor=get_current_user_id(); if (!self::is_staff($actor)) return new WP_Error('pcwork_staff_required','Само служители могат да преглеждат отпуски.',['status'=>403]);
        $table=self::staff_table('leave');
        if (user_can($actor,'manage_options')) $rows=$wpdb->get_results("SELECT l.*,u.display_name FROM $table l LEFT JOIN {$wpdb->users} u ON u.ID=l.user_id ORDER BY l.created_at DESC LIMIT 100",ARRAY_A);
        else $rows=$wpdb->get_results($wpdb->prepare("SELECT l.*,u.display_name FROM $table l LEFT JOIN {$wpdb->users} u ON u.ID=l.user_id WHERE l.user_id=%d ORDER BY l.created_at DESC LIMIT 50",$actor),ARRAY_A);
        return rest_ensure_response(['data'=>$rows?:[]]);
    }

    public static function create_leave_request($request) {
        global $wpdb; $actor=get_current_user_id(); if (!self::is_staff($actor)) return new WP_Error('pcwork_staff_required','Само служители могат да заявяват отпуск.',['status'=>403]);
        $p=$request->get_json_params(); $start=sanitize_text_field($p['start_date']??''); $end=sanitize_text_field($p['end_date']??''); $reason=sanitize_textarea_field($p['reason']??'');
        if (!preg_match('/^\\d{4}-\\d{2}-\\d{2}$/',$start) || !preg_match('/^\\d{4}-\\d{2}-\\d{2}$/',$end) || $end<$start) return new WP_Error('pcwork_leave_dates','Невалиден период на отпуската.',['status'=>400]);
        $ok=$wpdb->insert(self::staff_table('leave'),['user_id'=>$actor,'start_date'=>$start,'end_date'=>$end,'reason'=>$reason,'status'=>'pending','created_at'=>current_time('mysql')],['%d','%s','%s','%s','%s','%s']);
        if (!$ok) return new WP_Error('pcwork_leave_failed','Заявката за отпуск не беше записана.',['status'=>500]);
        return new WP_REST_Response(['success'=>true,'id'=>(int)$wpdb->insert_id],201);
    }

    public static function review_leave_request($request) {
        global $wpdb; $actor=get_current_user_id(); if (!user_can($actor,'manage_options')) return new WP_Error('pcwork_admin_required','Само администратор може да одобрява отпуски.',['status'=>403]);
        $id=absint($request['id']); $p=$request->get_json_params(); $status=sanitize_key($p['status']??'');
        if (!in_array($status,['approved','rejected'],true)) return new WP_Error('pcwork_leave_status','Невалиден статус на заявката.',['status'=>400]);
        $ok=$wpdb->update(self::staff_table('leave'),['status'=>$status,'reviewed_by'=>$actor,'reviewed_at'=>current_time('mysql')],['id'=>$id,'status'=>'pending'],['%s','%d','%s'],['%d','%s']);
        if (!$ok) return new WP_Error('pcwork_leave_not_pending','Заявката не е намерена или вече е обработена.',['status'=>404]);
        return rest_ensure_response(['success'=>true,'status'=>$status]);
    }

    public static function update_assignment($request) {
        global $wpdb;
        $actor=get_current_user_id(); if (!self::is_staff($actor)) return new WP_Error('pcwork_staff_required','Само служители могат да разпределят ремонти.',['status'=>403]);
        $id=absint($request['id']);
        $row=$wpdb->get_row($wpdb->prepare('SELECT * FROM '.self::repairs_table().' WHERE id=%d',$id));
        if (!$row) return new WP_Error('pcwork_repair_not_found','Ремонтът не е намерен.',['status'=>404]);
        if (!self::can_access($row,$actor) || (int)$row->customer_user_id===$actor) return new WP_Error('pcwork_repair_forbidden','Нямате права за този ремонт.',['status'=>403]);
        $p=$request->get_json_params(); if (!is_array($p)) $p=[];
        $technician=absint($p['assigned_technician_id'] ?? 0);
        $priority=sanitize_key($p['priority'] ?? 'normal');
        if (!in_array($priority,['low','normal','high','urgent'],true)) return new WP_Error('pcwork_priority_invalid','Невалиден приоритет.',['status'=>400]);
        $due_raw=sanitize_text_field($p['due_at'] ?? ''); $due=null;
        if ($due_raw!=='') { $ts=strtotime($due_raw); if (!$ts) return new WP_Error('pcwork_due_invalid','Невалиден срок. Използвайте ISO дата/час.',['status'=>400]); $due=gmdate('Y-m-d H:i:s',$ts); }
        if ($technician) {
            $u=get_user_by('id',$technician); $codes=get_user_meta($technician,'pcwork_location_codes',true); if (!is_array($codes)) $codes=[];
            if (!$u || (!user_can($technician,'pcwork_manage_repairs') && !user_can($technician,'manage_options')) || (!user_can($technician,'manage_options') && !in_array((string)$row->location_code,array_map('strval',$codes),true))) return new WP_Error('pcwork_technician_invalid','Избраният техник няма достъп до този сервизен обект.',['status'=>400]);
        }
        $ok=$wpdb->update(self::repairs_table(),['assigned_technician_id'=>$technician,'priority'=>$priority,'due_at'=>$due,'updated_at'=>current_time('mysql')],['id'=>$id],['%d','%s','%s','%s'],['%d']);
        if ($ok===false) return new WP_Error('pcwork_assignment_failed','Разпределението не беше записано.',['status'=>500]);
        $wpdb->insert(self::history_table(),['repair_id'=>$id,'status'=>(string)$row->status,'note'=>sprintf('Назначен техник ID %d; приоритет: %s; срок: %s',$technician,$priority,$due ?: 'няма'),'created_at'=>current_time('mysql')]);
        $fresh=$wpdb->get_row($wpdb->prepare('SELECT * FROM '.self::repairs_table().' WHERE id=%d',$id));
        return rest_ensure_response(['data'=>self::present($fresh,true),'message'=>'Назначението и срокът са записани.']);
    }

    public static function get_repair($request) {
        global $wpdb; $id = absint($request['id']);
        $row = $wpdb->get_row($wpdb->prepare('SELECT * FROM ' . self::repairs_table() . ' WHERE id=%d', $id));
        if (!$row) return new WP_Error('pcwork_repair_not_found','Ремонтът не е намерен.',['status'=>404]);
        if (!self::can_access($row, get_current_user_id())) return new WP_Error('pcwork_repair_forbidden','Нямате достъп до този ремонт.',['status'=>403]);
        return rest_ensure_response(['data'=>self::present($row, true)]);
    }
}
PCWork_Mobile_Repairs_API::init();
