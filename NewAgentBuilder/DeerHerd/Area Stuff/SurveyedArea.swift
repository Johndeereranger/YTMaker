//
//  SurveyedArea.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 12/4/25.
//


// MARK: - AreaCalculator.swift
// Utility for calculating surveyed area from pins and observations
// Provides multiple algorithms: Bounding Box, Convex Hull, Concave Hull, Buffer Union

import Foundation
import CoreLocation
import MapKit

struct SurveyedArea {
    let areaInSquareMeters: Double
    let areaInAcres: Double
    let boundaryCoordinates: [CLLocationCoordinate2D]
    let method: CalculationMethod
    
    enum CalculationMethod: String {
        case boundingBox = "Bounding Box"
        case convexHull = "Convex Hull"
        case concaveHull = "Concave Hull"
        case bufferUnion = "Buffer Union"
    }
    
    var description: String {
        String(format: "%.1f acres (%.0f sq m) via %@", areaInAcres, areaInSquareMeters, method.rawValue)
    }
}

class AreaCalculator {
    
    // MARK: - Public Interface
    
    /// Calculate area using all methods and return results
    static func calculateAllMethods(pins: [KMLPin], observations: [DeerObservation]) -> [SurveyedArea] {
        let points = combinePoints(pins: pins, observations: observations)
        guard points.count >= 3 else { return [] }
        
        return [
            calculateBoundingBox(points: points),
            calculateConvexHull(points: points),
            calculateConcaveHull(points: points, alpha: 0.15),
            calculateBufferUnion(points: points, bufferMeters: 50.0)
        ].compactMap { $0 }
    }
    
    /// Calculate using a specific method
    static func calculate(pins: [KMLPin], observations: [DeerObservation], method: SurveyedArea.CalculationMethod, bufferMeters: Double = 50.0) -> SurveyedArea? {
        let points = combinePoints(pins: pins, observations: observations)
        guard points.count >= 3 else { return nil }
        
        switch method {
        case .boundingBox:
            return calculateBoundingBox(points: points)
        case .convexHull:
            return calculateConvexHull(points: points)
        case .concaveHull:
            return calculateConcaveHull(points: points, alpha: 0.15)
        case .bufferUnion:
            return calculateBufferUnion(points: points, bufferMeters: bufferMeters)
        }
    }
    
    // MARK: - Method 1: Bounding Box (Simplest)
    
    private static func calculateBoundingBox(points: [CLLocationCoordinate2D]) -> SurveyedArea? {
        guard !points.isEmpty else { return nil }
        
        let minLat = points.map { $0.latitude }.min()!
        let maxLat = points.map { $0.latitude }.max()!
        let minLon = points.map { $0.longitude }.min()!
        let maxLon = points.map { $0.longitude }.max()!
        
        let boundary = [
            CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
            CLLocationCoordinate2D(latitude: maxLat, longitude: minLon),
            CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon),
            CLLocationCoordinate2D(latitude: minLat, longitude: maxLon)
        ]
        
        let area = polygonArea(coordinates: boundary)
        
        return SurveyedArea(
            areaInSquareMeters: area,
            areaInAcres: area / 4046.86,
            boundaryCoordinates: boundary,
            method: .boundingBox
        )
    }
    
    // MARK: - Method 2: Convex Hull (Standard GIS)
    
    private static func calculateConvexHull(points: [CLLocationCoordinate2D]) -> SurveyedArea? {
        guard points.count >= 3 else { return nil }
        
        // Graham Scan algorithm for convex hull
        let hull = grahamScan(points: points)
        guard hull.count >= 3 else { return nil }
        
        let area = polygonArea(coordinates: hull)
        
        return SurveyedArea(
            areaInSquareMeters: area,
            areaInAcres: area / 4046.86,
            boundaryCoordinates: hull,
            method: .convexHull
        )
    }
    
    // MARK: - Method 3: Concave Hull (Alpha Shape - More Accurate)
    
    private static func calculateConcaveHull(points: [CLLocationCoordinate2D], alpha: Double) -> SurveyedArea? {
        guard points.count >= 3 else { return nil }
        
        // For simplicity, using a convex hull with edge filtering based on alpha
        // A full alpha-shape would require Delaunay triangulation
        let hull = grahamScan(points: points)
        
        // Filter long edges (simplified concave approach)
        let maxEdgeLength = calculateMaxEdgeLength(points: points, alpha: alpha)
        let filtered = filterLongEdges(hull: hull, maxLength: maxEdgeLength)
        
        guard filtered.count >= 3 else { return calculateConvexHull(points: points) }
        
        let area = polygonArea(coordinates: filtered)
        
        return SurveyedArea(
            areaInSquareMeters: area,
            areaInAcres: area / 4046.86,
            boundaryCoordinates: filtered,
            method: .concaveHull
        )
    }
    
    // MARK: - Method 4: Buffer Union (Coverage-Based)
    
    private static func calculateBufferUnion(points: [CLLocationCoordinate2D], bufferMeters: Double) -> SurveyedArea? {
        guard points.count >= 1 else { return nil }
        
        // Create buffers around each point and calculate approximate total area
        // This is a simplified version - true buffer union requires computational geometry
        
        // Strategy: Use convex hull of buffered points
        var bufferedPoints: [CLLocationCoordinate2D] = []
        
        for point in points {
            // Add points around each location at bufferMeters distance
            let angles = stride(from: 0.0, to: 360.0, by: 30.0) // Every 30 degrees
            for angle in angles {
                let bearing = angle * .pi / 180.0
                let buffered = point.coordinate(at: bufferMeters, bearing: bearing)
                bufferedPoints.append(buffered)
            }
        }
        
        let hull = grahamScan(points: bufferedPoints)
        guard hull.count >= 3 else { return nil }
        
        let area = polygonArea(coordinates: hull)
        
        return SurveyedArea(
            areaInSquareMeters: area,
            areaInAcres: area / 4046.86,
            boundaryCoordinates: hull,
            method: .bufferUnion
        )
    }
    
    // MARK: - Helper Functions
    
    private static func combinePoints(pins: [KMLPin], observations: [DeerObservation]) -> [CLLocationCoordinate2D] {
        var points: [CLLocationCoordinate2D] = []
        points.append(contentsOf: pins.map { $0.coordinate })
        points.append(contentsOf: observations.map { $0.coordinate })
        return points
    }
    
    // Graham Scan for Convex Hull
    private static func grahamScan(points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard points.count >= 3 else { return points }
        
        // Find bottom-most point (or left-most if tied)
        let start = points.min { a, b in
            a.latitude != b.latitude ? a.latitude < b.latitude : a.longitude < b.longitude
        }!
        
        // Sort points by polar angle with respect to start point
        let sorted = points.sorted { a, b in
            let angleA = atan2(a.latitude - start.latitude, a.longitude - start.longitude)
            let angleB = atan2(b.latitude - start.latitude, b.longitude - start.longitude)
            return angleA < angleB
        }
        
        var hull: [CLLocationCoordinate2D] = []
        
        for point in sorted {
            // Remove points that make clockwise turn
            while hull.count >= 2 {
                let last = hull[hull.count - 1]
                let secondLast = hull[hull.count - 2]
                if crossProduct(secondLast, last, point) <= 0 {
                    hull.removeLast()
                } else {
                    break
                }
            }
            hull.append(point)
        }
        
        return hull
    }
    
    private static func crossProduct(_ o: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        return (a.longitude - o.longitude) * (b.latitude - o.latitude) -
               (a.latitude - o.latitude) * (b.longitude - o.longitude)
    }
    
    // Calculate polygon area using Shoelace formula
    private static func polygonArea(coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count >= 3 else { return 0 }
        
        // Convert to meters using first point as reference
        let reference = coordinates[0]
        var xyPoints: [(x: Double, y: Double)] = []
        
        for coord in coordinates {
            let x = CoordinateUtilities.shared.distance(
                from: reference,
                to: CLLocationCoordinate2D(latitude: reference.latitude, longitude: coord.longitude)
            )
            let y = CoordinateUtilities.shared.distance(
                from: reference,
                to: CLLocationCoordinate2D(latitude: coord.latitude, longitude: reference.longitude)
            )
            
            // Adjust sign based on direction
            let xSigned = coord.longitude > reference.longitude ? x : -x
            let ySigned = coord.latitude > reference.latitude ? y : -y
            
            xyPoints.append((xSigned, ySigned))
        }
        
        // Shoelace formula
        var area = 0.0
        let n = xyPoints.count
        
        for i in 0..<n {
            let j = (i + 1) % n
            area += xyPoints[i].x * xyPoints[j].y
            area -= xyPoints[j].x * xyPoints[i].y
        }
        
        return abs(area) / 2.0
    }
    
    // For concave hull - calculate max edge length
    private static func calculateMaxEdgeLength(points: [CLLocationCoordinate2D], alpha: Double) -> Double {
        var distances: [Double] = []
        
        for i in 0..<points.count {
            for j in (i+1)..<points.count {
                let dist = CoordinateUtilities.shared.distance(from: points[i], to: points[j])
                distances.append(dist)
            }
        }
        
        distances.sort()
        let percentileIndex = Int(Double(distances.count) * (1.0 - alpha))
        return distances[min(percentileIndex, distances.count - 1)]
    }
    
    // Filter edges longer than threshold
    private static func filterLongEdges(hull: [CLLocationCoordinate2D], maxLength: Double) -> [CLLocationCoordinate2D] {
        guard hull.count >= 3 else { return hull }
        
        var filtered: [CLLocationCoordinate2D] = [hull[0]]
        
        for i in 1..<hull.count {
            let distance = CoordinateUtilities.shared.distance(from: filtered.last!, to: hull[i])
            if distance <= maxLength {
                filtered.append(hull[i])
            }
        }
        
        // Check closing edge
        if let first = filtered.first, let last = filtered.last {
            let closingDist = CoordinateUtilities.shared.distance(from: last, to: first)
            if closingDist > maxLength {
                // If closing edge is too long, fall back to convex hull
                return hull
            }
        }
        
        return filtered
    }
}

// MARK: - CLLocationCoordinate2D Extension

extension CLLocationCoordinate2D {
    /// Calculate a new coordinate at a given distance and bearing
    func coordinate(at distance: Double, bearing: Double) -> CLLocationCoordinate2D {
        let R = 6371000.0 // Earth's radius in meters
        let lat1 = latitude * .pi / 180.0
        let lon1 = longitude * .pi / 180.0
        
        let lat2 = asin(sin(lat1) * cos(distance / R) +
                       cos(lat1) * sin(distance / R) * cos(bearing))
        
        let lon2 = lon1 + atan2(sin(bearing) * sin(distance / R) * cos(lat1),
                               cos(distance / R) - sin(lat1) * sin(lat2))
        
        return CLLocationCoordinate2D(
            latitude: lat2 * 180.0 / .pi,
            longitude: lon2 * 180.0 / .pi
        )
    }
}