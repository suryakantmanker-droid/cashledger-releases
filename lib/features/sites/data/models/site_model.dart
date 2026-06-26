class SiteModel {
  final String id;
  final String name;
  final String address;
  final String businessId;
  final String createdBy;
  final bool isActive;
  final DateTime createdAt;

  const SiteModel({
    required this.id,
    required this.name,
    required this.address,
    required this.businessId,
    required this.createdBy,
    required this.isActive,
    required this.createdAt,
  });

  factory SiteModel.fromJson(Map<String, dynamic> j) => SiteModel(
        id:         j['id']          as String,
        name:       j['name']        as String,
        address:    j['address']     as String? ?? '',
        businessId: j['business_id'] as String,
        createdBy:  j['created_by']  as String? ?? '',
        isActive:   j['is_active']   as bool? ?? true,
        createdAt:  DateTime.parse(j['created_at'] as String),
      );
}
