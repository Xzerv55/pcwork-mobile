<?php
if (!defined('ABSPATH')) exit;

/** Mobile storefront proxy. WooCommerce credentials and order operations stay server-side. */
final class PCWork_WooCommerce_Mobile_API {
    public static function init() { add_action('rest_api_init', [__CLASS__, 'routes']); }
    public static function routes() {
        register_rest_route('pcwork/v1', '/shop/products', ['methods'=>'GET','callback'=>[__CLASS__,'products'],'permission_callback'=>'__return_true']);
        register_rest_route('pcwork/v1', '/shop/products/(?P<id>\\d+)/variations', ['methods'=>'GET','callback'=>[__CLASS__,'variations'],'permission_callback'=>'__return_true']);
        register_rest_route('pcwork/v1', '/shop/categories', ['methods'=>'GET','callback'=>[__CLASS__,'categories'],'permission_callback'=>'__return_true']);
        register_rest_route('pcwork/v1', '/shop/orders', ['methods'=>'GET','callback'=>[__CLASS__,'orders'],'permission_callback'=>['PCWork_Mobile_Auth_Bridge','authorize']]);
        register_rest_route('pcwork/v1', '/shop/orders', ['methods'=>'POST','callback'=>[__CLASS__,'create_order'],'permission_callback'=>['PCWork_Mobile_Auth_Bridge','authorize']]);
        register_rest_route('pcwork/v1', '/shop/orders/(?P<id>\\d+)', ['methods'=>'GET','callback'=>[__CLASS__,'order_detail'],'permission_callback'=>['PCWork_Mobile_Auth_Bridge','authorize']]);
    }
    private static function ready() {
        if (!class_exists('WooCommerce') || !function_exists('wc_get_products')) return new WP_Error('pcw_wc_missing','WooCommerce не е инсталиран или активен.',['status'=>503]);
        if (class_exists('PCWork_Admin_Integration_Settings')) {
            $settings = PCWork_Admin_Integration_Settings::get_settings();
            if (empty($settings['woocommerce_enabled'])) return new WP_Error('pcw_wc_disabled','WooCommerce интеграцията е изключена от администратора.',['status'=>503]);
        }
        return true;
    }
    private static function product_data($product) {
        // Keep catalogue responses lightweight: variable products can have
        // hundreds of variations, so load those only on the product detail view.
        $image = wp_get_attachment_image_url($product->get_image_id(), 'woocommerce_thumbnail');
        return [
            'id'=>(int)$product->get_id(),
            'name'=>wp_strip_all_tags($product->get_name()),
            'slug'=>$product->get_slug(),
            'description'=>wp_strip_all_tags($product->get_short_description()),
            'price'=>$product->get_price(),
            'regular_price'=>$product->get_regular_price(),
            'sale_price'=>$product->get_sale_price(),
            'currency'=>get_woocommerce_currency(),
            'image'=>$image ?: '',
            'permalink'=>get_permalink($product->get_id()),
            'stock_status'=>$product->get_stock_status(),
            'stock_quantity'=>$product->get_stock_quantity(),
            'type'=>$product->get_type(),
            'purchasable'=>(bool)$product->is_purchasable() && (bool)$product->is_in_stock(),
            'on_sale'=>(bool)$product->is_on_sale(),
            'variations'=>[]
        ];
    }

    public static function products($request) {
        $ready=self::ready(); if (is_wp_error($ready)) return $ready;
        $per_page=max(1,min(20,(int)$request->get_param('per_page') ?: 20));
        $search=sanitize_text_field((string)$request->get_param('search'));
        $category=absint($request->get_param('category'));
        $cache_key='pcw_mobile_shop_products_' . md5($per_page . '|' . $search . '|' . $category);
        $cached=get_transient($cache_key);
        if (is_array($cached)) return rest_ensure_response($cached);
        $args=['status'=>'publish','limit'=>$per_page,'orderby'=>'menu_order','order'=>'ASC','return'=>'objects'];
        if ($search!=='') $args['s']=$search;
        if ($category) { $term=get_term($category,'product_cat'); if ($term && !is_wp_error($term)) $args['category']=[$term->slug]; }
        $items=array_map([__CLASS__,'product_data'],wc_get_products($args));
        $payload=['data'=>$items,'count'=>count($items),'currency'=>get_woocommerce_currency()];
        set_transient($cache_key,$payload,45);
        return rest_ensure_response($payload);
    }

    public static function variations($request) {
        $ready=self::ready(); if (is_wp_error($ready)) return $ready;
        $product=wc_get_product(absint($request['id']));
        if (!$product || $product->get_status() !== 'publish' || !$product->is_type('variable')) {
            return new WP_Error('pcw_product_not_variable','Продуктът не е намерен или няма варианти.',['status'=>404]);
        }
        $rows=[];
        // Read child IDs directly and cap the response; get_available_variations()
        // builds a much larger formatted structure for every child variation.
        $variation_ids=array_slice($product->get_children(),0,50);
        foreach ($variation_ids as $variation_id) {
            $variation_product=wc_get_product($variation_id);
            if (!$variation_product || $variation_product->get_status() !== 'publish') continue;
            $attributes=[];
            foreach ((array)$variation_product->get_variation_attributes() as $key=>$value) {
                $label=wc_attribute_label(str_replace('attribute_','',$key),$product);
                $attributes[$label]=$value !== '' ? wc_clean($value) : '';
            }
            $rows[]=[
                'id'=>(int)$variation_product->get_id(),
                'attributes'=>$attributes,
                'price'=>$variation_product->get_price(),
                'regular_price'=>$variation_product->get_regular_price(),
                'in_stock'=>(bool)$variation_product->is_in_stock(),
                'purchasable'=>(bool)$variation_product->is_purchasable(),
                'stock_quantity'=>$variation_product->get_stock_quantity(),
            ];
        }
        return rest_ensure_response(['data'=>$rows]);
    }
    public static function categories() {
        $ready=self::ready(); if (is_wp_error($ready)) return $ready;
        $cached=get_transient('pcw_mobile_shop_categories_v1');
        if (is_array($cached)) return rest_ensure_response(['data'=>$cached]);
        $terms=get_terms(['taxonomy'=>'product_cat','hide_empty'=>true,'orderby'=>'name','order'=>'ASC']); if (is_wp_error($terms)) return $terms;
        $rows=[]; foreach($terms as $term) $rows[]=['id'=>(int)$term->term_id,'name'=>$term->name,'slug'=>$term->slug,'parent'=>(int)$term->parent,'count'=>(int)$term->count];
        set_transient('pcw_mobile_shop_categories_v1',$rows,5 * MINUTE_IN_SECONDS);
        return rest_ensure_response(['data'=>$rows]);
    }
    public static function orders() {
        $ready=self::ready(); if (is_wp_error($ready)) return $ready;
        $customer_id=get_current_user_id();
        $orders=wc_get_orders(['customer_id'=>$customer_id,'limit'=>30,'orderby'=>'date','order'=>'DESC']);
        $rows=[]; foreach($orders as $order) $rows[]=['id'=>$order->get_id(),'number'=>$order->get_order_number(),'date'=>$order->get_date_created() ? $order->get_date_created()->date_i18n('d.m.Y H:i') : '', 'status'=>wc_get_order_status_name($order->get_status()),'total'=>$order->get_total(),'currency'=>$order->get_currency(),'payment_url'=>$order->get_checkout_payment_url()];
        return rest_ensure_response(['data'=>$rows]);
    }
    public static function order_detail($request) {
        $ready=self::ready(); if (is_wp_error($ready)) return $ready;
        $order=wc_get_order(absint($request['id']));
        if (!$order || (int)$order->get_customer_id() !== get_current_user_id()) return new WP_Error('pcw_order_not_found','Поръчката не е намерена.',['status'=>404]);
        $items=[];
        foreach ($order->get_items() as $item) {
            $items[]=['name'=>wp_strip_all_tags($item->get_name()),'quantity'=>(int)$item->get_quantity(),'price'=>wc_format_decimal($item->get_total() / max(1,$item->get_quantity()),2),'total'=>wc_format_decimal($item->get_total(),2)];
        }
        return rest_ensure_response(['data'=>['id'=>$order->get_id(),'number'=>$order->get_order_number(),'date'=>$order->get_date_created() ? $order->get_date_created()->date_i18n('d.m.Y H:i') : '', 'status'=>wc_get_order_status_name($order->get_status()),'total'=>$order->get_total(),'currency'=>$order->get_currency(),'payment_url'=>$order->get_checkout_payment_url(),'items'=>$items]]);
    }
    public static function create_order($request) {
        $ready=self::ready(); if (is_wp_error($ready)) return $ready;
        $user_id=get_current_user_id(); if (!$user_id) return new WP_Error('pcw_order_login','Влезте в профила си, за да направите поръчка.',['status'=>401]);
        $items=$request->get_param('items'); if (!is_array($items) || !$items || count($items)>50) return new WP_Error('pcw_order_items','Количката е празна или съдържа твърде много артикули.',['status'=>400]);
        try {
            $order=wc_create_order(['customer_id'=>$user_id,'created_via'=>'pcwork_mobile']);
            $shipping_contents=[]; $shipping_cost=0.0; $needs_shipping=false;
            if (is_wp_error($order)) return $order;
            foreach($items as $line) {
                $product_id=absint($line['product_id'] ?? 0); $qty=max(1,min(99,absint($line['quantity'] ?? 1)));
                $product=wc_get_product($product_id);
                $variation_id=absint($line['variation_id'] ?? 0);
                if (!$product || !$product->is_purchasable()) throw new Exception('Продуктът с номер '.$product_id.' вече не е наличен за покупка.');
                if ($product->is_type('variable')) {
                    if (!$variation_id) throw new Exception('Изберете вариант за: '.$product->get_name());
                    $variation=wc_get_product($variation_id);
                    if (!$variation || (int)$variation->get_parent_id() !== $product_id || !$variation->is_purchasable() || !$variation->is_in_stock()) throw new Exception('Избраният вариант вече не е наличен за: '.$product->get_name());
                    $product=$variation;
                } elseif ($product->is_type('simple')) {
                    if ($variation_id) throw new Exception('Невалиден вариант за продукт: '.$product->get_name());
                    if (!$product->is_in_stock()) throw new Exception('Продуктът '.$product->get_name().' е изчерпан.');
                } else {
                    throw new Exception('Този тип продукт не може да бъде поръчан от приложението.');
                }
                if (!$product->is_sold_individually() && !$product->has_enough_stock($qty)) throw new Exception('Недостатъчна наличност за: '.$product->get_name());
                if ($product->is_sold_individually()) $qty=1;
                $added=$order->add_product($product,$qty);
                if ($product->needs_shipping()) { $needs_shipping=true; $line_cost=(float)$product->get_price()*$qty; $shipping_cost += $line_cost; $shipping_contents['pcw_'.$product->get_id()]=['data'=>$product,'quantity'=>$qty,'line_total'=>$line_cost,'line_subtotal'=>$line_cost,'line_tax'=>0,'line_subtotal_tax'=>0]; }
                if (!$added) throw new Exception('Неуспешно добавяне на продукт: '.$product->get_name());
            }
            $billing=self::clean_address((array)$request->get_param('billing'));
            $shipping=self::clean_address((array)$request->get_param('shipping'));
            if (empty($billing['first_name']) || !is_email($billing['email']) || empty($billing['phone']) || empty($billing['address_1']) || empty($billing['city'])) throw new Exception('Моля, попълнете коректно данните за контакт и доставка.');
            $order->set_address($billing,'billing'); $order->set_address($shipping ?: $billing,'shipping');
            if ($needs_shipping) self::add_shipping_rate($order,$shipping,$shipping_contents,$shipping_cost,$user_id);
            $order->update_meta_data('_pcwork_mobile_order','yes');
            $order->calculate_totals(); $order->set_status('pending'); $order->save();
            return new WP_REST_Response(['data'=>['id'=>$order->get_id(),'number'=>$order->get_order_number(),'status'=>wc_get_order_status_name($order->get_status()),'total'=>$order->get_total(),'currency'=>$order->get_currency(),'payment_url'=>$order->get_checkout_payment_url(),'message'=>'Поръчката е създадена.']],201);
        } catch(Throwable $e) {
            if (isset($order) && $order instanceof WC_Order) $order->delete(true);
            return new WP_Error('pcw_order_failed',$e->getMessage(),['status'=>400]);
        }
    }
    private static function add_shipping_rate($order,$address,$contents,$contents_cost,$user_id) {
        if (!function_exists('WC') || !WC()->shipping()) throw new Exception('Доставката не може да бъде изчислена. Проверете настройките за доставка в WooCommerce.');
        $destination=['country'=>$address['country'] ?? 'BG','state'=>$address['state'] ?? '', 'postcode'=>$address['postcode'] ?? '', 'city'=>$address['city'] ?? '', 'address'=>$address['address_1'] ?? '', 'address_2'=>$address['address_2'] ?? ''];
        $package=['contents'=>$contents,'contents_cost'=>$contents_cost,'applied_coupons'=>[],'user'=>['ID'=>$user_id],'destination'=>$destination];
        WC()->shipping()->calculate_shipping([$package]);
        $packages=WC()->shipping()->get_packages(); $rates=$packages[0]['rates'] ?? [];
        if (!$rates) throw new Exception('Няма наличен метод за доставка за този адрес. Проверете зоните и методите за доставка в WooCommerce.');
        uasort($rates,function($a,$b){ return (float)$a->get_cost() <=> (float)$b->get_cost(); });
        $rate=reset($rates); $shipping_item=new WC_Order_Item_Shipping();
        $shipping_item->set_method_title($rate->get_label()); $shipping_item->set_method_id($rate->get_method_id());
        if (method_exists($rate,'get_instance_id')) $shipping_item->set_instance_id($rate->get_instance_id());
        $shipping_item->set_total((float)$rate->get_cost());
        if (method_exists($rate,'get_taxes')) $shipping_item->set_taxes(['total'=>$rate->get_taxes()]);
        $order->add_item($shipping_item);
    }
    private static function clean_address($input) {
        $keys=['first_name','last_name','company','address_1','address_2','city','state','postcode','country','email','phone']; $out=[];
        foreach($keys as $key) { $value=(string)($input[$key] ?? ''); $out[$key]=$key==='email' ? sanitize_email($value) : sanitize_text_field($value); }
        return $out;
    }
}
PCWork_WooCommerce_Mobile_API::init();
