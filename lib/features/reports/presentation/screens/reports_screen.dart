import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../features/business/domain/entities/business_membership_entity.dart';
import '../../../../shared/providers/business_context_provider.dart';
import '../../../expenses/data/models/expense_model.dart';
import '../../../expenses/presentation/providers/expense_provider.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _month = DateTime.now().month;
  int _year  = DateTime.now().year;
  bool _generating = false;

  @override
  Widget build(BuildContext context) {
    final expensesAsync   = ref.watch(allExpensesStreamProvider);
    final membership      = ref.watch(activeMembershipProvider);
    final isDemo          = membership?.subscriptionStatus == SubscriptionStatus.demo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        centerTitle: false,
        actions: [
          if (_generating)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Download PDF',
              onPressed: () => _handleDownload(expensesAsync, isDemo),
            ),
        ],
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data:    (all) => _Body(
          allExpenses: all,
          month: _month,
          year:  _year,
          onPrev: _prevMonth,
          onNext: _nextMonth,
        ),
      ),
    );
  }

  void _prevMonth() => setState(() {
    if (_month == 1) {
      _month = 12;
      _year--;
    } else {
      _month--;
    }
  });

  void _nextMonth() {
    final now = DateTime.now();
    if (_year < now.year || (_year == now.year && _month < now.month)) {
      setState(() {
        if (_month == 12) {
          _month = 1;
          _year++;
        } else {
          _month++;
        }
      });
    }
  }

  void _handleDownload(AsyncValue<List<ExpenseModel>> expensesAsync, bool isDemo) {
    if (isDemo) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Subscription Required'),
          content: const Text(
            'PDF reports are available on paid plans only.\n'
            'Upgrade your subscription to unlock this feature.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final expenses = expensesAsync.valueOrNull ?? [];
    final filtered = expenses.where((e) =>
        e.expenseDate.month == _month &&
        e.expenseDate.year  == _year  &&
        e.isApproved).toList();

    _generatePdf(filtered);
  }

  Future<void> _generatePdf(List<ExpenseModel> expenses) async {
    setState(() => _generating = true);
    try {
      // Load Noto Sans — supports ₹ and Devanagari characters
      final font     = await PdfGoogleFonts.notoSansRegular();
      final fontBold = await PdfGoogleFonts.notoSansBold();

      final pdf = pw.Document();
      final monthLabel = AppUtils.formatMonthYear(DateTime(_year, _month));
      final total = expenses.fold(0.0, (s, e) => s + e.amount);

      final catMap = <String, double>{};
      for (final e in expenses) {
        catMap[e.category] = (catMap[e.category] ?? 0) + e.amount;
      }
      final catList = catMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Helper: format currency for PDF using the loaded font
      String fmt(double v) => AppUtils.formatCurrency(v);

      pw.TextStyle body(double size) =>
          pw.TextStyle(font: font, fontSize: size);
      pw.TextStyle bold(double size) =>
          pw.TextStyle(font: fontBold, fontSize: size, fontWeight: pw.FontWeight.bold);

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Expense Report — $monthLabel', style: bold(20)),
            pw.SizedBox(height: 4),
            pw.Divider(),
            pw.SizedBox(height: 4),
          ],
        ),
        build: (_) => [
          // Summary card
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total Approved Expenses', style: body(13)),
                pw.Text(fmt(total), style: bold(15)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // Category table
          if (catList.isNotEmpty) ...[
            pw.Text('Category Breakdown', style: bold(14)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(2),
                2: pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: ['Category', 'Amount', '%']
                      .map((h) => pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(h, style: bold(11)),
                          ))
                      .toList(),
                ),
                for (final c in catList)
                  pw.TableRow(children: [
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(c.key, style: body(10))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(fmt(c.value), style: body(10))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                            total > 0
                                ? '${(c.value / total * 100).toStringAsFixed(1)}%'
                                : '0%',
                            style: body(10))),
                  ]),
              ],
            ),
            pw.SizedBox(height: 20),
          ],

          // Expense list
          pw.Text('All Approved Expenses', style: bold(14)),
          pw.SizedBox(height: 8),
          if (expenses.isEmpty)
            pw.Text('No approved expenses for this month.',
                style: pw.TextStyle(font: font, color: PdfColors.grey600))
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(2),
                1: pw.FlexColumnWidth(3),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: ['Date', 'Title', 'Category', 'Amount']
                      .map((h) => pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(h, style: bold(10)),
                          ))
                      .toList(),
                ),
                for (final e in expenses)
                  pw.TableRow(children: [
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(AppUtils.formatDate(e.expenseDate),
                            style: body(9))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(e.title, style: body(9))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(e.category, style: body(9))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(fmt(e.amount), style: body(9))),
                  ]),
              ],
            ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Generated on ${AppUtils.formatDateWithTime(DateTime.now())}',
            style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey500),
          ),
        ],
      ));

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'expense_report_${_year}_${_month.toString().padLeft(2, '0')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF generation failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }
}

// ── Body widget ───────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  final List<ExpenseModel> allExpenses;
  final int month;
  final int year;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _Body({
    required this.allExpenses,
    required this.month,
    required this.year,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = allExpenses.where((e) =>
        e.expenseDate.month == month &&
        e.expenseDate.year  == year  &&
        e.isApproved).toList();

    final total = filtered.fold(0.0, (s, e) => s + e.amount);

    final catMap = <String, double>{};
    for (final e in filtered) {
      catMap[e.category] = (catMap[e.category] ?? 0) + e.amount;
    }
    final catList = catMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Monthly bar data — last 6 months
    final barData = _buildBarData(allExpenses);

    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        // Month selector
        _MonthSelector(month: month, year: year, onPrev: onPrev, onNext: onNext),
        SizedBox(height: 16.h),

        // Summary card
        _SummaryCard(total: total, count: filtered.length),
        SizedBox(height: 20.h),

        // Trend bar chart
        if (barData.isNotEmpty) ...[
          _SectionHeader('6-Month Trend'),
          SizedBox(height: 12.h),
          _BarChart(data: barData),
          SizedBox(height: 20.h),
        ],

        // Pie chart + legend
        if (catList.isNotEmpty) ...[
          _SectionHeader('By Category'),
          SizedBox(height: 12.h),
          _PieSection(catList: catList, total: total),
          SizedBox(height: 20.h),
        ],

        // Category breakdown list
        _SectionHeader('Category Breakdown'),
        SizedBox(height: 8.h),
        if (catList.isEmpty)
          _EmptyMonthCard()
        else
          ...catList.asMap().entries.map((e) => Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: _CategoryRow(
                  label: e.value.key,
                  amount: e.value.value,
                  percent: total > 0 ? e.value.value / total : 0,
                  color: AppColors.chartColors[e.key % AppColors.chartColors.length],
                ),
              )),

        SizedBox(height: 32.h),
      ],
    );
  }

  List<_BarEntry> _buildBarData(List<ExpenseModel> all) {
    final now = DateTime.now();
    final result = <_BarEntry>[];
    for (int i = 5; i >= 0; i--) {
      int m = now.month - i;
      int y = now.year;
      while (m <= 0) { m += 12; y--; }
      final sum = all
          .where((e) => e.expenseDate.month == m && e.expenseDate.year == y && e.isApproved)
          .fold(0.0, (s, e) => s + e.amount);
      result.add(_BarEntry(month: m, year: y, total: sum));
    }
    return result;
  }
}

class _BarEntry {
  final int month, year;
  final double total;
  const _BarEntry({required this.month, required this.year, required this.total});
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _MonthSelector extends StatelessWidget {
  final int month, year;
  final VoidCallback onPrev, onNext;
  const _MonthSelector({required this.month, required this.year,
      required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left_rounded)),
          Text(
            AppUtils.formatMonthYear(DateTime(year, month)),
            style: TextStyle(fontFamily: 'Poppins', fontSize: 16.sp, fontWeight: FontWeight.w600),
          ),
          IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded)),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final double total;
  final int count;
  const _SummaryCard({required this.total, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: AppColors.blueGradient),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Approved',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12.sp,
                        color: Colors.white.withValues(alpha: 0.8))),
                SizedBox(height: 6.h),
                Text(AppUtils.formatCurrency(total),
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 26.sp,
                        fontWeight: FontWeight.w700, color: Colors.white)),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text('$count', style: TextStyle(fontFamily: 'Poppins',
                    fontSize: 20.sp, fontWeight: FontWeight.w700, color: Colors.white)),
                Text('Expenses', style: TextStyle(fontFamily: 'Poppins',
                    fontSize: 10.sp, color: Colors.white.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 15.sp, fontWeight: FontWeight.w600));
  }
}

class _BarChart extends StatelessWidget {
  final List<_BarEntry> data;
  const _BarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxVal = data.map((e) => e.total).fold(0.0, (a, b) => a > b ? a : b);
    final months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];

    return Container(
      height: 160.h,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: BarChart(
        BarChartData(
          maxY: maxVal == 0 ? 100 : maxVal * 1.25,
          barGroups: data.asMap().entries.map((e) => BarChartGroupData(
            x: e.key,
            barRods: [BarChartRodData(
              toY: e.value.total,
              color: AppColors.primary,
              width: 18.w,
              borderRadius: BorderRadius.circular(4),
            )],
          )).toList(),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, _) => Text(
                  months[(data[val.toInt()].month - 1)],
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 9.sp,
                      color: AppColors.textSecondary),
                ),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42.w,
                getTitlesWidget: (val, _) => Text(
                  AppUtils.formatCurrencyCompact(val),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 8.sp,
                      color: AppColors.textSecondary),
                ),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: Theme.of(context).dividerColor,
              strokeWidth: 0.5,
            ),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }
}

class _PieSection extends StatelessWidget {
  final List<MapEntry<String, double>> catList;
  final double total;
  const _PieSection({required this.catList, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          // Donut chart — fixed 180px height, radii in fixed dp (not .r)
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sections: catList.asMap().entries.map((e) => PieChartSectionData(
                  color: AppColors.chartColors[e.key % AppColors.chartColors.length],
                  value: e.value.value,
                  title: '',
                  radius: 45,   // fixed, no .r
                )).toList(),
                centerSpaceRadius: 50,  // fixed, no .r
                sectionsSpace: catList.length == 1 ? 0 : 2,
                startDegreeOffset: -90,
              ),
            ),
          ),
          SizedBox(height: 16.h),

          // Legend — wrap so it fits any number of categories
          Wrap(
            spacing: 12.w,
            runSpacing: 8.h,
            children: catList.asMap().entries.map((e) {
              final color =
                  AppColors.chartColors[e.key % AppColors.chartColors.length];
              final pct = total > 0
                  ? '${(e.value.value / total * 100).toStringAsFixed(1)}%'
                  : '0%';
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10.w,
                    height: 10.w,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  SizedBox(width: 5.w),
                  Text(
                    '${e.value.key} · ${AppUtils.formatCurrencyCompact(e.value.value)} ($pct)',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final String label;
  final double amount;
  final double percent;
  final Color color;

  const _CategoryRow({
    required this.label,
    required this.amount,
    required this.percent,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 4.w,
            height: 40.h,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 13.sp, fontWeight: FontWeight.w500)),
                SizedBox(height: 5.h),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent,
                    backgroundColor: color.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 6.h,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(AppUtils.formatCurrency(amount),
                  style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 13.sp, fontWeight: FontWeight.w700)),
              Text('${(percent * 100).toStringAsFixed(1)}%',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 10.sp, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyMonthCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Center(
        child: Text(
          'No approved expenses this month',
          style: TextStyle(fontFamily: 'Poppins',
              fontSize: 13.sp, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
