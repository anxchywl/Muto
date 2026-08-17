import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// How long a fold takes.
///
/// Deliberately the same 240ms the sheets already use for stepping and for
/// their own height changes: a fold, the sheet resizing around it and the
/// buttons swapping underneath all happen at once, and any two of them
/// running at different speeds reads as a wobble rather than as one motion.
const Duration focusModeDuration = Duration(milliseconds: 240);

const Curve focusModeCurve = Curves.easeOutCubic;

/// Which field inside a sheet is being typed into, if any.
///
/// A sheet on a phone gives up most of its height the moment the keyboard
/// comes up, and what is left is usually the wrong half: a stepper, a row of
/// chips and three other fields, with the one being typed into pinned against
/// the top of the keyboard. Focus mode is the answer — while a field has the
/// keyboard, everything that is not that field folds away, and comes back
/// when the keyboard goes.
///
/// Owned by the sheet's [State] so the nodes outlive rebuilds, and handed
/// down to whichever widgets need to know. Fields are identified by any
/// object that compares equal across rebuilds; an enum value is the usual one.
final class SheetFocusMode extends ChangeNotifier {
  final Map<Object, FocusNode> _nodes = {};
  Object? _typingIn;
  bool _keyboardVisible = false;

  /// The field with the keyboard, or null when nothing has it.
  Object? get typingIn => _typingIn;

  bool get isTyping => _typingIn != null && _keyboardVisible;

  void setKeyboardVisible(bool value) {
    if (value == _keyboardVisible) return;
    _keyboardVisible = value;
    if (!value && _typingIn != null) {
      _typingIn = null;
    }
  }

  /// True for everything that should fold while [id] is not the field in hand.
  bool hides(Object id) => isTyping && _typingIn != id;

  /// Folds anything that is not a field at all — a stepper, a heading, a row
  /// of chips — since none of it belongs on screen next to a keyboard.
  bool get hidesChrome => isTyping;

  /// The node bound to [id]. The same instance every time, so handing it to a
  /// field that rebuilds does not drop focus mid-keystroke.
  FocusNode nodeFor(Object id) {
    return _nodes.putIfAbsent(id, () {
      final node = FocusNode(debugLabel: 'SheetFocusMode($id)');
      node.addListener(() => _focusChanged(id, node));
      return node;
    });
  }

  void _focusChanged(Object id, FocusNode node) {
    final Object? next;
    if (node.hasFocus) {
      next = id;
    } else if (_typingIn == id && !_keyboardVisible) {
      // a tap straight from one field to another lands the gain before the
      // loss, so only clear when the field losing focus is still the one on
      // record — otherwise focus mode would blink off and back on between them
      next = null;
    } else {
      next = _typingIn;
    }
    if (next == _typingIn) return;
    _typingIn = next;
    notifyListeners();
  }

  /// Puts the keyboard away, which is what leaves focus mode. What "Done"
  /// does, and what moving between steps does.
  void release() {
    for (final node in _nodes.values) {
      if (node.hasFocus) node.unfocus();
    }
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _nodes.clear();
    super.dispose();
  }
}

/// Folds out of the way while the keyboard belongs to something else.
///
/// Collapses vertically rather than shrinking in both directions: the width
/// is held at whatever the row already was, so the content slides up under
/// its own top edge instead of being squeezed toward the middle on the way
/// out.
class FocusFold extends StatelessWidget {
  const FocusFold({
    super.key,
    required this.hidden,
    required this.child,
    this.animateSize = true,
  });

  final bool hidden;
  final Widget child;

  /// Whether this fold animates its own height.
  ///
  /// False when something above it — a sheet's content box, say — already
  /// animates height around it. Two [AnimatedSize]s in an ancestor/descendant
  /// pair both reacting to the same change fight each other: the outer one
  /// aims at the size the child had on the first frame, watches it keep
  /// moving, and then gives up and snaps onto the real size, which reads as
  /// the panel settling and then jumping. Collapsing instantly leaves the one
  /// animation above in charge of the whole motion.
  final bool animateSize;

  @override
  Widget build(BuildContext context) {
    final folded = hidden ? const SizedBox(width: double.infinity) : child;
    if (!animateSize) return folded;

    return AnimatedSize(
      duration: focusModeDuration,
      curve: focusModeCurve,
      alignment: Alignment.topCenter,
      child: folded,
    );
  }
}

/// The space between two fields, which is chrome like everything else: once
/// all but one field has folded away there is nothing left for it to separate,
/// and leaving it behind strands a gap under the one field still on screen.
class FocusGap extends StatelessWidget {
  const FocusGap({
    super.key,
    required this.hidden,
    this.height = AppSpacing.df,
    this.animateSize = true,
  });

  final bool hidden;
  final double height;

  /// See [FocusFold.animateSize].
  final bool animateSize;

  @override
  Widget build(BuildContext context) => FocusFold(
    hidden: hidden,
    animateSize: animateSize,
    child: SizedBox(height: height),
  );
}

/// Puts focus mode's Done button where the sheet's own actions sit — the one
/// button focus mode offers, which dismisses the keyboard and with it focus
/// mode itself.
///
/// [donePadding] should leave the bar the same height as [actions] so nothing
/// above it moves on the swap; the space this frees up belongs to the content
/// above, where it can animate along with the folds.
class FocusModeActions extends StatelessWidget {
  const FocusModeActions({
    super.key,
    required this.isTyping,
    required this.doneLabel,
    required this.onDone,
    required this.actions,
    this.donePadding = EdgeInsets.zero,
  });

  final bool isTyping;
  final String doneLabel;
  final VoidCallback onDone;

  /// What sits there when the keyboard is down.
  final Widget actions;

  /// Matches whatever inset [actions] carries, so Done lands exactly where the
  /// buttons it replaces were.
  final EdgeInsets donePadding;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: focusModeDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: isTyping
          ? Padding(
              key: const ValueKey<String>('focus-mode-done'),
              padding: donePadding,
              child: AppPrimaryButton(
                text: doneLabel,
                size: AppButtonSize.medium,
                onPressed: onDone,
              ),
            )
          : KeyedSubtree(
              key: const ValueKey<String>('focus-mode-actions'),
              child: actions,
            ),
    );
  }
}
