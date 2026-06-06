import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/expense_provider.dart';

class ExpenseDetailScreen extends ConsumerWidget {
  final String expenseId;
  const ExpenseDetailScreen({super.key, required this.expenseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenseAsync = ref.watch(expenseByIdProvider(expenseId));
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isAdmin = user?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Detail'),
        actions: [
          expenseAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (expense) => (!isAdmin && expense.isDraft)
                ? IconButton(
                    icon: const Icon(Icons.edit_rounded),
                    tooltip: 'Edit Draft',
                    onPressed: () => context.push(
                      '/employee/expenses/edit/${expense.id}',
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: expenseAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorStateWidget(message: e.toString()),
        data: (expense) => ListView(
          padding: EdgeInsets.all(16.w),
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          expense.title,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      StatusBadge(status: expense.status),
                    ],
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    AppUtils.formatCurrency(expense.amount),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 28.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.error,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    expense.expenseId,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.sp,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 14.h),

            // Details
            _DetailCard(
              title: 'Expense Details',
              items: [
                _Detail('Category', expense.category),
                _Detail('Date', AppUtils.formatDate(expense.expenseDate)),
                _Detail('Payment Method', expense.paymentMethod),
                if (expense.vendorName != null && expense.vendorName!.isNotEmpty)
                  _Detail('Vendor', expense.vendorName!),
                if (expense.description != null && expense.description!.isNotEmpty)
                  _Detail('Description', expense.description!),
                _Detail('Submitted By', expense.submittedByName),
                _Detail('Submitted On', AppUtils.formatDateWithTime(expense.createdAt)),
              ],
            ),
            SizedBox(height: 14.h),

            if (expense.isApproved || expense.isRejected) ...[
              _DetailCard(
                title: expense.isApproved ? 'Approval Info' : 'Rejection Info',
                items: [
                  _Detail(
                    expense.isApproved ? 'Approved By' : 'Rejected By',
                    expense.approvedByName ?? '',
                  ),
                  if (expense.approvedAt != null)
                    _Detail('On', AppUtils.formatDateWithTime(expense.approvedAt!)),
                  if (expense.isRejected && expense.rejectionReason != null)
                    _Detail('Reason', expense.rejectionReason!),
                ],
              ),
              SizedBox(height: 14.h),
            ],

            // Bills
            if (expense.billUrls.isNotEmpty) ...[
              Text(
                'Attached Bills (${expense.billUrls.length})',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 10.h),
              SizedBox(
                height: 120.h,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: expense.billUrls.length,
                  separatorBuilder: (_, __) => SizedBox(width: 10.w),
                  itemBuilder: (_, i) {
                    final url = expense.billUrls[i];
                    final isPdf = url.contains('.pdf') || url.contains('application%2Fpdf');

                    return GestureDetector(
                      onTap: () => _previewBill(context, url, isPdf),
                      child: Container(
                        width: 100.w,
                        height: 120.h,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Theme.of(context).dividerColor),
                          color: isPdf
                              ? AppColors.error.withValues(alpha: 0.08)
                              : null,
                        ),
                        child: isPdf
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.picture_as_pdf_rounded,
                                      size: 36.sp, color: AppColors.error),
                                  SizedBox(height: 4.h),
                                  Text(
                                    'PDF Bill ${i + 1}',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10.sp,
                                      color: AppColors.error,
                                    ),
                                  ),
                                ],
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (_, child, progress) =>
                                      progress == null
                                          ? child
                                          : const Center(child: CircularProgressIndicator()),
                                ),
                              ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: 14.h),
            ],

            // Employee: edit draft
            if (!isAdmin && expense.isDraft) ...[
              SizedBox(height: 8.h),
              AppButton(
                label: 'Edit Draft',
                onPressed: () =>
                    context.push('/employee/expenses/edit/${expense.id}'),
                prefixIcon: Icons.edit_rounded,
              ),
            ],

            // Admin Approval Actions
            if (isAdmin && expense.isPending) ...[
              SizedBox(height: 8.h),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Approve',
                      onPressed: () => _showApproveDialog(context, ref, expense.id),
                      prefixIcon: Icons.check_circle_rounded,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: AppButton(
                      label: 'Reject',
                      onPressed: () => _showRejectDialog(context, ref, expense.id),
                      variant: ButtonVariant.danger,
                      prefixIcon: Icons.cancel_rounded,
                    ),
                  ),
                ],
              ),
            ],

            SizedBox(height: 24.h),
          ],
        ),
      ),
    );
  }

  void _previewBill(BuildContext context, String url, bool isPdf) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BillPreviewSheet(url: url, isPdf: isPdf),
    );
  }

  void _showApproveDialog(BuildContext context, WidgetRef ref, String expenseId) {
    final user = ref.read(currentUserProvider).valueOrNull;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Expense?'),
        content: const Text('Are you sure you want to approve this expense? This will deduct from the employee\'s balance.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(expenseNotifierProvider.notifier).approveExpense(
                expenseId: expenseId,
                approvedBy: user?.uid ?? '',
                approvedByName: user?.name ?? '',
              );
              if (context.mounted) context.pop();
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(BuildContext context, WidgetRef ref, String expenseId) {
    final user = ref.read(currentUserProvider).valueOrNull;
    final reasonCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Expense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please provide a reason for rejection:'),
            SizedBox(height: 12.h),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Reason...'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              if (reasonCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              await ref.read(expenseNotifierProvider.notifier).rejectExpense(
                expenseId: expenseId,
                rejectedBy: user?.uid ?? '',
                rejectedByName: user?.name ?? '',
                reason: reasonCtrl.text.trim(),
              );
              if (context.mounted) context.pop();
            },
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).then((_) => reasonCtrl.dispose());
  }
}

class _DetailCard extends StatelessWidget {
  final String title;
  final List<_Detail> items;

  const _DetailCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 12.h),
          ...items.map((item) => Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 100.w,
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.sp,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.value,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _Detail {
  final String label;
  final String value;
  const _Detail(this.label, this.value);
}

// ── Bill Preview Sheet ────────────────────────────────────────────────────────

class _BillPreviewSheet extends StatefulWidget {
  final String url;
  final bool isPdf;
  const _BillPreviewSheet({required this.url, required this.isPdf});

  @override
  State<_BillPreviewSheet> createState() => _BillPreviewSheetState();
}

class _BillPreviewSheetState extends State<_BillPreviewSheet> {
  String? _localPdfPath;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isPdf) _downloadPdf();
  }

  Future<void> _downloadPdf() async {
    setState(() => _isLoading = true);
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.pdf';
      await Dio().download(widget.url, path);
      if (mounted) setState(() { _localPdfPath = path; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Failed to load PDF: $e'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        color: Colors.black,
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.isPdf ? 'PDF Bill' : 'Bill Image',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.isPdf ? _buildPdfView() : _buildImageView(),
          ),
        ],
      ),
    );
  }

  Widget _buildImageView() {
    return PhotoView(
      imageProvider: NetworkImage(widget.url),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 3,
      loadingBuilder: (_, __) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
      errorBuilder: (_, __, ___) => const Center(
        child: Text('Failed to load image', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildPdfView() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 12),
            Text('Loading PDF...', style: TextStyle(color: Colors.white70, fontFamily: 'Poppins')),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
        ),
      );
    }
    if (_localPdfPath == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return PDFView(
      filePath: _localPdfPath!,
      enableSwipe: true,
      swipeHorizontal: false,
      autoSpacing: true,
      pageFling: true,
      backgroundColor: Colors.black,
      onError: (e) => setState(() => _error = e.toString()),
    );
  }

  @override
  void dispose() {
    // Clean up temp file
    if (_localPdfPath != null) {
      File(_localPdfPath!).delete().ignore();
    }
    super.dispose();
  }
}
