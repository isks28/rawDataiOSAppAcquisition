//
//  SixMinuteWalkTestManager.swift
//  rawDataiOSAppAcquisition
//
//  Created by Irnu Suryohadi Kusumo on 31.10.24.
//

import SwiftUI
import CoreMotion
import CoreLocation
import UserNotifications
import AudioToolbox
import AVFoundation

class SixMinuteWalkTestManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    private let pedometer = CMPedometer()
    @Published var isCollectingData = false
    @Published var stepCount: Int = 0
    @Published var distanceGPS: Double = 0.0
    @Published var distancePedometer: Double = 0.0
    @Published var averageActivePace: Double?
    @Published var currentPace: Double?
    @Published var currentCadence: Double?
    @Published var floorAscended: Int?
    @Published var floorDescended: Int?
    @Published var savedFilePath: String?
    @Published var stepLengthInMeters: Double = 0.7
    @Published var elapsedTime: TimeInterval = 0
    
    let baseFolder: String = "ProcessedStepCountsData"
    
    private var recordingMode: String = "Six-Minute-Walk Test"
    private var serverURL: URL?
    private var locationManager: CLLocationManager?
    private var previousLocation: CLLocation?
    private var timer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    override init() {
        super.init()
        setupLocationManager()
        requestNotificationPermissions()
        setupAppLifecycleObservers()
    }
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    @objc private func appDidEnterBackground() {
        print("App entered background")
        if isCollectingData {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "KeepDataCollectionActive") {
                UIApplication.shared.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
        }
    }
    
    @objc private func appWillEnterForeground() {
        print("App will enter foreground")
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    @objc private func appDidBecomeActive() {
        print("App became active")
    }

    private func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.requestAlwaysAuthorization()
        locationManager?.allowsBackgroundLocationUpdates = true
        locationManager?.pausesLocationUpdatesAutomatically = false
        locationManager?.startUpdatingLocation()
        locationManager?.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager?.distanceFilter = 4.9
    }

    private func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted.")
            } else {
                print("Notification permission denied.")
            }
        }
    }
    
    func showDataCollectionNotification(elapsedTime: Int, isFinalUpdate: Bool = false) {
        guard isCollectingData else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Six Minute Walk Test Running"
        content.body = "Elapsed Time: \(formattedTime(from: elapsedTime))"
        
        if isFinalUpdate {
            content.sound = .default
        }
        
        let request = UNNotificationRequest(identifier: "dataCollectionNotification", content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error showing notification: \(error)")
            }
        }
    }
        
    private func formattedTime(from seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func removeDataCollectionNotification() {
        let notificationCenter = UNUserNotificationCenter.current()
        let identifier = "dataCollectionNotification"
        
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func startStepCountCollection(serverURL: URL) {
        guard !isCollectingData else { return }

        self.serverURL = serverURL
        isCollectingData = true
        stepCount = 0
        distanceGPS = 0.0
        distancePedometer = 0.0
        averageActivePace = nil
        currentPace = nil
        currentCadence = nil
        floorAscended = nil
        floorDescended = nil
        recordingMode = "Six-Minute-Walk Test"
        let startTime = Date()
        var elapsedTime = 0

        previousLocation = nil
        locationManager?.startUpdatingLocation()
        
        playStartAlert()
        showDataCollectionNotification(elapsedTime: elapsedTime, isFinalUpdate: true)
        
        guard CMPedometer.isStepCountingAvailable() else {
            print("Step counting is not available on this device")
            return
        }

        pedometer.startUpdates(from: Date()) { [weak self] pedometerData, error in
            guard let pedometerData = pedometerData, error == nil else {
                print("Error fetching pedometer data: \(String(describing: error))")
                return
            }
            
            DispatchQueue.main.async {
                self?.stepCount = pedometerData.numberOfSteps.intValue
                self?.distancePedometer = Double(pedometerData.numberOfSteps.intValue) * (self?.stepLengthInMeters ?? 0.7)
                if let averageActivePace = pedometerData.averageActivePace?.doubleValue {
                    self?.averageActivePace = averageActivePace
                }
                if let currentPace = pedometerData.currentPace?.doubleValue {
                    self?.currentPace = currentPace
                }
                if let currentCadence = pedometerData.currentCadence?.doubleValue {
                    self?.currentCadence = currentCadence / 60
                }
                if let floorsAscended = pedometerData.floorsAscended?.intValue {
                    self?.floorAscended = floorsAscended
                }
                if let floorsDescended = pedometerData.floorsDescended?.intValue {
                    self?.floorDescended = floorsDescended
                }
            }
        }

        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SixMinuteWalkTest") {
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            
            elapsedTime = Int(Date().timeIntervalSince(startTime))
            self.showDataCollectionNotification(elapsedTime: elapsedTime)
            
            if elapsedTime >= 360 {
                timer.invalidate()
                self.showDataCollectionNotification(elapsedTime: elapsedTime, isFinalUpdate: true)
                self.stopStepCountCollection()
            }
        }
    }

    func stopStepCountCollection(saveData: Bool = true) {
        guard isCollectingData else {
            print("Data collection already stopped.")
            return
        }
        
        isCollectingData = false
        pedometer.stopUpdates()
        locationManager?.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil

        playEndAlert()
        removeDataCollectionNotification()
        
        if saveData, let serverURL = serverURL {
            saveDataToCSV(serverURL: serverURL, baseFolder: self.baseFolder, recordingMode: self.recordingMode)
        } else {
            print("Error: serverURL is nil. CSV will not be saved.")
        }
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    func saveDataToCSV(serverURL: URL, baseFolder: String, recordingMode: String) {
        print("Attempting to save data to CSV")
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Documents directory not found")
            return
        }

        let folderURL = documentsDirectory.appendingPathComponent(baseFolder).appendingPathComponent(recordingMode)
        
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create directory: \(error)")
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        dateFormatter.timeZone = TimeZone.current
        let formattedDate = dateFormatter.string(from: Date())

        let csvStepLengthHeader = "Step length: \(String(format: "%.0f", stepLengthInMeters * 100))\n"
        let csvHeader = "DataType,TimeStamp,StepCount,Distance GPS (m),Distance Pedometer (m),AverageActivePace (m/s),CurrentPace (m/s),CurrentCadence (steps/min),FloorsAscended,FloorsDescended\n"
        let csvData = "WalkingData,\(formattedDate),\(stepCount),\(distanceGPS),\(distancePedometer),\(averageActivePace ?? 0),\(currentPace ?? 0),\(currentCadence ?? 0),\(floorAscended ?? 0),\(floorDescended ?? 0)"
        
        let csvString = csvStepLengthHeader + csvHeader + csvData

        let fileName = "SixMinuteWalkTest_\(formattedDate).csv"
        let fileURL = folderURL.appendingPathComponent(fileName)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            print("File with the same data already exists: \(fileURL.path)")
            savedFilePath = fileURL.path
            return
        }

        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            savedFilePath = fileURL.path
            self.uploadFile(fileURL: fileURL, serverURL: serverURL, category: baseFolder)
        } catch {
            print("Failed to save file: \(error)")
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
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let newLocation = locations.last else { return }
            
        let movementThreshold: CLLocationDistance = 4.9
            
            if let previousLocation = previousLocation {
                let distanceInMeters = newLocation.distance(from: previousLocation)
                
                if distanceInMeters >= movementThreshold {
                    distanceGPS += distanceInMeters
                    self.previousLocation = newLocation
                } else {
                    print("Ignoring small movement: \(distanceInMeters) meters")
                }
            } else {
                previousLocation = newLocation
            }
        }
    
    func playStartAlert() {
        AudioServicesPlaySystemSound(1007)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
     
    func playEndAlert() {
        AudioServicesPlaySystemSound(1007)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        
        let content = UNMutableNotificationContent()
        content.title = "Six-Minute-Walk Test Completed"
        content.body = "The test has ended. Data has been saved."
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "endTestNotification", content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error showing end notification: \(error)")
            }
        }
    }
}
