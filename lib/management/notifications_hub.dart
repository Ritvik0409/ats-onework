import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';

class NotificationsHubScreen extends StatefulWidget {
  const NotificationsHubScreen({super.key});

  @override
  State<NotificationsHubScreen> createState() => _NotificationsHubScreenState();
}

class _NotificationsHubScreenState extends State<NotificationsHubScreen> {
  static const Color obsidianBlack = Color(0xFF0D0D11);
  static const Color darkCharcoal = Color(0xFF16161F);
  static const Color champagneGold = Color(0xFFE2B93B);
  static const Color textFrost = Color(0xFFF3F4F6);
  static const Color textMuted = Color(0xFF9CA3AF);

  static const List<String> _tabs = ['All', 'Pending', 'Approved', 'Rejected'];

  final ExpenseStore _store = ExpenseStore.instance;
  late final PageController _pageController;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    setState(() => _selectedIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
    );
  }

  List<AppNotification> _filterFor(String tab, List<AppNotification> all) {
    switch (tab) {
      case 'Pending':
        return all.where((n) => n.type == 'info').toList();
      case 'Approved':
        return all.where((n) => n.type == 'approved').toList();
      case 'Rejected':
        return all.where((n) => n.type == 'rejected').toList();
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            foregroundColor: textFrost,
            title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold, color: textFrost)),
            elevation: 0,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(46),
              child: Row(
                children: List.generate(_tabs.length, (index) {
                  final isSelected = _selectedIndex == index;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _selectTab(index),
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: isSelected ? champagneGold : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                        ),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          style: TextStyle(
                            color: isSelected ? champagneGold : textMuted,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          child: Text(_tabs[index], textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          body: PageView(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (index) => setState(() => _selectedIndex = index),
            children: _tabs.map((tab) {
              final items = _filterFor(tab, _store.notifications);
              return Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  padding: const EdgeInsets.all(16.0),
                  child: items.isEmpty
                      ? const Center(
                          child: Text('No notifications here yet.', style: TextStyle(color: textMuted)),
                        )
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];

                            IconData iconData = Icons.info_rounded;
                            Color accentColor = champagneGold;

                            if (item.type == 'approved') {
                              iconData = Icons.check_circle_rounded;
                              accentColor = Colors.greenAccent.shade400;
                            } else if (item.type == 'rejected') {
                              iconData = Icons.cancel_rounded;
                              accentColor = Colors.redAccent.shade400;
                            }

                            return TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(milliseconds: 250 + (index * 40)),
                              curve: Curves.easeOut,
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                    offset: Offset(0, (1 - value) * 12),
                                    child: child,
                                  ),
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: darkCharcoal,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: champagneGold.withValues(alpha: 0.1), width: 1),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(iconData, color: accentColor, size: 24),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.title,
                                              style: const TextStyle(fontWeight: FontWeight.bold, color: textFrost, fontSize: 15),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              item.subtitle,
                                              style: TextStyle(color: textMuted.withValues(alpha: 0.8), fontSize: 14, height: 1.3),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              item.time,
                                              style: TextStyle(color: textMuted.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}