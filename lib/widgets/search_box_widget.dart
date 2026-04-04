import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class SearchBoxWidget extends StatelessWidget {
  final double scale;
  final VoidCallback onTap;
  const SearchBoxWidget({Key? key, required this.scale, required this.onTap})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 18 * scale),
        decoration: BoxDecoration(
          color: AppColores.surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColores.grey200, width: 1),
          boxShadow: const [
            BoxShadow(
              color: AppColores.borderSubtle,
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(
          vertical: 14 * scale,
          horizontal: 16 * scale,
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: AppColores.buttonPrimary),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Text(
                '¿A dónde vamos?',
                style: TextStyle(
                  color: AppColores.primary,
                  fontSize: 15 * scale,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColores.buttonPrimary),
          ],
        ),
      ),
    );
  }
}
