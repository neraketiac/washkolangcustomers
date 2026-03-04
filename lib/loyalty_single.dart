import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:washkolangcustomer/model/jobmodel.dart';
import 'package:washkolangcustomer/model/loyaltymodel.dart';

// 🔥 Make sure these are defined somewhere in your project
// const String JOBS_QUEUE_REF = "Jobs_queue";
// const String JOBS_ONGOING_REF = "Jobs_ongoing";
// const String JOBS_DONE_REF = "Jobs_done";
// const String JOBS_COMPLETED_REF = "Jobs_completed";

// ================= JOB QUERY FUNCTION =================

Future<List<JobModel>> getJobsByCardNumber(String cardNumber) async {
  const String JOBS_QUEUE_REF = "Jobs_queue";
  const String JOBS_ONGOING_REF = "Jobs_ongoing";
  const String JOBS_DONE_REF = "Jobs_done";
  const String JOBS_COMPLETED_REF = "Jobs_completed";
  final firestore = FirebaseFirestore.instance;

  const jobCollections = [
    JOBS_QUEUE_REF,
    JOBS_ONGOING_REF,
    JOBS_DONE_REF,
    JOBS_COMPLETED_REF,
  ];

  List<JobModel> allJobs = [];

  for (final jobCollection in jobCollections) {
    final snapshot = await firestore.collection(jobCollection).get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final dynamic rawId = data['C00_CustomerId'];

      if (rawId?.toString() == cardNumber) {
        data['docId'] = doc.id;
        final job = JobModel.fromJson(data);
        allJobs.add(job);
      }
    }
  }

  // Sort latest first
  allJobs.sort((a, b) => b.dateD.compareTo(a.dateD));

  return allJobs;
}

// ================= MAIN WIDGET =================

class MyLoyaltyCard extends StatefulWidget {
  final String code;

  const MyLoyaltyCard(this.code, {super.key});

  @override
  State<MyLoyaltyCard> createState() => _MyLoyaltyCardState();
}

class _MyLoyaltyCardState extends State<MyLoyaltyCard> {
  int? _selectedIndex;
  Future<LoyaltyModel?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchLoyalty();
  }

  Future<LoyaltyModel?> _fetchLoyalty() async {
    final parsed = int.tryParse(widget.code);
    if (parsed == null) return null;

    final firestore = FirebaseFirestore.instance;

    final snap = await firestore
        .collection('loyalty')
        .where('cardNumber', isEqualTo: parsed)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;

    final loyalty = LoyaltyModel.fromJson(snap.docs.first.data());

    // 🔥 Dynamically fetch jobs
    final jobs = await getJobsByCardNumber(widget.code);

    // Inject jobs in memory only
    loyalty.jobs = jobs;

    if (loyalty.jobs.isNotEmpty) {
      _selectedIndex = 0;
    }

    return loyalty;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB), Color(0xFF90CAF9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: FutureBuilder<LoyaltyModel?>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data == null) {
                return const Center(child: Text("Card not found"));
              }

              return _modernCardUI(snapshot.data!);
            },
          ),
        ),
      ),
    );
  }

  // ================= MAIN CARD =================

  Widget _modernCardUI(LoyaltyModel loyalty) {
    final int filledStars = loyalty.jobs.length > 10 ? 10 : loyalty.jobs.length;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "🫧 Wash Ko Lang",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Card #${loyalty.cardNumber}",
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
            const SizedBox(height: 16),

            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.95),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.blue.shade200, blurRadius: 18),
                  ],
                ),
                child: Column(
                  children: [
                    _infoRow("Name", loyalty.name),
                    _infoRow("Contact", loyalty.contact),
                    _infoRow("Address", loyalty.address),

                    const SizedBox(height: 18),

                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 10,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                          ),
                      itemBuilder: (context, index) {
                        final filled = index < filledStars;

                        return GestureDetector(
                          onTap: filled
                              ? () {
                                  setState(() {
                                    _selectedIndex = _selectedIndex == index
                                        ? null
                                        : index;
                                  });
                                }
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: filled
                                  ? (_selectedIndex == index
                                        ? Colors.orangeAccent
                                        : Colors.blueAccent)
                                  : Colors.blue.shade50,
                            ),
                            child: Icon(
                              filled ? Icons.star : Icons.star_border,
                              color: filled ? Colors.white : Colors.blueGrey,
                              size: 18,
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    Text(
                      "$filledStars / 10 Washes",
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.blueAccent,
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (_selectedIndex != null &&
                        _selectedIndex! < loyalty.jobs.length)
                      _jobDetailCard(loyalty.jobs[_selectedIndex!]),

                    const SizedBox(height: 14),

                    if (filledStars >= 10)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF64B5F6), Color(0xFF2196F3)],
                          ),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: const Text(
                          "🎁 FREE WASH!",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Back",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= HELPERS =================

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            "$label: ",
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.blueGrey,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String textJobStatus(JobModel jM) {
    if (jM.processStep == '') {
      if (jM.forSorting) {
        return 'For Sorting';
      }
      if (jM.riderPickup) {
        return 'Rider Pickup';
      }
    } else {
      if (jM.processStep == 'done') {
        if (jM.riderPickup) {
          if (jM.isDeliveredToCustomer) {
            return '${jM.processStep} 🚲 delivered\n${DateFormat('MM/dd hh:mm a').format(jM.riderDeliveryDate.toDate())}';
          } else {
            return '${jM.processStep} 🚲 for delivery';
          }
        } else {
          if (jM.isCustomerPickedUp) {
            return '${jM.processStep} 🛒 pickedup\n${DateFormat('MM/dd hh:mm a').format(jM.customerPickupDate.toDate())}';
          } else {
            return '${jM.processStep} 🛒 wait customer pickup';
          }
        }
      } else {
        return jM.processStep;
      }
    }

    return 'no status';
  }

  Widget _jobDetailCard(JobModel job) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueAccent.withOpacity(.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow(
            "📅 Date",
            DateFormat('MMMM dd, yyyy').format(job.dateD.toDate()),
          ),
          _detailRow('Status', textJobStatus(job)),
          _detailRow("💰 Price", "₱${job.finalPrice}"),
          _detailRow(
            "💳 Payment",
            job.paidCash
                ? "Paid Cash"
                : job.paidGCashverified
                ? "Paid GCash(verified)"
                : job.paidGCash
                ? "Paid GCash(unverified)"
                : "Unpaid",
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            "$label: ",
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.blueAccent,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
