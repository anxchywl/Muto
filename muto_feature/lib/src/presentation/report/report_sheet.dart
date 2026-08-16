import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../application/muto_scope.dart';
import '../../application/report_controller.dart';
import '../../domain/entities/report_reason.dart';
import '../../domain/failures.dart';
import '../../domain/validation/report_rules.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../formatting/listing_labels.dart';
import '../shared/focus_mode.dart';

/// Tells whoever runs the marketplace that something is wrong with a listing.
///
/// One way and one time: there is no queue to watch, no verdict to wait for
/// and nothing here that says whether anyone else has reported the same thing.
Future<bool?> showReportSheet(
  BuildContext context, {
  required String listingId,
  required ListingLabels labels,
}) {
  final scope = MutoScope.of(context);
  return AppBottomSheet.show<bool>(
    context: context,
    useRootNavigator: true,
    child: _ReportSheet(
      controller: ReportController(
        reports: scope.dependencies.reports,
        listingId: listingId,
        generation: scope.generation,
        onUnauthorized: scope.session.reportExpired,
      ),
      labels: labels,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.controller, required this.labels});

  final ReportController controller;
  final ListingLabels labels;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

/// The one field this sheet has, named so focus mode can talk about it.
enum _Field { note }

class _ReportSheetState extends State<_ReportSheet> {
  final TextEditingController _note = TextEditingController();
  final SheetFocusMode _focus = SheetFocusMode();

  @override
  void initState() {
    super.initState();
    // there is no picker any more, and a note-only report is exactly what
    // this reason already means in the domain — "other" is the one case that
    // requires a note rather than standing on its own
    widget.controller.select(ReportReason.other);
  }

  @override
  void dispose() {
    _note.dispose();
    _focus.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final sent = await widget.controller.submit();
    if (!sent || !mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final strings = widget.labels.strings;
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.df,
        AppSpacing.sm,
        AppSpacing.df,
        AppSpacing.df,
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([controller, _focus]),
        builder: (context, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetTitle(text: strings.reportTitle, isLight: isLight),

              // the promise of anonymity is worth reading before you write,
              // not while — it folds away with the keyboard up and comes
              // straight back when the note is finished
              FocusFold(
                hidden: _focus.hidesChrome,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        strings.reportSubtitle,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.df),

              AppTextField(
                controller: _note,
                focusNode: _focus.nodeFor(_Field.note),
                label: strings.reportNoteLabelRequired,
                hint: strings.reportNoteHint,
                maxLines: 3,
                maxLength: ReportRules.noteMax,
                errorText: _issueMessage(controller.issue, strings),
                onChanged: controller.noteChanged,
              ),

              if (controller.failure != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _failureMessage(controller.failure!, strings),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.lg),
              // no Done button here, unlike the editor: this sheet has one
              // field and one thing to do with it, so putting the keyboard
              // away is never a step worth asking for on the way to sending
              AppPrimaryButton(
                text: strings.actionSendReport,
                size: AppButtonSize.large,
                isLoading: controller.isSending,
                // a second tap while the first is in flight sends nothing, and
                // a retry reuses the token so it cannot become two reports
                onPressed: controller.canSubmit
                    ? () => unawaited(_submit())
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }
}

String? _issueMessage(ReportIssue? issue, MutoLocalizations strings) {
  if (issue == null) return null;
  return switch (issue) {
    ReportIssue.noteMissing => strings.reportNoteRequired,
    ReportIssue.noteTooLong => strings.reportNoteTooLong,
  };
}

String _failureMessage(MutoFailure failure, MutoLocalizations strings) {
  return switch (failure) {
    NetworkFailure() => strings.errorOffline,
    RateLimitedFailure() => strings.reportTooMany,
    _ => strings.errorGeneric,
  };
}
