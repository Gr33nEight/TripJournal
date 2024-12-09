//
//  NetworkEnums.swift
//  TripJournal
//
//  Created by Natanael Jop on 07/12/2024.
//

import Foundation

enum HTTPMethods: String {
    case POST, GET, PUT, DELETE
}

enum MIMEType: String {
    case JSON = "application/json"
    case form = "application/x-www-form-urlencoded"
    case multipartFromData = "multipart/form-data"
}

enum HTTPHeaders: String {
    case accept
    case contentType = "Content-Type"
    case authorization = "Authorization"
}

enum NetworkError: Error {
    case badUrl
    case badResponse
    case failedToDecodeResponse
    case invalidValue
    case unprocessableEntity
}

enum SessionError: Error {
    case expired
}
