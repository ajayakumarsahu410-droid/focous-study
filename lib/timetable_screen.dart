import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/study_controller.dart';

const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

class TimetableScreen extends StatelessWidget {
  const TimetableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudyController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Daily timetable')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editSlot(context, c, null),
        icon: const Icon(Icons.add),
        label: const Text('Add slot'),
      ),
      body: c.slots.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No slots yet.\n\nAdd one like "Economics 08:00 - 11:00" and the app '
                  'will alarm you 5 minutes in if you have not started studying.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: c.slots.length,
              itemBuilder: (_, i) {
                final s = c.slots[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    onTap: () => _editSlot(context, c, s),
                    title: Text(s.subjectName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${s.startTod.format(context)} - ${s.endTod.format(context)}'
                      '   •   ${s.durationMinutes ~/ 60}h ${s.durationMinutes % 60}m'
                      '\nAlarm ${s.graceMinutes} min after start   •   '
                      '${[for (var d = 0; d < 7; d++) if (s.days[d]) _dayLabels[d]].join(" ")}',
                    ),
                    isThreeLine: true,
                    trailing: Switch(
                      value: s.enabled,
                      onChanged: (v) => c.saveSlot(s.copyWith(enabled: v)),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _editSlot(
      BuildContext context, StudyController c, TimetableSlot? existing) async {
    var subject = existing?.subjectName ??
        (c.subjects.isNotEmpty ? c.subjects.first.name : 'Study');
    var start = existing?.startMinute ?? 8 * 60;
    var end = existing?.endMinute ?? 11 * 60;
    var days = List<bool>.from(existing?.days ?? List.filled(7, true));
    var grace = existing?.graceMinutes ?? 5;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing == null ? 'New slot' : 'Edit slot',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: subject,
                decoration: const InputDecoration(labelText: 'Subject'),
                items: [
                  for (final s in c.subjects)
                    DropdownMenuItem(value: s.name, child: Text(s.name))
                ],
                onChanged: (v) => setState(() => subject = v ?? subject),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _TimeField(
                      label: 'Starts',
                      minutes: start,
                      onPick: (m) => setState(() => start = m),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimeField(
                      label: 'Ends',
                      minutes: end,
                      onPick: (m) => setState(() => end = m),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Repeat on'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (var d = 0; d < 7; d++)
                    FilterChip(
                      label: Text(_dayLabels[d]),
                      selected: days[d],
                      onSelected: (v) => setState(() => days[d] = v),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Alarm if not started within $grace min'),
              Slider(
                value: grace.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                label: '$grace min',
                onChanged: (v) => setState(() => grace = v.round()),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (existing != null)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                      onPressed: () {
                        c.deleteSlot(existing);
                        Navigator.pop(ctx);
                      },
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      c.saveSlot(TimetableSlot(
                        id: existing?.id,
                        subjectName: subject,
                        startMinute: start,
                        endMinute: end,
                        days: days,
                        graceMinutes: grace,
                        enabled: existing?.enabled ?? true,
                      ));
                      Navigator.pop(ctx);
                    },
                    child: const Text('Save & arm alarm'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.minutes,
    required this.onPick,
  });

  final String label;
  final int minutes;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final tod = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: tod);
        if (picked != null) onPick(picked.hour * 60 + picked.minute);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(tod.format(context)),
      ),
    );
  }
}
