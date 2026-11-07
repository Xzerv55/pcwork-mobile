# PCWork Mobile WordPress Plugin v4.6.0

## Administrative panel consolidation
- Removed the standalone “Достъп без код” submenu and integrated it as a tab inside “Клиенти”.
- Customer list now includes direct profile editing and displays password-without-OTP access state.
- Customer profile editor supports display name, phone, billing address and shipping address. Registration email is explicitly read-only.
- Customer deletion is available to administrators with a confirmation step. It removes the selected customer account and associated repair rows, repair history, document metadata and worklog rows. It never allows deleting the currently logged-in administrator.
- Repair administration now supports editing device type/model, serial number, customer phone, problem description and intake notes in addition to status, technician, priority and due date.
- Repair deletion removes the repair and its related history, document metadata and worklog entries after nonce and capability checks.
- Added a narrowly scoped database cleanup action that deletes only orphaned repair history/document/worklog rows; it does not delete customers or repairs.
- All destructive actions require administrator capability and a WordPress nonce; UI confirmation is shown before deletion.

## Important
- Back up the WordPress database before updating or using deletion/cleanup actions.
- Deleting a customer also deletes all repairs linked to that customer; this is irreversible.
- The cleanup tool removes orphaned relational rows only. It does not attempt broad database purges or delete media files from the WordPress Media Library.
- PHP syntax and ZIP integrity checked. Live WordPress/WooCommerce behavior was not tested in this environment.
