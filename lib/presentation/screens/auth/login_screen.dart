import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/member_model.dart';
import '../../../providers/app_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    this.organizationId,
    this.joinCode,
  });

  final String? organizationId;
  final String? joinCode;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isRouting = false;
  String? _error;

  String get _normalizedPhone =>
      '+968${_phoneController.text.replaceAll(RegExp(r'\s+'), '')}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSession());
  }

  Future<void> _restoreSession() async {
    final authService = ref.read(authServiceProvider);
    if (authService.currentUser == null || _isRouting) return;

    final member = await authService.getCurrentMember();
    if (!mounted || member == null) return;
    await _routeMember(member);
  }

  Future<void> _login() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final member =
          await ref.read(authServiceProvider).signInWithPhoneAndPassword(
                phone: _normalizedPhone,
                password: _passwordController.text,
              );

      if (!mounted) return;
      if (member == null) {
        await ref.read(authServiceProvider).signOut();
        if (!mounted) return;
        setState(() {
          _error = 'تعذر العثور على بيانات الحساب. تواصل مع إدارة المجلس.';
        });
        return;
      }

      await _routeMember(member);
    } catch (_) {
      if (!mounted) return;
      await ref.read(authServiceProvider).signOut();
      if (!mounted) return;
      setState(() {
        _error = 'رقم الهاتف أو كلمة المرور غير صحيحة';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _routeMember(MemberModel member) async {
    if (_isRouting) return;
    _isRouting = true;

    context.goNamed('memberHome');
  }

  void _openRegister() {
    context.pushNamed(
      'register',
      queryParameters: {
        if (widget.organizationId?.trim().isNotEmpty == true)
          'organizationId': widget.organizationId!,
        if (widget.joinCode?.trim().isNotEmpty == true)
          'joinCode': widget.joinCode!,
      },
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: [AppColors.primaryShadow],
                    ),
                    child: const Icon(
                      Icons.account_balance,
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'مجلس القرية',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'نظام إدارة الاشتراكات المالية',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 48),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'رقم الهاتف',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _phoneController,
                    enabled: true,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    textDirection: TextDirection.ltr,
                    decoration: _fieldDecoration(
                      hintText: 'XXXXXXXX',
                      prefixText: '+968 ',
                    ),
                    validator: (value) {
                      final phone = value?.replaceAll(RegExp(r'\s+'), '') ?? '';
                      if (phone.isEmpty) return 'أدخل رقم الهاتف';
                      if (!RegExp(r'^\d{8}$').hasMatch(phone)) {
                        return 'رقم الهاتف يجب أن يتكون من 8 أرقام';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'كلمة المرور',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _login(),
                    decoration: _fieldDecoration(
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'أدخل كلمة المرور'
                        : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [AppColors.primaryShadow],
                      ),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          disabledBackgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'تسجيل الدخول',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'أدخل رقم هاتفك وكلمة المرور للدخول',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isLoading ? null : _openRegister,
                    child: const Text('إنشاء حساب جديد'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    String? hintText,
    String? prefixText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintTextDirection: TextDirection.ltr,
      prefixText: prefixText,
      prefixStyle: const TextStyle(
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
      ),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }
}
