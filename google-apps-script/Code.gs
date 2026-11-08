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
var PCWORK_SECURITY_VERSION = '2.7.0';
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
      var probe = pcwVerifySheetWrite_(props, requestId);
      console.info('[PCWork Security] spreadsheet write probe completed ' + requestId + '; verified=' + probe.write_verified);
      return pcwJson_({ok: true, event: eventName, version: PCWORK_SECURITY_VERSION, request_id: requestId, result: probe});
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


/**
 * Verifies actual Spreadsheet access and write permission. The probe is removed
 * immediately after read-back, so it does not leave test rows in the customer's sheet.
 */
function pcwVerifySheetWrite_(props, requestId) {
  var spreadsheetId = props.getProperty('PCWORK_SPREADSHEET_ID');
  if (!spreadsheetId) throw new Error('missing_spreadsheet_id');
  var targetName = props.getProperty('PCWORK_SHEET_NAME') || 'Repairs';
  var spreadsheet = SpreadsheetApp.openById(spreadsheetId);
  var target = spreadsheet.getSheetByName(targetName);
  if (!target) {
    target = spreadsheet.insertSheet(targetName);
    target.getRange(1, 1, 1, PCWORK_HEADERS.length).setValues([PCWORK_HEADERS]);
    target.setFrozenRows(1);
  } else if (target.getLastRow() === 0) {
    target.getRange(1, 1, 1, PCWORK_HEADERS.length).setValues([PCWORK_HEADERS]);
    target.setFrozenRows(1);
  }

  // Test writes in a disposable sheet so the health check never inserts/deletes
  // a row in the real Repairs sheet or races with a customer edit.
  var probeName = '_PCW_TEST_' + String(requestId).replace(/[^A-Za-z0-9]/g, '').substring(0, 18);
  var probe = null;
  var verified = false;
  try {
    probe = spreadsheet.insertSheet(probeName);
    var marker = 'PCWORK_WRITE_TEST_' + String(requestId);
    probe.getRange(1, 1).setValue(marker);
    SpreadsheetApp.flush();
    verified = String(probe.getRange(1, 1).getValue()) === marker;
  } finally {
    if (probe) spreadsheet.deleteSheet(probe);
    SpreadsheetApp.flush();
  }
  if (!verified) throw new Error('spreadsheet_write_verification_failed');
  return {
    write_verified: true,
    spreadsheet_title: spreadsheet.getName(),
    sheet_name: target.getName(),
    probe_removed: true
  };
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
    var match = sheet.getRange(2, 1, lastRow - 1, 1)
      .createTextFinder(repairId)
      .matchEntireCell(true)
      .findNext();
    if (match) targetRow = match.getRow();
  }
  if (targetRow) {
    sheet.getRange(targetRow, 1, 1, row.length).setValues([row]);
    SpreadsheetApp.flush();
    if (String(sheet.getRange(targetRow, 1).getDisplayValue()) !== repairId) throw new Error('repair_update_readback_failed');
    return {action: 'updated', repair_id: repairId, verified: true, row: targetRow};
  }
  sheet.appendRow(row);
  SpreadsheetApp.flush();
  var insertedRow = sheet.getLastRow();
  if (String(sheet.getRange(insertedRow, 1).getDisplayValue()) !== repairId) throw new Error('repair_insert_readback_failed');
  return {action: 'inserted', repair_id: repairId, verified: true, row: insertedRow};
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
