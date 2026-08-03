import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../config/muto_config.dart';
import '../../domain/entities/listing.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../browse/browse_screen.dart';

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
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  int _destination = 0;

  void _openListing(Listing listing) {
    // detail arrives in the next step; the route is already the one place a
    // listing is opened from
  }

  @override
  Widget build(BuildContext context) {
    final strings = MutoLocalizations.of(context);

    return Scaffold(
      body: Column(
        children: [
          if (widget.config.usesSampleData)
            SampleDataBanner(
              label: strings.sampleDataIndicator,
              onTap: () => _explainSampleData(context, strings),
            ),
          Expanded(
            child: Navigator(
              key: _navigator,
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => BrowseScreen(onOpenListing: _openListing),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        current: _destination,
        onSelected: (index) => setState(() => _destination = index),
        labels: [
          strings.navBrowse,
          strings.navFavorites,
          strings.navMyListings,
        ],
        icons: const [AppIcons.search, AppIcons.heart, AppIcons.request],
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
      padding: EdgeInsets.only(
        left: AppSpacing.df,
        right: AppSpacing.df,
        top: AppSpacing.xs,
        bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.xs,
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
    final accent = selected ? AppColors.primary : AppColors.iconSecondary;

    return Semantics(
      label: label,
      selected: selected,
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppSpacing.borderRadiusMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 22, color: accent),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelSmall.copyWith(
                  color: accent,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
