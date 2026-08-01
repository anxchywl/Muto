import '../entities/listing.dart';
import 'text_rules.dart';

/// A field a validation issue can attach to, so a form can mark the right
/// input rather than showing one message for the whole screen.
enum ListingField { title, description, price, wantedItems, images }

enum ListingIssue {
  titleTooShort(ListingField.title),
  titleTooLong(ListingField.title),
  descriptionTooLong(ListingField.description),
  priceMissing(ListingField.price),
  priceNotAllowed(ListingField.price),
  priceOutOfRange(ListingField.price),
  wantedItemsNotAllowed(ListingField.wantedItems),
  wantedItemsTooLong(ListingField.wantedItems),
  tooManyImages(ListingField.images);

  const ListingIssue(this.field);

  final ListingField field;
}

final class ListingValidation {
  const ListingValidation(this.issues);

  const ListingValidation.valid() : issues = const <ListingIssue>{};

  final Set<ListingIssue> issues;

  bool get isValid => issues.isEmpty;

  ListingIssue? firstFor(ListingField field) {
    for (final issue in issues) {
      if (issue.field == field) return issue;
    }
    return null;
  }
}

abstract final class ListingRules {
  static const int maxImages = 6;

  /// Normalises the text fields and drops anything the listing's kind does not
  /// allow, so an invalid combination cannot be constructed by accident.
  static ListingDraft normalize(ListingDraft draft) {
    return ListingDraft(
      kind: draft.kind,
      title: TextRules.normalizeLine(draft.title),
      description: TextRules.normalizeBlock(draft.description),
      condition: draft.condition,
      category: draft.category,
      images: draft.images,
      price: draft.kind.requiresPrice ? draft.price : null,
      wantedItems: draft.kind.allowsWantedItems
          ? _normalizeWanted(draft.wantedItems)
          : null,
    );
  }

  static String? _normalizeWanted(String? wantedItems) {
    if (wantedItems == null) return null;
    final normalized = TextRules.normalizeLine(wantedItems);
    return normalized.isEmpty ? null : normalized;
  }

  static ListingValidation validate(ListingDraft draft) {
    final issues = <ListingIssue>{};

    final title = TextRules.normalizeLine(draft.title);
    if (title.length < TextRules.titleMin) {
      issues.add(ListingIssue.titleTooShort);
    }
    if (title.length > TextRules.titleMax) {
      issues.add(ListingIssue.titleTooLong);
    }

    if (TextRules.normalizeBlock(draft.description).length >
        TextRules.descriptionMax) {
      issues.add(ListingIssue.descriptionTooLong);
    }

    final price = draft.price;
    if (draft.kind.requiresPrice) {
      if (price == null) {
        issues.add(ListingIssue.priceMissing);
      } else if (!price.isWithinBounds || price.isZero) {
        issues.add(ListingIssue.priceOutOfRange);
      }
    } else if (price != null) {
      issues.add(ListingIssue.priceNotAllowed);
    }

    final wantedItems = draft.wantedItems;
    if (wantedItems != null && wantedItems.isNotEmpty) {
      if (!draft.kind.allowsWantedItems) {
        issues.add(ListingIssue.wantedItemsNotAllowed);
      } else if (TextRules.normalizeLine(wantedItems).length >
          TextRules.wantedItemsMax) {
        issues.add(ListingIssue.wantedItemsTooLong);
      }
    }

    if (draft.images.length > maxImages) issues.add(ListingIssue.tooManyImages);

    return ListingValidation(issues);
  }
}
