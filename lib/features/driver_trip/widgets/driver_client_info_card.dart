import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';

// Definir localmente para evitar problemas de importación circular
bool hasNavigationBar(BuildContext context) {
  return MediaQuery.of(context).padding.bottom > 0;
}

 // Para usar hasNavigationBar

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
      required this.isArrivalReported,
  });

  final String clientName;
  final String clientAddress;
  final String clientPhotoUrl;
  final int unreadCount;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenNavigation;
  final VoidCallback onReportArrival;
  final bool isSendingArrival;
  final bool isArrivalReported;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width >= 900;

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final hasNavBar = hasNavigationBar(context);

    // Ajuste de padding inferior y superior según barra de navegación y tipo de dispositivo
    final bottomPadding = hasNavBar
        ? bottomInset + (isTablet ? 8.0 : 12.0)
        : (isTablet ? 18.0 : 14.0); // Si no hay barra, baja más el contenido
    final topPadding = (isTablet ? 18.0 : 16.0) + (hasNavBar ? 0.0 : (isTablet ? 6.0 : 8.0));

    return Container(
      width: double.infinity,
      // fill the parent panel height so we can push buttons to bottom
      height: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isTablet ? 20 : 14,
        topPadding,
        isTablet ? 20 : 14,
        bottomPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          // push the top content slightly down from the panel top
          SizedBox(height: isTablet ? 6 : 6),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Client photo on the left (bigger)
              CircleAvatar(
                radius: isTablet ? 52 : 44,
                backgroundColor: AppColores.grey200,
                backgroundImage: clientPhotoUrl.isNotEmpty ? NetworkImage(clientPhotoUrl) : null,
                child: clientPhotoUrl.isEmpty
                    ? const Icon(Icons.person, color: AppColores.textSecondary)
                    : null,
              ),
              const SizedBox(width: 12),
              // Name and below it the icon + address
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clientName,
                      style: TextStyle(
                        fontSize: isTablet ? 29 : 23,
                        fontWeight: FontWeight.w700,
                        color: AppColores.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, color: AppColores.buttonPrimary, size: 19),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            clientAddress.isNotEmpty ? clientAddress : 'Ubicacion del cliente',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColores.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isTablet ? 10 : 8),
          // use a fixed spacer to bring buttons up a bit (instead of Expanded)
          SizedBox(height: isTablet ? 6 : 6),
          Row(
            children: [
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onOpenChat,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
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
                      minimumSize: const Size.fromHeight(52),
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
                onPressed: (isSendingArrival || isArrivalReported) ? null : onReportArrival,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
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
                    : (isArrivalReported
                        ? const Icon(Icons.check, color: AppColores.textWhite)
                        : const Icon(Icons.my_location_rounded)),
                label: Text(
                  isSendingArrival ? 'Enviando...' : (isArrivalReported ? 'Enviado' : 'Ya llegue'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
