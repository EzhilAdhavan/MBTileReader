//
//  MapListViewController.swift
//  MaplySample
//
//  Created by Ezhil Adhavan on 10/12/22.
//

import UIKit
import UniformTypeIdentifiers


typealias CLLocationDictionary = [String: CLLocationDegrees]
class MapListViewController: UIViewController {

    @IBOutlet weak var listTableView: UITableView!
    static let mbtilesExt = "mbtiles"
    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private(set) var fileItems: [FileItem] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "List"
        
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addButtonAction))
        let mapButton = UIBarButtonItem(image: UIImage(systemName: "map")!, style: .plain, target: self, action: #selector(openMapAction))
        self.navigationItem.rightBarButtonItems = [addButton, mapButton]
        
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(onLongPress(gesture:)))
        longPressGesture.minimumPressDuration = 0.5
        self.listTableView.addGestureRecognizer(longPressGesture)
        
        self.fetchFiles()
    }
    
    @objc func addButtonAction() {
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = true
        documentPicker.modalPresentationStyle = .fullScreen
        self.present(documentPicker, animated: true)
    }
    
    @objc func openMapAction() {
        self.presentMapScreen()
    }
    
    @objc func onLongPress(gesture: UILongPressGestureRecognizer) {
        func shareFile(_ filePath: String) {
            let controller = UIActivityViewController(activityItems: [URL(filePath: filePath)], applicationActivities: nil)
            if UIDevice.current.userInterfaceIdiom == .pad {
                controller.popoverPresentationController?.sourceView = view
                controller.popoverPresentationController?.sourceRect = CGRect(x: UIScreen.main.bounds.size.width * 0.5, y: UIScreen.main.bounds.size.height * 0.5, width: 10, height: 10)
            }
            if self.presentedViewController == nil {
                self.present(controller, animated: true, completion: nil)
            }
        }
        
        let point = gesture.location(in: listTableView)
        guard let indexPath = listTableView.indexPathForRow(at: point) else { return }
        let item = fileItems[indexPath.row]
        shareFile(item.path)
    }
    
    private func fetchFiles() {
        var filelist = [FileItem]()
        var allFiles: [String] = []
        do {
            allFiles = try FileManager.default.contentsOfDirectory(atPath: documentsDir.path)
            guard allFiles.count > 0 else { return }
        } catch {
            print(error.localizedDescription)
        }
        allFiles.filter { !$0.hasPrefix(".") }.forEach { eachFile in
            let fullpath = documentsDir.appendingPathComponent(eachFile).path
            let pathExtension = URL(fileURLWithPath: fullpath).pathExtension.lowercased()
            if pathExtension == Self.mbtilesExt {
                var fileItem = FileItem(name: eachFile, path: fullpath)
                fileItem.storedLocation = self.getStoredLocation(eachFile)
                filelist.append(fileItem)
            }
        }
        self.fileItems = filelist
    }
    
    private func moveFiles(_ urls: [URL]) {
        let mbtilesUrls = self.removeNonMbtilesFile(urls)
        guard !mbtilesUrls.isEmpty else {
            print("No mbtiles url picked")
            return
        }
        mbtilesUrls.forEach { url in
            do {
                let destinationURL = documentsDir.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(atPath: destinationURL.path)
                    print("\nRemoved the same: \(destinationURL.path)\n")
                }
                try FileManager.default.moveItem(atPath: url.path, toPath: destinationURL.path)
                print("\nFile Moved from: \(url.path)\nto: \(destinationURL.path)\n")
            } catch {
                print("Error in FileSystem: \(error.localizedDescription)")
            }
        }
    }
    
    private func removeNonMbtilesFile(_ urls: [URL]) -> [URL] {
        var mbtilesUrls = [URL]()
        urls.forEach { url in
            let pathExtension = URL(fileURLWithPath: url.path).pathExtension.lowercased()
            if pathExtension != Self.mbtilesExt {
                do {
                    try FileManager.default.removeItem(atPath: url.path)
                    print("\nRemoved non mbtiles file: \(url.path)\n")
                } catch {
                    print("Error while removing file: \(error.localizedDescription)")
                }
            } else {
                mbtilesUrls.append(url)
            }
        }
        return mbtilesUrls
    }
    
    private func showFileDeleteAlert(with filePath: String, fileName: String, whichRow: Int) {
        let msg = "Are you sure you want to delete?"
        let alert = UIAlertController(title: "Delete \(fileName)?", message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { [weak self] (action) in
            self?.deleteFile(filePath: filePath, fileName: fileName, whichRow: whichRow)
        }))
        self.present(alert, animated: true, completion: nil)
    }
    
    private func deleteFile(filePath: String, fileName: String, whichRow: Int) {
        do {
            try FileManager.default.removeItem(atPath: filePath)
            fileItems.remove(at: whichRow)
            UserDefaults.standard.removeObject(forKey: fileName)
            self.listTableView.reloadData()
        } catch {
            print("Could not clear temp folder: \(error)")
        }
    }
    
    private func presentMapScreen(_ fileItem: FileItem? = nil, selectedLocation: CLLocationCoordinate2D? = nil) {
        let mapVC = MapViewController()
        mapVC.selectedFileItem = fileItem
        mapVC.selectedLocation = selectedLocation
        let naV = UINavigationController(rootViewController: mapVC)
        naV.modalPresentationStyle = .fullScreen
        self.present(naV, animated: true)
    }
    
    private func showLatLongAlert(_ fileItem: FileItem) {
        let alert = UIAlertController(title: "Latitude & Longitude", message: "Please enter known latitude & longitude of \(fileItem.name).", preferredStyle: .alert)
        alert.addTextField { latTexField in
            latTexField.placeholder = "Latitude"
            latTexField.keyboardType = .numbersAndPunctuation
            if let latitude = fileItem.storedLocation?.lat {
                latTexField.text =  "\(latitude)"
            }
        }
        alert.addTextField { lngTexField in
            lngTexField.placeholder = "Longitude"
            lngTexField.keyboardType = .numbersAndPunctuation
            if let longitude = fileItem.storedLocation?.long {
                lngTexField.text = "\(longitude)"
            }
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open Map", style: .default) { [weak self] _ in
            if let textFields = alert.textFields {
                let lat = textFields.first!
                let long = textFields.last!
                if let latitude = lat.text, !latitude.isEmpty, let longitude = long.text, !longitude.isEmpty {
                    let enteredLocation = CLLocationCoordinate2DMake(Double(latitude)!, Double(longitude)!)
                    print("enteredLocation: \(enteredLocation)")
                    self?.saveAndOpen(fileItem, selectedLocation: enteredLocation)
                } else {
                    self?.presentMapScreen(fileItem, selectedLocation: CLLocationCoordinate2DMake(0, 0))
                }
            }
        })
        self.present(alert, animated: true)
    }
    
    private func saveAndOpen(_ fileItem: FileItem, selectedLocation: CLLocationCoordinate2D) {
        UserDefaults.standard.setValue(selectedLocation.asDictionary, forKey: fileItem.name)
        UserDefaults.standard.synchronize()
        self.updateFileItem(fileItem, locationDictionary: selectedLocation.asDictionary)
        DispatchQueue.main.async { [weak self] in
            self?.listTableView.reloadData()
        }
        self.presentMapScreen(fileItem, selectedLocation: selectedLocation)
    }
    
    private func getStoredLocation(_ fileName: String) -> CLLocationDictionary? {
        return UserDefaults.standard.value(forKey: fileName) as? CLLocationDictionary
    }
    
    private func updateFileItem(_ fileItem: FileItem, locationDictionary: CLLocationDictionary) {
        let updatedFileItems = fileItems.compactMap { item in
            if item.name == fileItem.name {
                var _item = item
                _item.storedLocation = locationDictionary
                return _item
            } else {
                return item
            }
        }
        self.fileItems = updatedFileItems
    }
}

extension MapListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return fileItems.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let fileItem = fileItems[indexPath.row]
        cell.textLabel?.text = fileItem.name
        cell.detailTextLabel?.numberOfLines = 0
        let modifiedDate = DateFormatter.localizedString(from: fileItem.modificationDate,
                                                         dateStyle: .medium,
                                                         timeStyle: .medium)
        cell.detailTextLabel?.text = "\(modifiedDate)\n\n\(self.getStoredLocation(fileItem.name)?.toLatLngString ?? "No location stored")"
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        var fileItem = fileItems[indexPath.row]
        self.showLatLongAlert(fileItem)
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        let item = fileItems[indexPath.row]
        if (editingStyle == .delete) {
            self.showFileDeleteAlert(with: item.path, fileName: item.name, whichRow: indexPath.row)
        }
    }
}

extension MapListViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        print("URLs: \(urls)")
        self.moveFiles(urls)
        self.fetchFiles()
        DispatchQueue.main.async { [weak self] in
            self?.listTableView.reloadData()
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print("Dismissed")
    }
}


struct FileItem {
    var name: String
    var path: String
    var modificationDate: Date {
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: path)
            return attr[FileAttributeKey.modificationDate] as? Date ?? Date()
        } catch {
            print(error)
            return Date()
        }
    }
    var storedLocation: CLLocationDictionary?
}

extension CLLocationCoordinate2D {
    static let Lat = "latitude"
    static let Lon = "longitude"
    var asDictionary: CLLocationDictionary {
        return [CLLocationCoordinate2D.Lat: self.latitude, CLLocationCoordinate2D.Lon: self.longitude]
    }
    init(dict: CLLocationDictionary) {
        self.init(latitude: dict[CLLocationCoordinate2D.Lat]!, longitude: dict[CLLocationCoordinate2D.Lon]!)
    }
}

extension Dictionary {
    var toLatLngString: String {
        if let locationDict = self as? CLLocationDictionary,
           let latitude = locationDict[CLLocationCoordinate2D.Lat],
           let longitude = locationDict[CLLocationCoordinate2D.Lon] {
            let finalString = "\(CLLocationCoordinate2D.Lat): \(latitude)\n\(CLLocationCoordinate2D.Lon): \(longitude)"
            return finalString
        }
        return ""
    }
    
    var lat: Double? {
        let locationDict = self as? CLLocationDictionary
        let latitude = locationDict?[CLLocationCoordinate2D.Lat]
        return latitude
    }
    
    var long: Double? {
        let locationDict = self as? CLLocationDictionary
        let longitude = locationDict?[CLLocationCoordinate2D.Lon]
        return longitude
    }
}
