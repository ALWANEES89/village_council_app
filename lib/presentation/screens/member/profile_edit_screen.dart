import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/member_model.dart';
import '../../../data/models/user_profile_model.dart';
import '../../../providers/app_providers.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _civilIdController = TextEditingController();

  bool _initialized = false;
  bool _saving = false;
  File? _selectedPhoto;
  String? _photoUrl;

  void _initialize(UserProfileModel? profile, MemberModel? member) {
    if (_initialized) return;
    _fullNameController.text = profile?.fullName ?? member?.fullName ?? '';
    _emailController.text = profile?.email ?? '';
    _addressController.text = profile?.address ?? '';
    _photoUrl = profile?.photoUrl;
    _phoneController.text = profile?.phone ?? member?.phone ?? '';
    _civilIdController.text = profile?.civilId ?? member?.civilId ?? '';
    _initialized = true;
  }

  Future<void> _save(String userId) async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      var resolvedPhotoUrl = _photoUrl;
      if (_selectedPhoto != null) {
        resolvedPhotoUrl =
            await ref.read(storageServiceProvider).uploadProfilePhoto(
                  file: _selectedPhoto!,
                  userId: userId,
                );
      }
      await ref.read(userRepositoryProvider).saveProfile(
            UserProfileModel(
              userId: userId,
              fullName: _fullNameController.text.trim(),
              email: _emailController.text.trim(),
              address: _addressController.text.trim(),
              photoUrl: resolvedPhotoUrl,
              phone: _phoneController.text.trim(),
              civilId: _civilIdController.text.trim(),
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث الملف الشخصي بنجاح')),
      );
      context.pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('تعذر تحديث الملف الشخصي. حاول مرة أخرى.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (image != null && mounted) {
        setState(() => _selectedPhoto = File(image.path));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر اختيار الصورة')),
      );
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _civilIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).asData?.value ??
        ref.read(authServiceProvider).currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('تعذر العثور على بيانات الحساب')),
      );
    }

    final profileAsync = ref.watch(userProfileProvider(user.uid));
    final memberAsync = ref.watch(currentMemberProvider);
    if (!_initialized && !profileAsync.isLoading && !memberAsync.isLoading) {
      _initialize(profileAsync.asData?.value, memberAsync.asData?.value);
    }

    if (!_initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('تعديل الملف الشخصي'),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: 'الاسم الكامل',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'أدخل الاسم الكامل'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty) return null;
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
                      ? null
                      : 'البريد الإلكتروني غير صحيح';
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _addressController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'مكان السكن',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 46,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      backgroundImage: _selectedPhoto != null
                          ? FileImage(_selectedPhoto!)
                          : (_photoUrl?.trim().isNotEmpty == true
                              ? NetworkImage(_photoUrl!)
                              : null) as ImageProvider?,
                      child: _selectedPhoto == null &&
                              _photoUrl?.trim().isNotEmpty != true
                          ? const Icon(
                              Icons.person,
                              size: 48,
                              color: AppColors.primary,
                            )
                          : null,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _pickPhoto(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('اختيار من المعرض'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _pickPhoto(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('التقاط صورة'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phoneController,
                readOnly: true,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _civilIdController,
                readOnly: true,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'الرقم المدني',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : () => _save(user.uid),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('حفظ التغييرات'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
