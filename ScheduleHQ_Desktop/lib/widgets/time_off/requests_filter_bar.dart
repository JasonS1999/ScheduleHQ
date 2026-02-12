import 'package:flutter/material.dart';
import '../../models/employee.dart';
import '../../services/app_colors.dart';
import '../../utils/app_constants.dart';

class RequestsFilterBar extends StatelessWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final int? selectedEmployeeId;
  final ValueChanged<int?> onEmployeeChanged;
  final String? selectedType;
  final ValueChanged<String?> onTypeChanged;
  final bool showDenied;
  final ValueChanged<bool> onShowDeniedChanged;
  final List<Employee> employees;

  const RequestsFilterBar({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.selectedEmployeeId,
    required this.onEmployeeChanged,
    required this.selectedType,
    required this.onTypeChanged,
    required this.showDenied,
    required this.onShowDeniedChanged,
    required this.employees,
  });

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;

    return Padding(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 900;

          if (isWide) {
            return Row(
              children: [
                // Search field
                Expanded(
                  flex: 2,
                  child: _buildSearchField(context),
                ),
                const SizedBox(width: 12),

                // Employee dropdown
                SizedBox(
                  width: 180,
                  child: _buildEmployeeDropdown(context),
                ),
                const SizedBox(width: 12),

                // Type filter chips
                ..._buildTypeChips(context),
                const SizedBox(width: 12),

                // Show denied toggle
                _buildDeniedChip(context, appColors),
              ],
            );
          }

          // Narrow layout: stacked
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _buildSearchField(context)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 180,
                    child: _buildEmployeeDropdown(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ..._buildTypeChips(context),
                  _buildDeniedChip(context, appColors),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Search by employee name...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => onSearchChanged(''),
              )
            : null,
        isDense: true,
      ),
      onChanged: onSearchChanged,
      controller: TextEditingController(text: searchQuery)
        ..selection = TextSelection.fromPosition(
          TextPosition(offset: searchQuery.length),
        ),
    );
  }

  Widget _buildEmployeeDropdown(BuildContext context) {
    return DropdownButtonFormField<int?>(
      decoration: const InputDecoration(
        labelText: 'Employee',
        isDense: true,
      ),
      initialValue: selectedEmployeeId,
      isExpanded: true,
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('All')),
        ...employees.map(
          (e) => DropdownMenuItem<int?>(
            value: e.id,
            child: Text(e.displayName, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onEmployeeChanged,
    );
  }

  List<Widget> _buildTypeChips(BuildContext context) {
    const types = [
      (null, 'All'),
      ('pto', 'PTO'),
      ('vacation', 'Vacation'),
      ('requested', 'Requested'),
    ];

    return types.map((entry) {
      final (type, label) = entry;
      return FilterChip(
        label: Text(label),
        selected: selectedType == type,
        onSelected: (_) => onTypeChanged(type),
      );
    }).toList();
  }

  Widget _buildDeniedChip(BuildContext context, AppColors appColors) {
    return FilterChip(
      label: const Text('Show Denied'),
      avatar: Icon(Icons.block, size: 16, color: showDenied ? appColors.errorForeground : null),
      selected: showDenied,
      onSelected: onShowDeniedChanged,
      selectedColor: appColors.errorBackground,
    );
  }
}
