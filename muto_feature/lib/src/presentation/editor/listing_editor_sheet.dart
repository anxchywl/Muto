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
import '../shared/focus_mode.dart';
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

/// The typed-into fields of the editor, so focus mode can name the one in
/// hand and fold everything else.
enum _Field { title, description, price, wantedItems }

class _ListingEditorSheetState extends State<ListingEditorSheet> {
  ListingEditorController? _editor;
  final ImagePicker _picker = ImagePicker();

  // owned here rather than rebuilt from the draft, so the caret does not jump
  // back to the start on every keystroke
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _wantedItems = TextEditingController();

  /// Owns the fields' focus nodes, and says which one has the keyboard so the
  /// rest of the sheet can get out of its way.
  final SheetFocusMode _focus = SheetFocusMode();

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
    _focus.dispose();
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

    // the button is already dead when the step is short of something, so
    // reaching here at all means there is nothing left to refuse
    if (!_isStepValid(_step)) {
      editor.revealIssues();
      return;
    }

    if (_step == ListingEditorSheet.stepCount - 1) {
      unawaited(_submit(strings));
      return;
    }

    _focus.release();
    setState(() {
      _movingForward = true;
      _step++;
    });
  }

  void _back() {
    if (_step == 0) return;
    _focus.release();
    setState(() {
      _movingForward = false;
      _step--;
    });
  }

  /// Held only long enough for the submit button to show a tick.
  bool _saved = false;

  Future<void> _submit(MutoLocalizations strings) async {
    final editor = _editor;
    if (editor == null) return;
    final saved = await editor.submit();
    if (saved == null || !mounted) return;

    // the button that was pressed says it landed, and the sheet then closes
    // on its own — a toast would arrive over whatever is behind the sheet
    setState(() => _saved = true);
    await Future<void>.delayed(_confirmationHold);
    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final strings = MutoLocalizations.of(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final editor = _editor;

    return Padding(
      // the sheet rides the keyboard rather than being covered by it.
      //
      // deliberately not an AnimatedPadding: the platform already animates
      // this inset frame by frame as the keyboard rises, so animating toward
      // it again left the sheet chasing a moving target — it lagged behind
      // the keyboard on the way up and then snapped level once the keyboard
      // settled, which is the flick that showed up right as a field took
      // focus. tracking the inset directly is what keeps them locked together
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
                    // the sheet is rebuilt both by the draft changing and by
                    // the keyboard moving between fields, and the two arrive
                    // independently
                    listenable: Listenable.merge([editor, _focus]),
                    builder: (context, _) => _Body(
                      editor: editor,
                      picker: _picker,
                      focus: _focus,
                      step: _step,
                      movingForward: _movingForward,
                      title: _title,
                      description: _description,
                      price: _price,
                      wantedItems: _wantedItems,
                      saved: _saved,
                      isStepValid: _isStepValid(_step),
                      onPrimary: () => _onPrimary(strings),
                      onBack: _back,
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
    required this.focus,
    required this.step,
    required this.movingForward,
    required this.title,
    required this.description,
    required this.price,
    required this.wantedItems,
    required this.saved,
    required this.isStepValid,
    required this.onPrimary,
    required this.onBack,
  });

  final ListingEditorController editor;
  final ImagePicker picker;
  final SheetFocusMode focus;
  final int step;
  final bool movingForward;
  final TextEditingController title;
  final TextEditingController description;
  final TextEditingController price;
  final TextEditingController wantedItems;
  final bool saved;
  final bool isStepValid;
  final VoidCallback onPrimary;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = MutoLocalizations.of(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    focus.setKeyboardVisible(MediaQuery.viewInsetsOf(context).bottom > 0);
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
          isLight: isLight,
        ),
        // the stepper says where you are in a form you cannot see while the
        // keyboard is up, so it is the first thing to go
        FocusFold(
          hidden: focus.hidesChrome,
          child: _Progress(step: step, strings: strings),
        ),
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
                // the bottom inset goes with the chrome: with one field left
                // and Done right under it, a full gap on both sides of the
                // seam is twice as much air as that pairing wants
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.df,
                  AppSpacing.df,
                  AppSpacing.df,
                  focus.hidesChrome ? 0 : AppSpacing.df,
                ),
                child: _Step(
                  editor: editor,
                  picker: picker,
                  focus: focus,
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
        // Back/Next belong to a form you can see; while typing, the only
        // thing worth offering is the way back out to it
        FocusModeActions(
          isTyping: focus.isTyping,
          doneLabel: strings.actionDone,
          onDone: focus.release,
          // the same inset _BottomBar carries, so the bar is exactly as tall
          // either way and swapping the button moves nothing above it. the
          // tightening up against the field is done by the scroll view
          // dropping its own bottom padding, where it animates with the folds
          donePadding: AppSpacing.screenPadding,
          actions: _BottomBar(
            step: step,
            isEditing: editor.isEditing,
            isSaving: editor.isSaving,
            saved: saved,
            isStepValid: isStepValid,
            onPrimary: onPrimary,
            onBack: onBack,
          ),
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
  const _Header({required this.text, required this.isLight});

  final String text;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.df,
        AppSpacing.sm,
        AppSpacing.df,
        0,
      ),
      child: SheetTitle(text: text, isLight: isLight),
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
            // one segment per step rather than a single continuous bar: each
            // one grows from empty to full as it is reached, and shrinks back
            // to empty the moment the student steps behind it, so the bar
            // itself says which steps are actually done rather than just how
            // far along a fraction is
            Row(
              children: [
                for (var i = 0; i < labels.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  Expanded(child: _ProgressSegment(filled: i <= step)),
                ],
              ],
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

/// One step's share of the progress row.
///
/// A track the width of its step, filled from the left on a growing [width]
/// fraction — the same shape [TweenAnimationBuilder] is already trusted for
/// elsewhere in this sheet, which always continues smoothly from wherever it
/// is currently drawn rather than restarting at 0 on every rebuild.
class _ProgressSegment extends StatelessWidget {
  const _ProgressSegment({required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppSpacing.borderRadiusRound,
      child: Container(
        height: AppSpacing.xs,
        color: AppColors.fieldBackground,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          duration: _duration,
          curve: Curves.easeOutCubic,
          tween: Tween<double>(begin: 0, end: filled ? 1 : 0),
          builder: (context, value, _) => FractionallySizedBox(
            widthFactor: value,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(color: AppColors.primary),
            ),
          ),
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
    required this.saved,
    required this.isStepValid,
    required this.onPrimary,
    required this.onBack,
  });

  final int step;
  final bool isEditing;
  final bool isSaving;

  /// The write went through; the button says so before the sheet closes.
  final bool saved;

  /// Whether the current step has everything it asks for. The button greys
  /// out rather than staying live and refusing on tap, so the form never
  /// needs an inline error to say the same thing twice.
  final bool isStepValid;
  final VoidCallback onPrimary;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = MutoLocalizations.of(context);
    final isLast = step == ListingEditorSheet.stepCount - 1;
    final enabled = saved || (!isSaving && isStepValid);

    return Padding(
      padding: AppSpacing.screenPadding,
      child: Column(
        children: [
          Row(
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
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  opacity: enabled ? 1 : 0.45,
                  child: AppPrimaryButton(
                    text: saved
                        ? (isEditing
                              ? strings.listingSaved
                              : strings.listingPublished)
                        : isLast
                        ? (isEditing
                              ? strings.actionSaveChanges
                              : strings.actionPublish)
                        : strings.actionNext,
                    size: AppButtonSize.medium,
                    isLoading: isSaving && !saved,
                    icon: saved
                        ? const AppIcon(
                            AppIcons.check,
                            size: 18,
                            color: AppColors.white,
                          )
                        : null,
                    // a confirmed button keeps its full colour rather than greying
                    // out, so the tick reads as "done" and not as "unavailable"
                    onPressed: saved ? () {} : (enabled ? onPrimary : null),
                  ),
                ),
              ),
            ],
          ),
          if (isLast) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              strings.editorListingLifetimeNotice,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.editor,
    required this.picker,
    required this.focus,
    required this.step,
    required this.labels,
    required this.title,
    required this.description,
    required this.price,
    required this.wantedItems,
  });

  final ListingEditorController editor;
  final ImagePicker picker;
  final SheetFocusMode focus;
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
            focus: focus,
            title: title,
            description: description,
          ),
          1 => _Details(
            editor: editor,
            labels: labels,
            issues: issues,
            focus: focus,
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
    required this.focus,
    required this.title,
    required this.description,
  });

  final ListingEditorController editor;
  final ListingLabels labels;
  final ListingValidation issues;
  final SheetFocusMode focus;
  final TextEditingController title;
  final TextEditingController description;

  @override
  Widget build(BuildContext context) {
    final strings = labels.strings;
    final draft = editor.draft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FocusFold(
          animateSize: false,
          hidden: focus.hidesChrome,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Choices<ListingKind>(
                title: strings.filterKind,
                values: ListingKind.values,
                selected: draft.kind,
                labelOf: labels.kind,
                fullWidth: true,
                onSelected: (kind) => editor.edit(
                  (current) => current.copyWith(
                    kind: kind,
                    clearPrice: !kind.requiresPrice,
                    clearWantedItems: !kind.allowsWantedItems,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),

        FocusFold(
          animateSize: false,
          hidden: focus.hides(_Field.title),
          child: AppTextField(
            label: strings.editorFieldTitle,
            controller: title,
            focusNode: focus.nodeFor(_Field.title),
            maxLength: 80,
            // single-line fields hand over to the next one; the description is
            // deliberately left alone, since a paragraph needs its return key
            textInputAction: TextInputAction.next,
            errorText: issueMessage(
              issues.firstFor(ListingField.title),
              strings,
            ),
            onChanged: (value) =>
                editor.edit((current) => current.copyWith(title: value)),
          ),
        ),

        FocusGap(hidden: focus.hidesChrome, animateSize: false),

        FocusFold(
          animateSize: false,
          hidden: focus.hides(_Field.description),
          child: AppTextField(
            label: strings.editorFieldDescription,
            controller: description,
            focusNode: focus.nodeFor(_Field.description),
            maxLines: 4,
            errorText: issueMessage(
              issues.firstFor(ListingField.description),
              strings,
            ),
            onChanged: (value) =>
                editor.edit((current) => current.copyWith(description: value)),
          ),
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
    required this.focus,
    required this.price,
    required this.wantedItems,
  });

  final ListingEditorController editor;
  final ListingLabels labels;
  final ListingValidation issues;
  final SheetFocusMode focus;
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
          FocusFold(
            animateSize: false,
            hidden: focus.hides(_Field.price),
            child: _PriceField(editor: editor, focus: focus, field: price),
          ),
          FocusGap(hidden: focus.hidesChrome, animateSize: false),
        ],

        if (draft.kind.allowsWantedItems) ...[
          FocusFold(
            animateSize: false,
            hidden: focus.hides(_Field.wantedItems),
            child: AppTextField(
              label: strings.editorFieldLookingFor,
              controller: wantedItems,
              focusNode: focus.nodeFor(_Field.wantedItems),
              maxLength: 200,
              textInputAction: TextInputAction.done,
              errorText: issueMessage(
                issues.firstFor(ListingField.wantedItems),
                strings,
              ),
              onChanged: (value) => editor.edit(
                (current) => current.copyWith(wantedItems: value),
              ),
            ),
          ),
          FocusGap(hidden: focus.hidesChrome, animateSize: false),
        ],

        FocusFold(
          animateSize: false,
          hidden: focus.hidesChrome,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Choices<ListingCondition>(
                title: strings.filterCondition,
                values: ListingCondition.values,
                selected: draft.condition,
                labelOf: labels.condition,
                onSelected: (value) => editor.edit(
                  (current) => current.copyWith(condition: value),
                ),
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
          ),
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

    void openFullPreview() => unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ListingDetailPreviewScreen(
            draft: draft,
            labels: labels,
            sellerDisplayName: sellerName,
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings.editorPreviewFeedLabel,
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: strings.editorPreviewOpenFullPage,
              excludeSemantics: true,
              child: InkWell(
                borderRadius: AppSpacing.borderRadiusRound,
                onTap: openFullPreview,
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.xs),
                  child: AppIcon(
                    AppIcons.chevronRight,
                    size: 18,
                    color: AppColors.iconSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        // the same card the feed itself renders, so this is not an
        // approximation of how the listing will look — it is how it will look
        ListingCard(
          title: title,
          priceText: priceText,
          semanticLabel: strings.listingSemantics(title, priceText),
          imageSemanticLabel: strings.listingImageSemantics(title),
          image: resolveListingImage(
            scope.dependencies.imageLocator,
            draft.images.isEmpty ? null : draft.images.first,
          ),
          onTap: openFullPreview,
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
    required this.focus,
    required this.field,
  });

  final ListingEditorController editor;
  final SheetFocusMode focus;
  final TextEditingController field;

  @override
  Widget build(BuildContext context) {
    final strings = MutoLocalizations.of(context);
    final price = editor.draft.price;
    final currency = price?.currency ?? Currency.kzt;

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
                focusNode: focus.nodeFor(_Field.price),
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
            child: SelectableChip(
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
        // tucked into the corner itself rather than centred in an IconButton's
        // 48pt box, which pushed it a third of the way across the thumbnail.
        // its own dark disc keeps it legible over whatever the photo is
        Positioned(
          top: AppSpacing.xs,
          right: AppSpacing.xs,
          child: Semantics(
            label: removeLabel,
            button: true,
            excludeSemantics: true,
            child: Tooltip(
              message: removeLabel,
              child: Material(
                color: AppColors.black.withValues(alpha: 0.55),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(AppSpacing.xs),
                    child: AppIcon(
                      AppIcons.close,
                      size: 14,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
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
    this.fullWidth = false,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;
  final bool fullWidth;

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
        if (fullWidth)
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.borderGrey.withValues(alpha: 0.55),
              ),
              borderRadius: AppSpacing.borderRadiusMd,
            ),
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final selectedIndex = values.indexOf(selected);
                final segmentWidth =
                    (constraints.maxWidth -
                        AppSpacing.xs * (values.length - 1)) /
                    values.length;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 340),
                      curve: Curves.easeInOutCubic,
                      left: selectedIndex * (segmentWidth + AppSpacing.xs),
                      width: segmentWidth,
                      top: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).brightness == Brightness.light
                              ? AppColors.white
                              : AppColors.black,
                          borderRadius: AppSpacing.borderRadiusSm,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.black.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < values.length; i++) ...[
                          if (i > 0) const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: _EditorChoice(
                              label: labelOf(values[i]),
                              selected: values[i] == selected,
                              onTap: () => onSelected(values[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                );
              },
            ),
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final value in values)
                SelectableChip(
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

class _EditorChoice extends StatelessWidget {
  const _EditorChoice({
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
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppSpacing.borderRadiusSm,
        splashColor: AppColors.transparent,
        highlightColor: AppColors.transparent,
        hoverColor: AppColors.transparent,
        focusColor: AppColors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubic,
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.transparent,
            borderRadius: AppSpacing.borderRadiusSm,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
            style: AppTextStyles.chip.copyWith(
              color: selected
                  ? (isLight ? AppColors.primary : AppColors.primaryAccentDark)
                  : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }
}

/// Long enough to read as movement, short enough not to be waited on.
const Duration _duration = Duration(milliseconds: 240);

/// Long enough for a tick to register, short enough that it never feels like
/// waiting for the sheet to close.
const Duration _confirmationHold = Duration(milliseconds: 650);
