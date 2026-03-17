import 'package:flutter/material.dart';
import 'package:taxi_app/domain/models/country_model.dart';

class CountrySelector extends StatelessWidget {
  const CountrySelector({
    super.key,
    required this.countries,
    required this.selectedCountry,
    required this.onChanged,
    this.enabled = true,
  });

  final List<CountryModel> countries;
  final CountryModel selectedCountry;
  final ValueChanged<CountryModel?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<CountryModel>(
      initialValue: selectedCountry,
      decoration: const InputDecoration(
        labelText: 'Pais',
        border: OutlineInputBorder(),
      ),
      items: countries
          .map(
            (country) => DropdownMenuItem<CountryModel>(
              value: country,
              child: Text(
                '${country.flagEmoji} ${country.name} (${country.dialCode})',
              ),
            ),
          )
          .toList(growable: false),
      onChanged: enabled ? onChanged : null,
    );
  }
}
