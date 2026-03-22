import 'package:cloud_firestore/cloud_firestore.dart';

class LoyaltyOrderOnlineModel {
  final String name;
  final String contact;
  final String address;
  final String remarks;
  final DateTime scheduleDate;
  final String timeSlot;
  final Timestamp createdAt;

  LoyaltyOrderOnlineModel({
    required this.name,
    required this.contact,
    required this.address,
    this.remarks = '',
    required this.scheduleDate,
    required this.timeSlot,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'contact': contact,
    'address': address,
    'remarks': remarks,
    'scheduleDate': Timestamp.fromDate(scheduleDate),
    'timeSlot': timeSlot,
    'createdAt': createdAt,
  };
}
