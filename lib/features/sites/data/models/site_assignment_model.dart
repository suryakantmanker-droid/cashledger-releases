class SiteAssignmentModel {
  final String id;
  final String employeeId;
  final String siteId;
  final String siteName;
  final String siteAddress;
  final DateTime startDate;
  final DateTime? endDate;
  final String assignedBy;

  const SiteAssignmentModel({
    required this.id,
    required this.employeeId,
    required this.siteId,
    required this.siteName,
    required this.siteAddress,
    required this.startDate,
    this.endDate,
    required this.assignedBy,
  });

  bool get isCurrent => endDate == null;

  factory SiteAssignmentModel.fromJson(Map<String, dynamic> j) {
    final site = j['sites'] as Map<String, dynamic>? ?? {};
    return SiteAssignmentModel(
      id:          j['id']          as String,
      employeeId:  j['employee_id'] as String,
      siteId:      j['site_id']     as String,
      siteName:    site['name']    as String? ?? 'Unknown Site',
      siteAddress: site['address'] as String? ?? '',
      startDate:   DateTime.parse(j['start_date'] as String),
      endDate: j['end_date'] != null
          ? DateTime.parse(j['end_date'] as String)
          : null,
      assignedBy: j['assigned_by'] as String? ?? '',
    );
  }
}
