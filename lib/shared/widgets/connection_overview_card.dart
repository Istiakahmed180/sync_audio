import 'package:flutter/material.dart';

class ConnectionOverviewCard extends StatelessWidget {
  const ConnectionOverviewCard({
    super.key,
    required this.title,
    required this.state,
    required this.message,
    required this.icon,
    this.busy = false,
  });

  final String title;
  final String state;
  final String message;
  final IconData icon;
  final bool busy;

  bool get _isSuccess =>
      {'Connected', 'Streaming', 'Receiving'}.contains(state);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _isSuccess ? Colors.green.shade600 : scheme.secondary;

    return Card(
      color: color.withValues(alpha: _isSuccess ? .10 : .08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: _isSuccess
            ? BorderSide(color: color.withValues(alpha: .30), width: 1)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: .18),
              foregroundColor: color,
              radius: 24,
              child: busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 3),
                  Text(
                    state,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(message, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
