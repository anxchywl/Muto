import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:muto_ui/muto_ui.dart';

import '../../application/listing_editor_controller.dart';
import '../../application/muto_scope.dart';
import '../../domain/entities/currency.dart';
import '../../domain/entities/listing.dart';
import '../../domain/entities/listing_category.dart';
import '../../domain/entities/listing_condition.dart';
import '../../domain/entities/listing_kind.dart';
import '../../domain/entities/money.dart';
import '../../domain/failures.dart';
import '../../domain/validation/listing_rules.dart';
import '../../l10n/generated/muto_localizations.dart';
import '../formatting/listing_labels.dart';
import '../images/listing_image_provider.dart';
import '../listing/listing_detail_preview_screen.dart';
import 'editor_messages.dart';
import 'image_crop_screen.dart';
import 'image_picking.dart';

/// Opens the editor over whatever is on screen.
///
/// A sheet rather than a page: publishing is a short errand, and keeping the
/// feed visible behind it says so. It answers with the saved listing, or with
/// nothing when the student backed out.
Future<Listing?> showListingEditorSheet(
  BuildContext context, {
  Listing? editing,
}) {
  return showModalBottomSheet<Listing>(
    context: context,
    // deliberately the nearest navigator rather than the root one: the editor
    // reads the feature's scope, which lives below the host's navigator
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    builder: (_) => ListingEditorSheet(editing: editing),
  );
}

/// The form for creating a listing or changing one, walked one step at a time.
class ListingEditorSheet extends StatefulWidget {
  const ListingEditorSheet({super.key, this.editing});

  /// Null when publishing something new.
  final Listing? editing;

  /// Basics, details, photos, and a look at the result before it is published.
  static const int stepCount = 4;

  /// Never more than this much of the screen, so the sheet always reads as
  /// something laid over the feed rather than a page that replaced it.
  static const double maxHeightFraction = 0.8;

  @override
  State<ListingEditorSheet> createState() => _ListingEditorSheetState();
}

class _ListingEditorSheetState extends State<ListingEditorSheet> {
  ListingEditorController? _editor;
  final ImagePicker _picker = ImagePicker();

  // owned here rather than rebuilt from the draft, so the caret does not jump
  // back to the start on every keystroke
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _wantedItems = TextEditingController();

  int _step = 0;

  /// Which way the last move went, so the step that arrives slides in from the
  /// side it came from.
  bool _movingForward = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_editor != null) return;

    final scope = MutoScope.of(context);
    final identity = scope.session.identity;
    if (identity == null) return;

    final editing = widget.editing;
    final initial = editing == null ? _blankDraft() : _draftFrom(editing);
    _title.text = initial.title;
    _description.text = initial.description;
    _price.text = initial.price == null ? '' : '${initial.price!.minorUnits}';
    _wantedItems.text = initial.wantedItems ?? '';

    _editor = ListingEditorController(
      listings: scope.dependencies.listings,
      images: scope.dependencies.images,
      drafts: scope.dependencies.drafts,
      cache: scope.cache,
      generation: scope.generation,
      onUnauthorized: scope.session.reportExpired,
      userId: identity.userId,
      initial: initial,
      editingListingId: editing?.id,
      expectedVersion: editing?.version,
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _wantedItems.dispose();
    _editor?.dispose();
    super.dispose();
  }

  static ListingDraft _blankDraft() => const ListingDraft(
    kind: ListingKind.sale,
    title: '',
    description: '',
    condition: ListingCondition.good,
    category: ListingCategory.other,
    images: [],
  );

  static ListingDraft _draftFrom(Listing listing) => ListingDraft(
    kind: listing.kind,
    title: listing.title,
    description: listing.description,
    condition: listing.condition,
    category: listing.category,
    images: listing.images,
    price: listing.price,
    wantedItems: listing.wantedItems,
  );

  /// Whether the step the student is on has everything it asks for. The
  /// domain decides what is wrong; this only says which step owns it.
  bool _isStepValid(int step) {
    final editor = _editor;
    if (editor == null) return false;
    final issues = editor.validation;

    return switch (step) {
      0 =>
        issues.firstFor(ListingField.title) == null &&
            issues.firstFor(ListingField.description) == null,
      1 =>
        issues.firstFor(ListingField.price) == null &&
            issues.firstFor(ListingField.wantedItems) == null,
      2 => issues.firstFor(ListingField.images) == null,
      _ => true,
    };
  }

  void _onPrimary(MutoLocalizations strings) {
    final editor = _editor;
    if (editor == null) return;

    // the button stays live rather than going dead, so refusing to move on can
    // say why instead of leaving the student guessing
    if (!_isStepValid(_step)) {
      editor.revealIssues();
      return;
    }

    if (_step == ListingEditorSheet.stepCount - 1) {
      unawaited(_submit(strings));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _movingForward = true;
      _step++;
    });
  }

  void _back() {
    if (_step == 0) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _movingForward = false;
      _step--;
    });
  }

  Future<void> _submit(MutoLocalizations strings) async {
    final editor = _editor;
    if (editor == null) return;
    final saved = await editor.submit();
    if (saved == null || !mounted) return;

    AppToast.showSuccess(
      context,
      editor.isEditing ? strings.listingSaved : strings.listingPublished,
    );
    Navigator.of(context).pop(saved);
  }

  Future<void> _confirmDiscard(MutoLocalizations strings) async {
    final editor = _editor;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.discardDraftTitle),
        content: Text(strings.discardDraftMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.actionKeepEditing),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.actionDiscard),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    await editor?.discard();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final strings = MutoLocalizations.of(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final editor = _editor;

    return AnimatedPadding(
      // the sheet rides the keyboard rather than being covered by it
      duration: _duration,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height *
              ListingEditorSheet.maxHeightFraction,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: isLight ? AppColors.surface : AppColors.surfaceDark,
            borderRadius: AppSpacing.borderRadiusTopSheet,
          ),
          child: SafeArea(
            top: false,
            // shrinks to what the step needs, and only grows to the cap when
            // the step has more than that to show
            child: editor == null
                ? const Padding(
                    padding: AppSpacing.screenPadding,
                    child: Center(child: AppLoader()),
                  )
                : ListenableBuilder(
                    listenable: editor,
                    builder: (context, _) => _Body(
                      editor: editor,
                      picker: _picker,
                      step: _step,
                      movingForward: _movingForward,
                      title: _title,
                      description: _description,
                      price: _price,
                      wantedItems: _wantedItems,
                      onPrimary: () => _onPrimary(strings),
                      onBack: _back,
                      onClose: () => unawaited(_confirmDiscard(strings)),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.editor,
    required this.picker,
    required this.step,
    required this.movingForward,
    required this.title,
    required this.description,
    required this.price,
    required this.wantedItems,
    required this.onPrimary,
    required this.onBack,
    required this.onClose,
  });

  final ListingEditorController editor;
  final ImagePicker picker;
  final int step;
  final bool movingForward;
  final TextEditingController title;
  final TextEditingController description;
  final TextEditingController price;
  final TextEditingController wantedItems;
  final VoidCallback onPrimary;
  final VoidCallback onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final strings = MutoLocalizations.of(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final labels = ListingLabels(
      strings,
      Localizations.localeOf(context).toString(),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Handle(isLight: isLight),
        _Header(
          text: editor.isEditing
              ? strings.editorEditTitle
              : strings.editorNewTitle,
          closeLabel: strings.actionDiscard,
          isLight: isLight,
          onClose: onClose,
        ),
        _Progress(step: step, strings: strings),
        Flexible(
          // the sheet grows and shrinks with the step rather than jumping to
          // the height of whichever one is longest
          child: AnimatedSize(
            duration: _duration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: _duration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(movingForward ? 0.06 : -0.06, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, ?current],
              ),
              child: SingleChildScrollView(
                key: ValueKey<int>(step),
                padding: AppSpacing.screenPadding,
                child: _Step(
                  editor: editor,
                  picker: picker,
                  step: step,
                  labels: labels,
                  title: title,
                  description: description,
                  price: price,
                  wantedItems: wantedItems,
                ),
              ),
            ),
          ),
        ),
        _BottomBar(
          step: step,
          isEditing: editor.isEditing,
          isSaving: editor.isSaving,
          onPrimary: onPrimary,
          onBack: onBack,
        ),
      ],
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({required this.isLight});

  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Center(
        child: Container(
          width: AppSpacing.xxl,
          height: AppSpacing.xs,
          decoration: BoxDecoration(
            color: isLight ? AppColors.lightGrey : AppColors.borderDark,
            borderRadius: AppSpacing.borderRadiusRound,
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.text,
    required this.closeLabel,
    required this.isLight,
    required this.onClose,
  });

  final String text;
  final String closeLabel;
  final bool isLight;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.df,
        AppSpacing.sm,
        AppSpacing.sm,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: SheetTitle(text: text, isLight: isLight),
          ),
          IconButton(
            icon: const AppIcon(AppIcons.close, size: 20),
            tooltip: closeLabel,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// How far along the form is: a bar that fills, and the names of the steps.
class _Progress extends StatelessWidget {
  const _Progress({required this.step, required this.strings});

  final int step;
  final MutoLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final labels = [
      strings.editorStepBasics,
      strings.editorStepDetails,
      strings.editorStepPhotos,
      strings.editorStepPreview,
    ];

    return Semantics(
      label: strings.editorStepSemantics(
        step + 1,
        ListingEditorSheet.stepCount,
      ),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.df,
          AppSpacing.sm,
          AppSpacing.df,
          AppSpacing.sm,
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: AppSpacing.borderRadiusRound,
              child: TweenAnimationBuilder<double>(
                duration: _duration,
                curve: Curves.easeOutCubic,
                tween: Tween<double>(
                  begin: 0,
                  end: (step + 1) / ListingEditorSheet.stepCount,
                ),
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: AppSpacing.xs,
                  backgroundColor: AppColors.fieldBackground,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < labels.length; i++)
                  AnimatedDefaultTextStyle(
                    duration: _duration,
                    curve: Curves.easeOutCubic,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: i == step
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontWeight: i == step ? FontWeight.w700 : FontWeight.w500,
                    ),
                    child: Text(labels[i]),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.step,
    required this.isEditing,
    required this.isSaving,
    required this.onPrimary,
    required this.onBack,
  });

  final int step;
  final bool isEditing;
  final bool isSaving;
  final VoidCallback onPrimary;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = MutoLocalizations.of(context);
    final isLast = step == ListingEditorSheet.stepCount - 1;

    return Padding(
      padding: AppSpacing.screenPadding,
      child: Row(
        children: [
          if (step > 0) ...[
            Expanded(
              child: AppSecondaryButton(
                text: strings.actionBack,
                size: AppButtonSize.medium,
                onPressed: isSaving ? null : onBack,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: AppPrimaryButton(
              text: isLast
                  ? (isEditing
                        ? strings.actionSaveChanges
                        : strings.actionPublish)
                  : strings.actionNext,
              size: AppButtonSize.medium,
              isLoading: isSaving,
              onPressed: isSaving ? null : onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.editor,
    required this.picker,
    required this.step,
    required this.labels,
    required this.title,
    required this.description,
    required this.price,
    required this.wantedItems,
  });

  final ListingEditorController editor;
  final ImagePicker picker;
  final int step;
  final ListingLabels labels;
  final TextEditingController title;
  final TextEditingController description;
  final TextEditingController price;
  final TextEditingController wantedItems;

  @override
  Widget build(BuildContext context) {
    final strings = labels.strings;
    final issues = editor.visibleIssues;
    final draft = editor.draft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (step) {
          0 => _Basics(
            editor: editor,
            labels: labels,
            issues: issues,
            title: title,
            description: description,
          ),
          1 => _Details(
            editor: editor,
            labels: labels,
            issues: issues,
            price: price,
            wantedItems: wantedItems,
          ),
          2 => _Photos(editor: editor, picker: picker),
          _ => _Preview(draft: draft, labels: labels),
        },
        if (editor.failure != null) ...[
          const SizedBox(height: AppSpacing.df),
          Text(
            _failureMessage(editor.failure!, strings),
            style: AppTextStyles.error,
          ),
        ],
      ],
    );
  }
}

class _Basics extends StatelessWidget {
  const _Basics({
    required this.editor,
    required this.labels,
    required this.issues,
    required this.title,
    required this.description,
  });

  final ListingEditorController editor;
  final ListingLabels labels;
  final ListingValidation issues;
  final TextEditingController title;
  final TextEditingController description;

  @override
  Widget build(BuildContext context) {
    final strings = labels.strings;
    final draft = editor.draft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Choices<ListingKind>(
          title: strings.filterKind,
          values: ListingKind.values,
          selected: draft.kind,
          labelOf: labels.kind,
          onSelected: (kind) => editor.edit(
            (current) => current.copyWith(
              kind: kind,
              clearPrice: !kind.requiresPrice,
              clearWantedItems: !kind.allowsWantedItems,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        AppTextField(
          label: strings.editorFieldTitle,
          controller: title,
          maxLength: 80,
          // single-line fields hand over to the next one; the description is
          // deliberately left alone, since a paragraph needs its return key
          textInputAction: TextInputAction.next,
          errorText: issueMessage(issues.firstFor(ListingField.title), strings),
          onChanged: (value) =>
              editor.edit((current) => current.copyWith(title: value)),
        ),
        const SizedBox(height: AppSpacing.df),

        AppTextField(
          label: strings.editorFieldDescription,
          controller: description,
          maxLines: 4,
          errorText: issueMessage(
            issues.firstFor(ListingField.description),
            strings,
          ),
          onChanged: (value) =>
              editor.edit((current) => current.copyWith(description: value)),
        ),
      ],
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({
    required this.editor,
    required this.labels,
    required this.issues,
    required this.price,
    required this.wantedItems,
  });

  final ListingEditorController editor;
  final ListingLabels labels;
  final ListingValidation issues;
  final TextEditingController price;
  final TextEditingController wantedItems;

  @override
  Widget build(BuildContext context) {
    final strings = labels.strings;
    final draft = editor.draft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (draft.kind.requiresPrice) ...[
          _PriceField(editor: editor, issues: issues, field: price),
          const SizedBox(height: AppSpacing.df),
        ],

        if (draft.kind.allowsWantedItems) ...[
          AppTextField(
            label: strings.editorFieldLookingFor,
            controller: wantedItems,
            maxLength: 200,
            textInputAction: TextInputAction.done,
            errorText: issueMessage(
              issues.firstFor(ListingField.wantedItems),
              strings,
            ),
            onChanged: (value) =>
                editor.edit((current) => current.copyWith(wantedItems: value)),
          ),
          const SizedBox(height: AppSpacing.df),
        ],

        _Choices<ListingCondition>(
          title: strings.filterCondition,
          values: ListingCondition.values,
          selected: draft.condition,
          labelOf: labels.condition,
          onSelected: (value) =>
              editor.edit((current) => current.copyWith(condition: value)),
        ),
        const SizedBox(height: AppSpacing.lg),

        _Choices<ListingCategory>(
          title: strings.filterCategory,
          values: ListingCategory.values,
          selected: draft.category,
          labelOf: labels.category,
          onSelected: (value) =>
              editor.edit((current) => current.copyWith(category: value)),
        ),
      ],
    );
  }
}

/// The listing as the rest of the marketplace will meet it.
///
/// The same card the feed uses, so what is promised here is what appears there.
class _Preview extends StatelessWidget {
  const _Preview({required this.draft, required this.labels});

  final ListingDraft draft;
  final ListingLabels labels;

  @override
  Widget build(BuildContext context) {
    final scope = MutoScope.of(context);
    final strings = labels.strings;
    final title = draft.title.trim();
    final priceText = labels.priceOf(draft.price, draft.kind);
    final sellerName = scope.session.identity?.displayName ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.editorPreviewHint,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          strings.editorPreviewFeedLabel,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // the same card the feed itself renders, so this is not an
        // approximation of how the listing will look — it is how it will look
        ListingCard(
          title: title,
          priceText: priceText,
          metaLabel: labels.condition(draft.condition),
          semanticLabel: strings.listingSemantics(title, priceText),
          imageSemanticLabel: strings.listingImageSemantics(title),
          image: resolveListingImage(
            scope.dependencies.imageLocator,
            draft.images.isEmpty ? null : draft.images.first,
          ),
          onTap: () => unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ListingDetailPreviewScreen(
                  draft: draft,
                  labels: labels,
                  sellerDisplayName: sellerName,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppSecondaryButton(
          text: strings.editorPreviewOpenFullPage,
          size: AppButtonSize.medium,
          onPressed: () => unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ListingDetailPreviewScreen(
                  draft: draft,
                  labels: labels,
                  sellerDisplayName: sellerName,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _failureMessage(MutoFailure failure, MutoLocalizations strings) {
  return switch (failure) {
    ConflictFailure() => strings.editorConflictMessage,
    NetworkFailure() => strings.errorOffline,
    ForbiddenFailure() => strings.errorGeneric,
    _ => strings.errorGeneric,
  };
}

class _PriceField extends StatelessWidget {
  const _PriceField({
    required this.editor,
    required this.issues,
    required this.field,
  });

  final ListingEditorController editor;
  final ListingValidation issues;
  final TextEditingController field;

  @override
  Widget build(BuildContext context) {
    final strings = MutoLocalizations.of(context);
    final price = editor.draft.price;
    final currency = price?.currency ?? Currency.kzt;
    final errorText = issueMessage(
      issues.firstFor(ListingField.price),
      strings,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: AppTextField(
                label: strings.editorFieldPrice,
                controller: field,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) {
                  final amount = int.tryParse(value);
                  editor.edit(
                    (current) => amount == null
                        ? current.copyWith(clearPrice: true)
                        : current.copyWith(
                            price: Money(
                              minorUnits: amount,
                              currency: currency,
                            ),
                          ),
                  );
                },
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            _CurrencyToggle(
              selected: currency,
              onSelected: (next) => editor.edit(
                (current) => current.copyWith(
                  price: Money(
                    minorUnits: current.price?.minorUnits ?? 0,
                    currency: next,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(errorText, style: AppTextStyles.error),
        ],
      ],
    );
  }
}

class _CurrencyToggle extends StatelessWidget {
  const _CurrencyToggle({required this.selected, required this.onSelected});

  final Currency selected;
  final ValueChanged<Currency> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final currency in Currency.values)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            child: _Choice(
              label: currency.code,
              selected: currency == selected,
              onTap: () => onSelected(currency),
            ),
          ),
      ],
    );
  }
}

class _Photos extends StatelessWidget {
  const _Photos({required this.editor, required this.picker});

  final ListingEditorController editor;
  final ImagePicker picker;

  Future<void> _add(BuildContext context) async {
    final picked = await pickListingImage(picker);
    if (picked == null) return;
    if (!context.mounted) return;
    // the picker hands back whatever framing the photo happened to have; the
    // crop step is what makes every listing thumbnail actually square
    final cropped = await showImageCropScreen(context, bytes: picked.bytes);
    if (cropped == null) return;
    await editor.addImage(cropped);
  }

  @override
  Widget build(BuildContext context) {
    final scope = MutoScope.of(context);
    final strings = MutoLocalizations.of(context);
    final images = editor.draft.images;
    final issue = editor.imageIssue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              strings.editorFieldPhotos,
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              strings.editorPhotoCount(images.length, ListingRules.maxImages),
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final image in images)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: _Thumbnail(
                    provider: resolveListingImage(
                      scope.dependencies.imageLocator,
                      image,
                    ),
                    removeLabel: strings.actionRemovePhoto,
                    onRemove: () => editor.removeImage(image),
                  ),
                ),
              if (editor.canAddImage)
                Semantics(
                  label: strings.actionAddPhoto,
                  button: true,
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: editor.isStagingImage
                        ? null
                        : () => unawaited(_add(context)),
                    borderRadius: AppSpacing.borderRadiusMd,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: AppColors.fieldBackground,
                        borderRadius: AppSpacing.borderRadiusMd,
                      ),
                      child: Center(
                        child: editor.isStagingImage
                            ? const AppLoader()
                            : const AppIcon(
                                AppIcons.add,
                                color: AppColors.iconSecondary,
                              ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (issue != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(imageIssueMessage(issue, strings), style: AppTextStyles.error),
        ],
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.provider,
    required this.removeLabel,
    required this.onRemove,
  });

  final ImageProvider? provider;
  final String removeLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: AppSpacing.borderRadiusMd,
          child: SizedBox(
            width: 96,
            height: 96,
            child: ListingImage(provider: provider),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: Semantics(
            label: removeLabel,
            button: true,
            excludeSemantics: true,
            child: IconButton(
              icon: const AppIcon(AppIcons.close, size: 16),
              tooltip: removeLabel,
              onPressed: onRemove,
            ),
          ),
        ),
      ],
    );
  }
}

class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.title,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.labelMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final value in values)
              _Choice(
                label: labelOf(value),
                selected: value == selected,
                onTap: () => onSelected(value),
              ),
          ],
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final background = selected
        ? (isLight ? AppColors.primaryLight : AppColors.primaryLightDark)
        : (isLight ? AppColors.serviceBackground : AppColors.borderDark);
    final foreground = selected
        ? (isLight ? AppColors.primary : AppColors.primaryAccentDark)
        : AppColors.textSecondary;

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppSpacing.borderRadiusSm,
        child: AnimatedContainer(
          duration: _duration,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppSpacing.borderRadiusSm,
          ),
          child: Text(
            label,
            style: AppTextStyles.chip.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}

/// Long enough to read as movement, short enough not to be waited on.
const Duration _duration = Duration(milliseconds: 240);
