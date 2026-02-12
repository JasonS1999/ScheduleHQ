import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/settings.dart' as app_models;
import '../../providers/approval_provider.dart';
import '../../providers/employee_provider.dart';
import '../../providers/time_off_provider.dart';
import '../../utils/app_constants.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_message.dart';
import 'request_card.dart';
import 'requests_filter_bar.dart';
import 'requests_empty_state.dart';
import 'add_time_off_entry_dialog.dart';

class RequestsManagementTab extends StatefulWidget {
  final ApprovalProvider approvalProvider;
  final EmployeeProvider employeeProvider;
  final TimeOffProvider timeOffProvider;
  final app_models.Settings settings;

  const RequestsManagementTab({
    super.key,
    required this.approvalProvider,
    required this.employeeProvider,
    required this.timeOffProvider,
    required this.settings,
  });

  @override
  State<RequestsManagementTab> createState() => _RequestsManagementTabState();
}

class _RequestsManagementTabState extends State<RequestsManagementTab> {
  String _searchQuery = '';
  int? _selectedEmployeeId;
  String? _selectedType;
  bool _showDenied = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEntryDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Entry'),
      ),
      body: Column(
        children: [
          // Filter bar
          RequestsFilterBar(
            searchQuery: _searchQuery,
            onSearchChanged: (v) => setState(() => _searchQuery = v),
            selectedEmployeeId: _selectedEmployeeId,
            onEmployeeChanged: (v) => setState(() => _selectedEmployeeId = v),
            selectedType: _selectedType,
            onTypeChanged: (v) => setState(() => _selectedType = v),
            showDenied: _showDenied,
            onShowDeniedChanged: (v) => setState(() => _showDenied = v),
            employees: widget.employeeProvider.employees,
          ),
          const Divider(height: 1),

          // Content
          Expanded(
            child: _buildRequestsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsList() {
    final stream = _showDenied
        ? widget.approvalProvider.getDeniedRequestsStream()
        : widget.approvalProvider.getPendingRequestsStream();

    if (stream == null) {
      return const Center(
        child: ErrorMessage(
          message: 'Not connected to cloud. Please sign in to view requests.',
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingIndicator();
        }

        if (snapshot.hasError) {
          return ErrorMessage(
            message: 'Error loading requests: ${snapshot.error}',
          );
        }

        final docs = snapshot.data?.docs ?? [];

        // Apply client-side filters
        final filtered = docs.where((doc) {
          final data = doc.data();
          // Employee filter
          if (_selectedEmployeeId != null &&
              data['employeeLocalId'] != _selectedEmployeeId) {
            return false;
          }
          // Type filter
          if (_selectedType != null &&
              data['timeOffType'] != _selectedType) {
            return false;
          }
          // Search filter
          if (_searchQuery.isNotEmpty) {
            final name = widget.approvalProvider
                .getEmployeeName(data['employeeLocalId'] as int? ?? 0);
            if (!name.toLowerCase().contains(_searchQuery.toLowerCase())) {
              return false;
            }
          }
          return true;
        }).toList();

        if (filtered.isEmpty) {
          return RequestsEmptyState(isDeniedView: _showDenied);
        }

        return ListView.builder(
          padding: const EdgeInsets.only(
            top: AppConstants.smallPadding,
            bottom: 80, // room for FAB
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) => RequestCard(
            document: filtered[index],
            approvalProvider: widget.approvalProvider,
            settings: widget.settings,
            onApproved: () {
              widget.approvalProvider.loadApprovedEntries();
              widget.timeOffProvider.loadData();
            },
          ),
        );
      },
    );
  }

  Future<void> _showAddEntryDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AddTimeOffEntryDialog(
        employees: widget.employeeProvider.employees,
        approvalProvider: widget.approvalProvider,
        timeOffProvider: widget.timeOffProvider,
        settings: widget.settings,
      ),
    );

    if (result == true) {
      await widget.timeOffProvider.loadData();
      await widget.approvalProvider.loadApprovedEntries();
    }
  }
}
