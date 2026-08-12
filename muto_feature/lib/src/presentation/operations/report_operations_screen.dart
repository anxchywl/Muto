import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../application/muto_scope.dart';
import '../../application/report_operations_controller.dart';
import '../../domain/entities/operational_report.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../formatting/listing_labels.dart';

class ReportOperationsScreen extends StatefulWidget {
  const ReportOperationsScreen({super.key});

  @override
  State<ReportOperationsScreen> createState() => _ReportOperationsScreenState();
}

class _ReportOperationsScreenState extends State<ReportOperationsScreen> {
  ReportOperationsController? _controller;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final controller = ReportOperationsController(
      MutoScope.of(context).dependencies.reportOperations,
      onUnauthorized: MutoScope.of(context).session.reportExpired,
    );
    _controller = controller;
    unawaited(controller.load());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = MutoLocalizations.of(context);
    final controller = _controller!;
    final labels = ListingLabels(
      strings,
      Localizations.localeOf(context).toString(),
    );
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(strings.operationsReportsTitle),
      ),
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            if (controller.status == ReportOperationsStatus.loading &&
                controller.items.isEmpty) {
              return const Center(child: AppLoader());
            }
            if (controller.status == ReportOperationsStatus.failed &&
                controller.items.isEmpty) {
              return StateMessage(
                icon: AppIcons.alertCircle,
                title: strings.operationsReportsFailed,
                message: strings.errorGeneric,
                actionLabel: strings.actionRetry,
                onAction: () => unawaited(controller.load()),
              );
            }
            if (controller.items.isEmpty) {
              return StateMessage(
                icon: AppIcons.request,
                title: strings.operationsReportsEmpty,
                message: strings.operationsReportsEmptyMessage,
              );
            }
            return RefreshIndicator(
              onRefresh: controller.load,
              child: ListView.separated(
                padding: AppSpacing.screenPadding,
                itemCount:
                    controller.items.length +
                    (controller.hasMore ||
                            controller.status == ReportOperationsStatus.failed
                        ? 1
                        : 0),
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  if (index == controller.items.length) {
                    return AppSecondaryButton(
                      size: AppButtonSize.medium,
                      text: controller.status == ReportOperationsStatus.failed
                          ? strings.actionRetry
                          : strings.actionLoadMore,
                      onPressed: () => unawaited(controller.loadMore()),
                    );
                  }
                  return _ReportCard(
                    report: controller.items[index],
                    strings: strings,
                    labels: labels,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.strings,
    required this.labels,
  });

  final OperationalReport report;
  final MutoLocalizations strings;
  final ListingLabels labels;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    const secondary = AppColors.textSecondary;
    return AppCard(
      border: Border.all(
        color: isLight ? AppColors.borderGrey : AppColors.borderDark,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.listingTitle,
            style: AppTextStyles.titleSmall.copyWith(
              color: isLight
                  ? AppColors.textPrimary
                  : AppColors.textPrimaryDark,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${strings.operationsReasonLabel}: '
            '${labels.reportReason(report.reason)}',
            style: AppTextStyles.bodyMedium.copyWith(color: secondary),
          ),
          if (report.note case final note?) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${strings.operationsNoteLabel}: $note',
              style: AppTextStyles.bodyMedium.copyWith(color: secondary),
            ),
          ],
        ],
      ),
    );
  }
}
