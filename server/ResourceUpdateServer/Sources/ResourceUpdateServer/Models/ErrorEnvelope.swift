import Vapor

struct ErrorEnvelope: Content {
    let error: ErrorDetails
}

struct ErrorDetails: Content {
    let code: String
    let message: String
    let requestId: String
}
