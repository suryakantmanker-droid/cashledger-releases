import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/sale_provider.dart';

class AddSaleScreen extends ConsumerStatefulWidget {
  const AddSaleScreen({super.key});

  @override
  ConsumerState<AddSaleScreen> createState() => _AddSaleScreenState();
}

class _AddSaleScreenState extends ConsumerState<AddSaleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _itemCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _buyerCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  final List<File> _proofFiles = [];
  final _imagePicker = ImagePicker();

  @override
  void dispose() {
    _itemCtrl.dispose();
    _amountCtrl.dispose();
    _buyerCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saleState = ref.watch(saleNotifierProvider);
    final businessId = ref.watch(activeBusinessIdProvider);
    final isBusinessReady = businessId != null;

    ref.listen<SaleState>(saleNotifierProvider, (_, next) {
      if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.successMessage!),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: AppColors.error,
          ),
        );
        ref.read(saleNotifierProvider.notifier).clearMessages();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Log Sale / Collection')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info banner
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppColors.success, size: 18.sp),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(
                        'Amount will be credited to your wallet instantly.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.sp,
                          color: AppColors.success,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 18.h),

              AppTextField(
                label: 'Item / Material Sold',
                hint: 'E.g. Scrap iron, old furniture, surplus cement…',
                controller: _itemCtrl,
                validator: (v) =>
                    AppValidators.required(v, fieldName: 'Item description'),
                prefixIcon: const Icon(Icons.sell_rounded),
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
              ),
              SizedBox(height: 14.h),

              AppTextField(
                label: 'Amount Received (₹)',
                hint: '0.00',
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: AppValidators.amount,
                prefixIcon: const Icon(Icons.currency_rupee_rounded),
                textInputAction: TextInputAction.next,
              ),
              SizedBox(height: 14.h),

              AppTextField(
                label: 'Buyer Name (Optional)',
                hint: 'Who bought it?',
                controller: _buyerCtrl,
                prefixIcon: const Icon(Icons.person_outline_rounded),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
              ),
              SizedBox(height: 14.h),

              // Sale Date
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
                  padding: EdgeInsets.symmetric(
                      horizontal: 16.w, vertical: 16.h),
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: Theme.of(context).dividerColor),
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
                            'Sale Date',
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
                label: 'Notes (Optional)',
                hint: 'Any additional details…',
                controller: _notesCtrl,
                maxLines: 3,
                prefixIcon: const Icon(Icons.notes_rounded),
                textCapitalization: TextCapitalization.sentences,
              ),
              SizedBox(height: 20.h),

              // Proof Upload
              _ProofUploadSection(
                files: _proofFiles,
                onAddImage: _pickImage,
                onAddPdf: _pickPdf,
                onRemove: (i) =>
                    setState(() => _proofFiles.removeAt(i)),
              ),
              SizedBox(height: 28.h),

              // Upload progress
              if (saleState.isUploading) ...[
                LinearProgressIndicator(value: saleState.uploadProgress),
                SizedBox(height: 8.h),
                Text(
                  'Uploading proof… '
                  '${(saleState.uploadProgress * 100).toInt()}%',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.sp,
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(height: 12.h),
              ],

              AppButton(
                label: 'Submit & Credit Wallet',
                onPressed: (saleState.isLoading || !isBusinessReady)
                    ? null
                    : _submit,
                isLoading: saleState.isLoading,
                prefixIcon: Icons.account_balance_wallet_rounded,
              ),
              SizedBox(height: 24.h),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final status = await Permission.photos.request();
    if (!status.isGranted) return;

    final source = await _showSourceDialog();
    if (source == null) return;

    final xFile =
        await _imagePicker.pickImage(source: source, imageQuality: 85);
    if (xFile != null) {
      setState(() => _proofFiles.add(File(xFile.path)));
    }
  }

  Future<ImageSource?> _showSourceDialog() {
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
      setState(() => _proofFiles.add(File(result!.files.single.path!)));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = ref.read(currentUserProvider).valueOrNull ??
        ref.read(authNotifierProvider).user;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired. Please log in again.')),
      );
      return;
    }

    await ref.read(saleNotifierProvider.notifier).logSale(
      data: {
        'itemDescription': _itemCtrl.text.trim(),
        'amount': double.tryParse(_amountCtrl.text) ?? 0,
        'buyerName': _buyerCtrl.text.trim().isEmpty
            ? null
            : _buyerCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
        'saleDate': _selectedDate,
      },
      proofFiles: _proofFiles,
      employeeId: user.uid,
      employeeName: user.name,
    );
  }
}

// ── Proof Upload Section ───────────────────────────────────────────────────

class _ProofUploadSection extends StatelessWidget {
  final List<File> files;
  final VoidCallback onAddImage;
  final VoidCallback onAddPdf;
  final void Function(int) onRemove;

  const _ProofUploadSection({
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
              'Attach Proof (Optional)',
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
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surface,
            ),
            child: Column(
              children: [
                Icon(Icons.upload_file_rounded,
                    size: 32.sp, color: AppColors.textTertiary),
                SizedBox(height: 8.h),
                Text(
                  'No proof attached',
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
                        border: Border.all(
                            color: Theme.of(context).dividerColor),
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
                                Text('PDF',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10.sp,
                                      color: AppColors.error,
                                    )),
                              ],
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(file, fit: BoxFit.cover),
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
                          child: Icon(Icons.close,
                              size: 10.sp, color: Colors.white),
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
