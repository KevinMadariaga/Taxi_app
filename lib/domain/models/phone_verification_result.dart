class PhoneVerificationResult {
  const PhoneVerificationResult({
    required this.verificationId,
    this.resendToken,
  });

  final String verificationId;
  final int? resendToken;
}
