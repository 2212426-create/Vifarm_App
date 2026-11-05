/// Model Lịch Sử Xét Duyệt Hồ Sơ Gian Hàng
class StoreAuditLog {
  final int version;
  final String status; // 'pending' | 'needs_changes' | 'approved' | 'rejected'
  final String reviewerId;
  final String reviewerName;
  final String reason;
  final String internalNote;
  final int timestamp;

  StoreAuditLog({
    required this.version,
    required this.status,
    required this.reviewerId,
    required this.reviewerName,
    required this.reason,
    this.internalNote = '',
    required this.timestamp,
  });

  factory StoreAuditLog.fromMap(Map<String, dynamic> map) {
    return StoreAuditLog(
      version: (map['version'] as num?)?.toInt() ?? 1,
      status: map['status'] as String? ?? 'pending',
      reviewerId: map['reviewerId'] as String? ?? '',
      reviewerName: map['reviewerName'] as String? ?? '',
      reason: map['reason'] as String? ?? '',
      internalNote: map['internalNote'] as String? ?? '',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toMap() => {
        'version': version,
        'status': status,
        'reviewerId': reviewerId,
        'reviewerName': reviewerName,
        'reason': reason,
        'internalNote': internalNote,
        'timestamp': timestamp,
      };
}

/// Model Gian hàng Nông Nghiệp
class StoreModel {
  final String storeId;
  final String ownerId;
  final String ownerName;
  final String storeType;        // 'individual' (Cá nhân/Nhà vườn) | 'business' (Đơn vị kinh doanh)
  final String? businessSubtype;  // 'enterprise' (Doanh nghiệp) | 'agent' (Đại lý) | 'coop' (HTX)
  final String storeName;
  final String avatarUrl;
  final String coverUrl;
  final String description;
  final String contactName;
  final String phone;
  final String address;
  final String region;
  final String? pickupLocation;
  final List<String> targetCategories;
  final List<String> fulfillmentMethods;
  final List<String> verificationDocs; // Tài liệu xác minh bảo mật (chỉ chủ hồ sơ & admin xem)
  final String? taxCode;
  final String? representative;
  final String status;          // 'draft' | 'pending' | 'needs_changes' | 'approved' | 'rejected'
  final String? rejectionReason;
  final String operatingStatus; // 'active' | 'suspended' | 'closed'
  final int version;            // Phiên bản hồ sơ gửi xét duyệt (tăng mỗi lần resubmit)
  final int? submittedAt;
  final String? reviewedBy;
  final String? reviewedByName;
  final int? reviewedAt;
  final List<StoreAuditLog> auditHistory;
  final int createdAt;
  final int updatedAt;

  StoreModel({
    required this.storeId,
    required this.ownerId,
    this.ownerName = '',
    this.storeType = 'individual',
    this.businessSubtype,
    required this.storeName,
    this.avatarUrl = '',
    this.coverUrl = '',
    this.description = '',
    required this.contactName,
    required this.phone,
    required this.address,
    required this.region,
    this.pickupLocation,
    this.targetCategories = const [],
    this.fulfillmentMethods = const ['pickup', 'agreed_delivery'],
    this.verificationDocs = const [],
    this.taxCode,
    this.representative,
    this.status = 'draft',
    this.rejectionReason,
    this.operatingStatus = 'active',
    this.version = 1,
    this.submittedAt,
    this.reviewedBy,
    this.reviewedByName,
    this.reviewedAt,
    this.auditHistory = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isApproved => status == 'approved';
  bool get isActive => operatingStatus == 'active';
  bool get canSell => isApproved && isActive;

  factory StoreModel.fromMap(Map<String, dynamic> map, [String? docId]) {
    return StoreModel(
      storeId: docId ?? map['storeId'] as String? ?? '',
      ownerId: map['ownerId'] as String? ?? '',
      ownerName: map['ownerName'] as String? ?? '',
      storeType: map['storeType'] as String? ?? 'individual',
      businessSubtype: map['businessSubtype'] as String?,
      storeName: map['storeName'] as String? ?? '',
      avatarUrl: map['avatarUrl'] as String? ?? '',
      coverUrl: map['coverUrl'] as String? ?? '',
      description: map['description'] as String? ?? '',
      contactName: map['contactName'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      address: map['address'] as String? ?? '',
      region: map['region'] as String? ?? '',
      pickupLocation: map['pickupLocation'] as String?,
      targetCategories: (map['targetCategories'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      fulfillmentMethods: (map['fulfillmentMethods'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['pickup', 'agreed_delivery'],
      verificationDocs: (map['verificationDocs'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      taxCode: map['taxCode'] as String?,
      representative: map['representative'] as String?,
      status: map['status'] as String? ?? 'draft',
      rejectionReason: map['rejectionReason'] as String?,
      operatingStatus: map['operatingStatus'] as String? ?? 'active',
      version: (map['version'] as num?)?.toInt() ?? 1,
      submittedAt: (map['submittedAt'] as num?)?.toInt(),
      reviewedBy: map['reviewedBy'] as String?,
      reviewedByName: map['reviewedByName'] as String?,
      reviewedAt: (map['reviewedAt'] as num?)?.toInt(),
      auditHistory: (map['auditHistory'] as List<dynamic>?)
              ?.map((e) => StoreAuditLog.fromMap(e as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt: (map['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toMap() => {
        'storeId': storeId,
        'ownerId': ownerId,
        'ownerName': ownerName,
        'storeType': storeType,
        'businessSubtype': businessSubtype,
        'storeName': storeName,
        'avatarUrl': avatarUrl,
        'coverUrl': coverUrl,
        'description': description,
        'contactName': contactName,
        'phone': phone,
        'address': address,
        'region': region,
        'pickupLocation': pickupLocation,
        'targetCategories': targetCategories,
        'fulfillmentMethods': fulfillmentMethods,
        'verificationDocs': verificationDocs,
        'taxCode': taxCode,
        'representative': representative,
        'status': status,
        'rejectionReason': rejectionReason,
        'operatingStatus': operatingStatus,
        'version': version,
        'submittedAt': submittedAt,
        'reviewedBy': reviewedBy,
        'reviewedByName': reviewedByName,
        'reviewedAt': reviewedAt,
        'auditHistory': auditHistory.map((a) => a.toMap()).toList(),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}
