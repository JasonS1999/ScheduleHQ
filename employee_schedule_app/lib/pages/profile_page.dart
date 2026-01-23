import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _name;
  String? _jobCode;
  String? _email;
  int? _vacationWeeksAllowed;
  int? _vacationWeeksUsed;
  String? _managerUid;
  int? _employeeLocalId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    
    final user = AuthService.instance.currentUser;
    final managerUid = await AuthService.instance.getManagerUid();
    final employeeLocalId = await AuthService.instance.getEmployeeLocalId();
    final data = await AuthService.instance.getEmployeeData();
    
    if (mounted) {
      setState(() {
        _email = user?.email;
        _managerUid = managerUid;
        _employeeLocalId = employeeLocalId;
        _name = data?['name'] as String?;
        _jobCode = data?['jobCode'] as String?;
        _vacationWeeksAllowed = data?['vacationWeeksAllowed'] as int? ?? 0;
        _vacationWeeksUsed = data?['vacationWeeksUsed'] as int? ?? 0;
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService.instance.signOut();
      // Navigation is handled by AuthWrapper
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProfile,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Profile header
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Text(
                          _name?.isNotEmpty == true 
                              ? _name![0].toUpperCase() 
                              : '?',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _name ?? 'Unknown',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (_jobCode != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            _jobCode!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Info cards
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.email_outlined),
                        title: const Text('Email'),
                        subtitle: Text(_email ?? 'Not set'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.beach_access_outlined),
                        title: const Text('Vacation'),
                        subtitle: Text(
                          '${_vacationWeeksUsed ?? 0} of ${_vacationWeeksAllowed ?? 0} weeks used',
                        ),
                        trailing: _vacationWeeksAllowed != null && _vacationWeeksAllowed! > 0
                            ? CircularProgressIndicator(
                                value: (_vacationWeeksUsed ?? 0) / _vacationWeeksAllowed!,
                                strokeWidth: 3,
                                backgroundColor: Colors.grey.shade200,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // PTO Summary card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.timer_outlined),
                            SizedBox(width: 8),
                            Text(
                              'PTO Summary',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildPtoSummary(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Sign out button
                OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text(
                    'Sign Out',
                    style: TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPtoSummary() {
    final user = AuthService.instance.currentUser;
    if (user == null || _managerUid == null || _employeeLocalId == null) {
      return const Text('Not available');
    }

    // Calculate PTO from timeOff entries in the manager's subcollection
    return FutureBuilder<Map<String, int>>(
      future: _calculatePtoSummary(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Column(
            children: [
              _buildPtoRow('Used', '—'),
              _buildPtoRow('Available', '—'),
            ],
          );
        }

        final data = snapshot.data!;
        final used = data['used'] ?? 0;
        final available = data['available'] ?? 0;

        return Column(
          children: [
            _buildPtoRow('Used', '$used hours'),
            const Divider(),
            _buildPtoRow('Available', '$available hours', bold: true),
          ],
        );
      },
    );
  }

  Future<Map<String, int>> _calculatePtoSummary() async {
    try {
      // Get current trimester date range
      final now = DateTime.now();
      final trimesterStart = _getTrimesterStart(now);
      final trimesterEnd = _getTrimesterEnd(now);

      // Query all timeOff entries for this employee, then filter in memory
      // This avoids needing a complex compound Firestore index
      final query = await FirebaseFirestore.instance
          .collection('managers')
          .doc(_managerUid)
          .collection('timeOff')
          .where('employeeLocalId', isEqualTo: _employeeLocalId)
          .get();

      // Sum up used PTO hours in current trimester
      int usedHours = 0;
      for (final doc in query.docs) {
        final data = doc.data();
        final type = data['timeOffType'] as String?;
        if (type != 'pto') continue;
        
        final dateStr = data['date'] as String?;
        if (dateStr == null) continue;
        
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;
        
        // Check if in current trimester
        if (date.isBefore(trimesterStart) || date.isAfter(trimesterEnd)) continue;
        
        final hours = data['hours'] as int? ?? 8;
        usedHours += hours;
      }

      // Get employee's PTO allowance from settings (default 40 hours per trimester)
      // For now, use a default. Later this could come from manager settings synced to Firestore
      const allowancePerTrimester = 40;
      
      final available = allowancePerTrimester - usedHours;

      return {
        'used': usedHours,
        'available': available > 0 ? available : 0,
      };
    } catch (e) {
      debugPrint('Error calculating PTO: $e');
      return {'used': 0, 'available': 0};
    }
  }

  DateTime _getTrimesterStart(DateTime date) {
    final year = date.year;
    if (date.month <= 4) {
      return DateTime(year, 1, 1);
    } else if (date.month <= 8) {
      return DateTime(year, 5, 1);
    } else {
      return DateTime(year, 9, 1);
    }
  }

  DateTime _getTrimesterEnd(DateTime date) {
    final year = date.year;
    if (date.month <= 4) {
      return DateTime(year, 4, 30);
    } else if (date.month <= 8) {
      return DateTime(year, 8, 31);
    } else {
      return DateTime(year, 12, 31);
    }
  }

  Widget _buildPtoRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : null,
            ),
          ),
        ],
      ),
    );
  }
}
