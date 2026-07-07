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
    this.isMoto = false,
    this.onReportProblem,
  });

  final bool isMoto;
  final VoidCallback? onReportProblem;
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
              _DirectionalBar(animation: _shimmerAnimation, isMoto: widget.isMoto),

              if (_isExpanded) ...[
                const SizedBox(height: 24),

                // ── Acciones ──────────────────────────────────────────────
                if (widget.onOpenChat != null) ...[
                  // Con chat: [Chat | Navegar] y botón principal debajo.
                  Row(
                    children: [
                      Expanded(child: _buildChatButton()),
                      const SizedBox(width: 8),
                      Expanded(child: _buildNavegarButton()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: _buildPrimaryButton(),
                  ),
                ] else
                  // Sin chat: Navegar y botón principal uno al lado del otro.
                  SizedBox(
                    height: 52,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _buildNavegarButton()),
                        const SizedBox(width: 12),
                        Expanded(child: _buildPrimaryButton()),
                      ],
                    ),
                  ),
                if (widget.onReportProblem != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: widget.onReportProblem,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade400, width: 1.4),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: Icon(Icons.report_problem_rounded, size: 18, color: Colors.red.shade700),
                      label: Text(
                        'Problemas con el cliente',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.red.shade700),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatButton() {
    return InkWell(
      onTap: widget.onOpenChat,
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: AppColores.buttonPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColores.buttonPrimary, width: 1.5),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 18,
                  color: AppColores.buttonPrimary,
                ),
                SizedBox(width: 6),
                Text(
                  'Chat',
                  style: TextStyle(
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
    );
  }

  Widget _buildNavegarButton() {
    return InkWell(
      onTap: widget.onOpenNavigation,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: AppColores.secondary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
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
    );
  }

  Widget _buildPrimaryButton() {
    return ElevatedButton.icon(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
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
                ? const Icon(Icons.check, size: 20, color: AppColores.textWhite)
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
                  : (widget.primaryButtonText ?? 'Ya llegué al punto')),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }
}

class _DirectionalBar extends StatelessWidget {
  const _DirectionalBar({required this.animation, this.isMoto = false});
  final Animation<double> animation;
  final bool isMoto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColores.buttonPrimary,
          ),
          child: Icon(
            isMoto
                ? Icons.two_wheeler_rounded
                : Icons.directions_car_filled_rounded,
            color: Colors.white,
            size: 24,
          ),
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
