import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:washkolangcustomer/model/jobmodel.dart';

class LoyaltyModel {
  final String name;
  final String contact;
  final String address;
  final String remarks;
  final int count;
  final int cardNumber;
  final Timestamp logDate;
  final List<JobModel> jobs;

  LoyaltyModel({
    required this.name,
    required this.contact,
    required this.address,
    required this.remarks,
    required this.count,
    required this.cardNumber,
    required this.logDate,
    required this.jobs,
  });

  /// ===============================
  /// 🔵 FROM FIRESTORE (SAFE VERSION)
  /// ===============================
  factory LoyaltyModel.fromJson(Map<String, dynamic> json) {
    return LoyaltyModel(
      name: json['Name'] as String? ?? '',
      contact: json['Contact'] as String? ?? '',
      address: json['Address'] as String? ?? '',
      remarks: json['C5_Remarks'] as String? ?? '',
      count: (json['Count'] ?? 0) as int,
      cardNumber: (json['cardNumber'] ?? 0) as int,
      logDate: json['logDate'] as Timestamp? ?? Timestamp.now(),

      // 🔹 Safe Jobs Parsing
      jobs: (json['jobs'] as List<dynamic>? ?? [])
          .map((e) => JobModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// ===============================
  /// 🟡 COPY WITH
  /// ===============================
  LoyaltyModel copyWith({
    String? name,
    String? contact,
    String? address,
    String? remarks,
    int? count,
    int? cardNumber,
    Timestamp? logDate,
    List<JobModel>? jobs,
  }) {
    return LoyaltyModel(
      name: name ?? this.name,
      contact: contact ?? this.contact,
      address: address ?? this.address,
      remarks: remarks ?? this.remarks,
      count: count ?? this.count,
      cardNumber: cardNumber ?? this.cardNumber,
      logDate: logDate ?? this.logDate,
      jobs: jobs ?? this.jobs,
    );
  }

  /// ===============================
  /// 🟢 TO FIRESTORE
  /// ===============================
  Map<String, dynamic> toJson() {
    return {
      'Name': name,
      'Contact': contact,
      'Address': address,
      'C5_Remarks': remarks,
      'Count': count,
      'cardNumber': cardNumber,
      'logDate': logDate,

      // 🔹 Convert jobs list
      'jobs': jobs.map((e) => e.toJson()).toList(),
    };
  }
}
