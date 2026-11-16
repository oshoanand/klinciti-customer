class ChatMessageModel {
  final String id;
  final String chatSessionId;
  final String senderId;
  final String? text;
  final String? imageUrl;
  final bool isRead;
  final String createdAt;

  // ✅ ADDED: Required for Optimistic UI Updates & Error Handling
  final bool isSending;
  final bool isFailed;

  ChatMessageModel({
    required this.id,
    required this.chatSessionId,
    required this.senderId,
    this.text,
    this.imageUrl,
    required this.isRead,
    required this.createdAt,
    this.isSending = false, // Defaults to false for normal backend messages
    this.isFailed = false, // Defaults to false
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id'].toString(),
      chatSessionId:
          json['chat_session_id']?.toString() ??
          json['chatSessionId']?.toString() ??
          '',
      senderId:
          json['sender_id']?.toString() ?? json['senderId']?.toString() ?? '',
      text: json['text'],
      imageUrl: json['image_url'] ?? json['imageUrl'],
      isRead: json['is_read'] == true || json['isRead'] == true,
      createdAt:
          json['created_at'] ??
          json['createdAt'] ??
          DateTime.now().toUtc().toIso8601String(), // Ensure fallback is UTC
    );
  }

  ChatMessageModel copyWith({
    String? id,
    String? chatSessionId,
    String? senderId,
    String? text,
    String? imageUrl,
    bool? isRead,
    String? createdAt,
    bool? isSending,
    bool? isFailed,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      chatSessionId: chatSessionId ?? this.chatSessionId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      imageUrl: imageUrl ?? this.imageUrl,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      isSending: isSending ?? this.isSending,
      isFailed: isFailed ?? this.isFailed,
    );
  }
}
