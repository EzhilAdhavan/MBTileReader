//
//  ViewController.swift
//  MaplySample
//
//  Created by Ezhil Adhavan on 10/12/22.
//

import UIKit
import WhirlyGlobe

class MapViewController: UIViewController, WhirlyGlobeViewControllerDelegate, MaplyViewControllerDelegate {
    
    let isFlat: Bool = true
    private(set) var theViewC: MaplyBaseViewController?
    private(set) var mbTilesFetcher : MaplyMBTileFetcher?
    private(set) var imageLoader : MaplyQuadImageLoader?
    var selectedFileItem: FileItem?
    var selectedLocation: CLLocationCoordinate2D?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = self.selectedFileItem == nil ? "Countries" : self.selectedFileItem!.name
        self.setupMap()
        self.navigationController?.setNavigationBarHidden(false, animated: false)
        self.navigationController?.navigationBar.barTintColor = .white
        self.navigationController?.navigationBar.tintColor = .white
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor : UIColor.white]
        
        let button = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonAction))
        self.navigationItem.rightBarButtonItem = button
    }
    
    deinit {
        mbTilesFetcher?.shutdown()
        imageLoader?.shutdown()
        print("\(self) - deinited")
        theViewC = nil
    }
    
    @objc func cancelButtonAction() {
        self.dismiss(animated: true)
    }

    
    fileprivate func setupMap() {
        if isFlat {
            theViewC = MaplyViewController()
            theViewC!.clearColor = .white
        } else {
            theViewC = WhirlyGlobeViewController()
            theViewC!.clearColor = .black
        }
        
        self.view.addSubview(theViewC!.view)
        theViewC!.view.frame = self.view.bounds
        addChild(theViewC!)
        
        //theViewC!.frameInterval = 2
        mbTilesFetcher = MaplyMBTileFetcher(mbTiles: selectedFileItem == nil ? "countries" : selectedFileItem?.name ?? "")
        
        let samplingParams = MaplySamplingParams()
        samplingParams.coordSys = mbTilesFetcher!.coordSys()
        samplingParams.coverPoles = false
        samplingParams.edgeMatching = false
        samplingParams.minZoom = mbTilesFetcher!.minZoom()
        samplingParams.maxZoom = mbTilesFetcher!.maxZoom()
        samplingParams.singleLevel = true
        if mbTilesFetcher?.format == "pbf" {
            let alert = UIAlertController(title: "Not supported", message: "pbf, not supoorted.", preferredStyle: .alert)
            
            self.present(alert, animated: true)
            return
        } else {
            samplingParams.minImportance = 512*512
            imageLoader = MaplyQuadImageLoader(params: samplingParams,
                                               tileInfo: mbTilesFetcher!.tileInfo(),
                                               viewC: theViewC!)
            imageLoader!.setTileFetcher(mbTilesFetcher!)
            imageLoader!.baseDrawPriority = Constants.MapLayerPriority.baseMapDrawPriority
        }
        // 77.253749, 10.575718 - UDT
        // -85.9189498, 37.7088262, ekpc
        // -83.910534, 34.319422, Spring Dale
        // -83.9157023424918 34.31748303740376
        
        self.setupMapSettings()
    }
    
    func setupMapSettings() {
        let deg = MaplyCoordinateMakeWithDegrees(Float(self.selectedLocation?.longitude ?? 0.0), Float(self.selectedLocation?.latitude ?? 0.0))
        if let globeVC = theViewC as? WhirlyGlobeViewController {
            globeVC.height = 0.05
            globeVC.animate(toPosition: deg, time: 1.0)
            globeVC.pinchGesture = true
            globeVC.delegate = self
        } else if let mapVC = theViewC as? MaplyViewController {
            mapVC.height = 0.05
            mapVC.animate(toPosition: deg, time: 1.0)
            mapVC.pinchGesture = true
            mapVC.delegate = self
        }
        self.setupMarker(theViewC, location: deg)
    }
    
    func setupMarker(_ mapVC: MaplyBaseViewController?, location: MaplyCoordinate) {
        // Show location marker only if user selected some mbtiles not for default map(countries)
        guard let _ = selectedFileItem else { return }
        let annotation = MaplyScreenMarker()
        annotation.loc = location
        annotation.size = Constants.MapMarker.defaultMarkerSize
        annotation.offset = Constants.MapMarker.defaultMarkerOffset
        annotation.image = Constants.MapMarker.defaultMarkerImage
        annotation.layoutImportance = Float.infinity
        _ = mapVC?.addScreenMarkers([annotation],
                                   desc: [kMaplyDrawPriority: Constants.MapLayerPriority.screenMarkerDrawPriority])
        print("Marker at: \(location)")
    }
}

struct Constants {
    struct MapMarker {
        static let defaultMarkerSize = CGSize(width: 27, height: 34)
        static let defaultMarkerOffset = CGPoint(x: 0, y: 17)
        static let defaultMarkerImage = UIImage(named: "blue_marker")!
    }
    
    struct MapLayerPriority {
        static let baseMapDrawPriority: Int32 = kMaplyImageLayerDrawPriorityDefault
        static let screenMarkerDrawPriority: Int32 = kMaplyImageLayerDrawPriorityDefault+3000
    }
}


