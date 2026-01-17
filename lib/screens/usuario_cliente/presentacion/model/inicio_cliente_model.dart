class LocationShortcut {
  final String title;
  final String subtitle;
  final String iconLetter;

  LocationShortcut({
    required this.title,
    required this.subtitle,
    this.iconLetter = 'L',
  });
}

class LoyaltyProgram {
  final String name;
  final String description;
  final String asset; // optional asset or url

  LoyaltyProgram({
    required this.name,
    required this.description,
    this.asset = '',
  });
}