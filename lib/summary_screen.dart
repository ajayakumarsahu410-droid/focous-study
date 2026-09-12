import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database_helper.dart';
import '../state/study_controller.dart';

class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudyController>();
    final todayTotal = c.todayTotals.values.fold<int>(0, (a, b) => a + b);
    final weekTotal = c.weekTotals.values.fold<int>(0, (a, b) => a + b);
    final maxSubject =
        c.weekTotals.values.fold<int>(1, (a, b) => b > a ? b : a);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: c.refreshAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: c.refreshAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Row(
              children: [
                Expanded(
                    child: _StatCard(
                        label: 'Today', value: formatHours(todayTotal))),
                const SizedBox(width: 12),
                Expanded(
                    child: _StatCard(
                        label: 'This week', value: formatHours(weekTotal))),
              ],
            ),
            const SizedBox(height: 20),
            const Text('By subject (this week)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            if (c.weekTotals.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No sessions logged yet.'),
              ),
            for (final e in c.weekTotals.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(e.key),
                        const Spacer(),
                        Text(formatHours(e.value),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: e.value / maxSubject,
                        minHeight: 10,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            const Text('Last 7 days',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            FutureBuilder<List<int>>(
              future: DatabaseHelper.instance.dailyTotals(days: 7),
              builder: (_, snap) {
                final data = snap.data ?? List.filled(7, 0);
                final peak = data.fold<int>(1, (a, b) => b > a ? b : a);
                return SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < data.length; i++)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(formatHours(data[i]),
                                  style: const TextStyle(fontSize: 10)),
                              const SizedBox(height: 4),
                              Container(
                                height: 90 * (data[i] / peak).clamp(0.02, 1.0),
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                DateFormat('E').format(DateTime.now()
                                    .subtract(Duration(days: 6 - i))),
                                style: const TextStyle(fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text('Session log',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final s in c.recent)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline, size: 20),
                title: Text(s.subjectName),
                subtitle: Text(
                    '${DateFormat('EEE d MMM, h:mm a').format(s.startTime)}'),
                trailing: Text(formatHours(s.durationSeconds)),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Theme.of(context).hintColor)),
              const SizedBox(height: 6),
              Text(value,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
}
