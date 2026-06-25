import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

import '../../../consultations/presentation/pages/consultation_screen.dart';
import '../../../maps/widgets/doctor_location_map_card.dart';
import '../../../model.dart';

class DoctorProfileScreen extends StatelessWidget {
  final UserModel user;

  const DoctorProfileScreen({super.key, required this.user});

  Future<void> submitUserRating({
    required String doctorId,
    required String userId,
    required double rating,
  }) async {
    final ratingRef = FirebaseFirestore.instance
        .collection('users')
        .doc(doctorId)
        .collection('ratings')
        .doc(userId);

    await ratingRef.set({'rating': rating});
    await updateDoctorAverageRating(doctorId);
  }

  Future<void> updateDoctorAverageRating(String doctorId) async {
    final ratingsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(doctorId)
        .collection('ratings')
        .get();

    if (ratingsSnapshot.docs.isEmpty) return;

    double total = 0;
    for (var doc in ratingsSnapshot.docs) {
      total += (doc['rating'] as num).toDouble();
    }

    final average = total / ratingsSnapshot.docs.length;

    await FirebaseFirestore.instance.collection('users').doc(doctorId).update({
      'rating': average,
      'consultationCount': ratingsSnapshot.docs.length,
    });
  }

  // دالة لبدء الاستشارة مع الطبيب
  Future<void> _startConsultation(BuildContext context) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب تسجيل الدخول لبدء الاستشارة')),
      );
      return;
    }

    try {
      final userDataDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final userData = userDataDoc.data() ?? {};

      // التحقق من وجود استشارة نشطة حالياً
      final existingConsultation = await FirebaseFirestore.instance
          .collection('consultations')
          .where('userId', isEqualTo: currentUser.uid)
          .where('doctorId', isEqualTo: user.uid)
          .where('type', isEqualTo: 'instant')
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      String consultationId;

      if (existingConsultation.docs.isNotEmpty) {
        // استخدام الاستشارة الموجودة
        consultationId = existingConsultation.docs.first.id;
      } else {
        // إنشاء استشارة جديدة
        final consultationRef = await FirebaseFirestore.instance
            .collection('consultations')
            .add({
          'type': 'instant',
          'doctorId': user.uid,
          'doctorName': user.fullName,
          'doctorImage': user.photoURL,
          'doctorFcmToken': user.fcmToken,
          'userId': currentUser.uid,
          'userName': userData['fullName'] ?? (currentUser.displayName ?? 'مستخدم'),
          'userImage': userData['profilePicture'] ?? currentUser.photoURL,
          'specialty': user.specialtyName,
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessageTime': FieldValue.serverTimestamp(),
          'status': 'pending',
          'isActive': true,
          'seenBy': [currentUser.uid],
          'hasNewMessage': false,
          'newMessageFor': null,
          'unreadCount': {
            currentUser.uid: 0,
            user.uid: 0
          },
        });
        consultationId = consultationRef.id;
      }

      // الانتقال إلى شاشة المحادثة
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ConsultationScreen(
            consultationId: consultationId,
            doctorUid: user.uid,
            patientUid: currentUser.uid,
            doctorName: user.fullName,
            patientName: userData['fullName'] ?? (currentUser.displayName ?? 'مستخدم'),
            doctorImage: user.photoURL ?? '',
            userImage: userData['photoURL'] ?? currentUser.photoURL ?? '',
            isDoctor: false,
          ),
        ),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل في بدء الاستشارة: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = user.photoURL;
    final workplaces = user.workplaces;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(user.fullName),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.primary,
        elevation: 1,
        iconTheme: IconThemeData(color: colorScheme.primary),
      ),
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          Container(color: colorScheme.surface),
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 80),
                CircleAvatar(
                  radius: 60,
                  backgroundImage: imageUrl != null
                      ? NetworkImage(imageUrl)
                      : const AssetImage('assets/images/doctor_placeholder.png')
                  as ImageProvider,
                ),
                const SizedBox(height: 16),
                Text(
                  user.fullName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  user.displaySpecialty,
                  style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      user.isOnline == true
                          ? Icons.circle
                          : Icons.circle_outlined,
                      color: user.isOnline == true
                          ? colorScheme.tertiary
                          : colorScheme.outline,
                      size: 12,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      user.isOnline == true ? 'متصل الآن' : 'غير متصل',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                /// ✅ معلومات الطبيب الحية
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }

                    final data =
                    snapshot.data!.data() as Map<String, dynamic>;

                    final latitude = _toDouble(data['latitude']) ?? user.latitude;
                    final longitude = _toDouble(data['longitude']) ?? user.longitude;
                    final address = (data['address'] ?? data['clinicAddress'] ?? user.address)?.toString();
                    final minSessionPrice = _toDouble(data['minSessionPrice']) ?? user.minSessionPrice;
                    final maxSessionPrice = _toDouble(data['maxSessionPrice']) ?? user.maxSessionPrice;
                    final bookingFee = _toDouble(data['bookingFee'] ?? data['consultationFee'] ?? data['sessionPrice']) ?? user.bookingFee;

                    return Column(
                      children: [
                        _buildGlassInfoCardFromLiveData(
                          context: context,
                          rating: (data['rating'] ?? 0).toDouble(),
                          consultationCount: (data['consultationCount'] ?? 0).toInt(),
                          licenseNumber: data['licenseNumber'],
                          phone: data['phone'],
                          isAvailable: data['isAvailable'] == true,
                        ),
                        const SizedBox(height: 12),
                        _buildPricingCard(
                          context,
                          minSessionPrice: minSessionPrice,
                          maxSessionPrice: maxSessionPrice,
                          bookingFee: bookingFee,
                        ),
                        if (latitude != null && longitude != null) ...[
                          const SizedBox(height: 12),
                          DoctorLocationMapCard(
                            latitude: latitude,
                            longitude: longitude,
                            address: address,
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),

                // أماكن العمل
                if (workplaces != null && workplaces.isNotEmpty)
                  ...workplaces.map((place) {
                    final workplace = Workplace.fromMap(place);
                    return _buildWorkplaceCard(workplace, context);
                  }).toList(),

                const SizedBox(height: 20),

                // أزرار الإجراءات
                _buildActionButtons(context),
              ],
            ),
          ),
        ],
      ),
    );
  }


  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _formatPrice(double? value) {
    if (value == null || value <= 0) return 'غير محدد';
    final fixed = value.truncateToDouble() == value ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
    return '$fixed ريال';
  }

  Widget _buildPricingCard(
    BuildContext context, {
    required double? minSessionPrice,
    required double? maxSessionPrice,
    required double? bookingFee,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final sessionPrice = minSessionPrice == null && maxSessionPrice == null
        ? 'غير محدد'
        : minSessionPrice != null && maxSessionPrice != null && minSessionPrice != maxSessionPrice
            ? '${_formatPrice(minSessionPrice)} - ${_formatPrice(maxSessionPrice)}'
            : _formatPrice(minSessionPrice ?? maxSessionPrice);

    return Card(
      color: colorScheme.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payments_rounded, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('أسعار الطبيب', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(context, Icons.medical_services_outlined, 'سعر الاستشارة', sessionPrice),
            const SizedBox(height: 10),
            _buildInfoRow(context, Icons.event_available_rounded, 'سعر الحجز', _formatPrice(bookingFee)),
          ],
        ),
      ),
    );
  }

  // واجهة أزرار الإجراءات
  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        // زر بدء الاستشارة
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _startConsultation(context),
            icon: const Icon(Icons.chat, size: 24),
            label: const Text(
              "بدء الاستشارة",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              elevation: 3,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // زر تقييم الطبيب
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _showRatingDialog(context),
            icon: const Icon(Icons.star_rate, size: 24),
            label: const Text(
              "قيّم الطبيب",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onTertiaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              elevation: 3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassInfoCardFromLiveData({
    required BuildContext context,
    required double rating,
    required int consultationCount,
    String? licenseNumber,
    String? phone,
    required bool isAvailable,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withOpacity( 0.42),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(context,
                      Icons.star, 'التقييم', '${rating.toStringAsFixed(1)} / 5'),
                  const SizedBox(height: 4),
                  RatingBarIndicator(
                    rating: rating,
                    itemBuilder: (context, _) =>
                    Icon(Icons.star, color: colorScheme.tertiary),
                    itemCount: 5,
                    itemSize: 24,
                    unratedColor: colorScheme.outlineVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildInfoRow(context, Icons.chat, 'عدد الاستشارات', '$consultationCount'),
              if (licenseNumber != null) ...[
                const SizedBox(height: 10),
                _buildInfoRow(context,
                    Icons.verified_user, 'رقم الترخيص', licenseNumber),
              ],
              if (phone != null) ...[
                const SizedBox(height: 10),
                _buildInfoRow(context, Icons.phone, 'رقم الهاتف', phone),
              ],
              const SizedBox(height: 10),
              _buildInfoRow(context,
                isAvailable ? Icons.check_circle : Icons.cancel,
                'الحالة',
                isAvailable ? 'متاح للاستشارة' : 'غير متاح حالياً',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: colorScheme.primary, size: 20),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 16,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildWorkplaceCard(Workplace workplace, BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      color: colorScheme.surface,
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: Icon(Icons.location_on, color: colorScheme.primary),
        title:
        Text(workplace.name, style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
        subtitle: Text(
          workplace.formattedWorkingHours,
          style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  void _showRatingDialog(BuildContext parentContext) {
    double _currentRating = 3.0;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == null) {
      ScaffoldMessenger.of(parentContext).showSnackBar(
        const SnackBar(content: Text("يجب تسجيل الدخول لتقييم الطبيب")),
      );
      return;
    }

    showDialog(
      context: parentContext,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('قيّم الطبيب'),
          content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RatingBar.builder(
                initialRating: _currentRating,
                minRating: 1,
                allowHalfRating: true,
                itemCount: 5,
                unratedColor: colorScheme.outlineVariant,
                itemBuilder: (context, _) =>
                Icon(Icons.star, color: colorScheme.tertiary),
                onRatingUpdate: (rating) => setState(() => _currentRating = rating),
              ),
              const SizedBox(height: 12),
              Text('التقييم الحالي: ${_currentRating.toStringAsFixed(1)}'),
            ],
          ),
        ),
          actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              await submitUserRating(
                doctorId: user.uid,
                userId: currentUserId,
                rating: _currentRating,
              );

              ScaffoldMessenger.of(parentContext).showSnackBar(
                const SnackBar(content: Text('تم إرسال التقييم بنجاح')),
              );
            },
            child: const Text('إرسال'),
          ),
        ],
      );
      },
    );
  }
}