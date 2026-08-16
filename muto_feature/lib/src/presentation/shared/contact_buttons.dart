import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/generated/muto_localizations.dart';
import '../listing/contact_channels.dart';

/// Every way to reach a seller, as one row.
///
/// One channel carries the call to action and the rest sit beside it as
/// squares: three equal buttons split a phone's width so finely that no label
/// survives, and they leave a reader with no idea which to press.
///
/// Shared by the listing and by the seller's own page, because the same
/// handles shown two different ways would be two things to learn instead of
/// one.
class ContactChannelRow extends StatelessWidget {
  const ContactChannelRow({
    super.key,
    required this.channels,
    required this.strings,
  });

  final List<ContactChannel> channels;
  final MutoLocalizations strings;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: _ContactButton(channel: channels.first, strings: strings),
        ),
        for (final channel in channels.skip(1)) ...[
          const SizedBox(width: AppSpacing.sm),
          _ContactButton(channel: channel, strings: strings, compact: true),
        ],
      ],
    );
  }
}

String _labelFor(ContactMedium medium, MutoLocalizations strings) =>
    switch (medium) {
      ContactMedium.telegram => strings.contactTelegram,
      ContactMedium.email => strings.contactEmail,
      ContactMedium.phone => strings.contactPhone,
    };

AppIconData _iconFor(ContactMedium medium) => switch (medium) {
  ContactMedium.telegram => AppIcons.telegram,
  ContactMedium.email => AppIcons.email,
  ContactMedium.phone => AppIcons.phone,
};

/// Telegram gets its own brand blue, since the mark only means something
/// paired with the colour it is always shown in. Phone gets the green a call
/// button carries everywhere. Email has no one brand to speak for — a
/// seller's address is as likely to be a university domain as Gmail — so it
/// stays in the app's own colour rather than borrowing one that would claim a
/// provider it does not know.
Color? _brandColorFor(ContactMedium medium) => switch (medium) {
  ContactMedium.telegram => AppColors.socialTelegram,
  ContactMedium.phone => AppColors.success,
  ContactMedium.email => null,
};

/// Copies a channel's handle, then tries to open the thing itself — the
/// chat, a blank email, the dialler.
///
/// Shared by every shape a contact channel is shown in, since the interaction
/// underneath a button and underneath a row of text is the same one: the two
/// halves run independently on purpose — a device with nothing to open the
/// chat should still leave the handle on the clipboard, and the chat should
/// not be kept waiting on a clipboard that is slow to answer — so the copy is
/// started and let go of, never awaited.
///
/// The destination is the [ContactChannel]'s own [Uri], built from a value
/// that already passed its shape check — no address arrives from outside and
/// is opened as given.
mixin _ContactReach<T extends StatefulWidget> on State<T> {
  bool copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> reach(ContactChannel channel) async {
    unawaited(
      _bestEffort(
        () => Clipboard.setData(ClipboardData(text: channel.display)),
      ),
    );
    setState(() => copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => copied = false);
    });

    await _bestEffort(
      () => launchUrl(channel.uri, mode: LaunchMode.externalApplication),
    );
  }

  /// Runs something the platform may simply refuse to do, and carries on.
  ///
  /// Neither half of [reach] is worth an error in front of the student:
  /// between them one will have worked, and the caller has already said so.
  Future<void> _bestEffort(Future<void> Function() action) async {
    try {
      await action();
    } on PlatformException {
      // nothing on this device answers to it
    } on MissingPluginException {
      // nor on a host that never registered the plugin
    }
  }
}

class _ContactButton extends StatefulWidget {
  const _ContactButton({
    required this.channel,
    required this.strings,
    this.compact = false,
  });

  final ContactChannel channel;
  final MutoLocalizations strings;

  /// Icon only, at button height and square, for the channels that stand
  /// beside the main one.
  final bool compact;

  @override
  State<_ContactButton> createState() => _ContactButtonState();
}

class _ContactButtonState extends State<_ContactButton>
    with _ContactReach<_ContactButton> {
  void _reachChannel() {
    unawaited(reach(widget.channel));
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final medium = widget.channel.medium;
    final label = _labelFor(medium, strings);
    final semanticLabel =
        '${strings.actionCopy} $label ${widget.channel.display}';

    final brand = _brandColorFor(medium);
    final compactAccent =
        brand ?? (isLight ? AppColors.primary : AppColors.primaryAccentDark);

    // the icon carries the whole confirmation on a compact button, so it swaps
    // to a tick there exactly as it does next to the label on the wide one
    final icon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: AppIcon(
        copied ? AppIcons.check : _iconFor(medium),
        key: ValueKey(copied),
        size: widget.compact ? 20 : 18,
        color: widget.compact ? compactAccent : AppColors.white,
      ),
    );
    if (widget.compact) {
      return Semantics(
        button: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: Tooltip(
          message: label,
          child: Material(
            // a brand colour keeps its own tint rather than the app's purple
            // one, so the square still says which channel it is once the
            // label has been dropped for space
            color:
                brand?.withValues(alpha: isLight ? 0.14 : 0.22) ??
                (isLight ? AppColors.primaryLight : AppColors.primaryLightDark),
            borderRadius: AppSpacing.borderRadiusMd,
            child: InkWell(
              borderRadius: AppSpacing.borderRadiusMd,
              onTap: _reachChannel,
              child: SizedBox.square(
                dimension: AppSpacing.buttonHeightDf,
                child: Center(child: icon),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: AppPrimaryButton(
        text: copied ? strings.copiedToClipboard : label,
        size: AppButtonSize.medium,
        icon: icon,
        backgroundColor: brand,
        onPressed: _reachChannel,
      ),
    );
  }
}

/// Every way to reach a seller, as a short list of "Telegram: @handle" rows
/// rather than a row of buttons.
///
/// Fits the seller page the buttons did not: this is a page of facts about
/// someone, read top to bottom, and a filled purple button in the middle of
/// it would read as the one action on the page rather than as one more thing
/// being said about them. A line of text sits at the same level as the join
/// date above it.
class ContactChannelList extends StatelessWidget {
  const ContactChannelList({
    super.key,
    required this.channels,
    required this.strings,
  });

  final List<ContactChannel> channels;
  final MutoLocalizations strings;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final channel in channels)
          _ContactRow(channel: channel, strings: strings),
      ],
    );
  }
}

class _ContactRow extends StatefulWidget {
  const _ContactRow({required this.channel, required this.strings});

  final ContactChannel channel;
  final MutoLocalizations strings;

  @override
  State<_ContactRow> createState() => _ContactRowState();
}

class _ContactRowState extends State<_ContactRow>
    with _ContactReach<_ContactRow> {
  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final medium = widget.channel.medium;
    final label = _labelFor(medium, strings);
    final accent =
        _brandColorFor(medium) ??
        (isLight ? AppColors.primary : AppColors.primaryAccentDark);
    final semanticLabel =
        '${strings.actionCopy} $label ${widget.channel.display}';

    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppSpacing.borderRadiusMd,
          onTap: () => unawaited(reach(widget.channel)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(_iconFor(medium), size: 18, color: accent),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  // no separate copy control: the row is the button, and its
                  // own value swaps to say "Copied" for the same beat every
                  // other copy control in the app uses, rather than a second
                  // element next to it that reads as its own button
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: copied
                        ? Text(
                            strings.copiedToClipboard,
                            key: const ValueKey(true),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : Text.rich(
                            key: const ValueKey(false),
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '$label: ',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                TextSpan(
                                  text: widget.channel.display,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: isLight
                                        ? AppColors.textPrimary
                                        : AppColors.textPrimaryDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Everything the owner may do to their own listing, taken from the transition
/// map so the screen can never offer a move the rules would refuse.
///
/// Pinned to the bottom like the buyer's contact bar, rather than sitting
/// inline in the scroll — a toolbar reads as a toolbar when it has its own
/// place, not when it is one more block of content under the description.
