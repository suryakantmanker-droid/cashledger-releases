import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/expense_provider.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  final String? expenseId;
  const AddExpenseScreen({super.key, this.expenseId});

  bool get isEditing => expenseId != null;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _vendorCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  String _selectedCategory = AppConstants.expenseCategories.first;
  String _selectedPaymentMethod = AppConstants.paymentModes.first;
  DateTime _selectedDate = DateTime.now();
  final List<File> _billFiles = [];
  final _imagePicker = ImagePicker();
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.isEditing && !_prefilled) {
      final expenseAsync = ref.read(expenseByIdProvider(widget.expenseId!));
      expenseAsync.whenData((expense) {
        if (!mounted) return;
        setState(() {
          _titleCtrl.text        = expense.title;
          _amountCtrl.text       = expense.amount.toStringAsFixed(2);
          _vendorCtrl.text       = expense.vendorName ?? '';
          _descriptionCtrl.text  = expense.description ?? '';
          _selectedCategory      = AppConstants.expenseCategories.contains(expense.category)
              ? expense.category
              : AppConstants.expenseCategories.first;
          _selectedPaymentMethod = AppConstants.paymentModes.contains(expense.paymentMethod)
              ? expense.paymentMethod
              : AppConstants.paymentModes.first;
          _selectedDate          = expense.expenseDate;
          _prefilled             = true;
        });
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _vendorCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expenseState = ref.watch(expenseNotifierProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final businessId = ref.watch(activeBusinessIdProvider);
    final isBusinessReady = businessId != null;
    final businessCtx = ref.watch(businessContextProvider);
    final isLoadingBusiness = !isBusinessReady && (businessCtx.isIdle || businessCtx.isLoading);

    ref.listen<ExpenseState>(expenseNotifierProvider, (_, next) {
      if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.successMessage!), backgroundColor: AppColors.success),
        );
        context.pop();
      }
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!), backgroundColor: AppColors.error),
        );
        ref.read(expenseNotifierProvider.notifier).clearMessages();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Expense' : 'Add Expense'),
        actions: [
          TextButton(
            onPressed: (expenseState.isLoading || !isBusinessReady)
                ? null
                : () => _submit(user, isDraft: true),
            child: const Text('Save Draft'),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Loading banner — shown only while business context is actively fetching
                  if (isLoadingBusiness)
                    Container(
                      width: double.infinity,
                      margin: EdgeInsets.only(bottom: 12.h),
                      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14.sp,
                            height: 14.sp,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: Text(
                              'Setting up your account, please wait…',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12.sp,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  AppTextField(
                    label: 'Expense Title',
                    hint: 'E.g. Hotel booking, fuel, materials...',
                    controller: _titleCtrl,
                    validator: (v) => AppValidators.required(v, fieldName: 'Title'),
                    prefixIcon: const Icon(Icons.receipt_long_rounded),
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                  ),
                  SizedBox(height: 14.h),

                  AppTextField(
                    label: 'Amount (₹)',
                    hint: '0.00',
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    validator: AppValidators.amount,
                    prefixIcon: const Icon(Icons.currency_rupee_rounded),
                    textInputAction: TextInputAction.next,
                  ),
                  SizedBox(height: 14.h),

                  // Category
                  _DropdownField<String>(
                    label: 'Category',
                    icon: Icons.category_rounded,
                    value: _selectedCategory,
                    items: AppConstants.expenseCategories,
                    onChanged: (v) => setState(() => _selectedCategory = v!),
                  ),
                  SizedBox(height: 14.h),

                  AppTextField(
                    label: 'Vendor / Shop Name',
                    hint: 'Enter vendor name',
                    controller: _vendorCtrl,
                    prefixIcon: const Icon(Icons.store_rounded),
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                  ),
                  SizedBox(height: 14.h),

                  // Payment Method
                  _DropdownField<String>(
                    label: 'Payment Method',
                    icon: Icons.payment_rounded,
                    value: _selectedPaymentMethod,
                    items: AppConstants.paymentModes,
                    onChanged: (v) => setState(() => _selectedPaymentMethod = v!),
                  ),
                  SizedBox(height: 14.h),

                  // Date
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) setState(() => _selectedDate = date);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded),
                          SizedBox(width: 12.w),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Expense Date',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11.sp,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              Text(
                                AppUtils.formatDate(_selectedDate),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 14.h),

                  AppTextField(
                    label: 'Description (Optional)',
                    hint: 'Add details about this expense',
                    controller: _descriptionCtrl,
                    maxLines: 3,
                    prefixIcon: const Icon(Icons.notes_rounded),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  SizedBox(height: 20.h),

                  // Bill Upload
                  _BillUploadSection(
                    files: _billFiles,
                    onAddImage: _pickImage,
                    onAddPdf: _pickPdf,
                    onRemove: (i) => setState(() => _billFiles.removeAt(i)),
                  ),
                  SizedBox(height: 28.h),

                  // Upload Progress
                  if (expenseState.isUploading) ...[
                    LinearProgressIndicator(value: expenseState.uploadProgress),
                    SizedBox(height: 8.h),
                    Text(
                      'Uploading bills... ${(expenseState.uploadProgress * 100).toInt()}%',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.sp,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(height: 12.h),
                  ],

                  AppButton(
                    label: 'Submit Expense',
                    onPressed: (expenseState.isLoading || !isBusinessReady)
                        ? null
                        : () => _submit(user, isDraft: false),
                    isLoading: expenseState.isLoading,
                    prefixIcon: Icons.send_rounded,
                  ),
                  SizedBox(height: 24.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final status = await Permission.photos.request();
    if (!status.isGranted) return;

    final source = await _showImageSourceDialog();
    if (source == null) return;

    final xFile = await _imagePicker.pickImage(source: source, imageQuality: 85);
    if (xFile != null) {
      setState(() => _billFiles.add(File(xFile.path)));
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result?.files.single.path != null) {
      setState(() => _billFiles.add(File(result!.files.single.path!)));
    }
  }

  Future<void> _submit(dynamic streamUser, {required bool isDraft}) async {
    // Use auth notifier user as fallback — it's available immediately after
    // login even while the Supabase stream is still initializing.
    final user = streamUser ?? ref.read(authNotifierProvider).user;

    if (!isDraft && !_formKey.currentState!.validate()) return;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired. Please log in again.')),
      );
      return;
    }

    final data = {
      'title': _titleCtrl.text.trim(),
      'amount': double.tryParse(_amountCtrl.text) ?? 0,
      'category': _selectedCategory,
      'vendorName': _vendorCtrl.text.trim(),
      'description': _descriptionCtrl.text.trim(),
      'expenseDate': _selectedDate,
      'paymentMethod': _selectedPaymentMethod,
      'submittedBy': user.uid,
      'submittedByName': user.name,
    };

    if (widget.isEditing) {
      // Update existing draft
      await ref.read(expenseNotifierProvider.notifier).updateDraft(
        id: widget.expenseId!,
        data: {
          ...data,
          'status': isDraft ? AppConstants.statusDraft : AppConstants.statusPending,
        },
        billFiles: isDraft ? [] : _billFiles,
        submittedBy: user.uid,
      );
    } else if (isDraft) {
      await ref.read(expenseNotifierProvider.notifier).saveDraft(data);
    } else {
      await ref.read(expenseNotifierProvider.notifier).submitExpense(
        data: data,
        billFiles: _billFiles,
        submittedBy: user.uid,
      );
    }
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final T value;
  final List<T> items;
  final void Function(T?) onChanged;

  const _DropdownField({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13.sp,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        SizedBox(height: 6.h),
        DropdownButtonFormField<T>(
          initialValue: value,
          decoration: InputDecoration(prefixIcon: Icon(icon)),
          items: items
              .map((i) => DropdownMenuItem<T>(value: i, child: Text(i.toString())))
              .toList(),
          onChanged: onChanged,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14.sp,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _BillUploadSection extends StatelessWidget {
  final List<File> files;
  final VoidCallback onAddImage;
  final VoidCallback onAddPdf;
  final void Function(int) onRemove;

  const _BillUploadSection({
    required this.files,
    required this.onAddImage,
    required this.onAddPdf,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Attach Bills',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onAddImage,
                  icon: const Icon(Icons.image_rounded, size: 16),
                  label: const Text('Image'),
                ),
                TextButton.icon(
                  onPressed: onAddPdf,
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                  label: const Text('PDF'),
                ),
              ],
            ),
          ],
        ),
        if (files.isEmpty)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 24.h),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).dividerColor,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surface,
            ),
            child: Column(
              children: [
                Icon(
                  Icons.upload_file_rounded,
                  size: 32.sp,
                  color: AppColors.textTertiary,
                ),
                SizedBox(height: 8.h),
                Text(
                  'No bills attached',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.sp,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 100.h,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: files.length,
              separatorBuilder: (_, __) => SizedBox(width: 8.w),
              itemBuilder: (_, i) {
                final file = files[i];
                final isPdf = file.path.toLowerCase().endsWith('.pdf');

                return Stack(
                  children: [
                    Container(
                      width: 90.w,
                      height: 90.h,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Theme.of(context).dividerColor),
                        color: isPdf
                            ? AppColors.error.withValues(alpha: 0.1)
                            : null,
                      ),
                      child: isPdf
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.picture_as_pdf_rounded,
                                    color: AppColors.error, size: 28.sp),
                                Text(
                                  'PDF',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 10.sp,
                                    color: AppColors.error,
                                  ),
                                ),
                              ],
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                file,
                                fit: BoxFit.cover,
                              ),
                            ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: InkWell(
                        onTap: () => onRemove(i),
                        child: Container(
                          padding: EdgeInsets.all(2.w),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close, size: 10.sp, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}
