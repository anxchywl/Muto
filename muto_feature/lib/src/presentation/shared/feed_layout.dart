import 'package:app_ui/app_ui.dart';

/// How a feed arranges its listings.
///
/// A shopper scanning for one known thing wants rows — a title has room to be
/// read in full, and a screen holds fewer of them. A shopper browsing wants
/// tiles, where the photo is what carries and twice as many fit. Neither is
/// the right default for both, so it is the reader's to choose.
enum FeedLayout {
  rows,
  grid;

  FeedLayout get other => this == rows ? grid : rows;

  /// The icon for [other], because a toggle that shows the state it is already
  /// in says nothing a reader cannot already see by looking at the feed.
  AppIconData get switchIcon =>
      other == grid ? AppIcons.layoutGrid : AppIcons.layoutRows;
}
