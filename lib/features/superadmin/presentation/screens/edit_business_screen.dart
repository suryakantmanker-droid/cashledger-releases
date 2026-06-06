import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../data/datasources/superadmin_datasource.dart';
import '../providers/superadmin_provider.dart';

class EditBusinessScreen extends ConsumerStatefulWidget {
  final BusinessOverview business;
  const EditBusinessScreen({super.key, required this.business});

  @override
  ConsumerState<EditBusinessScreen> createState() => _EditBusinessScreenState();
}

class _EditBusinessScreenState extends ConsumerState<EditBusinessScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _maxEmpCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _districtCtrl;
  late final TextEditingController _stateCtrl;
  late final TextEditingController _ownerNameCtrl;
  late final TextEditingController _ownerEmailCtrl;
  late String _selectedPlan;

  static const _plans = ['starter', 'professional', 'enterprise'];

  @override
  void initState() {
    super.initState();
    final b = widget.business;
    _nameCtrl      = TextEditingController(text: b.name);
    _phoneCtrl     = TextEditingController(text: b.phone      ?? '');
    _maxEmpCtrl    = TextEditingController(text: '${b.maxEmployees}');
    _addressCtrl   = TextEditingController(text: b.address    ?? '');
    _cityCtrl      = TextEditingController(text: b.city       ?? '');
    _districtCtrl  = TextEditingController(text: b.district   ?? '');
    _stateCtrl     = TextEditingController(text: b.state      ?? '');
    _ownerNameCtrl = TextEditingController(text: b.ownerName  ?? '');
    _ownerEmailCtrl= TextEditingController(text: b.ownerEmail ?? '');
    _selectedPlan  = _plans.contains(b.plan) ? b.plan : 'starter';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _maxEmpCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _districtCtrl.dispose();
    _stateCtrl.dispose();
    _ownerNameCtrl.dispose();
    _ownerEmailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subState = ref.watch(subscriptionProvider);

    ref.listen<SubscriptionState>(subscriptionProvider, (_, next) {
      if (!context.mounted) return;
      if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.successMessage!),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            ref.read(subscriptionProvider.notifier).clearMessages();
            context.pop();
          }
        });
      }
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.errorMessage!),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) ref.read(subscriptionProvider.notifier).clearMessages();
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Business'),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel('Business Details'),
              SizedBox(height: 12.h),

              AppTextField(
                label: 'Business Name *',
                hint: 'Enter business name',
                controller: _nameCtrl,
                prefixIcon: const Icon(Icons.store_outlined),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Name is required';
                  if (v.trim().length < 3) return 'Minimum 3 characters';
                  return null;
                },
              ),
              SizedBox(height: 14.h),

              AppTextField(
                label: 'Phone Number',
                hint: '+91 98765 43210',
                controller: _phoneCtrl,
                prefixIcon: const Icon(Icons.phone_outlined),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
              ),
              SizedBox(height: 14.h),

              // Plan dropdown
              _DropdownLabel('Plan'),
              SizedBox(height: 6.h),
              DropdownButtonFormField<String>(
                value: _selectedPlan,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.workspace_premium_outlined),
                ),
                items: _plans
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p[0].toUpperCase() + p.substring(1)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedPlan = v ?? _selectedPlan),
              ),
              SizedBox(height: 14.h),

              AppTextField(
                label: 'Max Employees',
                hint: '15',
                controller: _maxEmpCtrl,
                prefixIcon: const Icon(Icons.group_outlined),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 1) return 'Enter a valid number';
                  if (n > 10000) return 'Maximum 10,000';
                  return null;
                },
              ),
              SizedBox(height: 24.h),

              _SectionLabel('Address'),
              SizedBox(height: 12.h),

              AppTextField(
                label: 'Street Address',
                hint: 'House / Flat / Street',
                controller: _addressCtrl,
                prefixIcon: const Icon(Icons.location_on_outlined),
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
              ),
              SizedBox(height: 14.h),

              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'City',
                      hint: 'City',
                      controller: _cityCtrl,
                      prefixIcon: const Icon(Icons.location_city_outlined),
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppTextField(
                      label: 'District',
                      hint: 'District',
                      controller: _districtCtrl,
                      prefixIcon: const Icon(Icons.map_outlined),
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14.h),

              AppTextField(
                label: 'State',
                hint: 'State',
                controller: _stateCtrl,
                prefixIcon: const Icon(Icons.flag_outlined),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
              ),
              SizedBox(height: 24.h),

              if (widget.business.ownerUid != null) ...[
                _SectionLabel('Owner / Admin Details'),
                SizedBox(height: 12.h),

                AppTextField(
                  label: 'Owner Name',
                  hint: 'Full name',
                  controller: _ownerNameCtrl,
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
                SizedBox(height: 14.h),

                AppTextField(
                  label: 'Owner Email',
                  hint: 'owner@example.com',
                  controller: _ownerEmailCtrl,
                  prefixIcon: const Icon(Icons.email_outlined),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final re = RegExp(r'^[\w._%+-]+@[\w.-]+\.[a-zA-Z]{2,}$');
                    if (!re.hasMatch(v.trim())) return 'Enter a valid email';
                    return null;
                  },
                ),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 13, color: Colors.orange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Email change updates app records only, not login credentials.',
                        style: TextStyle(fontSize: 11.sp, color: Colors.orange.shade700),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24.h),
              ],

              AppButton(
                label: 'Save Changes',
                onPressed: subState.isLoading ? null : _save,
                isLoading: subState.isLoading,
                prefixIcon: Icons.save_rounded,
              ),
              SizedBox(height: 24.h),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    await ref.read(subscriptionProvider.notifier).updateBusiness(
      widget.business.id,
      name:         _nameCtrl.text.trim(),
      phone:        _phoneCtrl.text.trim(),
      plan:         _selectedPlan,
      maxEmployees: int.tryParse(_maxEmpCtrl.text.trim()) ?? widget.business.maxEmployees,
      address:      _addressCtrl.text.trim(),
      city:         _cityCtrl.text.trim(),
      district:     _districtCtrl.text.trim(),
      stateName:    _stateCtrl.text.trim(),
      ownerName:    _ownerNameCtrl.text.trim().isEmpty ? null : _ownerNameCtrl.text.trim(),
      ownerEmail:   _ownerEmailCtrl.text.trim().isEmpty ? null : _ownerEmailCtrl.text.trim(),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 15.sp,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
    );
  }
}

class _DropdownLabel extends StatelessWidget {
  final String label;
  const _DropdownLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 13.sp,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
      ),
    );
  }
}
