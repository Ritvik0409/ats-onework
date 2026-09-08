import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';

class NotificationsHubScreen extends StatefulWidget {
  const NotificationsHubScreen({super.key});

  @override
  State<NotificationsHubScreen> createState() => _NotificationsHubScreenState();
}

class _NotificationsHubScreenState extends State<NotificationsHubScreen> {
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
        final obsidianBlack = _store.bg;
        final darkCharcoal = _store.card;
        final champagneGold = _store.accentGold;
        final textFrost = _store.textFrost;
        final textMuted = _store.textMuted;
        
        final List<BoxShadow> cardShadows = _store.isDarkMode
            ? <BoxShadow>[]
            : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 4)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 12), spreadRadius: -4),
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 2, offset: const Offset(0, -1)),
              ];

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            foregroundColor: textFrost,
            title: Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold, color: textFrost)),
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
                      ? Center(
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
                                  border: Border.all(color: _store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2), width: 1),
                                  boxShadow: cardShadows,
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
                                              style: TextStyle(fontWeight: FontWeight.bold, color: textFrost, fontSize: 15),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              item.subtitle.replaceAll('. Reason:', '.\nReason:'), style: TextStyle(color: textMuted.withValues(alpha: 0.85), fontSize: 13)),
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