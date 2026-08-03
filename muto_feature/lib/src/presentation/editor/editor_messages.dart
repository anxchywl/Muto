import '../../domain/validation/image_rules.dart';
import '../../domain/validation/listing_rules.dart';
import '../../l10n/generated/muto_localizations.dart';

/// Turns a validation result into the sentence shown under the field it
/// belongs to.
///
/// Kept apart from the form so the wording is testable without pumping a
/// widget, and so no message is ever written inline in layout code.
String? issueMessage(ListingIssue? issue, MutoLocalizations strings) {
  if (issue == null) return null;
  return switch (issue) {
    ListingIssue.titleTooShort => strings.issueTitleTooShort,
    ListingIssue.titleTooLong => strings.issueTitleTooLong,
    ListingIssue.descriptionTooLong => strings.issueDescriptionTooLong,
    ListingIssue.priceMissing => strings.issuePriceMissing,
    ListingIssue.priceNotAllowed => strings.issuePriceMissing,
    ListingIssue.priceOutOfRange => strings.issuePriceOutOfRange,
    ListingIssue.wantedItemsNotAllowed => strings.issueWantedItemsTooLong,
    ListingIssue.wantedItemsTooLong => strings.issueWantedItemsTooLong,
    ListingIssue.tooManyImages => strings.issueTooManyImages,
  };
}

String imageIssueMessage(ImageIssue issue, MutoLocalizations strings) {
  return switch (issue) {
    ImageIssue.unsupportedType => strings.imageIssueUnsupported,
    ImageIssue.tooLarge => strings.imageIssueTooLarge,
    ImageIssue.tooSmall => strings.imageIssueTooSmall,
    ImageIssue.tooManyPixels => strings.imageIssueTooManyPixels,
  };
}
