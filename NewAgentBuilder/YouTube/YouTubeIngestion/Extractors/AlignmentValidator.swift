//
//  AlignmentValidator.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/17/26.
//


// MARK: - Alignment Validator (unchanged)
struct AlignmentValidator {
    func validate(_ alignment: AlignmentData) -> (status: ValidationStatus, issues: [ValidationIssue]) {
        var issues: [ValidationIssue] = []
        
        // Check 1: Section count reasonable
        if alignment.sections.count < 2 {
            issues.append(ValidationIssue(
                severity: .error,
                type: .sectionCount,
                message: "Only \(alignment.sections.count) sections (expected 3-8)"
            ))
        }
        if alignment.sections.count > 12 {
            issues.append(ValidationIssue(
                severity: .warning,
                type: .sectionCount,
                message: "Many sections (\(alignment.sections.count)) - may be over-segmented"
            ))
        }
        
        // Check 2: Section boundaries valid (word indexes or time ranges)
        for i in 0..<alignment.sections.count-1 {
            let current = alignment.sections[i]
            let next = alignment.sections[i+1]

            // Check word boundaries (new format)
            if let currentEnd = current.endWordIndex, let nextStart = next.startWordIndex {
                if currentEnd >= nextStart {
                    issues.append(ValidationIssue(
                        severity: .error,
                        type: .timeOverlap,
                        message: "Section \(i) overlaps with \(i+1) (word indexes)"
                    ))
                }
                if currentEnd + 1 < nextStart {
                    issues.append(ValidationIssue(
                        severity: .warning,
                        type: .timeGap,
                        message: "Gap between sections \(i) and \(i+1) (word indexes)"
                    ))
                }
            }
            // Fall back to time range checks (legacy format)
            else if let currentTime = current.timeRange, let nextTime = next.timeRange {
                if currentTime.end > nextTime.start {
                    issues.append(ValidationIssue(
                        severity: .error,
                        type: .timeOverlap,
                        message: "Section \(i) overlaps with \(i+1)"
                    ))
                }
                if currentTime.end < nextTime.start - 5 {
                    issues.append(ValidationIssue(
                        severity: .warning,
                        type: .timeGap,
                        message: "Gap between sections \(i) and \(i+1)"
                    ))
                }
            }
        }
        
        // Check 3: Logic spine complete
        if alignment.logicSpine.chain.count != alignment.sections.count {
            issues.append(ValidationIssue(
                severity: .error,
                type: .incompleteSpine,
                message: "Logic spine has \(alignment.logicSpine.chain.count) steps but \(alignment.sections.count) sections"
            ))
        }
        
        // Check 4: Roles logical
        let roleSequence = alignment.sections.map { $0.role }
        if roleSequence.contains("PAYOFF") && !roleSequence.contains("HOOK") {
            issues.append(ValidationIssue(
                severity: .warning,
                type: .illogicalFlow,
                message: "PAYOFF without HOOK"
            ))
        }
        
        let status: ValidationStatus = issues.contains { $0.severity == .error } ? .failed : .passed
        
        return (status: status, issues: issues)
    }
}