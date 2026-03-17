import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class UserTripInfoCard extends StatelessWidget {
  const UserTripInfoCard({
    super.key,
    required this.name,
    required this.userPhotoUrl,
    required this.vehiclePhotoUrl,
    required this.unreadCount,
    required this.onOpenChat,
    required this.onCancel,
    required this.isCancelling,
  });

  final String name;
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

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isTablet ? 20 : 14),
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(isTablet ? 28 : 20),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: isTablet ? 34 : 28,
                backgroundColor: AppColores.primary,
                backgroundImage: userPhotoUrl.isNotEmpty
                    ? NetworkImage(userPhotoUrl)
                    : null,
                child: userPhotoUrl.isEmpty
                    ? const Icon(Icons.person, color: AppColores.textWhite)
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
                        fontSize: isTablet ? 24 : 18,
                        fontWeight: FontWeight.w700,
                        color: AppColores.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Seguimiento en tiempo real',
                      style: TextStyle(color: AppColores.textSecondary),
                    ),
                  ],
                ),
              ),
              if (vehiclePhotoUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    vehiclePhotoUrl,
                    width: isTablet ? 92 : 70,
                    height: isTablet ? 62 : 48,
                    fit: BoxFit.cover,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size.fromHeight(isTablet ? 54 : 48),
                        side: const BorderSide(
                          color: AppColores.buttonChat,
                          width: 1.8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: onOpenChat,
                      icon: const Icon(
                        Icons.chat_bubble_outline,
                        color: AppColores.buttonChat,
                      ),
                      label: const Text(
                        'Chat',
                        style: TextStyle(
                          color: AppColores.buttonChat,
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
                    minimumSize: Size.fromHeight(isTablet ? 54 : 48),
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
