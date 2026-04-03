import 'package:flutter/material.dart';
import 'package:hiddify/utils/utils.dart';

bool showDrawerButton(BuildContext context) {
  return true;
}

class NestedAppBar extends StatelessWidget {
  const NestedAppBar({
    super.key,
    this.title,
    this.actions,
    this.pinned = true,
    this.forceElevated = false,
    this.bottom,
  });

  final Widget? title;
  final List<Widget>? actions;
  final bool pinned;
  final bool forceElevated;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      leading: _buildLeadingButton(context),
      title: title,
      actions: _buildActions(context),
      pinned: pinned,
      forceElevated: forceElevated,
      bottom: bottom,
    );
  }

  Widget? _buildLeadingButton(BuildContext context) {
    final scaffoldState = Scaffold.maybeOf(context);
    final hasDrawer = scaffoldState?.hasDrawer ?? false;
    if (hasDrawer && showDrawerButton(context)) {
      return FocusableActionDetector(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              scaffoldState?.openDrawer();
              return null;
            },
          ),
        },
        child: Builder(
          builder: (BuildContext context) {
            final isFocused = Focus.of(context).hasFocus;
            return DrawerButton(
              onPressed: () {
                scaffoldState?.openDrawer();
              },
              style: ButtonStyle(
                overlayColor: MaterialStateProperty.resolveWith<Color?>(
                  (Set<MaterialState> states) {
                    if (states.contains(MaterialState.focused)) {
                      return Theme.of(context).colorScheme.primary.withOpacity(0.12);
                    }
                    return null;
                  },
                ),
              ),
            );
          },
        ),
      );
    } else if (Navigator.of(context).canPop()) {
      return FocusableActionDetector(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: Builder(
          builder: (BuildContext context) {
            final isFocused = Focus.of(context).hasFocus;
            return IconButton(
              icon: Icon(context.isRtl ? Icons.arrow_forward : Icons.arrow_back),
              padding: EdgeInsets.only(right: context.isRtl ? 50 : 0),
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: ButtonStyle(
                overlayColor: MaterialStateProperty.resolveWith<Color?>(
                  (Set<MaterialState> states) {
                    if (states.contains(MaterialState.focused)) {
                      return Theme.of(context).colorScheme.primary.withOpacity(0.12);
                    }
                    return null;
                  },
                ),
              ),
            );
          },
        ),
      );
    }
    return null;
  }

  List<Widget>? _buildActions(BuildContext context) {
    if (actions == null) return null;
    return actions!.map((action) {
      return FocusableActionDetector(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (action is IconButton) {
                action.onPressed?.call();
              }
              return null;
            },
          ),
        },
        child: Builder(
          builder: (BuildContext context) {
            final isFocused = Focus.of(context).hasFocus;
            if (action is IconButton) {
              return IconButton(
                icon: action.icon,
                onPressed: action.onPressed,
                style: ButtonStyle(
                  overlayColor: MaterialStateProperty.resolveWith<Color?>(
                    (Set<MaterialState> states) {
                      if (states.contains(MaterialState.focused)) {
                        return Theme.of(context).colorScheme.primary.withOpacity(0.12);
                      }
                      return null;
                    },
                  ),
                ),
              );
            }
            return action;
          },
        ),
      );
    }).toList();
  }
}