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
import 'editor_messages.dart';
import 'image_picking.dart';

/// The form for creating a listing or changing one.
class ListingEditorScreen extends StatefulWidget {
  const ListingEditorScreen({super.key, this.editing});

  /// Null when publishing something new.
  final Listing? editing;

  @override
  State<ListingEditorScreen> createState() => _ListingEditorScreenState();
}

class _ListingEditorScreenState extends State<ListingEditorScreen> {
  ListingEditorController? _editor;
  final ImagePicker _picker = ImagePicker();

  // owned here rather than rebuilt from the draft, so the caret does not jump
  // back to the start on every keystroke
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _wantedItems = TextEditingController();

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
    final editor = _editor;
    if (editor == null) {
      return const Scaffold(body: Center(child: AppLoader()));
    }

    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(
            editor.isEditing ? strings.editorEditTitle : strings.editorNewTitle,
          ),
          leading: IconButton(
            icon: const AppIcon(AppIcons.close),
            tooltip: strings.actionDiscard,
            onPressed: () => unawaited(_confirmDiscard(strings)),
          ),
        ),
        body: _Form(
          editor: editor,
          picker: _picker,
          title: _title,
          description: _description,
          price: _price,
          wantedItems: _wantedItems,
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: AppSpacing.screenPadding,
            child: AppPrimaryButton(
              text: editor.isEditing
                  ? strings.actionSaveChanges
                  : strings.actionPublish,
              size: AppButtonSize.large,
              isLoading: editor.isSaving,
              onPressed: editor.isSaving
                  ? null
                  : () => unawaited(_submit(strings)),
            ),
          ),
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({
    required this.editor,
    required this.picker,
    required this.title,
    required this.description,
    required this.price,
    required this.wantedItems,
  });

  final ListingEditorController editor;
  final ImagePicker picker;
  final TextEditingController title;
  final TextEditingController description;
  final TextEditingController price;
  final TextEditingController wantedItems;

  @override
  Widget build(BuildContext context) {
    final strings = MutoLocalizations.of(context);
    final labels = ListingLabels(
      strings,
      Localizations.localeOf(context).toString(),
    );
    final issues = editor.visibleIssues;
    final draft = editor.draft;

    return ListView(
      padding: AppSpacing.screenPadding,
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
          maxLines: 5,
          errorText: issueMessage(
            issues.firstFor(ListingField.description),
            strings,
          ),
          onChanged: (value) =>
              editor.edit((current) => current.copyWith(description: value)),
        ),
        const SizedBox(height: AppSpacing.df),

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
        const SizedBox(height: AppSpacing.lg),

        _Photos(editor: editor, picker: picker),

        if (editor.failure != null) ...[
          const SizedBox(height: AppSpacing.df),
          Text(
            _failureMessage(editor.failure!, strings),
            style: AppTextStyles.error,
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                label: strings.editorFieldPrice,
                controller: field,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                errorText: issueMessage(
                  issues.firstFor(ListingField.price),
                  strings,
                ),
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
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Row(
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
      ),
    );
  }
}

class _Photos extends StatelessWidget {
  const _Photos({required this.editor, required this.picker});

  final ListingEditorController editor;
  final ImagePicker picker;

  Future<void> _add(BuildContext context) async {
    final staged = await pickListingImage(picker);
    if (staged == null) return;
    await editor.addImage(staged);
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
        child: Container(
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
