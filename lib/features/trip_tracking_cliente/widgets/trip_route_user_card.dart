import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class TripRouteUserCard extends StatelessWidget {
  const TripRouteUserCard({
    super.key,
    required this.title,
    required this.userName,
    required this.userPhotoUrl,
    required this.destinationText,
    required this.vehiclePlate,
    required this.vehiclePhotoUrl,
    this.showVehicleInfo = true,
    this.showActionButtons = true,
    this.showSecondaryAction = true,
    this.showCompleteTripButton = false,
    required this.onSharePressed,
    required this.onSecondaryActionPressed,
    this.secondaryActionLabel = 'Panico',
    this.secondaryActionIcon = Icons.warning_amber_rounded,
    this.secondaryActionColor = AppColores.buttonCancel,
    this.onCompleteTripPressed,
  });

  final String title;
  final String userName;
  final String userPhotoUrl;
  final String destinationText;
  final String vehiclePlate;
  final String vehiclePhotoUrl;
  final bool showVehicleInfo;
  final bool showActionButtons;
  final bool showSecondaryAction;
  final bool showCompleteTripButton;
  final VoidCallback onSharePressed;
  final VoidCallback onSecondaryActionPressed;
  final String secondaryActionLabel;
  final IconData secondaryActionIcon;
  final Color secondaryActionColor;
  final VoidCallback? onCompleteTripPressed;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width >= 900;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 22 : 14,
        vertical: isTablet ? 20 : 12,
      ),
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(isTablet ? 24 : 16),
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColores.borderSubtle,
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: isTablet ? 18 : 15,
              color: AppColores.textSecondary,
            ),
          ),
          SizedBox(height: isTablet ? 12 : 8),
          Row(
            children: [
              CircleAvatar(
                radius: isTablet ? 42 : 34,
                backgroundColor: AppColores.primary,
                backgroundImage: userPhotoUrl.isNotEmpty
                    ? NetworkImage(userPhotoUrl)
                    : null,
                child: userPhotoUrl.isEmpty
                    ? const Icon(Icons.person, color: Colors.white, size: 34)
                    : null,
              ),
              SizedBox(width: isTablet ? 14 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName.isNotEmpty ? userName : 'Usuario',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: isTablet ? 22 : 16,
                        color: AppColores.textPrimary,
                      ),
                    ),
                    if (destinationText.trim().isNotEmpty)
                      Text(
                        destinationText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColores.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (showVehicleInfo && vehiclePlate.isNotEmpty)
                      Text(
                        'Placa: $vehiclePlate',
                        style: const TextStyle(
                          color: AppColores.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              if (showVehicleInfo && vehiclePhotoUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    vehiclePhotoUrl,
                    width: isTablet ? 106 : 76,
                    height: isTablet ? 72 : 52,
                    fit: BoxFit.cover,
                  ),
                ),
            ],
          ),
          if (showActionButtons) ...[
            SizedBox(height: isTablet ? 14 : 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onSharePressed,
                    icon: const Icon(Icons.share_location),
                    label: const Text('Ubicacion'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColores.buttonChat,
                      foregroundColor: Colors.white,
                      minimumSize: Size.fromHeight(isTablet ? 52 : 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (showSecondaryAction) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onSecondaryActionPressed,
                      icon: Icon(secondaryActionIcon),
                      label: Text(secondaryActionLabel),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: secondaryActionColor,
                        foregroundColor: Colors.white,
                        minimumSize: Size.fromHeight(isTablet ? 52 : 46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (showCompleteTripButton) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onCompleteTripPressed,
                icon: const Icon(Icons.flag),
                label: const Text('Terminar viaje'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColores.success,
                  foregroundColor: Colors.white,
                  minimumSize: Size.fromHeight(isTablet ? 50 : 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
