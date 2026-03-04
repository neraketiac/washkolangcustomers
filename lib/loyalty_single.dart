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

    jobs.sort((a, b) => a.dateD.compareTo(b.dateD));

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
    /// sort jobs by date
    final jobs = [...loyalty.jobs];
    jobs.sort((a, b) => a.dateD.compareTo(b.dateD));

    /// map stamps to jobs
    final List<int> starToJobIndex = [];

    for (int j = 0; j < jobs.length; j++) {
      final job = jobs[j];

      for (int i = 0; i < job.promoCounter; i++) {
        starToJobIndex.add(j);
      }
    }

    /// detect reward stamps
    final List<int> rewardStars = [];
    final List<int> filteredStars = [];

    for (int i = 0; i < starToJobIndex.length; i++) {
      if ((i + 1) % 11 == 0) {
        rewardStars.add(starToJobIndex[i]);
      } else {
        filteredStars.add(starToJobIndex[i]);
      }
    }

    /// split stamps into promo groups
    final List<List<int>> promoGroups = [];

    for (int i = 0; i < filteredStars.length; i += 10) {
      promoGroups.add(
        filteredStars.sublist(
          i,
          (i + 10 > filteredStars.length) ? filteredStars.length : i + 10,
        ),
      );
    }

    /// newest promo card on top
    final groups = promoGroups.reversed.toList();

    final promoCounter = starToJobIndex.length;

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
              constraints: const BoxConstraints(maxWidth: 420),
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

                    /// PROMO CARDS
                    Column(
                      children: groups.asMap().entries.map((entry) {
                        final groupIndex = entry.key;
                        final groupStars = entry.value;
                        final filledStars = groupStars.length;

                        /// real promo index
                        final rewardIndex = promoGroups.length - 1 - groupIndex;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              /// STAMP GRID
                              Expanded(
                                child: GridView.builder(
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

                                    int? jobIndex;

                                    if (filled && index < groupStars.length) {
                                      jobIndex = groupStars[index];
                                    }

                                    String? stampDate;

                                    if (filled && jobIndex != null) {
                                      final job = jobs[jobIndex];

                                      final DateTime d = job.dateD.toDate();

                                      stampDate =
                                          "${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}";
                                    }

                                    return GestureDetector(
                                      onTap: filled && jobIndex != null
                                          ? () {
                                              setState(() {
                                                _selectedIndex = jobIndex!;
                                              });
                                            }
                                          : null,
                                      child: AnimatedScale(
                                        scale: (_selectedIndex == jobIndex)
                                            ? 1.15
                                            : 1,
                                        duration: const Duration(
                                          milliseconds: 250,
                                        ),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: filled
                                                ? const LinearGradient(
                                                    colors: [
                                                      Color(0xFF4FC3F7),
                                                      Color(0xFF1E88E5),
                                                    ],
                                                  )
                                                : null,
                                            color: filled
                                                ? null
                                                : Colors.blue.shade100,
                                            boxShadow: filled
                                                ? [
                                                    BoxShadow(
                                                      color: Colors.blueAccent
                                                          .withOpacity(.4),
                                                      blurRadius: 12,
                                                    ),
                                                  ]
                                                : [],
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                filled
                                                    ? Icons.star
                                                    : Icons.star_border,
                                                color: filled
                                                    ? Colors.white
                                                    : Colors.blueGrey,
                                                size: 24,
                                              ),
                                              const SizedBox(height: 4),
                                              if (filled && stampDate != null)
                                                Text(
                                                  stampDate,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors
                                                        .blueGrey
                                                        .shade700,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),

                              const SizedBox(width: 12),

                              /// BIG FREE STAR
                              /// BIG FREE STAR
                              Builder(
                                builder: (context) {
                                  int? jobIndex;

                                  if (rewardStars.length > rewardIndex) {
                                    jobIndex = rewardStars[rewardIndex];
                                  }

                                  String? stampDate;

                                  if (jobIndex != null) {
                                    final job = jobs[jobIndex];
                                    final DateTime d = job.dateD.toDate();

                                    stampDate =
                                        "${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}";
                                  }

                                  return GestureDetector(
                                    onTap: jobIndex != null
                                        ? () {
                                            setState(() {
                                              _selectedIndex = jobIndex!;
                                            });
                                          }
                                        : null,
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      width: 70,
                                      height: 70,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: jobIndex != null
                                            ? const LinearGradient(
                                                colors: [
                                                  Color(0xFFFFD54F),
                                                  Color(0xFFFFA000),
                                                ],
                                              )
                                            : null,
                                        color: jobIndex != null
                                            ? null
                                            : Colors.orange.shade100,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.orange.withOpacity(
                                              .35,
                                            ),
                                            blurRadius: 10,
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.star,
                                            color: Colors.white,
                                            size: 28,
                                          ),

                                          const SizedBox(height: 2),

                                          const Text(
                                            "FREE",
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),

                                          if (stampDate != null)
                                            Text(
                                              stampDate,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 12),

                    /// TOTAL
                    Text(
                      "$promoCounter Load(s) Full Service",
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.blueAccent,
                      ),
                    ),

                    const SizedBox(height: 12),

                    /// JOB DETAILS
                    if (_selectedIndex != null && _selectedIndex! < jobs.length)
                      _jobDetailCard(jobs[_selectedIndex!]),
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
            return '${jM.processStep} 🚲 delivered ${DateFormat('MM/dd hh:mm a').format(jM.riderDeliveryDate.toDate())}';
          } else {
            return '${jM.processStep} 🚲 for delivery';
          }
        } else {
          if (jM.isCustomerPickedUp) {
            return '${jM.processStep} 🛒 pickedup ${DateFormat('MM/dd hh:mm a').format(jM.customerPickupDate.toDate())}';
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
          _detailRow('🫧 Status', textJobStatus(job)),
          _detailRow("💰 Price", "₱${job.finalPrice}"),
          _detailRow(
            "💳 Payment",
            job.paidCash
                ? "Paid Cash"
                : job.paidGCashverified
                ? "Paid GCash"
                : job.paidGCash
                ? "GCash Pending"
                : "Unpaid",
          ),
          if (job.remarks != '') _detailRow("✍️ Remarks", job.remarks),
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
