class AuthIdentityEntity {
  const AuthIdentityEntity({
    required this.uid,
    this.displayName,
    this.email,
    this.phoneNumber,
  });

  final String uid;
  final String? displayName;
  final String? email;
  final String? phoneNumber;
}
