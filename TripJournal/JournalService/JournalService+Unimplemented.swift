import Combine
import Foundation

/// An unimplemented version of the `JournalService`.
class JournalServiceLive: JournalService {
    
    private let urlSession: URLSession
    
    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 60.0
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        self.urlSession = URLSession(configuration: configuration)
    }
    
    @Published private var token: Token? {
        didSet {
            if let token = token {
                try? KeychainHelper.shared.saveToken(token)
            }else{
                try? KeychainHelper.shared.deleteToken()
            }
        }
    }
    
    enum EndPoints {
        static let base = "http://localhost:8000/"
        
        case register
        case login
        case trips
        case handleTrip(String)
        case events
        case handleEvent(String)
        case medias
        case mediasUploaded
        case handleMedia(String)
        
        private var stringValue: String {
            switch self {
            case .register:
                return EndPoints.base + "register"
            case .login:
                return EndPoints.base + "token"
            case .trips:
                return EndPoints.base + "trips"
            case .handleTrip(let tripId):
                return EndPoints.base + "trips/\(tripId)"
            case .events:
                return EndPoints.base + "events"
            case .handleEvent(let eventId):
                return EndPoints.base + "events/\(eventId)"
            case .medias:
                return EndPoints.base + "medias"
            case .mediasUploaded:
                return EndPoints.base + "mediasUploaded"
            case .handleMedia(let mediaId):
                return EndPoints.base + "medias/\(mediaId)"
                
            }
        }
        
        var url: URL {
            return URL(string: stringValue)!
        }
    }
}


// MARK: - Authentication Methods

extension JournalServiceLive {
    var isAuthenticated: AnyPublisher<Bool, Never> {
        $token
            .map { $0 != nil }
            .eraseToAnyPublisher()
    }

    func register(username: String, password: String) async throws -> Token {
        let request = try createRegisterRequest(username: username, password: password)
        var token = try await performNetworkRequest(request, responseType: Token.self)
        token.expirationDate = Token.defaultExpirationDate()
        self.token = token
        return token
    }

    func logOut() {
        token = nil
    }

    func logIn(username: String, password: String) async throws -> Token {
        let request = try createLoginRequest(username: username, password: password)
        var token = try await performNetworkRequest(request, responseType: Token.self)
        token.expirationDate = Token.defaultExpirationDate()
        self.token = token
        return token
    }
}

// MARK: - Trip Methods

extension JournalServiceLive {
    func createTrip(with request: TripCreate) async throws -> Trip {
        guard let token = token else {
            throw NetworkError.invalidValue
        }

        var requestURL = URLRequest(url: EndPoints.trips.url)
        requestURL.httpMethod = HTTPMethods.POST.rawValue
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.contentType.rawValue)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let tripData: [String: Any] = [
            "name": request.name,
            "start_date": dateFormatter.string(from: request.startDate),
            "end_date": dateFormatter.string(from: request.endDate)
        ]
        requestURL.httpBody = try JSONSerialization.data(withJSONObject: tripData)

        return try await performNetworkRequest(requestURL, responseType: Trip.self)
    }
    
    func getTrips() async throws -> [Trip] {
        guard let token = token else {
            throw NetworkError.invalidValue
        }
        
        var requestURL = URLRequest(url: EndPoints.trips.url)
        requestURL.httpMethod = HTTPMethods.GET.rawValue
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)
        
        do {
            let trips = try await performNetworkRequest(requestURL, responseType: [Trip].self)
            //TODO: - cache manager save trips
            return trips
        } catch {
            print("Fetching trips failed, loading from UserDefaults")
            return [] // TODO: - cache manager load trips
        }
    }
    
    func getTrip(withId tripId: Trip.ID) async throws -> Trip {
        guard let token = token else {
            throw NetworkError.invalidValue
        }
        
        var requestURL = URLRequest(url: EndPoints.handleTrip(tripId.description).url)
        requestURL.httpMethod = HTTPMethods.GET.rawValue
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)
        
        do {
            let trip = try await performNetworkRequest(requestURL, responseType: Trip.self)
            return trip
        } catch {
            throw NetworkError.badResponse
        }
    }

    func updateTrip(withId tripId: Trip.ID, and tripUpdate: TripUpdate) async throws -> Trip {
        guard let token = token else {
            throw NetworkError.invalidValue
        }
        
        var requestURL = URLRequest(url: EndPoints.handleTrip(tripId.description).url)
        requestURL.httpMethod = HTTPMethods.PUT.rawValue
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)
        requestURL.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.contentType.rawValue)
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let tripData: [String: Any] = [
            "name": tripUpdate.name,
            "start_date": dateFormatter.string(from: tripUpdate.startDate),
            "end_date": dateFormatter.string(from: tripUpdate.endDate)
        ]
        requestURL.httpBody = try JSONSerialization.data(withJSONObject: tripData)
        
        return try await performNetworkRequest(requestURL, responseType: Trip.self)
    }
    
    func deleteTrip(withId tripId: Trip.ID) async throws {
        guard let token = token else {
            throw NetworkError.invalidValue
        }
        let url = EndPoints.handleTrip(tripId.description).url
        var requestURL = URLRequest(url: url)
        requestURL.httpMethod = HTTPMethods.DELETE.rawValue
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)
        
        try await performVoidNetworkRequest(requestURL)
    }
}

// MARK: - Network Request Helpers

extension JournalServiceLive {
    private func createRegisterRequest(username: String, password: String) throws -> URLRequest {
        var request = URLRequest(url: EndPoints.register.url)
        request.httpMethod = HTTPMethods.POST.rawValue
        request.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        request.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.contentType.rawValue)
        
        let registerData = LoginRequest(username: username, password: password)
        request.httpBody = try JSONEncoder().encode(registerData)
                
        return request
    }
    
    private func createLoginRequest(username: String, password: String) throws -> URLRequest {
        var request = URLRequest(url: EndPoints.login.url)
        request.httpMethod = HTTPMethods.POST.rawValue
        request.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        request.addValue(MIMEType.form.rawValue, forHTTPHeaderField: HTTPHeaders.contentType.rawValue)
        
        let loginData = "grant_type=&username=\(username)&password=\(password)"
        request.httpBody = loginData.data(using: .utf8)
        
        return request
    }
    
    private func performNetworkRequest<T: Codable>(_ request: URLRequest, responseType: T.Type) async throws -> T {
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.badResponse
            }

            if httpResponse.statusCode == 422 {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    print("Error: \(errorMessage)")
                }
                throw NetworkError.unprocessableEntity
            }

            guard httpResponse.statusCode == 200 else {
                throw NetworkError.badResponse
            }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let object = try decoder.decode(T.self, from: data)
            return object
        } catch {
            throw NetworkError.failedToDecodeResponse
        }
    }
    
    private func performVoidNetworkRequest(_ request: URLRequest) async throws {
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 204 else {
            throw NetworkError.badResponse
        }
    }
}

// MARK: - Event Methods

extension JournalServiceLive {
    func createEvent(with eventCreate: EventCreate) async throws -> Event {
        guard let token = token else {
            throw NetworkError.invalidValue
        }
        var requestUrl = URLRequest(url: EndPoints.events.url)
        requestUrl.httpMethod = HTTPMethods.POST.rawValue
        requestUrl.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestUrl.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)
        requestUrl.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.contentType.rawValue)
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let location: [String: Any] = [
            "latitude": eventCreate.location?.latitude ?? 0.0,
            "longitude": eventCreate.location?.longitude ?? 0.0,
            "address": eventCreate.location?.address ?? ""
        ]
        
        let eventData: [String: Any] = [
            "trip_id": eventCreate.tripId.description,
            "name": eventCreate.name,
            "note": eventCreate.note ?? "",
            "date": dateFormatter.string(from: eventCreate.date),
            "location": location,
            "transition_from_previous": eventCreate.transitionFromPrevious ?? ""
        ]
        requestUrl.httpBody = try JSONSerialization.data(withJSONObject: eventData)

        return try await performNetworkRequest(requestUrl, responseType: Event.self)
    }

    func updateEvent(withId eventId: Event.ID, and eventUpdate: EventUpdate) async throws -> Event {
        guard let token = token else {
            throw NetworkError.invalidValue
        }
        
        var requestUrl = URLRequest(url: EndPoints.handleEvent(eventId.description).url)
        requestUrl.httpMethod = HTTPMethods.PUT.rawValue
        requestUrl.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestUrl.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)
        requestUrl.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.contentType.rawValue)
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let location: [String: Any] = [
            "latitude": eventUpdate.location?.latitude ?? 0.0,
            "longitude": eventUpdate.location?.longitude ?? 0.0,
            "address": eventUpdate.location?.address ?? ""
        ]
        
        let eventData: [String: Any] = [
            "name": eventUpdate.name,
            "note": eventUpdate.note ?? "",
            "date": dateFormatter.string(from: eventUpdate.date),
            "location": location,
            "transition_from_previous": eventUpdate.transitionFromPrevious ?? ""
        ]
        requestUrl.httpBody = try JSONSerialization.data(withJSONObject: eventData)
        
        return try await performNetworkRequest(requestUrl, responseType: Event.self)
    }

    func deleteEvent(withId eventId: Event.ID) async throws {
        guard let token = token else {
            throw NetworkError.invalidValue
        }
        
        let url = EndPoints.handleEvent(eventId.description).url
        var requestURL = URLRequest(url: url)
        requestURL.httpMethod = HTTPMethods.DELETE.rawValue
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)
        
        try await performVoidNetworkRequest(requestURL)
    }

    func createMedia(with mediaCreate: MediaCreate) async throws -> Media {
        guard let token = token else {
            throw NetworkError.invalidValue
        }
        let mediaUrl = try await uploadImageAndGetUrl(imageData: mediaCreate.base64Data)
        
        print(mediaUrl)

        var requestUrl = URLRequest(url: EndPoints.medias.url)
        requestUrl.httpMethod = HTTPMethods.POST.rawValue
        requestUrl.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.accept.rawValue)
        requestUrl.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)
        requestUrl.addValue(MIMEType.JSON.rawValue, forHTTPHeaderField: HTTPHeaders.contentType.rawValue)

        let mediaData: [String: Any] = [
            "event_id": mediaCreate.eventId,
            "url": mediaUrl.absoluteString
        ]

        requestUrl.httpBody = try JSONSerialization.data(withJSONObject: mediaData)
        
        return try await performNetworkRequest(requestUrl, responseType: Media.self)
    }


    func uploadImageAndGetUrl(imageData: Data) async throws -> URL {
        guard let token = token else {
            throw NetworkError.invalidValue
        }

        var uploadRequest = URLRequest(url: EndPoints.medias.url)
        uploadRequest.httpMethod = HTTPMethods.POST.rawValue
        uploadRequest.addValue(MIMEType.multipartFromData.rawValue, forHTTPHeaderField: HTTPHeaders.contentType.rawValue)
        uploadRequest.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)

        let (data, response) = try await urlSession.upload(for: uploadRequest, from: imageData)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NetworkError.badResponse
        }

        let decoder = JSONDecoder()
        let uploadResponse = try decoder.decode(UploadResponse.self, from: data)
        
        guard let uploadedUrl = uploadResponse.url else {
            throw NetworkError.badResponse
        }

        return uploadedUrl
    }


    
    func deleteMedia(withId mediaId: Media.ID) async throws {
        guard let token = token else {
            throw NetworkError.invalidValue
        }
        
        let url = EndPoints.handleMedia(mediaId.description).url
        var requestURL = URLRequest(url: url)
        requestURL.httpMethod = HTTPMethods.DELETE.rawValue
        requestURL.addValue("Bearer \(token.accessToken)", forHTTPHeaderField: HTTPHeaders.authorization.rawValue)
        
        try await performVoidNetworkRequest(requestURL)
    }
}



extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
