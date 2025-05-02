//
//  halteModelextension.swift
//  StibAlert
//
//  Created by studentehb on 02/05/2025.
//
import Foundation
import CoreLocation

extension HalteModel {
    var locationCoordinate: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
