import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';

class CreateOrganizationScreen extends ConsumerStatefulWidget {
  const CreateOrganizationScreen({super.key, this.organization});

  final Map<String, dynamic>? organization;

  @override
  ConsumerState<CreateOrganizationScreen> createState() =>
      _CreateOrganizationScreenState();
}

class _CreateOrganizationScreenState
    extends ConsumerState<CreateOrganizationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _arabicName = TextEditingController();
  final _englishName = TextEditingController();
  final _shortName = TextEditingController();
  final _description = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _googleMapsUrl = TextEditingController();
  final _primaryColor = TextEditingController(text: '#6A1BFF');
  final _secondaryColor = TextEditingController(text: '#9C4DFF');
  bool _saving = false;
  bool _assignAsChairman = false;

  bool get _isEditing => widget.organization != null;

  @override
  void initState() {
    super.initState();
    final data = widget.organization;
    if (data == null) return;
    _arabicName.text = data['officialNameArabic'] as String? ?? '';
    _englishName.text = data['officialNameEnglish'] as String? ?? '';
    _shortName.text = data['shortName'] as String? ?? '';
    final description = data['description'];
    _description.text = description is Map
        ? description['ar'] as String? ?? ''
        : description as String? ?? '';
    _phone.text = data['phone'] as String? ?? '';
    _email.text = data['email'] as String? ?? '';
    _address.text = data['address'] as String? ?? '';
    _googleMapsUrl.text = data['googleMapsUrl'] as String? ?? '';
    _primaryColor.text = data['primaryColor'] as String? ?? '#6A1BFF';
    _secondaryColor.text = data['secondaryColor'] as String? ?? '#9C4DFF';
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final access = await ref.read(adminAccessProvider.future);
    final user = ref.read(authServiceProvider).currentUser;
    if (!access.isSuperAdmin || user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هذه العملية متاحة للمشرف العام فقط')),
        );
      }
      return;
    }

    setState(() => _saving = true);
    final data = <String, dynamic>{
      'officialNameArabic': _arabicName.text.trim(),
      'officialNameEnglish': _englishName.text.trim(),
      'shortName': _shortName.text.trim(),
      'description': {
        'ar': _description.text.trim(),
        'en': _englishName.text.trim(),
      },
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'address': _address.text.trim(),
      'googleMapsUrl': _googleMapsUrl.text.trim(),
      'primaryColor': _primaryColor.text.trim().isEmpty
          ? '#6A1BFF'
          : _primaryColor.text.trim(),
      'secondaryColor': _secondaryColor.text.trim().isEmpty
          ? '#9C4DFF'
          : _secondaryColor.text.trim(),
    };
    try {
      if (_isEditing) {
        await ref.read(organizationRepositoryProvider).update(
              organizationId: widget.organization!['organizationId'] as String,
              data: data,
              actorUserId: user.uid,
            );
      } else {
        await ref.read(organizationRepositoryProvider).createWithDefaults(
              data: data,
              createdBy: user.uid,
              assignCreatorAsChairman: _assignAsChairman,
            );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'تم تحديث المجلس' : 'تم إنشاء المجلس'),
        ),
      );
      context.pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ بيانات المجلس')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _arabicName,
      _englishName,
      _shortName,
      _description,
      _phone,
      _email,
      _address,
      _googleMapsUrl,
      _primaryColor,
      _secondaryColor,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(_isEditing ? 'تعديل المجلس' : 'إضافة مجلس'),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _field(_arabicName, 'اسم المجلس بالعربية'),
              _field(
                _englishName,
                'اسم المجلس بالإنجليزية',
                textDirection: ui.TextDirection.ltr,
              ),
              _field(_shortName, 'الاسم المختصر'),
              _field(_description, 'وصف المجلس', maxLines: 3),
              _field(_phone, 'الهاتف', keyboard: TextInputType.phone),
              _field(
                _email,
                'البريد الإلكتروني',
                keyboard: TextInputType.emailAddress,
                textDirection: ui.TextDirection.ltr,
              ),
              _field(_address, 'الموقع / العنوان', maxLines: 2),
              _field(
                _googleMapsUrl,
                'رابط Google Maps (اختياري)',
                required: false,
                keyboard: TextInputType.url,
                textDirection: ui.TextDirection.ltr,
              ),
              _field(
                _primaryColor,
                'اللون الأساسي (اختياري)',
                required: false,
                textDirection: ui.TextDirection.ltr,
              ),
              _field(
                _secondaryColor,
                'اللون الثانوي (اختياري)',
                required: false,
                textDirection: ui.TextDirection.ltr,
              ),
              if (!_isEditing)
                CheckboxListTile(
                  value: _assignAsChairman,
                  onChanged: _saving
                      ? null
                      : (value) => setState(
                            () => _assignAsChairman = value ?? false,
                          ),
                  title: const Text('تعييني كرئيس لهذا المجلس'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
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
                label: Text(_isEditing ? 'حفظ التعديلات' : 'إنشاء المجلس'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = true,
    int maxLines = 1,
    TextInputType? keyboard,
    ui.TextDirection? textDirection,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboard,
        textDirection: textDirection,
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (value) =>
                value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب' : null
            : null,
      ),
    );
  }
}
