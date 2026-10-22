import 'package:flutter/material.dart';

import '../core/formatting.dart';
import 'tokens.dart';

/// Standard scrolling page: safe area, responsive gutters, centred
/// content capped at a readable width.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.child,
    this.maxWidth = AppTokens.pageMaxWidth,
    this.padding,
    this.controller,
    this.busy = false,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets? padding;
  final ScrollController? controller;

  /// Shows a thin progress bar while a refresh is in flight. The page
  /// keeps the data it already has — the bar says "this is updating"
  /// instead of blanking the screen.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 700;
    final EdgeInsets gutters =
        padding ??
        EdgeInsets.fromLTRB(
          wide ? 32 : 18,
          wide ? 28 : 18,
          wide ? 32 : 18,
          wide ? 48 : 110,
        );
    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: SingleChildScrollView(
              controller: controller,
              padding: gutters,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The app's one card surface.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.color,
    this.borderColor,
    this.margin,
    this.radius = AppTokens.radiusLg,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final EdgeInsetsGeometry? margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final BorderRadius shape = BorderRadius.circular(radius);
    return Container(
      margin: margin,
      decoration: BoxDecoration(borderRadius: shape, boxShadow: palette.shadow),
      child: Material(
        color: color ?? palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: shape,
          side: BorderSide(color: borderColor ?? palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: 12),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(color: palette.muted, fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// KPI tile used across every dashboard.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.subtitle,
    this.trend,
    this.trendLabel,
    this.increaseIsGood = true,
    this.onTap,
    this.loading = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final String? subtitle;
  final double? trend;

  /// Explains what the trend is measured against ("vs prev").
  final String? trendLabel;
  final bool increaseIsGood;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    // A flat trend is neither good nor bad — colouring it red would read
    // as a problem that is not there.
    final Color trendColor = trend == null || trend! == 0
        ? palette.muted
        : (trend! >= 0) == increaseIsGood
        ? palette.success
        : palette.danger;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (loading)
            SkeletonBox(width: 92, height: 30)
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
            ),
          if (subtitle != null || trend != null) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                if (trend != null) ...<Widget>[
                  Icon(
                    trend! >= 0
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    size: 15,
                    color: trendColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${trend!.abs().toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: trendColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (trendLabel != null) ...<Widget>[
                    const SizedBox(width: 4),
                    Text(
                      trendLabel!,
                      style: TextStyle(color: palette.muted, fontSize: 11.5),
                    ),
                  ],
                  const SizedBox(width: 6),
                ],
                if (subtitle != null)
                  Expanded(
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.muted, fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    required this.color,
    this.label,
    this.icon,
  });

  final String status;
  final Color color;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label ?? status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: compact ? 18 : 34,
        horizontal: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: compact ? 44 : 58,
            height: compact ? 44 : 58,
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: palette.muted, size: compact ? 22 : 28),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.text,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 14 : 16,
            ),
          ),
          if (message != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.muted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          if (action != null) ...<Widget>[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Shimmer placeholder. Replaces the bare spinners that made loaded and
/// unloaded states indistinguishable.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(
              palette.surfaceAlt,
              palette.border,
              0.25 + _controller.value * 0.35,
            ),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key, this.cards = 4});

  final int cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SkeletonBox(width: 220, height: 26),
        const SizedBox(height: 10),
        const SkeletonBox(width: 150, height: 14),
        const SizedBox(height: 26),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final int columns = constraints.maxWidth >= 760 ? 4 : 2;
            final double width =
                (constraints.maxWidth - (columns - 1) * 14) / columns;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: List<Widget>.generate(
                cards,
                (_) => SizedBox(
                  width: width,
                  height: 140,
                  child: const AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SkeletonBox(width: 38, height: 38, radius: 12),
                        SizedBox(height: 16),
                        SkeletonBox(width: 90, height: 24),
                        SizedBox(height: 10),
                        SkeletonBox(width: 120, height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        const AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SkeletonBox(width: 180, height: 18),
              SizedBox(height: 24),
              SkeletonBox(height: 180, radius: 14),
            ],
          ),
        ),
      ],
    );
  }
}

class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.height = 220,
    this.legend = const <ChartLegendItem>[],
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double height;
  final Widget child;
  final List<ChartLegendItem> legend;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: title,
            subtitle: subtitle,
            trailing: trailing,
            padding: EdgeInsets.zero,
          ),
          if (legend.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            ChartLegend(items: legend),
          ],
          const SizedBox(height: 16),
          SizedBox(height: height, child: child),
        ],
      ),
    );
  }
}

class ChartLegendItem {
  const ChartLegendItem(this.label, this.color, {this.value});

  final String label;
  final Color color;
  final String? value;
}

class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.items});

  final List<ChartLegendItem> items;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: items
          .map(
            (ChartLegendItem item) => Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: item.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  item.value == null
                      ? item.label
                      : '${item.label} · ${item.value}',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
  }
}

/// A progress bar that cannot render NaN or out-of-range values.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 8,
    this.trackColor,
  });

  final double value;
  final Color color;
  final double height;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final double safe = value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: safe,
        minHeight: height,
        backgroundColor: trackColor ?? palette.surfaceAlt,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

/// Wraps children into a responsive grid without a GridView.
class AppGrid extends StatelessWidget {
  const AppGrid({
    super.key,
    required this.children,
    this.minItemWidth = 210,
    this.spacing = 14,
    this.maxColumns = 4,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final int columns = (width / minItemWidth).floor().clamp(1, maxColumns);
        final double itemWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: children
              .map((Widget child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }
}

/// Compact action tile used in "Quick actions" rows.
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Color color = accent ?? palette.gold;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: palette.muted, size: 18),
        ],
      ),
    );
  }
}

/// Greeting + identity block shared by every dashboard.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.initials,
    this.trailing,
    this.accent,
  });

  final String title;
  final String subtitle;
  final String? initials;
  final Widget? trailing;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Color color = accent ?? palette.gold;
    final bool wide = MediaQuery.sizeOf(context).width >= 640;

    final Widget identity = Row(
      children: <Widget>[
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          alignment: Alignment.center,
          child: initials == null || initials!.isEmpty
              ? Icon(Icons.person_rounded, color: color, size: 26)
              : Text(
                  initials!,
                  style: TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.text,
                  fontSize: wide ? 22 : 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    );

    if (trailing == null) return identity;
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[identity, const SizedBox(height: 14), trailing!],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(child: identity),
        const SizedBox(width: 16),
        trailing!,
      ],
    );
  }
}

/// Segmented date-window picker used by the analytical dashboards.
class RangePicker extends StatelessWidget {
  const RangePicker({super.key, required this.value, required this.onChanged});

  final AnalyticsRange value;
  final ValueChanged<AnalyticsRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Wrap(
          spacing: 2,
          runSpacing: 2,
          children: AnalyticsRange.values.map((AnalyticsRange range) {
            final bool selected = range == value;
            return Material(
              color: selected ? palette.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: selected ? null : () => onChanged(range),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    range.label,
                    style: TextStyle(
                      color: selected ? palette.text : palette.muted,
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Inline error with a retry affordance. Replaces bare red text and the
/// silent empty states the dashboards used to show on a failed load.
class InlineError extends StatelessWidget {
  const InlineError({
    super.key,
    required this.message,
    this.onRetry,
    this.title = 'Could not load analytics',
  });

  final String message;
  final VoidCallback? onRetry;

  /// What failed. Defaults to the analytics wording; other screens pass
  /// their own.
  final String title;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return AppCard(
      borderColor: palette.danger.withValues(alpha: 0.35),
      child: Row(
        children: <Widget>[
          Icon(Icons.cloud_off_rounded, color: palette.danger, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(width: 8),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}

/// Limits `value` to a sane 0..1 fraction — the guard that stops NaN and
/// Infinity from reaching layout.
double safeFraction(double value) =>
    value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;

/// The identity block at the top of the profile screens: avatar, name,
/// email and the tags under it.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.initials,
    required this.name,
    required this.email,
    this.tags = const <Widget>[],
  });

  final String initials;
  final String name;
  final String email;
  final List<Widget> tags;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Row(
      children: <Widget>[
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: palette.gold.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: palette.gold.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: TextStyle(
              color: palette.gold,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
              if (tags.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: tags),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A card of settings rows with dividers between them.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            children[i],
            if (i != children.length - 1)
              Divider(height: 1, color: palette.border),
          ],
        ],
      ),
    );
  }
}

/// A tappable row: title, optional subtitle, optional leading and
/// trailing. The access catalogue, the people list and the tool menus
/// all used to carry their own copy of this card.
class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Small muted label above a form field.
class AppFieldLabel extends StatelessWidget {
  const AppFieldLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: palette.muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing case final Widget widget) widget,
        ],
      ),
    );
  }
}

/// A month chip that opens a date picker and can be cleared.
///
/// The report screens each had their own copy of this chip — including
/// its own colour scheme override for the picker.
class AppMonthFilter extends StatelessWidget {
  const AppMonthFilter({
    super.key,
    required this.value,
    required this.onChanged,
    this.clearLabel = 'All time',
  });

  /// The selected month, or null for "no month filter".
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final DateTime? month = value;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () async {
        final DateTime now = DateTime.now();
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: month ?? now,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.gold.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.calendar_month_rounded, size: 16, color: palette.gold),
            const SizedBox(width: 8),
            Text(
              month == null ? clearLabel : formatMonthLabel(month),
              style: TextStyle(
                color: palette.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (month != null) ...<Widget>[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => onChanged(null),
                child: Icon(Icons.close_rounded, size: 18, color: palette.gold),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Filter chips for the list screens. One implementation so every list
/// filters the same way — the old copies each styled their own chips.
class AppFilterBar extends StatelessWidget {
  const AppFilterBar({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    // A single scrollable line instead of a Wrap: five filters on a
    // narrow phone used to wrap into two rows of floating chips, which
    // read as clutter. One steady row keeps the card list predictable.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < options.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 8),
            Builder(
              builder: (BuildContext chipContext) {
                final bool selected = options[i] == value;
                return ChoiceChip(
                  label: Text(options[i]),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (bool isSelected) {
                    if (!isSelected) return;
                    onChanged(options[i]);
                    // Bring the picked chip fully into view when it was
                    // partly scrolled off.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      Scrollable.ensureVisible(
                        chipContext,
                        alignment: 0.1,
                        duration: const Duration(milliseconds: 200),
                      );
                    });
                  },
                  selectedColor: palette.gold.withValues(alpha: 0.18),
                  backgroundColor: palette.surfaceAlt,
                  side: BorderSide(
                    color: selected ? palette.gold : palette.border,
                  ),
                  labelStyle: TextStyle(
                    color: selected ? palette.gold : palette.muted,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 12.5,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Themed search field used by the list screens.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Search…',
    this.controller,
  });

  final ValueChanged<String> onChanged;
  final String hint;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(color: palette.text, fontSize: 13.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: palette.muted, fontSize: 13.5),
        prefixIcon: Icon(Icons.search_rounded, color: palette.gold, size: 20),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

/// Small pill for metadata (a project name, a category, a count).
class AppTag extends StatelessWidget {
  const AppTag({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.dense = false,
    this.maxLines,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool dense;

  /// Clamps the label so a long value cannot stretch a row it sits in.
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Color tint = color ?? palette.gold;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 9,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: dense ? 10 : 12, color: tint),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: maxLines ?? 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tint,
                fontSize: dense ? 10 : 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
