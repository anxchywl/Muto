import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../../application/muto_scope.dart';
import '../../domain/entities/listing.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../browse/browse_screen.dart';
import '../editor/listing_editor_sheet.dart';
import '../favorites/favorites_screen.dart';
import '../listing/listing_detail_screen.dart';
import '../my_listings/my_listings_screen.dart';
import '../operations/report_operations_screen.dart';

/// The feature's own navigation surface.
///
/// It keeps its stack inside a nested navigator so a host can push its own
/// routes above the feature without the two fighting over one stack.
class MutoShell extends StatefulWidget {
  const MutoShell({
    super.key,
    this.initialDestination = 0,
    this.onDevelopmentRoleSwitch,
  });

  final int initialDestination;
  final Future<void> Function()? onDevelopmentRoleSwitch;

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
  late int _destination = widget.initialDestination;
  int _browseTapCount = 0;
  bool _switchingDevelopmentRole = false;

  // the FAB belongs to the root of "my listings", not to whatever screen got
  // pushed on top of it (a listing's own detail page, say), so the stack
  // depth of the active tab decides whether it is shown at all
  final List<int> _stackDepths = [1, 1, 1];

  // built once rather than inline in `build`, since an observer recreated on
  // every rebuild would forget the depth it was already tracking
  late final List<_StackDepthObserver> _stackObservers = [
    for (var i = 0; i < _navigators.length; i++)
      _StackDepthObserver(
        onChanged: (depth) {
          if (_stackDepths[i] == depth) return;
          setState(() => _stackDepths[i] = depth);
        },
      ),
  ];

  NavigatorState? get _navigator => _navigators[_destination].currentState;

  /// Every destination is built up front so its stack and cached feed survive
  /// a tab switch. Explicit refresh gestures and writes are responsible for
  /// asking the source for fresh data.
  void _selectDestination(int index) {
    setState(() => _destination = index);

    // a previously empty favorites feed may become non-empty after saving on
    // another tab, so reload that edge case without refreshing every switch
    if (index == 1) {
      final favorites = MutoScope.of(context).favorites;
      if (favorites.hasLoaded && favorites.items.isEmpty) {
        unawaited(favorites.refresh());
      }
    }
  }

  Future<void> _handleDestinationTap(int index) async {
    const browseIndex = 0;
    if (index != browseIndex) {
      _browseTapCount = 0;
      _selectDestination(index);
      return;
    }
    final switchRole = widget.onDevelopmentRoleSwitch;
    if (switchRole == null) {
      _selectDestination(index);
      return;
    }
    if (_switchingDevelopmentRole) return;
    _browseTapCount += 1;
    if (_browseTapCount < 5) {
      if (_destination != index) _selectDestination(index);
      return;
    }
    _browseTapCount = 0;
    _switchingDevelopmentRole = true;
    try {
      await switchRole();
    } finally {
      _switchingDevelopmentRole = false;
    }
  }

  Future<void> _openEditor() async {
    final saved = await showListingEditorSheet(context);
    if (saved == null || !mounted) return;
    // the feeds were marked stale by the write; reload them so the listing the
    // student just published is actually there when they look
    final scope = MutoScope.of(context);
    unawaited(scope.mine.refresh());
    unawaited(scope.browse.refresh());
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
    final isAdmin = session.identity?.isAdmin ?? false;

    // publishing belongs to the root of the student's own listings, so the
    // button lives there and nowhere else — not on a listing pushed on top
    final showsCompose =
        session.canPublish && _destination == 2 && _stackDepths[2] <= 1;

    // the bar belongs to the three destinations themselves, not to whatever
    // got pushed on top of one (a listing's detail, a seller's profile) —
    // those read as their own full screens, not a tab with a bar bolted on
    final showsBottomBar = _stackDepths[_destination] <= 1;

    return Scaffold(
      body: IndexedStack(
        index: _destination,
        children: [
          for (var i = 0; i < (isAdmin ? 2 : _navigators.length); i++)
            Navigator(
              key: _navigators[i],
              observers: [_stackObservers[i]],
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => switch (i) {
                  1 when isAdmin => const ReportOperationsScreen(),
                  1 => FavoritesScreen(onOpenListing: _openListing),
                  2 => MyListingsScreen(onOpenListing: _openListing),
                  _ => BrowseScreen(onOpenListing: _openListing),
                },
              ),
            ),
        ],
      ),
      // it grows into place on the tab that owns it and folds away on the
      // others, rather than blinking in and out between tabs
      floatingActionButton: session.canPublish
          ? AnimatedScale(
              duration: _duration,
              curve: showsCompose ? Curves.easeOutBack : Curves.easeInCubic,
              scale: showsCompose ? 1 : 0,
              child: AnimatedOpacity(
                duration: _duration,
                curve: Curves.easeOutCubic,
                opacity: showsCompose ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !showsCompose,
                  child: FloatingActionButton(
                    onPressed: () => unawaited(_openEditor()),
                    tooltip: strings.editorNewTitle,
                    child: const AppIcon(AppIcons.add, color: AppColors.white),
                  ),
                ),
              ),
            )
          : null,
      bottomNavigationBar: showsBottomBar
          ? _BottomBar(
              current: _destination,
              onSelected: (index) => unawaited(_handleDestinationTap(index)),
              labels: isAdmin
                  ? [strings.navBrowse, strings.navReports]
                  : [
                      strings.navBrowse,
                      strings.navFavorites,
                      strings.navMyListings,
                    ],
              icons: isAdmin
                  ? const [AppIcons.home, AppIcons.request]
                  : const [AppIcons.home, AppIcons.heart, AppIcons.request],
            )
          : null,
    );
  }
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
      padding: EdgeInsets.fromLTRB(
        AppSpacing.df,
        AppSpacing.xs,
        AppSpacing.df,
        MediaQuery.paddingOf(context).bottom + AppSpacing.xs,
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: _NavButton(
                icon: icons[i],
                label: labels[i],
                selected: i == current,
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
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final bool selected;

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
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reports how many routes deep a tab's own navigator stack is, so the shell
/// can tell a tab's root screen apart from something pushed on top of it.
class _StackDepthObserver extends NavigatorObserver {
  _StackDepthObserver({required this.onChanged});

  final ValueChanged<int> onChanged;
  // the initial route also fires didPush once the Navigator mounts, so start
  // at zero and let that first callback bring it to one
  int _depth = 0;

  void _report() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(_depth));

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _depth++;
    _report();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _depth = _depth > 1 ? _depth - 1 : 1;
    _report();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _depth = _depth > 1 ? _depth - 1 : 1;
    _report();
  }
}

/// Long enough to read as movement, short enough not to be waited on.
const Duration _duration = Duration(milliseconds: 220);
