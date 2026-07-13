import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/user.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';

/// Admin-only: view staff/admin accounts and create new ones with a role
/// (permission level).
class ManageStaffScreen extends StatefulWidget {
  const ManageStaffScreen({super.key});

  @override
  State<ManageStaffScreen> createState() => _ManageStaffScreenState();
}

class _ManageStaffScreenState extends State<ManageStaffScreen> {
  AppUser? _pendingDelete;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final staff = auth.staffUsers;

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        final pending = _pendingDelete;
        if (pending == null) return;
        _pendingDelete = null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.errorMessage ?? '${pending.name} deleted'),
          ),
        );
      },
      child: Scaffold(
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: staff.length,
          itemBuilder: (_, i) {
            final u = staff[i];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: u.role == UserRole.admin
                      ? Colors.deepPurple.shade100
                      : Colors.blue.shade100,
                  child: Icon(
                    u.role == UserRole.admin
                        ? Icons.admin_panel_settings
                        : Icons.badge,
                  ),
                ),
                title: Text(u.name),
                subtitle: Text('${u.email}\n${u.phone}'),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(label: Text(u.role.label)),
                    IconButton(
                      icon:
                          const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Delete account',
                      onPressed: () => _confirmDelete(context, u),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddStaff(context),
          icon: const Icon(Icons.person_add),
          label: const Text('Add staff'),
        ),
      ),
    );
  }

  void _showAddStaff(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddStaffSheet(),
    );
  }

  void _confirmDelete(BuildContext context, AppUser user) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account'),
        content: Text('Delete ${user.name}\'s account? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _pendingDelete = user;
              context.read<AuthBloc>().add(AuthStaffDeleteRequested(user.id));
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _AddStaffSheet extends StatefulWidget {
  const _AddStaffSheet();

  @override
  State<_AddStaffSheet> createState() => _AddStaffSheetState();
}

class _AddStaffSheetState extends State<_AddStaffSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  UserRole _role = UserRole.staff;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthBloc>().add(AuthStaffCreateRequested(
          name: _name.text,
          email: _email.text,
          phone: _phone.text,
          password: _password.text,
          role: _role,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state.errorMessage != null) {
          setState(() => _error = state.errorMessage);
          return;
        }
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_role.label} account created')),
        );
      },
      child: Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'New staff account',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) =>
                  (v == null || !v.contains('@')) ? 'Invalid email' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
              validator: (v) =>
                  (v == null || v.trim().length < 8) ? 'Invalid phone' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (v) =>
                  (v == null || v.length < 6) ? 'Min 6 characters' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<UserRole>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Permission level'),
              items: const [
                DropdownMenuItem(value: UserRole.staff, child: Text('Staff')),
                DropdownMenuItem(
                  value: UserRole.admin,
                  child: Text('Administrator'),
                ),
              ],
              onChanged: (v) => setState(() => _role = v ?? UserRole.staff),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submit,
              child: const Text('Create account'),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
