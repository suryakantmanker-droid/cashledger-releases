import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../providers/superadmin_provider.dart';

class CreateBusinessScreen extends ConsumerStatefulWidget {
  const CreateBusinessScreen({super.key});

  @override
  ConsumerState<CreateBusinessScreen> createState() =>
      _CreateBusinessScreenState();
}

class _CreateBusinessScreenState
    extends ConsumerState<CreateBusinessScreen> {
  final _formKey = GlobalKey<FormState>();

  final _bizNameCtrl    = TextEditingController();
  final _phoneCtrl      = TextEditingController();
  final _addressCtrl    = TextEditingController();
  final _cityCtrl       = TextEditingController();
  final _districtCtrl   = TextEditingController();
  final _stateCtrl      = TextEditingController();
  final _adminNameCtrl  = TextEditingController();
  final _emailCtrl      = TextEditingController();
  final _passwordCtrl   = TextEditingController();
  final _customDaysCtrl = TextEditingController();

  bool _obscurePassword = true;
  int _demoDays = 14;
  bool _useCustomDays = false;
  String _selectedPlan = 'starter';

  static const _presets = [7, 14, 30];
  static const _plans   = ['starter', 'professional', 'enterprise'];

  @override
  void dispose() {
    _bizNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _districtCtrl.dispose();
    _stateCtrl.dispose();
    _adminNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _customDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final days = _useCustomDays
        ? int.tryParse(_customDaysCtrl.text.trim()) ?? 14
        : _demoDays;

    final success = await ref.read(createBusinessProvider.notifier).create(
      businessName:  _bizNameCtrl.text,
      adminName:     _adminNameCtrl.text,
      adminEmail:    _emailCtrl.text,
      adminPassword: _passwordCtrl.text,
      demoDays:      days,
      phone:         _phoneCtrl.text,
      plan:          _selectedPlan,
      address:       _addressCtrl.text,
      city:          _cityCtrl.text,
      district:      _districtCtrl.text,
      stateName:     _stateCtrl.text,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Business "${_bizNameCtrl.text}" created! Demo: $days days'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go(RouteConstants.superadminDashboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(createBusinessProvider);
    final theme = Theme.of(context);

    ref.listen<CreateBusinessState>(createBusinessProvider, (_, next) {
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: theme.colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.read(createBusinessProvider.notifier).clearMessages();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Create New Business')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Business Info ────────────────────────────────────────────
              _SectionHeader(icon: Icons.business, label: 'Business Details'),
              const SizedBox(height: 12),

              TextFormField(
                controller: _bizNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Business Name *',
                  hintText: 'e.g. Sharma Traders Pvt Ltd',
                  prefixIcon: Icon(Icons.store_outlined),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Business name is required';
                  if (v.trim().length < 3) return 'Minimum 3 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Business Phone',
                  hintText: 'e.g. +91 9876543210',
                  prefixIcon: Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: _selectedPlan,
                decoration: const InputDecoration(
                  labelText: 'Plan',
                  prefixIcon: Icon(Icons.workspace_premium_outlined),
                  border: OutlineInputBorder(),
                ),
                items: _plans
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p[0].toUpperCase() + p.substring(1)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedPlan = v ?? _selectedPlan),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _addressCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Street Address',
                  hintText: 'Office / Building / Street',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _districtCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'District',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _stateCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'State',
                  prefixIcon: Icon(Icons.flag_outlined),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 24),

              // ── Trial Period ─────────────────────────────────────────────
              _SectionHeader(
                icon: Icons.timer_outlined,
                label: 'Trial / Demo Period',
                subtitle: 'Business will be blocked after demo ends.',
              ),
              const SizedBox(height: 12),

              Wrap(
                spacing: 8,
                children: [
                  ..._presets.map((days) {
                    final selected = !_useCustomDays && _demoDays == days;
                    return ChoiceChip(
                      label: Text('$days days'),
                      selected: selected,
                      selectedColor: Theme.of(context).colorScheme.primary,
                      labelStyle: TextStyle(
                        color: selected
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      onSelected: (_) => setState(() {
                        _demoDays = days;
                        _useCustomDays = false;
                      }),
                    );
                  }),
                  ChoiceChip(
                    label: const Text('Custom'),
                    selected: _useCustomDays,
                    selectedColor: Theme.of(context).colorScheme.primary,
                    labelStyle: TextStyle(
                      color: _useCustomDays
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: _useCustomDays ? FontWeight.w600 : FontWeight.normal,
                    ),
                    onSelected: (_) => setState(() => _useCustomDays = true),
                  ),
                ],
              ),

              if (_useCustomDays) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customDaysCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Number of days *',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                    border: OutlineInputBorder(),
                    suffixText: 'days',
                  ),
                  validator: (v) {
                    if (!_useCustomDays) return null;
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 1) return 'Enter a valid number of days';
                    if (n > 365) return 'Maximum 365 days';
                    return null;
                  },
                ),
              ],

              const SizedBox(height: 8),
              Text(
                _useCustomDays
                    ? 'Custom demo period — enter the number of days above.'
                    : 'Demo expires $_demoDays days after creation.',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),

              const SizedBox(height: 28),

              // ── Admin account ─────────────────────────────────────────────
              _SectionHeader(
                icon: Icons.admin_panel_settings_outlined,
                label: 'Business Admin Account',
                subtitle:
                    'This person will manage the business. Share these credentials with the client.',
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _adminNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Admin Full Name *',
                  hintText: 'e.g. Rajesh Sharma',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Admin Email *',
                  hintText: 'e.g. admin@sharma-traders.com',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Email is required';
                  final emailRe = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                  if (!emailRe.hasMatch(v.trim())) return 'Invalid email';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Admin Password *',
                  hintText: 'Min. 8 characters',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  if (v.length < 8) return 'Minimum 8 characters';
                  return null;
                },
              ),

              const SizedBox(height: 32),

              FilledButton(
                onPressed: state.isLoading ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
                child: state.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Create Business & Admin Account',
                        style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;

  const _SectionHeader({
    required this.icon,
    required this.label,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey[600])),
        ],
      ],
    );
  }
}
