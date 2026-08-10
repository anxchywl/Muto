import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../application/muto_scope.dart';
import '../../config/muto_config.dart';
import '../../domain/entities/listing.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../browse/browse_screen.dart';
import '../editor/listing_editor_screen.dart';
import '../favorites/favorites_screen.dart';
import '../listing/listing_detail_screen.dart';
import '../my_listings/my_listings_screen.dart';

/// The feature's own navigation surface.
///
/// It keeps its stack inside a nested navigator so a host can push its own
/// routes above the feature without the two fighting over one stack.
class MutoShell extends StatefulWidget {
  const MutoShell({super.key, required this.config});

  final MutoConfig config;

  @override
  State<MutoShell> createState() => _MutoShellState();
}

class _MutoShellState extends State<MutoShell> {
  // one navigator per destination, so switching tabs keeps each stack rather
  // than throwing it away
  final List<GlobalKey<NavigatorState>> _navigators = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];
  int _destination = 0;

  NavigatorState? get _navigator => _navigators[_destination].currentState;

  /// Every destination is built up front so its stack survives a tab switch,
  /// which also means its feed is loaded long before it is looked at. Opening
  /// a tab therefore has to ask for fresh data rather than trusting what was
  /// fetched at launch.
  void _selectDestination(int index) {
    setState(() => _destination = index);

    final scope = MutoScope.of(context);
    unawaited(switch (index) {
      1 => scope.favorites.refresh(),
      2 => scope.mine.refresh(),
      _ => scope.browse.refresh(),
    });
  }

  Future<void> _openEditor() async {
    // pushed on the feature's navigator, not the tab's, so it covers the whole
    // surface the way a separate task should
    final saved = await Navigator.of(context).push<Listing>(
      MaterialPageRoute<Listing>(
        fullscreenDialog: true,
        builder: (_) => const ListingEditorScreen(),
      ),
    );
    if (saved == null || !mounted) return;
    // the feed was marked stale by the write; reload it so the listing the
    // student just published is actually there when they land back on it
    unawaited(MutoScope.of(context).browse.refresh());
  }

  void _openListing(Listing listing) {
    _navigator?.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ListingDetailScreen(listingId: listing.id, preloaded: listing),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = MutoLocalizations.of(context);
    final session = MutoScope.of(context).session;

    return Scaffold(
      body: Column(
        children: [
          if (widget.config.usesSampleData)
            SafeArea(
              bottom: false,
              child: SampleDataBanner(
                label: strings.sampleDataIndicator,
                onTap: () => _explainSampleData(context, strings),
              ),
            ),
          Expanded(
            // the banner already sits under the notch, so the destinations
            // below it must not inset for it a second time
            child: MediaQuery.removePadding(
              context: context,
              removeTop: widget.config.usesSampleData,
              child: IndexedStack(
                index: _destination,
                children: [
                  for (var i = 0; i < _navigators.length; i++)
                    Navigator(
                      key: _navigators[i],
                      onGenerateRoute: (settings) => MaterialPageRoute<void>(
                        settings: settings,
                        builder: (_) => switch (i) {
                          1 => FavoritesScreen(onOpenListing: _openListing),
                          2 => MyListingsScreen(onOpenListing: _openListing),
                          _ => BrowseScreen(onOpenListing: _openListing),
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: session.canPublish
          ? FloatingActionButton(
              onPressed: () => unawaited(_openEditor()),
              tooltip: strings.editorNewTitle,
              child: const AppIcon(AppIcons.add, color: AppColors.white),
            )
          : null,
      bottomNavigationBar: _BottomBar(
        current: _destination,
        onSelected: _selectDestination,
        labels: [
          strings.navBrowse,
          strings.navFavorites,
          strings.navMyListings,
        ],
        icons: const [AppIcons.home, AppIcons.heart, AppIcons.request],
      ),
    );
  }
}

void _explainSampleData(BuildContext context, MutoLocalizations strings) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.sampleDataIndicator),
      content: Text(strings.sampleDataExplanation),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionClose),
        ),
      ],
    ),
  );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.current,
    required this.onSelected,
    required this.labels,
    required this.icons,
  });

  final int current;
  final ValueChanged<int> onSelected;
  final List<String> labels;
  final List<AppIconData> icons;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      decoration: BoxDecoration(
        color: isLight ? AppColors.surface : AppColors.surfaceDark,
        border: Border(
          top: BorderSide(
            color: isLight ? AppColors.borderGrey : AppColors.borderDark,
          ),
        ),
      ),
      // the home-indicator inset belongs to each destination rather than to
      // the bar, so a thumb landing low still lands on something
      padding: const EdgeInsets.only(
        left: AppSpacing.df,
        right: AppSpacing.df,
        top: AppSpacing.xs,
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: _NavButton(
                icon: icons[i],
                label: labels[i],
                selected: i == current,
                bottomInset:
                    MediaQuery.paddingOf(context).bottom + AppSpacing.xs,
                onTap: () => onSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.bottomInset,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final bool selected;

  /// Sits inside the tap target, under the pill, so the strip above the home
  /// indicator is not dead space.
  final double bottomInset;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final accent = selected
        ? (isLight ? AppColors.primary : AppColors.primaryAccentDark)
        : AppColors.iconSecondary;

    return Semantics(
      label: label,
      selected: selected,
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppSpacing.borderRadiusMd,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // the pill widens under the icon as a destination is chosen,
              // rather than appearing at full size in one frame
              AnimatedContainer(
                duration: _duration,
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(
                  horizontal: selected ? AppSpacing.lg : AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? (isLight
                            ? AppColors.primaryLight
                            : AppColors.primaryLightDark)
                      : Colors.transparent,
                  borderRadius: AppSpacing.borderRadiusMd,
                ),
                child: AppIcon(icon, size: 22, color: accent),
              ),
              const SizedBox(height: AppSpacing.xs),
              AnimatedDefaultTextStyle(
                duration: _duration,
                curve: Curves.easeOutCubic,
                style: AppTextStyles.labelSmall.copyWith(
                  color: accent,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Long enough to read as movement, short enough not to be waited on.
const Duration _duration = Duration(milliseconds: 220);
