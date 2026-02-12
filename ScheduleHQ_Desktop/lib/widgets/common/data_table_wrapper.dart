import 'package:flutter/material.dart';
import '../../utils/app_constants.dart';

/// A wrapper widget for DataTable with consistent styling and functionality
class DataTableWrapper extends StatefulWidget {
  /// The columns for the data table
  final List<DataColumn> columns;
  
  /// The rows for the data table
  final List<DataRow> rows;
  
  /// Whether the table allows sorting
  final bool sortAscending;
  
  /// The index of the column to sort by
  final int? sortColumnIndex;
  
  /// Callback when a column header is tapped for sorting
  final Function(int columnIndex, bool ascending)? onSort;
  
  /// Whether to show checkboxes for row selection
  final bool showCheckboxColumn;
  
  /// The minimum width of the data table
  final double? minWidth;
  
  /// The table border configuration
  final TableBorder? border;
  
  /// The decoration for the table container
  final BoxDecoration? decoration;
  
  /// Whether to make the table scrollable horizontally
  final bool horizontalScrollable;
  
  /// Whether to make the table scrollable vertically
  final bool verticalScrollable;
  
  /// Maximum height for vertical scrolling
  final double? maxHeight;

  const DataTableWrapper({
    super.key,
    required this.columns,
    required this.rows,
    this.sortAscending = true,
    this.sortColumnIndex,
    this.onSort,
    this.showCheckboxColumn = false,
    this.minWidth,
    this.border,
    this.decoration,
    this.horizontalScrollable = true,
    this.verticalScrollable = false,
    this.maxHeight,
  });

  @override
  State<DataTableWrapper> createState() => _DataTableWrapperState();
}

class _DataTableWrapperState extends State<DataTableWrapper> {
  late ScrollController _horizontalController;
  late ScrollController _verticalController;

  @override
  void initState() {
    super.initState();
    _horizontalController = ScrollController();
    _verticalController = ScrollController();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Build the data table
    Widget dataTable = DataTable(
      columns: widget.columns,
      rows: widget.rows,
      sortAscending: widget.sortAscending,
      sortColumnIndex: widget.sortColumnIndex,
      onSelectAll: widget.showCheckboxColumn ? (selected) {
        // Handle select all logic if needed
      } : null,
      showCheckboxColumn: widget.showCheckboxColumn,
      columnSpacing: 24,
      horizontalMargin: 24,
      headingRowHeight: 56,
      dataRowHeight: 48,
      border: widget.border ?? TableBorder.all(
        color: theme.dividerColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
      ),
      headingTextStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface,
      ),
      dataTextStyle: theme.textTheme.bodyMedium,
    );

    // Add minimum width constraint if specified
    if (widget.minWidth != null) {
      dataTable = ConstrainedBox(
        constraints: BoxConstraints(minWidth: widget.minWidth!),
        child: dataTable,
      );
    }

    // Add horizontal scrolling if enabled
    if (widget.horizontalScrollable) {
      dataTable = SingleChildScrollView(
        controller: _horizontalController,
        scrollDirection: Axis.horizontal,
        child: dataTable,
      );
    }

    // Add vertical scrolling if enabled
    if (widget.verticalScrollable) {
      dataTable = Scrollbar(
        controller: _verticalController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _verticalController,
          scrollDirection: Axis.vertical,
          child: dataTable,
        ),
      );
    }

    // Add height constraint if specified
    if (widget.maxHeight != null) {
      dataTable = SizedBox(
        height: widget.maxHeight,
        child: dataTable,
      );
    }

    // Apply decoration if provided
    if (widget.decoration != null) {
      dataTable = Container(
        decoration: widget.decoration,
        child: dataTable,
      );
    } else {
      // Default card styling
      dataTable = Card(
        elevation: AppConstants.cardElevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
        child: dataTable,
      );
    }

    return dataTable;
  }
}

/// A paginated data table wrapper with search and filtering capabilities
class PaginatedDataTableWrapper<T> extends StatefulWidget {
  /// The source data for the table
  final List<T> data;
  
  /// Function to build columns
  final List<DataColumn> Function() columnBuilder;
  
  /// Function to build rows from data items
  final DataRow Function(T item, int index) rowBuilder;
  
  /// Items per page
  final int rowsPerPage;
  
  /// Available rows per page options
  final List<int> availableRowsPerPage;
  
  /// Search hint text
  final String? searchHint;
  
  /// Function to filter data based on search query
  final bool Function(T item, String query)? searchFilter;
  
  /// Additional filters
  final Map<String, bool Function(T item)>? filters;
  
  /// Whether columns can be sorted
  final bool sortable;
  
  /// Initial sort column index
  final int? initialSortColumn;
  
  /// Initial sort direction
  final bool initialSortAscending;

  const PaginatedDataTableWrapper({
    super.key,
    required this.data,
    required this.columnBuilder,
    required this.rowBuilder,
    this.rowsPerPage = 10,
    this.availableRowsPerPage = const [5, 10, 20, 50],
    this.searchHint,
    this.searchFilter,
    this.filters,
    this.sortable = true,
    this.initialSortColumn,
    this.initialSortAscending = true,
  });

  @override
  State<PaginatedDataTableWrapper<T>> createState() => _PaginatedDataTableWrapperState<T>();
}

class _PaginatedDataTableWrapperState<T> extends State<PaginatedDataTableWrapper<T>> {
  late TextEditingController _searchController;
  late List<T> _filteredData;
  late int _currentPage;
  late int _rowsPerPage;
  int? _sortColumnIndex;
  bool _sortAscending = true;
  final Map<String, bool> _activeFilters = {};

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredData = widget.data;
    _currentPage = 0;
    _rowsPerPage = widget.rowsPerPage;
    _sortColumnIndex = widget.initialSortColumn;
    _sortAscending = widget.initialSortAscending;
    
    // Initialize filters
    if (widget.filters != null) {
      for (final key in widget.filters!.keys) {
        _activeFilters[key] = false;
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _updateFilters() {
    setState(() {
      _filteredData = widget.data.where((item) {
        // Apply search filter
        if (_searchController.text.isNotEmpty && widget.searchFilter != null) {
          if (!widget.searchFilter!(item, _searchController.text.toLowerCase())) {
            return false;
          }
        }
        
        // Apply additional filters
        if (widget.filters != null) {
          for (final entry in widget.filters!.entries) {
            if (_activeFilters[entry.key] == true && !entry.value(item)) {
              return false;
            }
          }
        }
        
        return true;
      }).toList();
      
      _currentPage = 0; // Reset to first page when filtering
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalPages = (_filteredData.length / _rowsPerPage).ceil();
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, _filteredData.length);
    final pageData = _filteredData.sublist(startIndex, endIndex);

    return Card(
      elevation: AppConstants.cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search and filters row
          Padding(
            padding: const EdgeInsets.all(AppConstants.defaultPadding),
            child: Row(
              children: [
                // Search field
                if (widget.searchHint != null)
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: widget.searchHint,
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (_) => _updateFilters(),
                    ),
                  ),
                
                // Filter chips
                if (widget.filters != null) ...[
                  const SizedBox(width: 16),
                  Wrap(
                    spacing: 8,
                    children: widget.filters!.keys.map((filterKey) {
                      return FilterChip(
                        label: Text(filterKey),
                        selected: _activeFilters[filterKey] ?? false,
                        onSelected: (selected) {
                          _activeFilters[filterKey] = selected;
                          _updateFilters();
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          
          // Data table
          DataTableWrapper(
            columns: widget.columnBuilder(),
            rows: pageData.asMap().entries.map((entry) {
              return widget.rowBuilder(entry.value, startIndex + entry.key);
            }).toList(),
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            onSort: widget.sortable ? (columnIndex, ascending) {
              setState(() {
                _sortColumnIndex = columnIndex;
                _sortAscending = ascending;
                // Implement sorting logic here based on your data type
              });
            } : null,
            horizontalScrollable: true,
          ),
          
          // Pagination controls
          Padding(
            padding: const EdgeInsets.all(AppConstants.defaultPadding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${startIndex + 1}-$endIndex of ${_filteredData.length} items',
                  style: theme.textTheme.bodySmall,
                ),
                Row(
                  children: [
                    DropdownButton<int>(
                      value: _rowsPerPage,
                      items: widget.availableRowsPerPage.map((value) {
                        return DropdownMenuItem(
                          value: value,
                          child: Text('$value per page'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _rowsPerPage = value;
                            _currentPage = 0;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      onPressed: _currentPage > 0 ? () {
                        setState(() => _currentPage--);
                      } : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('${_currentPage + 1} / $totalPages'),
                    IconButton(
                      onPressed: _currentPage < totalPages - 1 ? () {
                        setState(() => _currentPage++);
                      } : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}