import AWSDynamoDB
import AsyncHTTPClient
import Foundation
import NIOCore
import NIOFoundationCompat
import SmithyHTTPAPI

/// AsyncHTTPClient を利用した HTTPClient 実装
public struct AsyncHTTPClientEngine: SmithyHTTPAPI.HTTPClient {
    private let httpClient: AsyncHTTPClient.HTTPClient

    /// タイムアウトなど、`execute` 実行時の設定を行うためのパラメータ
    private let defaultRequestTimeout: NIODeadline

    /// イニシャライザ
    /// - Parameters:
    ///   - httpClient: `AsyncHTTPClient.HTTPClient` のインスタンス
    ///   - timeoutSeconds: リクエスト1回あたりのデフォルトタイムアウト秒数
    public init(
        httpClient: AsyncHTTPClient.HTTPClient,
        timeoutSeconds: Int = 30
    ) {
        self.httpClient = httpClient
        self.defaultRequestTimeout = NIODeadline.now() + .seconds(Int64(timeoutSeconds))
    }

    /// プロトコル準拠メソッド
    /// `HTTPRequest` を受け取り、実際にリクエストを送信して `HTTPResponse` を生成して返す
    public func send(request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = request.destination.url else {
            throw ClientError.dataNotFound(
                message: "Failed to construct URL from `HTTPRequest.destination`.")
        }

        var clientRequest = HTTPClientRequest(url: url.absoluteString)
        clientRequest.method = .RAW(value: request.method.rawValue)

        for header in request.headers.headers {
            for value in header.value {
                clientRequest.headers.add(name: header.name, value: value)
            }
        }

        if let bodyData = try await request.body.readData() {
            request.body = .data(bodyData)
            clientRequest.body = .bytes(bodyData)
        }

        let clientResponse = try await httpClient.execute(
            clientRequest,
            deadline: defaultRequestTimeout
        )

        let status = clientResponse.status
        guard let statusCode: HTTPStatusCode = .init(rawValue: Int(status.code)) else {
            throw ClientError.invalidStatusCode(code: Int(status.code))
        }

        var responseHeaders = Headers()
        for (name, value) in clientResponse.headers {
            responseHeaders.add(name: name, value: value)
        }

        var buffer = try await clientResponse.body.collect(upTo: 2 << 24)  // 16MB など
        let responseData = buffer.readData(length: buffer.readableBytes) ?? Data()

        let response = HTTPResponse(
            headers: responseHeaders,
            statusCode: statusCode,
            body: .data(responseData),
            reason: status.reasonPhrase
        )
        return response
    }

    public enum ClientError: Sendable, Error {
        case dataNotFound(message: String)
        case invalidStatusCode(code: Int)
    }
}
