import 'dart:async';
import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../network/api_client.dart';

typedef SocketEventCallback = void Function(dynamic data);

final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService();
  ref.onDispose(service.dispose);
  return service;
});

class SocketService {
  io.Socket? _socket;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Persistent listener registry so long-lived services (e.g. NotificationService)
  // automatically reattach after disconnect/reconnect or account switches.
  final Map<String, Set<SocketEventCallback>> _listeners = {};

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  String? _currentUserId;
  bool _isConnecting = false;
  bool _isDisposed = false;

  bool get isConnected => _socket?.connected ?? false;
  String? get currentUserId => _currentUserId;
  Stream<bool> get connectionStream => _connectionController.stream;

  Future<void> connect(String userId) async {
    if (_isDisposed || userId.trim().isEmpty) return;

    // Already connected (or connecting) for this exact user
    if (_currentUserId == userId &&
        (_socket?.connected == true || _isConnecting)) {
      return;
    }

    _isConnecting = true;
    try {
      // Tear down any existing socket (stale or belonging to a different user)
      if (_socket != null) {
        _teardownSocket();
      }

      _currentUserId = userId;
      final token = await _storage.read(key: 'jwt_token');

      final uri = Uri.tryParse(ApiClient.baseUrl);
      if (uri == null || uri.host.isEmpty) {
        log('❌ Invalid ApiClient.baseUrl for socket connection');
        return;
      }

      final String socketUrl = '${uri.scheme}://${uri.authority}';

      final socket = io.io(
        socketUrl,
        io.OptionBuilder()
            .setPath('/socket.io')
            .setTransports(['websocket'])
            .enableReconnection()
            .setReconnectionAttempts(99999)
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(5000)
            .setAuth({
              'token': token ?? '',
              'userId': userId,
              'role': 'CUSTOMER',
            })
            .disableAutoConnect()
            .build(),
      );

      _socket = socket;

      // Re-attach all registered listeners onto the fresh socket instance
      _listeners.forEach((event, callbacks) {
        for (final callback in callbacks) {
          socket.on(event, callback);
        }
      });

      socket.onConnect((_) {
        log('✅ Socket Connected to $socketUrl (ID: ${socket.id})');
        _emitConnectionState(true);
      });

      socket.onDisconnect((_) {
        log('⚠️ Socket Disconnected');
        _emitConnectionState(false);
      });

      socket.onReconnect((attempt) {
        log('🔄 Socket Reconnected after $attempt attempts');
        _emitConnectionState(true);
      });

      socket.onReconnectAttempt((_) async {
        // Refresh JWT in handshake auth in case the token was rotated while offline
        final freshToken = await _storage.read(key: 'jwt_token');
        if (freshToken != null &&
            freshToken.isNotEmpty &&
            _socket != null &&
            _currentUserId != null) {
          _socket!.auth = {
            'token': freshToken,
            'userId': _currentUserId!,
            'role': 'CUSTOMER',
          };
        }
      });

      socket.onConnectError((err) {
        log('❌ Socket Connection Error: $err');
        _emitConnectionState(false);
      });

      socket.onError((err) => log('❌ Socket Error: $err'));
      socket.on('error', (data) {
        log('⚠️ Backend Socket Error Event: $data');
      });

      socket.connect();
    } finally {
      _isConnecting = false;
    }
  }

  /// Updates the JWT on the active socket without dropping registered listeners.
  void updateAuthToken(String token) {
    if (_socket != null && _currentUserId != null) {
      _socket!.auth = {
        'token': token,
        'userId': _currentUserId!,
        'role': 'CUSTOMER',
      };
    }
  }

  void listen(String event, SocketEventCallback callback) {
    final callbacks = _listeners.putIfAbsent(
      event,
      () => <SocketEventCallback>{},
    );
    final wasAdded = callbacks.add(callback);

    // Attach immediately if a socket exists and this callback wasn't already bound
    if (wasAdded && _socket != null) {
      _socket!.on(event, callback);
    }
  }

  /// Removes a specific callback if provided, or all listeners for [event] if omitted.
  void stopListening(String event, [SocketEventCallback? callback]) {
    if (callback != null) {
      _listeners[event]?.remove(callback);
      if (_listeners[event]?.isEmpty ?? false) {
        _listeners.remove(event);
      }
      _socket?.off(event, callback);
    } else {
      _listeners.remove(event);
      _socket?.off(event);
    }
  }

  void emit(String event, dynamic data) {
    if (_socket != null) {
      _socket!.emit(event, data);
    } else {
      log('⚠️ Tried to emit "$event" before socket was initialized.');
    }
  }

  /// Disconnects the active socket on logout while preserving persistent service listeners.
  void disconnect() {
    _teardownSocket();
    _currentUserId = null;
    _emitConnectionState(false);
    log('🛑 Socket disconnected.');
  }

  void _teardownSocket() {
    if (_socket != null) {
      _socket!.clearListeners();
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }
  }

  void _emitConnectionState(bool connected) {
    if (!_isDisposed && !_connectionController.isClosed) {
      _connectionController.add(connected);
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _teardownSocket();
    _listeners.clear();
    _currentUserId = null;
    _connectionController.close();
  }
}
