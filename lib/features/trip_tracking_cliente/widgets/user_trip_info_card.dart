import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class UserTripInfoCard extends StatefulWidget {
  const UserTripInfoCard({
    super.key,
    required this.name,
    required this.vehiclePlate,
    required this.userPhotoUrl,
    required this.vehiclePhotoUrl,
    required this.unreadCount,
    required this.onPrimaryAction,
    required this.onCancel,
    required this.isCancelling,
    required this.etaText,
    required this.distanceText,
    required this.onHelp,
    required this.onDetails,
    this.cancelEnabled = true,
    this.title = 'Conductor llegando a tu ubicacion',
    this.primaryActionText = 'Chat',
    this.primaryActionIcon = Icons.chat_bubble_outline,
  });

  final String name;
  final String vehiclePlate;
  final String userPhotoUrl;
  final String vehiclePhotoUrl;
  final int unreadCount;
  final VoidCallback onPrimaryAction;
  final VoidCallback onCancel;
  final bool isCancelling;
  final bool cancelEnabled;
  final String etaText;
  final String distanceText;
  final VoidCallback onHelp;
  final VoidCallback onDetails;
  final String title;
  final String primaryActionText;
  final IconData primaryActionIcon;

  @override
  State<UserTripInfoCard> createState() => _UserTripInfoCardState();
}

class _UserTripInfoCardState extends State<UserTripInfoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;
  late final Animation<double> _shimmerAnimation;
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _shimmerAnimation = CurvedAnimation(
      parent: _shimmerController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColores.cardBackground,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Top Row: Expand/Collapse and Ayuda ──────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: _toggleExpanded,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 24,
                      ),
                    ),
                  ),
                  if (_isExpanded)
                    InkWell(
                      onTap: widget.onHelp,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Ayuda',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (_isExpanded) const SizedBox(height: 16),

              // ── Title ───────────────────────────────────────────────────────
              if (_isExpanded)
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                    color: AppColores.textPrimary,
                  ),
                ),
              if (_isExpanded) const SizedBox(height: 8),

              // ── Subtitle (ETA/Distance) - Always Visible ──────────────────
              if (_isExpanded)
                Text(
                  'Tiempo estimado: ${widget.etaText} • ${widget.distanceText}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.etaText,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.route_outlined,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.distanceText,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              SizedBox(height: _isExpanded ? 18 : 10),

              // ── Barra direccional animada - Always Visible ──────────────────
              _DirectionalBar(animation: _shimmerAnimation),

              // ── Botones Inferiores (Chat y Detalles) ──────────────────────
              if (_isExpanded) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    InkWell(
                      onTap: widget.onPrimaryAction,
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColores.buttonPrimary.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColores.buttonPrimary,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  widget.primaryActionIcon,
                                  size: 18,
                                  color: AppColores.buttonPrimary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  widget.primaryActionText,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppColores.buttonPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.unreadCount > 0)
                            Positioned(
                              top: -6,
                              right: -4,
                              child: _UnreadBadge(count: widget.unreadCount),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    InkWell(
                      onTap: widget.onDetails,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Detalles',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColores.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
class _DirectionalBar extends StatelessWidget {
  const _DirectionalBar({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return SizedBox(
          height: 48,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icono taxi (izquierda)
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColores.buttonPrimary, // Color verde tracker visual
                ),
                child: const Icon(
                  Icons.local_taxi_rounded, // Taxi a la izquierda
                  color: Colors.white,
                  size: 24,
                ),
              ),

              // Línea animada central
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: (0.15 + animation.value * 0.85).clamp(
                            0.0,
                            1.0,
                          ),
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              color: AppColores.buttonPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Icono persona (derecha)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade300, width: 1.5),
                ),
                child: Icon(
                  Icons.person_outline_rounded, // Persona a la derecha
                  color: Colors.grey.shade800,
                  size: 26,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColores.error,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: const TextStyle(
          color: AppColores.textWhite,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}
