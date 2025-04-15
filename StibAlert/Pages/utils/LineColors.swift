//
//  LineColors.swift
//  StibAlert
//
//  Created by studentehb on 15/04/2025.
//
 
import SwiftUI
 
struct LineColors {

     static let colors: [String: String] = [

         // Métros & Trams Structurants

         "3": "#C8D100",

         "4": "#1E40AF",

         "7": "#F5566E",

         "8": "#F09E1B",

         "9": "#5FB04A",
 
        // Trams Classiques

         "19": "#A3B3D1",

         "25": "#8A9FBC",

         "32": "#F187FB",

         "39": "#C2C2C2",

         "44": "#F09E1B",

         "51": "#1E3A8A",

         "55": "#6E90CA",

         "62": "#8DA3D2",

         "81": "#B7C0D9",

         "82": "#1E3A8A",

         "92": "#1E3A8A",

         "93": "#1E3A8A",

         "94": "#1E3A8A",

         "97": "#1E3A8A",
 
        // Bus (extraits de l’image + officiel STIB)

         "12": "#1E3A8A",

         "13": "#ADC2FF",

         "14": "#E4CCFF",

         "17": "#F5566E",

         "20": "#FFD700",

         "21": "#1E3A8A",

         "27": "#9CBFDD",

         "28": "#F65A4E",

         "29": "#F75C0D",

         "33": "#FBA6D6",

         "34": "#F2C230",

         "36": "#377DFF",

         "37": "#AAC4F8",

         "38": "#B9CFF1",

         "41": "#C5D3EF",

         "42": "#5BC97B",

         "43": "#9DA43A",

         "45": "#F084A8",

         "46": "#F65A4E",

         "47": "#F5413C",

         "48": "#FF9031",

         "49": "#2F78D5",

         "50": "#D9C31A",

         "52": "#F2C230",

         "53": "#66C76D",

         "54": "#F04132",

         "56": "#FB7832",

         "58": "#6FAF5A",

         "59": "#5FB04A",

         "60": "#A57D4E",

         "61": "#FFEE33",

         "63": "#3762FF",

         "64": "#FF4C32",

         "65": "#E2C820",

         "66": "#3366CC",

         "69": "#FCBD33",

         "71": "#81BB64",

         "72": "#E9D3F0",

         "73": "#D15E8E",

         "74": "#B7C3E0",

         "75": "#FFD200",

         "76": "#F7E94B",

         "77": "#6FD97B",

         "78": "#B28ACF",

         "79": "#F09E1B",

         "80": "#6AB978",

         "83": "#5A8CF9",

         "86": "#91E2D6",

         "87": "#75C37F",

         "88": "#E7504C",

         "89": "#D5D539",

         "90": "#F187FB",

         "95": "#4263A3"

     ]
 
    static func color(for line: String) -> Color {

         if let hex = colors[line] {

             return Color(hex: hex)

         }

         return Color.gray // Couleur par défaut si non trouvée

     }

 }
