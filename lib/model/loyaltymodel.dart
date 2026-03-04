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

  // 🔥 NOT final anymore
  List<JobModel> jobs;

  LoyaltyModel({
    required this.name,
    required this.contact,
    required this.address,
    required this.remarks,
    required this.count,
    required this.cardNumber,
    required this.logDate,
    this.jobs = const [],
  });

  factory LoyaltyModel.fromJson(Map<String, dynamic> json) {
    return LoyaltyModel(
      name: json['Name'] ?? '',
      contact: json['Contact'] ?? '',
      address: json['Address'] ?? '',
      remarks: json['C5_Remarks'] ?? '',
      count: json['Count'] ?? 0,
      cardNumber: json['cardNumber'] ?? 0,
      logDate: json['logDate'],
      jobs: [],
    );
  }
}
