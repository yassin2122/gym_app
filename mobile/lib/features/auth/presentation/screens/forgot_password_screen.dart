import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../../../core/widgets/primary_button.dart';
import '../providers/auth_state_notifier.dart';
import '../widgets/auth_header.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSubmitting = false;
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    final failure = await ref
        .read(authStateProvider.notifier)
        .sendPasswordReset(_emailController.text.trim());

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (failure != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    } else {
      setState(() => _emailSent = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: LoadingOverlay(
        isLoading: _isSubmitting,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            child: _emailSent ? _buildConfirmation() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthHeader(
              title: 'Reset password',
              subtitle: "Enter your email and we'll send you a reset link.",
            ),
            const SizedBox(height: AppSpacing.xl),
            AppTextField(
              label: 'Email',
              controller: _emailController,
              hintText: 'you@example.com',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              validator: Validators.email,
              onSubmitted: (_) => _handleSubmit(),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Send Reset Link',
              isLoading: _isSubmitting,
              onPressed: _handleSubmit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmation() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.mark_email_read_outlined,
            color: AppColors.accentGreen,
            size: 64,
          ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'Check your email',
            style: AppTypography.headline,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "We've sent a password reset link to ${_emailController.text.trim()}.",
            style: AppTypography.body,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
