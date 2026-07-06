import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../presentation/screens/member/council_booking_screen.dart';

/// التوجيه الموحّد عند النقر على أي إشعار (داخلي عبر مركز الإشعارات، أو خارجي
/// عبر Push في الخلفية/الإغلاق). المصدر الوحيد لمنطق فتح الشاشة الصحيحة حسب
/// نوع الحدث والمجلس المرتبط، مع تبديل سياق المجلس عند الحاجة.
class NotificationDeepLink {
  const NotificationDeepLink._();

  /// نوع الإشعار → مسار شاشة المراجعة الإدارية (للطلبات الجديدة فقط)، أو null.
  static String? reviewRouteFor(String type) {
    switch (type) {
      case 'bookingSubmitted':
        return 'bookingRequestsReview';
      case 'membershipRequestSubmitted':
        return 'membershipRequestsReview';
      case 'receiptSubmitted':
        return 'financialReview';
      default:
        return null;
    }
  }

  /// يفتح الشاشة المناسبة للإشعار. يُستدعى من مركز الإشعارات ومن معالج نقر Push.
  static Future<void> open(
    BuildContext context,
    WidgetRef ref, {
    required String type,
    required String relatedEntityType,
    required String relatedEntityId,
    String? organizationId,
  }) async {
    final currentUserId = ref.read(authStateProvider).value?.uid;

    // 1) إشعارات الطلبات الجديدة الموجَّهة للمراجِعين: افتح شاشة المراجعة داخل
    //    نفس المجلس الذي ورد منه الطلب مباشرةً ليعتمد المسؤول فورًا.
    final reviewRoute = reviewRouteFor(type);
    if (reviewRoute != null &&
        organizationId != null &&
        organizationId.isNotEmpty &&
        currentUserId != null) {
      final entered = await enterOrganization(ref, organizationId, currentUserId);
      if (!context.mounted) return;
      if (!entered) {
        _toast(context, 'تعذّر فتح مجلس الطلب. تأكّد من صلاحياتك والاتصال.');
        return;
      }
      context.pushNamed(reviewRoute);
      return;
    }

    // 2) إشعارات النتائج الموجَّهة لصاحب الطلب: افتح شاشته داخل مجلس الإشعار.
    final hasOrg = organizationId != null && organizationId.isNotEmpty;
    switch (relatedEntityType) {
      case 'booking':
        if (hasOrg) {
          context.pushNamed(
            'rentalPlaceholder',
            extra: CouncilBookingArguments(organizationId: organizationId),
          );
        }
        return;
      case 'receipt':
        // بدّل سياق المجلس أولًا حتى يعرض سجل الإيصالات إيصالات هذا المجلس فقط.
        if (hasOrg && currentUserId != null) {
          await enterOrganization(ref, organizationId, currentUserId);
        }
        if (!context.mounted) return;
        context.pushNamed('receiptHistory');
        return;
      case 'membership':
      case 'membershipRequest':
        context.goNamed('memberHome');
        return;
      default:
        return;
    }
  }

  /// يبدّل سياق المجلس إلى [organizationId]: كعضو إن كان له عضوية نشطة، وإلا
  /// كمشرف منصّة. يُرجع false إذا تعذّر الدخول.
  static Future<bool> enterOrganization(
    WidgetRef ref,
    String organizationId,
    String userId,
  ) async {
    final current = ref
        .read(organizationContextProvider)
        .currentOrganization?['organizationId'] as String?;
    if (current == organizationId) return true;
    final notifier = ref.read(organizationContextProvider.notifier);
    try {
      await notifier.selectOrganization(
        organizationId: organizationId,
        userId: userId,
      );
      return true;
    } catch (_) {
      final isSuperAdmin =
          ref.read(adminAccessProvider).valueOrNull?.isSuperAdmin ?? false;
      if (!isSuperAdmin) return false;
      try {
        await notifier.selectOrganizationAsSuperAdmin(organizationId);
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
