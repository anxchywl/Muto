import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../domain/entities/currency.dart';
import '../../domain/entities/listing.dart';
import '../../domain/entities/listing_category.dart';
import '../../domain/entities/listing_condition.dart';
import '../../domain/entities/listing_kind.dart';
import '../../domain/entities/listing_status.dart';
import '../../domain/entities/money.dart';
import '../../domain/repositories/listing_repository.dart';
import '../../l10n/generated/muto_localizations.dart';

/// Turns domain values into the words a reader sees.
///
/// This is the only place meaning becomes text. Widgets receive the result and
/// never decide wording themselves, which is what keeps three languages from
/// leaking into layout code.
final class ListingLabels {
  const ListingLabels(this.strings, this.localeName);

  final MutoLocalizations strings;
  final String localeName;

  String money(Money amount) {
    final digits = amount.currency.minorUnitDigits;
    final value = amount.minorUnits / math.pow(10, digits);
    return NumberFormat.currency(
      locale: localeName,
      symbol: _symbol(amount.currency),
      decimalDigits: digits,
    ).format(value);
  }

  static String _symbol(Currency currency) {
    switch (currency) {
      case Currency.kzt:
        return '₸';
      case Currency.usd:
        return r'$';
    }
  }

  /// What sits where a price would be. A giveaway and a swap have no amount,
  /// but the space still has to say something useful.
  String price(Listing listing) {
    final amount = listing.price;
    if (amount != null) return money(amount);
    switch (listing.kind) {
      case ListingKind.giveaway:
        return strings.priceFree;
      case ListingKind.exchange:
        return strings.priceSwap;
      case ListingKind.sale:
        return strings.priceFree;
    }
  }

  String kind(ListingKind value) {
    switch (value) {
      case ListingKind.sale:
        return strings.kindSale;
      case ListingKind.exchange:
        return strings.kindExchange;
      case ListingKind.giveaway:
        return strings.kindGiveaway;
    }
  }

  String condition(ListingCondition value) {
    switch (value) {
      case ListingCondition.brandNew:
        return strings.conditionNew;
      case ListingCondition.likeNew:
        return strings.conditionLikeNew;
      case ListingCondition.good:
        return strings.conditionGood;
      case ListingCondition.worn:
        return strings.conditionWorn;
    }
  }

  String category(ListingCategory value) {
    switch (value) {
      case ListingCategory.textbooks:
        return strings.categoryTextbooks;
      case ListingCategory.electronics:
        return strings.categoryElectronics;
      case ListingCategory.furniture:
        return strings.categoryFurniture;
      case ListingCategory.clothing:
        return strings.categoryClothing;
      case ListingCategory.sports:
        return strings.categorySports;
      case ListingCategory.dorm:
        return strings.categoryDorm;
      case ListingCategory.tickets:
        return strings.categoryTickets;
      case ListingCategory.other:
        return strings.categoryOther;
    }
  }

  String sort(ListingSort value) {
    switch (value) {
      case ListingSort.newest:
        return strings.sortNewest;
      case ListingSort.priceAscending:
        return strings.sortPriceAscending;
      case ListingSort.priceDescending:
        return strings.sortPriceDescending;
    }
  }

  /// Null when the listing is plainly available, so a card shows a status only
  /// when there is something to say.
  String? status(ListingStatus value) {
    switch (value) {
      case ListingStatus.reserved:
        return strings.statusReserved;
      case ListingStatus.sold:
        return strings.statusSold;
      case ListingStatus.hidden:
        return strings.statusHidden;
      case ListingStatus.active:
      case ListingStatus.removed:
      case ListingStatus.unknown:
        return null;
    }
  }

  /// One announcement per row, so a screen reader does not read a card as four
  /// unrelated fragments.
  String listingSemantics(Listing listing) {
    final statusLabel = status(listing.status);
    if (statusLabel == null) {
      return strings.listingSemantics(listing.title, price(listing));
    }
    return strings.listingSemanticsWithStatus(
      listing.title,
      price(listing),
      statusLabel,
    );
  }

  String savedAt(DateTime moment) =>
      DateFormat.jm(localeName).format(moment.toLocal());
}
