import 'dart:async';
import 'dart:math' as math;

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../application/muto_scope.dart';
import '../../domain/entities/listing.dart';
import '../../domain/entities/listing_status.dart';
import '../../domain/failures.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../formatting/listing_labels.dart';
import '../editor/listing_editor_sheet.dart';
import '../report/report_sheet.dart';
import '../seller/seller_profile_screen.dart';
import '../shared/confirm_sheet.dart';
import '../shared/contact_buttons.dart';
import 'contact_channels.dart';
import 'listing_detail_visuals.dart';
import 'owner_actions.dart';

/// One listing in full.
///
/// The cached copy paints immediately and the listing is always re-read on
/// open, because status is the field most likely to have moved since the feed
/// was loaded.
class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({
    super.key,
    required this.listingId,
    this.preloaded,
  });

  final String listingId;

  /// The row that opened this screen, used to paint something at once.
  final Listing? preloaded;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  Listing? _listing;
  MutoFailure? _failure;

  @override
  void initState() {
    super.initState();
    _listing =
        widget.preloaded ?? MutoScope.of(context).cache.peek(widget.listingId);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final scope = MutoScope.of(context);
    final generation = scope.generation.value;
    final cached = scope.cache.peek(widget.listingId);
    if (mounted &&
        cached != null &&
        (_listing == null || cached.contact != null)) {
      setState(() {
        _listing = cached;
        _failure = null;
      });
    } else if (mounted) {
      setState(() => _failure = null);
    }

    try {
      final listing = await scope.dependencies.listings.byId(widget.listingId);
      if (!mounted || !scope.generation.isCurrent(generation)) return;
      scope.cache.absorb(listing);
      setState(() {
        _listing = listing;
      });
    } on MutoFailure catch (failure) {
      if (!mounted || !scope.generation.isCurrent(generation)) return;
      if (failure is UnauthorizedFailure) scope.session.reportExpired();
      setState(() {
        _failure = failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = MutoLocalizations.of(context);
    final labels = ListingLabels(
      strings,
      Localizations.localeOf(context).toString(),
    );
    final listing = _listing;
    final failure = _failure;
    final identity = MutoScope.of(context).session.identity;
    final isOwner =
        listing != null && identity != null && listing.isOwnedBy(identity);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? AppColors.background
          : AppColors.black,
      body: switch ((listing, failure)) {
        (null, final MutoFailure f) => SafeArea(
          child: Column(
            children: [
              _FloatingBar(canReport: false, labels: labels),
              Expanded(
                child: _Unavailable(failure: f, strings: strings),
              ),
            ],
          ),
        ),
        (null, null) => const Center(child: AppLoader()),
        (final Listing value, _) => _Content(
          listing: value,
          labels: labels,
          isOwner: isOwner,
          onUpdated: (updated) => setState(() => _listing = updated),
        ),
      },
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.failure, required this.strings});

  final MutoFailure failure;
  final MutoLocalizations strings;

  @override
  Widget build(BuildContext context) {
    // a listing the seller took down and one that never existed are different
    // situations, and saying which is the difference between an explanation
    // and an error
    final (title, message) = switch (failure) {
      GoneFailure() => (
        strings.listingUnavailableTitle,
        strings.listingRemovedMessage,
      ),
      NotFoundFailure() => (
        strings.listingUnavailableTitle,
        strings.listingNotFoundMessage,
      ),
      NetworkFailure() => (strings.browseErrorTitle, strings.errorOffline),
      _ => (strings.browseErrorTitle, strings.errorGeneric),
    };

    return StateMessage(
      icon: AppIcons.alertCircle,
      title: title,
      message: message,
      actionLabel: strings.actionBackToBrowse,
      onAction: () => Navigator.of(context).maybePop(),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.listing,
    required this.labels,
    required this.isOwner,
    required this.onUpdated,
  });

  final Listing listing;
  final ListingLabels labels;
  final bool isOwner;
  final ValueChanged<Listing> onUpdated;

  @override
  Widget build(BuildContext context) {
    final scope = MutoScope.of(context);
    final strings = labels.strings;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final identity = scope.session.identity;
    final isVerified = identity?.isVerified ?? false;
    final channels = contactChannelsOf(listing.contact);
    final notice = _noticeFor(listing.status, strings, isOwner: isOwner);
    final showContactBar =
        !isOwner &&
        isVerified &&
        channels.isNotEmpty &&
        listing.status != ListingStatus.sold;

    // the bars are pinned over the scroll, so the last line of the listing has
    // to stop above them rather than behind them — a bar's own height plus the
    // home-indicator inset it carries
    final bottomReserve = showContactBar || isOwner
        ? AppSpacing.xxxxl +
              AppSpacing.df +
              MediaQuery.paddingOf(context).bottom
        : AppSpacing.xl;

    final content = Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: ListingImageGallery(
                  images: listing.images,
                  title: listing.title,
                  strings: strings,
                  price: labels.detailPrice(listing),
                  header: _FloatingBar(
                    canReport: !isOwner,
                    listingId: isOwner ? null : listing.id,
                    labels: labels,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: const Offset(0, -sheetOverlap),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isLight ? AppColors.background : AppColors.black,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    // the sheet is pulled up over the photo, so its top
                    // padding has to clear that overlap before it counts as
                    // breathing room — otherwise the first line sits flush
                    // against the picture
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.df,
                      sheetOverlap + AppSpacing.xl,
                      AppSpacing.df,
                      bottomReserve,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (notice != null) ...[
                          _Notice(text: notice),
                          const SizedBox(height: AppSpacing.df),
                        ],
                        Text(
                          listing.title,
                          style: AppTextStyles.titleLarge.copyWith(
                            color: isLight
                                ? AppColors.textPrimary
                                : AppColors.textPrimaryDark,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          labels.postedDate(listing.createdAt),
                          style: AppTextStyles.labelSmall.copyWith(
                            color: isLight
                                ? AppColors.textSecondary
                                : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            MetaChip(
                              label: labels.condition(listing.condition),
                            ),
                            MetaChip(label: labels.category(listing.category)),
                          ],
                        ),
                        if (!isOwner) ...[
                          const SizedBox(height: AppSpacing.lg),
                          const DetailDivider(),
                          const SizedBox(height: AppSpacing.lg),
                          _SellerCard(listing: listing, strings: strings),
                        ],
                        if (listing.description.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          const DetailDivider(),
                          const SizedBox(height: AppSpacing.lg),
                          // plain text, never rich or auto-linked, so a
                          // crafted description cannot become a tappable
                          // destination
                          DetailSection(
                            title: strings.detailDescription,
                            body: listing.description,
                          ),
                        ],
                        if (listing.wantedItems != null) ...[
                          const SizedBox(height: AppSpacing.lg),
                          DetailSection(
                            title: strings.detailLookingFor,
                            body: listing.wantedItems!,
                          ),
                        ],
                        if (!isOwner && !isVerified) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            strings.contactUnavailableUnverified,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showContactBar)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ContactBar(channels: channels, strings: strings),
          ),
        if (isOwner)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _OwnerActionsBar(
              listing: listing,
              strings: strings,
              onUpdated: onUpdated,
            ),
          ),
      ],
    );

    if (!_isInactive) return content;
    return Opacity(
      opacity: 0.62,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: content,
      ),
    );
  }

  bool get _isInactive => listing.status == ListingStatus.reserved && !isOwner;
}

/// The owner and a shopper are told different things by the same status: one
/// is being informed a deal is off the table, the other is being reminded of
/// a choice they made. Staying on the screen after a status change is what
/// makes the difference visible, so it has to be worded for whoever is there.
String? _noticeFor(
  ListingStatus status,
  MutoLocalizations strings, {
  required bool isOwner,
}) {
  if (isOwner) {
    return null;
  }
  return switch (status) {
    ListingStatus.sold => strings.noticeSold,
    ListingStatus.reserved => null,
    _ => null,
  };
}

/// An action's icon, which acts out the move at the moment it lands.
///
/// The frames are real icons from the set rather than anything drawn here: the
/// clock has a face for every hour and the eye has an open, a shut and a
/// struck-through state, so stepping through them animates the thing itself
/// instead of dissolving it into a generic tick.
class _AnimatedActionIcon extends StatefulWidget {
  const _AnimatedActionIcon({
    required this.icon,
    required this.motion,
    required this.playing,
    required this.rewindOnStop,
    required this.color,
    required this.size,
  });

  final AppIconData icon;
  final OwnerActionMotion motion;
  final bool playing;

  /// The move came back refused, so the motion walks backwards to undo itself.
  /// A move that landed does not: the hand is already home at the end of its
  /// sweep, and running it in reverse reads as the move being taken back.
  final bool rewindOnStop;

  final Color color;
  final double size;

  @override
  State<_AnimatedActionIcon> createState() => _AnimatedActionIconState();
}

class _AnimatedActionIconState extends State<_AnimatedActionIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // built here rather than lazily: the ticker mixin reaches for the ticker
    // mode on activate and dispose, and a controller that has not been touched
    // yet would be created at exactly the wrong moment
    _controller = AnimationController(vsync: this, duration: _confirmationHold);
  }

  @override
  void didUpdateWidget(_AnimatedActionIcon old) {
    super.didUpdateWidget(old);
    if (widget.playing && !old.playing) _controller.forward(from: 0);
    if (!widget.playing && old.playing) {
      // refused: unwind, so the eye reopens and the hand walks back.
      // landed: drop straight home instead of replaying the sweep backwards —
      // the bar is about to be rebuilt around the new status, and a rewind
      // running underneath that read as the move undoing itself
      if (widget.rewindOnStop) {
        _controller.reverse();
      } else {
        _controller.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.motion == OwnerActionMotion.none) return _icon(widget.icon);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        if (t == 0) return _icon(widget.icon);

        return switch (widget.motion) {
          OwnerActionMotion.sweep => _sweep(t),
          OwnerActionMotion.spin => _spin(t),
          OwnerActionMotion.close => _close(t),
          OwnerActionMotion.confirm => _confirm(t),
          OwnerActionMotion.none => _icon(widget.icon),
        };
      },
    );
  }

  Widget _icon(AppIconData icon) =>
      AppIcon(icon, size: widget.size, color: widget.color);

  /// The hand goes round once, easing out so it settles rather than stopping
  /// dead, and lands back at twelve.
  Widget _sweep(double t) {
    final eased = Curves.easeOutCubic.transform(t);
    final faces = AppIcons.clockHours;
    // wraps rather than clamps, so the last frame is twelve again and the hand
    // completes the circle instead of stopping an hour short of it
    final frame = (eased * faces.length).floor() % faces.length;
    return _icon(faces[frame]);
  }

  /// A full turn, which is what the arrows on the icon are drawn to suggest.
  Widget _spin(double t) {
    return Transform.rotate(
      angle: Curves.easeInOutCubic.transform(t) * 2 * math.pi,
      child: _icon(widget.icon),
    );
  }

  /// Open, then shut, then struck through — with the squash of a real blink
  /// on the frame where the lid meets.
  Widget _close(double t) {
    final (frame, squash) = switch (t) {
      < 0.35 => (AppIcons.visibility, 1.0),
      < 0.6 => (AppIcons.visibilityClosing, 0.75),
      _ => (AppIcons.visibilityOff, 1.0),
    };
    return Transform.scale(scaleY: squash, child: _icon(frame));
  }

  /// The second tick arrives beside the first, and the pair settle together.
  Widget _confirm(double t) {
    final eased = Curves.easeOutBack.transform(t.clamp(0.0, 1.0));
    return Transform.scale(
      scale: 1 + 0.18 * math.sin(math.pi * Curves.easeOut.transform(t)),
      child: _icon(eased > 0.35 ? AppIcons.markAsRead : widget.icon),
    );
  }
}

/// Back and report/favorite controls, floating over the photo rather than
/// living in an app bar — the photo has no room to spare beneath them.
class _FloatingBar extends StatefulWidget {
  const _FloatingBar({
    required this.canReport,
    required this.labels,
    this.listingId,
  });

  final bool canReport;
  final String? listingId;
  final ListingLabels labels;

  @override
  State<_FloatingBar> createState() => _FloatingBarState();
}

class _FloatingBarState extends State<_FloatingBar> {
  bool _reported = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final strings = labels.strings;
    final listingId = widget.listingId;
    final top = MediaQuery.paddingOf(context).top + AppSpacing.sm;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.df,
        top,
        AppSpacing.df,
        AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          DetailRoundIconButton(
            icon: AppIcons.back,
            tooltip: strings.actionBackToBrowse,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Row(
            children: [
              if (listingId != null) _FavoriteRoundButton(listingId: listingId),
              if (widget.canReport && listingId != null) ...[
                const SizedBox(width: AppSpacing.sm),
                DetailRoundIconButton(
                  icon: _reported ? AppIcons.check : AppIcons.flag,
                  // the tick is the confirmation, so it says what happened
                  // rather than still offering the thing already done
                  tooltip: _reported
                      ? strings.reportSent
                      : strings.actionReportListing,
                  color: _reported ? AppColors.success : AppColors.primary,
                  backgroundColor: AppColors.white,
                  onPressed: () => unawaited(_report(context, listingId)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _report(BuildContext context, String listingId) async {
    final sent = await showReportSheet(
      context,
      listingId: listingId,
      labels: widget.labels,
    );
    if (sent != true || !mounted) return;
    setState(() => _reported = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(_confirmationLinger, () {
      if (mounted) setState(() => _reported = false);
    });
  }
}

class _FavoriteRoundButton extends StatefulWidget {
  const _FavoriteRoundButton({required this.listingId});

  final String listingId;

  @override
  State<_FavoriteRoundButton> createState() => _FavoriteRoundButtonState();
}

class _FavoriteRoundButtonState extends State<_FavoriteRoundButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Which way the last tap went. Saving something is worth a flourish;
  /// taking it back is not, so it gets a smaller, quieter version.
  bool _saving = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _heartBeat);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle(bool saved) {
    setState(() => _saving = !saved);
    _controller.forward(from: 0);
    final scope = MutoScope.of(context);
    unawaited(
      scope.savedListings.toggle(
        widget.listingId,
        listing: scope.cache.peek(widget.listingId),
      ),
    );
  }

  /// Up and back down in one arc — a sine over the run, so it leaves and
  /// returns to rest without a seam at either end.
  double get _scale {
    if (_controller.value == 0) return 1;
    // easeOut rather than easeOutBack: the overshoot pushed the peak past the
    // swell it was multiplying and then dipped back under rest on the way out,
    // which is what made a small acknowledgement read as a lurch
    final swell = math.sin(
      math.pi * Curves.easeOut.transform(_controller.value),
    );
    return _saving ? 1 + 0.22 * swell : 1 - 0.1 * swell;
  }

  @override
  Widget build(BuildContext context) {
    final favorites = MutoScope.of(context).savedListings;
    final strings = MutoLocalizations.of(context);

    return ListenableBuilder(
      listenable: favorites,
      builder: (context, _) {
        final saved = favorites.isSaved(widget.listingId);

        return TweenAnimationBuilder<Color?>(
          duration: _confirmationFade,
          curve: Curves.easeOutCubic,
          tween: ColorTween(begin: AppColors.error, end: AppColors.error),
          builder: (context, color, _) => AnimatedBuilder(
            animation: _controller,
            builder: (context, child) =>
                Transform.scale(scale: _scale, child: child),
            child: DetailRoundIconButton(
              icon: AppIcons.heart,
              tooltip: saved
                  ? strings.actionUnsaveListing
                  : strings.actionSaveListing,
              color: saved ? AppColors.error : AppColors.primary,
              backgroundColor: AppColors.white,
              onPressed: () => _toggle(saved),
            ),
          ),
        );
      },
    );
  }
}

/// Long enough to read as a beat, short enough to keep up with a double tap.
const Duration _heartBeat = Duration(milliseconds: 340);

/// Who is selling, and the way through to everything else they have listed —
/// a bordered card rather than a plain row, so it reads as its own tappable
/// unit the way a seller block does on OLX or Avito.
/// Who is selling, read as one of the listing's sections rather than as a
/// tile dropped into it.
///
/// It used to be a bordered box in a page that has no other boxes, which made
/// the one piece of the listing that is a person look like a form field. It
/// now carries the same small grey heading as Description does, and the row
/// underneath is the content of that section.
class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.listing, required this.strings});

  final Listing listing;
  final MutoLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final name = listing.sellerDisplayName;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Semantics(
      button: true,
      label: strings.openSellerSemantics(name),
      excludeSemantics: true,
      container: true,
      child: InkWell(
        borderRadius: AppSpacing.borderRadiusMd,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SellerProfileScreen(
              sellerId: listing.sellerId,
              sellerDisplayName: name,
              contact: listing.contact,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.detailSeller,
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                CircleAvatar(
                  radius: AppSpacing.avatarMd / 2,
                  backgroundColor: isLight
                      ? AppColors.primaryLight
                      : AppColors.primaryLightDark,
                  child: Text(
                    initial,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: isLight
                          ? AppColors.primary
                          : AppColors.primaryAccentDark,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleSmall.copyWith(
                      color: isLight
                          ? AppColors.textPrimary
                          : AppColors.textPrimaryDark,
                    ),
                  ),
                ),
                // the only thing saying this row leads somewhere, now that the
                // border is gone
                AppIcon(
                  AppIcons.chevronRight,
                  size: 20,
                  color: AppColors.iconSecondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactBar extends StatelessWidget {
  const _ContactBar({required this.channels, required this.strings});

  final List<ContactChannel> channels;
  final MutoLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.df,
        AppSpacing.sm,
        AppSpacing.df,
        AppSpacing.sm + bottomInset,
      ),
      child: ContactChannelRow(channels: channels, strings: strings),
    );
  }
}

class _OwnerActionsBar extends StatefulWidget {
  const _OwnerActionsBar({
    required this.listing,
    required this.strings,
    required this.onUpdated,
  });

  final Listing listing;
  final MutoLocalizations strings;

  /// Hands the changed listing back so the screen repaints around it — the
  /// notice, the chips and which moves are still allowed all follow status.
  final ValueChanged<Listing> onUpdated;

  @override
  State<_OwnerActionsBar> createState() => _OwnerActionsBarState();
}

class _OwnerActionsBarState extends State<_OwnerActionsBar> {
  bool _busy = false;

  /// The move currently under way. Its button plays its motion from the
  /// instant of the press, and the bar is rebuilt around the new status only
  /// once that motion has run — the button that was pressed is usually retired
  /// by its own move, and would otherwise vanish mid-animation.
  ListingStatus? _playing;

  /// The last move came back refused, so its motion has to walk itself back.
  /// Cleared on the next press, since a fresh move starts from home either way.
  bool _rewind = false;

  Future<void> _apply(OwnerAction action) async {
    if (_busy) return;
    final scope = MutoScope.of(context);
    final strings = widget.strings;

    if (action.isDestructive) {
      final confirmed = await showConfirmSheet(
        context,
        title: strings.removeListingTitle,
        confirmLabel: strings.actionRemove,
        cancelLabel: strings.actionCancel,
        isDestructive: true,
      );
      if (!confirmed || !mounted) return;
    }

    // the motion starts on the press rather than on the answer: waiting for
    // the server first left the bar sitting greyed and still for as long as
    // the round trip took, and only then began to move
    setState(() {
      _busy = true;
      _rewind = false;
      _playing = action.motion == OwnerActionMotion.none ? null : action.next;
    });
    final startedAt = DateTime.now();
    final generation = scope.generation.value;
    try {
      final updated = await scope.dependencies.listings.changeStatus(
        widget.listing.id,
        action.next,
        expected: widget.listing.version,
      );
      if (!mounted || !scope.generation.isCurrent(generation)) return;
      scope.cache.patch(updated);
      unawaited(scope.mine.refresh());

      // a removed listing has nothing left to show, so that one move still
      // closes the screen; every other move leaves the owner looking at the
      // listing they just changed, now repainted around its new status
      if (action.isDestructive) {
        unawaited(Navigator.of(context).maybePop());
        return;
      }

      // if the answer beat the animation, let the animation finish; if it was
      // slower, hand over at once rather than adding a wait to a wait
      final remaining =
          _confirmationHold - DateTime.now().difference(startedAt);
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      if (!mounted) return;
      setState(() => _playing = null);
      widget.onUpdated(updated);
    } on MutoFailure catch (failure) {
      if (!mounted) return;
      if (failure is UnauthorizedFailure) scope.session.reportExpired();
      // the move did not happen, so the icon goes back the way it came
      setState(() {
        _rewind = true;
        _playing = null;
      });
      AppToast.showError(
        context,
        failure is ConflictFailure
            ? strings.editorConflictMessage
            : strings.errorGeneric,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final saved = await showListingEditorSheet(
      context,
      editing: widget.listing,
    );
    if (saved == null || !mounted) return;
    // the editor's own submit button already showed a tick on its way out, so
    // this only has to put the changes on screen
    widget.onUpdated(saved);
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final actions = ownerActionsFor(widget.listing.status, strings);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      // the same geometry as the shell's navigation bar: the inset is left to
      // each item so the strip above the home indicator is still tappable
      padding: const EdgeInsets.only(
        left: AppSpacing.df,
        right: AppSpacing.df,
        top: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isLight ? AppColors.surface : AppColors.surfaceDark,
        boxShadow: HomeShadows.navBar,
        border: Border(
          top: BorderSide(
            color: isLight ? AppColors.borderGrey : AppColors.borderDark,
          ),
        ),
      ),
      // every button is keyed to the move it makes, because the set of moves
      // changes with status: without keys the row matches children by position
      // and hands a retired button's live animation controller to whichever
      // different action slid into its place, which is what made the clock
      // flicker and run backwards on the way from Reserve to Relist
      child: Row(
        children: [
          if (widget.listing.status.isEditable)
            Expanded(
              child: _OwnerActionButton(
                key: const ValueKey('edit'),
                icon: AppIcons.edit,
                label: strings.actionShortEdit,
                semanticLabel: strings.actionEditListing,
                tone: _ActionTone.accent,
                bottomInset: bottomInset + AppSpacing.xs,
                onPressed: _busy ? null : () => unawaited(_edit()),
              ),
            ),
          for (final action in actions)
            Expanded(
              child: _OwnerActionButton(
                key: ValueKey(action.next),
                icon: action.icon,
                label: action.shortLabel,
                semanticLabel: action.label,
                tone: action.isDestructive
                    ? _ActionTone.destructive
                    : _ActionTone.neutral,
                bottomInset: bottomInset + AppSpacing.xs,
                motion: action.motion,
                playing: _playing == action.next,
                rewindOnStop: _rewind,
                onPressed: _busy ? null : () => unawaited(_apply(action)),
              ),
            ),
        ],
      ),
    );
  }
}

/// How much weight an owner action carries, which is the whole reason this bar
/// is not five identical buttons: editing is the everyday move, removing is
/// the one that cannot be taken back, and the rest sit between them.
enum _ActionTone { accent, neutral, destructive }

/// One owner action, drawn the way a destination in the shell's navigation bar
/// is drawn — an icon in a pill with its word underneath — so the bar reads as
/// part of the same app rather than as a row of anonymous glyphs.
class _OwnerActionButton extends StatelessWidget {
  const _OwnerActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.tone,
    required this.bottomInset,
    required this.onPressed,
    this.motion = OwnerActionMotion.none,
    this.playing = false,
    this.rewindOnStop = false,
  });

  final AppIconData icon;

  /// What [icon] does when this button's move lands.
  final OwnerActionMotion motion;

  /// The word under the icon.
  final String label;

  /// The full sentence, for a screen reader and for the tooltip.
  final String semanticLabel;

  final _ActionTone tone;

  /// Sits inside the tap target, under the label, matching the navigation bar.
  final double bottomInset;

  final VoidCallback? onPressed;

  /// This button's move is under way: the icon plays out its [motion] and the
  /// pill fills in, from the press until the bar is rebuilt around the new
  /// status — or until the move fails and the motion runs backwards.
  final bool playing;

  /// Whether the motion that just stopped should unwind rather than cut home.
  final bool rewindOnStop;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final enabled = onPressed != null;

    final base = switch (tone) {
      _ActionTone.accent =>
        isLight ? AppColors.primary : AppColors.primaryAccentDark,
      _ActionTone.destructive => AppColors.error,
      _ActionTone.neutral => AppColors.iconSecondary,
    };
    // a move under way is worth seeing whatever tone it started in
    final accent = playing
        ? (isLight ? AppColors.primary : AppColors.primaryAccentDark)
        : base;
    final pill = switch (tone) {
      _ActionTone.accent =>
        isLight ? AppColors.primaryLight : AppColors.primaryLightDark,
      _ActionTone.destructive => AppColors.error.withValues(alpha: 0.12),
      _ActionTone.neutral => Colors.transparent,
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: semanticLabel,
        child: AnimatedOpacity(
          duration: _confirmationFade,
          // the rest of the bar dims and stops taking taps while a move is in
          // flight; the button that was pressed stays lit, because it is the
          // one doing the talking
          opacity: enabled || playing ? 1 : 0.4,
          child: InkWell(
            onTap: onPressed,
            borderRadius: AppSpacing.borderRadiusMd,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: _confirmationFade,
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: playing
                          ? (isLight
                                ? AppColors.primaryLight
                                : AppColors.primaryLightDark)
                          : pill,
                      borderRadius: AppSpacing.borderRadiusMd,
                    ),
                    child: _AnimatedActionIcon(
                      icon: icon,
                      motion: motion,
                      playing: playing,
                      rewindOnStop: rewindOnStop,
                      size: 22,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AnimatedDefaultTextStyle(
                    duration: _confirmationFade,
                    curve: Curves.easeOutCubic,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: accent,
                      fontWeight: tone == _ActionTone.neutral && !playing
                          ? FontWeight.w500
                          : FontWeight.w600,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Long enough for a tick to register before the bar is rebuilt around the
/// status it just moved to.
const Duration _confirmationHold = Duration(milliseconds: 650);
const Duration _confirmationFade = Duration(milliseconds: 200);

/// A confirmation that is not followed by the screen closing has to stand on
/// its own for long enough to be read, then quietly go back.
const Duration _confirmationLinger = Duration(milliseconds: 2500);

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: AppSpacing.borderRadiusMd,
      ),
      child: Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning),
      ),
    );
  }
}
