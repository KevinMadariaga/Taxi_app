import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class DriverClientInfoCard extends StatelessWidget {
  const DriverClientInfoCard({
    super.key,
    required this.clientName,
    required this.clientAddress,
    required this.clientPhotoUrl,
    required this.unreadCount,
    required this.onOpenChat,
    required this.onOpenNavigation,
    required this.onReportArrival,
    required this.isSendingArrival,
  });

  final String clientName;
  final String clientAddress;
  final String clientPhotoUrl;
  final int unreadCount;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenNavigation;
  final VoidCallback onReportArrival;
  final bool isSendingArrival;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width >= 900;

    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isTablet ? 20 : 14,
        14,
        isTablet ? 20 : 14,
        18 + bottomInset,
      ),
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(isTablet ? 28 : 20)),
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
                backgroundColor: AppColores.grey200,
                backgroundImage: clientPhotoUrl.isNotEmpty ? NetworkImage(clientPhotoUrl) : null,
                child: clientPhotoUrl.isEmpty
                    ? const Icon(Icons.person, color: AppColores.textSecondary)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clientName,
                      style: TextStyle(
                        fontSize: isTablet ? 23 : 18,
                        fontWeight: FontWeight.w700,
                        color: AppColores.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      clientAddress.isNotEmpty ? clientAddress : 'Ubicacion del cliente',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColores.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
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
                      onPressed: onOpenChat,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: AppColores.buttonPrimary, width: 1.8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline, color: AppColores.buttonPrimary),
                      label: const Text(
                        'Chat',
                        style: TextStyle(color: AppColores.buttonPrimary, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: -8,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
                  onPressed: onOpenNavigation,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: AppColores.buttonPrimary,
                    foregroundColor: AppColores.textWhite,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.navigation_rounded),
                  label: const Text('Navegar', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isSendingArrival ? null : onReportArrival,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: AppColores.success ,
                foregroundColor: AppColores.textWhite,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: isSendingArrival
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColores.textWhite),
                    )
                  : const Icon(Icons.my_location_rounded),
              label: Text(
                isSendingArrival ? 'Enviando...' : 'Ya llegue',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
