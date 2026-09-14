import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/firebase_function_error_message.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';

class SendCouncilNotificationScreen extends ConsumerStatefulWidget {
  const SendCouncilNotificationScreen({super.key});

  @override
  ConsumerState<SendCouncilNotificationScreen> createState() =>
      _SendCouncilNotificationScreenState();
}

class _SendCouncilNotificationScreenState
    extends ConsumerState<SendCouncilNotificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  final String _requestId = const Uuid().v4();
  bool _sending = false;

  String _errorMessage(Object error, AppLocalizations strings) {
    if (error is FirebaseFunctionsException &&
        error.code == 'unauthenticated' &&
        ref.read(authServiceProvider).currentUser != null) {
      return strings.notificationSecurityVerificationFailed;
    }
    return firebaseFunctionErrorMessage(
      error,
      fallback: strings.couldNotSendNotification,
      unavailableMessage: strings.serviceUnavailable,
      unauthenticatedMessage: strings.notificationAuthRequired,
      permissionDeniedMessage: strings.notificationPermissionDenied,
      rateLimitedMessage: strings.notificationRateLimited,
      networkMessage: strings.notificationNetworkError,
      invalidArgumentMessage: strings.notificationInvalidData,
      alreadyExistsMessage: strings.notificationAlreadySent,
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send(String organizationId) async {
    if (_sending) return;
    if (!_formKey.currentState!.validate()) return;
    final strings = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(strings.confirmSendNotification),
            content: Text(strings.sendToAllCouncilMembers),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(strings.cancel)),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(strings.send)),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    if (_sending) return;
    final currentOrganizationId = ref
        .read(organizationContextProvider)
        .currentOrganization?['organizationId'];
    if (currentOrganizationId != organizationId ||
        organizationId.trim().isEmpty ||
        ref
                .read(adminAccessProvider)
                .valueOrNull
                ?.canSendCouncilNotifications !=
            true ||
        ref.read(authServiceProvider).currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.notificationPermissionDenied)),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final count = await ref
          .read(councilManagementRepositoryProvider)
          .sendCouncilNotification(
            requestId: _requestId,
            organizationId: organizationId,
            title: _title.text,
            body: _body.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.notificationSentTo(count))),
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_errorMessage(error, strings)),
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final organizationId = ref
        .watch(organizationContextProvider)
        .currentOrganization?['organizationId'] as String?;
    final access = ref.watch(adminAccessProvider).valueOrNull;
    if (organizationId == null || access?.canSendCouncilNotifications != true) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.sendNotification)),
        body: Center(child: Text(strings.accessDenied)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(strings.sendNotification)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(strings.sendToAllCouncilMembers),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              maxLength: 120,
              decoration: InputDecoration(labelText: strings.notificationTitle),
              validator: (value) => value == null || value.trim().isEmpty
                  ? strings.requiredField
                  : null,
            ),
            TextFormField(
              controller: _body,
              maxLength: 1000,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(labelText: strings.notificationBody),
              validator: (value) => value == null || value.trim().isEmpty
                  ? strings.requiredField
                  : null,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending ? null : () => _send(organizationId),
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_outlined),
              label: Text(strings.send),
            ),
          ],
        ),
      ),
    );
  }
}
