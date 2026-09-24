    //
    //  DataTypes+Extensions.swift
    //  
    //
    //  Created by Apurva   on 27/08/24.
    //

import Foundation



extension Date {
    var date: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd"
        return dateFormatter.string(from: self)
    }
}

