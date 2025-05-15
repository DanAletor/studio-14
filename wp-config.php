<?php
define('DB_NAME', 'wpdb');
define('DB_USER', 'mysql');
define('DB_PASSWORD', 'ea852e0ddce00fab');
define('DB_HOST', 'wpdb:3306');
define('DB_CHARSET', 'utf8');
define('DB_COLLATE', '');

$table_prefix  = 'wp_';
define('WP_DEBUG', false);

// Absolute path to the WordPress directory.
if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}

// Sets up WordPress vars and included files.
require_once ABSPATH . 'wp-settings.php';

