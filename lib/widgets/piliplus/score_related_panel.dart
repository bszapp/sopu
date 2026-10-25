// Copied and adapted from PiliPlus lib/pages/video/related/view.dart.
// GPL-3.0-or-later; see SOURCE.md and LICENSE.
import 'package:flutter/material.dart';

import '../common.dart';
import 'score_card_h.dart';

class ScoreRelatedPanel extends StatelessWidget {
  const ScoreRelatedPanel({
    super.key,
    required this.items,
    required this.loading,
    required this.error,
    required this.onReload,
    required this.onOpen,
  });
  final List<Map<String, dynamic>> items;
  final bool loading;
  final String error;
  final VoidCallback onReload;
  final ValueChanged<Map<String, dynamic>> onOpen;
  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.only(top: 7),
      sliver: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (loading) return const SliverToBoxAdapter(child: LoadingCenter());
    if (error.isNotEmpty) {
      return SliverToBoxAdapter(child: ErrorCenter(error, onRetry: onReload));
    }
    return SliverMainAxisGroup(
      slivers: [
        if (items.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(12), child: Text('暂无相关曲谱')),
          )
        else
          SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 600,
              mainAxisExtent: 110,
              mainAxisSpacing: 2,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) =>
                ScoreCardH(items[index], onTap: () => onOpen(items[index])),
          ),
      ],
    );
  }
}
