import Foundation

/// Represents PTO summary for a trimester period
struct TrimesterSummary: Identifiable, Equatable {
    let id = UUID()
    let label: String           // "Trimester 1", "Trimester 2", "Trimester 3"
    let start: Date
    let end: Date
    let earned: Int             // Always 30 hours per trimester
    let carryoverIn: Int        // From previous trimester
    let available: Int          // earned + carryover (max 40)
    let used: Int
    let remaining: Int
    let carryoverOut: Int       // min(remaining, 10)
    
    /// Whether this is the current trimester
    var isCurrent: Bool {
        let now = Date()
        return now >= start && now <= end
    }
    
    /// Progress towards using available PTO (0.0 - 1.0)
    var usageProgress: Double {
        guard available > 0 else { return 0 }
        return Double(used) / Double(available)
    }
    
    /// Formatted date range for display
    var formattedDateRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
    
    /// Create trimester summaries for a given year
    static func forYear(_ year: Int, ptoUsed: [Date: Int]) -> [TrimesterSummary] {
        let calendar = Calendar.current
        
        // Trimester boundaries
        let t1Start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let t1End = calendar.date(from: DateComponents(year: year, month: 4, day: 30))!
        
        let t2Start = calendar.date(from: DateComponents(year: year, month: 5, day: 1))!
        let t2End = calendar.date(from: DateComponents(year: year, month: 8, day: 31))!
        
        let t3Start = calendar.date(from: DateComponents(year: year, month: 9, day: 1))!
        let t3End = calendar.date(from: DateComponents(year: year, month: 12, day: 31))!
        
        // Calculate used hours per trimester
        func hoursUsed(from start: Date, to end: Date) -> Int {
            ptoUsed.filter { date, _ in
                date >= start && date <= end
            }.values.reduce(0, +)
        }
        
        let t1Used = hoursUsed(from: t1Start, to: t1End)
        let t2Used = hoursUsed(from: t2Start, to: t2End)
        let t3Used = hoursUsed(from: t3Start, to: t3End)
        
        // Build summaries with carryover logic
        let earned = 30
        let maxAvailable = 40
        let maxCarryover = 10
        
        // Trimester 1 (no carryover from previous year in this implementation)
        let t1Available = min(earned, maxAvailable)
        let t1Remaining = max(0, t1Available - t1Used)
        let t1CarryoverOut = min(t1Remaining, maxCarryover)
        
        // Trimester 2
        let t2Available = min(earned + t1CarryoverOut, maxAvailable)
        let t2Remaining = max(0, t2Available - t2Used)
        let t2CarryoverOut = min(t2Remaining, maxCarryover)
        
        // Trimester 3
        let t3Available = min(earned + t2CarryoverOut, maxAvailable)
        let t3Remaining = max(0, t3Available - t3Used)
        let t3CarryoverOut = min(t3Remaining, maxCarryover)
        
        return [
            TrimesterSummary(
                label: "Trimester 1",
                start: t1Start,
                end: t1End,
                earned: earned,
                carryoverIn: 0,
                available: t1Available,
                used: t1Used,
                remaining: t1Remaining,
                carryoverOut: t1CarryoverOut
            ),
            TrimesterSummary(
                label: "Trimester 2",
                start: t2Start,
                end: t2End,
                earned: earned,
                carryoverIn: t1CarryoverOut,
                available: t2Available,
                used: t2Used,
                remaining: t2Remaining,
                carryoverOut: t2CarryoverOut
            ),
            TrimesterSummary(
                label: "Trimester 3",
                start: t3Start,
                end: t3End,
                earned: earned,
                carryoverIn: t2CarryoverOut,
                available: t3Available,
                used: t3Used,
                remaining: t3Remaining,
                carryoverOut: t3CarryoverOut
            )
        ]
    }
    
    /// Get the current trimester summary for a given year
    static func current(forYear year: Int, ptoUsed: [Date: Int]) -> TrimesterSummary? {
        forYear(year, ptoUsed: ptoUsed).first { $0.isCurrent }
    }
}
