import Foundation

/// Date utilities for schedule calculations
extension Date {
    /// Start of the week (Sunday) for this date
    var startOfWeek: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }
    
    /// End of the week (Saturday) for this date
    var endOfWeek: Date {
        let calendar = Calendar.current
        guard let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)),
              let end = calendar.date(byAdding: .day, value: 6, to: start) else {
            return self
        }
        // Set to end of day
        return calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
    }
    
    /// Start of day for this date
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    
    /// End of day for this date
    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay) ?? self
    }
    
    /// Previous week's start date
    var previousWeekStart: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: -1, to: startOfWeek) ?? startOfWeek
    }
    
    /// Next week's start date
    var nextWeekStart: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: 1, to: startOfWeek) ?? startOfWeek
    }
    
    /// Formatted as day abbreviation (e.g., "Mon")
    var dayAbbreviation: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: self)
    }
    
    /// Formatted as day number (e.g., "15")
    var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: self)
    }
    
    /// Formatted as month and day (e.g., "Jan 15")
    var monthDay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }
    
    /// Formatted as full date (e.g., "January 15, 2026")
    var fullDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: self)
    }
    
    /// Formatted week range (e.g., "Jan 12 - Jan 18, 2026")
    var weekRangeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "MMM d, yyyy"
        
        return "\(formatter.string(from: startOfWeek)) - \(yearFormatter.string(from: endOfWeek))"
    }
    
    /// All dates in the week containing this date
    var datesInWeek: [Date] {
        let start = startOfWeek
        return (0..<7).compactMap { dayOffset in
            Calendar.current.date(byAdding: .day, value: dayOffset, to: start)
        }
    }
    
    /// Whether this date is today
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    /// Whether this date is in the current week
    var isCurrentWeek: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .weekOfYear)
    }
    
    /// Year component
    var year: Int {
        Calendar.current.component(.year, from: self)
    }
    
    /// Month component (1-12)
    var month: Int {
        Calendar.current.component(.month, from: self)
    }
}

/// String extension for time formatting
extension String {
    /// Convert "HH:mm" string to formatted time (e.g., "9:00 AM")
    var formattedTime: String? {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "HH:mm"
        
        guard let date = inputFormatter.date(from: self) else { return nil }
        
        let outputFormatter = DateFormatter()
        outputFormatter.timeStyle = .short
        return outputFormatter.string(from: date)
    }
}
