import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/brand.dart';

/// 首页占位。实现顺序建议：
/// 1. 地图（docs/02-ux-spec.md 3.5）
/// 2. 跟踪面板（3.6）
/// 3. 设备列表 / 事件
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(Brand.appName),
        actions: [
          IconButton(
            tooltip: '设置',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('项目骨架已就绪', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    '按 docs/06-roadmap.md 的 Sprint 顺序实现功能。'
                    '当前为无平台工程的占位版本。',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _StepTile(
            index: 1,
            title: '生成平台工程并配置高德 / 极光',
            subtitle: 'tool/bootstrap.sh → docs/10-setup-runbook.md',
          ),
          _StepTile(
            index: 2,
            title: '实现服务器档案与登录',
            subtitle: 'docs/01-prd.md AUTH-01 ~ AUTH-07',
          ),
          _StepTile(
            index: 3,
            title: '接入跟踪引擎',
            subtitle: 'docs/05-tracking-engine.md',
          ),
          _StepTile(
            index: 4,
            title: '实现实时地图',
            subtitle: 'lib/core/map/tracker_map_view.dart（高德）+ docs/02 3.5',
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.index,
    required this.title,
    required this.subtitle,
  });

  final int index;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('$index')),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}
