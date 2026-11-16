import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import 'auth_provider.dart';

enum AuthStep { login, register, forgotPassword, otp, resetPassword }

enum OtpContext { auth, register, reset }

class AuthModalState {
  final AuthStep step;
  final OtpContext otpContext;
  final String identifier;
  final String verifiedOtp;
  final bool isLoading;
  final String? alertMessage;
  final bool isErrorAlert;

  AuthModalState({
    this.step = AuthStep.login,
    this.otpContext = OtpContext.auth,
    this.identifier = '',
    this.verifiedOtp = '',
    this.isLoading = false,
    this.alertMessage,
    this.isErrorAlert = false,
  });

  AuthModalState copyWith({
    AuthStep? step,
    OtpContext? otpContext,
    String? identifier,
    String? verifiedOtp,
    bool? isLoading,
    String? alertMessage,
    bool? isErrorAlert,
    bool clearAlert = false,
  }) {
    return AuthModalState(
      step: step ?? this.step,
      otpContext: otpContext ?? this.otpContext,
      identifier: identifier ?? this.identifier,
      verifiedOtp: verifiedOtp ?? this.verifiedOtp,
      isLoading: isLoading ?? this.isLoading,
      alertMessage: clearAlert ? null : (alertMessage ?? this.alertMessage),
      isErrorAlert: isErrorAlert ?? this.isErrorAlert,
    );
  }
}

final authModalProvider =
    StateNotifierProvider.autoDispose<AuthModalNotifier, AuthModalState>((ref) {
      return AuthModalNotifier(ref.watch(apiClientProvider), ref);
    });

class AuthModalNotifier extends StateNotifier<AuthModalState> {
  final ApiClient _api;
  final Ref _ref;

  AuthModalNotifier(this._api, this._ref) : super(AuthModalState());

  void setStep(AuthStep step) =>
      state = state.copyWith(step: step, clearAlert: true);

  void clearAlert() => state = state.copyWith(clearAlert: true);

  // 1. LOGIN ROUTE
  Future<bool> login(String identifier, String password) async {
    state = state.copyWith(
      isLoading: true,
      identifier: identifier,
      clearAlert: true,
    );
    try {
      final res = await _api.dio.post(
        '/auth/login',
        data: {'identifier': identifier, 'password': password},
      );

      // Backend returns 200 with needsVerification if OTP is required
      if (res.data['needsVerification'] == true) {
        state = state.copyWith(
          isLoading: false,
          step: AuthStep.otp,
          otpContext: OtpContext.auth,
          alertMessage: 'Необходимо подтвердить аккаунт. Код отправлен.',
          isErrorAlert: false,
        );
        return false; // Wait for OTP
      }

      // Delegate saving the session to the global AuthController!
      await _ref.read(authControllerProvider).saveSession(res.data);

      state = state.copyWith(isLoading: false);
      return true; // Success, close modal
    } catch (e) {
      final error = e is ApiException
          ? e
          : ApiException.fromDioException(e as dynamic);
      state = state.copyWith(
        isLoading: false,
        alertMessage: error.message,
        isErrorAlert: true,
      );
      return false;
    }
  }

  // 2. REGISTER ROUTE
  Future<void> registerUser({
    required String firstName,
    required String lastName,
    required String identifier,
    required String password,
  }) async {
    state = state.copyWith(
      isLoading: true,
      identifier: identifier,
      clearAlert: true,
    );
    try {
      await _api.dio.post(
        '/auth/register',
        data: {
          'firstName': firstName,
          'lastName': lastName,
          'identifier': identifier,
          'password': password,
          'role': 'CUSTOMER',
          'termsAccepted': true,
        },
      );

      // On successful registration, backend sends OTP
      state = state.copyWith(
        isLoading: false,
        step: AuthStep.otp,
        otpContext: OtpContext.register,
        alertMessage: 'Код отправлен. Подтвердите контактные данные',
        isErrorAlert: false,
      );
    } catch (e) {
      final error = e is ApiException
          ? e
          : ApiException.fromDioException(e as dynamic);
      state = state.copyWith(
        isLoading: false,
        alertMessage: error.message,
        isErrorAlert: true,
      );
    }
  }

  // 3. FORGOT PASSWORD ROUTE
  Future<void> forgotPassword(String identifier) async {
    state = state.copyWith(
      isLoading: true,
      identifier: identifier,
      clearAlert: true,
    );
    try {
      await _api.dio.post(
        '/auth/forgot-password',
        data: {'identifier': identifier},
      );
      state = state.copyWith(
        isLoading: false,
        step: AuthStep.otp,
        otpContext: OtpContext.reset,
        alertMessage: 'Код для сброса пароля отправлен',
        isErrorAlert: false,
      );
    } catch (e) {
      final error = e is ApiException
          ? e
          : ApiException.fromDioException(e as dynamic);
      state = state.copyWith(
        isLoading: false,
        alertMessage: error.message,
        isErrorAlert: true,
      );
    }
  }

  // 4. VERIFY OTP ROUTE
  Future<bool> verifyOtp(String otp) async {
    state = state.copyWith(isLoading: true, clearAlert: true);
    try {
      final res = await _api.dio.post(
        '/auth/verify-otp',
        data: {
          'identifier': state.identifier,
          'otp': otp,
          'context': state.otpContext.name.toUpperCase(),
        },
      );

      if (state.otpContext == OtpContext.reset) {
        // Reset context doesn't return a token, it just allows password change
        state = state.copyWith(
          isLoading: false,
          verifiedOtp: otp,
          step: AuthStep.resetPassword,
        );
        return false; // Keep modal open to show reset screen
      } else {
        // FIXED: Delegate saving the session to the global AuthController!
        await _ref.read(authControllerProvider).saveSession(res.data);

        state = state.copyWith(isLoading: false);
        return true; // Success, close modal
      }
    } catch (e) {
      final error = e is ApiException
          ? e
          : ApiException.fromDioException(e as dynamic);
      state = state.copyWith(
        isLoading: false,
        alertMessage: error.message,
        isErrorAlert: true,
      );
      return false;
    }
  }

  // 5. RESET PASSWORD ROUTE
  Future<void> resetPassword(String newPassword) async {
    state = state.copyWith(isLoading: true, clearAlert: true);
    try {
      await _api.dio.post(
        '/auth/reset-password',
        data: {
          'identifier': state.identifier,
          'otp': state.verifiedOtp,
          'newPassword': newPassword,
        },
      );

      state = state.copyWith(
        isLoading: false,
        step: AuthStep.login,
        alertMessage: 'Пароль успешно изменен. Теперь вы можете войти',
        isErrorAlert: false,
      );
    } catch (e) {
      final error = e is ApiException
          ? e
          : ApiException.fromDioException(e as dynamic);
      state = state.copyWith(
        isLoading: false,
        alertMessage: error.message,
        isErrorAlert: true,
      );
    }
  }
}
