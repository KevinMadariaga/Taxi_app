class CountryModel {
  const CountryModel({
    required this.isoCode,
    required this.name,
    required this.dialCode,
    required this.flagEmoji,
  });

  final String isoCode;
  final String name;
  final String dialCode;
  final String flagEmoji;
}
