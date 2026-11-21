import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../categories/providers/category_provider.dart';

class JobFormValues {
  String categoryId;
  List<String> subcategoryIds;
  String description;
  String city;
  String address;
  String? budget;
  String timing;

  JobFormValues({
    this.categoryId = '',
    this.subcategoryIds = const [],
    this.description = '',
    this.city = '',
    this.address = '',
    this.budget,
    this.timing = 'today',
  });
}

class JobFormWidget extends ConsumerStatefulWidget {
  /// CTA text rendered on the primary submit button
  final String title;
  final String? initialCategory;
  final JobFormValues? initialValues;
  final List<String> initialPhotos;
  final bool isSubmitting;
  final Future<void> Function(
    JobFormValues data,
    List<String> existingPhotos,
    List<File> newPhotos,
  )
  onSubmit;

  const JobFormWidget({
    super.key,
    required this.title,
    this.initialCategory,
    this.initialValues,
    this.initialPhotos = const [],
    required this.isSubmitting,
    required this.onSubmit,
  });

  @override
  ConsumerState<JobFormWidget> createState() => _JobFormWidgetState();
}

class _JobFormWidgetState extends ConsumerState<JobFormWidget> {
  static const int _maxPhotos = 8;

  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  late JobFormValues _formData;
  late List<String> _existingPhotos;
  final List<File> _newPhotos = [];
  bool _showPhotoError = false;

  static const List<Map<String, String>> _timingOptions = [
    {'id': 'asap', 'label': 'Срочно'},
    {'id': 'today', 'label': 'В течение дня'},
    {'id': 'week', 'label': 'До конца недели'},
    {'id': 'flexible', 'label': 'Сроки не горят'},
  ];

  int get _totalPhotoCount => _existingPhotos.length + _newPhotos.length;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValues;
    // Clone values so the widget never mutates caller-owned references
    _formData = JobFormValues(
      categoryId: initial?.categoryId ?? widget.initialCategory ?? '',
      subcategoryIds: List<String>.from(initial?.subcategoryIds ?? const []),
      description: initial?.description ?? '',
      city: (initial?.city == 'Не указан') ? '' : (initial?.city ?? ''),
      address: initial?.address ?? '',
      budget: initial?.budget,
      timing: (initial?.timing.isNotEmpty ?? false) ? initial!.timing : 'today',
    );
    _existingPhotos = List<String>.from(widget.initialPhotos);
  }

  Future<void> _showImageSourceActionSheet() async {
    if (_totalPhotoCount >= _maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Можно прикрепить максимум $_maxPhotos фотографий'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(
                    LucideIcons.camera,
                    color: Color(0xFF0F172A),
                  ),
                  title: const Text('Сделать фото'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _pickImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    LucideIcons.image,
                    color: Color(0xFF0F172A),
                  ),
                  title: const Text('Выбрать из галереи'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _pickImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final remainingSlots = _maxPhotos - _totalPhotoCount;
    if (remainingSlots <= 0) return;

    try {
      if (source == ImageSource.camera) {
        final pickedFile = await _picker.pickImage(
          source: source,
          imageQuality: 75,
        );
        if (!mounted || pickedFile == null) return;
        setState(() {
          _newPhotos.add(File(pickedFile.path));
          _showPhotoError = false;
        });
      } else {
        final pickedFiles = await _picker.pickMultiImage(imageQuality: 75);
        if (!mounted || pickedFiles.isEmpty) return;

        final filesToAdd = pickedFiles
            .take(remainingSlots)
            .map((x) => File(x.path))
            .toList();

        setState(() {
          _newPhotos.addAll(filesToAdd);
          _showPhotoError = false;
        });

        if (pickedFiles.length > remainingSlots) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Добавлены только первые $_maxPhotos фото'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось выбрать фото: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _submit() {
    FocusScope.of(context).unfocus();

    final isFormValid = _formKey.currentState?.validate() ?? false;
    final hasPhotos = _totalPhotoCount > 0;

    if (!hasPhotos) {
      setState(() => _showPhotoError = true);
    }

    if (!isFormValid) return;

    _formKey.currentState!.save();

    if (_formData.categoryId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Выберите основную категорию услуги'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_formData.subcategoryIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Выберите хотя бы одну подкатегорию услуги'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!hasPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Добавьте хотя бы одно фото задачи'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    widget.onSubmit(_formData, _existingPhotos, _newPhotos);
  }

  InputDecoration _inputDecoration({
    required String hint,
    String? label,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(publicCategoriesProvider);

    return Column(
      children: [
        Expanded(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                // =======================================================
                // CARD 1: CATEGORY, SUBCATEGORIES & DESCRIPTION
                // =======================================================
                _buildCard(
                  children: [
                    const _SectionTitle(
                      icon: LucideIcons.layers,
                      title: 'Услуги',
                    ),
                    categoriesAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      error: (_, __) => Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Ошибка загрузки категорий',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(publicCategoriesProvider),
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                      data: (categories) {
                        if (categories.isEmpty) {
                          return const Text(
                            'Категории временно недоступны.',
                            style: TextStyle(color: Colors.red),
                          );
                        }

                        final isCategoryValid = categories.any(
                          (c) => c.id == _formData.categoryId,
                        );
                        final dropdownValue = isCategoryValid
                            ? _formData.categoryId
                            : null;
                        final parentCategory = isCategoryValid
                            ? categories.firstWhere(
                                (c) => c.id == _formData.categoryId,
                              )
                            : null;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Основная категория *',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: dropdownValue,
                              hint: const Text('Выберите основную услугу'),
                              isExpanded: true,
                              decoration: _inputDecoration(
                                hint: 'Выберите основную услугу',
                              ),
                              items: categories.map((cat) {
                                return DropdownMenuItem(
                                  value: cat.id,
                                  child: Text(
                                    cat.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                );
                              }).toList(),
                              validator: (val) => val == null || val.isEmpty
                                  ? 'Выберите категорию'
                                  : null,
                              onChanged: widget.isSubmitting
                                  ? null
                                  : (newVal) {
                                      if (newVal != null &&
                                          newVal != _formData.categoryId) {
                                        setState(() {
                                          _formData.categoryId = newVal;
                                          // Reset subcategories when parent category changes
                                          _formData.subcategoryIds.clear();
                                        });
                                      }
                                    },
                            ),
                            if (parentCategory != null) ...[
                              const SizedBox(height: 18),
                              const Text(
                                'Уточните услугу (можно выбрать несколько) *',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (parentCategory.subcategories.isEmpty)
                                const Text(
                                  'Нет доступных подкатегорий',
                                  style: TextStyle(color: Colors.grey),
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: parentCategory.subcategories.map((
                                    subcat,
                                  ) {
                                    final isSelected = _formData.subcategoryIds
                                        .contains(subcat.id);
                                    return FilterChip(
                                      label: Text(subcat.name),
                                      selected: isSelected,
                                      onSelected: widget.isSubmitting
                                          ? null
                                          : (selected) {
                                              setState(() {
                                                if (selected) {
                                                  _formData.subcategoryIds.add(
                                                    subcat.id,
                                                  );
                                                } else {
                                                  _formData.subcategoryIds
                                                      .remove(subcat.id);
                                                }
                                              });
                                            },
                                      backgroundColor: const Color(0xFFF8FAFC),
                                      selectedColor: const Color(0xFF0F172A),
                                      checkmarkColor: Colors.white,
                                      side: BorderSide(
                                        color: isSelected
                                            ? const Color(0xFF0F172A)
                                            : const Color(0xFFE2E8F0),
                                      ),
                                      labelStyle: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? Colors.white
                                            : const Color(0xFF334155),
                                      ),
                                    );
                                  }).toList(),
                                ),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 22),
                    const _SectionTitle(
                      icon: LucideIcons.pencil,
                      title: 'Описание задачи *',
                    ),
                    TextFormField(
                      initialValue: _formData.description,
                      enabled: !widget.isSubmitting,
                      maxLines: 4,
                      minLines: 3,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _inputDecoration(
                        hint:
                            'Опишите задачу подробнее (объем, особенности)...',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().length < 10) {
                          return 'Описание должно быть не менее 10 символов';
                        }
                        return null;
                      },
                      onSaved: (v) => _formData.description = (v ?? '').trim(),
                    ),
                  ],
                ),

                // =======================================================
                // CARD 2: PHOTOS
                // =======================================================
                _buildCard(
                  borderColor: _showPhotoError ? Colors.red : null,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const _SectionTitle(
                          icon: LucideIcons.camera,
                          title: 'Фотографии *',
                          bottomPadding: 0,
                        ),
                        Text(
                          '$_totalPhotoCount / $_maxPhotos',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _showPhotoError
                                ? Colors.red
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ..._existingPhotos.asMap().entries.map(
                          (e) => _PhotoThumb(
                            imageUrl: e.value,
                            onRemove: widget.isSubmitting
                                ? null
                                : () => setState(
                                    () => _existingPhotos.removeAt(e.key),
                                  ),
                          ),
                        ),
                        ..._newPhotos.asMap().entries.map(
                          (e) => _PhotoThumb(
                            file: e.value,
                            onRemove: widget.isSubmitting
                                ? null
                                : () => setState(
                                    () => _newPhotos.removeAt(e.key),
                                  ),
                          ),
                        ),
                        if (_totalPhotoCount < _maxPhotos)
                          GestureDetector(
                            onTap: widget.isSubmitting
                                ? null
                                : _showImageSourceActionSheet,
                            child: Container(
                              width: 82,
                              height: 82,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _showPhotoError
                                      ? Colors.red
                                      : const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    LucideIcons.image_plus,
                                    size: 22,
                                    color: _showPhotoError
                                        ? Colors.red
                                        : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Добавить',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _showPhotoError
                                          ? Colors.red
                                          : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (_showPhotoError) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Добавьте хотя бы одно фото',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                  ],
                ),

                // =======================================================
                // CARD 3: LOCATION & TIMING
                // =======================================================
                _buildCard(
                  children: [
                    const _SectionTitle(
                      icon: LucideIcons.map_pin,
                      title: 'Местоположение',
                    ),
                    TextFormField(
                      initialValue: _formData.city,
                      enabled: !widget.isSubmitting,
                      textCapitalization: TextCapitalization.words,
                      decoration: _inputDecoration(
                        label: 'Город',
                        hint: 'Например: Москва',
                      ),
                      validator: (v) {
                        if (v != null &&
                            v.trim().isNotEmpty &&
                            v.trim().length < 2) {
                          return 'Введите корректное название города';
                        }
                        return null;
                      },
                      onSaved: (v) => _formData.city = (v ?? '').trim(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _formData.address,
                      enabled: !widget.isSubmitting,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _inputDecoration(
                        label: 'Адрес выполнения *',
                        hint: 'Улица, дом, подъезд / квартира',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().length < 5) {
                          return 'Укажите полный адрес (минимум 5 символов)';
                        }
                        return null;
                      },
                      onSaved: (v) => _formData.address = (v ?? '').trim(),
                    ),
                    const SizedBox(height: 22),
                    const _SectionTitle(
                      icon: LucideIcons.clock,
                      title: 'Срочность',
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _timingOptions.map((opt) {
                        final isSelected = _formData.timing == opt['id'];
                        return ChoiceChip(
                          label: Text(opt['label']!),
                          selected: isSelected,
                          onSelected: widget.isSubmitting
                              ? null
                              : (selected) {
                                  if (selected) {
                                    setState(
                                      () => _formData.timing = opt['id']!,
                                    );
                                  }
                                },
                          backgroundColor: const Color(0xFFF8FAFC),
                          selectedColor: const Color(0xFF0F172A),
                          side: BorderSide(
                            color: isSelected
                                ? const Color(0xFF0F172A)
                                : const Color(0xFFE2E8F0),
                          ),
                          labelStyle: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF334155),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),

                // =======================================================
                // CARD 4: BUDGET
                // =======================================================
                _buildCard(
                  children: [
                    const _SectionTitle(
                      icon: LucideIcons.wallet,
                      title: 'Бюджет (необязательно)',
                    ),
                    TextFormField(
                      initialValue: _formData.budget,
                      enabled: !widget.isSubmitting,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _inputDecoration(
                        hint: 'Договорная цена, если оставить пустым',
                        prefixIcon: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Text(
                            '₽',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final parsed = int.tryParse(v.trim());
                        if (parsed == null || parsed <= 0) {
                          return 'Бюджет должен быть больше 0';
                        }
                        return null;
                      },
                      onSaved: (v) {
                        final trimmed = v?.trim() ?? '';
                        _formData.budget = trimmed.isEmpty ? null : trimmed;
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // =======================================================
        // STICKY BOTTOM SUBMIT BAR
        // =======================================================
        Container(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            MediaQuery.paddingOf(context).bottom + 12,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: widget.isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: widget.isSubmitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required List<Widget> children, Color? borderColor}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor ?? const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final double bottomPadding;

  const _SectionTitle({
    required this.icon,
    required this.title,
    this.bottomPadding = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF0F172A)),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final String? imageUrl;
  final File? file;
  final VoidCallback? onRemove;

  const _PhotoThumb({this.imageUrl, this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 82,
            height: 82,
            child: imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: imageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: Colors.grey.shade100,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(
                        LucideIcons.image_off,
                        color: Colors.grey,
                        size: 20,
                      ),
                    ),
                  )
                : Image.file(file!, fit: BoxFit.cover),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.x, color: Colors.white, size: 14),
              ),
            ),
          ),
      ],
    );
  }
}
