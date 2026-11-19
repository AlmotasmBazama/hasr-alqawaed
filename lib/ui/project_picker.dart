import 'package:flutter/material.dart';

import '../project/models.dart';
import 'app_theme.dart';

class ProjectPicker extends StatefulWidget {
  const ProjectPicker({
    super.key,
    required this.projects,
    required this.selectedId,
  });

  final List<Project> projects;
  final String selectedId;

  @override
  State<ProjectPicker> createState() => _ProjectPickerState();
}

class _ProjectPickerState extends State<ProjectPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final matches = widget.projects.where(
      (p) => '${p.name} ${p.location}'.toLowerCase().contains(
        _query.trim().toLowerCase(),
      ),
    );
    return SafeArea(
      child: AnimatedPadding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        duration: const Duration(milliseconds: 150),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .78,
          ),
          child: ListView(
            shrinkWrap: true,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            children: [
              const Text(
                'المشاريع المحفوظة',
                style: TextStyle(
                  fontSize: 22,
                  color: forestInk,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (widget.projects.length >= 5)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'ابحث باسم المشروع أو الموقع',
                    ),
                  ),
                ),
              if (matches.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد مشاريع تطابق البحث'),
                ),
              for (final project in matches)
                ListTile(
                  selected: project.id == widget.selectedId,
                  selectedTileColor: const Color(0xFFEAF4EA),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(
                    project.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    [
                      if (project.location.isNotEmpty) project.location,
                      project.date,
                      if (project.isExample) 'مشروع توضيحي',
                    ].join(' • '),
                  ),
                  trailing: project.id == widget.selectedId
                      ? const Icon(Icons.check_circle, size: 20)
                      : null,
                  onTap: () => Navigator.pop(context, project.id),
                ),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const ValueKey('new_project'),
                onPressed: () => Navigator.pop(context, '__new'),
                icon: const Icon(Icons.add_rounded),
                label: const Text('إنشاء مشروع جديد'),
              ),
              const SizedBox(height: 8),
              ListTile(
                key: const ValueKey('example_project'),
                leading: const Icon(Icons.description_outlined),
                title: const Text('إضافة «مثال الأوراق»'),
                subtitle: const Text('المثال السابق دون السقف'),
                onTap: () => Navigator.pop(context, '__example'),
              ),
              ListTile(
                key: const ValueKey('full_example_project'),
                leading: const Icon(Icons.description_outlined),
                title: const Text('إضافة «مثال الأوراق بالسقف»'),
                subtitle: const Text(
                  'مثال مستقل يشمل مساحة السقف وأطوال الكمرات',
                ),
                onTap: () => Navigator.pop(context, '__full_example'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
