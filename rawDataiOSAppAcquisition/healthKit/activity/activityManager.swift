//
//  activityManager.swift
//  rawDataiOSAppAcquisition
//
//  Created by Irnu Suryohadi Kusumo on 03.09.24.
//

import HealthKit
import Foundation
import SwiftUI

class ActivityManager: ObservableObject {
    let healthStore = HKHealthStore()
    
    @Published var stepCountData: [HKQuantitySample] = []
    @Published var activeEnergyBurnedData: [HKQuantitySample] = []
    @Published var appleMoveTimeData: [HKQuantitySample] = []
    @Published var appleStandTimeData: [HKQuantitySample] = []
    @Published var distanceWalkingRunningData: [HKQuantitySample] = []
    @Published var appleExerciseTimeData: [HKQuantitySample] = []
    @Published var savedFilePath: String?
    
    let baseFolder: String = "ActivityData"
    
    @Published var startDate: Date
    @Published var endDate: Date
    
    private var dataCache: [HKQuantityTypeIdentifier: [HKQuantitySample]] = [:]
    private let backgroundQueue = DispatchQueue(label: "com.activityManager.backgroundQueue", attributes: .concurrent)
    
    init(startDate: Date, endDate: Date) {
        self.startDate = startDate
        self.endDate = endDate
        requestAuthorization()
    }
    
    func requestAuthorization() {
        let typesToRead: Set<HKQuantityType> = [
            .quantityType(forIdentifier: .stepCount)!,
            .quantityType(forIdentifier: .activeEnergyBurned)!,
            .quantityType(forIdentifier: .appleMoveTime)!,
            .quantityType(forIdentifier: .appleStandTime)!,
            .quantityType(forIdentifier: .distanceWalkingRunning)!,
            .quantityType(forIdentifier: .appleExerciseTime)!
        ]
        
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, error in
            if !success {
                print("Authorization failed: \(String(describing: error?.localizedDescription))")
            } else {
                print("Authorization succeeded")
            }
        }
    }
    
    func fetchActivityData(startDate: Date, endDate: Date) {
        dataCache.removeAll()
        
        fetchData(identifier: .stepCount, startDate: startDate, endDate: endDate) { [weak self] result in
            DispatchQueue.main.async {
                self?.stepCountData = result
            }
        }
        
        fetchData(identifier: .activeEnergyBurned, startDate: startDate, endDate: endDate) { [weak self] result in
            DispatchQueue.main.async {
                self?.activeEnergyBurnedData = result
            }
        }
        
        fetchData(identifier: .appleMoveTime, startDate: startDate, endDate: endDate) { [weak self] result in
            DispatchQueue.main.async {
                self?.appleMoveTimeData = result
            }
        }
        
        fetchData(identifier: .appleStandTime, startDate: startDate, endDate: endDate) { [weak self] result in
            DispatchQueue.main.async {
                self?.appleStandTimeData = result
            }
        }
        
        fetchData(identifier: .distanceWalkingRunning, startDate: startDate, endDate: endDate) { [weak self] result in
            DispatchQueue.main.async {
                self?.distanceWalkingRunningData = result
            }
        }
        
        fetchData(identifier: .appleExerciseTime, startDate: startDate, endDate: endDate) { [weak self] result in
            DispatchQueue.main.async {
                self?.appleExerciseTimeData = result
            }
        }
    }
    
    private func fetchData(identifier: HKQuantityTypeIdentifier, startDate: Date, endDate: Date, completion: @escaping ([HKQuantitySample]) -> Void) {
        if let cachedData = dataCache[identifier] {
            completion(cachedData)
            return
        }
        
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            print("\(identifier.rawValue) Type is unavailable")
            completion([])
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [weak self] _, samples, error in
            if let error = error {
                print("Failed to fetch \(identifier.rawValue) data: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let quantitySamples = samples as? [HKQuantitySample] else {
                completion([])
                return
            }
            
            self?.dataCache[identifier] = quantitySamples
            completion(quantitySamples)
        }
        
        backgroundQueue.async {
            self.healthStore.execute(query)
        }
    }
    
    func saveDataAsCSV(serverURL: URL) {
        backgroundQueue.async {
            self.saveCSV(for: self.stepCountData , fileName: "step_count_data.csv", valueUnit: HKUnit.count(), unitLabel: "Step Counts", serverURL: serverURL, baseFolder: self.baseFolder, shouldRound: true)
            self.saveCSV(for: self.activeEnergyBurnedData, fileName: "active_energy_burned_data.csv", valueUnit: HKUnit.largeCalorie(), multiplier: 1.0, unitLabel: "Kilo Calories", serverURL: serverURL, baseFolder: self.baseFolder, shouldRound: false)
            self.saveCSV(for: self.appleMoveTimeData, fileName: "move_time_data.csv", valueUnit: HKUnit.minute(), unitLabel: "Minutes", serverURL: serverURL, baseFolder: self.baseFolder, shouldRound: true)
            self.saveCSV(for: self.appleStandTimeData, fileName: "apple_stand_time_data.csv", valueUnit: HKUnit.minute(), unitLabel: "Minutes", serverURL: serverURL, baseFolder: self.baseFolder, shouldRound: true)
            self.saveCSV(for: self.distanceWalkingRunningData, fileName: "distance_walking_running_data.csv", valueUnit: HKUnit.meterUnit(with: .kilo), unitLabel: "Kilometers", serverURL: serverURL, baseFolder: self.baseFolder, shouldRound: false)
            self.saveCSV(for: self.appleExerciseTimeData, fileName: "exercise_time_data.csv", valueUnit: HKUnit.minute(), unitLabel: "Minutes", serverURL: serverURL, baseFolder: self.baseFolder, shouldRound: true)
        }
    }
    
    private func saveCSV(for samples: [HKQuantitySample], fileName: String, valueUnit: HKUnit, multiplier: Double = 1.0, unitLabel: String, serverURL: URL, baseFolder: String, shouldRound: Bool = false) {
        var csvString = "Recorded Date and Time,Value (\(unitLabel))\n"
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = TimeZone.current
        
        for sample in samples {
            let value = sample.quantity.doubleValue(for: valueUnit) * multiplier
            let finalValue: String
            
            if shouldRound {
                finalValue = "\(Int(value))"
            } else {
                finalValue = String(format: "%.2f", value)
            }
            
            let date = sample.endDate
            let dateString = dateFormatter.string(from: date)
            csvString += "\(dateString),\(finalValue)\n"
        }
        
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Documents directory not found")
            return
        }
        
        let folderURL = documentsDirectory.appendingPathComponent(baseFolder)
        
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create directory: \(error)")
            return
        }
        
        let fileURL = folderURL.appendingPathComponent(fileName)
        
        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            DispatchQueue.main.async {
                print("File saved locally at \(fileURL.path)")
                self.savedFilePath = fileURL.path
                
                self.uploadFile(fileURL: fileURL, serverURL: serverURL, category: self.baseFolder)
            }
        } catch {
            print("Failed to save file locally: \(error)")
        }
    }
    
    func uploadFile(fileURL: URL, serverURL: URL, category: String) {
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        let fileName = fileURL.lastPathComponent
        let mimeType = "text/csv"
        
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"category\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(category)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(try! Data(contentsOf: fileURL))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        let task = URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
            if let error = error {
                print("Error uploading file: \(error)")
                return
            }
            print("File uploaded successfully to server")
        }
        
        task.resume()
    }
}
