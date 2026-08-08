import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:muto_ui/muto_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/listing.dart';
import '../../l10n/generated/muto_localizations.dart';
import 'contact_channels.dart';

/// Offers the seller's contact details, one row per channel.
///
/// Nothing opens on its own. Every channel asks first and names where it is
/// about to go, so leaving the app is always the student's decision.
Future<void> showContactSheet(
  BuildContext context, {
  required Listing listing,
  required MutoLocalizations strings,
}) {
  final channels = contactChannelsOf(listing.contact);
  return AppBottomSheet.show<void>(
    context: context,
    useRootNavigator: true,
    child: _ContactSheet(
      sellerName: listing.sellerDisplayName,
      channels: channels,
      strings: strings,
    ),
  );
}

class _ContactSheet extends StatelessWidget {
  const _ContactSheet({
    required this.sellerName,
    required this.channels,
    required this.strings,
  });

  final String sellerName;
  final List<ContactChannel> channels;
  final MutoLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.df,
        AppSpacing.sm,
        AppSpacing.df,
        AppSpacing.df,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetTitle(
            text: strings.contactSheetTitle(sellerName),
            isLight: isLight,
          ),
          const SizedBox(height: AppSpacing.df),
          for (final channel in channels)
            _ChannelRow(channel: channel, strings: strings),
        ],
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.channel, required this.strings});

  final ContactChannel channel;
  final MutoLocalizations strings;

  String get _label => switch (channel.medium) {
    ContactMedium.telegram => strings.contactTelegram,
    ContactMedium.email => strings.contactEmail,
    ContactMedium.phone => strings.contactPhone,
  };

  AppIconData get _icon => switch (channel.medium) {
    ContactMedium.telegram => AppIcons.telegram,
    ContactMedium.email => AppIcons.email,
    ContactMedium.phone => AppIcons.phone,
  };

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          AppIcon(_icon, size: 20, color: AppColors.iconSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  channel.display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: isLight
                        ? AppColors.textPrimary
                        : AppColors.textPrimaryDark,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            label: '${strings.actionCopy} ${channel.display}',
            button: true,
            excludeSemantics: true,
            child: IconButton(
              icon: const AppIcon(AppIcons.copy, size: 20),
              tooltip: strings.actionCopy,
              onPressed: () => _copy(context, channel.display),
            ),
          ),
          Semantics(
            label: '$_label ${channel.display}',
            button: true,
            excludeSemantics: true,
            child: IconButton(
              icon: const AppIcon(AppIcons.openInNew, size: 20),
              tooltip: strings.actionOpen,
              onPressed: () => _confirmAndOpen(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    AppToast.showSuccess(context, strings.copiedToClipboard);
  }

  Future<void> _confirmAndOpen(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.leaveAppTitle),
        // the destination is named in full, so the student sees where this
        // goes before it goes there
        content: Text(strings.leaveAppMessage(channel.uri.toString())),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.actionOpen),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await launchUrl(channel.uri, mode: LaunchMode.externalApplication);
  }
}
