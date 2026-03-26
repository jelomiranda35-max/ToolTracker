import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://gdxnkwuarlltxhefizmw.supabase.co/functions/v1';
  static const Duration _timeout = Duration(seconds: 10);

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }


  static const String _anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdkeG5rd3VhcmxsdHhoZWZpem13Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM2MjQ2ODYsImV4cCI6MjA4OTIwMDY4Nn0.LXbagrO68jEWKZ939jPcGlZrh8XMNv-_Mg9VZVeZrjg';

  static Future<Map<String, String>> _authHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${token ?? _anonKey}',
    };
  }

  // ── AUTH ─────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> login(
      String username, String password) async {
    try {
      debugPrint('[LOGIN] Attempting: $baseUrl/login');
      final response = await http
          .post(
            Uri.parse('$baseUrl/login'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(_timeout);
      debugPrint('[LOGIN] Status: ${response.statusCode}');
      debugPrint('[LOGIN] Body: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', data['access_token']);
        return data;
      }
      return null;
    } catch (e) {
      debugPrint('[LOGIN] ERROR: $e');
      return null;
    }
  }

  // ── INSTRUMENTS ──────────────────────────────────────────────────────────────

  static Future<List<dynamic>?> getInstruments() async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/instruments'), headers: headers)
          .timeout(_timeout);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  /// PATCH a single instrument — updates only the fields provided.
  ///
  /// Pass an empty string `""` to clear a nullable field on the server
  /// (e.g. `scheduled_repair_date: ""`).
  ///
  /// Supported keys: current_condition, location, scheduled_repair_date,
  /// scheduled_condemn_date, notes, last_calibrated_date, calibration_notes.
  ///
  /// Returns true if the server accepted the update (HTTP 200).
  static Future<bool> patchInstrument(
      String instrumentCode, Map<String, dynamic> fields) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .patch(
            Uri.parse('$baseUrl/instruments/$instrumentCode'),
            headers: headers,
            body: jsonEncode(fields),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ── DISPATCHES ───────────────────────────────────────────────────────────────

  static Future<List<dynamic>?> getDispatches() async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/dispatches'), headers: headers)
          .timeout(_timeout);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> createDispatch(Map<String, dynamic> data) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/dispatches'),
            headers: headers,
            body: jsonEncode(data),
          )
          .timeout(_timeout);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  /// Return a dispatch without condition data (legacy / simple return).
  static Future<bool> returnDispatch(String dispatchNo) async {
    return returnDispatchWithConditions(dispatchNo, itemConditions: []);
  }

  /// Return a dispatch AND send per-instrument return conditions so the server
  /// updates instrument statuses and condition records correctly.
  static Future<bool> returnDispatchWithConditions(
    String dispatchNo, {
    required List<Map<String, String>> itemConditions,
  }) async {
    try {
      final headers = await _authHeaders();

      final body = itemConditions.isNotEmpty
          ? jsonEncode({
              'item_conditions': itemConditions
                  .map((i) => {
                        'instrument_code': i['instrument_code'],
                        'return_condition': i['return_condition'],
                      })
                  .toList(),
            })
          : null;

      final response = await http
          .put(
            Uri.parse('$baseUrl/dispatches/$dispatchNo/return'),
            headers: headers,
            body: body,
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ── ADMIN ────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getAdminStats() async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/dispatches'), headers: headers)
          .timeout(_timeout);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>?> getUsers() async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/users'), headers: headers)
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> createUser({
    required String name,
    required String username,
    required String password,
    required String role,
  }) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/users'),
            headers: headers,
            body: jsonEncode({
              'name': name,
              'username': username,
              'password': password,
              'role': role,
            }),
          )
          .timeout(_timeout);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> changePassword(int userId, String newPassword) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .patch(
            Uri.parse('$baseUrl/users/$userId'),
            headers: headers,
            body: jsonEncode({'password': newPassword}),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> deleteUser(int userId) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .delete(
            Uri.parse('$baseUrl/users/$userId'),
            headers: headers,
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> createInstrument(Map<String, dynamic> data) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/instruments'),
            headers: headers,
            body: jsonEncode(data),
          )
          .timeout(_timeout);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> deleteInstrument(String instrumentCode) async {
    try {
      final headers = await _authHeaders();
      final url = '$baseUrl/instruments/$instrumentCode';
      final hasToken = headers.containsKey('Authorization');
      debugPrint('[DELETE] Attempting: $url  token=$hasToken');
      final response = await http
          .delete(
            Uri.parse(url),
            headers: headers,
          )
          .timeout(_timeout);
      debugPrint('[DELETE] Status: ' + response.statusCode.toString() + ' Body: ' + response.body);
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint('[DELETE] EXCEPTION: ' + e.toString());
      return false;
    }
  }
  static Future<List<dynamic>?> getActivityLog({int limit = 100}) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/logs/activity?limit=$limit'),
              headers: headers)
          .timeout(_timeout);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<List<dynamic>?> getUserHistory(String actorName,
      {int limit = 100}) async {
    try {
      final headers = await _authHeaders();
      final encoded = Uri.encodeComponent(actorName);
      final response = await http
          .get(
              Uri.parse(
                  '$baseUrl/logs/history?actor=$encoded&limit=$limit'),
              headers: headers)
          .timeout(_timeout);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> postActivityLog(
      List<Map<String, dynamic>> entries) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/logs/activity'),
            headers: headers,
            body: jsonEncode(entries),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> postInstrumentHistory(
      List<Map<String, dynamic>> entries) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/logs/history'),
            headers: headers,
            body: jsonEncode(entries),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> postRevertRequests(
      List<Map<String, dynamic>> entries) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/logs/revert-requests'),
            headers: headers,
            body: jsonEncode(entries),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>?> getRevertRequests() async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/logs/revert-requests'), headers: headers)
          .timeout(_timeout);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> respondRevertRequest(
      String instrumentCode, String status) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/logs/revert-requests/$instrumentCode/respond'),
            headers: headers,
            body: jsonEncode({'status': status}),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ── MESSAGING ─────────────────────────────────────────────────────────────

  static Future<bool> sendMessage({
    required int toUserId,
    required String toUserName,
    required String message,
  }) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/messages'),
            headers: headers,
            body: jsonEncode({
              'to_user_id': toUserId,
              'to_user_name': toUserName,
              'message': message,
            }),
          )
          .timeout(_timeout);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>?> getUnreadMessages() async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/messages/unread'), headers: headers)
          .timeout(_timeout);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> markMessageRead(int messageId) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .patch(
            Uri.parse('$baseUrl/messages/$messageId/read'),
            headers: headers,
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>?> getMessageStatus() async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/messages/admin/status'), headers: headers)
          .timeout(_timeout);
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  // ── GOOGLE SHEETS INTEGRATION ────────────────────────────────────────────────
  // Fire-and-forget pattern: sheets sync failures never block the app

  /// Push data to Google Sheets via Supabase Edge Function.
  /// 
  /// Actions:
  /// - 'dispatch_created': New staff dispatch
  /// - 'dispatch_returned': Staff dispatch returned
  /// - 'borrow_created': New student borrow
  /// - 'borrow_returned': Student borrow returned
  /// - 'instrument_updated': Instrument condition/schedule changed
  ///
  /// Fire-and-forget: failures are logged but don't throw
  static Future<void> pushToSheets(String action, Map<String, dynamic> data) async {
    try {
      final headers = await _authHeaders();
      await http.post(
        Uri.parse('$baseUrl/sheets'),
        headers: headers,
        body: jsonEncode({'action': action, 'data': data}),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[SHEETS] Error syncing $action: $e');
      // Silently continue - sheet sync should never block app functionality
    }
  }
}