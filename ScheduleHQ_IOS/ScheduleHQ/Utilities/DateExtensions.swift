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
    
    // MARK: - Month Helpers (Calendar View)
    
    /// First day of the month for this date
    var startOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components) ?? self
    }
    
    /// Last day of the month for this date
    var endOfMonth: Date {
        let calendar = Calendar.current
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else { return self }
        return calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? self
    }
    
    /// Previous month's start date
    var previousMonthStart: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: startOfMonth) ?? startOfMonth
    }
    
    /// Next month's start date
    var nextMonthStart: Date {
        Calendar.current.date(byAdding: .month, value: 1, to: startOfMonth) ?? startOfMonth
    }
    
    /// All dates in the month containing this date
    var datesInMonth: [Date] {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: self) ?? 1..<2
        return range.compactMap { day in
            calendar.date(bySetting: .day, value: day, of: startOfMonth)
        }
    }
    
    /// All dates needed for a full calendar grid (includes leading/trailing days from adjacent months)
    var calendarGridDates: [Date] {
        let calendar = Calendar.current
        let firstDay = startOfMonth
        let lastDay = endOfMonth
        
        // Day of week for first day (1=Sunday, 7=Saturday)
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        
        // Leading days from previous month (to fill first row)
        let leadingDays = firstWeekday - 1 // Sunday = 0 leading days
        var dates: [Date] = []
        
        for i in stride(from: leadingDays, through: 1, by: -1) {
            if let date = calendar.date(byAdding: .day, value: -i, to: firstDay) {
                dates.append(date)
            }
        }
        
        // All days in current month
        dates.append(contentsOf: datesInMonth)
        
        // Trailing days from next month (to fill last row)
        let remainingSlots = (7 - (dates.count % 7)) % 7
        if let dayAfterLast = calendar.date(byAdding: .day, value: 1, to: lastDay) {
            for i in 0..<remainingSlots {
                if let date = calendar.date(byAdding: .day, value: i, to: dayAfterLast) {
                    dates.append(date)
                }
            }
        }
        
        return dates
    }
    
    /// Formatted as "February 2026"
    var monthYearFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: self)
    }
    
    /// Whether this date is in the current month
    var isCurrentMonth: Bool {
        let calendar = Calendar.current
        return calendar.isDate(self, equalTo: Date(), toGranularity: .month)
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
