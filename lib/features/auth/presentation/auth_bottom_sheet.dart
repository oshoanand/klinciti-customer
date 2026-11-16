import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:smart_auth/smart_auth.dart';

import '../providers/auth_modal_provider.dart';

void showAuthBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (context) => const AuthBottomSheet(),
  );
}

class AuthBottomSheet extends ConsumerStatefulWidget {
  const AuthBottomSheet({super.key});

  @override
  ConsumerState<AuthBottomSheet> createState() => _AuthBottomSheetState();
}

class _AuthBottomSheetState extends ConsumerState<AuthBottomSheet> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();

  bool _termsAccepted = false;
  bool _termsError = false;

  // --- VALIDATORS (Matching Zod) ---
  String? _validateIdentifier(String? val) {
    if (val == null || val.isEmpty) return 'Поле обязательно';
    final isEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(val);
    if (isEmail) return null;
    final cleanedPhone = val.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    final isPhone = RegExp(r'^(7|8)\d{10}$').hasMatch(cleanedPhone);
    if (isPhone) return null;
    return 'Введите корректный email или номер телефона';
  }

  String? _validatePassword(String? val) {
    if (val == null || val.length < 8) return 'Минимум 8 символов';
    if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(val)) return 'Только буквы и цифры';
    return null;
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthModalState state) async {
    if (!_formKey.currentState!.validate()) return;

    final notifier = ref.read(authModalProvider.notifier);
    bool shouldClose = false;

    if (state.step == AuthStep.login) {
      shouldClose = await notifier.login(
        _identifierCtrl.text.trim(),
        _passwordCtrl.text,
      );
    } else if (state.step == AuthStep.register) {
      if (!_termsAccepted) {
        setState(() => _termsError = true);
        return;
      }
      await notifier.registerUser(
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        identifier: _identifierCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
    } else if (state.step == AuthStep.forgotPassword) {
      await notifier.forgotPassword(_identifierCtrl.text.trim());
    } else if (state.step == AuthStep.resetPassword) {
      await notifier.resetPassword(_passwordCtrl.text);
    }

    if (shouldClose && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authModalProvider);
    final notifier = ref.read(authModalProvider.notifier);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(bottom: bottomInset, top: 40),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Close Button
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 16, right: 16),
              child: IconButton(
                icon: Icon(LucideIcons.x, color: Colors.grey),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: _buildCurrentStep(state, notifier),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep(AuthModalState state, AuthModalNotifier notifier) {
    switch (state.step) {
      case AuthStep.login:
        return _buildLoginForm(state, notifier);
      case AuthStep.register:
        return _buildRegisterForm(state, notifier);
      case AuthStep.forgotPassword:
        return _buildForgotPasswordForm(state, notifier);
      case AuthStep.otp:
        return _OtpFormWidget(
          state: state,
          notifier: notifier,
          onClose: () => Navigator.pop(context),
          alertWidget: _buildAlert(state),
        );
      case AuthStep.resetPassword:
        return _buildResetPasswordForm(state, notifier);
    }
  }

  // ==========================================
  // STEP 1: LOGIN
  // ==========================================
  Widget _buildLoginForm(AuthModalState state, AuthModalNotifier notifier) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Вход в аккаунт',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Введите ваш номер телефона или почту для продолжения',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),

          _buildAlert(state),

          _buildTextField(
            'Телефон или почта',
            _identifierCtrl,
            validator: _validateIdentifier,
          ),
          const SizedBox(height: 16),

          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => notifier.setStep(AuthStep.forgotPassword),
              child: const Text(
                'Забыли пароль?',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          ),

          _buildTextField(
            'Пароль',
            _passwordCtrl,
            isPassword: true,
            validator: _validatePassword,
          ),
          const SizedBox(height: 24),

          _buildSubmitButton(state, 'Войти'),

          const SizedBox(height: 32),
          const Text(
            'Или продолжить через',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildOAuthBtn(
                  text: 'Яндекс',
                  bg: Colors.white,
                  fg: Colors.black,
                  customIcon: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFC3F1D), // Yandex Red
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Я',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'sans-serif',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildOAuthBtn(
                  text: 'ВКонтакте',
                  bg: const Color(0xFF0077FF), // VK Blue
                  fg: Colors.white,
                  customIcon: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'VK',
                      style: TextStyle(
                        color: Color(0xFF0077FF),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'sans-serif',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Нет аккаунта? ',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              GestureDetector(
                onTap: () {
                  _formKey.currentState?.reset();
                  notifier.setStep(AuthStep.register);
                },
                child: const Text(
                  'Зарегистрироваться',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ==========================================
  // STEP 2: REGISTER
  // ==========================================
  Widget _buildRegisterForm(AuthModalState state, AuthModalNotifier notifier) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Создать аккаунт',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Введите ваши данные для регистрации',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),

          _buildAlert(state),

          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  'Имя',
                  _firstNameCtrl,
                  validator: (v) => v!.isEmpty ? 'Введите имя' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  'Фамилия',
                  _lastNameCtrl,
                  validator: (v) => v!.isEmpty ? 'Введите фамилию' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField(
            'Телефон',
            _identifierCtrl,
            validator: _validateIdentifier,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            'Пароль',
            _passwordCtrl,
            isPassword: true,
            validator: _validatePassword,
          ),

          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _termsAccepted,
                  activeColor: const Color(0xFF0F172A),
                  onChanged: (val) {
                    setState(() {
                      _termsAccepted = val ?? false;
                      _termsError = false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Я принимаю Пользовательское соглашение и Политику обработки данных.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (_termsError)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Необходимо принять соглашение',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          _buildSubmitButton(state, 'Зарегистрироваться'),

          const SizedBox(height: 24),
          Center(
            child: GestureDetector(
              onTap: () {
                _formKey.currentState?.reset();
                notifier.setStep(AuthStep.login);
              },
              child: const Text(
                'Уже есть аккаунт? Войти',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ==========================================
  // STEP 3: FORGOT PASSWORD
  // ==========================================
  Widget _buildForgotPasswordForm(
    AuthModalState state,
    AuthModalNotifier notifier,
  ) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              LucideIcons.key_round,
              color: const Color(0xFF0F172A),
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Восстановление пароля',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Введите ваш email или номер телефона, и мы отправим вам код для сброса пароля.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 32),

          _buildAlert(state),

          _buildTextField(
            '+7 (999) 000-00-00 или email',
            _identifierCtrl,
            validator: _validateIdentifier,
          ),
          const SizedBox(height: 24),

          _buildSubmitButton(state, 'Получить код'),
          const SizedBox(height: 32),
          TextButton(
            onPressed: () => notifier.setStep(AuthStep.login),
            child: const Text(
              'Вернуться ко входу',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ==========================================
  // STEP 5: RESET PASSWORD
  // ==========================================
  Widget _buildResetPasswordForm(
    AuthModalState state,
    AuthModalNotifier notifier,
  ) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Новый пароль',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Придумайте надежный пароль для вашего аккаунта.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),

          _buildAlert(state),

          const Text(
            'НОВЫЙ ПАРОЛЬ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 6),
          _buildTextField(
            '••••••••',
            _passwordCtrl,
            isPassword: true,
            validator: _validatePassword,
          ),

          const SizedBox(height: 16),
          const Text(
            'ПОВТОРИТЕ ПАРОЛЬ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 6),
          _buildTextField(
            '••••••••',
            _confirmPasswordCtrl,
            isPassword: true,
            validator: (v) {
              if (v != _passwordCtrl.text) return 'Пароли не совпадают';
              return null;
            },
          ),

          const SizedBox(height: 32),
          _buildSubmitButton(state, 'Сохранить пароль'),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // --- UI HELPERS ---

  Widget _buildTextField(
    String hint,
    TextEditingController ctrl, {
    bool isPassword = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: isPassword,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.grey.shade100,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildAlert(AuthModalState state) {
    if (state.alertMessage == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: state.isErrorAlert ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: state.isErrorAlert
              ? Colors.red.shade200
              : Colors.green.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            state.isErrorAlert
                ? LucideIcons.circle_alert
                : LucideIcons.circle_check,
            color: state.isErrorAlert ? Colors.red : Colors.green,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.alertMessage!,
              style: TextStyle(
                color: state.isErrorAlert
                    ? Colors.red.shade900
                    : Colors.green.shade900,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton(AuthModalState state, String text) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: state.isLoading ? null : () => _submit(state),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: state.isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildOAuthBtn({
    required String text,
    required Color bg,
    required Color fg,
    required Widget customIcon,
  }) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          customIcon,
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// SEPARATE WIDGET FOR OTP TO HANDLE TIMER, SMS & SHAKE
// ==========================================
class _OtpFormWidget extends StatefulWidget {
  final AuthModalState state;
  final AuthModalNotifier notifier;
  final VoidCallback onClose;
  final Widget alertWidget;

  const _OtpFormWidget({
    required this.state,
    required this.notifier,
    required this.onClose,
    required this.alertWidget,
  });

  @override
  State<_OtpFormWidget> createState() => _OtpFormWidgetState();
}

class _OtpFormWidgetState extends State<_OtpFormWidget>
    with SingleTickerProviderStateMixin {
  final _otpCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _smartAuth = SmartAuth.instance;

  Timer? _timer;
  int _secondsLeft = 50;
  bool _canResend = false;
  bool _isShaking = false;

  late final AnimationController _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  late final Animation<double> _shakeAnimation = Tween<double>(
    begin: 0,
    end: 1,
  ).animate(CurvedAnimation(parent: _shakeController, curve: Curves.linear));

  @override
  void initState() {
    super.initState();
    _startTimer();
    _listenForSms();

    _shakeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) setState(() => _isShaking = false);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  @override
  void didUpdateWidget(_OtpFormWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.isErrorAlert && !oldWidget.state.isErrorAlert) {
      setState(() => _isShaking = true);
      _shakeController.forward(from: 0);
      _otpCtrl.clear();
      FocusScope.of(context).requestFocus(_focusNode);
    }
  }

  Future<void> _listenForSms() async {
    try {
      // ✅ New method name specifically for the User Consent API
      final res = await _smartAuth.getSmsWithUserConsentApi();

      // ✅ New way to check if the code was successfully extracted
      if (res.hasData && res.requireData.code != null && mounted) {
        setState(() {
          _otpCtrl.text = res.requireData.code!;
        });
        _submitOtp(); // Automatically submit once populated
      }
    } catch (e) {
      // Silently fail and allow the user to type manually if the API is unavailable
    }
  }

  void _startTimer() {
    setState(() {
      _secondsLeft = 50;
      _canResend = false;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        setState(() => _canResend = true);
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _shakeController.dispose();

    // ✅ New method name to cleanly remove the consent listener
    _smartAuth.removeUserConsentApiListener();

    _timer?.cancel();
    _otpCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submitOtp() async {
    if (_otpCtrl.text.length != 6) return;

    widget.notifier.clearAlert();

    final shouldClose = await widget.notifier.verifyOtp(_otpCtrl.text.trim());
    if (shouldClose && mounted) {
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasError = widget.state.isErrorAlert;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          height: 56,
          width: 56,
          decoration: BoxDecoration(
            color: hasError
                ? Colors.red.withOpacity(0.1)
                : const Color(0xFF0F172A).withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            hasError ? LucideIcons.shield_alert : LucideIcons.shield_check,
            color: hasError ? Colors.red : const Color(0xFF0F172A),
            size: 28,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Подтверждение',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Мы отправили 6-значный проверочный код на\n${widget.state.identifier}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 32),

        widget.alertWidget,

        AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) {
            final sineValue = math.sin(_shakeAnimation.value * math.pi * 4);
            return Transform.translate(
              offset: Offset(sineValue * 8, 0),
              child: child,
            );
          },
          child: GestureDetector(
            onTap: () => FocusScope.of(context).requestFocus(_focusNode),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: 0.0,
                  child: TextField(
                    controller: _otpCtrl,
                    focusNode: _focusNode,
                    readOnly: _isShaking,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 6,
                    onChanged: (val) {
                      if (hasError) widget.notifier.clearAlert();
                      setState(() {});
                      if (val.length == 6) _submitOtp();
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    final isFocused =
                        _focusNode.hasFocus && _otpCtrl.text.length == index;
                    final hasValue = _otpCtrl.text.length > index;
                    final char = hasValue ? _otpCtrl.text[index] : "";

                    Color borderColor = Colors.transparent;
                    if (hasError) {
                      borderColor = Colors.red;
                    } else if (isFocused) {
                      borderColor = const Color(0xFF0F172A);
                    } else if (hasValue) {
                      borderColor = Colors.grey.shade400;
                    }

                    return Container(
                      width: 45,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: (isFocused || hasError)
                            ? Colors.white
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: borderColor,
                          width: (isFocused || hasError) ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        char,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: hasError
                              ? Colors.red
                              : const Color(0xFF0F172A),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        Text(
          _canResend
              ? 'Код не пришел?'
              : 'Запросить новый код можно через 0:${_secondsLeft.toString().padLeft(2, '0')}',
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        if (_canResend) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: _isShaking
                ? null
                : () {
                    if (widget.state.identifier != null) {
                      widget.notifier.forgotPassword(widget.state.identifier!);
                      _startTimer();
                    }
                  },
            child: const Text(
              'Отправить код снова',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),

        SizedBox(
          height: 48,
          width: double.infinity,
          child: ElevatedButton(
            onPressed:
                widget.state.isLoading ||
                    _isShaking ||
                    _otpCtrl.text.length != 6
                ? null
                : _submitOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: widget.state.isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Подтвердить код',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
