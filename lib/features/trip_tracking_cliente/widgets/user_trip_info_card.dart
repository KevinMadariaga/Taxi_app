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
  });

  final String name;
  final String vehiclePlate;
  final String userPhotoUrl;
  final String vehiclePhotoUrl;
  final int unreadCount;
  final VoidCallback onOpenChat;
  final VoidCallback onCancel;
  final bool isCancelling;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width >= 900;
    final isNarrow = width < 390;
    final useVerticalButtons = width < 360;

    final avatarRadius = isTablet ? 44.0 : (isNarrow ? 30.0 : 36.0);
    final nameFontSize = isTablet ? 36.0 : (isNarrow ? 20.0 : 22.0);
    final plateFontSize = isTablet ? 20.0 : (isNarrow ? 14.0 : 16.0);
    final textSpacing = isTablet ? 6.0 : 4.0;
    final vehicleThumbWidth = isTablet ? 102.0 : (isNarrow ? 66.0 : 76.0);
    final vehicleThumbHeight = isTablet ? 68.0 : (isNarrow ? 44.0 : 52.0);
    final buttonHeight = isTablet ? 60.0 : (isNarrow ? 48.0 : 54.0);
    final cardPadding = EdgeInsets.fromLTRB(
      isTablet ? 26 : (isNarrow ? 14 : 20),
      isTablet ? 22 : (isNarrow ? 14 : 20),
      isTablet ? 26 : (isNarrow ? 14 : 20),
      isTablet ? 24 : (isNarrow ? 16 : 20),
    );

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: isTablet ? 246 : 216),
      padding: cardPadding,
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(isTablet ? 32 : 24),
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColores.borderSubtle,
            blurRadius: 14,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: isTablet ? 8 : 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isNotEmpty ? name : 'Usuario',
                      style: TextStyle(
                        fontSize: nameFontSize,
                        fontWeight: FontWeight.w700,
                        color: AppColores.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (vehiclePlate.trim().isNotEmpty) ...[
                      SizedBox(height: textSpacing),
                      Text(
                        'Placa: ${vehiclePlate.trim().toUpperCase()}',
                        style: TextStyle(
                          color: AppColores.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: plateFontSize,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    SizedBox(height: textSpacing),
                  ],
                ),
              ),
              if (vehiclePhotoUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    vehiclePhotoUrl,
                    width: vehicleThumbWidth,
                    height: vehicleThumbHeight,
                    fit: BoxFit.cover,
                  ),
                ),
            ],
          ),
          SizedBox(height: isTablet ? 20 : 16),
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
                onPressed: isCancelling ? null : onCancel,
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
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size.fromHeight(buttonHeight),
                      backgroundColor: AppColores.buttonCancel,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: isCancelling ? null : onCancel,
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
