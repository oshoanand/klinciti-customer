class ChatSessionModel {
  final String id;
  final String partnerId;
  final String? partnerName;
  final String? partnerAvatar;
  final String? partnerRole;
  final String? lastMessage;
  final String updatedAt;
  final int unreadCount;
  final bool isOnline;
  final bool isTyping;
  final String? lastSeen;
  final bool isAdmin;

  const ChatSessionModel({
    required this.id,
    required this.partnerId,
    this.partnerName,
    this.partnerAvatar,
    this.partnerRole,
    this.lastMessage,
    required this.updatedAt,
    this.unreadCount = 0,
    this.isOnline = false,
    this.isTyping = false,
    this.lastSeen,
    this.isAdmin = false,
  });

  factory ChatSessionModel.fromJson(Map<String, dynamic> json) {
    // Parse name and avatar safely
    final rawName = json['partnerName']?.toString().trim();
    final rawAvatar = json['partnerAvatar']?.toString().trim();
    final rawLastMessage = json['lastMessage']?.toString().trim();

    return ChatSessionModel(
      id: json['id']?.toString() ?? '',
      partnerId: json['partnerId']?.toString() ?? '',
      partnerName: (rawName != null && rawName.isNotEmpty) ? rawName : null,
      partnerAvatar: (rawAvatar != null && rawAvatar.isNotEmpty)
          ? rawAvatar
          : null,
      partnerRole: json['partnerRole']?.toString(),
      lastMessage: (rawLastMessage != null && rawLastMessage.isNotEmpty)
          ? rawLastMessage
          : null,
      updatedAt:
          json['updatedAt']?.toString() ??
          DateTime.now().toUtc().toIso8601String(),
      unreadCount: int.tryParse(json['unreadCount']?.toString() ?? '0') ?? 0,
      isOnline: _parseBool(json['isOnline']),
      isTyping: _parseBool(json['isTyping']),
      lastSeen: json['lastSeen']?.toString(),
      isAdmin: _parseBool(json['isAdmin']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'partnerId': partnerId,
      'partnerName': partnerName,
      'partnerAvatar': partnerAvatar,
      'partnerRole': partnerRole,
      'lastMessage': lastMessage,
      'updatedAt': updatedAt,
      'unreadCount': unreadCount,
      'isOnline': isOnline,
      'isTyping': isTyping,
      'lastSeen': lastSeen,
      'isAdmin': isAdmin,
    };
  }

  ChatSessionModel copyWith({
    String? id,
    String? partnerId,
    String? partnerName,
    String? partnerAvatar,
    String? partnerRole,
    String? lastMessage,
    String? updatedAt,
    int? unreadCount,
    bool? isOnline,
    bool? isTyping,
    String? lastSeen,
    bool? isAdmin,
  }) {
    return ChatSessionModel(
      id: id ?? this.id,
      partnerId: partnerId ?? this.partnerId,
      partnerName: partnerName ?? this.partnerName,
      partnerAvatar: partnerAvatar ?? this.partnerAvatar,
      partnerRole: partnerRole ?? this.partnerRole,
      lastMessage: lastMessage ?? this.lastMessage,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
      isTyping: isTyping ?? this.isTyping,
      lastSeen: lastSeen ?? this.lastSeen,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      final lower = value.toLowerCase();
      return lower == 'true' || lower == '1';
    }
    return false;
  }
}
