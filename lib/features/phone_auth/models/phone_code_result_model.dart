enum AuthNextDestination {
  clientHome,
  completeClientProfile,
  clientRegistration,
  adminPanel,
  adminRegistration,
}

class PhoneCodeResultModel {
  const PhoneCodeResultModel({required this.verificationId, this.resendToken});

  final String verificationId;
  final int? resendToken;
}

class AuthResolutionModel {
  const AuthResolutionModel({
    required this.destination,
    required this.uid,
    required this.phoneNumber,
  });

  final AuthNextDestination destination;
  final String uid;
  final String phoneNumber;
}
