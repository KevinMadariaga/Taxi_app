import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class UserTripInfoCard extends StatelessWidget {
  const UserTripInfoCard({
    super.key,
    required this.name,
    required this.vehiclePlate,
    required this.userPhotoUrl,
    required this.vehiclePhotoUrl,
    required this.unreadCount,
    required this.onOpenChat,
    required this.onCancel,
    required this.isCancelling,
    this.cancelEnabled = true,
  });

  final String name;
  final String vehiclePlate;
  final String userPhotoUrl;
  final String vehiclePhotoUrl;
  final int unreadCount;
  final VoidCallback onOpenChat;
  final VoidCallback onCancel;
  final bool isCancelling;
  final bool cancelEnabled;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width >= 900;
    final isNarrow = width < 390;
    final useVerticalButtons = width < 360;

    // increased avatar size for better visibility
    final avatarRadius = isTablet ? 52.0 : (isNarrow ? 36.0 : 44.0);
    final nameFontSize = isTablet ? 36.0 : (isNarrow ? 20.0 : 22.0);
    final plateFontSize = isTablet ? 20.0 : (isNarrow ? 14.0 : 16.0);
    final textSpacing = isTablet ? 6.0 : 4.0;
    // larger vehicle thumbnail
    final vehicleThumbWidth = isTablet ? 122.0 : (isNarrow ? 86.0 : 96.0);
    final vehicleThumbHeight = isTablet ? 82.0 : (isNarrow ? 58.0 : 68.0);
    final buttonHeight = isTablet ? 60.0 : (isNarrow ? 48.0 : 54.0);
    final cardPadding = EdgeInsets.fromLTRB(
      isTablet ? 26 : (isNarrow ? 14 : 20),
      isTablet ? 22 : (isNarrow ? 14 : 20),
      isTablet ? 26 : (isNarrow ? 14 : 20),
       // reduce bottom padding so buttons can reach nearer to the safe area
       isTablet ? 12 : (isNarrow ? 10 : 12),
    );

    return Container(
      width: double.infinity,
       // let parent decide height; fill it
       height: double.infinity,
      padding: cardPadding,
      decoration: const BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.zero,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: isTablet ? 8 : 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Conductor: foto encima del nombre
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: avatarRadius,
                      backgroundColor: AppColores.primary,
                      backgroundImage: userPhotoUrl.isNotEmpty
                          ? NetworkImage(userPhotoUrl)
                          : null,
                      child: userPhotoUrl.isEmpty
                          ? const Icon(
                              Icons.person,
                              color: AppColores.textWhite,
                              size: 30,
                            )
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      name.isNotEmpty ? name : 'Usuario',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: nameFontSize,
                        fontWeight: FontWeight.w700,
                        color: AppColores.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Vehiculo: foto encima de la placa
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (vehiclePhotoUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          vehiclePhotoUrl,
                          width: vehicleThumbWidth,
                          height: vehicleThumbHeight,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Container(
                        width: vehicleThumbWidth,
                        height: vehicleThumbHeight,
                        decoration: BoxDecoration(
                          color: AppColores.overlayLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.directions_car,
                          color: AppColores.textSecondary,
                          size: 28,
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (vehiclePlate.trim().isNotEmpty)
                      Text(
                        vehiclePlate.trim().toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColores.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: plateFontSize,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isTablet ? 20 : 16),
          // flexible spacer to push buttons toward the bottom (above safe area)
          const Expanded(child: SizedBox.shrink()),
          if (useVerticalButtons) ...[
            SizedBox(
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size.fromHeight(buttonHeight),
                      side: const BorderSide(
                        color: AppColores.buttonPrimary,
                        width: 1.8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onOpenChat,
                    icon: const Icon(
                      Icons.chat_bubble_outline,
                      color: AppColores.buttonPrimary,
                    ),
                    label: const Text(
                      'Chat',
                      style: TextStyle(
                        color: AppColores.buttonPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      top: -8,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColores.error,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : unreadCount.toString(),
                          style: const TextStyle(
                            color: AppColores.textWhite,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: Size.fromHeight(buttonHeight),
                  backgroundColor: AppColores.buttonCancel,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: (isCancelling || !cancelEnabled) ? null : onCancel,
                icon: isCancelling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColores.textWhite,
                        ),
                      )
                    : const Icon(Icons.cancel_outlined),
                label: Text(
                  isCancelling ? 'Cancelando...' : 'Cancelar',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: Size.fromHeight(buttonHeight),
                          side: const BorderSide(
                            color: AppColores.buttonPrimary,
                            width: 1.8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: onOpenChat,
                        icon: const Icon(
                          Icons.chat_bubble_outline,
                          color: AppColores.buttonPrimary,
                        ),
                        label: const Text(
                          'Chat',
                          style: TextStyle(
                            color: AppColores.buttonPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          top: -8,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColores.error,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : unreadCount.toString(),
                              style: const TextStyle(
                                color: AppColores.textWhite,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size.fromHeight(buttonHeight),
                      backgroundColor: AppColores.buttonCancel,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: (isCancelling || !cancelEnabled) ? null : onCancel,
                    icon: isCancelling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColores.textWhite,
                            ),
                          )
                        : const Icon(Icons.cancel_outlined),
                    label: Text(
                      isCancelling ? 'Cancelando...' : 'Cancelar',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
