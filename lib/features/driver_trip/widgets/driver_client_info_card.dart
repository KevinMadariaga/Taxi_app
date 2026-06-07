import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class DriverClientInfoCard extends StatefulWidget {
  const DriverClientInfoCard({
    super.key,
    required this.clientName,
    required this.clientAddress,
    required this.clientPhotoUrl,
    required this.unreadCount,
    this.onOpenChat,
    required this.onOpenNavigation,
    required this.onReportArrival,
    required this.isSendingArrival,
    required this.isArrivalReported,
    this.arrivalButtonEnabled = true,
    required this.etaText,
    required this.distanceText,
    required this.title,
    required this.onDetails,
    this.primaryButtonText,
    this.primaryButtonSuccessText,
  });

  final String clientName;
  final String clientAddress;
  final String clientPhotoUrl;
  final int unreadCount;
  final VoidCallback? onOpenChat;
  final VoidCallback onOpenNavigation;
  final VoidCallback onReportArrival;
  final bool isSendingArrival;
  final bool isArrivalReported;
  final String etaText;
  final String distanceText;
  final String title;
  final VoidCallback onDetails;
  final String? primaryButtonText;
  final String? primaryButtonSuccessText;
  final bool arrivalButtonEnabled;

  @override
  State<DriverClientInfoCard> createState() => _DriverClientInfoCardState();
}

class _DriverClientInfoCardState extends State<DriverClientInfoCard>
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
              // ── Top Row: Expand/Collapse & Detalles ───────────────────────
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
                        child: const Text(
                          'Detalles',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColores.textPrimary,
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
              SizedBox(height: _isExpanded ? 20 : 12),

              // ── Barra direccional animada - Always Visible ──────────────────
              _DirectionalBar(animation: _shimmerAnimation),

              if (_isExpanded) ...[
                const SizedBox(height: 24),

                // ── Botones Inferiores (Chat, Nav) ──────────────────────
                Row(
                  children: [
                    if (widget.onOpenChat != null) ...[
                      Expanded(
                        child: InkWell(
                          onTap: widget.onOpenChat,
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColores.buttonPrimary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppColores.buttonPrimary,
                                    width: 1.4,
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_rounded,
                                      size: 18,
                                      color: AppColores.buttonPrimary,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Chat',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
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
                                  child: _UnreadBadge(
                                    count: widget.unreadCount,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: InkWell(
                        onTap: widget.onOpenNavigation,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: AppColores.secondary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.navigation_rounded,
                                size: 18,
                                color: AppColores.textWhite,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Navegar',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppColores.textWhite,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Botón Principal (Llegué) ──────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        (widget.isSendingArrival ||
                            widget.isArrivalReported ||
                            !widget.arrivalButtonEnabled)
                        ? null
                        : widget.onReportArrival,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: AppColores.success,
                      foregroundColor: AppColores.textWhite,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: widget.isSendingArrival
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColores.textWhite,
                            ),
                          )
                        : (widget.isArrivalReported
                              ? const Icon(
                                  Icons.check,
                                  size: 20,
                                  color: AppColores.textWhite,
                                )
                              : const Icon(
                                  Icons.my_location_rounded,
                                  size: 20,
                                  color: AppColores.textWhite,
                                )),
                    label: Text(
                      widget.isArrivalReported
                          ? (widget.primaryButtonSuccessText ?? 'Enviado')
                          : (widget.isSendingArrival
                                ? 'Enviando...'
                                : (widget.primaryButtonText ??
                                      'Ya llegué al punto')),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionalBar extends StatelessWidget {
  const _DirectionalBar({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.directions_car,
          size: 18,
          color: AppColores.buttonPrimary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: AppColores.buttonPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  return FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.3,
                    child: Transform.translate(
                      offset: Offset(
                        MediaQuery.of(context).size.width * animation.value,
                        0,
                      ),
                      child: Container(color: AppColores.buttonPrimary),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        const Icon(Icons.person, size: 18, color: AppColores.textPrimary),
      ],
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
