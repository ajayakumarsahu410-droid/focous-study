import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/focus_mode_service.dart';
import '../state/study_controller.dart';

class TimerScreen extends StatelessWidget {
  const TimerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudyController>();
    final slot = c.currentSlot;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          Row(
            children: [
              const Text('Focus Study',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (c.focusActive)
                const Chip(
                  avatar: Icon(Icons.do_not_disturb_on, size: 18),
                  label: Text('DND on'),
                ),
            ],
          ),
          const SizedBox(height: 16),

          if (slot != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_available),
                title: Text('Scheduled now: ${slot.subjectName}'),
                subtitle: Text(
                    '${slot.startTod.format(context)} - ${slot.endTod.format(context)}'),
                trailing: TextButton(
                  onPressed: c.hasActiveSession
                      ? null
                      : () {
                          c.selectSubject(slot.subjectName);
                          c.start();
                        },
                  child: const Text('Start'),
                ),
              ),
            ),

          const SizedBox(height: 8),
          const Text('Subject', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in c.subjects)
                ChoiceChip(
                  label: Text(s.name),
                  selected: c.selectedSubject == s.name,
                  avatar: CircleAvatar(backgroundColor: s.color, radius: 7),
                  onSelected: c.hasActiveSession
                      ? null
                      : (_) => c.selectSubject(s.name),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('New'),
                onPressed: () => _addSubjectDialog(context, c),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ----------------------------------------------------- stopwatch
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              child: Column(
                children: [
                  Text(
                    formatDuration(c.elapsed),
                    style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    c.hasActiveSession
                        ? (c.isRunning ? 'Recording...' : 'Paused')
                        : 'Ready',
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: Icon(c.isRunning
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                          label: Text(c.isRunning
                              ? 'Pause'
                              : (c.hasActiveSession ? 'Resume' : 'Start')),
                          onPressed: c.selectedSubject == null
                              ? null
                              : () => c.isRunning ? c.pause() : c.start(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.stop_rounded),
                          label: const Text('Stop & save'),
                          onPressed: !c.hasActiveSession
                              ? null
                              : () async {
                                  final s = await c.stopAndSave();
                                  if (s != null && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Saved ${formatHours(s.durationSeconds)} of ${s.subjectName}'),
                                      ),
                                    );
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ---------------------------------------------------- focus mode
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: c.focusEnabled,
                  onChanged: c.setFocusEnabled,
                  secondary: const Icon(Icons.do_not_disturb_on_outlined),
                  title: const Text('Focus Mode'),
                  subtitle: const Text(
                      'Silence calls + notifications automatically while the timer runs'),
                ),
                if (c.focusEnabled) ...[
                  const Divider(height: 1),
                  for (final level in [
                    FocusLevel.alarmsOnly,
                    FocusLevel.priorityOnly,
                    FocusLevel.totalSilence
                  ])
                    RadioListTile<FocusLevel>(
                      value: level,
                      groupValue: c.focusLevel,
                      onChanged: (v) => v == null ? null : c.setFocusLevel(v),
                      title: Text(level.label),
                      subtitle: Text(level.description,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  if (!c.dndGranted)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Text(
                            'Android requires you to grant "Do Not Disturb access" once. '
                            'No app can block calls without it.',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonal(
                            onPressed: () => FocusModeService.instance
                                .openPermissionSettings(),
                            child: const Text('Grant DND access'),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addSubjectDialog(BuildContext context, StudyController c) async {
    final ctrl = TextEditingController();
    const palette = [
      Color(0xFF6366F1),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
      Color(0xFFEF4444),
      Color(0xFF06B6D4),
      Color(0xFFA855F7),
    ];
    var color = palette.first;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('New subject'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'e.g. Economics'),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                children: [
                  for (final p in palette)
                    GestureDetector(
                      onTap: () => setState(() => color = p),
                      child: CircleAvatar(
                        backgroundColor: p,
                        radius: 16,
                        child: color == p
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                c.addSubject(ctrl.text, color);
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}
