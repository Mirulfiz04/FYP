import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../viewmodels/profile_view_model.dart';
import '../widgets/ui_kit.dart';
import 'edit_profile_screen.dart';

const Color _accent = Color(0xFF6A5AE0);

/// Read view of the user's personal details, with an Edit action.
class PersonalInformationScreen extends StatelessWidget {
  final ProfileViewModel vm;
  const PersonalInformationScreen({super.key, required this.vm});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal Information'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: _accent),
            tooltip: 'Edit',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EditProfileScreen(vm: vm))),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          final p = vm.profile;
          if (p == null) {
            return const Center(child: CircularProgressIndicator(color: _accent));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                child: Column(
                  children: [
                    _row('Full name', p.name),
                    _row('Display name', p.displayName),
                    _row('Email address', p.email),
                    _row('Age group', p.ageGroup),
                    _row('Gender', p.gender),
                    _row('User category',
                        p.userCategory == 'Other' && p.userCategoryOther != null
                            ? 'Other · ${p.userCategoryOther}'
                            : p.userCategory),
                    _row('Monitoring goal', p.monitoringGoal),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => EditProfileScreen(vm: vm))),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Information'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(color: MedsColors.muted, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value?.trim().isNotEmpty == true ? value!.trim() : 'Not set',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: value?.trim().isNotEmpty == true
                    ? null
                    : MedsColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
