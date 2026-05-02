import 'api_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  Future<Map<String, dynamic>> login(
    String userOrEmail,
    String password,
    String pin,
  ) => ApiService.instance.login(
        usernameOrEmail: userOrEmail,
        password: password,
        pin: pin,
      );

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String password2,
    String? firstName,
    String? lastName,
  }) =>
      ApiService.instance.register(
        username: username,
        email: email,
        password: password,
        password2: password2,
        firstName: firstName,
        lastName: lastName,
      );

  Future<Map<String, dynamic>> me() => ApiService.instance.getMe();
  Future<void> logout() => ApiService.instance.logout();
  Future<String?> changeCurrency(dynamic currency) =>
      ApiService.instance.changeCurrency(currency);
}
