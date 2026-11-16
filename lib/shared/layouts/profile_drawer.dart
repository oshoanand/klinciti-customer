import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';

// If you have cached_network_image, uncomment the line below:
// import 'package:cached_network_image/cached_network_image.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/presentation/auth_bottom_sheet.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/phone_formatter.dart';

final isAvatarUploadingProvider = StateProvider.autoDispose<bool>(
  (ref) => false,
);

class ProfileDrawer extends ConsumerWidget {
  const ProfileDrawer({super.key});

  // ==========================================
  // UPLOAD LOGIC
  // ==========================================
  Future<void> _pickAndUploadAvatar(
    BuildContext context,
    WidgetRef ref,
    ImageSource source,
  ) async {
    Navigator.pop(context); // Close the camera/gallery bottom sheet

    final picker = ImagePicker();
    final XFile? pickedImage = await picker.pickImage(
      source: source,
      imageQuality: 70, // Compress slightly for faster uploads
      maxWidth: 800,
    );

    if (pickedImage == null) return;

    ref.read(isAvatarUploadingProvider.notifier).state = true;

    try {
      final file = File(pickedImage.path);
      final fileName = p.basename(file.path);
      final api = ref.read(apiClientProvider);

      // 1. Get Presigned URL
      final presignedRes = await api.dio.post(
        '/customers/presigned-url',
        data: {'fileName': fileName, 'folderName': 'profileImage'},
      );
      final String uploadUrl = presignedRes.data['presignedUrl'];
      final String publicUrl = presignedRes.data['publicUrl'];

      // 2. Upload to MinIO directly
      final rawDio = Dio(
        BaseOptions(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      String contentType = 'image/jpeg';
      if (fileName.toLowerCase().endsWith('.png')) contentType = 'image/png';
      if (fileName.toLowerCase().endsWith('.webp')) contentType = 'image/webp';

      await rawDio.put(
        uploadUrl,
        data: file.openRead(),
        options: Options(
          headers: {
            Headers.contentLengthHeader: await file.length(),
            Headers.contentTypeHeader: contentType,
          },
        ),
      );

      // 3. Tell backend to save the URL to the user's profile
      await api.dio.patch(
        '/customers/photo',
        data: {'imageUrl': publicUrl, 'imageType': 'profileImage'},
      );

      // 4. Update local Riverpod state and Secure Storage instantly!
      final currentUser = ref.read(currentUserProvider);
      if (currentUser != null) {
        final updatedUser = Map<String, dynamic>.from(currentUser);
        updatedUser['image'] = publicUrl; // Update local map

        // Update global provider
        ref.read(currentUserProvider.notifier).state = updatedUser;

        // Save to secure storage so it survives app restarts
        await api.storage.write(
          key: 'user_data',
          value: jsonEncode(updatedUser),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка при загрузке фото. Попробуйте еще раз.'),
          ),
        );
      }
    } finally {
      ref.read(isAvatarUploadingProvider.notifier).state = false;
    }
  }

  void _showImageSourcePicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  LucideIcons.camera,
                  color: Color(0xFF0F172A),
                ),
                title: const Text(
                  'Сделать фото',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () =>
                    _pickAndUploadAvatar(context, ref, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  LucideIcons.image,
                  color: Color(0xFF0F172A),
                ),
                title: const Text(
                  'Выбрать из галереи',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () =>
                    _pickAndUploadAvatar(context, ref, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // UI BUILD
  // ==========================================
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(isAuthenticatedProvider);
    final user = ref.watch(currentUserProvider);
    final isUploading = ref.watch(isAvatarUploadingProvider);

    final String? avatarUrl =
        user?['image']?.toString() ?? user?['photo']?.toString();
    String name =
        user?['name']?.toString() ?? user?['first_name']?.toString() ?? '';
    if (name.trim().isEmpty) name = 'Пользователь';

    final String? mobile = user?['mobile']?.toString();
    final String? email = user?['email']?.toString();
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(8)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // const Text(
                  //   'Меню',
                  //   style: TextStyle(
                  //     fontSize: 24,
                  //     fontWeight: FontWeight.w900,
                  //     color: Color(0xFF0F172A),
                  //   ),
                  // ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (isAuthenticated) ...[
                    // ==========================================
                    // LOGGED IN HEADER WITH AVATAR STACK
                    // ==========================================
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          // 📸 AVATAR STACK
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A)
                                      .withOpacity(0.1),
                                  shape: BoxShape.circle,
                                  image:
                                      avatarUrl != null && avatarUrl.isNotEmpty
                                      ? DecorationImage(
                                          image: NetworkImage(avatarUrl),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: avatarUrl == null || avatarUrl.isEmpty
                                    ? const Icon(
                                        LucideIcons.user,
                                        color: Color(0xFF0F172A),
                                        size: 28,
                                      )
                                    : null,
                              ),

                              // LOADING OVERLAY
                              if (isUploading)
                                Positioned.fill(
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black26,
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    child: const CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 3,
                                    ),
                                  ),
                                ),

                              // CAMERA BADGE
                              // Positioned(
                              //   bottom: -2,
                              //   right: -2,
                              //   child: GestureDetector(
                              //     onTap: isUploading
                              //         ? null
                              //         : () => _showImageSourcePicker(
                              //             context,
                              //             ref,
                              //           ),
                              //     child: Container(
                              //       padding: const EdgeInsets.all(6),
                              //       decoration: BoxDecoration(
                              //         color: const Color(0xFF0F172A),
                              //         shape: BoxShape.circle,
                              //         border: Border.all(
                              //           color: Colors.white,
                              //           width: 2,
                              //         ),
                              //       ),
                              //       child: const Icon(
                              //         LucideIcons.camera,
                              //         color: Colors.white,
                              //         size: 14,
                              //       ),
                              //     ),
                              //   ),
                              // ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                if (mobile != null && mobile.isNotEmpty)
                                  Text(
                                    PhoneFormatter.format(mobile),
                                    style: const TextStyle(
                                      color: Color.fromARGB(255, 138, 137, 137),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                if (email != null && email.isNotEmpty)
                                  Text(
                                    email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    _MenuItem(
                      icon: LucideIcons.user_pen,
                      title: 'Редактировать профиль',
                      subtitle: 'Настройки и данные',
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/profile/edit');
                      },
                    ),
                    _MenuItem(
                      icon: LucideIcons.package,
                      title: 'Мои заказы',
                      subtitle: 'Все созданные заявки',
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/orders');
                      },
                    ),
                    const Divider(height: 32, color: Color(0xFFF1F5F9)),
                  ] else ...[
                    // ==========================================
                    // NOT LOGGED IN HEADER
                    // ==========================================
                    Container(
                      padding: const EdgeInsets.all(24),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            LucideIcons.user,
                            size: 40,
                            color: Color(0xFF0F172A),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Войдите, чтобы использовать все функции платформы.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    _MenuItem(
                      icon: LucideIcons.log_in,
                      title: 'Вход и Регистрация',
                      subtitle: 'Создать аккаунт или войти',
                      onTap: () {
                        Navigator.pop(context);
                        showAuthBottomSheet(context);
                      },
                    ),
                  ],

                  // ==========================================
                  // COMMON LINKS
                  // ==========================================
                  _MenuItem(
                    icon: LucideIcons.message_square_text,
                    title: 'Служба поддержки',
                    subtitle: 'Помощь и история обращений',
                    iconColor: const Color(0xFFF59E0B),
                    onTap: () {
                      Navigator.pop(context);
                      if (!isAuthenticated) {
                        showAuthBottomSheet(context);
                      } else {
                        context.push('/support');
                      }
                    },
                  ),
                  if (isAuthenticated) ...[
                    const Divider(height: 32, color: Color(0xFFF1F5F9)),
                    _MenuItem(
                      icon: LucideIcons.log_out,
                      title: 'Выйти',
                      subtitle: 'Завершить сеанс',
                      iconColor: Colors.red,
                      isDestructive: true,
                      onTap: () {
                        ref.read(authControllerProvider).logout(context);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final bool isDestructive;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor = const Color(0xFF0F172A),
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isDestructive ? Colors.red : Colors.grey).withOpacity(
                  0.1,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: isDestructive ? Colors.red : iconColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isDestructive
                          ? Colors.red
                          : const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
