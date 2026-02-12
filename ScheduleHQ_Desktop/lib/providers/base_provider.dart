import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../utils/app_constants.dart';

/// Base provider class with common functionality for all providers
abstract class BaseProvider extends ChangeNotifier {
  LoadingState _loadingState = LoadingState.idle;
  String? _errorMessage;
  DateTime? _lastUpdated;
  bool _notifyScheduled = false;

  /// Override [notifyListeners] so that it is always safe to call from any
  /// phase of the frame pipeline (build, layout, paint, semantics, or even
  /// from a non-platform thread callback).
  ///
  /// If we are currently inside a frame (anything other than
  /// [SchedulerPhase.idle] or [SchedulerPhase.postFrameCallbacks]),
  /// the notification is deferred to a post-frame callback so it never
  /// mutates the render tree while semantics are being computed.
  @override
  void notifyListeners() {
    // Fast path: if the scheduler is idle or we're already in
    // post-frame callbacks, it's safe to notify immediately.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      super.notifyListeners();
      return;
    }

    // We are mid-frame (build / layout / paint / semantics).
    // Defer notification to after this frame finishes.
    if (!_notifyScheduled) {
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        super.notifyListeners();
      });
    }
  }
  
  /// Current loading state
  LoadingState get loadingState => _loadingState;
  
  /// Current error message (if any)
  String? get errorMessage => _errorMessage;
  
  /// Last time the data was updated
  DateTime? get lastUpdated => _lastUpdated;
  
  /// Whether the provider is currently loading
  bool get isLoading => _loadingState == LoadingState.loading;
  
  /// Whether the provider has an error
  bool get hasError => _loadingState == LoadingState.error;
  
  /// Whether the provider has data that was successfully loaded
  bool get hasData => _loadingState == LoadingState.success && _lastUpdated != null;
  
  /// Whether the data is idle (not loaded yet)
  bool get isIdle => _loadingState == LoadingState.idle;

  /// Set the loading state and notify listeners
  @protected
  void setLoadingState(LoadingState state, {String? error}) {
    if (_loadingState != state) {
      _loadingState = state;
      
      if (state == LoadingState.error && error != null) {
        _errorMessage = error;
      } else if (state != LoadingState.error) {
        _errorMessage = null;
      }
      
      if (state == LoadingState.success) {
        _lastUpdated = DateTime.now();
      }
      
      notifyListeners();
    }
  }

  /// Execute an async operation with automatic state management
  @protected
  Future<T?> executeWithState<T>(Future<T> Function() operation, {
    String? errorPrefix,
  }) async {
    if (_loadingState == LoadingState.loading) return null;
    
    try {
      setLoadingState(LoadingState.loading);
      final result = await operation();
      setLoadingState(LoadingState.success);
      return result;
    } catch (error) {
      final errorMessage = errorPrefix != null 
          ? '$errorPrefix: ${error.toString()}'
          : error.toString();
      setLoadingState(LoadingState.error, error: errorMessage);
      debugPrint('Error in ${runtimeType}: $errorMessage');
      return null;
    }
  }

  /// Clear any error state
  void clearError() {
    if (_loadingState == LoadingState.error) {
      setLoadingState(LoadingState.idle);
    }
  }

  /// Set an error message and update state
  @protected
  void setErrorMessage(String message) {
    setLoadingState(LoadingState.error, error: message);
  }

  /// Execute an async operation with loading state
  Future<T?> executeWithLoading<T>(Future<T> Function() operation, {
    String? errorPrefix,
  }) async {
    return executeWithState(operation, errorPrefix: errorPrefix);
  }

  /// Show a success message (override in subclasses for custom implementation)
  @protected
  void showSuccessMessage(String message) {
    // Base implementation - can be overridden
    debugPrint('Success: $message');
  }

  /// Refresh the data (should be implemented by subclasses)
  Future<void> refresh();

  /// Get a human-readable loading message for the current state
  String getLoadingMessage() {
    switch (_loadingState) {
      case LoadingState.idle:
        return 'Ready to load';
      case LoadingState.loading:
        return 'Loading...';
      case LoadingState.success:
        return _lastUpdated != null 
            ? 'Last updated: ${_formatTime(_lastUpdated!)}'
            : 'Loaded successfully';
      case LoadingState.error:
        return _errorMessage ?? 'An error occurred';
    }
  }

  /// Format time for display
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  /// Reset the provider to its initial state
  @protected
  void reset() {
    _loadingState = LoadingState.idle;
    _errorMessage = null;
    _lastUpdated = null;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}

/// Mixin for providers that handle lists of data with CRUD operations
mixin CrudProviderMixin<T> on BaseProvider {
  List<T> _items = [];
  T? _selectedItem;
  
  /// All items in the list
  List<T> get items => List.unmodifiable(_items);
  
  /// Currently selected item
  T? get selectedItem => _selectedItem;
  
  /// Number of items in the list
  int get itemCount => _items.length;
  
  /// Whether the list is empty
  bool get isEmpty => _items.isEmpty;
  
  /// Whether the list has any items
  bool get isNotEmpty => _items.isNotEmpty;

  /// Set the items list
  @protected
  void setItems(List<T> items) {
    _items = List.from(items);
    notifyListeners();
  }

  /// Add an item to the list
  @protected
  void addItem(T item) {
    _items.add(item);
    notifyListeners();
  }

  /// Update an item in the list
  @protected
  void updateItem(T oldItem, T newItem) {
    final index = _items.indexOf(oldItem);
    if (index != -1) {
      _items[index] = newItem;
      if (_selectedItem == oldItem) {
        _selectedItem = newItem;
      }
      notifyListeners();
    }
  }

  /// Remove an item from the list
  @protected
  void removeItem(T item) {
    _items.remove(item);
    if (_selectedItem == item) {
      _selectedItem = null;
    }
    notifyListeners();
  }

  /// Set the selected item
  void selectItem(T? item) {
    if (_selectedItem != item) {
      _selectedItem = item;
      notifyListeners();
    }
  }

  /// Clear the selected item
  void clearSelection() {
    selectItem(null);
  }

  /// Find an item by predicate
  T? findItem(bool Function(T item) predicate) {
    try {
      return _items.firstWhere(predicate);
    } catch (e) {
      return null;
    }
  }

  /// Filter items by predicate
  List<T> filterItems(bool Function(T item) predicate) {
    return _items.where(predicate).toList();
  }

  /// Sort items by comparator
  void sortItems(int Function(T a, T b) compare) {
    _items.sort(compare);
    notifyListeners();
  }

  @override
  @protected
  void reset() {
    super.reset();
    _items.clear();
    _selectedItem = null;
  }
}

/// Mixin for providers that need search functionality
mixin SearchProviderMixin on BaseProvider {
  String _searchQuery = '';
  
  /// Current search query
  String get searchQuery => _searchQuery;
  
  /// Whether a search is active
  bool get isSearching => _searchQuery.isNotEmpty;

  /// Set the search query
  void setSearchQuery(String query) {
    if (_searchQuery != query) {
      _searchQuery = query.toLowerCase().trim();
      onSearchQueryChanged();
      notifyListeners();
    }
  }

  /// Clear the search query
  void clearSearch() {
    setSearchQuery('');
  }

  /// Called when the search query changes (override in subclasses)
  @protected
  void onSearchQueryChanged() {}

  @override
  @protected
  void reset() {
    super.reset();
    _searchQuery = '';
  }
}

/// Mixin for providers that support pagination
mixin PaginationProviderMixin on BaseProvider {
  int _currentPage = 0;
  int _itemsPerPage = 20;
  int _totalItems = 0;
  
  /// Current page index (0-based)
  int get currentPage => _currentPage;
  
  /// Items per page
  int get itemsPerPage => _itemsPerPage;
  
  /// Total number of items across all pages
  int get totalItems => _totalItems;
  
  /// Total number of pages
  int get totalPages => (_totalItems / _itemsPerPage).ceil();
  
  /// Whether there's a next page
  bool get hasNextPage => _currentPage < totalPages - 1;
  
  /// Whether there's a previous page
  bool get hasPreviousPage => _currentPage > 0;

  /// Set the current page (0-based)
  void setPage(int page) {
    if (page >= 0 && page < totalPages && page != _currentPage) {
      _currentPage = page;
      onPageChanged();
      notifyListeners();
    }
  }

  /// Go to the next page
  void nextPage() {
    if (hasNextPage) {
      setPage(_currentPage + 1);
    }
  }

  /// Go to the previous page
  void previousPage() {
    if (hasPreviousPage) {
      setPage(_currentPage - 1);
    }
  }

  /// Set items per page
  void setItemsPerPage(int count) {
    if (count > 0 && count != _itemsPerPage) {
      _itemsPerPage = count;
      _currentPage = 0; // Reset to first page
      onItemsPerPageChanged();
      notifyListeners();
    }
  }

  /// Set total items count
  @protected
  void setTotalItems(int count) {
    if (count >= 0 && count != _totalItems) {
      _totalItems = count;
      // Adjust current page if necessary
      if (_currentPage >= totalPages && totalPages > 0) {
        _currentPage = totalPages - 1;
      }
      notifyListeners();
    }
  }

  /// Called when the page changes (override in subclasses)
  @protected
  void onPageChanged() {}

  /// Called when items per page changes (override in subclasses)
  @protected
  void onItemsPerPageChanged() {}

  @override
  @protected
  void reset() {
    super.reset();
    _currentPage = 0;
    _totalItems = 0;
  }
}