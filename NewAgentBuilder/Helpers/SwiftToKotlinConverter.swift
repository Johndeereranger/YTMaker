//
//  SwiftToKotlinConverter.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 7/9/25.
//

import Foundation

// MARK: - Line-by-Line Swift to Kotlin Converter
class LineByLineSwiftConverter {
    
    init(debugMode: Bool) {
        self.DEBUG_MODE = debugMode
        print("Converter initialized with DEBUG_MODE = \(DEBUG_MODE)\n")
    }
    
    // MARK: - Debug Control (Change this to see debug output)
    private let DEBUG_MODE: Bool
    
    // MARK: - Debug Counter
    private var debugCounter = 0
    
    // MARK: - Processing State
    private struct ProcessingState {
        var currentVariable: String = ""
        var currentText: String = ""
        var currentStyle: String = ""
        var baselineOffset: Int? = nil
        var foregroundColor: String? = nil
        var isInMultilineString: Bool = false
        var isCurrentFromMultilineSource: Bool = false
        var multilineBuffer: String = ""
        var segments: [SwiftSegment] = []
        var currentSegmentIndex: Int = 0
    }
    
    // MARK: - Line Types
    enum LineType {
        case functionDeclaration
        case variableDeclaration
        case fontAssignment
        case baselineOffsetAssignment
        case foregroundColorAssignment
        case appendCall
        case multilineStringStart
        case multilineStringContinuation
        case multilineStringEnd
        case returnStatement
        case closingBrace
        case unknown
    }
    
    // MARK: - Main Conversion Function
    func convertSwiftFunction(_ swiftCode: String) -> String {
        debugCounter = 0
        let lines = swiftCode.components(separatedBy: "\n")
        
        debug("=== STARTING CONVERSION ===")
        debug("Total lines to process: \(lines.count)")
        
        guard let functionName = extractFunctionName(from: swiftCode) else {
            debug("ERROR: Could not extract function name")
            return generateErrorFunction("Could not extract function name")
        }
        
        debug("Function name extracted: \(functionName)")
        
        var state = ProcessingState()
        
        for (index, line) in lines.enumerated() {
            debug("\n--- Segment: \(state.currentSegmentIndex + 1) LINE \(index + 1) ---")
            debug("Raw line: '\(line)'")
            
            let trimmedLine = String(line.drop(while: { $0.isWhitespace }))
            debug("Trimmed line: '\(trimmedLine)'")
            
            let lineType = classifyLine(trimmedLine)
            debug("Line type: \(lineType)")
            
            processLine(trimmedLine, type: lineType, state: &state, lineNumber: index + 1, lines: lines)
        }
        
        // Process any remaining variable
        if !state.currentVariable.isEmpty {
            debug("Processing final variable: \(state.currentVariable)")
            let segment = SwiftSegment(
                variableName: state.currentVariable,
                text: state.currentText,
                style: state.currentStyle,
                baselineOffset: state.baselineOffset,
                foregroundColor: state.foregroundColor,
                isMultilineSource: state.isCurrentFromMultilineSource
            )
            state.segments.append(segment)
            state.currentSegmentIndex += 1
        }
        
        debug("\n=== GENERATING KOTLIN ===")
        debug("Total segments to convert: \(state.segments.count)")
        
        return generateKotlinFunction(functionName: functionName, segments: state.segments)
    }
    
    // MARK: - Line Classification
    private func classifyLine(_ line: String) -> LineType {
        let classification: LineType
        if line.hasPrefix("//") {
            classification = .unknown
        } else if line.contains("func ") && line.contains("AttributedString") {
            classification = .functionDeclaration
        } else if line.contains("var ") && line.contains("AttributedString(") {
            if line.contains("AttributedString(\"\"\"") {
                classification = .multilineStringStart
            } else {
                classification = .variableDeclaration
            }
        } else if line.contains(".font = ") {
            classification = .fontAssignment
        } else if line.contains(".baselineOffset = ") {
            classification = .baselineOffsetAssignment
        } else if line.contains(".foregroundColor = ") {
            classification = .foregroundColorAssignment
        } else if line.contains(".append(") {
            classification = .appendCall
        } else if line.contains("\"\"\")") {
            classification = .multilineStringEnd
        } else if line.contains("return ") {
            classification = .returnStatement
        } else if line == "}" {
            classification = .closingBrace
        } else if line.isEmpty {
            classification = .unknown
        } else {
            // Could be multiline string continuation
            classification = .multilineStringContinuation
        }
        
        debug("Classified as: \(classification)")
        return classification
    }
    
    // MARK: - Line Processing
    //private func processLine(_ line: String, type: LineType, state: inout ProcessingState, lineNumber: Int) {
        private func processLine(_ line: String, type: LineType, state: inout ProcessingState, lineNumber: Int, lines: [String]){
        switch type {
        case .functionDeclaration:
            debug("Processing function declaration - skipping")
            
        case .variableDeclaration:
            debug("Processing variable declaration")
            // Save previous variable if exists
            if !state.currentVariable.isEmpty {
                debug("Saving previous variable: \(state.currentVariable)")
                let segment = SwiftSegment(
                    variableName: state.currentVariable,
                    text: state.currentText,
                    style: state.currentStyle,
                    baselineOffset: state.baselineOffset,
                    foregroundColor: state.foregroundColor,
                    isMultilineSource: state.isCurrentFromMultilineSource
                )
                state.segments.append(segment)
                state.currentSegmentIndex += 1
            }
            
            // Extract new variable
            state.currentVariable = extractVariableName(from: line)
            state.currentText = extractSimpleText(from: line)
            state.currentStyle = ".body" // default
            state.baselineOffset = nil
            state.foregroundColor = nil
            state.isCurrentFromMultilineSource = false
            
            debug("New variable: '\(state.currentVariable)'")
            debug("Extracted text: '\(state.currentText)'")
            
        case .multilineStringStart:
            debug("Processing multiline string start")
            // Save previous variable if exists
            if !state.currentVariable.isEmpty {
                debug("Saving previous variable before multiline: \(state.currentVariable)")
                let segment = SwiftSegment(
                    variableName: state.currentVariable,
                    text: state.currentText,
                    style: state.currentStyle,
                    baselineOffset: state.baselineOffset,
                    foregroundColor: state.foregroundColor,
                    isMultilineSource: state.isCurrentFromMultilineSource
                )
                state.segments.append(segment)
                state.currentSegmentIndex += 1
            }
            
            state.currentVariable = extractVariableName(from: line)
            state.isInMultilineString = true
            state.multilineBuffer = extractMultilineStart(from: line)
            state.currentStyle = ".body"
            state.baselineOffset = nil
            state.foregroundColor = nil
            state.isCurrentFromMultilineSource = true
            
            debug("Multiline variable: '\(state.currentVariable)'")
            debug("Multiline start: '\(state.multilineBuffer)'")
            
//        case .multilineStringContinuation:
//            if state.isInMultilineString {
//                debug("Adding to multiline buffer: '\(line)'")
//                state.multilineBuffer += line + "\n"
//            } else {
//                debug("Not in multiline string - ignoring continuation")
//            }
        case .multilineStringContinuation:
            if state.isInMultilineString {
                debug("Adding to multiline buffer: '\(line)' \(state.currentSegmentIndex + 1)")
                debug("Line ends with space: \(line.last == " " ? "YES" : "NO")")
                debug("Line length: \(line.count)")
                debug("Last character: '\(line.last ?? Character(" "))'")
                
                state.multilineBuffer += line
                
                // ✅ Look ahead to next line
                let nextIndex = lineNumber
                if nextIndex < lines.count {
                    let nextLine = lines[nextIndex].trimmingCharacters(in: .whitespaces)
                    debug("Next line (index \(nextIndex)): '\(nextLine)'")
                    debug("Next line contains triple quotes: \(nextLine.contains("\"\"\"") ? "YES" : "NO")")
                    
                    if !nextLine.contains("\"\"\"") {
                        // Next line is continuation, add newline
                        state.multilineBuffer += "\n"
                        debug("✅ ADDED newline (next line is continuation)")
                    } else {
                        debug("⏭️ SKIPPED newline (next line is multiline end)")
                    }
                } else {
                    debug("⚠️ No next line found - at end of input")
                }
                
                debug("Current buffer after processing: '\(state.multilineBuffer)'")
                debug("Buffer ends with newline: \(state.multilineBuffer.hasSuffix("\n") ? "YES" : "NO")")
            } else {
                debug("Not in multiline string - ignoring continuation")
            }
            
            
     
            
        case .multilineStringEnd:
            if state.isInMultilineString {
                debug("Processing multiline string end")
                let endText = extractMultilineEnd(from: line)
                state.multilineBuffer += endText
                state.currentText = state.multilineBuffer//.trimmingCharacters(in: .whitespacesAndNewlines)
                state.isInMultilineString = true
                state.multilineBuffer = ""
                debug("Final multiline text: '\(state.currentText)'")
            } else {
                debug("Not in multiline string - ignoring end")
            }
            
        case .fontAssignment:
            debug("Processing font assignment")
            let oldStyle = state.currentStyle
            state.currentStyle = extractStyle(from: line)
            debug("Style changed from '\(oldStyle)' to '\(state.currentStyle)'")
            
        case .baselineOffsetAssignment:
            debug("Processing baseline offset assignment")
            state.baselineOffset = extractBaselineOffset(from: line)
            debug("Baseline offset set to: \(state.baselineOffset ?? -1)")
            
        case .foregroundColorAssignment:
            debug("Processing foreground color assignment")
            let oldColor = state.foregroundColor ?? "none"
            state.foregroundColor = extractForegroundColor(from: line)
            debug("Color changed from '\(oldColor)' to '\(state.foregroundColor ?? "none")'")
            
        case .appendCall:
            debug("Processing append call")
            // Save current variable before processing append
            if !state.currentVariable.isEmpty {
                debug("Saving variable before append: \(state.currentVariable)")
                let segment = SwiftSegment(
                    variableName: state.currentVariable,
                    text: state.currentText,
                    style: state.currentStyle,
                    baselineOffset: state.baselineOffset,
                    foregroundColor: state.foregroundColor,
                    isMultilineSource: state.isCurrentFromMultilineSource
                )
                state.segments.append(segment)
                state.currentSegmentIndex += 1
                
                // Reset state
                state.currentVariable = ""
                state.currentText = ""
                state.currentStyle = ""
                state.baselineOffset = nil
                state.foregroundColor = nil
                state.isCurrentFromMultilineSource = false
            }
            
        case .returnStatement:
            debug("Processing return statement - finishing up")
            
        case .closingBrace:
            debug("Processing closing brace - ignoring")
            
        case .unknown:
            if line.hasPrefix("//") {
                   debug("Skipping commented line: '\(line)'")
               } else {
                   debug("Unknown line type - ignoring")
               }
        }
    }
    
    // MARK: - Extraction Functions
    private func extractFunctionName(from swiftCode: String) -> String? {
        let lines = swiftCode.components(separatedBy: "\n")
        for line in lines {
            if line.contains("func ") && line.contains("() -> AttributedString") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let funcRange = trimmed.range(of: "func "),
                   let parenRange = trimmed.range(of: "()") {
                    let functionName = String(trimmed[funcRange.upperBound..<parenRange.lowerBound])
                    return functionName.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
    
    private func extractVariableName(from line: String) -> String {
        debug("Extracting variable name from: '\(line)'")
        if let varRange = line.range(of: "var "),
           let equalRange = line.range(of: " =") {
            let varName = String(line[varRange.upperBound..<equalRange.lowerBound])
            debug("Variable name extracted: '\(varName)'")
            return varName.trimmingCharacters(in: .whitespaces)
        }
        debug("Could not extract variable name")
        return "unknownVar"
    }
    
    private func extractSimpleText(from line: String) -> String {
        debug("Extracting simple text from: '\(line)'")
        if let startQuote = line.range(of: "AttributedString(\""),
           let endQuote = line.range(of: "\")") {
            let text = String(line[startQuote.upperBound..<endQuote.lowerBound])
            let processed = text.replacingOccurrences(of: "\\n", with: "\n")
            debug("Simple text extracted: '\(processed)'")
            return processed
        }
        debug("Could not extract simple text")
        return "TEXT_PLACEHOLDER"
    }
    
    private func extractMultilineStart(from line: String) -> String {
        debug("Extracting multiline start from: '\(line)'")
        if let startRange = line.range(of: "AttributedString(\"\"\"") {
            let afterStart = String(line[startRange.upperBound...])
            let cleaned = afterStart.trimmingCharacters(in: .whitespaces)
            debug("Multiline start extracted: '\(cleaned)'")
            return cleaned.isEmpty ? "" : cleaned + "\n"
        }
        debug("Could not extract multiline start")
        return ""
    }
    
    private func extractMultilineEnd(from line: String) -> String {
        debug("Extracting multiline end from: '\(line)'")
        if let endRange = line.range(of: "\"\"\")") {
            let beforeEnd = String(line[..<endRange.lowerBound])
            debug("Multiline end extracted: '\(beforeEnd)'")
            return beforeEnd
        }
        debug("Could not extract multiline end")
        return ""
    }
    


    private func extractStyle(from line: String) -> String {
        debug("Extracting style from: '\(line)'")
        if let fontRange = line.range(of: ".font = ") {
            var style = String(line[fontRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            
            // Clean up the style - remove comments
            if let commentRange = style.range(of: "//") {
                style = String(style[..<commentRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            
            debug("Style extracted: '\(style)'")
            return style
        }
        debug("Could not extract style")
        return ".body"
    }
    
    private func extractBaselineOffset(from line: String) -> Int? {
        debug("Extracting baseline offset from: '\(line)'")
        if let range = line.range(of: ".baselineOffset = ") {
            let numberString = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            let offset = Int(numberString)
            debug("Baseline offset extracted: \(offset ?? -1)")
            return offset
        }
        debug("Could not extract baseline offset")
        return nil
    }
    
    private func extractForegroundColorOLD(from line: String) -> String? {
        debug("Extracting foreground color from: '\(line)'")
        if let range = line.range(of: ".foregroundColor = ") {
            let color = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            debug("Foreground color extracted: '\(color)'")
            return color
        }
        debug("Could not extract foreground color")
        return nil
    }
    
    private func extractForegroundColor(from line: String) -> String? {
        debug("Extracting foreground color from: '\(line)'")
        if let range = line.range(of: ".foregroundColor = ") {
            var color = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            
            // Clean up color - remove comments
            if let commentRange = color.range(of: "//") {
                color = String(color[..<commentRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            
            debug("Foreground color extracted: '\(color)'")
            return color
        }
        debug("Could not extract foreground color")
        return nil
    }
    
    private func shouldInsertSpacer(between prev: SwiftSegment?, and current: SwiftSegment) -> Bool {
        guard let prev = prev else { return false }

        // Only consider adding space for .body-like styles (not headings, captions, scripture refs)
        if !prev.style.contains(".body") || !current.style.contains(".body") {
            return false
        }

        let prevEndsClean = !prev.text.hasSuffix(" ") && !prev.text.hasSuffix("\n")
        let currStartsClean = !current.text.hasPrefix(" ") && !current.text.hasPrefix("\n")

        let currentStartsWithPunctuation = current.text.first.map { ".!,?;:".contains($0) } ?? false

        // Only insert space if both ends are clean AND current doesn't start with punctuation
        return prevEndsClean && currStartsClean && !currentStartsWithPunctuation
    }
    
    // MARK: - Kotlin Generation
    private func generateKotlinFunction(functionName: String, segments: [SwiftSegment]) -> String {
        debug("Generating Kotlin function for: \(functionName)")
        debug("Number of segments: \(segments.count)")

        var kotlinCode = ""

        if functionName.contains("Day0") {
            kotlinCode += """
            import androidx.compose.runtime.Composable
            import androidx.compose.ui.text.AnnotatedString
            import androidx.compose.ui.text.SpanStyle
            import androidx.compose.ui.text.font.FontStyle
            import androidx.compose.ui.text.font.FontWeight
            import androidx.compose.ui.text.style.BaselineShift
            import androidx.compose.ui.graphics.Color
            import androidx.compose.ui.text.buildAnnotatedString
            import androidx.compose.ui.text.withStyle
            import com.livingworthyministries.forty.helpers.AppTypography
            import com.livingworthyministries.forty.helpers.AppTypography.appendStyled

            """
        }

        kotlinCode += """
            @Composable
            fun \(functionName)(): AnnotatedString {
                return buildAnnotatedString {

            """

        for (index, segment) in segments.enumerated() {
            debug("Processing segment \(index + 1): \(segment.variableName)")

            let kotlinStyle = mapStyleToKotlin(segment.style)
            let formattedText = formatTextForKotlin(segment.text, isMultilineSource: segment.isMultilineSource)

            if DEBUG_MODE {
                kotlinCode += """
                    // === DEBUG SEGMENT \(debugCounter + 1) ===
                    // Name: \(segment.variableName)
                    // isMultilineSource: \(segment.isMultilineSource)
                    // Input Style: \(segment.style)
                    // Kotlin Style: \(kotlinStyle)
                    // Original Text:
                    // \(segment.text.replacingOccurrences(of: "\n", with: "\\n"))
                    // Formatted Text:
                    // \(formattedText)
                    // ================================
                    
                    """
                debugCounter += 1
            }

            kotlinCode += "        val \(segment.variableName)Text = \(formattedText)\n"

            if segment.baselineOffset != nil || segment.foregroundColor != nil {
                kotlinCode += generateKotlinWithSpan(segment: segment, kotlinStyle: kotlinStyle)
            } else {
                kotlinCode += "        appendStyled(\(segment.variableName)Text, \(kotlinStyle))\n"
            }

            // ✅ Check if next segment exists and a spacer is needed
            if index < segments.count - 1 {
                let next = segments[index + 1]
                if shouldInsertSpacer(between: segment, and: next) {
                    kotlinCode += "        append(\" \")\n"
                }
            }

            kotlinCode += "\n"
        }

        kotlinCode += """
            }
        }

        """

        debug("Kotlin generation complete")
        return kotlinCode
    }
    private func generateKotlinFunctionOld(functionName: String, segments: [SwiftSegment]) -> String {
        debug("Generating Kotlin function for: \(functionName)")
        debug("Number of segments: \(segments.count)")
        
        var kotlinCode = ""

        if functionName.contains("Day0") {
            kotlinCode += """
        import androidx.compose.runtime.Composable
        import androidx.compose.ui.text.AnnotatedString
        import androidx.compose.ui.text.SpanStyle
        import androidx.compose.ui.text.font.FontStyle
        import androidx.compose.ui.text.font.FontWeight
        import androidx.compose.ui.text.style.BaselineShift
        import androidx.compose.ui.graphics.Color
        import androidx.compose.ui.text.buildAnnotatedString
        import androidx.compose.ui.text.withStyle
        import com.livingworthyministries.forty.helpers.AppTypography
        import com.livingworthyministries.forty.helpers.AppTypography.appendStyled

        """
        }

        kotlinCode += """
        @Composable
        fun \(functionName)(): AnnotatedString {
            return buildAnnotatedString {

        """
        
        for (index, segment) in segments.enumerated() {
            debug("Processing segment \(index + 1): \(segment.variableName)")
            
            let kotlinStyle = mapStyleToKotlin(segment.style)
            let formattedText = formatTextForKotlin(segment.text, isMultilineSource: segment.isMultilineSource)
            if DEBUG_MODE {
                kotlinCode += """
                    // === DEBUG SEGMENT \(debugCounter + 1) ===
                    // Name: \(segment.variableName)
                    // isMultilineSource: \(segment.isMultilineSource)
                    // Input Style: \(segment.style)
                    // Kotlin Style: \(kotlinStyle)
                    // Original Text:
                    // \(segment.text.replacingOccurrences(of: "\n", with: "\\n"))
                    // Formatted Text:
                    // \(formattedText)
                    // ================================
                    \n
                    """
                debugCounter += 1
            }
            kotlinCode += "        val \(segment.variableName)Text = \(formattedText)\n"
            
            if segment.baselineOffset != nil || segment.foregroundColor != nil {
                kotlinCode += generateKotlinWithSpan(segment: segment, kotlinStyle: kotlinStyle)
            } else {
                kotlinCode += "        appendStyled(\(segment.variableName)Text, \(kotlinStyle))\n"
            }
            
            kotlinCode += "\n"
        }
        
        kotlinCode += """
    }
}

"""
        
        debug("Kotlin generation complete")
        return kotlinCode
    }
    
    private func mapStyleToKotlin(_ iosStyle: String) -> String {
        let mapping: [String: String] = [
            ".largeTitle.bold()": "AppTypography.largeTitleStyle.copy(fontWeight = FontWeight.Bold)",
            ".title.bold()": "AppTypography.titleStyle.copy(fontWeight = FontWeight.Bold)",
            ".title.bold().italic()": "AppTypography.titleStyle.copy(fontWeight = FontWeight.Bold, fontStyle = FontStyle.Italic)",
            ".title": "AppTypography.titleStyle",
            ".title2.bold()": "AppTypography.title2Style.copy(fontWeight = FontWeight.Bold)",
            ".title2": "AppTypography.title2Style",
            ".title3.bold().italic()": "AppTypography.title3Style.copy(fontWeight = FontWeight.Bold, fontStyle = FontStyle.Italic)",
            ".title3": "AppTypography.title3Style",
            ".title3.bold()": "AppTypography.title3Style.copy(fontWeight = FontWeight.Bold)",
            ".headline.bold()": "AppTypography.headlineStyle.copy(fontWeight = FontWeight.Bold)",
            ".headline": "AppTypography.headlineStyle",
            ".body.bold()": "AppTypography.bodyStyle.copy(fontWeight = FontWeight.Bold)",
            ".body.italic()": "AppTypography.bodyStyle.copy(fontStyle = FontStyle.Italic)",
            ".body.bold().italic()": "AppTypography.bodyStyle.copy(fontWeight = FontWeight.Bold, fontStyle = FontStyle.Italic)",
            ".body.italic().bold()": "AppTypography.bodyStyle.copy(fontWeight = FontWeight.Bold, fontStyle = FontStyle.Italic)",
            ".body": "AppTypography.bodyStyle",
            ".caption": "AppTypography.captionStyle",
            ".italic(.caption)()": "AppTypography.captionStyle.copy(fontStyle = FontStyle.Italic)"
        ]
        
        let result = mapping[iosStyle] ?? "AppTypography.bodyStyle /* DEBUG: Unknown style \(iosStyle) */"
        debug("Style mapping: '\(iosStyle)' -> '\(result)'")
        
        
        if result.contains("/* DEBUG: Unknown style") {
            print("DEBUG")
        }
        return result
    }
    private func commentOutBlock(_ block: String) -> String {
        return block
            .split(separator: "\n")
            .map { "        // \($0)" }
            .joined(separator: "\n") + "\n"
    }
    
//    private func formatTextForKotlin(_ text: String, isMultilineSource: Bool) -> String {
//        let cleanedText = text.replacingOccurrences(of: "\\n", with: "\n")
//        
//        if isMultilineSource {
//            return formatMultilineTextForKotlin(cleanedText)
//        } else {
//            return formatSingleLineTextForKotlin(cleanedText)
//        }
//    }
    private func formatTextForKotlin(_ text: String, isMultilineSource: Bool) -> String {
        return isMultilineSource ? formatMultilineTextForKotlin(text) : formatSingleLineTextForKotlin(text)
    }


    // MARK: - Single Line Handler (Clean Mirror)
    private func formatSingleLineTextForKotlin(_ text: String) -> String {
        let escapedText = text
           
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escapedText)\""
    }

    // MARK: - Multiline Handler (Convert to Single Line)
    private func formatMultilineTextForKotlin2(_ text: String) -> String {
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        if DEBUG_MODE {
            return "\" Input: \(text)\nOutput: \"\(escapedText)\""
        } else {
            return "\"\(escapedText)\""
        }
    }
    // MARK: - Multiline Handler (Correct Escaping Only)
    private func formatMultilineTextForKotlin21(_ text: String) -> String {
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") // keep as escaped
        return "\"\(escapedText)\"" // DO NOT add actual newline here
    }
    
    private func formatMultilineTextForKotlin(_ text: String) -> String {
        let processedText = text
            .replacingOccurrences(of: "\\n", with: "\n") // Convert literal \n
        let finalText: String
        if processedText.hasSuffix("\n") && !processedText.hasSuffix("\n\n") {
            // Likely a single accidental newline — strip just 1
            finalText = String(processedText.dropLast())
        } else {
            // Preserve real paragraph endings
            finalText = processedText
        }
        
        let escapedText = processedText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")  // Then escape the actual newlines
            return "\"\(escapedText)\""
        
    }
    
    
    private func generateKotlinWithSpan(segment: SwiftSegment, kotlinStyle: String) -> String {
        var spanComponents: [String] = []
        
        if let baselineOffset = segment.baselineOffset {
            spanComponents.append("baselineShift = BaselineShift(0.3f)")
        }
        
        if let color = segment.foregroundColor {
            let kotlinColor = mapColorToKotlin(color)
            spanComponents.append("color = \(kotlinColor)")
        }
        
        let spanStyle = "SpanStyle(\(spanComponents.joined(separator: ", ")))"
        
        return """
        withStyle(\(kotlinStyle).toSpanStyle().merge(\(spanStyle))) {
            append(\(segment.variableName)Text)
        }
"""
    }
    
    private func mapColorToKotlin(_ iosColor: String) -> String {
        switch iosColor {
        case ".gray":
            return "Color.Gray"
        default:
            return "Color.Gray /* DEBUG: Unknown color \(iosColor) */"
        }
    }
    
    private func generateErrorFunction(_ error: String) -> String {
        return """
@Composable
private fun unknownFunction(): AnnotatedString {
    return buildAnnotatedString {
        val errorText = "Error: \(error)"
        appendStyled(errorText, AppTypography.bodyStyle)
    }
}

"""
    }
    
    // MARK: - Debug Function
    private func debug(_ message: String) {
        if DEBUG_MODE {
            print("DEBUG: \(message)")
        }
    }
}

// MARK: - Supporting Structures
struct SwiftSegment {
    let variableName: String
    let text: String
    let style: String
    let baselineOffset: Int?
    let foregroundColor: String?
    let isMultilineSource: Bool  // ADD THIS LINE
    
    init(variableName: String, text: String, style: String, baselineOffset: Int? = nil, foregroundColor: String? = nil, isMultilineSource: Bool = false) {  // ADD PARAMETER
        self.variableName = variableName
        self.text = text
        self.style = style
        self.baselineOffset = baselineOffset
        self.foregroundColor = foregroundColor
        self.isMultilineSource = isMultilineSource  // ADD THIS LINE
    }
}
