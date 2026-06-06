import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/employee_provider.dart';
import '../../../departments/presentation/widgets/department_dropdown.dart';

class AddEmployeeScreen extends ConsumerStatefulWidget {
  final String? employeeId;
  const AddEmployeeScreen({super.key, this.employeeId});

  bool get isEditing => employeeId != null;

  @override
  ConsumerState<AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends ConsumerState<AddEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _addressCtrl  = TextEditingController();
  final _cityCtrl     = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _stateCtrl    = TextEditingController();
  String? _selectedDepartment;
  String? _deptError;
  bool _obscurePassword = true;
  bool _initialized = false;

  File? _pickedImage;
  String? _existingImageUrl;
  bool _uploadingImage = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _districtCtrl.dispose();
    _stateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _pickedImage = File(picked.path));
  }

  Future<String?> _uploadImageIfPicked(String employeeId) async {
    if (_pickedImage == null) return null;
    setState(() => _uploadingImage = true);
    try {
      final url = await StorageService().uploadProfileImage(
        file: _pickedImage!,
        userId: employeeId,
      );
      return url;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Photo upload failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
      return null;
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final employeeState = ref.watch(employeeNotifierProvider);
    final currentUser = ref.watch(currentUserProvider).valueOrNull;

    // ── Pre-fill form when editing ─────────────────────────────────────────
    if (widget.isEditing && !_initialized) {
      ref.watch(employeeByIdProvider(widget.employeeId!)).whenData((emp) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_initialized) {
            setState(() {
              _nameCtrl.text     = emp.name;
              _emailCtrl.text    = emp.email;
              _phoneCtrl.text    = emp.phone;
              _addressCtrl.text  = emp.address  ?? '';
              _cityCtrl.text     = emp.city     ?? '';
              _districtCtrl.text = emp.district ?? '';
              _stateCtrl.text    = emp.state    ?? '';
              _selectedDepartment = emp.department.isNotEmpty
                  ? emp.department
                  : null;
              _existingImageUrl = emp.profileImageUrl;
              _initialized = true;
            });
          }
        });
      });
    }

    // ── Success / Error listener ───────────────────────────────────────────
    ref.listen<EmployeeState>(employeeNotifierProvider, (_, next) {
      if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.successMessage!),
          backgroundColor: AppColors.success,
        ));
        ref.read(employeeNotifierProvider.notifier).clearMessages();
        context.pop();
      }
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.errorMessage!),
          backgroundColor: AppColors.error,
        ));
        ref.read(employeeNotifierProvider.notifier).clearMessages();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Employee' : 'Add Employee'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Profile Image ──────────────────────────────────────────────
              Center(
                child: Stack(
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: CircleAvatar(
                        radius: 44.r,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                        backgroundImage: _pickedImage != null
                            ? FileImage(_pickedImage!)
                            : (_existingImageUrl?.isNotEmpty == true
                                ? NetworkImage(_existingImageUrl!)
                                : null) as ImageProvider?,
                        child: (_pickedImage == null && _existingImageUrl == null)
                            ? Icon(
                                Icons.person_rounded,
                                size: 44.sp,
                                color: AppColors.primary.withValues(alpha: 0.5),
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          padding: EdgeInsets.all(6.w),
                          decoration: BoxDecoration(
                            color: _uploadingImage
                                ? AppColors.textSecondary
                                : AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: _uploadingImage
                              ? SizedBox(
                                  width: 14.sp,
                                  height: 14.sp,
                                  child: const CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(Icons.camera_alt_rounded,
                                  color: Colors.white, size: 14.sp),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_pickedImage != null)
                Padding(
                  padding: EdgeInsets.only(top: 6.h),
                  child: Center(
                    child: Text(
                      'Photo selected — will upload on save',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11.sp,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ),
              SizedBox(height: 24.h),

              _SectionLabel('Personal Information'),
              SizedBox(height: 12.h),

              AppTextField(
                label: 'Full Name',
                hint: 'Enter employee full name',
                controller: _nameCtrl,
                validator: (v) => AppValidators.name(v, fieldName: 'Name'),
                prefixIcon: const Icon(Icons.person_outline_rounded),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
              ),
              SizedBox(height: 14.h),

              AppTextField(
                label: 'Email Address',
                hint: 'Enter work email',
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                validator: widget.isEditing ? null : AppValidators.email,
                prefixIcon: const Icon(Icons.email_outlined),
                enabled: !widget.isEditing || (currentUser?.isAdmin ?? false),
                textInputAction: TextInputAction.next,
              ),
              SizedBox(height: 14.h),

              AppTextField(
                label: 'Mobile Number',
                hint: '10-digit mobile number',
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                validator: AppValidators.phone,
                prefixIcon: const Icon(Icons.phone_outlined),
                textInputAction: TextInputAction.next,
              ),
              SizedBox(height: 14.h),

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
                  SizedBox(width: 10.w),
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
                textInputAction: TextInputAction.next,
              ),
              SizedBox(height: 14.h),

              // Department Dropdown
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Department',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.7),
                    ),
                  ),
                  SizedBox(height: 6.h),
                  DepartmentDropdown(
                    value: _selectedDepartment,
                    onChanged: (v) => setState(() => _selectedDepartment = v),
                    errorText: _deptError,
                  ),
                ],
              ),
              SizedBox(height: 20.h),

              if (!widget.isEditing) ...[
                _SectionLabel('Account Credentials'),
                SizedBox(height: 12.h),
                AppTextField(
                  label: 'Password',
                  hint: 'Set a password (min 6 characters)',
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  validator: AppValidators.password,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                SizedBox(height: 8.h),
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16.sp, color: AppColors.info),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          'An email & password will be created for this employee to login.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11.sp,
                            color: AppColors.info,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: 28.h),
              AppButton(
                label: widget.isEditing ? 'Update Employee' : 'Add Employee',
                onPressed: () => _submit(currentUser),
                isLoading: employeeState.isLoading || _uploadingImage,
                prefixIcon: widget.isEditing
                    ? Icons.save_rounded
                    : Icons.person_add_rounded,
              ),
              SizedBox(height: 24.h),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit(UserEntity? currentUser) async {
    // Validate department separately (not inside FormField)
    if (_selectedDepartment == null) {
      setState(() => _deptError = 'Please select a department');
      return;
    }
    setState(() => _deptError = null);
    if (!_formKey.currentState!.validate()) return;

    if (widget.isEditing) {
      // 1. Upload new photo if selected
      String? newPhotoUrl;
      if (_pickedImage != null) {
        newPhotoUrl = await _uploadImageIfPicked(widget.employeeId!);
      }

      // 2. Update employee data
      final updateData = <String, dynamic>{
        'name':       _nameCtrl.text.trim(),
        'phone':      _phoneCtrl.text.trim(),
        'department': _selectedDepartment,
        'address':    _addressCtrl.text.trim(),
        'city':       _cityCtrl.text.trim(),
        'district':   _districtCtrl.text.trim(),
        'state':      _stateCtrl.text.trim(),
      };
      if (currentUser?.isAdmin == true) {
        updateData['email'] = _emailCtrl.text.trim();
      }
      if (newPhotoUrl != null) updateData['profileImageUrl'] = newPhotoUrl;

      await ref
          .read(employeeNotifierProvider.notifier)
          .updateEmployee(widget.employeeId!, updateData);
    } else {
      // 1. Create employee account
      final uid = await ref.read(employeeNotifierProvider.notifier).addEmployee(
        name:       _nameCtrl.text.trim(),
        email:      _emailCtrl.text.trim(),
        phone:      _phoneCtrl.text.trim(),
        department: _selectedDepartment!,
        password:   _passwordCtrl.text,
        createdBy:  currentUser?.uid ?? '',
        address:    _addressCtrl.text.trim(),
        city:       _cityCtrl.text.trim(),
        district:   _districtCtrl.text.trim(),
        stateName:  _stateCtrl.text.trim(),
      );

      // 2. Upload photo if selected (non-blocking — error shown as snackbar)
      if (uid != null && _pickedImage != null) {
        final photoUrl = await _uploadImageIfPicked(uid);
        if (photoUrl != null) {
          await ref.read(employeeNotifierProvider.notifier).updateEmployee(
            uid,
            {'profileImageUrl': photoUrl},
          );
        }
      }
    }
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
        fontSize: 13.sp,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
        letterSpacing: 0.5,
      ),
    );
  }
}
