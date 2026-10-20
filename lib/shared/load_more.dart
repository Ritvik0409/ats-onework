/// A "load more" footer for a cursor-paginated list.
///
/// The API pages by cursor, so a list can hold more rows than one
/// request returns. Without this the rest of the list was simply never
/// fetched.
library;

import 'package:flutter/material.dart';

import 'package:ats_onework/management/expense_store.dart';

/// Shows a button that fetches the next page, when there is one.
///
/// Put it as the last item of a [ListView.builder] and give the builder
/// one extra index for it.
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({
    required this.hasMore,
    required this.loading,
    required this.onLoad,
    super.key,
  });

  final bool hasMore;
  final bool loading;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;
    if (!hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : OutlinedButton.icon(
                onPressed: onLoad,
                icon: Icon(Icons.expand_more_rounded, color: store.accentGold),
                label: Text(
                  'Load more',
                  style: TextStyle(color: store.accentGold),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: store.accentGold.withValues(alpha: 0.4)),
                ),
              ),
      ),
    );
  }
}
