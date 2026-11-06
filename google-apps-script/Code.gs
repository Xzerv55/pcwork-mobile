/**
 * PCWork Google Sheets webhook – Security v2.6.0
 *
 * Required Script Properties:
 *   PCWORK_HMAC_SECRET      - same value as WordPress PCWork HMAC Secret
 *   PCWORK_SPREADSHEET_ID  - existing spreadsheet ID
 *   PCWORK_SHEET_NAME      - optional; defaults to Repairs
 *
 * Deploy as Web App: Execute as Me; Who has access: Anyone.
 * POST payload is a URL-encoded `payload` field containing exact JSON.
 * HMAC-SHA256 covers timestamp + "." + nonce + "." + exact JSON payload.
 */
var PCWORK_SECURITY_VERSION = '2.6.0';
var PCWORK_MAX_BODY_BYTES = 65536;
var PCWORK_MAX_CLOCK_SKEW_SECONDS = 300;
var PCWORK_NONCE_TTL_SECONDS = 600;
var PCWORK_MAX_REQUESTS_PER_MINUTE = 120;
var PCWORK_HEADERS = [
  'Repair ID', 'Repair Number', 'Customer', 'Email', 'Phone',
  'Location Code', 'Service Location', 'Device Type', 'Device Model',
  'Serial Number', 'Problem Description', 'External Condition',
  'Accessories', 'Status', 'Technician ID', 'Priority', 'Due At',
  'Created At', 'Updated At', 'Last Synced At'
];

function doGet() {
  return pcwJson_({ok: true, service: 'PCWork Google Sheets webhook', version: PCWORK_SECURITY_VERSION});
}

function doPost(e) {
  var requestId = Utilities.getUuid();
  try {
    var params = (e && e.parameter) ? e.parameter : {};
    var rawBody = '';
    var postContents = (e && e.postData && typeof e.postData.contents === 'string') ? e.postData.contents : '';
    var postType = (e && e.postData && e.postData.type) ? String(e.postData.type).toLowerCase() : '';
    if (postContents !== '') {
      if (postType.indexOf('application/x-www-form-urlencoded') !== -1) {
        // Prefer Apps Script's decoded form parameter, otherwise decode the
        // POST body directly. Do not HMAC the transport wrapper; HMAC the JSON.
        rawBody = (typeof params.payload === 'string' && params.payload !== '')
          ? params.payload : pcwFormValue_(postContents, 'payload');
      } else {
        rawBody = postContents;
      }
    }
    // Last-resort compatibility for gateways that expose POST fields only in
    // the event parameter map. The HMAC still authenticates the exact JSON.
    if (rawBody === '' && typeof params.payload === 'string') rawBody = params.payload;
    if (rawBody === '') {
      var parameterNames = Object.keys(params || {}).sort().join(',');
      console.warn('[PCWork Security] rejected request ' + requestId + ': missing_post_data; has_event=' + Boolean(e) + '; has_parameters=' + Boolean(e && e.parameter) + '; has_post_data=' + Boolean(e && e.postData) + '; post_type=' + postType + '; post_content_length=' + postContents.length + '; parameter_names=' + parameterNames);
      return pcwFail_('missing_post_data', requestId);
    }
    if (Utilities.newBlob(rawBody).getBytes().length > PCWORK_MAX_BODY_BYTES) return pcwFail_('payload_too_large', requestId);

    var props = PropertiesService.getScriptProperties();
    var secret = props.getProperty('PCWORK_HMAC_SECRET');
    if (!secret) return pcwFail_('missing_secret', requestId);

    var timestamp = String(params.ts || '');
    var nonce = String(params.nonce || '');
    var suppliedSignature = String(params.sig || '').toLowerCase();
    if (!/^\d{10,13}$/.test(timestamp)) return pcwFail_('invalid_timestamp', requestId);
    if (!/^[a-f0-9]{32}$/.test(nonce)) return pcwFail_('invalid_nonce', requestId);
    if (!/^[a-f0-9]{64}$/.test(suppliedSignature)) return pcwFail_('invalid_signature_format', requestId);

    var timestampSeconds = Number(timestamp);
    if (timestampSeconds > 9999999999) timestampSeconds = Math.floor(timestampSeconds / 1000);
    var nowSeconds = Math.floor(Date.now() / 1000);
    if (Math.abs(nowSeconds - timestampSeconds) > PCWORK_MAX_CLOCK_SKEW_SECONDS) return pcwFail_('timestamp_expired', requestId);

    var signedMessage = timestamp + '.' + nonce + '.' + rawBody;
    var expectedSignature = pcwHex_(Utilities.computeHmacSha256Signature(signedMessage, secret));
    if (!pcwConstantTimeEquals_(expectedSignature, suppliedSignature)) return pcwFail_('invalid_hmac', requestId);

    var lock = LockService.getScriptLock();
    if (!lock.tryLock(5000)) return pcwFail_('server_busy', requestId);
    try {
      var cache = CacheService.getScriptCache();
      var nonceKey = 'pcw_nonce_' + nonce;
      if (cache.get(nonceKey)) return pcwFail_('replayed_request', requestId);
      var minuteKey = 'pcw_rate_' + Math.floor(nowSeconds / 60);
      var count = Number(cache.get(minuteKey) || 0);
      if (count >= PCWORK_MAX_REQUESTS_PER_MINUTE) return pcwFail_('rate_limited', requestId);
      cache.put(nonceKey, '1', PCWORK_NONCE_TTL_SECONDS);
      cache.put(minuteKey, String(count + 1), 120);
    } finally {
      lock.releaseLock();
    }

    var payload;
    try { payload = JSON.parse(rawBody); }
    catch (parseError) { return pcwFail_('invalid_json', requestId); }
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return pcwFail_('invalid_payload', requestId);

    var eventName = String(payload.event || '');
    if (eventName === 'pcwork.integration.ping') {
      console.info('[PCWork Security] authenticated ping accepted ' + requestId);
      return pcwJson_({ok: true, event: eventName, version: PCWORK_SECURITY_VERSION, request_id: requestId});
    }
    if (eventName === 'pcwork.repair.upsert') {
      var result = pcwUpsertRepair_(payload, props);
      console.info('[PCWork Security] repair upsert processed ' + requestId + '; action=' + result.action + '; repair_id=' + result.repair_id);
      return pcwJson_({ok: true, event: eventName, version: PCWORK_SECURITY_VERSION, request_id: requestId, result: result});
    }
    return pcwFail_('event_not_allowed', requestId);
  } catch (err) {
    console.error('[PCWork Security] request failed ' + requestId + ': ' + String(err && err.message ? err.message : err));
    return pcwFail_('internal_error', requestId);
  }
}

function pcwUpsertRepair_(payload, props) {
  var spreadsheetId = props.getProperty('PCWORK_SPREADSHEET_ID');
  if (!spreadsheetId) throw new Error('missing_spreadsheet_id');
  var sheetName = props.getProperty('PCWORK_SHEET_NAME') || 'Repairs';
  var spreadsheet = SpreadsheetApp.openById(spreadsheetId);
  var sheet = spreadsheet.getSheetByName(sheetName) || spreadsheet.insertSheet(sheetName);
  if (sheet.getLastRow() === 0) {
    sheet.getRange(1, 1, 1, PCWORK_HEADERS.length).setValues([PCWORK_HEADERS]);
    sheet.setFrozenRows(1);
  } else {
    var currentHeaders = sheet.getRange(1, 1, 1, PCWORK_HEADERS.length).getValues()[0];
    if (String(currentHeaders[0]) !== 'Repair ID') throw new Error('unexpected_sheet_headers');
  }
  var repair = payload.repair || {};
  var repairId = String(repair.repair_id || '').trim();
  if (!repairId || !/^\d+$/.test(repairId)) throw new Error('invalid_repair_id');
  var now = new Date();
  var row = [
    repairId, repair.repair_number || '', repair.customer_name || '', repair.customer_email || '',
    repair.customer_phone || '', repair.location_code || '', repair.location_name || '',
    repair.device_type || '', repair.device_model || '', repair.serial_number || '',
    repair.problem_description || '', repair.external_condition || '', repair.accessories || '',
    repair.status || '', repair.assigned_technician_id || '', repair.priority || 'normal',
    repair.due_at || '', repair.created_at || '', repair.updated_at || '', now.toISOString()
  ].map(pcwSafeCell_);
  var lastRow = sheet.getLastRow();
  var targetRow = 0;
  if (lastRow >= 2) {
    var ids = sheet.getRange(2, 1, lastRow - 1, 1).getDisplayValues();
    for (var i = 0; i < ids.length; i++) {
      if (String(ids[i][0]) === repairId) { targetRow = i + 2; break; }
    }
  }
  if (targetRow) {
    sheet.getRange(targetRow, 1, 1, row.length).setValues([row]);
    return {action: 'updated', repair_id: repairId};
  }
  sheet.appendRow(row);
  return {action: 'inserted', repair_id: repairId};
}

function pcwFormValue_(formBody, wantedName) {
  var pairs = String(formBody || '').split('&');
  for (var i = 0; i < pairs.length; i++) {
    if (!pairs[i]) continue;
    var splitAt = pairs[i].indexOf('=');
    var rawName = splitAt >= 0 ? pairs[i].substring(0, splitAt) : pairs[i];
    var rawValue = splitAt >= 0 ? pairs[i].substring(splitAt + 1) : '';
    var name = decodeURIComponent(rawName.replace(/\+/g, ' '));
    if (name === wantedName) return decodeURIComponent(rawValue.replace(/\+/g, ' '));
  }
  return '';
}

function pcwSafeCell_(value) {
  if (value === null || value === undefined) return '';
  var text = String(value);
  if (/^[\s]*[=+@-]/.test(text)) return "'" + text;
  return text;
}
function pcwHex_(bytes) {
  return bytes.map(function(b) { var value = (b < 0 ? b + 256 : b).toString(16); return value.length === 1 ? '0' + value : value; }).join('');
}
function pcwConstantTimeEquals_(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  var length = Math.max(a.length, b.length), diff = a.length ^ b.length;
  for (var i = 0; i < length; i++) diff |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  return diff === 0;
}
function pcwJson_(object) {
  return ContentService.createTextOutput(JSON.stringify(object)).setMimeType(ContentService.MimeType.JSON);
}
function pcwFail_(code, requestId) {
  console.warn('[PCWork Security] rejected request ' + String(requestId || '') + ': ' + code);
  return pcwJson_({ok: false, error: code, request_id: requestId || ''});
}
