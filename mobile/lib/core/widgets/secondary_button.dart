import 'package:flutter/material.dart';
import 'primary_button.dart';

/// Secondary call-to-action — visually the outlined variant of
/// [PrimaryButton]. Kept as its own widget (rather than making every
/// call site pass `variant: outlined`) so secondary actions read clearly
/// at the call site and can diverge from [PrimaryButton] later without
/// touching every screen that uses one.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isEnabled = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    return PrimaryButton(
      label: label,
      onPressed: onPressed,
      isLoading: isLoading,
      isEnabled: isEnabled,
      variant: PrimaryButtonVariant.outlined,
    );
  }
}
