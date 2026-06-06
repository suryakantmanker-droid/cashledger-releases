class DepartmentModel {
  final String id;
  final String name;
  final String? businessId;   // null = global (superadmin)
  final String createdBy;
  final bool isActive;
  final DateTime createdAt;

  const DepartmentModel({
    required this.id,
    required this.name,
    this.businessId,
    required this.createdBy,
    required this.isActive,
    required this.createdAt,
  });

  bool get isGlobal => businessId == null;

  factory DepartmentModel.fromJson(Map<String, dynamic> j) => DepartmentModel(
        id:         j['id']          as String,
        name:       j['name']        as String,
        businessId: j['business_id'] as String?,
        createdBy:  j['created_by']  as String? ?? '',
        isActive:   j['is_active']   as bool? ?? true,
        createdAt:  DateTime.parse(j['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id':          id,
        'name':        name,
        'business_id': businessId,
        'created_by':  createdBy,
        'is_active':   isActive,
        'created_at':  createdAt.toIso8601String(),
      };
}
