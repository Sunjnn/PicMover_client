//
//  ServerDetailView.swift
//  PicMover_client
//
//  Created by sunjnn on 2025/11/25.
//

import Photos
import SwiftUI

enum ClientStatus {
    case INIT
    case CONNECTING
    case UPLOADING
    case DONE
    case ERROR
}

struct ServerDetailView: View {
    var body: some View {
        VStack {
            Text("Server Name: \(_meta.name)")
                .font(.headline)
                .padding()
            
            Text("IP Address: \(_meta.host)")
                .font(.headline)
                .padding()
            
            Text("Port: \(String(PORT))")
                .font(.headline)
                .padding()
            
            if FailedPhotoManager.shared.count() > 0 {
                Toggle("Backup failed photos", isOn: $_isBackupFailedPhotos).padding()
            }
            
            Spacer()
            
            Text(_statusDescription)
                .padding()
            
            Button(action: {
                backup()
            }) {
                HStack {
                    if _status == ClientStatus.CONNECTING
                        || _status == ClientStatus.UPLOADING
                    {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding(.trailing, 6)
                    }
                    Text(
                        _status == ClientStatus.INIT
                            ? "Start backup"
                            : _status == ClientStatus.CONNECTING
                                ? "Connecting server"
                                : _status == ClientStatus.UPLOADING
                                    ? "Uploading pictures"
                                    : _status == ClientStatus.DONE
                                        ? "Backup done" : "ERROR"
                    )
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    (_status == ClientStatus.INIT) ? Color.blue : Color.gray
                )
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(
                _status == ClientStatus.CONNECTING
                    || _status == ClientStatus.UPLOADING
                    || _status == ClientStatus.DONE
                    || _status == ClientStatus.ERROR
            )
            .padding()
        }
        .navigationTitle("Server Details")
    }
    
    @State private var _status: ClientStatus = ClientStatus.INIT
    @State private var _statusDescription: String = ""
    @State private var _isBackupFailedPhotos: Bool = false
    
    private var _meta: ServerMeta
    
    init(meta: ServerMeta) {
        _meta = meta
    }
    
    func backup() {
        Task {
            guard let connectId = await connect_server() else {
                return;
            }
            
            var photos: [PHAsset] = []
            if _isBackupFailedPhotos {
                let identifiers = FailedPhotoManager.shared.getAllIdentifiers()
                photos = get_photos(identifiers: identifiers)
            }
            else {
                photos = get_photos()
            }
            
            await upload_photos(connectId: connectId, assets: photos)
            
            if _status != ClientStatus.ERROR {
                DispatchQueue.main.async {
                    _statusDescription = "Backup success"
                    _status = ClientStatus.DONE
                }
            }
        }
    }
    
    func connect_server() async -> Int? {
        DispatchQueue.main.async {
            _statusDescription = "Connecting server..."
            _status = ClientStatus.CONNECTING
        }
        
        let jsonData = try? JSONSerialization.data(
            withJSONObject: ["ClientName": "hanhan"],
            options: []
        )
        
        let url = URL(string: "http://\(_meta.host):\(PORT)/connect")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        
        guard let (data, response) = await send_http_request(request: request) else {
            return nil
        }
        
        guard let dict = handle_http_response(data: data, response: response, error: nil) as [String: Any]? else {
            return nil
        }
        
        guard let connectId = dict["ConnectId"] as? Int else {
            DispatchQueue.main.async {
                _statusDescription =
                    "Return json has no key 'TaskId': \(dict)"
                _status = ClientStatus.ERROR
            }
            return nil
        }
        
        await wait_server_approved(connectId: connectId)
        
        if _status == ClientStatus.ERROR {
            return nil
        }
        return connectId
    }
    
    func wait_server_approved(connectId: Int) async {
        DispatchQueue.main.async {
            _statusDescription = "Waiting for server approved"
        }
        
        await interval_repeats(interval: 2.0) {
            let url = URL(
                string:
                    "http://\(_meta.host):\(PORT)/status?ConnectId=\(connectId)"
            )!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            
            guard let (data, response) = await send_http_request(request: request) else {
                return true
            }
            
            guard let dict = handle_http_response(data: data, response: response, error: nil) else {
                return true
            }
            
            guard let isApproved = dict["Approved"] as? Bool else {
                DispatchQueue.main.async {
                    _statusDescription =
                        "Return json has no key 'Status' in \(dict)"
                    _status = ClientStatus.ERROR
                }
                return true
            }
            
            return isApproved
        }
    }
    
    func get_photos() -> [PHAsset] {
        DispatchQueue.main.async {
            _statusDescription = "Fetching photos..."
        }
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: true)
        ]
        
        let fetchResult = PHAsset.fetchAssets(
            with: .image,
            options: fetchOptions
        )
        
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        return assets
    }
    
    func get_photos(identifiers: [String]) -> [PHAsset] {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }
    
    func upload_photos(connectId: Int, assets: [PHAsset]) async {
        DispatchQueue.main.async {
            _statusDescription = "Uploading photos..."
            _status = ClientStatus.UPLOADING
        }
        
        let batchSize = 100
        let totalSize = assets.count
        
        var assetIndex = 0
        var batchAssets: [PHAsset] = []
        while assetIndex < totalSize {
            let batchStart = assetIndex
            let batchEnd = min(
                batchStart + batchSize,
                totalSize
            )
            
            assetIndex += batchSize
            batchAssets = Array(assets[batchStart..<batchEnd])
            
            DispatchQueue.main.async {
                _statusDescription = "Uploading photos from \(batchStart) to \(batchEnd)"
            }
            
            guard let taskId = await upload_batch(assets: batchAssets, connectId: connectId) else {
                return
            }
            await interval_repeats(interval: 2.0) {
                let url = URL(
                    string: "http://\(_meta.host):\(PORT)/status?TaskId=\(taskId)"
                )!
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                
                guard let (data, response) = await send_http_request(request: request) else {
                    return true
                }
                
                guard let dict = handle_http_response(data: data, response: response, error: nil) else {
                    return true
                }
                
                guard let status = dict["Status"] as? String else {
                    DispatchQueue.main.async {
                        _statusDescription = "Return json has no key 'status' in \(dict)"
                        _status = ClientStatus.ERROR
                    }
                    return true
                }
                
                if status != "Finished" {
                    return false
                }
                
                guard let result = dict["Result"] as? [Int] else {
                    return true
                }

                for index in result {
                    FailedPhotoManager.shared.add(localIdentifier: assets[index].localIdentifier)
                }
                return true
            }
            if _status == ClientStatus.ERROR {
                return
            }
        }
    }
    
    func upload_batch(assets: [PHAsset], connectId: Int) async -> Int? {
        let manager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = true
        requestOptions.deliveryMode = .highQualityFormat
        
        var photosData: [[String: String]] = []
        
        for asset in assets {
            let resource = PHAssetResource.assetResources(for: asset)
            guard let resource = resource.first else {
                FailedPhotoManager.shared.add(localIdentifier: asset.localIdentifier)
                continue
            }
            let fileName: String = resource.originalFilename
            
            let typeString: String = "image"
            
            var creationDateString: String = "unknow_date"
            if let creationDate = asset.creationDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd_HHmmss"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone.current
                creationDateString = formatter.string(from: creationDate)
            }
            
            manager.requestImageDataAndOrientation(
                for: asset,
                options: requestOptions
            ) { data, _, _, _ in
                if let imageData = data {
                    let dataBase64: String = imageData.base64EncodedString()
                    
                    photosData.append([
                        "FileName": fileName,
                        "MediaType": typeString,
                        "CreationDate": creationDateString,
                        "Content": dataBase64,
                    ])
                } else {
                    FailedPhotoManager.shared.add(localIdentifier: asset.localIdentifier)
                }
            }
        }
        
        let url = URL(string: "http://\(_meta.host):\(PORT)/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        
        let requestJson: [String: Any] = [
            "ConnectId": connectId,
            "Data": photosData,
        ]
        let jsonData = try? JSONSerialization.data(withJSONObject: requestJson)
        request.httpBody = jsonData
        
        guard let (data, response) = await send_http_request(request: request) else {
            return nil
        }
        
        guard let dict = handle_http_response(data: data, response: response, error: nil) else {
            return nil
        }
        
        guard let taskId = dict["TaskId"] as? Int else {
            DispatchQueue.main.async {
                _statusDescription =
                    "Return json has no key 'TaskId': \(dict)"
                _status = ClientStatus.ERROR
            }
            return nil
        }
        return taskId
    }
    
    func interval_repeats(interval: TimeInterval, completion: @escaping() async -> Bool) async {
        while true {
            if await completion() {
                break
            }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }
    
    func send_http_request(request: URLRequest) async -> (Data, URLResponse)? {
        do {
            return try await URLSession.shared.data(for: request)
        }
        catch {
            DispatchQueue.main.async {
                _statusDescription = "Send http request failed: \(request)"
                _status = ClientStatus.ERROR
            }
        }
        return nil
    }
    
    func handle_http_response(data: Data?, response:  URLResponse?, error: (any Error)?) -> [String: Any]? {
        if let error = error {
            DispatchQueue.main.async {
                _statusDescription =
                    "Connect server failed：\(error.localizedDescription)"
                _status = ClientStatus.ERROR
            }
            return nil
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            DispatchQueue.main.async {
                _statusDescription = "Connect server failed, response is not HTTPURLResponse"
                _status = ClientStatus.ERROR
            }
            return nil
        }

        if httpResponse.statusCode != 200 {
            DispatchQueue.main.async {
                _statusDescription = "Server send error, code: \(httpResponse.statusCode)"
                if let data = data {
                    _statusDescription += ", \(data)"
                }
                _status = ClientStatus.ERROR
            }
            return nil
        }

        guard let data = data else {
            DispatchQueue.main.async {
                _statusDescription = "No data from server"
                _status = ClientStatus.ERROR
            }
            return nil
        }

        var jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            DispatchQueue.main.async {
                _statusDescription = "Return data is not json: \(data)"
                _status = ClientStatus.ERROR
            }
            return nil
        }

        guard let dict = jsonObject as? [String: Any] else {
            DispatchQueue.main.async {
                _statusDescription =
                    "Return data format error, need to be [String: Any]: \(jsonObject)"
                _status = ClientStatus.ERROR
            }
            return nil
        }
        
        return dict
    }
}
